import SwiftUI

struct SocialHomeView: View {
    @EnvironmentObject private var socialStore: TogetherStore
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    @EnvironmentObject private var activityStore: ActivityStore
    @State private var selectedCommentPost: TogetherPostDTO?
    @State private var selectedShareActivity: SavedActivity?

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

                    if let latestActivity = activityStore.activities.first,
                       latestActivity.sync?.serverActivityId != nil {
                        shareLatestActivityCard(latestActivity)
                    }

                    if socialStore.state.upcomingRuns.isEmpty
                        && socialStore.state.clubs.isEmpty
                        && socialStore.state.posts.isEmpty {
                        socialEmptyState
                    } else {
                        upcomingRuns
                        joinedClubs
                        recentPosts
                    }
                }
                .padding(OutboundSpacing.screen)
            }
            .background(OutboundPalette.background)
            .navigationTitle("Social")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
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
                        Image(systemName: socialStore.unreadNotificationCount > 0 ? "bell.badge.fill" : "bell")
                    }
                    .accessibilityLabel("Social notifications")
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
            .sheet(item: $selectedCommentPost) { post in
                SocialCommentsView(post: post)
            }
            .sheet(item: $selectedShareActivity) { activity in
                SocialActivityShareView(activity: activity)
            }
        }
    }

    private func shareLatestActivityCard(_ activity: SavedActivity) -> some View {
        OutboundCard {
            HStack(spacing: OutboundSpacing.standard) {
                Image(systemName: "square.and.arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(OutboundPalette.companion)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Share your latest run").font(.headline)
                    Text(activity.title).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Share") { selectedShareActivity = activity }
                    .buttonStyle(.bordered)
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

    private var socialEmptyState: some View {
        OutboundCard(style: .companion) {
            VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                Text("Running is better with people who matter")
                    .font(.headline)
                Text("Connect with friends, share selected runs, and make plans to run together.")
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
        if !socialStore.state.upcomingRuns.isEmpty {
            Text("UPCOMING TOGETHER").socialSectionLabel()
            ForEach(socialStore.state.upcomingRuns.prefix(2)) { run in
                OutboundCard {
                    VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                        Text(run.club?.name ?? run.creator.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(run.title).font(.headline)
                        Text(run.startsAt.formatted(date: .abbreviated, time: .shortened) + locationSuffix(run.locationName))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let compatibility = run.compatibility {
                            AIExplanationView(text: compatibility.explanation)
                        }
                        HStack {
                            NavigationLink("View run") {
                                SocialGroupRunView(run: run)
                            }
                            .buttonStyle(.borderedProminent)

                            if let invitationURL = socialStore.latestInvitationURL {
                                ShareLink(item: "Join me for a run on Plainstride: \(invitationURL.absoluteString)") {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                }
                                .buttonStyle(.bordered)
                            } else {
                                Button("Invite", systemImage: "person.badge.plus") {
                                    Task { await socialStore.invite(to: run) }
                                }
                                .buttonStyle(.bordered)
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
                            Text([club.city, club.role?.capitalized].compactMap { $0 }.joined(separator: " · "))
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
        if !socialStore.state.posts.isEmpty {
            Text("RECENT").socialSectionLabel()
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
                            }
                            .accessibilityLabel("Post actions")
                        }
                        Text(post.activity?.title ?? "Run").font(.headline)
                        if let activity = post.activity {
                            HStack {
                                socialStat(activity.distanceM.map { measurementPreferences.unitSystem.distanceString(meters: $0, fractionDigits: 1) } ?? "—", "Distance")
                                socialStat(activity.durationSecs.map { $0.formatted() } ?? "—", "Time")
                                socialStat(activity.avgPace.map { $0.paceString(for: measurementPreferences.unitSystem) } ?? "—", "Pace")
                            }
                        }
                        if let caption = post.caption, !caption.isEmpty {
                            Text(caption).font(.subheadline)
                        }
                        HStack {
                            Button(post.currentUserCheered ? "Cheered · \(post.reactionCount)" : "Cheer · \(post.reactionCount)", systemImage: post.currentUserCheered ? "heart.fill" : "heart") {
                                Task { await socialStore.toggleCheer(on: post) }
                            }
                            .buttonStyle(.bordered)
                            .disabled(socialStore.isSocialMutationPending)

                            Button("Comment · \(post.commentCount)", systemImage: "bubble.left") {
                                selectedCommentPost = post
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    private func shareReferral() async {
        guard let url = await socialStore.referralInvitationURL() else { return }
        await SystemSharePresenter.present(activityItems: [
            "Join me for a run on Plainstride: \(url.absoluteString)",
        ])
    }

    private func locationSuffix(_ location: String?) -> String {
        location.map { " · \($0)" } ?? ""
    }

    private func socialStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.subheadline.monospacedDigit().weight(.semibold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SocialGroupsView: View {
    @EnvironmentObject private var socialStore: TogetherStore

    var body: some View {
        List(socialStore.discoverableGroups) { group in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.name).font(.headline)
                        Text([group.city, "\(group.memberCount) members"].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(group.membershipRole == nil ? "Join" : "Leave") {
                        Task { await socialStore.toggleMembership(in: group) }
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
    let run: TogetherGroupRunDTO
    @State private var detail: SocialGroupRunDetailDTO?
    @State private var isConnectionPickerPresented = false

    var body: some View {
        List {
            Section {
                LabeledContent("When", value: run.startsAt.formatted(date: .abbreviated, time: .shortened))
                if let location = run.locationName { LabeledContent("Where", value: location) }
                if let pace = run.paceNote { LabeledContent("Pace", value: pace) }
                if let detail { LabeledContent("Going", value: "\(detail.attendeeCount)") }
            }
            if let compatibility = run.compatibility {
                Section("Fit") { AIExplanationView(text: compatibility.explanation) }
            }
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
            Section {
                Button(detail?.currentUserGoing == true ? "Leave run" : "I'm going") {
                    guard let detail else { return }
                    Task { self.detail = await socialStore.toggleRSVP(for: detail) }
                }
                .disabled(detail == nil)

                Button("Invite connections") {
                    isConnectionPickerPresented = true
                }
                if let invitationURL = socialStore.latestInvitationURL {
                    ShareLink(item: "Join me for a run on Plainstride: \(invitationURL.absoluteString)") {
                        Label("Share invitation", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .navigationTitle(run.title)
        .task { detail = await socialStore.groupRunDetail(id: run.id) }
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
                            Text("Invite")
                        }
                    }
                }
                .navigationTitle("Invite connections")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { isConnectionPickerPresented = false } } }
                .task { await socialStore.refreshConnections() }
            }
        }
    }
}

private struct SocialNotificationsView: View {
    @EnvironmentObject private var socialStore: TogetherStore

    var body: some View {
        List {
            if socialStore.notifications.isEmpty {
                ContentUnavailableView("No notifications", systemImage: "bell", description: Text("Connection requests, Cheers, comments, and run invitations appear here."))
            } else {
                ForEach(socialStore.notifications) { notification in
                    HStack(alignment: .top, spacing: OutboundSpacing.compact) {
                        SocialAvatar(name: notification.actor?.displayName ?? "Plainstride", avatarURL: notification.actor?.avatarUrl)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(notification.message)
                                .font(notification.readAt == nil ? .body.weight(.semibold) : .body)
                            Text(notification.createdAt.formatted(.relative(presentation: .named)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if notification.type == "runInvitation" {
                                Button("Accept invitation") {
                                    Task { await socialStore.acceptRunInvitation(notification) }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Notifications")
        .task {
            await socialStore.refreshNotifications()
            await socialStore.markNotificationsRead()
        }
        .refreshable { await socialStore.refreshNotifications() }
    }
}

private struct SocialCommentsView: View {
    @EnvironmentObject private var socialStore: TogetherStore
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
                    Button("Post") {
                        let body = draft
                        draft = ""
                        Task { await socialStore.addComment(body, to: post) }
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

private struct SocialActivityShareView: View {
    @EnvironmentObject private var socialStore: TogetherStore
    @Environment(\.dismiss) private var dismiss
    let activity: SavedActivity
    @State private var caption = ""
    @State private var isSharing = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Activity") {
                    Text(activity.title)
                    LabeledContent("Audience", value: "Connections")
                }
                Section("Caption") {
                    TextField("Add an optional caption", text: $caption, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section {
                    Button {
                        isSharing = true
                        Task {
                            let shared = await socialStore.shareActivity(activity, caption: caption.isEmpty ? nil : caption)
                            isSharing = false
                            if shared { dismiss() }
                        }
                    } label: {
                        if isSharing { ProgressView() } else { Label("Share with connections", systemImage: "person.2.fill") }
                    }
                    .disabled(isSharing)
                } footer: {
                    Text("Your private reflection and coaching context are never included.")
                }
            }
            .navigationTitle("Share activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

private struct SocialConnectionsView: View {
    @EnvironmentObject private var socialStore: TogetherStore
    @State private var searchQuery = ""

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
                            Button("Accept") {
                                Task { await socialStore.acceptConnection(connection) }
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Decline", role: .destructive) {
                                Task { await socialStore.removeConnection(connection) }
                            }
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
                            Button("Cancel") {
                                Task { await socialStore.removeConnection(connection) }
                            }
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
                            Button("Unblock") { Task { await socialStore.unblock(block) } }
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

            Section {
                Button {
                    Task {
                        guard let url = await socialStore.referralInvitationURL() else { return }
                        await SystemSharePresenter.present(activityItems: [
                            "Join me for a run on Plainstride: \(url.absoluteString)",
                        ])
                    }
                } label: {
                    Label("Invite someone by link", systemImage: "square.and.arrow.up")
                }
            }
        }
        .navigationTitle("Connections")
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
            Button("Connect") {
                Task { await socialStore.requestConnection(to: person) }
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct SocialAvatar: View {
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

private extension Text {
    func socialSectionLabel() -> some View {
        font(.caption.weight(.semibold)).foregroundStyle(.secondary)
    }
}
