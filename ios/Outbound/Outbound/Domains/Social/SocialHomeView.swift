import MapKit
import SwiftUI

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
    @State private var selectedCommentPost: TogetherPostDTO?
    @State private var isCreateActivityEventPresented = false
    @State private var showsNotifications = false
    @State private var showsConnections = false
    @State private var pushedLiveCheerSessionID: String?
    @State private var toastMessage: String?
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

    private var syncedActivityIDs: [String] {
        activityStore.activities.compactMap(\.sync?.serverActivityId).sorted()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                    if !liveCheerStore.sessions.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Cheer someone on").socialSectionLabel()
                            ForEach(liveCheerStore.sessions) { session in
                                NavigationLink {
                                    LiveCheerView(sessionID: session.id)
                                } label: {
                                    liveCheerRow(name: session.runner.displayName)
                                }
                            }
                        }
                    }
                    if let incomingRequest = socialStore.connections.first(where: {
                        $0.status == "pending" && $0.direction == "incoming"
                    }) {
                        incomingRequestCard(incomingRequest)
                    }

                    if !socialStore.hasLoadedConnections {
                        connectionsLoadingSection
                    } else if shouldShowConnectionPrompt {
                        connectionGrowthCard
                    } else if !acceptedConnections.isEmpty {
                        connectionsSection
                    }

                    yourCircleSection

                    if let milestone = socialRecognitionStore.highlight {
                        SocialMilestoneCard(preview: milestone)
                    }

                    upcomingRuns
                    pastActivityEvents
                    joinedClubs
                    recentPosts
                }
                .padding(OutboundSpacing.screen)
            }
            .background(OutboundPalette.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    GlobalConditionsButton()

                    Menu {
                        NavigationLink {
                            SocialGroupsView()
                        } label: {
                            Label("Groups", systemImage: "person.3")
                        }

                        NavigationLink {
                            CommunityRouteLibraryView()
                        } label: {
                            Label("Explore routes", systemImage: "map")
                        }
                    } label: {
                        Image(systemName: "person.2.circle")
                    }
                    .accessibilityLabel("Social community")

                    Button {
                        showsNotifications = true
                    } label: {
                        Image(systemName: socialStore.showsNotificationBadge ? "bell.badge.fill" : "bell")
                    }
                    .accessibilityLabel("Social notifications")
                    .accessibilityValue(socialStore.pendingInvitationCount > 0
                        ? String(localized: "\(socialStore.pendingInvitationCount) pending invitations")
                        : "")
                }
            }
            .refreshable {
                async let homeRefresh: Void = socialStore.refresh()
                async let connectionsRefresh: Void = socialStore.refreshConnections()
                async let circleRefresh: Void = circleStore.refresh()
                async let invitationRefresh: Void = circleStore.refreshInvitations()
                _ = await (homeRefresh, connectionsRefresh, circleRefresh, invitationRefresh)
            }
            .task {
                async let liveCheers: Void = liveCheerStore.refreshSessions()
                async let connectionsRefresh: Void = socialStore.refreshConnections()
                async let notificationsRefresh: Void = socialStore.refreshNotifications()
                async let circleRefresh: Void = circleStore.refresh()
                async let circleInvitations: Void = circleStore.refreshInvitations()
                _ = await (connectionsRefresh, notificationsRefresh, circleRefresh, circleInvitations, liveCheers)
            }
            .onChange(of: shouldShowConnectionPrompt, initial: true) { _, showsPrompt in
                guard showsPrompt else { return }
                Task {
                    await analyticsManager?.track(.init(.featureExposed, properties: [
                        .feature: .string("social_connection_growth_prompt"),
                    ]))
                }
            }
            .onChange(of: acceptedConnections.isEmpty, initial: true) { _, isEmpty in
                guard socialStore.hasLoadedConnections, !isEmpty else { return }
                Task {
                    await analyticsManager?.track(.init(.featureExposed, properties: [
                        .feature: .string("social_connections_section"),
                    ]))
                }
            }
            .onChange(of: socialStore.hasLoadedConnections, initial: true) { _, loaded in
                guard loaded else { return }
                Task { await analyticsManager?.track(.init(.circleSectionExposed, properties: [
                    .entrySource: .string("social"),
                    .participantCountBucket: .string(ProductAnalyticsBucket.count(circleStore.primaryCircle?.memberCount ?? 0))
                ])) }
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
            .navigationDestination(item: $pushedLiveCheerSessionID) { sessionID in
                LiveCheerView(sessionID: sessionID, entrySource: "push")
            }
            .onChange(of: pushNotifications.pendingNotificationID, initial: true) { _, notificationID in
                guard notificationID != nil else { return }
                if pushNotifications.pendingNotificationType == "liveCheerInvitation",
                   let sessionID = pushNotifications.pendingObjectID,
                   !sessionID.isEmpty {
                    pushedLiveCheerSessionID = sessionID
                    trackPushOpen(type: "live_cheer_invitation", destination: "live_cheer")
                    pushNotifications.consumePendingNotification()
                } else if pushNotifications.pendingNotificationType == "connectionRequest" {
                    showsConnections = true
                    trackPushOpen(type: "connection_request", destination: "connections")
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
            .sheet(isPresented: $isCreateActivityEventPresented) {
                CreateActivityEventView()
                    .environmentObject(socialStore)
            }
        }
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
            Text(String(localized: "circle.section.title", defaultValue: "Your Circle"))
                .socialSectionLabel()
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
                                Text(String(localized: "circle.create.inspiration_title", defaultValue: "Active. Positive. Together."))
                                    .font(.title3.bold())
                                    .foregroundStyle(.primary)
                                Text(String(localized: "circle.create.detail", defaultValue: "Share goals and progress with the people closest to you—and cheer each other on."))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(String(localized: "circle.create.start", defaultValue: "Create your Circle"))
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
                        CircleCompactCard(circle: circle, isPrimary: circle.id == circleStore.primaryCircleID)
                    }
                    .buttonStyle(.plain)
                }
                if socialStore.hasLoadedConnections, !acceptedConnections.isEmpty {
                    NavigationLink {
                        CircleCreateView()
                    } label: {
                        Label(String(localized: "circle.create.another", defaultValue: "Create another Circle"), systemImage: "plus.circle")
                            .frame(minHeight: 44)
                    }
                }
            }
        }
    }

    private func circleInvitationCard(_ invitation: CircleInvitationDTO) -> some View {
        OutboundCard(style: .companion) {
            VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                Text(String(localized: "circle.invitation.title", defaultValue: "You’re invited to a Circle"))
                    .font(.headline)
                Text(String(
                    format: String(localized: "circle.invitation.from", defaultValue: "%@ invited you to %@"),
                    invitation.sender.displayName,
                    invitation.circle.name
                ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(String(localized: "circle.invitation.promise", defaultValue: "Share workouts, encourage each other, and build a healthier week together."))
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

    private var connectionsSection: some View {
        VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
            HStack {
                Text("Connections").socialSectionLabel()
                Spacer()
                Button("All", action: openConnections)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OutboundPalette.companion)
            }

            OutboundCard {
                ScrollView(.horizontal) {
                    HStack(spacing: OutboundSpacing.standard) {
                        ForEach(acceptedConnections.prefix(8)) { connection in
                            SocialProfileLink(
                                person: connection.person,
                                connection: connection,
                                entrySource: "social_connections_section"
                            ) {
                                VStack(spacing: 6) {
                                    ZStack(alignment: .bottomTrailing) {
                                        SocialAvatar(
                                            name: connection.person.displayName,
                                            avatarURL: connection.person.avatarUrl
                                        )
                                        if connection.isInActiveWorkout == true {
                                            Circle()
                                                .fill(.green)
                                                .frame(width: 12, height: 12)
                                                .overlay {
                                                    Circle().stroke(OutboundPalette.surface, lineWidth: 2)
                                                }
                                        }
                                    }
                                    Text(connection.firstName)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                        .frame(width: 58)
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityValue(connection.isInActiveWorkout == true ? String(localized: "Workout in progress") : "")
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var connectionsLoadingSection: some View {
        VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
            HStack {
                Text("Connections").socialSectionLabel()
                Spacer()
                Text("All")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OutboundPalette.companion)
            }

            OutboundCard {
                HStack(spacing: OutboundSpacing.standard) {
                    ForEach(0..<4, id: \.self) { _ in
                        VStack(spacing: 6) {
                            Circle()
                                .fill(OutboundPalette.companion.opacity(0.12))
                                .frame(width: 40, height: 40)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.secondary.opacity(0.12))
                                .frame(width: 48, height: 12)
                        }
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func openConnections() {
        showsConnections = true
        Task {
            await analyticsManager?.track(.init(.connectionsOpened, properties: [
                .entrySource: .string("social_home_preview"),
            ]))
        }
    }

    @ViewBuilder
    private var upcomingRuns: some View {
        HStack {
            Text("UPCOMING").socialSectionLabel()
            Spacer()
            NavigationLink {
                SocialActivityDiscoveryView()
            } label: {
                Text("Discover")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(OutboundPalette.companion)
            Button {
                isCreateActivityEventPresented = true
            } label: {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .background(OutboundPalette.companion.opacity(0.12), in: Circle())
            }
            .foregroundStyle(OutboundPalette.companion)
            .accessibilityLabel("Plan a run")
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
                                    Text(run.startsAt.formatted(date: .abbreviated, time: .shortened) + locationSuffix(run.locationName))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    if let note = run.paceNote {
                                        Text(note).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.trailing, 44)

                                VStack(alignment: .leading, spacing: 4) {
                                    Label("Meet up or join from anywhere", systemImage: "person.2.wave.2")
                                    Text("People going: \(run.attendeeCount ?? 0)")
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
                                        Task { await socialStore.deletePost(post) }
                                    }
                                } else {
                                    Button("Report post", role: .destructive) {
                                        Task { await socialStore.reportPost(post, reason: "other") }
                                    }
                                    Button("Block \(post.user.displayName)", role: .destructive) {
                                        Task { await socialStore.blockAuthor(of: post) }
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
                        NavigationLink {
                            SocialActivityDetailView(post: post)
                        } label: {
                            VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                                Text(post.activity?.title ?? String(localized: "Run")).font(.headline).foregroundStyle(.primary)
                                if let activity = post.activity {
                                    ZStack(alignment: .bottom) {
                                        SocialRouteMap(route: activity.route)
                                        HStack(spacing: 0) {
                                            socialStat(activity.distanceM.map { measurementPreferences.unitSystem.distanceString(meters: $0, fractionDigits: 1) } ?? "—", "Distance")
                                            socialStat(activity.durationSecs.map(socialDuration) ?? "—", "Time")
                                            socialStat(activity.avgPace.map { $0.paceString(for: measurementPreferences.unitSystem) } ?? "—", "Pace")
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .background(.regularMaterial)
                                    }
                                    .frame(height: 210)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(alignment: .topLeading) {
                                        if let milestone = milestone(for: activity, isCurrentUser: post.isCurrentUser) {
                                            RecognitionPill(preview: milestone, compact: true).padding(12)
                                        }
                                    }
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if let caption = post.caption, !caption.isEmpty {
                            Text(caption).font(.subheadline)
                        }
                        HStack(spacing: OutboundSpacing.compact) {
                            Button {
                                Task { await toggleCheer(on: post) }
                            } label: {
                                Label("\(post.reactionCount)", systemImage: post.currentUserCheered ? "heart.fill" : "heart")
                            }
                            .buttonStyle(SocialFeedActionButtonStyle(isActive: post.currentUserCheered))
                            .disabled(socialStore.isSocialMutationPending)
                            .accessibilityLabel(post.currentUserCheered ? "Remove cheer" : "Cheer")
                            .accessibilityValue("\(post.reactionCount)")

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
                            Label("Meet up or join from anywhere", systemImage: "person.2.wave.2")
                                .font(.caption)
                                .foregroundStyle(OutboundPalette.companion)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Discover activities")
        .refreshable { await socialStore.refresh() }
    }
}

private struct SocialGroupsView: View {
    @EnvironmentObject private var socialStore: TogetherStore
    @EnvironmentObject private var socialRecognitionStore: SocialRecognitionStore

    var body: some View {
        List(socialStore.discoverableGroups) { group in
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
                if let description = group.description { Text(description).font(.subheadline) }
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("Groups")
        .overlay {
            if socialStore.discoverableGroups.isEmpty {
                ContentUnavailableView("No groups yet", systemImage: "person.3", description: Text("Discoverable running groups will appear here."))
            }
        }
        .task { await socialStore.refreshGroups() }
        .refreshable { await socialStore.refreshGroups() }
    }
}

private struct ActivityEventDetailView: View {
    @EnvironmentObject private var socialStore: TogetherStore
    @EnvironmentObject private var socialRecognitionStore: SocialRecognitionStore
    let run: ActivityEventDTO
    @State private var detail: ActivityEventDetailDTO?
    @State private var isConnectionPickerPresented = false
    @State private var selectedConnectionIDs: Set<String> = []
    @State private var isInviting = false
    @State private var isAttendanceChoicePresented = false
    @State private var invitationToDelete: ActivityEventPendingInvitationDTO?
    @State private var deletingInvitationIDs: Set<String> = []
    private var results: ActivityEventResultDTO? { socialStore.resultsByActivityEventID[run.id] }
    private var isCreator: Bool { (detail?.currentUserRole ?? run.currentUserRole) == "owner" }
    private var participantIDs: Set<String> { Set(detail?.participants?.map(\.person.id) ?? []) }
    private var invitedUserIDs: Set<String> { Set(detail?.invitedUserIds ?? []) }
    private var eventEndsAt: Date? { detail?.endsAt ?? run.endsAt }

    var body: some View {
        List {
            if let detail, detail.currentUserGoing, !isCreator {
                Section {
                    Label("You're going", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(OutboundPalette.companion)
                    Label(attendanceLabel(detail.currentUserAttendanceMode), systemImage: attendanceIcon(detail.currentUserAttendanceMode))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Label("Meet up or join from anywhere", systemImage: "person.2.wave.2")
                    .font(.headline)
                    .foregroundStyle(OutboundPalette.companion)
                Text("Meet at the listed place or join from anywhere.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Created by", value: run.creator.displayName)
                LabeledContent("When", value: run.startsAt.formatted(date: .abbreviated, time: .shortened))
                if let eventEndsAt {
                    LabeledContent("Duration", value: activityDurationLabel(from: run.startsAt, to: eventEndsAt))
                    LabeledContent("Scheduled end", value: eventEndsAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Results close", value: eventEndsAt.addingTimeInterval(ActivityEventTiming.reconciliationWindow).formatted(date: .abbreviated, time: .shortened))
                }
                if let location = run.locationName { LabeledContent("Where", value: location) }
                if let pace = run.paceNote { LabeledContent("Pace / note", value: pace) }
                if run.locationName == nil { LabeledContent("Where", value: "Join from anywhere") }
                if let detail { LabeledContent("Going", value: "\(detail.attendeeCount)") }
            }
            if let coordinate = detail?.meetupCoordinate ?? run.meetupCoordinate {
                Section {
                    ActivityEventMeetingPointView(
                        coordinate: coordinate,
                        locationName: detail?.locationName ?? run.locationName
                    )
                } header: {
                    Text(String(localized: "social.event.location.meeting_point", defaultValue: "Meeting point"))
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
                Section("Going") {
                    ForEach(participants) { participant in
                        HStack {
                            SocialAvatar(name: participant.person.displayName, avatarURL: participant.person.avatarUrl)
                            Text(participant.person.displayName)
                            Spacer()
                            Label(attendanceLabel(participant.attendanceMode), systemImage: attendanceIcon(participant.attendanceMode))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if isCreator, let invitations = detail?.pendingInvitations, !invitations.isEmpty {
                Section("Pending invitations") {
                    ForEach(invitations) { invitation in
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
            if let results, results.status != "scheduled" {
                Section("Results") {
                    LabeledContent("Results received", value: String(localized: "\(results.resolvedCount) of \(results.goingCount)"))
                    if results.combinedDurationSeconds > 0 {
                        LabeledContent("Combined time", value: String(localized: "\(max(1, results.combinedDurationSeconds / 60)) min"))
                    }
                    ForEach(results.participants) { participant in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(participant.person.displayName).font(.headline)
                            Text(resultLabel(participant)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if detail?.currentUserGoing == true && detail?.currentUserOutcome == nil {
                        Button("I joined without recording") {
                            Task { _ = await socialStore.markActivityEventWithoutRecording(id: run.id) }
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
        .confirmationDialog("Meet up or join from anywhere", isPresented: $isAttendanceChoicePresented, titleVisibility: .visible) {
            Button(run.locationName ?? String(localized: "Meet in person")) {
                join(attendanceMode: "in_person")
            }
            Button("Join from anywhere") {
                join(attendanceMode: "virtual")
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

private struct SocialNotificationsView: View {
    @EnvironmentObject private var socialStore: TogetherStore
    @EnvironmentObject private var pushNotifications: PushNotificationCoordinator
    @EnvironmentObject private var circleStore: CircleStore
    @State private var selectedNotification: SocialNotificationDTO?

    var body: some View {
        List {
            if socialStore.notifications.isEmpty {
                ContentUnavailableView("No notifications", systemImage: "bell", description: Text("Connection requests, Cheers, comments, and run invitations appear here."))
            } else {
                ForEach(socialStore.notifications) { notification in
                    Button {
                        selectedNotification = notification
                    } label: {
                        HStack(alignment: .top, spacing: OutboundSpacing.compact) {
                            SocialAvatar(name: notification.actor?.displayName ?? "Plainstride", avatarURL: notification.actor?.avatarUrl)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(localizedCircleNotificationMessage(notification))
                                    .font(notification.readAt == nil ? .body.weight(.semibold) : .body)
                                    .foregroundStyle(.primary)
                                Text(notification.createdAt.formatted(.relative(presentation: .named)))
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
                    .accessibilityHint(notificationAccessibilityHint(notification))
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationDestination(item: $selectedNotification) { notification in
            notificationDestination(notification)
        }
        .task {
            await socialStore.refreshNotifications()
            if let notificationID = pushNotifications.pendingNotificationID,
               let notification = socialStore.notifications.first(where: { $0.id == notificationID }) {
                selectedNotification = notification
                pushNotifications.consumePendingNotification()
            }
            await socialStore.markNotificationsRead()
            await pushNotifications.clearAppIconBadge()
        }
        .refreshable { await socialStore.refreshNotifications() }
    }

    @ViewBuilder
    private func notificationDestination(_ notification: SocialNotificationDTO) -> some View {
        switch notification.type {
        case "liveCheerInvitation":
            if let sessionID = notification.objectId {
                LiveCheerView(sessionID: sessionID, entrySource: "notification_inbox")
            } else {
                SocialNotificationDetailView(notification: notification)
            }
        case "connectionRequest", "connectionAccepted":
            SocialConnectionsView()
        case "cheer", "comment":
            SocialNotificationActivityView(notification: notification)
        case "runInvitation":
            SocialRunInvitationActionView(notification: notification)
        case "invitationAccepted":
            if let runID = notification.objectId,
               let run = socialStore.state.upcomingRuns.first(where: { $0.id == runID }) {
                ActivityEventDetailView(run: run)
            } else {
                SocialNotificationDetailView(notification: notification)
            }
        case "circleInvitation":
            CircleNotificationInvitationView(notification: notification)
        case "circleInvitationAccepted", "circleCheer", "circleWeeklyGoalCompleted", "circleOwnershipTransferred":
            if let circleID = notification.objectId,
               let circle = circleStore.circles.first(where: { $0.id == circleID }) {
                CircleDetailView(circle: circle)
            } else {
                SocialNotificationDetailView(notification: notification)
            }
        default:
            SocialNotificationDetailView(notification: notification)
        }
    }

    private func notificationAccessibilityHint(_ notification: SocialNotificationDTO) -> String {
        switch notification.type {
        case "liveCheerInvitation": return String(localized: "Opens the live activity")
        case "connectionRequest", "connectionAccepted": return String(localized: "Opens Connections")
        case "cheer", "comment": return String(localized: "Opens the activity")
        case "runInvitation": return String(localized: "Opens the invitation")
        case "invitationAccepted": return String(localized: "Opens the group run")
        case "circleInvitation": return String(localized: "circle.notification.open_invitation", defaultValue: "Opens the Circle invitation")
        case "circleInvitationAccepted", "circleCheer", "circleWeeklyGoalCompleted", "circleOwnershipTransferred": return String(localized: "circle.notification.open", defaultValue: "Opens the Circle")
        default: return String(localized: "Opens notification details")
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
            Label(localizedCircleNotificationMessage(notification), systemImage: "person.3.fill")
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
        .navigationTitle(String(localized: "circle.invitation.navigation", defaultValue: "Circle invitation"))
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
                                SocialRouteMap(route: activity.route)
                                HStack(spacing: 0) {
                                    stat(activity.distanceM.map { measurementPreferences.unitSystem.distanceString(meters: $0, fractionDigits: 1) } ?? "—", String(localized: "Distance"))
                                    stat(activity.durationSecs.map(duration) ?? "—", String(localized: "Time"))
                                    stat(activity.avgPace.map { $0.paceString(for: measurementPreferences.unitSystem) } ?? "—", "Pace")
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(.regularMaterial)
                            }
                            .frame(height: 240)
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
        .navigationTitle("Connections")
        .toolbar {
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
        .task {
            await socialStore.refreshConnections()
            await socialStore.refreshBlocks()
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

private struct SocialActivityDetailView: View {
    @EnvironmentObject private var socialStore: TogetherStore
    @EnvironmentObject private var socialRecognitionStore: SocialRecognitionStore
    let post: TogetherPostDTO
    @State private var showsComments = false
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
                showsShareControl: true,
                showsEditControl: false,
                showsPrivateDetails: false,
                routePublicationActivityID: currentPost.isCurrentUser ? activity.id : nil,
                supplementalContent: AnyView(socialCard),
                bottomContent: AnyView(socialCompanionCard)
            )
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
        HStack(spacing: 12) {
            Button {
                Task { await toggleCheer() }
            } label: {
                Label {
                    Text("\(String(localized: "Cheers")) · \(currentPost.reactionCount)")
                } icon: {
                    Image(systemName: currentPost.currentUserCheered ? "heart.fill" : "heart")
                }
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(SocialFeedActionButtonStyle(isActive: currentPost.currentUserCheered))
            .disabled(socialStore.isSocialMutationPending)
            .accessibilityLabel(currentPost.currentUserCheered ? String(localized: "Remove cheer") : String(localized: "Cheer"))
            .accessibilityValue("\(currentPost.reactionCount)")

            Button { showsComments = true } label: {
                Label {
                    Text("\(String(localized: "Comments")) · \(currentPost.commentCount)")
                } icon: {
                    Image(systemName: "bubble.left")
                }
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(SocialFeedActionButtonStyle())
            .accessibilityLabel(String(localized: "Comments"))
            .accessibilityValue("\(currentPost.commentCount)")
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
        let coordinates = route?.geometry.coordinates ?? []
        let routePoints = coordinates.enumerated().compactMap { index, coordinate -> SavedRoutePoint? in
            guard coordinate.count >= 2 else { return nil }
            let progress = coordinates.count > 1 ? Double(index) / Double(coordinates.count - 1) : 0
            return SavedRoutePoint(
                timestamp: resolvedStartedAt.addingTimeInterval(TimeInterval(duration) * progress),
                latitude: coordinate[1],
                longitude: coordinate[0],
                altitude: nil,
                verticalAccuracy: nil
            )
        }
        let savedPhotos = (photos ?? []).compactMap { photo -> SavedPhoto? in
            guard let clientPhotoID = UUID(uuidString: photo.clientPhotoId),
                  let url = photo.url else { return nil }
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
            title: title ?? String(localized: "Activity"),
            guideNudge: "",
            reflection: nil,
            createdAt: postCreatedAt,
            startedAt: resolvedStartedAt,
            endedAt: resolvedEndedAt,
            durationSecs: duration,
            distanceM: max(0, distanceM ?? 0),
            avgPace: avgPace,
            route: routePoints.isEmpty ? nil : SavedRoute(points: routePoints),
            photos: savedPhotos,
            sync: nil
        )
    }
}

struct SocialAvatar: View {
    let name: String
    let avatarURL: String?
    @StateObject private var loader: AvatarImageLoader

    init(name: String, avatarURL: String?) {
        self.name = name
        self.avatarURL = avatarURL
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
        .frame(width: 40, height: 40)
        .clipShape(Circle())
        .accessibilityLabel(name)
        .task(id: avatarURL) { await loader.load(url: avatarURL) }
    }

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }
}

private struct SocialRouteMap: View {
    let route: TogetherActivityRouteDTO?

    private var coordinates: [CLLocationCoordinate2D] {
        route?.geometry.coordinates.compactMap { coordinate in
            guard coordinate.count >= 2,
                  (-180...180).contains(coordinate[0]),
                  (-90...90).contains(coordinate[1]) else { return nil }
            return CLLocationCoordinate2D(latitude: coordinate[1], longitude: coordinate[0])
        } ?? []
    }

    private var position: MapCameraPosition {
        guard coordinates.count > 1 else { return .automatic }
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: ((latitudes.min() ?? 0) + (latitudes.max() ?? 0)) / 2,
            longitude: ((longitudes.min() ?? 0) + (longitudes.max() ?? 0)) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(((latitudes.max() ?? 0) - (latitudes.min() ?? 0)) * 1.7, 0.006),
            longitudeDelta: max(((longitudes.max() ?? 0) - (longitudes.min() ?? 0)) * 1.7, 0.006)
        )
        return .region(MKCoordinateRegion(center: center, span: span))
    }

    var body: some View {
        Group {
            if coordinates.count > 1 {
                Map(position: .constant(position), interactionModes: []) {
                    MapPolyline(coordinates: coordinates)
                        .stroke(OutboundPalette.companion, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
                .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
            } else {
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
        .allowsHitTesting(false)
        .accessibilityLabel(coordinates.count > 1 ? "Activity route map" : "Activity without route data")
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
        return String(format: String(localized: "circle.notification.invitation", defaultValue: "%@ invited you to a Circle."), actorName)
    case "circleInvitationAccepted":
        return String(format: String(localized: "circle.notification.accepted", defaultValue: "%@ joined your Circle."), actorName)
    case "circleCheer":
        return String(format: String(localized: "circle.notification.cheer", defaultValue: "%@ sent you a Cheer."), actorName)
    case "circleWeeklyGoalCompleted":
        return String(localized: "circle.notification.weekly_complete", defaultValue: "Your Circle completed this week’s focus.")
    case "circleOwnershipTransferred":
        return String(format: String(localized: "circle.notification.ownership", defaultValue: "%@ made you the Circle owner."), actorName)
    default:
        return notification.message
    }
}
