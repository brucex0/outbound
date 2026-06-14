#if OUTBOUND_ENABLE_SOCIAL
import SwiftUI

struct ActivityFeedView: View {
    @EnvironmentObject private var activityStore: ActivityStore
    @EnvironmentObject private var socialStore: SocialStore
    @EnvironmentObject private var socialRecognitionStore: SocialRecognitionStore
    let bottomContentInset: CGFloat
    @State private var selectedScope: SocialFeedScope = .squad
    @State private var showingRelayComposer = false
    @State private var selectedCommentPost: SocialFeedPost?
    @State private var routePrompt: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    socialCommandBar
                    if let socialHighlight = socialRecognitionStore.highlight {
                        SocialRecognitionCard(preview: socialHighlight)
                    }
                    crewPulseStrip
                    scopePicker
                    PrivacyControlCard(visibility: $socialStore.defaultVisibility)

                    if let latestActivity = activityStore.activities.first {
                        ShareLatestRunCard(
                            activity: latestActivity,
                            activityStore: activityStore,
                            isShared: socialRecognitionStore.sharedActivityIDs.contains(latestActivity.id)
                        ) {
                            toggleShared(latestActivity)
                        }
                    }

                    if let routePrompt {
                        SocialStatusCard(symbol: "arrow.triangle.turn.up.right.circle.fill", title: "Route prompt saved", message: routePrompt)
                    }

                    if !socialStore.reportedContentIDs.isEmpty || !socialStore.blockedPersonIDs.isEmpty {
                        SocialStatusCard(
                            symbol: "checkmark.shield.fill",
                            title: "Local safety controls active",
                            message: "\(socialStore.reportedContentIDs.count) report\(socialStore.reportedContentIDs.count == 1 ? "" : "s") and \(socialStore.blockedPersonIDs.count) block\(socialStore.blockedPersonIDs.count == 1 ? "" : "s") are hidden in this preview."
                        )
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
            .safeAreaInset(edge: .bottom) {
                Color.clear
                    .frame(height: bottomContentInset)
                    .allowsHitTesting(false)
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
                RelayComposerSheet { routeLabel, windowLabel, audienceLabel in
                    socialStore.createRelay(routeLabel: routeLabel, windowLabel: windowLabel, audienceLabel: audienceLabel)
                    _ = socialRecognitionStore.toggleClubMembership(clubID: "relay-preview")
                }
            }
            .sheet(item: $selectedCommentPost) { post in
                CommentThreadSheet(
                    post: post,
                    comments: socialStore.comments(for: post.id)
                ) { text in
                    socialStore.addComment(text, to: post.id)
                }
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
            ForEach(socialStore.relayInvites) { invite in
                RelayInviteCard(invite: invite)
            }

            ForEach(SocialSeed.feedPosts) { post in
                if !socialStore.blockedPersonIDs.contains(post.author.id) && !socialStore.reportedContentIDs.contains(post.id) {
                    SocialFeedPostCard(
                        post: post,
                        isCheered: socialStore.cheeredPostIDs.contains(post.id),
                        commentCount: socialStore.commentCount(for: post),
                        onCheer: {
                            toggleCheer(for: post)
                        },
                        onComment: {
                            selectedCommentPost = post
                        },
                        onRunRoute: {
                            routePrompt = "\(post.activity.routeName) is queued as a route idea for your next start."
                        },
                        onReport: {
                            socialStore.reportContent(post.id)
                        },
                        onBlock: {
                            socialStore.blockPerson(post.author.id)
                        }
                    )
                }
            }
        }
    }

    private var clubsAndChallenges: some View {
        LazyVStack(spacing: 12) {
            ForEach(SocialSeed.clubs) { club in
                SocialClubCard(
                    club: club,
                    isJoined: socialRecognitionStore.joinedClubIDs.contains(club.id)
                ) {
                    toggleClub(club)
                }
            }

            ForEach(SocialSeed.challenges) { challenge in
                SocialChallengeCard(
                    challenge: challenge,
                    isJoined: socialStore.joinedChallengeIDs.contains(challenge.id)
                ) {
                    socialStore.toggleChallenge(challenge.id)
                }
            }
        }
    }

    private var rivalBoard: some View {
        LazyVStack(spacing: 12) {
            RivalryHeaderCard(hasClaimedEdge: socialRecognitionStore.claimedRivalEdge) {
                _ = socialRecognitionStore.claimRivalEdge()
            }

            ForEach(SocialSeed.rivals) { rival in
                RivalRow(rival: rival)
            }
        }
    }

    private func toggleCheer(for post: SocialFeedPost) {
        if socialStore.toggleCheer(for: post.id) {
            _ = socialRecognitionStore.registerCheer(for: post.id)
        }
    }

    private func toggleClub(_ club: SocialClub) {
        _ = socialRecognitionStore.toggleClubMembership(clubID: club.id)
    }

