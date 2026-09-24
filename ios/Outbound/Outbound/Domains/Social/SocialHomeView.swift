import CryptoKit
import MapKit
import SwiftUI
import UIKit

struct SocialHomeView: View {
    private static let feedPageSize = 12

    @Environment(\.analyticsManager) private var analyticsManager
    @EnvironmentObject private var socialStore: TogetherStore
    @EnvironmentObject private var circleStore: CircleStore
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    @EnvironmentObject private var recognitionStore: RecognitionStore
    @EnvironmentObject private var socialRecognitionStore: SocialRecognitionStore
    @EnvironmentObject private var activityStore: ActivityStore
    @EnvironmentObject private var pushNotifications: PushNotificationCoordinator
    @EnvironmentObject private var healthImportStore: HealthImportStore
    @State private var selectedCommentPost: TogetherPostDTO?
    @State private var selectedActivityPost: TogetherPostDTO?
    @State private var selectedCheersPost: TogetherPostDTO?
    @State private var selectedFeatureTab: SocialFeatureTab = .feed
    @State private var hasInitializedFeatureTab = false
    @State private var hasInteractedWithFeatureTabs = false
    @State private var exposedBadgeSignatures: Set<String> = []
    @State private var peopleFocusRequestID = 0
    @State private var routeImportRequestID = 0
    @State private var isCreateActivityEventPresented = false
    @State private var isGroupCreationPresented = false
    @State private var showsNotifications = false
    @State private var showsConnections = false
    @State private var showsAddConnection = false
    @State private var pushedLiveCheerSessionID: String?
    @State private var toastMessage: String?
    @State private var postPendingReport: TogetherPostDTO?
    @State private var postPendingBlock: TogetherPostDTO?
    @State private var postPendingDeletion: TogetherPostDTO?
    @State private var hasTrackedActiveNowExposure = false
    @State private var hasTrackedUpcomingExposure = false
    @State private var hasTrackedFirstFeedCard = false
    @AppStorage("social.skipPostDeletionConfirmation") private var skipsPostDeletionConfirmation = false
    @StateObject private var liveCheerStore = LiveCheerStore()

    private var shouldShowConnectionPrompt: Bool {
        socialStore.hasLoadedConnections
            && acceptedConnections.isEmpty
    }

    private var acceptedConnections: [SocialConnectionDTO] {
        socialStore.connections
            .filter { $0.status == "accepted" }
            .sorted(by: SocialConnectionDTO.previewOrder)
    }

    private var activeConnections: [SocialConnectionDTO] {
        acceptedConnections.filter { $0.isInActiveWorkout == true }
    }

    private var incomingConnectionRequestCount: Int {
        socialStore.connections.filter { $0.status == "pending" && $0.direction == "incoming" }.count
    }

    private var tabBadges: [SocialFeatureTab: SocialTabBadge] {
        var badges: [SocialFeatureTab: SocialTabBadge] = [:]
        if socialStore.hasUnseenFeedPosts { badges[.feed] = .dot }
        if incomingConnectionRequestCount > 0 { badges[.people] = .count(incomingConnectionRequestCount) }
        if !circleStore.invitations.isEmpty { badges[.groups] = .count(circleStore.invitations.count) }
        return badges
    }

    private var syncedActivityIDs: [String] {
        activityStore.activities.compactMap(\.sync?.serverActivityId).sorted()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SocialFeatureTabBar(
                    selection: selectedFeatureTab,
                    badges: tabBadges,
                    onSelect: { selectFeatureTab($0) }
                )
                socialTabContent
            }
            .background(OutboundPalette.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    GlobalConditionsButton()

                    Menu {
                        Button {
                            isCreateActivityEventPresented = true
                            trackUpcomingInteraction("plan")
                        } label: {
                            Label(String(localized: "social.create.plan", defaultValue: "Plan an activity"), systemImage: "calendar.badge.plus")
                        }

                        Button {
                            selectFeatureTab(.people, entrySource: "create_menu")
                            peopleFocusRequestID += 1
                        } label: {
                            Label(String(localized: "social.create.person", defaultValue: "Add connection"), systemImage: "person.badge.plus")
                        }

                        Button {
                            selectFeatureTab(.groups, entrySource: "create_menu")
                            isGroupCreationPresented = true
                        } label: {
                            Label {
                                Text(String(localized: "social.create.group", defaultValue: "Create Group"))
                            } icon: {
                                CircleMark()
                                    .frame(width: 18, height: 18)
                            }
                        }

                        Button {
                            selectFeatureTab(.routes, entrySource: "create_menu")
                            routeImportRequestID += 1
                        } label: {
                            Label(String(localized: "social.create.route", defaultValue: "Import a route"), systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .accessibilityLabel(String(localized: "social.create.menu", defaultValue: "Create or add"))

                    Button {
                        showsNotifications = true
                        trackSocialInboxOpened(entrySource: "social")
                    } label: {
                        NotificationCenterIcon(count: notificationCenterBadgeCount)
                    }
                    .accessibilityLabel(String(localized: "app.notifications.destination", defaultValue: "Notification Center"))
                    .accessibilityValue(notificationCenterAccessibilityValue(count: notificationCenterBadgeCount))
                }
            }
            .task {
                async let liveCheers: Void = liveCheerStore.refreshSessions()
                async let connectionsRefresh: Void = socialStore.refreshConnections()
                async let notificationsRefresh: Void = socialStore.refreshNotifications()
                async let circleRefresh: Void = circleStore.refresh()
                async let circleInvitations: Void = circleStore.refreshInvitations()
                _ = await (connectionsRefresh, notificationsRefresh, circleRefresh, circleInvitations, liveCheers)
            }
            .onChange(of: socialStore.hasLoadedConnections, initial: true) { _, loaded in
                guard loaded else { return }
                initializeFeatureTabIfNeeded()
            }
            .onChange(of: selectedFeatureTab) { _, tab in
                guard tab == .feed else { return }
                trackFeedModuleExposuresIfNeeded()
            }
            .onChange(of: badgeAnalyticsSignature, initial: true) { _, _ in
                trackNewBadgeExposures()
            }
            .onChange(of: circleStore.errorMessage) { _, message in
                guard let message else { return }
                toastMessage = message
                Task { await analyticsManager?.track(.init(.circleOperationFailed, properties: [.sourceType: .string("social_home"), .errorCategory: .string("api_unavailable")])) }
            }
            .onChange(of: circleStore.toastMessage) { _, message in
                guard let message else { return }
                toastMessage = message
                circleStore.clearToast()
            }
            .onChange(of: socialStore.errorMessage) { _, message in
                guard message != nil else { return }
                toastMessage = String(
                    localized: "social.error.refresh",
                    defaultValue: "Social couldn’t fully refresh. Pull down to try again."
                )
                Task {
                    await analyticsManager?.track(.init(.socialOperationFailed, properties: [
                        .sourceType: .string("social_home"),
                        .errorCategory: .string("api_unavailable"),
                    ]))
                }
            }
            .task(id: syncedActivityIDs) {
                await socialStore.refresh()
            }
            .navigationDestination(isPresented: $showsNotifications) {
                SocialNotificationsView()
            }
            .navigationDestination(isPresented: $showsConnections) {
                SocialConnectionsView()
            }
            .navigationDestination(isPresented: $showsAddConnection) {
                SocialConnectionsView(startsAdding: true)
            }
            .navigationDestination(isPresented: $isGroupCreationPresented) {
                CircleCreateView()
            }
            .navigationDestination(item: $pushedLiveCheerSessionID) { sessionID in
                LiveCheerView(sessionID: sessionID, entrySource: "push")
            }
            .modifier(SocialActivityCardNavigation(post: $selectedActivityPost))
            .onChange(of: pushNotifications.pendingNotificationID, initial: true) { _, notificationID in
                guard notificationID != nil else { return }
                if pushNotifications.pendingNotificationType == "liveCheerInvitation",
                   let sessionID = pushNotifications.pendingObjectID,
                   !sessionID.isEmpty {
                    pushedLiveCheerSessionID = sessionID
                    trackPushOpen(type: "live_cheer_invitation", destination: "live_cheer")
                    pushNotifications.consumePendingNotification()
                } else if pushNotifications.pendingNotificationType == "connectionRequest" {
                    selectFeatureTab(.people, entrySource: "push")
                    trackPushOpen(type: "connection_request", destination: "people")
                    pushNotifications.consumePendingNotification()
                } else {
                    showsNotifications = true
                    trackPushOpen(type: pushNotifications.pendingNotificationType ?? "unknown", destination: "notifications")
                }
            }
            .overlay(alignment: .top) {
                if let toastMessage {
                    Label(toastMessage, systemImage: "exclamationmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: toastMessage)
            .task(id: toastMessage) {
                guard toastMessage != nil else { return }
                try? await Task.sleep(for: .seconds(2.2))
                guard !Task.isCancelled else { return }
                toastMessage = nil
            }
            .task(id: socialStore.state.posts.map(\.id)) {
                reconcileSharedActivityMilestones()
                trackActivityFeedLoaded()
            }
            .sheet(item: $selectedCommentPost) { post in
                SocialCommentsView(post: post)
            }
            .sheet(item: $selectedCheersPost) { post in
                SocialCheersListView(post: post)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isCreateActivityEventPresented) {
                CreateActivityEventView()
                    .environmentObject(socialStore)
            }
            .confirmationDialog(
                String(localized: "social.report.reason.title", defaultValue: "Why are you reporting this post?"),
                isPresented: Binding(
                    get: { postPendingReport != nil },
                    set: { if !$0 { postPendingReport = nil } }
                ),
                titleVisibility: .visible
            ) {
                ForEach(SocialPostReportReason.allCases) { reason in
                    Button(reason.localizedLabel, role: .destructive) {
                        guard let post = postPendingReport else { return }
                        postPendingReport = nil
                        Task { await socialStore.reportPost(post, reason: reason.rawValue) }
                    }
                }
                Button(String(localized: "Cancel"), role: .cancel) { postPendingReport = nil }
            } message: {
                Text(String(localized: "social.report.confirmation", defaultValue: "Select a reason to confirm your private report."))
            }
            .alert(
                String(localized: "social.block.confirmation.title", defaultValue: "Block this person?"),
                isPresented: Binding(
                    get: { postPendingBlock != nil },
                    set: { if !$0 { postPendingBlock = nil } }
                )
            ) {
                Button(String(localized: "social.block", defaultValue: "Block person"), role: .destructive) {
                    guard let post = postPendingBlock else { return }
                    postPendingBlock = nil
                    Task { await socialStore.blockAuthor(of: post) }
                }
                Button(String(localized: "Cancel"), role: .cancel) { postPendingBlock = nil }
            } message: {
                Text(String(localized: "social.block.confirmation.message", defaultValue: "Blocking removes the connection and hides each person’s content."))
            }
            .confirmationDialog(
                String(localized: "social.delete.post.confirmation.title", defaultValue: "Delete this post?"),
                isPresented: Binding(
                    get: { postPendingDeletion != nil },
                    set: { if !$0 { postPendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(String(localized: "Delete post"), role: .destructive) {
                    deletePendingPost(skipFutureConfirmations: false)
                }
                Button(String(localized: "social.delete.post.dont.ask.again", defaultValue: "Delete and don’t ask again"), role: .destructive) {
                    deletePendingPost(skipFutureConfirmations: true)
                }
                Button(String(localized: "Cancel"), role: .cancel) { postPendingDeletion = nil }
            } message: {
                Text(String(localized: "social.delete.post.confirmation.message", defaultValue: "This removes the post from Social. Your saved activity is not deleted."))
            }
        }
    }

    private var badgeAnalyticsSignature: String {
        SocialFeatureTab.allCases.compactMap { tab in
            tabBadges[tab].map { "\(tab.rawValue):\($0.analyticsKind)" }
        }.joined(separator: "|")
    }

    @ViewBuilder
    private var socialTabContent: some View {
        ZStack {
            tabLayer(.feed) { feedTab }
            tabLayer(.people) {
                SocialConnectionsView(
                    embedded: true,
                    focusRequestID: peopleFocusRequestID
                )
            }
            tabLayer(.groups) { groupsTab }
            tabLayer(.routes) {
                CommunityRouteLibraryView(
                    embedded: true,
                    importRequestID: routeImportRequestID
                )
            }
        }
    }

    private func tabLayer<Content: View>(
        _ tab: SocialFeatureTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .opacity(selectedFeatureTab == tab ? 1 : 0)
            .allowsHitTesting(selectedFeatureTab == tab)
            .accessibilityHidden(selectedFeatureTab != tab)
    }

    private var feedTab: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                activeNowRail
                upcomingCarousel
                recentPosts
            }
            .padding(.horizontal, OutboundSpacing.screen)
            .padding(.vertical, 12)
        }
        .refreshable { await refreshFeed(clearUnseenBadge: true) }
    }

    private var groupsTab: some View {
        VStack(spacing: 0) {
            if !circleStore.circles.isEmpty || !circleStore.invitations.isEmpty || !acceptedConnections.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                        Text(String(localized: "social.groups.yours", defaultValue: "Your groups"))
                            .socialSectionLabel()
                        yourCircleSection
                    }
                    .padding(.horizontal, OutboundSpacing.screen)
                    .padding(.vertical, 12)
                }
                .frame(maxHeight: 320)
            }
            SocialGroupsView(embedded: true)
        }
        .refreshable {
            async let circles: Void = circleStore.refresh()
            async let invitations: Void = circleStore.refreshInvitations()
            _ = await (circles, invitations)
        }
    }

    private func groupDisplayName(_ circle: CircleDTO) -> String {
        let normalized = circle.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let duplicateCount = circleStore.circles.filter {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized
        }.count
        guard duplicateCount > 1 else { return circle.name }
        return "\(circle.name) · \(circle.owner.displayName)"
    }

