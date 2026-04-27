import SwiftUI

struct ActivityFeedView: View {
    @EnvironmentObject private var activityStore: ActivityStore
    @State private var selectedScope: SocialFeedScope = .squad
    @State private var cheeredPostIDs: Set<String> = ["maya-waterfront"]
    @State private var joinedClubIDs: Set<String> = ["sf-dawn"]
    @State private var sharedActivityIDs: Set<UUID> = []
    @State private var showingRelayComposer = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    socialCommandBar
                    crewPulseStrip
                    scopePicker

                    if let latestActivity = activityStore.activities.first {
                        ShareLatestRunCard(
                            activity: latestActivity,
                            activityStore: activityStore,
                            isShared: sharedActivityIDs.contains(latestActivity.id)
                        ) {
                            toggleShared(latestActivity)
                        }
                    }

                    switch selectedScope {
                    case .squad:
                        squadFeed
                    case .clubs:
                        clubsAndChallenges
                    case .rivals:
                        rivalBoard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Social")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingRelayComposer = true } label: {
                        Image(systemName: "person.badge.plus")
                    }
                    .accessibilityLabel("Invite Runner")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button { } label: {
                        Image(systemName: "bell.badge")
                    }
                    .accessibilityLabel("Notifications")
                }
            }
            .sheet(isPresented: $showingRelayComposer) {
                RelayComposerSheet()
            }
        }
    }

    private var socialCommandBar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Crew Pulse")
                        .font(.title3.bold())
                    Text("4 running now")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button { showingRelayComposer = true } label: {
                    Label("Start Relay", systemImage: "bolt.fill")
                        .font(.subheadline.bold())
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }

            HStack(spacing: 10) {
                SocialMetricPill(value: "12", label: "active", symbol: "figure.run")
                SocialMetricPill(value: "8", label: "cheers", symbol: "hands.clap.fill")
                SocialMetricPill(value: "3", label: "invites", symbol: "link")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var crewPulseStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(SocialSeed.people) { person in
                    CrewPulseAvatar(person: person)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var scopePicker: some View {
        Picker("Social Scope", selection: $selectedScope) {
            ForEach(SocialFeedScope.allCases) { scope in
                Text(scope.rawValue).tag(scope)
            }
        }
        .pickerStyle(.segmented)
    }

    private var squadFeed: some View {
        LazyVStack(spacing: 12) {
            ForEach(SocialSeed.feedPosts) { post in
                SocialFeedPostCard(
                    post: post,
                    isCheered: cheeredPostIDs.contains(post.id)
                ) {
                    toggleCheer(for: post)
                }
            }
        }
    }

    private var clubsAndChallenges: some View {
        LazyVStack(spacing: 12) {
            ForEach(SocialSeed.clubs) { club in
                SocialClubCard(
                    club: club,
                    isJoined: joinedClubIDs.contains(club.id)
                ) {
                    toggleClub(club)
                }
            }

            ForEach(SocialSeed.challenges) { challenge in
                SocialChallengeCard(challenge: challenge)
            }
        }
    }

    private var rivalBoard: some View {
        LazyVStack(spacing: 12) {
            RivalryHeaderCard()

            ForEach(SocialSeed.rivals) { rival in
                RivalRow(rival: rival)
            }
        }
    }

    private func toggleCheer(for post: SocialFeedPost) {
        if cheeredPostIDs.contains(post.id) {
            cheeredPostIDs.remove(post.id)
        } else {
            cheeredPostIDs.insert(post.id)
        }
    }

    private func toggleClub(_ club: SocialClub) {
        if joinedClubIDs.contains(club.id) {
            joinedClubIDs.remove(club.id)
        } else {
            joinedClubIDs.insert(club.id)
        }
    }

    private func toggleShared(_ activity: SavedActivity) {
        if sharedActivityIDs.contains(activity.id) {
            sharedActivityIDs.remove(activity.id)
        } else {
            sharedActivityIDs.insert(activity.id)
        }
    }
}

private enum SocialFeedScope: String, CaseIterable, Identifiable {
    case squad = "Squad"
    case clubs = "Clubs"
    case rivals = "Rivals"

    var id: String { rawValue }
}

private struct SocialMetricPill: View {
    let value: String
    let label: String
    let symbol: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.caption.bold())
                .foregroundStyle(.orange)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.callout.bold())
                    .monospacedDigit()
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct CrewPulseAvatar: View {
    let person: SocialPerson

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                AvatarCircle(initials: person.initials, tint: person.tint, size: 58)
                    .overlay {
                        Circle()
                            .stroke(person.isRunning ? Color.green : Color.clear, lineWidth: 3)
                    }

                Circle()
                    .fill(person.isRunning ? Color.green : Color(.systemGray3))
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color(.systemGroupedBackground), lineWidth: 2))
            }

            Text(person.firstName)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .frame(width: 68)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(person.firstName), \(person.isRunning ? "running" : "offline")")
    }
}