    private func toggleShared(_ activity: SavedActivity) {
        _ = socialRecognitionStore.toggleShare(for: activity)
    }
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

private struct PrivacyControlCard: View {
    @Binding var visibility: SocialVisibility

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Default visibility", systemImage: "lock.shield.fill")
                    .font(.subheadline.bold())
                Spacer()
                Text("Local preview")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            Picker("Default visibility", selection: $visibility) {
                ForEach(SocialVisibility.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SocialStatusCard: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(.green)
                .frame(width: 34, height: 34)
                .background(.green.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.bold())
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
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
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
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
                    SocialStat(symbol: "figure.run", value: measurementPreferences.unitSystem.distanceString(meters: activity.distanceM))
                    SocialStat(symbol: "timer", value: activity.durationSecs.formatted())
                    if let pace = activity.avgPace {
                        SocialStat(symbol: "speedometer", value: pace.paceString(for: measurementPreferences.unitSystem))
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

private struct RelayInviteCard: View {
    let invite: SocialRelayInvite

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.fill")
                .font(.title3.bold())
                .foregroundStyle(.green)
                .frame(width: 42, height: 42)
                .background(.green.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text("Relay invite created")
                    .font(.headline)
                Text("\(invite.routeLabel) - \(invite.windowLabel) - \(invite.audienceLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            LiveBadge()
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SocialFeedPostCard: View {
    let post: SocialFeedPost
    let isCheered: Bool
    let commentCount: Int
    let onCheer: () -> Void
    let onComment: () -> Void
    let onRunRoute: () -> Void
    let onReport: () -> Void
    let onBlock: () -> Void

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

                Menu {
                    Button("Report post", systemImage: "exclamationmark.bubble") {
                        onReport()
                    }
                    Button("Block \(post.author.firstName)", systemImage: "person.crop.circle.badge.xmark", role: .destructive) {
                        onBlock()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                        .background(Color(.tertiarySystemGroupedBackground), in: Circle())
                }
                .accessibilityLabel("Post options")
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

                SocialActionButton(title: "\(commentCount)", symbol: "bubble.left.fill", isActive: false, action: onComment)
                SocialActionButton(title: "Run it", symbol: "arrow.triangle.turn.up.right.circle.fill", isActive: false, action: onRunRoute)

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
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
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
                SocialStat(symbol: "figure.run", value: post.activity.distanceText(unitSystem: measurementPreferences.unitSystem))
                SocialStat(symbol: "timer", value: post.activity.duration)
                SocialStat(symbol: "speedometer", value: post.activity.paceText(unitSystem: measurementPreferences.unitSystem))
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
    let isJoined: Bool
    let onToggleJoin: () -> Void

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

            Button(isJoined ? "Joined" : "Join") {
                onToggleJoin()
            }
            .font(.caption.bold())
            .buttonStyle(.bordered)
            .tint(isJoined ? .green : challenge.tint)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct RivalryHeaderCard: View {
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    let hasClaimedEdge: Bool
    let onClaimEdge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Weekly Loop")
                        .font(.headline)
                    Text("You are \(measurementPreferences.unitSystem.distanceString(meters: 1800, fractionDigits: 1)) behind Maya")
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

            Button(hasClaimedEdge ? "Edge logged" : "Log this week's edge") {
                onClaimEdge()
            }
            .font(.caption.bold())
            .buttonStyle(.bordered)
            .tint(hasClaimedEdge ? .green : .blue)
            .disabled(hasClaimedEdge)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SocialRecognitionCard: View {
    let preview: SocialRecognitionPreview

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: preview.symbolName)
                .font(.headline.weight(.bold))
                .foregroundStyle(.orange)
                .frame(width: 38, height: 38)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(preview.title)
                    .font(.subheadline.bold())
                Text(preview.coachLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct RivalRow: View {
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
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
                Text(rival.weeklyDistanceText(unitSystem: measurementPreferences.unitSystem))
                    .font(.subheadline.bold())
                Text(rival.deltaText(unitSystem: measurementPreferences.unitSystem))
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

private struct CommentThreadSheet: View {
    @Environment(\.dismiss) private var dismiss
    let post: SocialFeedPost
    let comments: [SocialComment]
    let onSend: (String) -> Void
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    Section {
                        Text(post.caption)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    } header: {
                        Text(post.author.fullName)
                    }

                    Section("Thread") {
                        if comments.isEmpty {
                            Text("No comments yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(comments) { comment in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(comment.authorName)
                                        .font(.caption.bold())
                                    Text(comment.text)
                                        .font(.subheadline)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }

                HStack(spacing: 10) {
                    TextField("Add a comment", text: $draft)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        onSend(draft)
                        draft = ""
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(12)
                .background(.bar)
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct RelayComposerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onCreate: (String, String, String) -> Void
    @State private var selectedRoute = "Neighborhood Loop"
    @State private var selectedWindow = "Lunch Window"
    @State private var selectedAudience = "Squad Only"

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Invite runners into a shared route, live pace board, and finish-line thread.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                RelayOptionPicker(
                    symbol: "location.fill",
                    title: "Route",
                    options: ["Neighborhood Loop", "Waterfront Out-and-Back", "Track Ladder"],
                    selection: $selectedRoute
                )
                RelayOptionPicker(
                    symbol: "clock.fill",
                    title: "Window",
                    options: ["Lunch Window", "After Work", "Weekend Morning"],
                    selection: $selectedWindow
                )
                RelayOptionPicker(
                    symbol: "person.2.fill",
                    title: "Audience",
                    options: ["Squad Only", "Club Members", "Rivals"],
                    selection: $selectedAudience
                )

                Spacer()

                Button {
                    onCreate(selectedRoute, selectedWindow, selectedAudience)
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

private struct RelayOptionPicker: View {
    let symbol: String
    let title: String
    let options: [String]
    @Binding var selection: String

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
                Picker(title, selection: $selection) {
                    ForEach(options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .labelsHidden()
            }

            Spacer()
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#endif
