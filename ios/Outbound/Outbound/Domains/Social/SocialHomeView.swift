import SwiftUI

struct SocialHomeView: View {
    @EnvironmentObject private var socialStore: TogetherStore
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences

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
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SocialConnectionsView()
                    } label: {
                        Image(systemName: "person.2")
                    }
                    .accessibilityLabel("Connections")
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
                        if let invitationURL = socialStore.latestInvitationURL {
                            ShareLink(item: "Join me for a run on Plainstride: \(invitationURL.absoluteString)") {
                                Label("Share invite", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.borderedProminent)
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

    @ViewBuilder
    private var joinedClubs: some View {
        if !socialStore.state.clubs.isEmpty {
            Text("YOUR CLUBS").socialSectionLabel()
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
                        Button("Cheer · \(post.reactions.count)", systemImage: "heart") {
                            Task { await socialStore.react(to: post) }
                        }
                        .buttonStyle(.bordered)
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
        .searchable(text: $searchQuery, prompt: "Search name or username")
        .task { await socialStore.refreshConnections() }
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