private struct ShareLatestRunCard: View {
    let activity: SavedActivity
    let activityStore: ActivityStore
    let isShared: Bool
    let onToggleShare: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                    Text(isShared ? "Shared with Squad" : "Ready to Share")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                }

                Text(activity.title)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    SocialStat(symbol: "figure.run", value: String(format: "%.2f km", activity.distanceM / 1000))
                    SocialStat(symbol: "timer", value: activity.durationSecs.formatted())
                    if let pace = activity.avgPace {
                        SocialStat(symbol: "speedometer", value: pace.paceString)
                    }
                }
            }

            Spacer(minLength: 0)

            Button(isShared ? "Posted" : "Share") {
                onToggleShare()
            }
            .font(.subheadline.bold())
            .buttonStyle(.borderedProminent)
            .tint(isShared ? .green : .orange)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let photo = activity.photos.first, let url = activityStore.imageURL(for: photo) {
            LocalImageView(url: url) {
                Color.orange.opacity(0.18)
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RouteMiniTile()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct SocialFeedPostCard: View {
    let post: SocialFeedPost
    let isCheered: Bool
    let onCheer: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AvatarCircle(initials: post.author.initials, tint: post.author.tint, size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(post.author.fullName)
                            .font(.subheadline.bold())
                            .lineLimit(1)
                        if post.isLive {
                            LiveBadge()
                        }
                    }

                    Text(post.context)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: post.kind.symbol)
                    .font(.headline)
                    .foregroundStyle(post.kind.tint)
                    .frame(width: 34, height: 34)
                    .background(post.kind.tint.opacity(0.12), in: Circle())
            }

            Text(post.caption)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            RoutePreviewCard(post: post)

            HStack(spacing: 10) {
                SocialActionButton(
                    title: isCheered ? "Cheered" : "Cheer",
                    symbol: "hands.clap.fill",
                    isActive: isCheered,
                    action: onCheer
                )

                SocialActionButton(title: "\(post.comments)", symbol: "bubble.left.fill", isActive: false) { }
                SocialActionButton(title: "Run it", symbol: "arrow.triangle.turn.up.right.circle.fill", isActive: false) { }

                Spacer()

                Text("\(post.cheers + (isCheered ? 1 : 0))")
                    .font(.caption.bold())
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct RoutePreviewCard: View {
    let post: SocialFeedPost

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: post.gradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RouteLineShape()
                .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .padding(18)

            HStack(spacing: 10) {
                SocialStat(symbol: "figure.run", value: String(format: "%.1f km", post.activity.distanceKm))
                SocialStat(symbol: "timer", value: post.activity.duration)
                SocialStat(symbol: "speedometer", value: post.activity.pace)
            }
            .padding(10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(10)
        }
        .frame(height: 168)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .topTrailing) {
            Text(post.activity.routeName)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(.black.opacity(0.28), in: Capsule())
                .padding(10)
        }
    }
}