    @ViewBuilder
    private var activeNowRail: some View {
        if !activeConnections.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text(String(localized: "social.active_now.title", defaultValue: "Active now"))
                    .socialSectionLabel()
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(activeConnections) { connection in
                            activeConnectionLink(connection)
                        }
                    }
                    .padding(.horizontal, 1)
                }
                .frame(height: 70)
            }
            .onAppear {
                guard hasInitializedFeatureTab, selectedFeatureTab == .feed else { return }
                trackActiveNowExposureIfNeeded()
            }
        }
    }

    @ViewBuilder
    private func activeConnectionLink(_ connection: SocialConnectionDTO) -> some View {
        if let session = liveCheerStore.sessions.first(where: {
            $0.runner.id == connection.person.id && $0.status == "active"
        }) {
            NavigationLink {
                LiveCheerView(
                    sessionID: session.id,
                    entrySource: "social_active_now",
                    initialSession: session
                )
            } label: {
                activeConnectionLabel(connection, showsCheer: true)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded {
                trackActiveNowInteraction("cheer")
            })
        } else {
            SocialProfileLink(
                person: connection.person,
                connection: connection,
                entrySource: "social_active_now"
            ) {
                activeConnectionLabel(connection, showsCheer: false)
            }
            .simultaneousGesture(TapGesture().onEnded {
                trackActiveNowInteraction("profile")
            })
        }
    }

    private func activeConnectionLabel(
        _ connection: SocialConnectionDTO,
        showsCheer: Bool
    ) -> some View {
        VStack(spacing: 3) {
            SocialAvatar(
                name: connection.person.displayName,
                avatarURL: connection.person.avatarUrl
            )
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: showsCheer ? "waveform.circle.fill" : "circle.fill")
                    .font(.caption)
                    .foregroundStyle(OutboundPalette.companion)
                    .background(.background, in: Circle())
            }
            Text(connection.firstName)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .frame(width: 58)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(
            format: String(localized: "social.active_now.person", defaultValue: "%@ is active now"),
            connection.person.displayName
        ))
        .accessibilityHint(
            showsCheer
                ? String(localized: "social.active_now.cheer_hint", defaultValue: "Opens the live Cheer screen")
                : String(localized: "social.active_now.profile_hint", defaultValue: "Opens this person’s profile")
        )
    }

    @ViewBuilder
    private var upcomingCarousel: some View {
        let upcoming = prioritizedUpcomingRuns
        if !upcoming.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 10) {
                    Text(String(localized: "social.upcoming", defaultValue: "Upcoming"))
                        .socialSectionLabel()
                    Spacer()
                    Button {
                        isCreateActivityEventPresented = true
                        trackUpcomingInteraction("plan")
                    } label: {
                        Label(String(localized: "social.upcoming.plan", defaultValue: "Plan"), systemImage: "plus")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                    .foregroundStyle(OutboundPalette.companion)

                    NavigationLink {
                        SocialActivityDiscoveryView()
                    } label: {
                        Text(String(localized: "social.upcoming.see_all", defaultValue: "See all"))
                            .font(.caption.weight(.semibold))
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(OutboundPalette.companion)
                    .simultaneousGesture(TapGesture().onEnded {
                        trackUpcomingInteraction("see_all")
                    })
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(upcoming.prefix(3)) { run in
                            NavigationLink {
                                ActivityEventDetailView(run: run)
                            } label: {
                                upcomingCompactCard(run)
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(TapGesture().onEnded {
                                trackUpcomingInteraction("card")
                            })
                        }
                    }
                    .padding(.horizontal, 1)
                }
                .frame(height: 118)
            }
            .onAppear {
                guard hasInitializedFeatureTab, selectedFeatureTab == .feed else { return }
                trackUpcomingExposureIfNeeded()
            }
        }
    }

    private var prioritizedUpcomingRuns: [ActivityEventDTO] {
        socialStore.state.upcomingRuns.sorted { lhs, rhs in
            let lhsPriority = upcomingPriority(lhs)
            let rhsPriority = upcomingPriority(rhs)
            return lhsPriority == rhsPriority ? lhs.startsAt < rhs.startsAt : lhsPriority < rhsPriority
        }
    }

    private func upcomingPriority(_ run: ActivityEventDTO) -> Int {
        if isActionRequired(run) { return 0 }
        if run.startsAt <= Date().addingTimeInterval(72 * 60 * 60) { return 1 }
        return 2
    }

    private func isActionRequired(_ run: ActivityEventDTO) -> Bool {
        run.source?.kind == "directInvitation" && run.currentUserGoing != true
    }

    private func upcomingCompactCard(_ run: ActivityEventDTO) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(run.startsAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                .font(.caption.weight(.semibold))
                .foregroundStyle(OutboundPalette.companion)
                .lineLimit(1)
            Text(run.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            ActivityEventContextIndicators(event: run)
            Image(systemName: "person.2.wave.2")
                .foregroundStyle(OutboundPalette.companion)
                .accessibilityLabel(String(localized: "social.event.flexible_location", defaultValue: "Flexible attendance"))
            Label(
                String(localized: "social.upcoming.attendees", defaultValue: "\(run.attendeeCount ?? 0) going"),
                systemImage: "person.2"
            )
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(width: 226, height: 88, alignment: .topLeading)
        .padding(12)
        .background(OutboundPalette.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(OutboundPalette.companion.opacity(0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func initializeFeatureTabIfNeeded() {
        guard !hasInitializedFeatureTab, !hasInteractedWithFeatureTabs else { return }
        hasInitializedFeatureTab = true
        selectedFeatureTab = acceptedConnections.isEmpty ? .people : .feed
        track(.socialTabExposed, properties: [
            .selectionType: .string(selectedFeatureTab.rawValue),
            .entrySource: .string("social_visit"),
        ])
        if selectedFeatureTab == .feed {
            trackFeedModuleExposuresIfNeeded()
        }
    }

    private func selectFeatureTab(
        _ tab: SocialFeatureTab,
        entrySource explicitEntrySource: String? = nil
    ) {
        hasInteractedWithFeatureTabs = true
        let entrySource = explicitEntrySource ?? (selectedFeatureTab == tab ? "reselect" : "tab_row")
        selectedFeatureTab = tab
        track(.socialTabExposed, properties: [
            .selectionType: .string(tab.rawValue),
            .entrySource: .string(entrySource),
        ])
        track(.socialTabSelected, properties: [
            .selectionType: .string(tab.rawValue),
            .entrySource: .string(entrySource),
        ])
        if let badge = tabBadges[tab] {
            track(.socialTabBadgeSelected, properties: [
                .selectionType: .string(tab.rawValue),
                .sourceType: .string(badge.analyticsKind),
            ])
        }
        if tab == .feed {
            trackFeedModuleExposuresIfNeeded()
            Task { await refreshFeed(clearUnseenBadge: true) }
        }
    }

    private func refreshFeed(clearUnseenBadge: Bool) async {
        let previousRevision = socialStore.homeRefreshRevision
        async let home: Void = socialStore.refresh()
        async let live: Void = liveCheerStore.refreshSessions()
        _ = await (home, live)
        guard clearUnseenBadge,
              socialStore.homeRefreshRevision > previousRevision,
              socialStore.hasUnseenFeedPosts else { return }
        socialStore.markNewestFeedPostViewed()
        track(.socialTabBadgeCleared, properties: [
            .selectionType: .string(SocialFeatureTab.feed.rawValue),
            .sourceType: .string("successful_refresh"),
        ])
    }

    private func trackNewBadgeExposures() {
        let currentSignatures = Set(SocialFeatureTab.allCases.compactMap { tab in
            tabBadges[tab].map { "\(tab.rawValue):\($0.analyticsKind)" }
        })
        exposedBadgeSignatures.formIntersection(currentSignatures)
        for tab in SocialFeatureTab.allCases {
            guard let badge = tabBadges[tab] else { continue }
            let signature = "\(tab.rawValue):\(badge.analyticsKind)"
            guard exposedBadgeSignatures.insert(signature).inserted else { continue }
            track(.socialTabBadgeExposed, properties: [
                .selectionType: .string(tab.rawValue),
                .sourceType: .string(badge.analyticsKind),
            ])
        }
    }

    private func trackActiveNowInteraction(_ selection: String) {
        track(.socialActiveNowSelected, properties: [
            .selectionType: .string(selection),
            .entrySource: .string("active_now"),
        ])
    }

    private func trackUpcomingInteraction(_ selection: String) {
        track(.socialUpcomingSelected, properties: [
            .selectionType: .string(selection),
            .entrySource: .string("feed"),
        ])
    }

    private func trackFeedModuleExposuresIfNeeded() {
        trackActiveNowExposureIfNeeded()
        trackUpcomingExposureIfNeeded()
        trackFirstFeedCardVisibilityIfNeeded()
    }

    private func trackActiveNowExposureIfNeeded() {
        guard !activeConnections.isEmpty, !hasTrackedActiveNowExposure else { return }
        hasTrackedActiveNowExposure = true
        track(.socialActiveNowExposed, properties: [
            .countBucket: .string(ProductAnalyticsBucket.count(activeConnections.count)),
        ])
    }

    private func trackUpcomingExposureIfNeeded() {
        let upcoming = prioritizedUpcomingRuns
        guard !upcoming.isEmpty, !hasTrackedUpcomingExposure else { return }
        hasTrackedUpcomingExposure = true
        track(.socialUpcomingExposed, properties: [
            .countBucket: .string(ProductAnalyticsBucket.count(upcoming.count)),
            .sourceType: .string(upcoming.contains(where: isActionRequired) ? "action_required" : "relevant"),
        ])
    }

    private func trackFirstFeedCardVisibilityIfNeeded() {
        guard let firstPost = socialStore.state.posts.first,
              !hasTrackedFirstFeedCard else { return }
        hasTrackedFirstFeedCard = true
        track(.socialFeedFirstCardVisible, properties: [
            .sourceType: .string(firstPost.isCurrentUser ? "self" : "connection"),
        ])
    }

    private func track(
        _ name: ProductEventName,
        properties: [ProductPropertyKey: AnalyticsValue]
    ) {
        Task { await analyticsManager?.track(.init(name, properties: properties)) }
    }

    private func liveCheerRow(name: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.circle.fill")
            Text(String(format: String(localized: "social.cheer_live.named", defaultValue: "Cheer %@ on"), name))
        }
        .font(.headline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func trackPushOpen(type: String, destination: String) {
        Task {
            await analyticsManager?.track(.init(.pushNotificationOpened, properties: [
                .sourceType: .string(type),
                .selectionType: .string(destination),
            ]))
        }
    }

    private func deletePendingPost(skipFutureConfirmations: Bool) {
        guard let post = postPendingDeletion else { return }
        if skipFutureConfirmations {
            skipsPostDeletionConfirmation = true
        }
        postPendingDeletion = nil
        Task { await socialStore.deletePost(post) }
    }

    private func trackSocialInboxOpened(entrySource: String) {
        Task {
            await analyticsManager?.track(.init(.socialInboxOpened, properties: [
                .entrySource: .string(entrySource),
            ]))
        }
    }

    private var notificationCenterBadgeCount: Int {
        socialStore.actionableNotificationCount + (healthImportStore.importCandidates.isEmpty ? 0 : 1)
    }

    private func incomingRequestCard(_ connection: SocialConnectionDTO) -> some View {
        OutboundCard(style: .companion) {
            HStack(spacing: OutboundSpacing.compact) {
                SocialProfileLink(person: connection.person, entrySource: "social_connection_request") {
                    HStack(spacing: OutboundSpacing.compact) {
                        SocialAvatar(name: connection.person.displayName, avatarURL: connection.person.avatarUrl)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(connection.person.displayName) wants to connect").font(.headline)
                            Text("@\(connection.person.username)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                    .contentShape(Rectangle())
                }
                Spacer()
                NavigationLink("Review") {
                    SocialConnectionsView()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var connectionGrowthCard: some View {
        OutboundCard(style: .companion) {
            VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                Text("Running is better with people who matter")
                    .font(.headline)
                Text("Connect with a few friends to make your activity feed and run plans more useful.")
                    .font(.subheadline)
                HStack {
                    Button(action: openConnections) {
                        Label("Find people", systemImage: "person.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        Task { await shareReferral() }
                    } label: {
                        Label("Invite", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder
    private var yourCircleSection: some View {
        VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
            ForEach(circleStore.invitations) { invitation in
                circleInvitationCard(invitation)
            }
            if circleStore.circles.isEmpty {
                if circleStore.invitations.isEmpty,
                   socialStore.hasLoadedConnections,
                   !acceptedConnections.isEmpty {
                    NavigationLink {
                        CircleCreateView()
                    } label: {
                        OutboundCard(style: .companion) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 10) {
                                    ForEach(["figure.walk", "figure.run", "figure.outdoor.cycle"], id: \.self) { symbol in
                                        Image(systemName: symbol)
                                            .foregroundStyle(OutboundPalette.companion)
                                            .frame(width: 36, height: 36)
                                            .background(OutboundPalette.companion.opacity(0.12), in: Circle())
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                        .foregroundStyle(OutboundPalette.companion)
                                }
                                Text(String(localized: "group.create.inspiration_title", defaultValue: "Active. Positive. Together."))
                                    .font(.title3.bold())
                                    .foregroundStyle(.primary)
                                Text(String(localized: "group.create.detail", defaultValue: "Share activities and progress with the people closest to you—and cheer each other on."))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(String(localized: "social.create.group.start", defaultValue: "Create your Group"))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(OutboundPalette.companion)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } else {
                ForEach(circleStore.circles) { circle in
                    NavigationLink {
                        CircleDetailView(circle: circle)
                    } label: {
                        CircleCompactCard(circle: circle, isPrimary: false, displayName: groupDisplayName(circle))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func circleInvitationCard(_ invitation: CircleInvitationDTO) -> some View {
        OutboundCard(style: .companion) {
            VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                Text(String(localized: "group.invitation.title", defaultValue: "You’re invited to a Group"))
                    .font(.headline)
                Text(String(
                    format: String(localized: "circle.invitation.from", defaultValue: "%@ invited you to %@"),
                    invitation.sender.displayName,
                    invitation.circle.name
                ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(String(localized: "group.invitation.promise", defaultValue: "Share activities, encourage each other, and build a healthier week together."))
                    .font(.subheadline)
                HStack {
                    Button(String(localized: "circle.invitation.accept", defaultValue: "Accept")) {
                        Task {
                            if await circleStore.accept(invitation),
                               let joined = circleStore.circles.first(where: { $0.id == invitation.circleId }) {
                                await analyticsManager?.track(.init(.circleInvitationAccepted, properties: [
                                    .entrySource: .string("social"),
                                    .participantCountBucket: .string(ProductAnalyticsBucket.count(joined.memberCount))
                                ]))
                                if joined.lifecycle == "active" {
                                    await analyticsManager?.track(.init(.circleActivated, properties: [
                                        .participantCountBucket: .string(ProductAnalyticsBucket.count(joined.memberCount))
                                    ]))
                                }
                            }
                        }
                    }
                        .buttonStyle(.borderedProminent)
                    Button(String(localized: "circle.invitation.decline", defaultValue: "Decline")) { Task { if await circleStore.decline(invitation) { await analyticsManager?.track(.init(.circleInvitationDeclined, properties: [.entrySource: .string("social")])) } } }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private func openConnections() {
        showsConnections = true
        Task {
            await analyticsManager?.track(.init(.connectionsOpened, properties: [
                .entrySource: .string("social_home_preview"),
            ]))
        }
    }

    private func openAddConnection() {
        showsAddConnection = true
        Task {
            await analyticsManager?.track(.init(.connectionsOpened, properties: [
                .entrySource: .string("social_home_add"),
            ]))
        }
    }

    @ViewBuilder
    private var upcomingRuns: some View {
        HStack {
            Text(String(localized: "social.upcoming", defaultValue: "Upcoming")).socialSectionLabel()
            Spacer()
            SocialSectionHeaderAction(
                systemName: "plus",
                accessibilityLabel: String(localized: "social.create.plan", defaultValue: "Plan an activity"),
                action: { isCreateActivityEventPresented = true }
            )
            NavigationLink {
                SocialActivityDiscoveryView()
            } label: {
                SocialSectionHeaderIcon(systemName: "ellipsis")
            }
            .buttonStyle(.plain)
            .foregroundStyle(OutboundPalette.companion)
            .accessibilityLabel(String(localized: "social.upcoming.open", defaultValue: "Show all upcoming activities"))
        }
        if socialStore.state.upcomingRuns.isEmpty {
            OutboundCard {
                HStack(spacing: OutboundSpacing.compact) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.title2)
                        .foregroundStyle(OutboundPalette.companion)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("No upcoming runs")
                            .font(.headline)
                        Text("Group runs and plans from your connections will appear here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            ForEach(socialStore.state.upcomingRuns.prefix(2)) { run in
                OutboundCard {
                    ZStack(alignment: .topTrailing) {
                        NavigationLink {
                            ActivityEventDetailView(run: run)
                        } label: {
                            VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                                VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                                    Text(activityEventSourceLabel(run))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(run.title).font(.headline).foregroundStyle(.primary)
                                    ActivityEventContextIndicators(event: run)
                                    Text(run.startsAt.formatted(date: .abbreviated, time: .shortened) + locationSuffix(run.locationName))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    if let note = run.paceNote {
                                        Text(note).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.trailing, 44)

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "person.2.wave.2")
                                        Text("\(run.attendeeCount ?? 0) participants")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(OutboundPalette.companion)
                                if let compatibility = run.compatibility {
                                    AIExplanationView(text: compatibility.explanation)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if let invitationURL = socialStore.latestInvitationURL {
                            ShareLink(item: String(localized: "Join me for a run on Plainstride: \(invitationURL.absoluteString)")) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .buttonStyle(SocialIconButtonStyle())
                            .accessibilityLabel("Share run invitation")
                        } else {
                            Button {
                                Task { await socialStore.invite(to: run) }
                            } label: {
                                Image(systemName: "person.badge.plus")
                            }
                            .buttonStyle(SocialIconButtonStyle())
                            .accessibilityLabel("Invite connections")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var pastActivityEvents: some View {
        if !socialStore.state.pastEvents.isEmpty {
            HStack {
                Text("PAST GROUP RUNS").socialSectionLabel()
                Spacer()
                if socialStore.state.pastEvents.count > 1 {
                    NavigationLink {
                        PastActivityEventsView(events: socialStore.state.pastEvents)
                    } label: {
                        Text("All")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(OutboundPalette.companion)
                }
            }
            PastActivityEventRow(event: socialStore.state.pastEvents[0])
        }
    }

    @ViewBuilder
    private var joinedClubs: some View {
        if !socialStore.state.clubs.isEmpty {
            Text("YOUR GROUPS").socialSectionLabel()
            ForEach(socialStore.state.clubs.prefix(3)) { club in
                NavigationLink {
                    SocialGroupsView()
                } label: {
                    OutboundCard {
                        HStack {
                            Image(systemName: "flag.fill").foregroundStyle(OutboundPalette.companion)
                            VStack(alignment: .leading) {
                                Text(club.name).font(.headline).foregroundStyle(.primary)
                                Text([club.city, club.role.map(localizedGroupRole)].compactMap { $0 }.joined(separator: " · "))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            NavigationLink {
                SocialGroupsView()
            } label: {
                Label("Discover groups", systemImage: "person.3")
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var recentPosts: some View {
        Text("ACTIVITY FEED").socialSectionLabel()
        if socialStore.state.posts.isEmpty {
            OutboundCard {
                HStack(spacing: OutboundSpacing.compact) {
                    Image(systemName: "figure.run.circle")
                        .font(.title2)
                        .foregroundStyle(OutboundPalette.companion)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("No activity yet")
                            .font(.headline)
                        Text("New activities from you and your connections will appear here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            ForEach(socialStore.state.posts) { post in
                OutboundCard {
                    VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                        HStack {
                            SocialProfileLink(person: post.user, entrySource: "activity_feed") {
                                HStack {
                                    SocialAvatar(name: post.user.displayName, avatarURL: post.user.avatarUrl)
                                    VStack(alignment: .leading) {
                                        Text(post.user.displayName).font(.headline).foregroundStyle(.primary)
                                        Text(post.activityTimestamp.formatted(.relative(presentation: .named)))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            Spacer()
                            Menu {
                                if post.isCurrentUser {
                                    Button("Delete post", role: .destructive) {
                                        if skipsPostDeletionConfirmation {
                                            Task { await socialStore.deletePost(post) }
                                        } else {
                                            postPendingDeletion = post
                                        }
                                    }
                                } else {
                                    Button("Report post", role: .destructive) {
                                        postPendingReport = post
                                    }
                                    Button("Block \(post.user.displayName)", role: .destructive) {
                                        postPendingBlock = post
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.body.weight(.semibold))
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Post actions")
                        }
                        VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                            Text(post.activity?.title ?? String(localized: "Run")).font(.headline).foregroundStyle(.primary)
                            if let activity = post.activity {
                                ZStack(alignment: .bottom) {
                                    SocialRoutePreviewImage(activity: activity)
                                    HStack(spacing: 0) {
                                        socialStat(activity.distanceM.map { measurementPreferences.unitSystem.distanceString(meters: $0, fractionDigits: 1) } ?? "—", "Distance")
                                        socialStat(activity.durationSecs.map(socialDuration) ?? "—", "Time")
                                        socialStat(activity.avgPace.map { $0.paceString(for: measurementPreferences.unitSystem) } ?? "—", "Pace")
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(.regularMaterial)
                                }
                                .aspectRatio(1.5, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(alignment: .topLeading) {
                                    if let milestone = milestone(for: activity, isCurrentUser: post.isCurrentUser) {
                                        RecognitionPill(preview: milestone, compact: true).padding(12)
                                    }
                                }
                            }
                        }
                        if let caption = post.caption, !caption.isEmpty {
                            Text(caption).font(.subheadline)
                        }
                        HStack(spacing: OutboundSpacing.compact) {
                            Button {
                                Task { await toggleCheer(on: post) }
                            } label: {
                                Image(systemName: post.currentUserCheered ? "heart.fill" : "heart")
                            }
                            .buttonStyle(SocialFeedActionButtonStyle(isActive: post.currentUserCheered))
                            .disabled(socialStore.isSocialMutationPending)
                            .accessibilityLabel(post.currentUserCheered ? "Remove cheer" : "Cheer")
                            .accessibilityValue("\(post.reactionCount)")

                            if post.reactionCount > 0 {
                                SocialCheerAvatarsButton(post: post) {
                                    selectedCheersPost = post
                                }
                            }

                            Button {
                                selectedCommentPost = post
                            } label: {
                                Label("\(post.commentCount)", systemImage: "bubble.left")
                            }
                            .buttonStyle(SocialFeedActionButtonStyle())
                            .accessibilityLabel("Comments")
                            .accessibilityValue("\(post.commentCount)")

                            Spacer()
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedActivityPost = post
                    Task {
                        await analyticsManager?.track(.init(.activityDetailOpened, properties: [
                            .sourceType: .string("social_feed"),
                        ]))
                    }
                }
                .accessibilityAction(named: String(localized: "Open activity")) {
                    selectedActivityPost = post
                }
                .onAppear {
                    guard post.id == socialStore.state.posts.first?.id,
                          hasInitializedFeatureTab,
                          selectedFeatureTab == .feed else { return }
                    trackFirstFeedCardVisibilityIfNeeded()
                }
                if post.id == socialStore.state.posts.last?.id,
                   socialStore.state.nextFeedCursor != nil {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, OutboundSpacing.compact)
                        .task {
                            guard let appendedCount = await socialStore.loadMorePosts() else {
                                toastMessage = String(localized: "social.feed.load_more_failed")
                                return
                            }
                            guard appendedCount > 0 else { return }
                            let page = Int(ceil(
                                Double(socialStore.state.posts.count) / Double(Self.feedPageSize)
                            ))
                            await analyticsManager?.track(.init(.paginatedListPageLoaded, properties: [
                                .sourceType: .string("activity_feed"),
                                .countBucket: .string(ProductAnalyticsBucket.count(appendedCount)),
                                .pageDepthBucket: .string(ProductAnalyticsBucket.pageDepth(page))
                            ]))
                        }
                }
            }
        }
    }

    private func trackActivityFeedLoaded() {
        let posts = socialStore.state.posts
        let sourceType: String
        let timestampSource: String
        if posts.isEmpty {
            sourceType = "empty"
            timestampSource = "empty"
        } else {
            sourceType = posts.contains(where: { !$0.isCurrentUser }) ? "connections" : "self_only"
            let exactTimestampCount = posts.filter { $0.activity?.startedAt != nil }.count
            if exactTimestampCount == posts.count {
                timestampSource = "activity_start"
            } else if exactTimestampCount == 0 {
                timestampSource = "post_created_fallback"
            } else {
                timestampSource = "mixed"
            }
        }
        Task {
            await analyticsManager?.track(.init(.activityFeedLoaded, properties: [
                .countBucket: .string(ProductAnalyticsBucket.count(posts.count)),
                .sourceType: .string(sourceType),
                .timestampSource: .string(timestampSource),
            ]))
        }
    }

    private func shareReferral() async {
        guard let url = await socialStore.referralInvitationURL() else { return }
        await SystemSharePresenter.present(activityItems: [
            String(localized: "Join me for a run on Plainstride: \(url.absoluteString)"),
        ])
    }

    private func milestone(for activity: TogetherActivityDTO, isCurrentUser: Bool) -> RecognitionPreview? {
        guard isCurrentUser, let activityID = UUID(uuidString: activity.id) else { return nil }
        return recognitionStore.topRecognition(for: activityID)
    }

    private func toggleCheer(on post: TogetherPostDTO) async {
        let addsSupport = !post.currentUserCheered
        guard await socialStore.toggleCheer(on: post) else {
            toastMessage = String(localized: "Could not update cheer. Try again.")
            return
        }
        guard addsSupport else { return }
        _ = socialRecognitionStore.registerSupport(for: post.id)
    }

    private func reconcileSharedActivityMilestones() {
        let sharedActivityIDs = Set(
            socialStore.state.posts
                .filter(\.isCurrentUser)
                .compactMap(\.activity?.id)
        )
        for activity in activityStore.activities where !activity.photos.isEmpty {
            let serverID = activity.sync?.serverActivityId
            if sharedActivityIDs.contains(serverID ?? activity.id.uuidString) {
                _ = socialRecognitionStore.registerPhotoFinish(for: activity)
            }
        }
    }

    private func locationSuffix(_ location: String?) -> String {
        location.map { " · \($0)" } ?? ""
    }

    private func activityEventSourceLabel(_ run: ActivityEventDTO) -> String {
        switch run.source?.kind {
        case "createdByYou":
            return String(localized: "Created by you")
        case "joined":
            return String(localized: "Joined · From \(run.creator.displayName)")
        case "directInvitation":
            return String(localized: "From \(run.creator.displayName) · Direct invitation")
        case "group":
            return String(localized: "From \(run.club?.name ?? run.creator.displayName) · Your group")
        case "connection":
            return String(localized: "From \(run.creator.displayName) · Your connection")
        default:
            return String(localized: "From \(run.creator.displayName)")
        }
    }

    private func socialStat(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.subheadline.monospacedDigit().weight(.semibold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func socialDuration(_ seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
            : String(format: "%d:%02d", minutes, remainingSeconds)
    }

    private func localizedGroupRole(_ role: String) -> String {
        switch role.lowercased() {
        case "owner": String(localized: "Owner")
        case "admin": String(localized: "Admin")
        case "member": String(localized: "Member")
        default: role
        }
    }
}

private enum SocialPostReportReason: String, CaseIterable, Identifiable {
    case harassment, hate, spam, sexual, violence, privacy, other

    var id: String { rawValue }

    var localizedLabel: String {
        switch self {
        case .harassment: String(localized: "social.report.reason.harassment", defaultValue: "Harassment")
        case .hate: String(localized: "social.report.reason.hate", defaultValue: "Hate speech")
        case .spam: String(localized: "social.report.reason.spam", defaultValue: "Spam")
        case .sexual: String(localized: "social.report.reason.sexual", defaultValue: "Sexual content")
        case .violence: String(localized: "social.report.reason.violence", defaultValue: "Violence")
        case .privacy: String(localized: "social.report.reason.privacy", defaultValue: "Privacy")
        case .other: String(localized: "social.report.reason.other", defaultValue: "Other")
        }
    }
}

private struct ActivityEventMeetingPointView: View {
    let coordinate: CLLocationCoordinate2D
    let locationName: String?

    private var coordinateText: String {
        String(
            format: String(
                localized: "social.event.location.coordinates.format",
                defaultValue: "%1$@, %2$@"
            ),
            locale: .autoupdatingCurrent,
            coordinate.latitude.coordinateString,
            coordinate.longitude.coordinateString
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let locationName {
                Text(locationName)
                    .font(.headline)
            }
            Map(
                position: .constant(.region(MKCoordinateRegion(
                    center: coordinate,
                    latitudinalMeters: 500,
                    longitudinalMeters: 500
                ))),
                interactionModes: [.pan, .zoom]
            ) {
                Annotation(
                    String(
                        localized: "social.event.location.map.meet_here",
                        defaultValue: "Meet here"
                    ),
                    coordinate: coordinate,
                    anchor: .bottom
                ) {
                    Image(systemName: "mappin")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(OutboundPalette.companion)
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityLabel(
                String(
                    localized: "social.event.location.map.detail_accessibility",
                    defaultValue: "Meeting point map"
                )
            )

            Label(coordinateText, systemImage: "location")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .accessibilityLabel(
                    String(
                        localized: "social.event.location.coordinates.accessibility",
                        defaultValue: "Exact coordinates"
                    )
                )
                .accessibilityValue(coordinateText)
        }
    }
}

private extension Double {
    var coordinateString: String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), self)
    }
}

private struct SocialActivityDiscoveryView: View {
    @EnvironmentObject private var socialStore: TogetherStore

    var body: some View {
        List {
            if socialStore.state.upcomingRuns.isEmpty {
                ContentUnavailableView(
                    "No activities to discover",
                    systemImage: "figure.run.circle",
                    description: Text("Plans from your connections and groups will appear here.")
                )
            } else {
                ForEach(socialStore.state.upcomingRuns) { activity in
                    NavigationLink {
                        ActivityEventDetailView(run: activity)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(activity.title)
                                .font(.headline)
                            Text(activity.startsAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Image(systemName: "person.2.wave.2")
                                .accessibilityLabel("Flexible attendance")
                                .font(.caption)
                                .foregroundStyle(OutboundPalette.companion)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            if !socialStore.state.pastEvents.isEmpty {
                Section(String(localized: "social.activities.past", defaultValue: "Past activities")) {
                    ForEach(socialStore.state.pastEvents) { event in
                        PastActivityEventRow(event: event)
                    }
                }
            }
        }
        .navigationTitle(String(localized: "social.upcoming", defaultValue: "Upcoming"))
        .refreshable { await socialStore.refresh() }
    }
}

private struct SocialGroupsView: View {
    @EnvironmentObject private var socialStore: TogetherStore
    @EnvironmentObject private var socialRecognitionStore: SocialRecognitionStore
    let embedded: Bool

    init(embedded: Bool = false) {
        self.embedded = embedded
    }

    private var joinedGroups: [SocialGroupDTO] {
        socialStore.discoverableGroups.filter { $0.membershipRole != nil }
    }

    private var discoveryGroups: [SocialGroupDTO] {
        socialStore.discoverableGroups.filter { $0.membershipRole == nil }
    }

    var body: some View {
        List {
            Section(String(localized: "social.groups.joined", defaultValue: "Joined Groups")) {
                if joinedGroups.isEmpty {
                    Label(
                        String(localized: "social.groups.joined.empty", defaultValue: "Groups you join will appear here."),
                        systemImage: "person.3"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(joinedGroups) { group in
                        groupRow(group)
                    }
                }
            }

            Section(String(localized: "social.groups.discover", defaultValue: "Discover")) {
                if discoveryGroups.isEmpty {
                    ContentUnavailableView(
                        String(localized: "social.groups.discover.empty", defaultValue: "No new Groups right now"),
                        systemImage: "binoculars",
                        description: Text(String(localized: "social.groups.discover.description", defaultValue: "Pull to refresh as more running Groups become available."))
                    )
                } else {
                    ForEach(discoveryGroups) { group in
                        groupRow(group)
                    }
                }
            }
        }
        .navigationTitle(embedded ? "" : String(localized: "Groups"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await socialStore.refreshGroups() }
        .refreshable { await socialStore.refreshGroups() }
    }

    private func groupRow(_ group: SocialGroupDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.name).font(.headline)
                    Text([group.city, String(localized: "\(group.memberCount) members")].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(group.membershipRole == nil ? String(localized: "Join") : String(localized: "Leave")) {
                    Task {
                        let isJoining = group.membershipRole == nil
                        if await socialStore.toggleMembership(in: group), isJoining {
                            _ = socialRecognitionStore.registerGroupJoin(groupID: group.id)
                        }
                    }
                }
                .buttonStyle(.bordered)
            }
            if let description = group.description {
                Text(description).font(.subheadline)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ActivityEventDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.analyticsManager) private var analyticsManager
    @EnvironmentObject private var socialStore: TogetherStore
    @EnvironmentObject private var socialRecognitionStore: SocialRecognitionStore
    let run: ActivityEventDTO
    var entrySource = "social_upcoming"
    @State private var detail: ActivityEventDetailDTO?
    @State private var isConnectionPickerPresented = false
    @State private var selectedConnectionIDs: Set<String> = []
    @State private var isInviting = false
    @State private var isAttendanceChoicePresented = false
    @State private var invitationToDelete: ActivityEventPendingInvitationDTO?
    @State private var deletingInvitationIDs: Set<String> = []
    @State private var isActivityStartPresented = false
    @State private var isLocationPermissionPromptPresented = false
    @State private var isActivityStartPendingPermission = false
    @State private var isEditPresented = false
    @StateObject private var startLocationManager = LocationManager()
    @State private var showAllParticipants = false
    private var results: ActivityEventResultDTO? { socialStore.resultsByActivityEventID[run.id] }
    private var isCreator: Bool { (detail?.currentUserRole ?? run.currentUserRole) == "owner" }
    private var participantIDs: Set<String> { Set(detail?.participants?.map(\.person.id) ?? []) }
    private var invitedUserIDs: Set<String> { Set(detail?.invitedUserIds ?? []) }
    private var visiblePendingInvitations: [ActivityEventPendingInvitationDTO] {
        let goingIDs = participantIDs
        let goingNames = Set((detail?.participants ?? []).map { $0.person.displayName.lowercased() })
        return (detail?.pendingInvitations ?? []).filter {
            !goingIDs.contains($0.recipient.id)
                && !goingNames.contains($0.recipient.displayName.lowercased())
        }
    }
    private var eventEndsAt: Date? { detail?.endsAt ?? run.endsAt }

    var body: some View {
        List {
            Section {
                LabeledContent("Created by", value: run.creator.displayName)
                LabeledContent("When", value: run.startsAt.formatted(date: .abbreviated, time: .shortened))
                if let eventEndsAt {
                    LabeledContent("Duration", value: activityDurationLabel(from: run.startsAt, to: eventEndsAt))
                    LabeledContent("Scheduled end", value: eventEndsAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Results close", value: eventEndsAt.addingTimeInterval(ActivityEventTiming.reconciliationWindow).formatted(date: .abbreviated, time: .shortened))
                }
                if let pace = run.paceNote { LabeledContent("Pace / note", value: pace) }
            }
            if let location = detail?.locationName ?? run.locationName {
                Section {
                    if detail?.participationMode == "hybrid" {
                        Label("Join virtually or meet at:", systemImage: "person.2.wave.2")
                            .font(.headline)
                    } else {
                        Label("Meet at:", systemImage: "mappin.and.ellipse")
                            .font(.headline)
                    }
                    if let coordinate = detail?.meetupCoordinate ?? run.meetupCoordinate {
                        ActivityEventMeetingPointView(
                            coordinate: coordinate,
                            locationName: location
                        )
                    } else {
                        Text(location)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Location")
                }
            } else if detail?.participationMode == "hybrid" {
                Section {
                    Label("Join virtually", systemImage: "wifi")
                        .font(.headline)
                }
            }
            if let compatibility = run.compatibility {
                Section("Fit") { AIExplanationView(text: compatibility.explanation) }
            }
            if !run.groups.isEmpty {
                Section("Options") {
                ForEach(run.groups) { option in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(option.label).font(.headline)
                        if let distance = option.distanceMeters {
                            Text(MeasurementUnitSystem.metric.distanceString(meters: distance, fractionDigits: 1))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            }
            if let participants = detail?.participants, !participants.isEmpty {
                Section {
                    ForEach(showAllParticipants ? participants : Array(participants.prefix(3))) { participant in
                        participantRow(participant)
                    }
                    if let results, results.status != "scheduled",
                       detail?.currentUserGoing == true, detail?.currentUserOutcome == nil {
                        Button("I joined without recording") {
                            Task { _ = await socialStore.markActivityEventWithoutRecording(id: run.id) }
                        }
                    }
                } header: {
                    HStack {
                        Text("Participants (\(detail?.attendeeCount ?? participants.count))")
                        Spacer()
                        if participants.count > 3 {
                            Button(showAllParticipants ? "Less" : "More") {
                                showAllParticipants.toggle()
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }
                }
            }
            if isCreator, !visiblePendingInvitations.isEmpty {
                Section("Pending invitations") {
                    ForEach(visiblePendingInvitations) { invitation in
                        HStack(spacing: 12) {
                            SocialAvatar(name: invitation.recipient.displayName, avatarURL: invitation.recipient.avatarUrl)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(invitation.recipient.displayName)
                                Text("Awaiting response")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                invitationToDelete = invitation
                            } label: {
                                if deletingInvitationIDs.contains(invitation.id) {
                                    ProgressView()
                                } else {
                                    Image(systemName: "trash")
                                }
                            }
                            .buttonStyle(.borderless)
                            .disabled(deletingInvitationIDs.contains(invitation.id))
                            .accessibilityLabel("Delete invitation for \(invitation.recipient.displayName)")
                        }
                    }
                }
            }
            Section {
                if !isCreator && ["scheduled", "active"].contains(detail?.status ?? run.status ?? "scheduled") {
                    Button {
                        guard let detail else { return }
                        if detail.currentUserGoing {
                            Task {
                                if let updatedDetail = await socialStore.toggleRSVP(for: detail) {
                                    self.detail = updatedDetail
                                }
                            }
                        } else {
                            isAttendanceChoicePresented = true
                        }
                    } label: {
                        Label(detail?.currentUserGoing == true ? String(localized: "Leave run") : String(localized: "I'm going"),
                              systemImage: detail?.currentUserGoing == true ? "calendar.badge.minus" : "calendar.badge.checkmark")
                    }
                    .disabled(detail == nil)
                }

                if isCreator && (detail?.status ?? run.status) == "scheduled" {
                    Button {
                        selectedConnectionIDs.removeAll()
                        isConnectionPickerPresented = true
                    } label: {
                        Label("Invite connections", systemImage: "person.badge.plus")
                    }
                }
                if let invitationURL = socialStore.latestInvitationURL {
                    ShareLink(item: String(localized: "Join me for a run on Plainstride: \(invitationURL.absoluteString)")) {
                        Label("Share invitation", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .navigationTitle(run.title)
        .toolbar {
            if isCreator && (detail?.status ?? run.status) == "scheduled" {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isEditPresented = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel("Edit activity")
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if canStartActivity {
                Button {
                    startActivity()
                } label: {
                    Label(
                        String(localized: "social.event.start", defaultValue: "Start activity"),
                        systemImage: "figure.run"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(OutboundPalette.companion)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
        .fullScreenCover(isPresented: $isActivityStartPresented) {
            RecordView(
                initialIntent: SessionIntent.freestyleRun.paired(
                    with: run,
                    attendanceMode: detail?.currentUserAttendanceMode
                ),
                isVisible: true,
                startImmediately: true,
                onLocationPermissionRequired: {
                    isActivityStartPresented = false
                    isLocationPermissionPromptPresented = true
                },
                onCloseRequest: { shouldKeepAlive in
                    if !shouldKeepAlive { isActivityStartPresented = false }
                }
            )
        }
        .alert(
            String(localized: "record.location.permission.title", defaultValue: "Enable location"),
            isPresented: $isLocationPermissionPromptPresented
        ) {
            Button(String(localized: "record.location.permission.enable", defaultValue: "Enable location")) {
                enableEventLocation()
            }
            Button(String(localized: "common.close", defaultValue: "Close"), role: .cancel) {
                isActivityStartPendingPermission = false
            }
        } message: {
            Text(String(
                localized: "record.location.permission.message",
                defaultValue: "Outdoor activities need location to map your route and record pace. Grant access to start, or turn it on in Settings if it was denied before."
            ))
        }
        .onChange(of: startLocationManager.authorizationStatus) { _, _ in
            continuePendingEventStartIfReady()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            startLocationManager.refreshForForeground()
            continuePendingEventStartIfReady()
        }
        .sheet(isPresented: $isEditPresented) {
            if let detail {
                CreateActivityEventView(editingActivity: detail) {
                    isEditPresented = false
                    Task { self.detail = await socialStore.activityEventDetail(id: run.id) }
                }
            }
        }
        .confirmationDialog("Choose attendance", isPresented: $isAttendanceChoicePresented, titleVisibility: .visible) {
            Button(run.locationName ?? String(localized: "Meet in person")) {
                join(attendanceMode: "in_person")
            }
            if detail?.participationMode == "hybrid" {
                Button("Join virtually") {
                    join(attendanceMode: "virtual")
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete invitation?", isPresented: Binding(
            get: { invitationToDelete != nil },
            set: { if !$0 { invitationToDelete = nil } }
        ), presenting: invitationToDelete) { invitation in
            Button("Delete invitation", role: .destructive) {
                deleteInvitation(invitation)
            }
            Button("Cancel", role: .cancel) {}
        } message: { invitation in
            Text("\(invitation.recipient.displayName) will no longer be able to accept this invitation.")
        }
        .task {
            await analyticsManager?.track(.init(.activityEventDetailOpened, properties: [
                .entrySource: .string(entrySource),
            ]))
            detail = await socialStore.activityEventDetail(id: run.id)
            if run.startsAt <= Date() { await socialStore.loadActivityEventResults(id: run.id) }
        }
        .sheet(isPresented: $isConnectionPickerPresented) {
            NavigationStack {
                List(socialStore.connections.filter { $0.status == "accepted" }) { connection in
                    let isGoing = participantIDs.contains(connection.person.id)
                    let isInvited = invitedUserIDs.contains(connection.person.id)
                    let isUnavailable = isGoing || isInvited
                    Button {
                        if selectedConnectionIDs.contains(connection.person.id) {
                            selectedConnectionIDs.remove(connection.person.id)
                        } else if !isUnavailable {
                            selectedConnectionIDs.insert(connection.person.id)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            SocialAvatar(name: connection.person.displayName, avatarURL: connection.person.avatarUrl)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(connection.person.displayName).foregroundStyle(.primary)
                                Text(isGoing ? String(localized: "Going") : isInvited ? String(localized: "Sent") : "@\(connection.person.username)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: isUnavailable ? "checkmark.circle.fill" : selectedConnectionIDs.contains(connection.person.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(isUnavailable ? .secondary : selectedConnectionIDs.contains(connection.person.id) ? OutboundPalette.companion : .secondary)
                        }
                    }
                    .disabled(isUnavailable)
                    .accessibilityLabel(isGoing ? "\(connection.person.displayName), going" : isInvited ? "\(connection.person.displayName), already invited" : "Select \(connection.person.displayName)")
                }
                .navigationTitle("Invite friends")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { isConnectionPickerPresented = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            Task {
                                isInviting = true
                                if await socialStore.inviteConnections(Array(selectedConnectionIDs), toActivityEvent: run.id) {
                                    detail = await socialStore.activityEventDetail(id: run.id)
                                    isConnectionPickerPresented = false
                                }
                                isInviting = false
                            }
                        } label: {
                            if isInviting { ProgressView() } else { Text("Invite") }
                        }
                        .disabled(isInviting || selectedConnectionIDs.isEmpty)
                    }
                }
                .task {
                    await socialStore.refreshConnections()
                    await socialStore.loadRemainingConnections()
                }
            }
        }
    }

    private var canStartActivity: Bool {
        guard detail?.currentUserGoing ?? run.currentUserGoing ?? false else { return false }
        let status = detail?.status ?? run.status ?? "scheduled"
        return ["scheduled", "active"].contains(status)
            && (Calendar.current.isDateInToday(run.startsAt) || status == "active")
    }

    private func startActivity() {
        startLocationManager.refreshForForeground()
        guard startLocationManager.isLocationPermissionGranted else {
            isActivityStartPendingPermission = true
            isLocationPermissionPromptPresented = true
            return
        }
        presentActivityStart()
    }

    private func presentActivityStart() {
        isActivityStartPendingPermission = false
        socialStore.prepareToRecord(activityEventID: run.id)
        isActivityStartPresented = true
    }

    private func continuePendingEventStartIfReady() {
        guard isActivityStartPendingPermission,
              isLocationPermissionPromptPresented == false,
              startLocationManager.isLocationPermissionGranted
        else { return }
        presentActivityStart()
    }

    private func enableEventLocation() {
        let locationManager = startLocationManager
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestPermission()
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func participantRow(_ participant: ActivityEventParticipantDTO) -> some View {
        HStack(spacing: 10) {
            SocialAvatar(name: participant.person.displayName, avatarURL: participant.person.avatarUrl)
            VStack(alignment: .leading, spacing: 2) {
                Text(participant.person.displayName)
                if let result = results?.participants.first(where: { $0.person.id == participant.person.id }) {
                    Text(resultLabel(result))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: attendanceIcon(participant.attendanceMode))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(attendanceLabel(participant.attendanceMode))
        }
    }

    private func resultLabel(_ participant: ActivityEventResultParticipantDTO) -> String {
        if let result = participant.result {
            return String(localized: "Completed · \(MeasurementUnitSystem.metric.distanceString(meters: result.distanceM ?? 0, fractionDigits: 1))")
        }
        switch participant.outcome {
        case "no_recording": return String(localized: "Finished · No activity saved")
        case "did_not_participate": return String(localized: "Couldn't participate")
        default: return String(localized: "Waiting for result")
        }
    }

    private func activityDurationLabel(from start: Date, to end: Date) -> String {
        let totalMinutes = max(0, Int(end.timeIntervalSince(start) / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return String(localized: "\(minutes) min") }
        if minutes == 0 { return String(localized: "\(hours) hr") }
        return String(localized: "\(hours) hr \(minutes) min")
    }

    private func join(attendanceMode: String) {
        guard let detail else { return }
        Task {
            if let updatedDetail = await socialStore.toggleRSVP(for: detail, attendanceMode: attendanceMode) {
                self.detail = updatedDetail
                _ = socialRecognitionStore.registerGroupJoin(groupID: "run:\(run.id)")
            }
        }
    }

    private func deleteInvitation(_ invitation: ActivityEventPendingInvitationDTO) {
        deletingInvitationIDs.insert(invitation.id)
        Task {
            if let updatedDetail = await socialStore.deleteActivityEventInvitation(id: invitation.id, activityEventID: run.id) {
                detail = updatedDetail
            }
            deletingInvitationIDs.remove(invitation.id)
        }
    }

    private func attendanceLabel(_ mode: String?) -> String {
        switch mode {
        case "virtual": String(localized: "Join from anywhere")
        case "in_person": run.locationName ?? String(localized: "Meet in person")
        default: String(localized: "Meet up or join from anywhere")
        }
    }

    private func attendanceIcon(_ mode: String?) -> String {
        switch mode {
        case "virtual": "wifi"
        case "in_person": "mappin.and.ellipse"
        default: "person.2.wave.2"
        }
    }
}

private struct PastActivityEventsView: View {
    let events: [ActivityEventDTO]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: OutboundSpacing.standard) {
                ForEach(events) { event in
                    PastActivityEventRow(event: event)
                }
            }
            .padding(OutboundSpacing.screen)
        }
        .background(OutboundPalette.background)
        .navigationTitle("Past activities")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ActivityEventContextIndicators: View {
    let event: ActivityEventDTO
    var attendanceMode: String? = nil
    var iconOnly = false

    private var indicators: [(label: String, icon: String)] {
        var values: [(label: String, icon: String)] = []
        if event.club != nil || event.source?.kind == "group" {
            values.append((String(localized: "Group run", defaultValue: "Group run"), "person.3.fill"))
        } else if let companionLabel {
            values.append((companionLabel, "person.2.fill"))
        }
        if attendanceMode == "virtual" {
            values.append((String(localized: "Virtual", defaultValue: "Virtual"), "wifi"))
        }
        return values
    }

    private var companionLabel: String? {
        switch event.source?.kind {
        case "connection", "directInvitation", "joined", "invitation":
            return String(
                format: String(localized: "social.event.with_person", defaultValue: "With %@"),
                locale: .autoupdatingCurrent,
                event.creator.displayName
            )
        case "createdByYou":
            return (event.attendeeCount ?? 0) > 1
                ? String(localized: "With others", defaultValue: "With others")
                : nil
        default:
            return (event.attendeeCount ?? 0) > 1
                ? String(localized: "With others", defaultValue: "With others")
                : nil
        }
    }

    var body: some View {
        if indicators.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 6) {
                ForEach(Array(indicators.enumerated()), id: \.offset) { _, indicator in
                    if iconOnly {
                        Image(systemName: indicator.icon)
                            .font(.headline)
                            .foregroundStyle(OutboundPalette.companion)
                            .accessibilityLabel(indicator.label)
                    } else {
                        Label(indicator.label, systemImage: indicator.icon)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(OutboundPalette.companion)
                            .lineLimit(1)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(indicators.map(\.label).joined(separator: ", "))
        }
    }
}

private struct PastActivityEventRow: View {
    let event: ActivityEventDTO

    var body: some View {
        NavigationLink {
            ActivityEventDetailView(run: event)
        } label: {
            OutboundCard {
                HStack(spacing: OutboundSpacing.compact) {
                    Image(systemName: "person.2.fill")
                        .foregroundStyle(OutboundPalette.companion)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.title).font(.headline).foregroundStyle(.primary)
                        ActivityEventContextIndicators(event: event)
                        Text(event.startsAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(event.status == "reconciling" ? String(localized: "Collecting participant results") : String(localized: "View shared results"))
                            .font(.caption.weight(.semibold)).foregroundStyle(OutboundPalette.companion)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct SocialNotificationsView: View {
    @Environment(\.analyticsManager) private var analyticsManager
    @EnvironmentObject private var socialStore: TogetherStore
    @EnvironmentObject private var pushNotifications: PushNotificationCoordinator
    @EnvironmentObject private var circleStore: CircleStore
    @EnvironmentObject private var healthImportStore: HealthImportStore
    @State private var selectedNotification: SocialNotificationDTO?

    private var presentationItems: [NotificationCenterPresentationItem] {
        NotificationPresentationPolicy.items(from: socialStore.notifications)
    }

    var body: some View {
        List {
            if socialStore.notifications.isEmpty && healthImportStore.importCandidates.isEmpty {
                ContentUnavailableView("No notifications", systemImage: "bell", description: Text("Connection requests, Cheers, comments, and run invitations appear here."))
            } else {
                ForEach(NotificationCenterTier.allCases) { tier in
                    let items = presentationItems.filter { $0.presentation.tier == tier }
                    if !items.isEmpty || (tier == .needsYou && !healthImportStore.importCandidates.isEmpty) {
                        Section(tier.localizedTitle) {
                            if tier == .needsYou {
                                ForEach(items.filter { $0.presentation.urgencyRank == 0 }) { item in
                                    notificationButton(item)
                                }
                                if !healthImportStore.importCandidates.isEmpty {
                                    healthImportButton
                                }
                                ForEach(items.filter { $0.presentation.urgencyRank != 0 }) { item in
                                    notificationButton(item)
                                }
                            } else {
                                ForEach(items) { item in
                                    notificationButton(item)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(String(localized: "app.notifications.destination", defaultValue: "Notification Center"))
        .navigationDestination(item: $selectedNotification) { notification in
            notificationDestination(notification)
        }
        .task {
            if !healthImportStore.importCandidates.isEmpty {
                await analyticsManager?.track(.init(.featureExposed, properties: [
                    .feature: .string("health_import_notification_center_item"),
                ]))
            }
            await socialStore.refreshNotifications()
            if let notificationID = pushNotifications.pendingNotificationID,
               let notification = socialStore.notifications.first(where: { $0.id == notificationID }) {
                selectedNotification = notification
                pushNotifications.consumePendingNotification()
            }
            await trackCenterExposure()
            await socialStore.markNotificationsRead()
            await pushNotifications.clearAppIconBadge()
        }
        .refreshable { await socialStore.refreshNotifications() }
    }

    private var healthImportNotificationDetail: String {
        String(
            format: String(
                localized: "health.import.notification.detail",
                defaultValue: "Ready to review: %d"
            ),
            locale: .autoupdatingCurrent,
            healthImportStore.importCandidates.count
        )
    }

    private var healthImportButton: some View {
        Button {
            Task {
                await analyticsManager?.track(.init(.notificationActionSelected, properties: [
                    .section: .string(NotificationCenterTier.needsYou.analyticsValue),
                    .category: .string("health_import"),
                    .selectionType: .string("batched"),
                    .countBucket: .string(ProductAnalyticsBucket.count(healthImportStore.importCandidates.count)),
                ]))
            }
            healthImportStore.isReviewPresented = true
        } label: {
            HStack(alignment: .top, spacing: OutboundSpacing.compact) {
                Image(systemName: "heart.text.clipboard.fill")
                    .font(.title3)
                    .foregroundStyle(OutboundPalette.companion)
                    .frame(width: 36, height: 36)
                    .background(OutboundPalette.companion.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "health.import.notification.title", defaultValue: "New Apple Health workouts"))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(healthImportNotificationDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(String(localized: "health.import.notification.hint", defaultValue: "Review and choose which workouts to import."))
        .swipeActions {
            Button(role: .destructive) {
                healthImportStore.dismissCandidates()
            } label: {
                Label(String(localized: "common.dismiss", defaultValue: "Dismiss"), systemImage: "xmark")
            }
        }
    }

    private func notificationButton(_ item: NotificationCenterPresentationItem) -> some View {
        Button {
            Task {
                await analyticsManager?.track(.init(.notificationActionSelected, properties: [
                    .section: .string(item.presentation.tier.analyticsValue),
                    .category: .string(item.presentation.category.rawValue),
                    .selectionType: .string(item.notifications.count > 1 ? "aggregated" : "single"),
                    .countBucket: .string(ProductAnalyticsBucket.count(item.notifications.count)),
                ]))
            }
            selectedNotification = item.primary
        } label: {
            HStack(alignment: .top, spacing: OutboundSpacing.compact) {
                SocialAvatar(name: item.primary.actor?.displayName ?? "Plainstride", avatarURL: item.primary.actor?.avatarUrl)
                VStack(alignment: .leading, spacing: 4) {
                    Text(localizedCircleNotificationMessage(item.primary))
                        .font(item.hasUnread ? .body.weight(.semibold) : .body)
                        .foregroundStyle(.primary)
                    if item.additionalCount > 0 {
                        Text(String(
                            format: String(localized: "safety.inbox.additional_count", defaultValue: "%d more"),
                            locale: .autoupdatingCurrent,
                            item.additionalCount
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Text(item.primary.createdAt.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(notificationAccessibilityHint(item.primary))
    }

    private func trackCenterExposure() async {
        await analyticsManager?.track(.init(.notificationCenterOpened, properties: [
            .countBucket: .string(ProductAnalyticsBucket.count(presentationItems.count + (healthImportStore.importCandidates.isEmpty ? 0 : 1))),
        ]))
        for tier in NotificationCenterTier.allCases {
            let itemCount = presentationItems.count { $0.presentation.tier == tier }
                + (tier == .needsYou && !healthImportStore.importCandidates.isEmpty ? 1 : 0)
            guard itemCount > 0 else { continue }
            await analyticsManager?.track(.init(.notificationSectionExposed, properties: [
                .section: .string(tier.analyticsValue),
                .countBucket: .string(ProductAnalyticsBucket.count(itemCount)),
            ]))
        }
    }

    @ViewBuilder
    private func notificationDestination(_ notification: SocialNotificationDTO) -> some View {
        switch NotificationPresentationPolicy.presentation(for: notification.type, objectID: notification.objectId).destination {
        case .liveCheer:
            if let sessionID = notification.objectId {
                LiveCheerView(sessionID: sessionID, entrySource: "notification_inbox")
            } else {
                SocialNotificationDetailView(notification: notification)
            }
        case .connections:
            SocialConnectionsView()
        case .post:
            SocialNotificationActivityView(notification: notification)
        case .runInvitation:
            SocialRunInvitationActionView(notification: notification)
        case .activityEvent:
            if let runID = notification.objectId,
               let run = socialStore.state.upcomingRuns.first(where: { $0.id == runID }) {
                ActivityEventDetailView(run: run)
            } else {
                SocialNotificationDetailView(notification: notification)
            }
        case .circleInvitation:
            CircleNotificationInvitationView(notification: notification)
        case .circle:
            if let circleID = notification.objectId,
               let circle = circleStore.circles.first(where: { $0.id == circleID }) {
                CircleDetailView(circle: circle)
            } else {
                SocialNotificationDetailView(notification: notification)
            }
        case .generic:
            SocialNotificationDetailView(notification: notification)
        }
    }

    private func notificationAccessibilityHint(_ notification: SocialNotificationDTO) -> String {
        switch NotificationPresentationPolicy.presentation(for: notification.type, objectID: notification.objectId).destination {
        case .liveCheer: return String(localized: "Opens the live activity")
        case .connections: return String(localized: "Opens Connections")
        case .post: return String(localized: "Opens the activity")
        case .runInvitation: return String(localized: "Opens the invitation")
        case .activityEvent: return String(localized: "Opens the group run")
        case .circleInvitation: return String(localized: "group.notification.open_invitation", defaultValue: "Opens the Group invitation")
        case .circle: return String(localized: "group.notification.open", defaultValue: "Opens the Group")
        case .generic: return String(localized: "Opens notification details")
        }
    }
}

private struct CircleNotificationInvitationView: View {
    @EnvironmentObject private var circleStore: CircleStore
    @Environment(\.analyticsManager) private var analyticsManager
    @Environment(\.dismiss) private var dismiss
    let notification: SocialNotificationDTO

    private var invitation: CircleInvitationDTO? { circleStore.invitations.first { $0.id == notification.objectId } }

    var body: some View {
        List {
            Label {
                Text(localizedCircleNotificationMessage(notification))
            } icon: {
                CircleMark()
                    .frame(width: 18, height: 18)
            }
            if let invitation {
                Button(String(localized: "circle.invitation.accept", defaultValue: "Accept")) {
                    Task {
                        if await circleStore.accept(invitation),
                           let joined = circleStore.circles.first(where: { $0.id == invitation.circleId }) {
                            await analyticsManager?.track(.init(.circleInvitationAccepted, properties: [
                                .entrySource: .string("notification_inbox"),
                                .participantCountBucket: .string(ProductAnalyticsBucket.count(joined.memberCount))
                            ]))
                            if joined.lifecycle == "active" {
                                await analyticsManager?.track(.init(.circleActivated, properties: [
                                    .participantCountBucket: .string(ProductAnalyticsBucket.count(joined.memberCount))
                                ]))
                            }
                            dismiss()
                        }
                    }
                }
                Button(String(localized: "circle.invitation.decline", defaultValue: "Decline"), role: .destructive) { Task { if await circleStore.decline(invitation) { dismiss() } } }
            } else {
                Text(String(localized: "circle.invitation.handled", defaultValue: "This invitation is no longer available."))
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(String(localized: "group.invitation.navigation", defaultValue: "Group invitation"))
        .task { await circleStore.refreshInvitations() }
    }
}

private struct SocialNotificationActivityView: View {
    @EnvironmentObject private var socialStore: TogetherStore
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    let notification: SocialNotificationDTO
    @State private var selectedCommentPost: TogetherPostDTO?

    private var post: TogetherPostDTO? {
        guard let postID = notification.objectId else { return nil }
        return socialStore.state.posts.first { $0.id == postID }
    }

    var body: some View {
        ScrollView {
            if let post {
                OutboundCard {
                    VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                        HStack(spacing: OutboundSpacing.compact) {
                            SocialAvatar(name: post.user.displayName, avatarURL: post.user.avatarUrl)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(post.user.displayName).font(.headline)
                                Text(post.activityTimestamp.formatted(.relative(presentation: .named)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text(post.activity?.title ?? String(localized: "Run")).font(.headline)
                        if let activity = post.activity {
                            ZStack(alignment: .bottom) {
                                SocialRoutePreviewImage(activity: activity)
                                HStack(spacing: 0) {
                                    stat(activity.distanceM.map { measurementPreferences.unitSystem.distanceString(meters: $0, fractionDigits: 1) } ?? "—", String(localized: "Distance"))
                                    stat(activity.durationSecs.map(duration) ?? "—", String(localized: "Time"))
                                    stat(activity.avgPace.map { $0.paceString(for: measurementPreferences.unitSystem) } ?? "—", "Pace")
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(.regularMaterial)
                            }
                            .aspectRatio(1.5, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        if let caption = post.caption, !caption.isEmpty { Text(caption).font(.subheadline) }
                        Button {
                            selectedCommentPost = post
                        } label: {
                            Label("View \(post.commentCount) comments", systemImage: "bubble.left")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(OutboundSpacing.screen)
            } else {
                ContentUnavailableView(
                    "Activity unavailable",
                    systemImage: "figure.run",
                    description: Text("This activity may have been removed or is no longer shared with you.")
                )
                .padding(.top, 80)
            }
        }
        .background(OutboundPalette.background)
        .navigationTitle(notification.type == "comment" ? "Comment" : "Cheer")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if post == nil { await socialStore.refresh() }
        }
        .sheet(item: $selectedCommentPost) { SocialCommentsView(post: $0) }
    }

    private func duration(_ seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        return hours > 0 ? "\(hours):\(String(format: "%02d", minutes))" : "\(minutes) min"
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.weight(.semibold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SocialRunInvitationActionView: View {
    @EnvironmentObject private var socialStore: TogetherStore
    @Environment(\.dismiss) private var dismiss
    let notification: SocialNotificationDTO

    var body: some View {
        List {
            Section {
                Label(notification.message, systemImage: "figure.run")
                LabeledContent("Received", value: notification.createdAt.formatted(date: .abbreviated, time: .shortened))
            }
            Section {
                Button {
                    accept(attendanceMode: "in_person")
                } label: {
                    Label("Meet in person", systemImage: "mappin.and.ellipse")
                }
                Button {
                    accept(attendanceMode: "virtual")
                } label: {
                    Label("Join from anywhere", systemImage: "wifi")
                }
            }
        }
        .navigationTitle("Run invitation")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func accept(attendanceMode: String) {
        Task {
            await socialStore.acceptRunInvitation(notification, attendanceMode: attendanceMode)
            dismiss()
        }
    }
}

private struct SocialNotificationDetailView: View {
    let notification: SocialNotificationDTO

    var body: some View {
        List {
            Label(localizedCircleNotificationMessage(notification), systemImage: "bell")
            LabeledContent("Received", value: notification.createdAt.formatted(date: .abbreviated, time: .shortened))
        }
        .navigationTitle("Notification")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SocialCommentsView: View {
    @EnvironmentObject private var socialStore: TogetherStore
    @EnvironmentObject private var socialRecognitionStore: SocialRecognitionStore
    @Environment(\.dismiss) private var dismiss
    let post: TogetherPostDTO
    @State private var draft = ""
    @State private var failedDraft: String?
    @State private var toastMessage: String?

    private var comments: [TogetherCommentDTO] {
        socialStore.commentsByPostID[post.id] ?? post.comments
    }

    var body: some View {
        NavigationStack {
            List {
                if comments.isEmpty {
                    ContentUnavailableView("No comments yet", systemImage: "bubble.left", description: Text("Add the first bit of encouragement."))
                } else {
                    ForEach(comments) { comment in
                        HStack(alignment: .top, spacing: 12) {
                            SocialAvatar(name: comment.author.displayName, avatarURL: comment.author.avatarUrl)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(comment.author.displayName).font(.subheadline.weight(.semibold))
                                    Text(comment.createdAt.formatted(.relative(presentation: .named)))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Text(comment.body)
                            }
                            Spacer()
                            Menu {
                                Button("Report comment", role: .destructive) {
                                    Task { await socialStore.reportComment(comment) }
                                }
                                if comment.canDelete {
                                    Button("Delete comment", role: .destructive) {
                                        Task { await socialStore.deleteComment(comment, from: post) }
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                            }
                            .accessibilityLabel("Comment actions")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    TextField(String(localized: "Add a comment…"), text: $draft)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        let body = draft
                        draft = ""
                        Task {
                            if await socialStore.addComment(body, to: post) {
                                _ = socialRecognitionStore.registerSupport(for: post.id)
                            } else {
                                failedDraft = body
                                toastMessage = String(localized: "Comment failed to post. Tap to try again.")
                            }
                        }
                    } label: {
                        Image(systemName: "paperplane.fill")
                    }
                    .buttonStyle(SocialIconButtonStyle())
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Post comment")
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle("\(String(localized: "Comments")) (\(comments.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(String(localized: "Close comments"))
                }
            }
            .task { await socialStore.loadComments(for: post) }
            .overlay(alignment: .top) {
                if let toastMessage {
                    Button {
                        if let failedDraft { draft = failedDraft }
                        self.toastMessage = nil
                    } label: {
                        Label(toastMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.regularMaterial, in: Capsule())
                            .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
            }
        }
    }
}

struct SocialConnectionsView: View {
    @EnvironmentObject private var socialStore: TogetherStore
    @Environment(\.analyticsManager) private var analyticsManager
    let startsAdding: Bool
    let embedded: Bool
    let focusRequestID: Int
    @State private var searchQuery = ""
    @State private var paginationToast: String?
    @State private var searchToast: String?
    @State private var lastRequestedSearchQuery: String?
    @State private var autocompleteResults: [SocialPersonSearchResultDTO] = []
    @State private var isAutocompleteLoading = false
    @State private var autocompleteFailed = false
    @State private var submittedSearchQuery = ""
    @State private var showsSearchResults = false
    @State private var showsQRCode = false
    @State private var showsScanner = false
    @FocusState private var isSearchFocused: Bool

    init(
        startsAdding: Bool = false,
        embedded: Bool = false,
        focusRequestID: Int = 0
    ) {
        self.startsAdding = startsAdding
        self.embedded = embedded
        self.focusRequestID = focusRequestID
    }

    private static let pageSize = 20

    private var incomingRequests: [SocialConnectionDTO] {
        socialStore.connections.filter { $0.status == "pending" && $0.direction == "incoming" }
    }

    private var outgoingRequests: [SocialConnectionDTO] {
        socialStore.connections.filter { $0.status == "pending" && $0.direction == "outgoing" }
    }

    private var acceptedConnections: [SocialConnectionDTO] {
        socialStore.connections
            .filter { $0.status == "accepted" }
            .sorted(by: SocialConnectionDTO.previewOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            peopleSearchField
            Divider()
            ZStack(alignment: .top) {
                connectionsList
                if showsAutocomplete {
                    autocompleteDropdown
                        .zIndex(1)
                }
            }
        }
        .navigationTitle(embedded ? "" : String(localized: "Connections"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !embedded {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showsScanner = true
                        } label: {
                            Label(String(localized: "Scan QR code", table: "ConnectionQRCode"), systemImage: "qrcode.viewfinder")
                        }

                        Button {
                            showsQRCode = true
                        } label: {
                            Label("Show my QR code", systemImage: "qrcode")
                        }

                        Button {
                            Task { await inviteByLink() }
                        } label: {
                            Label("Invite by link", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add connection")
                }
            }
        }
        .task {
            await socialStore.refreshConnections()
            await socialStore.refreshBlocks()
            if startsAdding {
                isSearchFocused = true
            }
        }
        .onChange(of: focusRequestID) { _, _ in
            isSearchFocused = true
        }
        .navigationDestination(isPresented: $showsQRCode) {
            SocialConnectionQRCodeView()
        }
        .navigationDestination(isPresented: $showsSearchResults) {
            SocialPeopleSearchResultsView(initialQuery: submittedSearchQuery)
        }
        .fullScreenCover(isPresented: $showsScanner) {
            SocialConnectionQRScannerView()
        }
        .task(id: searchQuery) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await performAutocompleteSearch()
        }
        .overlay(alignment: .top) {
            if let message = searchToast ?? paginationToast {
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: paginationToast)
        .animation(.snappy, value: searchToast)
        .task(id: paginationToast) {
            guard paginationToast != nil else { return }
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            paginationToast = nil
        }
        .task(id: searchToast) {
            guard searchToast != nil else { return }
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            searchToast = nil
        }
    }

    private var peopleSearchField: some View {
        HStack(spacing: OutboundSpacing.compact) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search name or username", text: $searchQuery)
                .focused($isSearchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { openSubmittedSearch() }
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    autocompleteResults = []
                    autocompleteFailed = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, OutboundSpacing.screen)
        .frame(minHeight: 52)
        .background(.bar)
    }

    private var showsAutocomplete: Bool {
        isSearchFocused && !TogetherStore.normalizedPeopleSearchQuery(searchQuery).isEmpty
    }

    private var autocompleteDropdown: some View {
        VStack(spacing: 0) {
            if isAutocompleteLoading && autocompleteResults.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .accessibilityLabel(String(localized: "Searching for people"))
            } else if autocompleteFailed {
                Button {
                    Task { await performAutocompleteSearch(force: true) }
                } label: {
                    Label(String(localized: "Search failed. Try again."), systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.plain)
            } else if autocompleteResults.isEmpty {
                Text(String(localized: "No people found"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 52)
            } else {
                ForEach(Array(autocompleteResults.prefix(5).enumerated()), id: \.element.id) { index, person in
                    SocialPeopleSearchRow(person: person, compact: true) { succeeded in
                        await handleSearchMutation(succeeded: succeeded)
                    }
                    if index < min(autocompleteResults.count, 5) - 1 {
                        Divider().padding(.leading, 58)
                    }
                }
                Button {
                    openSubmittedSearch()
                } label: {
                    HStack {
                        Text(String(localized: "See all results"))
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, OutboundSpacing.standard)
                    .frame(minHeight: 46)
                }
                .buttonStyle(.plain)
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
        .padding(.horizontal, OutboundSpacing.screen)
        .padding(.top, 8)
    }

    private var connectionsList: some View {
        List {
            if !incomingRequests.isEmpty {
                Section("Requests") {
                    ForEach(incomingRequests) { connection in
                        connectionRow(connection) {
                            Button {
                                Task { await socialStore.acceptConnection(connection) }
                            } label: {
                                Image(systemName: "checkmark")
                            }
                            .buttonStyle(SocialIconButtonStyle())
                            .disabled(socialStore.pendingConnectionIDs.contains(connection.id))
                            .accessibilityLabel("Accept connection request")

                            Button(role: .destructive) {
                                Task { await socialStore.removeConnection(connection) }
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(SocialIconButtonStyle(tint: .red))
                            .disabled(socialStore.pendingConnectionIDs.contains(connection.id))
                            .accessibilityLabel("Decline connection request")
                        }
                    }
                }
            }

            if !acceptedConnections.isEmpty {
                Section("Connections") {
                    ForEach(acceptedConnections) { connection in
                        connectionRow(connection) {
                            EmptyView()
                        }
                    }
                }
            }

            if socialStore.hasLoadedConnections && acceptedConnections.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(
                            String(localized: "social.people.empty.title", defaultValue: "Find your people"),
                            systemImage: "person.2.circle"
                        )
                        .font(.headline)
                        Text(String(localized: "social.people.empty.description", defaultValue: "Connect with friends to share activities, plan runs, and cheer each other on."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Button {
                            isSearchFocused = true
                            trackDiscoveryAction("find_people")
                        } label: {
                            Label(String(localized: "social.people.find", defaultValue: "Find people"), systemImage: "magnifyingglass")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            trackDiscoveryAction("invite_friend")
                            Task { await inviteByLink() }
                        } label: {
                            Label(String(localized: "social.people.invite", defaultValue: "Invite a friend"), systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            showsScanner = true
                            trackDiscoveryAction("scan_qr")
                        } label: {
                            Label(String(localized: "social.people.scan", defaultValue: "Scan QR"), systemImage: "qrcode.viewfinder")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 8)
                }
            }

            if !outgoingRequests.isEmpty {
                Section("Sent") {
                    ForEach(outgoingRequests) { connection in
                        connectionRow(connection) {
                            Button(role: .destructive) {
                                Task { await socialStore.removeConnection(connection) }
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(SocialIconButtonStyle(tint: .red))
                            .disabled(socialStore.pendingConnectionIDs.contains(connection.id))
                            .accessibilityLabel("Cancel connection request")
                        }
                    }
                }
            }

            if socialStore.hasMoreConnections {
                Section {
                    Button {
                        Task { await loadMoreConnections() }
                    } label: {
                        HStack {
                            Spacer()
                            if socialStore.isLoadingMoreConnections {
                                ProgressView()
                            } else {
                                Text(String(localized: "common.load_more", defaultValue: "Load more"))
                            }
                            Spacer()
                        }
                    }
                    .disabled(socialStore.isLoadingMoreConnections)
                    .accessibilityHint(String(localized: "social.connections.load_more.hint", defaultValue: "Shows more connections and requests."))
                }
            }

            if !socialStore.blocks.isEmpty {
                Section("Blocked") {
                    ForEach(socialStore.blocks) { block in
                        HStack {
                            SocialAvatar(name: block.person.displayName, avatarURL: block.person.avatarUrl)
                            Text(block.person.displayName)
                            Spacer()
                            Button {
                                Task { await socialStore.unblock(block) }
                            } label: {
                                Image(systemName: "person.crop.circle.badge.checkmark")
                            }
                            .buttonStyle(SocialIconButtonStyle())
                            .accessibilityLabel("Unblock \(block.person.displayName)")
                        }
                    }
                }
            }

        }
        .refreshable { await socialStore.refreshConnections() }
        .overlay {
            if socialStore.isConnectionsLoading && socialStore.connections.isEmpty {
                ProgressView()
            }
        }
    }

    private func trackDiscoveryAction(_ selection: String) {
        Task {
            await analyticsManager?.track(.init(.socialDiscoveryActionSelected, properties: [
                .selectionType: .string(selection),
                .entrySource: .string("people_empty"),
            ]))
        }
    }

    private func performAutocompleteSearch(force: Bool = false) async {
        let normalizedQuery = TogetherStore.normalizedPeopleSearchQuery(searchQuery)
        guard !normalizedQuery.isEmpty else {
            lastRequestedSearchQuery = nil
            autocompleteResults = []
            autocompleteFailed = false
            await socialStore.searchPeople("")
            return
        }
        guard force || normalizedQuery != lastRequestedSearchQuery else { return }
        lastRequestedSearchQuery = normalizedQuery
        isAutocompleteLoading = true
        autocompleteFailed = false

        let outcome = await socialStore.searchPeople(normalizedQuery)
        guard lastRequestedSearchQuery == normalizedQuery,
              TogetherStore.normalizedPeopleSearchQuery(searchQuery) == normalizedQuery else { return }

        isAutocompleteLoading = false
        autocompleteFailed = outcome == nil
        if outcome != nil {
            autocompleteResults = socialStore.peopleResults
        }

        if outcome == nil {
            lastRequestedSearchQuery = nil
        }
        await analyticsManager?.track(.init(.connectionsSearchCompleted, properties: [
            .sourceType: .string("autocomplete"),
            .inputScript: .string(Self.searchInputScript(normalizedQuery)),
            .queryLengthBucket: .string(ProductAnalyticsBucket.count(normalizedQuery.count)),
            .countBucket: .string(ProductAnalyticsBucket.count(outcome?.count ?? 0)),
            .matchMode: .string(outcome?.matchMode ?? "unavailable"),
            .result: .string(outcome == nil ? "failure" : "success")
        ]))
    }

    private func openSubmittedSearch() {
        let normalizedQuery = TogetherStore.normalizedPeopleSearchQuery(searchQuery)
        guard !normalizedQuery.isEmpty else { return }
        submittedSearchQuery = normalizedQuery
        isSearchFocused = false
        showsSearchResults = true
    }

    private func handleSearchMutation(succeeded: Bool) async {
        searchToast = succeeded
            ? String(localized: "Connection updated")
            : String(localized: "Could not update connection. Try again.")
        if succeeded {
            lastRequestedSearchQuery = nil
            await performAutocompleteSearch(force: true)
        }
    }

    nonisolated private static func searchInputScript(_ query: String) -> String {
        let meaningfulScalars = query.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        }
        let hasHan = meaningfulScalars.contains { $0.properties.isIdeographic }
        let hasNonHan = meaningfulScalars.contains { !$0.properties.isIdeographic }
        if hasHan && hasNonHan { return "mixed" }
        if hasHan { return "han" }
        if meaningfulScalars.allSatisfy(\.isASCII) { return "latin" }
        return "other"
    }

    private func loadMoreConnections() async {
        guard let appendedCount = await socialStore.loadMoreConnections() else {
            paginationToast = String(
                localized: "social.connections.load_more_failed",
                defaultValue: "Could not load more connections. Try again."
            )
            return
        }
        guard appendedCount > 0 else { return }
        let page = Int(ceil(Double(socialStore.connections.count) / Double(Self.pageSize)))
        await analyticsManager?.track(.init(.paginatedListPageLoaded, properties: [
            .sourceType: .string("connections"),
            .countBucket: .string(ProductAnalyticsBucket.count(appendedCount)),
            .pageDepthBucket: .string(ProductAnalyticsBucket.pageDepth(page))
        ]))
    }

    private func connectionRow<Actions: View>(
        _ connection: SocialConnectionDTO,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(spacing: OutboundSpacing.compact) {
            SocialProfileLink(
                person: connection.person,
                connection: connection,
                entrySource: "connections"
            ) {
                HStack(spacing: OutboundSpacing.compact) {
                    SocialAvatar(name: connection.person.displayName, avatarURL: connection.person.avatarUrl)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(connection.person.displayName).font(.headline).foregroundStyle(.primary)
                        Text("@\(connection.person.username)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            Spacer()
            actions()
        }
    }

    private func inviteByLink() async {
        guard let url = await socialStore.referralInvitationURL() else { return }
        await SystemSharePresenter.present(activityItems: [
            String(localized: "Join me for a run on Plainstride: \(url.absoluteString)"),
        ])
    }

}

private struct SocialPeopleSearchResultsView: View {
    @EnvironmentObject private var socialStore: TogetherStore
    @Environment(\.analyticsManager) private var analyticsManager
    @State private var query: String
    @State private var results: [SocialPersonSearchResultDTO] = []
    @State private var isLoading = false
    @State private var searchFailed = false
    @State private var toastMessage: String?
    @State private var lastRequestedQuery: String?
    @State private var hasPerformedInitialSearch = false
    @FocusState private var isSearchFocused: Bool

    init(initialQuery: String) {
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: OutboundSpacing.compact) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search name or username", text: $query)
                    .focused($isSearchFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { Task { await search(trigger: "submitted", force: true) } }
                if !query.isEmpty {
                    Button {
                        query = ""
                        results = []
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, OutboundSpacing.screen)
            .frame(minHeight: 52)
            .background(.bar)

            Divider()

            List(results) { person in
                SocialPeopleSearchRow(person: person, compact: false) { succeeded in
                    toastMessage = succeeded
                        ? String(localized: "Connection updated")
                        : String(localized: "Could not update connection. Try again.")
                    if succeeded { await search(trigger: "submitted", force: true) }
                }
            }
            .listStyle(.plain)
            .overlay {
                if isLoading && results.isEmpty {
                    ProgressView().accessibilityLabel(String(localized: "Searching for people"))
                } else if searchFailed {
                    ContentUnavailableView {
                        Label(String(localized: "Search failed"), systemImage: "wifi.exclamationmark")
                    } actions: {
                        Button("Try again") { Task { await search(trigger: "submitted", force: true) } }
                    }
                } else if !TogetherStore.normalizedPeopleSearchQuery(query).isEmpty && results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else if TogetherStore.normalizedPeopleSearchQuery(query).isEmpty {
                    ContentUnavailableView(
                        String(localized: "Search for people"),
                        systemImage: "person.2",
                        description: Text(String(localized: "Enter a name or username."))
                    )
                }
            }
        }
        .navigationTitle(String(localized: "Search people"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: query) {
            let trigger = hasPerformedInitialSearch ? "autocomplete" : "submitted"
            if hasPerformedInitialSearch {
                try? await Task.sleep(for: .milliseconds(300))
            }
            guard !Task.isCancelled else { return }
            await search(trigger: trigger, force: !hasPerformedInitialSearch)
            hasPerformedInitialSearch = true
        }
        .overlay(alignment: .top) {
            if let toastMessage {
                Label(toastMessage, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
                    .padding(.top, 8)
            }
        }
        .task(id: toastMessage) {
            guard toastMessage != nil else { return }
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            toastMessage = nil
        }
    }

    private func search(trigger: String, force: Bool = false) async {
        let normalizedQuery = TogetherStore.normalizedPeopleSearchQuery(query)
        guard !normalizedQuery.isEmpty else {
            lastRequestedQuery = nil
            results = []
            searchFailed = false
            return
        }
        guard force || normalizedQuery != lastRequestedQuery else { return }
        lastRequestedQuery = normalizedQuery
        isLoading = true
        searchFailed = false

        let outcome = await socialStore.searchPeople(normalizedQuery)
        guard lastRequestedQuery == normalizedQuery,
              TogetherStore.normalizedPeopleSearchQuery(query) == normalizedQuery else { return }
        isLoading = false
        searchFailed = outcome == nil
        if let outcome {
            results = socialStore.peopleResults
            await analyticsManager?.track(.init(.connectionsSearchCompleted, properties: [
                .sourceType: .string(trigger),
                .inputScript: .string(Self.searchInputScript(normalizedQuery)),
                .queryLengthBucket: .string(ProductAnalyticsBucket.count(normalizedQuery.count)),
                .countBucket: .string(ProductAnalyticsBucket.count(outcome.count)),
                .matchMode: .string(outcome.matchMode),
                .result: .string("success")
            ]))
        } else {
            lastRequestedQuery = nil
            await analyticsManager?.track(.init(.connectionsSearchCompleted, properties: [
                .sourceType: .string(trigger),
                .inputScript: .string(Self.searchInputScript(normalizedQuery)),
                .queryLengthBucket: .string(ProductAnalyticsBucket.count(normalizedQuery.count)),
                .countBucket: .string(ProductAnalyticsBucket.count(0)),
                .matchMode: .string("unavailable"),
                .result: .string("failure")
            ]))
        }
    }

    nonisolated private static func searchInputScript(_ query: String) -> String {
        let meaningfulScalars = query.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        let hasHan = meaningfulScalars.contains { $0.properties.isIdeographic }
        let hasNonHan = meaningfulScalars.contains { !$0.properties.isIdeographic }
        if hasHan && hasNonHan { return "mixed" }
        if hasHan { return "han" }
        if meaningfulScalars.allSatisfy(\.isASCII) { return "latin" }
        return "other"
    }
}

private struct SocialPeopleSearchRow: View {
    @EnvironmentObject private var socialStore: TogetherStore
    let person: SocialPersonSearchResultDTO
    let compact: Bool
    let onMutation: (Bool) async -> Void
    @State private var isMutating = false

    private var socialPerson: SocialPersonDTO {
        SocialPersonDTO(id: person.id, username: person.username, displayName: person.displayName, avatarUrl: person.avatarUrl)
    }

    private var connection: SocialConnectionDTO? {
        guard let relationship = person.relationship else { return nil }
        return SocialConnectionDTO(
            id: relationship.id,
            status: relationship.status,
            direction: relationship.direction,
            person: socialPerson
        )
    }

    var body: some View {
        HStack(spacing: OutboundSpacing.compact) {
            SocialProfileLink(
                person: socialPerson,
                connection: connection,
                entrySource: compact ? "connections_autocomplete" : "connections_search_results"
            ) {
                HStack(spacing: OutboundSpacing.compact) {
                    SocialAvatar(name: person.displayName, avatarURL: person.avatarUrl)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.displayName).font(.headline).foregroundStyle(.primary)
                        Text("@\(person.username)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            Spacer(minLength: 8)
            relationshipAction
        }
        .padding(.horizontal, compact ? OutboundSpacing.standard : 0)
        .frame(minHeight: 56)
        .disabled(isMutating)
        .opacity(isMutating ? 0.6 : 1)
    }

    @ViewBuilder
    private var relationshipAction: some View {
        switch (person.relationship?.status, person.relationship?.direction) {
        case ("accepted", _):
            Text("Connected")
                .font(.caption)
                .foregroundStyle(.secondary)
        case ("pending", "outgoing"):
            if compact {
                Text("Sent").font(.caption).foregroundStyle(.secondary)
            } else if let connection {
                Button(role: .destructive) { mutate { await socialStore.removeConnection(connection) } } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(SocialIconButtonStyle(tint: .red))
                .accessibilityLabel(String(localized: "Cancel connection request"))
            }
        case ("pending", "incoming"):
            if let connection {
                Button { mutate { await socialStore.acceptConnection(connection) } } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(SocialIconButtonStyle())
                .accessibilityLabel(String(localized: "Accept connection request"))
                if !compact {
                    Button(role: .destructive) { mutate { await socialStore.removeConnection(connection) } } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(SocialIconButtonStyle(tint: .red))
                    .accessibilityLabel(String(localized: "Decline connection request"))
                }
            }
        default:
            Button { mutate { await socialStore.requestConnection(to: person) } } label: {
                Image(systemName: "person.badge.plus")
            }
            .buttonStyle(SocialIconButtonStyle())
            .accessibilityLabel(String(localized: "Connect with \(person.displayName)"))
        }
    }

    private func mutate(_ operation: @escaping () async -> Bool) {
        guard !isMutating else { return }
        isMutating = true
        Task {
            let succeeded = await operation()
            isMutating = false
            await onMutation(succeeded)
        }
    }
}

struct SocialPersonProfileView: View {
    @EnvironmentObject private var socialStore: TogetherStore
    @EnvironmentObject private var socialRecognitionStore: SocialRecognitionStore
    let person: TogetherPersonDTO
    var username: String? = nil
    @State private var sharedRecognitions: [RecognitionAwardDTO] = []

    private var posts: [TogetherPostDTO] {
        socialStore.state.posts.filter { $0.user.id == person.id }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                VStack(spacing: OutboundSpacing.compact) {
                    SocialAvatar(name: person.displayName, avatarURL: person.avatarUrl)
                        .scaleEffect(2)
                        .frame(width: 80, height: 80)
                    Text(person.displayName).font(.title2.weight(.semibold))
                    if let username { Text("@\(username)").font(.subheadline).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, OutboundSpacing.standard)

                if !sharedRecognitions.isEmpty {
                    Text(String(localized: "social.profile.milestones", defaultValue: "MILESTONES"))
                        .socialSectionLabel()
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: OutboundSpacing.compact) {
                            ForEach(sharedRecognitions, id: \.id) { award in
                                let display = recognitionDisplay(for: award.badgeId)
                                VStack(spacing: 6) {
                                    Image(systemName: display.symbolName)
                                        .font(.headline)
                                        .foregroundStyle(OutboundPalette.companion)
                                        .frame(width: 42, height: 42)
                                        .background(OutboundPalette.companion.opacity(0.12), in: Circle())
                                    Text(display.title)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                }
                                .frame(width: 86)
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }

                Text("RECENT ACTIVITIES").socialSectionLabel()
                if posts.isEmpty {
                    OutboundCard {
                        Text("No shared activities yet.").font(.subheadline).foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(posts) { post in
                        NavigationLink {
                            SocialActivityDetailView(post: post)
                        } label: {
                            OutboundCard {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(post.activity?.title ?? String(localized: "Run")).font(.headline).foregroundStyle(.primary)
                                        Text(post.activityTimestamp.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(OutboundSpacing.screen)
        }
        .background(OutboundPalette.background)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: person.id) {
            if let response = try? await APIClient.shared.fetchSocialProfile(userID: person.id) {
                sharedRecognitions = response.recognitions
            }
        }
    }

    private func recognitionDisplay(for badgeID: String) -> (title: String, symbolName: String) {
        if let primaryID = RecognitionBadgeID(rawValue: badgeID) {
            let definition = RecognitionStore.definition(for: primaryID)
            return (definition.title, definition.symbolName)
        }
        if let socialID = SocialRecognitionBadgeID(rawValue: badgeID) {
            let preview = socialRecognitionStore.preview(for: socialID)
            return (preview.title, preview.symbolName)
        }
        return (String(localized: "recognition.title", defaultValue: "Recognition"), "sparkles")
    }
}

private struct SocialActivityCardNavigation: ViewModifier {
    @Binding var post: TogetherPostDTO?

    func body(content: Content) -> some View {
        content.navigationDestination(isPresented: Binding(
            get: { post != nil },
            set: { if !$0 { post = nil } }
        )) {
            if let post {
                SocialActivityDetailView(post: post)
            }
        }
    }
}

private struct SocialActivityDetailView: View {
    @EnvironmentObject private var socialStore: TogetherStore
    @EnvironmentObject private var socialRecognitionStore: SocialRecognitionStore
    let post: TogetherPostDTO
    @State private var showsComments = false
    @State private var showsCheers = false
    @State private var toastMessage: String?

    private var currentPost: TogetherPostDTO {
        socialStore.state.posts.first(where: { $0.id == post.id }) ?? post
    }

    @ViewBuilder
    var body: some View {
        if let activity = currentPost.activity {
            ActivityDetailView(
                activity: activity.savedActivity(postCreatedAt: currentPost.createdAt),
                usesStoredActivity: false,
                showsShareControl: currentPost.isCurrentUser,
                showsEditControl: false,
                showsPrivateDetails: false,
                routePublicationActivityID: currentPost.isCurrentUser ? activity.id : nil,
                supplementalContent: AnyView(socialCard),
                bottomContent: AnyView(socialCompanionCard)
            )
            .sheet(isPresented: $showsCheers) {
                SocialCheersListView(post: currentPost)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showsComments) {
                SocialCommentsView(post: currentPost)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .overlay(alignment: .top) {
                if let toastMessage {
                    Text(toastMessage)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        } else {
            ContentUnavailableView(
                String(localized: "Activity unavailable"),
                systemImage: "figure.run",
                description: Text(String(localized: "This shared activity is no longer available."))
            )
        }
    }

    private var socialCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SocialProfileLink(person: currentPost.user, entrySource: "social_activity_detail") {
                HStack(spacing: 12) {
                    SocialAvatar(name: currentPost.user.displayName, avatarURL: currentPost.user.avatarUrl)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(currentPost.user.displayName).font(.headline).foregroundStyle(.primary)
                        Text(currentPost.activityTimestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
            }

            if let caption = currentPost.caption, !caption.isEmpty {
                Text(caption).font(.body)
            }

            socialActionBar

        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private var socialActionBar: some View {
        HStack(spacing: OutboundSpacing.compact) {
            Button {
                Task { await toggleCheer() }
            } label: {
                Image(systemName: currentPost.currentUserCheered ? "heart.fill" : "heart")
            }
            .buttonStyle(SocialFeedActionButtonStyle(isActive: currentPost.currentUserCheered))
            .disabled(socialStore.isSocialMutationPending)
            .accessibilityLabel(currentPost.currentUserCheered ? String(localized: "Remove cheer") : String(localized: "Cheer"))
            .accessibilityValue("\(currentPost.reactionCount)")

            if currentPost.reactionCount > 0 {
                SocialCheerAvatarsButton(post: currentPost) {
                    showsCheers = true
                }
            }

            Button { showsComments = true } label: {
                Label("\(currentPost.commentCount)", systemImage: "bubble.left")
            }
            .buttonStyle(SocialFeedActionButtonStyle())
            .accessibilityLabel(String(localized: "Comments"))
            .accessibilityValue("\(currentPost.commentCount)")

            Spacer()
        }
    }

    private var socialCompanionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                Text(String(localized: "activity.social.companion.title", defaultValue: "Great hustle."))
                    .font(.subheadline.weight(.semibold))
                Text(String(localized: "activity.guide.companion", defaultValue: "Your companion"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.orange)

            Text(String(localized: "\(currentPost.user.displayName) put in a strong effort. Send a cheer to keep the momentum going!"))
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private func toggleCheer() async {
        let addsSupport = !currentPost.currentUserCheered
        guard await socialStore.toggleCheer(on: currentPost) else {
            withAnimation { toastMessage = String(localized: "Could not update cheer. Try again.") }
            return
        }
        if addsSupport { _ = socialRecognitionStore.registerSupport(for: currentPost.id) }
    }
}

private extension TogetherActivityDTO {
    func savedActivity(postCreatedAt: Date) -> SavedActivity {
        let duration = max(0, durationSecs ?? 0)
        let resolvedStartedAt = startedAt ?? postCreatedAt.addingTimeInterval(TimeInterval(-duration))
        let resolvedEndedAt = endedAt ?? resolvedStartedAt.addingTimeInterval(TimeInterval(duration))
        let coordinates = route?.coordinates ?? []
        let routePoints = coordinates.enumerated().compactMap { index, coordinate -> SavedRoutePoint? in
            guard coordinate.count >= 2 else { return nil }
            let progress = coordinates.count > 1 ? Double(index) / Double(coordinates.count - 1) : 0
            let fallbackTimestamp = resolvedStartedAt.addingTimeInterval(TimeInterval(duration) * progress)
            return SavedRoutePoint(
                timestamp: fallbackTimestamp,
                latitude: coordinate[1],
                longitude: coordinate[0],
                altitude: nil,
                verticalAccuracy: nil
            )
        }
        let savedPhotos = (photos ?? []).compactMap { photo -> SavedPhoto? in
            guard let clientPhotoID = UUID(uuidString: photo.clientPhotoId),
                  let url = photo.url.map({ APIClient.shared.mediaURL($0) }) else { return nil }
            let coordinate = photo.latitude.flatMap { latitude in
                photo.longitude.map { longitude in
                    SavedCoordinate(latitude: latitude, longitude: longitude)
                }
            }
            return SavedPhoto(
                id: clientPhotoID,
                takenAt: photo.takenAt,
                paceAtShot: photo.paceAtShot,
                hrAtShot: photo.hrAtShot,
                distAtShot: photo.distAtShot ?? 0,
                coordinate: coordinate,
                captureContext: photo.captureContext.flatMap(PhotoCaptureContext.init(rawValue:)) ?? .active,
                relativePath: url.absoluteString,
                remotePhotoId: photo.id,
                remoteUploadedAt: photo.takenAt
            )
        }
        return SavedActivity(
            id: UUID(uuidString: id) ?? UUID(),
            activityType: type.flatMap(ActivityType.init(rawValue:)) ?? .running,
            title: title ?? String(localized: "Activity"),
            guideNudge: "",
            reflection: nil,
            createdAt: postCreatedAt,
            startedAt: resolvedStartedAt,
            endedAt: resolvedEndedAt,
            durationSecs: duration,
            distanceM: max(0, distanceM ?? 0),
            avgPace: avgPace,
            elevationGainM: elevationM,
            energyKilocalories: energyKilocalories,
            route: routePoints.isEmpty ? nil : SavedRoute(points: routePoints),
            photos: savedPhotos,
            sync: nil
        )
    }

}

struct SocialCheerAvatarsButton: View {
    let post: TogetherPostDTO
    let action: () -> Void

    private var displayedCheerers: [SocialPersonDTO] {
        Array(post.cheers.prefix(3))
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                HStack(spacing: -6) {
                    ForEach(displayedCheerers) { cheerer in
                        SocialAvatar(name: cheerer.displayName, avatarURL: cheerer.avatarUrl, size: 24)
                            .overlay(
                                Circle().strokeBorder(Color(.systemBackground), lineWidth: 1.5)
                            )
                    }
                    if post.reactionCount > displayedCheerers.count {
                        ZStack {
                            Circle().fill(Color(.secondarySystemBackground))
                            Text("+\(post.reactionCount - displayedCheerers.count)")
                                .font(.caption2.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle().strokeBorder(Color(.systemBackground), lineWidth: 1.5)
                        )
                    }
                }
                .accessibilityHidden(true)

                Text("\(post.reactionCount)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "activity.social.cheer_count", defaultValue: "Cheers"))
        .accessibilityValue("\(post.reactionCount)")
        .accessibilityHint(String(localized: "activity.social.cheer_count.hint", defaultValue: "Shows the full list of people who cheered"))
    }
}

struct SocialCheersListView: View {
    @Environment(\.dismiss) private var dismiss
    let post: TogetherPostDTO

    var body: some View {
        NavigationStack {
            Group {
                if post.cheers.isEmpty {
                    ContentUnavailableView(
                        String(localized: "activity.social.cheer_count", defaultValue: "Cheers"),
                        systemImage: "heart",
                        description: Text(String(localized: "activity.social.cheers.empty", defaultValue: "No cheers yet. Be the first to send one."))
                    )
                } else {
                    List(post.cheers) { cheerer in
                        SocialProfileLink(person: cheerer, entrySource: "social_activity_cheers") {
                            HStack(spacing: 12) {
                                SocialAvatar(name: cheerer.displayName, avatarURL: cheerer.avatarUrl)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(cheerer.displayName).font(.subheadline.weight(.semibold))
                                    if !cheerer.username.isEmpty {
                                        Text("@\(cheerer.username)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(String(localized: "activity.social.cheer_count", defaultValue: "Cheers"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(String(localized: "Close", defaultValue: "Close"))
                }
            }
        }
    }
}

struct SocialAvatar: View {
    let name: String
    let avatarURL: String?
    var size: CGFloat = 40
    @StateObject private var loader: AvatarImageLoader

    init(name: String, avatarURL: String?, size: CGFloat = 40) {
        self.name = name
        self.avatarURL = avatarURL
        self.size = size
        _loader = StateObject(wrappedValue: AvatarImageLoader(url: avatarURL))
    }

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(OutboundPalette.companion.opacity(0.15))
                    Text(initials).font(.caption.weight(.semibold))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityLabel(name)
        .task(id: avatarURL) { await loader.load(url: avatarURL) }
    }

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }
}

private struct SocialRoutePreviewImage: View {
    let activity: TogetherActivityDTO

    @State private var image: UIImage?

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    placeholder
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1.5, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityLabel("Activity route preview")
        .task(id: SocialRoutePreviewCache.cacheKey(for: activity)) {
            guard activity.route?.coordinates.count ?? 0 > 1 else { return }
            guard let data = await SocialRoutePreviewCache.shared.imageData(for: activity),
                  !Task.isCancelled else { return }
            image = UIImage(data: data)
        }
    }

    private var placeholder: some View {
        LinearGradient(
            colors: [OutboundPalette.companion.opacity(0.28), OutboundPalette.background],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(OutboundPalette.companion.opacity(0.65))
        }
    }
}

private actor SocialRoutePreviewCache {
    static let shared = SocialRoutePreviewCache()

    private static let imageSize = CGSize(width: 720, height: 480)
    private static let maxRoutePoints = 360
    private static let memoryLimit = 24

    private var memory: [String: Data] = [:]
    private var inFlight: [String: Task<Data?, Never>] = [:]
    private var generationTail: Task<Void, Never> = Task {}

    static func cacheKey(for activity: TogetherActivityDTO) -> String {
        let coordinates = activity.route?.coordinates ?? []
        let stride = max(1, Int(ceil(Double(coordinates.count) / Double(maxRoutePoints))))
        let sampledCoordinates = coordinates.enumerated().compactMap { index, coordinate in
            index.isMultiple(of: stride) || index == coordinates.count - 1
                ? coordinate
                : nil
        }
        let routeSignature = sampledCoordinates.map { coordinate in
            coordinate.prefix(2).map { String(format: "%.6f", $0) }.joined(separator: ",")
        }.joined(separator: ";")
        let raw = "v3|\(activity.id)|\(coordinates.count)|\(routeSignature)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func imageData(for activity: TogetherActivityDTO) async -> Data? {
        let key = Self.cacheKey(for: activity)
        if let data = memory[key] { return data }
        if let data = Self.readCachedData(for: key) {
            remember(data, for: key)
            return data
        }
        if let task = inFlight[key] { return await task.value }

        let previous = generationTail
        let task = Task<Data?, Never> { [weak self] in
            _ = await previous.value
            guard let self else { return nil }
            return await self.generate(activity: activity, key: key)
        }
        inFlight[key] = task
        generationTail = Task { _ = await task.value }
        let data = await task.value
        inFlight[key] = nil
        return data
    }

    private func generate(activity: TogetherActivityDTO, key: String) async -> Data? {
        let coordinates = (activity.route?.coordinates ?? []).compactMap { value -> CLLocationCoordinate2D? in
            guard value.count >= 2,
                  value[0].isFinite,
                  value[1].isFinite,
                  (-180...180).contains(value[0]),
                  (-90...90).contains(value[1]) else { return nil }
            return CLLocationCoordinate2D(latitude: value[1], longitude: value[0])
        }
        guard coordinates.count > 1 else { return nil }

        let stride = max(1, Int(ceil(Double(coordinates.count) / Double(Self.maxRoutePoints))))
        let route = coordinates.enumerated().compactMap { index, coordinate in
            index.isMultiple(of: stride) || index == coordinates.count - 1
                ? coordinate
                : nil
        }

        let options = MKMapSnapshotter.Options()
        options.size = Self.imageSize
        options.scale = 2
        options.mapType = .standard
        options.pointOfInterestFilter = .excludingAll
        options.showsBuildings = false
        // Fit the route to the snapshot's aspect ratio before adding breathing room.
        // Passing an independently padded MKCoordinateRegion lets MapKit adjust the
        // region again for the image size, which can place the final point outside
        // the rendered image on tall or asymmetric routes.
        options.mapRect = Self.mapRect(for: route, size: Self.imageSize)
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }

        let projectedRoute = route.map(snapshot.point(for:))
        let projectedBounds = projectedRoute.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
        // The feed lays a translucent stats panel over the bottom of this image.
        // Keep the complete route above that panel so its finish is not obscured.
        let bottomOverlayReservation: CGFloat = 160
        let drawingBounds = CGRect(
            x: 24,
            y: 24,
            width: Self.imageSize.width - 48,
            height: Self.imageSize.height - bottomOverlayReservation - 24
        )
        let fitScale = min(
            drawingBounds.width / max(projectedBounds.width, 1),
            drawingBounds.height / max(projectedBounds.height, 1)
        )
        let fitOffset = CGPoint(
            x: drawingBounds.midX - projectedBounds.midX * fitScale,
            y: drawingBounds.midY - projectedBounds.midY * fitScale
        )
        func fittedPoint(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x * fitScale + fitOffset.x, y: point.y * fitScale + fitOffset.y)
        }

        let renderer = UIGraphicsImageRenderer(size: Self.imageSize)
        let image = renderer.image { context in
            snapshot.image.draw(in: CGRect(origin: .zero, size: Self.imageSize))
            let path = CGMutablePath()
            for (index, point) in projectedRoute.enumerated() {
                let fitted = fittedPoint(point)
                if index == 0 { path.move(to: fitted) } else { path.addLine(to: fitted) }
            }
            context.cgContext.addPath(path)
            context.cgContext.setStrokeColor(UIColor.white.withAlphaComponent(0.92).cgColor)
            context.cgContext.setLineWidth(14)
            context.cgContext.setLineCap(.round)
            context.cgContext.setLineJoin(.round)
            context.cgContext.strokePath()
            context.cgContext.addPath(path)
            context.cgContext.setStrokeColor(UIColor.systemOrange.cgColor)
            context.cgContext.setLineWidth(8)
            context.cgContext.strokePath()
        }
        guard let data = image.jpegData(compressionQuality: 0.82) else { return nil }
        remember(data, for: key)
        Self.writeCachedData(data, for: key)
        return data
    }

    private static func mapRect(for coordinates: [CLLocationCoordinate2D], size: CGSize) -> MKMapRect {
        var rect = coordinates.reduce(MKMapRect.null) { rect, coordinate in
            let point = MKMapPoint(coordinate)
            return rect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
        }

        guard !rect.isNull, rect.width > 0, rect.height > 0,
              size.width > 0, size.height > 0 else { return rect }

        // MKMapSnapshotter preserves the requested map rect's aspect ratio only
        // approximately. Expand the short dimension explicitly so every route
        // point remains inside the image even for very tall or very wide routes.
        let targetAspect = size.width / size.height
        let currentAspect = rect.width / rect.height
        if currentAspect > targetAspect {
            let targetHeight = rect.width / targetAspect
            rect = rect.insetBy(dx: 0, dy: -(targetHeight - rect.height) / 2)
        } else {
            let targetWidth = rect.height * targetAspect
            rect = rect.insetBy(dx: -(targetWidth - rect.width) / 2, dy: 0)
        }

        let padding = min(rect.width, rect.height) * 0.12
        return rect.insetBy(dx: -max(padding, 1_500), dy: -max(padding, 1_500))
    }

    private func remember(_ data: Data, for key: String) {
        memory[key] = data
        if memory.count > Self.memoryLimit, let oldest = memory.keys.first {
            memory.removeValue(forKey: oldest)
        }
    }

    private static func cacheDirectory() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("SocialRoutePreviews", isDirectory: true)
    }

    private static func readCachedData(for key: String) -> Data? {
        guard let directory = cacheDirectory() else { return nil }
        return try? Data(contentsOf: directory.appendingPathComponent("\(key).jpg"))
    }

    private static func writeCachedData(_ data: Data, for key: String) {
        guard let directory = cacheDirectory() else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent("\(key).jpg"), options: .atomic)
    }
}

private struct SocialMilestoneCard: View {
    let preview: SocialRecognitionPreview

    var body: some View {
        OutboundCard {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.orange, .yellow],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: preview.symbolName)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 42, height: 42)
                .shadow(color: .orange.opacity(0.22), radius: 7, y: 3)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Milestone unlocked")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                    Text(preview.title)
                        .font(.headline)
                    Text(preview.guideLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SocialFeedActionButtonStyle: ButtonStyle {
    var isActive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isActive ? Color.pink : Color.secondary)
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .background(
                (isActive ? Color.pink : OutboundPalette.companion)
                    .opacity(configuration.isPressed ? 0.18 : 0.08),
                in: Capsule()
            )
            .contentShape(Capsule())
    }
}

private struct SocialIconButtonStyle: ButtonStyle {
    var tint: Color = OutboundPalette.companion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
            .background(tint.opacity(configuration.isPressed ? 0.2 : 0.1), in: Circle())
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

extension Text {
    func socialSectionLabel() -> some View {
        font(.caption.weight(.semibold)).foregroundStyle(.secondary)
    }
}

private func localizedCircleNotificationMessage(_ notification: SocialNotificationDTO) -> String {
    let actorName = notification.actor?.displayName ?? String(localized: "circle.notification.someone", defaultValue: "Someone")
    switch notification.type {
    case "circleInvitation":
        return String(format: String(localized: "group.notification.invitation", defaultValue: "%@ invited you to a Group."), actorName)
    case "circleInvitationAccepted":
        return String(format: String(localized: "group.notification.accepted", defaultValue: "%@ joined your Group."), actorName)
    case "circleCheer":
        return String(format: String(localized: "circle.notification.cheer", defaultValue: "%@ sent you a Cheer."), actorName)
    case "circleWeeklyGoalCompleted":
        return String(localized: "group.notification.weekly_complete", defaultValue: "Your Group completed this week’s theme.")
    case "circleOwnershipTransferred":
        return String(format: String(localized: "group.notification.ownership", defaultValue: "%@ made you the Group owner."), actorName)
    default:
        return notification.message
    }
}
