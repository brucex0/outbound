import MapKit
import SwiftUI

struct SocialHomeView: View {
    @EnvironmentObject private var socialStore: TogetherStore
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    @EnvironmentObject private var recognitionStore: RecognitionStore
    @EnvironmentObject private var socialRecognitionStore: SocialRecognitionStore
    @EnvironmentObject private var activityStore: ActivityStore
    @State private var selectedCommentPost: TogetherPostDTO?
    @State private var isCreateFutureActivityPresented = false

    private var shouldShowConnectionPrompt: Bool {
        socialStore.connections.filter { $0.status == "accepted" }.count < 3
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                    if let message = socialStore.errorMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let incomingRequest = socialStore.connections.first(where: {
                        $0.status == "pending" && $0.direction == "incoming"
                    }) {
                        incomingRequestCard(incomingRequest)
                    }

                    if shouldShowConnectionPrompt {
                        connectionGrowthCard
                    }

                    if let milestone = socialRecognitionStore.highlight {
                        SocialMilestoneCard(preview: milestone)
                    }

                    upcomingRuns
                    joinedClubs
                    recentPosts
                }
                .padding(OutboundSpacing.screen)
            }
            .background(OutboundPalette.background)
            .navigationTitle("Social")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            isCreateFutureActivityPresented = true
                        } label: {
                            Label("Plan a run", systemImage: "calendar.badge.plus")
                        }

                        NavigationLink {
                            SocialConnectionsView()
                        } label: {
                            Label("Connections", systemImage: "person.2")
                        }

                        NavigationLink {
                            SocialGroupsView()
                        } label: {
                            Label("Groups", systemImage: "person.3")
                        }
                    } label: {
                        Image(systemName: "person.2.circle")
                    }
                    .accessibilityLabel("Social community")

                    NavigationLink {
                        SocialNotificationsView()
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
                _ = await (homeRefresh, connectionsRefresh)
            }
            .task {
                if socialStore.connections.isEmpty {
                    await socialStore.refreshConnections()
                }
                await socialStore.refreshNotifications()
            }
            .task(id: socialStore.state.posts.map(\.id)) {
                reconcileSharedActivityMilestones()
            }
            .sheet(item: $selectedCommentPost) { post in
                SocialCommentsView(post: post)
            }
            .sheet(isPresented: $isCreateFutureActivityPresented) {
                CreateFutureActivityView()
                    .environmentObject(socialStore)
            }
        }
    }

    private func incomingRequestCard(_ connection: SocialConnectionDTO) -> some View {
        OutboundCard(style: .companion) {
            HStack(spacing: OutboundSpacing.compact) {
                SocialAvatar(name: connection.person.displayName, avatarURL: connection.person.avatarUrl)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(connection.person.displayName) wants to connect")
                        .font(.headline)
                    Text("@\(connection.person.username)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    NavigationLink {
                        SocialConnectionsView()
                    } label: {
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
    private var upcomingRuns: some View {
        Text("UPCOMING").socialSectionLabel()
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
                    VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                        Text(run.source?.label ?? run.club?.name ?? run.creator.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(run.title).font(.headline)
                        Text(run.startsAt.formatted(date: .abbreviated, time: .shortened) + locationSuffix(run.locationName))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let note = run.paceNote {
                            Text(note).font(.subheadline).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 8) {
                            Text("\(run.attendeeCount ?? 0) going")
                            Text("Meet up or join from anywhere")
                        }
                        .font(.caption)
                        .foregroundStyle(OutboundPalette.companion)
                        if let compatibility = run.compatibility {
                            AIExplanationView(text: compatibility.explanation)
                        }
                        HStack {
                            NavigationLink(run.currentUserGoing == true ? "View" : "Review") {
                                SocialGroupRunView(run: run)
                            }
                            .buttonStyle(.borderedProminent)

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
    }

    @ViewBuilder
    private var joinedClubs: some View {
        if !socialStore.state.clubs.isEmpty {
            Text("YOUR GROUPS").socialSectionLabel()
            ForEach(socialStore.state.clubs.prefix(3)) { club in
                OutboundCard {
                    HStack {
                        Image(systemName: "flag.fill").foregroundStyle(OutboundPalette.companion)
                        VStack(alignment: .leading) {
                            Text(club.name).font(.headline)
                            Text([club.city, club.role.map(localizedGroupRole)].compactMap { $0 }.joined(separator: " · "))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
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
        Text("RECENT").socialSectionLabel()
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
            ForEach(socialStore.state.posts.prefix(5)) { post in
                OutboundCard {
                    VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                        HStack {
                            SocialAvatar(name: post.user.displayName, avatarURL: post.user.avatarUrl)
                            VStack(alignment: .leading) {
                                Text(post.user.displayName).font(.headline)
                                Text(post.createdAt.formatted(.relative(presentation: .named)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
                        Text(post.activity?.title ?? String(localized: "Run")).font(.headline)
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
                                    RecognitionPill(preview: milestone, compact: true)
                                        .padding(12)
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
            }
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
        guard await socialStore.toggleCheer(on: post), addsSupport else { return }
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

private struct SocialGroupRunView: View {
    @EnvironmentObject private var socialStore: TogetherStore
    @EnvironmentObject private var socialRecognitionStore: SocialRecognitionStore
    let run: TogetherGroupRunDTO
    @State private var detail: SocialGroupRunDetailDTO?
    @State private var isConnectionPickerPresented = false
    private var results: FutureActivityResultDTO? { socialStore.resultsByFutureActivityID[run.id] }

    var body: some View {
        List {
            if let detail, detail.currentUserGoing {
                Section {
                    Label("You're going", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(OutboundPalette.companion)
                    Text("Meet at the listed place or join from anywhere.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                LabeledContent("Created by", value: run.creator.displayName)
                LabeledContent("When", value: run.startsAt.formatted(date: .abbreviated, time: .shortened))
                if let location = run.locationName { LabeledContent("Where", value: location) }
                if let pace = run.paceNote { LabeledContent("Pace / note", value: pace) }
                if run.locationName == nil { LabeledContent("Where", value: "Join from anywhere") }
                if let detail { LabeledContent("Going", value: "\(detail.attendeeCount)") }
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
                        }
                    }
                }
            }
            if let results, results.status != "scheduled" {
                Section("Results") {
                    LabeledContent("Resolved", value: "\(results.resolvedCount) of \(results.goingCount)")
                    if results.combinedDurationSeconds > 0 {
                        LabeledContent("Combined time", value: "\(max(1, results.combinedDurationSeconds / 60)) min")
                    }
                    ForEach(results.participants) { participant in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(participant.person.displayName).font(.headline)
                            Text(resultLabel(participant)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if detail?.currentUserGoing == true && detail?.currentUserOutcome == nil {
                        Button("I joined without recording") {
                            Task { _ = await socialStore.markFutureActivityWithoutRecording(id: run.id) }
                        }
                    }
                }
            }
            Section {
                Button {
                    guard let detail else { return }
                    Task {
                        let isJoining = !detail.currentUserGoing
                        if let updatedDetail = await socialStore.toggleRSVP(for: detail) {
                            self.detail = updatedDetail
                            if isJoining, updatedDetail.currentUserGoing {
                                _ = socialRecognitionStore.registerGroupJoin(groupID: "run:\(run.id)")
                            }
                        }
                    }
                } label: {
                    Label(detail?.currentUserGoing == true ? String(localized: "Leave run") : String(localized: "I'm going"),
                          systemImage: detail?.currentUserGoing == true ? "calendar.badge.minus" : "calendar.badge.checkmark")
                }
                .disabled(detail == nil)

                Button {
                    isConnectionPickerPresented = true
                } label: {
                    Label("Invite connections", systemImage: "person.badge.plus")
                }
                if let invitationURL = socialStore.latestInvitationURL {
                    ShareLink(item: String(localized: "Join me for a run on Plainstride: \(invitationURL.absoluteString)")) {
                        Label("Share invitation", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .navigationTitle(run.title)
        .task {
            detail = await socialStore.groupRunDetail(id: run.id)
            if run.startsAt <= Date() { await socialStore.loadFutureActivityResults(id: run.id) }
        }
        .sheet(isPresented: $isConnectionPickerPresented) {
            NavigationStack {
                List(socialStore.connections.filter { $0.status == "accepted" }) { connection in
                    Button {
                        Task {
                            if await socialStore.invite(connection, to: run) {
                                isConnectionPickerPresented = false
                            }
                        }
                    } label: {
                        HStack {
                            SocialAvatar(name: connection.person.displayName, avatarURL: connection.person.avatarUrl)
                            VStack(alignment: .leading) {
                                Text(connection.person.displayName)
                                Text("@\(connection.person.username)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "person.badge.plus")
                                .foregroundStyle(OutboundPalette.companion)
                        }
                    }
                    .accessibilityLabel("Invite \(connection.person.displayName)")
                }
                .navigationTitle("Invite connections")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { isConnectionPickerPresented = false } } }
                .task { await socialStore.refreshConnections() }
            }
        }
    }

    private func resultLabel(_ participant: FutureActivityResultParticipantDTO) -> String {
        if let result = participant.result {
            return "Completed · \(MeasurementUnitSystem.metric.distanceString(meters: result.distanceM ?? 0, fractionDigits: 1))"
        }
        switch participant.outcome {
        case "no_recording": return "Participated · No recording"
        case "did_not_participate": return "Couldn't participate"
        default: return "Waiting for result"
        }
    }
}

private struct SocialNotificationsView: View {
    @EnvironmentObject private var socialStore: TogetherStore
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
                                Text(notification.message)
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
            await socialStore.markNotificationsRead()
        }
        .refreshable { await socialStore.refreshNotifications() }
    }

    @ViewBuilder
    private func notificationDestination(_ notification: SocialNotificationDTO) -> some View {
        switch notification.type {
        case "connectionRequest", "connectionAccepted":
            SocialConnectionsView()
        case "cheer", "comment":
            SocialNotificationActivityView(notification: notification)
        case "runInvitation":
            SocialRunInvitationActionView(notification: notification)
        case "invitationAccepted":
            if let runID = notification.objectId,
               let run = socialStore.state.upcomingRuns.first(where: { $0.id == runID }) {
                SocialGroupRunView(run: run)
            } else {
                SocialNotificationDetailView(notification: notification)
            }
        default:
            SocialNotificationDetailView(notification: notification)
        }
    }

    private func notificationAccessibilityHint(_ notification: SocialNotificationDTO) -> String {
        switch notification.type {
        case "connectionRequest", "connectionAccepted": return String(localized: "Opens Connections")
        case "cheer", "comment": return String(localized: "Opens the activity")
        case "runInvitation": return String(localized: "Opens the invitation")
        case "invitationAccepted": return String(localized: "Opens the group run")
        default: return String(localized: "Opens notification details")
        }
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
                                Text(post.createdAt.formatted(.relative(presentation: .named)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text(post.activity?.title ?? String(localized: "Run")).font(.headline)
                        if let activity = post.activity {
                            ZStack(alignment: .bottom) {
                                SocialRouteMap(route: activity.route)
                                HStack(spacing: 0) {
                                    stat(activity.distanceM.map { measurementPreferences.unitSystem.distanceString(meters: $0, fractionDigits: 1) } ?? "—", "Distance")
                                    stat(activity.durationSecs.map(duration) ?? "—", "Time")
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
                    Task {
                        await socialStore.acceptRunInvitation(notification)
                        dismiss()
                    }
                } label: {
                    Label("Accept invitation", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle("Run invitation")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SocialNotificationDetailView: View {
    let notification: SocialNotificationDTO

    var body: some View {
        List {
            Label(notification.message, systemImage: "bell")
            LabeledContent("Received", value: notification.createdAt.formatted(date: .abbreviated, time: .shortened))
        }
        .navigationTitle("Notification")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SocialCommentsView: View {
    @EnvironmentObject private var socialStore: TogetherStore
    @EnvironmentObject private var socialRecognitionStore: SocialRecognitionStore
    @Environment(\.dismiss) private var dismiss
    let post: TogetherPostDTO
    @State private var draft = ""

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
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(comment.author.displayName).font(.headline)
                                Text(comment.body)
                                Text(comment.createdAt.formatted(.relative(presentation: .named)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
                    TextField("Add encouragement", text: $draft)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        let body = draft
                        draft = ""
                        Task {
                            if await socialStore.addComment(body, to: post) {
                                _ = socialRecognitionStore.registerSupport(for: post.id)
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
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await socialStore.loadComments(for: post) }
        }
    }
}

private struct SocialConnectionsView: View {
    @EnvironmentObject private var socialStore: TogetherStore
    @State private var searchQuery = ""
    @FocusState private var isSearchFocused: Bool

    private var incomingRequests: [SocialConnectionDTO] {
        socialStore.connections.filter { $0.status == "pending" && $0.direction == "incoming" }
    }

    private var outgoingRequests: [SocialConnectionDTO] {
        socialStore.connections.filter { $0.status == "pending" && $0.direction == "outgoing" }
    }

    private var acceptedConnections: [SocialConnectionDTO] {
        socialStore.connections.filter { $0.status == "accepted" }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search name or username", text: $searchQuery)
                        .focused($isSearchFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
            }

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
                            Menu {
                                Button("Remove connection", role: .destructive) {
                                    Task { await socialStore.removeConnection(connection) }
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                            }
                            .accessibilityLabel("Connection actions")
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

            if !socialStore.peopleResults.isEmpty {
                Section("People") {
                    ForEach(socialStore.peopleResults) { person in
                        HStack(spacing: OutboundSpacing.compact) {
                            SocialAvatar(name: person.displayName, avatarURL: person.avatarUrl)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(person.displayName).font(.headline)
                                Text("@\(person.username)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            relationshipAction(for: person)
                        }
                    }
                }
            } else if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2,
                      !socialStore.isConnectionsLoading {
                ContentUnavailableView.search(text: searchQuery)
            }

        }
        .navigationTitle("Connections")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        isSearchFocused = true
                    } label: {
                        Label("Find people", systemImage: "magnifyingglass")
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
        .task(id: searchQuery) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await socialStore.searchPeople(searchQuery)
        }
        .refreshable { await socialStore.refreshConnections() }
        .overlay {
            if socialStore.isConnectionsLoading && socialStore.connections.isEmpty {
                ProgressView()
            }
        }
    }

    private func connectionRow<Actions: View>(
        _ connection: SocialConnectionDTO,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(spacing: OutboundSpacing.compact) {
            SocialAvatar(name: connection.person.displayName, avatarURL: connection.person.avatarUrl)
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.person.displayName).font(.headline)
                Text("@\(connection.person.username)").font(.caption).foregroundStyle(.secondary)
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

    @ViewBuilder
    private func relationshipAction(for person: SocialPersonSearchResultDTO) -> some View {
        switch (person.relationship?.status, person.relationship?.direction) {
        case ("accepted", _):
            Text("Connected").font(.caption).foregroundStyle(.secondary)
        case ("pending", "outgoing"):
            Text("Sent").font(.caption).foregroundStyle(.secondary)
        case ("pending", "incoming"):
            Text("Requested").font(.caption).foregroundStyle(.secondary)
        default:
            Button {
                Task { await socialStore.requestConnection(to: person) }
            } label: {
                Image(systemName: "person.badge.plus")
            }
            .buttonStyle(SocialIconButtonStyle())
            .accessibilityLabel("Connect with \(person.displayName)")
        }
    }
}

struct SocialAvatar: View {
    let name: String
    let avatarURL: String?

    var body: some View {
        AsyncImage(url: avatarURL.flatMap(URL.init(string:))) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                Circle().fill(OutboundPalette.companion.opacity(0.15))
                Text(initials).font(.caption.weight(.semibold))
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
        .accessibilityLabel(name)
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
                    Text("Coach noticed this")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                    Text(preview.title)
                        .font(.headline)
                    Text(preview.coachLine)
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

private extension Text {
    func socialSectionLabel() -> some View {
        font(.caption.weight(.semibold)).foregroundStyle(.secondary)
    }
}