private struct SocialClubCard: View {
    let club: SocialClub
    let isJoined: Bool
    let onToggleJoin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: club.symbol)
                    .font(.title3)
                    .foregroundStyle(club.tint)
                    .frame(width: 42, height: 42)
                    .background(club.tint.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(club.name)
                        .font(.headline)
                    Text(club.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button(isJoined ? "Joined" : "Join") {
                    onToggleJoin()
                }
                .font(.subheadline.bold())
                .buttonStyle(.bordered)
                .tint(isJoined ? .green : .orange)
            }

            HStack(spacing: 12) {
                AvatarStack(initials: club.memberInitials, tint: club.tint)
                Text("\(club.memberCount) runners")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(club.nextRun)
                    .font(.caption.bold())
                    .foregroundStyle(club.tint)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SocialChallengeCard: View {
    let challenge: SocialChallenge

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: challenge.progress)
                    .stroke(challenge.tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(challenge.progress * 100))%")
                    .font(.caption.bold())
                    .monospacedDigit()
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 5) {
                Text(challenge.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(challenge.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(challenge.reward)
                    .font(.caption.bold())
                    .foregroundStyle(challenge.tint)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct RivalryHeaderCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Weekly Loop")
                        .font(.headline)
                    Text("You are 1.8 km behind Maya")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "flag.checkered")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }

            ProgressView(value: 0.78)
                .tint(.blue)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct RivalRow: View {
    let rival: SocialRival

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rival.rank)")
                .font(.headline.monospacedDigit())
                .frame(width: 28)
                .foregroundStyle(.secondary)

            AvatarCircle(initials: rival.person.initials, tint: rival.person.tint, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(rival.person.fullName)
                    .font(.subheadline.bold())
                Text(rival.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(String(format: "%.1f km", rival.weeklyKm))
                    .font(.subheadline.bold())
                Text(rival.delta)
                    .font(.caption)
                    .foregroundStyle(rival.delta.hasPrefix("+") ? .green : .secondary)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SocialActionButton: View {
    let title: String
    let symbol: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.caption.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .buttonStyle(.bordered)
        .tint(isActive ? .orange : .secondary)
    }
}

private struct SocialStat: View {
    let symbol: String
    let value: String

    var body: some View {
        Label(value, systemImage: symbol)
            .font(.caption.bold())
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }
}

private struct AvatarCircle: View {
    let initials: String
    let tint: Color
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(tint.gradient)
            .frame(width: size, height: size)
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.33, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
            }
    }
}

private struct AvatarStack: View {
    let initials: [String]
    let tint: Color

    var body: some View {
        HStack(spacing: -10) {
            ForEach(Array(initials.prefix(4)), id: \.self) { item in
                AvatarCircle(initials: item, tint: tint, size: 28)
                    .overlay(Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2))
            }
        }
    }
}

private struct LiveBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(.green)
                .frame(width: 6, height: 6)
            Text("LIVE")
                .font(.caption2.bold())
        }
        .foregroundStyle(.green)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.green.opacity(0.12), in: Capsule())
    }
}

private struct RouteMiniTile: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [.orange.opacity(0.7), .blue.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
            RouteLineShape()
                .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .padding(10)
        }
    }
}

private struct RouteLineShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.midY + rect.height * 0.22))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.22),
            control1: CGPoint(x: rect.minX + rect.width * 0.24, y: rect.maxY),
            control2: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.minY)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.midY - rect.height * 0.18),
            control1: CGPoint(x: rect.maxX - rect.width * 0.25, y: rect.minY + rect.height * 0.42),
            control2: CGPoint(x: rect.maxX - rect.width * 0.24, y: rect.maxY - rect.height * 0.18)
        )
        return path
    }
}

private struct RelayComposerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Invite runners into a shared route, live pace board, and finish-line thread.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                RelayOptionRow(symbol: "location.fill", title: "Neighborhood Loop", subtitle: "3.2 km near home")
                RelayOptionRow(symbol: "clock.fill", title: "Lunch Window", subtitle: "Open for the next 45 minutes")
                RelayOptionRow(symbol: "person.2.fill", title: "Squad Only", subtitle: "Maya, Leo, Zoe, Chen")

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Label("Create Relay", systemImage: "bolt.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding(20)
            .navigationTitle("New Relay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct RelayOptionRow: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(.orange)
                .frame(width: 38, height: 38)
                .background(.orange.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.bold())
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SocialPerson: Identifiable {
    let id: String
    let firstName: String
    let fullName: String
    let initials: String
    let tint: Color
    let isRunning: Bool
}

private struct SocialFeedPost: Identifiable {
    let id: String
    let author: SocialPerson
    let context: String
    let caption: String
    let activity: SocialActivitySummary
    let kind: SocialPostKind
    let gradient: [Color]
    let isLive: Bool
    let cheers: Int
    let comments: Int
}

private struct SocialActivitySummary {
    let routeName: String
    let distanceKm: Double
    let duration: String
    let pace: String
}

private enum SocialPostKind {
    case run
    case relay
    case challenge

    var symbol: String {
        switch self {
        case .run: return "figure.run"
        case .relay: return "bolt.fill"
        case .challenge: return "flag.checkered"
        }
    }

    var tint: Color {
        switch self {
        case .run: return .orange
        case .relay: return .green
        case .challenge: return .blue
        }
    }
}

private struct SocialClub: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let memberInitials: [String]
    let memberCount: Int
    let nextRun: String
}

private struct SocialChallenge: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let reward: String
    let progress: Double
    let tint: Color
}

private struct SocialRival: Identifiable {
    let id: String
    let rank: Int
    let person: SocialPerson
    let weeklyKm: Double
    let delta: String
    let note: String
}

private enum SocialSeed {
    static let maya = SocialPerson(id: "maya", firstName: "Maya", fullName: "Maya Chen", initials: "MC", tint: .orange, isRunning: true)
    static let leo = SocialPerson(id: "leo", firstName: "Leo", fullName: "Leo Park", initials: "LP", tint: .blue, isRunning: true)
    static let zoe = SocialPerson(id: "zoe", firstName: "Zoe", fullName: "Zoe Kim", initials: "ZK", tint: .pink, isRunning: false)
    static let noah = SocialPerson(id: "noah", firstName: "Noah", fullName: "Noah Singh", initials: "NS", tint: .green, isRunning: true)
    static let ava = SocialPerson(id: "ava", firstName: "Ava", fullName: "Ava Brooks", initials: "AB", tint: .purple, isRunning: false)
    static let chen = SocialPerson(id: "chen", firstName: "Chen", fullName: "Chen Li", initials: "CL", tint: .teal, isRunning: true)

    static let people = [maya, leo, zoe, noah, ava, chen]

    static let feedPosts = [
        SocialFeedPost(
            id: "maya-waterfront",
            author: maya,
            context: "Waterfront Loop - 8 min ago",
            caption: "Negative split the last kilometer. Someone take this segment before dinner.",
            activity: SocialActivitySummary(routeName: "Pier Dash", distanceKm: 5.4, duration: "26:12", pace: "4:51 /km"),
            kind: .challenge,
            gradient: [.orange.opacity(0.85), .blue.opacity(0.62)],
            isLive: false,
            cheers: 18,
            comments: 4
        ),
        SocialFeedPost(
            id: "leo-relay",
            author: leo,
            context: "Mission Relay - live now",
            caption: "Holding a conversational pace for anyone who wants to jump in remotely.",
            activity: SocialActivitySummary(routeName: "Mission Grid", distanceKm: 3.1, duration: "15:48", pace: "5:05 /km"),
            kind: .relay,
            gradient: [.green.opacity(0.82), .cyan.opacity(0.55)],
            isLive: true,
            cheers: 11,
            comments: 7
        ),
        SocialFeedPost(
            id: "zoe-hills",
            author: zoe,
            context: "Twin Peaks - yesterday",
            caption: "Hill repeats are better when the group chat is watching.",
            activity: SocialActivitySummary(routeName: "Peak Steps", distanceKm: 6.8, duration: "41:03", pace: "6:02 /km"),
            kind: .run,
            gradient: [.pink.opacity(0.78), .orange.opacity(0.58)],
            isLive: false,
            cheers: 24,
            comments: 6
        )
    ]

    static let clubs = [
        SocialClub(
            id: "sf-dawn",
            name: "SF Dawn Patrol",
            subtitle: "Early runs, quiet streets, coffee after.",
            symbol: "sunrise.fill",
            tint: .orange,
            memberInitials: ["MC", "LP", "ZK", "CL"],
            memberCount: 128,
            nextRun: "Tue 6:30"
        ),
        SocialClub(
            id: "founders",
            name: "Founders 5K",
            subtitle: "Fast lunch loops for builders and designers.",
            symbol: "building.2.fill",
            tint: .blue,
            memberInitials: ["AB", "NS", "LP", "MC"],
            memberCount: 74,
            nextRun: "Today"
        )
    ]

    static let challenges = [
        SocialChallenge(
            id: "seven-day-chain",
            title: "7 Day Chain",
            subtitle: "Four teammates have checked in today.",
            reward: "2 days left",
            progress: 0.71,
            tint: .green
        ),
        SocialChallenge(
            id: "city-segments",
            title: "City Segments",
            subtitle: "Own three short routes before Sunday.",
            reward: "1 segment held",
            progress: 0.33,
            tint: .blue
        )
    ]

    static let rivals = [
        SocialRival(id: "r1", rank: 1, person: maya, weeklyKm: 32.4, delta: "+1.8 km", note: "Won Pier Dash"),
        SocialRival(id: "r2", rank: 2, person: chen, weeklyKm: 30.6, delta: "You", note: "2 runs logged"),
        SocialRival(id: "r3", rank: 3, person: leo, weeklyKm: 28.1, delta: "-2.5 km", note: "Live relay open"),
        SocialRival(id: "r4", rank: 4, person: zoe, weeklyKm: 24.7, delta: "-5.9 km", note: "Climbing week")
    ]
}
