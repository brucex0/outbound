import Combine
import Foundation

@MainActor
final class TogetherStore: ObservableObject {
    @Published private(set) var state: TogetherResponseDTO
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var latestInvitationURL: URL?
    @Published private(set) var connections: [SocialConnectionDTO] = []
    @Published private(set) var peopleResults: [SocialPersonSearchResultDTO] = []
    @Published private(set) var isConnectionsLoading = false
    @Published private(set) var commentsByPostID: [String: [TogetherCommentDTO]] = [:]
    @Published private(set) var isSocialMutationPending = false
    @Published private(set) var notifications: [SocialNotificationDTO] = []
    @Published private(set) var discoverableGroups: [SocialGroupDTO] = []
    @Published private(set) var blocks: [SocialBlockDTO] = []

    private let api: APIClient
    private let defaults: UserDefaults
    private let cacheKey = "together_state_v1"

    init(api: APIClient? = nil, defaults: UserDefaults = .standard) {
        self.api = api ?? .shared
        self.defaults = defaults
        state = ProcessInfo.processInfo.arguments.contains("-OutboundUITestSeedData")
            ? Self.uiTestFixture
            : Self.decode(TogetherResponseDTO.self, from: defaults.data(forKey: cacheKey))
                ?? TogetherResponseDTO(upcomingRuns: [], clubs: [], posts: [])
        if isUITestSeedData {
            connections = Self.uiTestConnections
            notifications = Self.uiTestNotifications
            discoverableGroups = Self.uiTestGroups
            blocks = Self.uiTestBlocks
        }
    }

    func refresh() async {
        if ProcessInfo.processInfo.arguments.contains("-OutboundUITestSeedData") {
            state = Self.uiTestFixture
            errorMessage = nil
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            state = try await api.fetchTogether()
            persist()
            errorMessage = nil
        } catch {
            errorMessage = state.upcomingRuns.isEmpty && state.posts.isEmpty
                ? "Together is unavailable. Your private training remains available."
                : "Showing saved Together activity."
        }
    }

    func invite(to run: TogetherGroupRunDTO) async {
        if isUITestSeedData {
            latestInvitationURL = URL(string: "https://plainstride.app/invite/ui-test-run")
            return
        }
        do {
            let invitation = try await api.createTogetherInvitation(runID: run.id)
            latestInvitationURL = PlainstrideLinks.scheduledRunInvitation(token: invitation.token)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func invite(_ connection: SocialConnectionDTO, to run: TogetherGroupRunDTO) async -> Bool {
        if isUITestSeedData { return true }
        do {
            _ = try await api.createTogetherInvitation(runID: run.id, recipientUserID: connection.person.id)
            await refreshNotifications()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func referralInvitationURL() async -> URL? {
        do {
            let referral = try await api.createReferralLink()
            errorMessage = nil
            return referral.url
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func react(to post: TogetherPostDTO) async {
        await toggleCheer(on: post)
    }

    func toggleCheer(on post: TogetherPostDTO) async {
        guard !isSocialMutationPending else { return }
        if isUITestSeedData {
            state = replacing(post: post, cheered: !post.currentUserCheered)
            return
        }
        isSocialMutationPending = true
        defer { isSocialMutationPending = false }
        do {
            if post.currentUserCheered {
                _ = try await api.removeCheerFromSocialPost(postID: post.id)
            } else {
                _ = try await api.cheerSocialPost(postID: post.id)
            }
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadComments(for post: TogetherPostDTO) async {
        if isUITestSeedData {
            commentsByPostID[post.id] = post.comments
            return
        }
        do {
            commentsByPostID[post.id] = try await api.fetchSocialComments(postID: post.id).comments
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addComment(_ body: String, to post: TogetherPostDTO) async {
        let cleaned = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        if isUITestSeedData {
            var comments = commentsByPostID[post.id] ?? post.comments
            comments.append(Self.uiTestComment(body: cleaned))
            commentsByPostID[post.id] = comments
            return
        }
        do {
            _ = try await api.commentOnSocialPost(postID: post.id, body: cleaned)
            await loadComments(for: post)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteComment(_ comment: TogetherCommentDTO, from post: TogetherPostDTO) async {
        do {
            _ = try await api.deleteSocialComment(id: comment.id)
            await loadComments(for: post)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func shareActivity(_ activity: SavedActivity, caption: String?) async -> Bool {
        if isUITestSeedData { return true }
        guard let serverActivityID = activity.sync?.serverActivityId else {
            errorMessage = "This activity is still syncing. Try sharing again shortly."
            return false
        }
        do {
            _ = try await api.shareSocialActivity(activityID: serverActivityID, caption: caption)
            await refresh()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func refreshConnections() async {
        if isUITestSeedData {
            connections = connections.isEmpty ? Self.uiTestConnections : connections
            return
        }
        isConnectionsLoading = true
        defer { isConnectionsLoading = false }
        do {
            connections = try await api.fetchSocialConnections().connections
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func searchPeople(_ query: String) async {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 2 else {
            peopleResults = []
            return
        }
        if isUITestSeedData {
            peopleResults = Self.uiTestPeople.filter {
                $0.displayName.localizedCaseInsensitiveContains(cleaned)
                    || $0.username.localizedCaseInsensitiveContains(cleaned)
            }
            return
        }
        do {
            peopleResults = try await api.searchSocialPeople(query: cleaned).people
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requestConnection(to person: SocialPersonSearchResultDTO) async {
        do {
            _ = try await api.requestSocialConnection(userID: person.id)
            await refreshConnections()
            await searchPeople(person.username)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func acceptConnection(_ connection: SocialConnectionDTO) async {
        if isUITestSeedData {
            replaceConnection(connection, status: "accepted", direction: "incoming")
            return
        }
        do {
            _ = try await api.acceptSocialConnection(id: connection.id)
            await refreshConnections()
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeConnection(_ connection: SocialConnectionDTO) async {
        if isUITestSeedData {
            connections.removeAll { $0.id == connection.id }
            return
        }
        do {
            _ = try await api.removeSocialConnection(id: connection.id)
            await refreshConnections()
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        defaults.set(try? encoder.encode(state), forKey: cacheKey)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    private var isUITestSeedData: Bool {
        ProcessInfo.processInfo.arguments.contains("-OutboundUITestSeedData")
    }

    private static var uiTestFixture: TogetherResponseDTO {
        let club = TogetherClubDTO(
            id: "ui-test-club",
            name: "Golden Gate Run Club",
            description: "Friendly local miles for every pace.",
            city: "San Francisco",
            role: "member"
        )
        let maya = TogetherPersonDTO(id: "ui-test-maya", displayName: "Maya Chen", avatarUrl: nil)
        return TogetherResponseDTO(
            upcomingRuns: [
                TogetherGroupRunDTO(
                    id: "ui-test-saturday-5k",
                    title: "Saturday waterfront 5K",
                    startsAt: Date().addingTimeInterval(86_400),
                    locationName: "Crissy Field",
                    paceNote: "Conversational pace",
                    club: club,
                    creator: maya,
                    groups: [TogetherRunGroupDTO(id: "ui-test-social", label: "Social", distanceMeters: 5_000, paceMinSeconds: 330, paceMaxSeconds: 390)],
                    compatibility: TogetherCompatibilityDTO(groupId: "ui-test-social", explanation: "This easy group matches your current training week.")
                ),
            ],
            clubs: [club],
            posts: [
                TogetherPostDTO(
                    id: "ui-test-post",
                    caption: "Easy miles and good company this morning.",
                    createdAt: Date().addingTimeInterval(-3_600),
                    isCurrentUser: false,
                    user: maya,
                    activity: TogetherActivityDTO(id: "ui-test-social-activity", title: "Presidio Morning Run", durationSecs: 2_040, distanceM: 5_800, avgPace: 352),
                    reactionCount: 2,
                    currentUserCheered: false,
                    commentCount: 1,
                    comments: [TogetherCommentDTO(
                        id: "ui-test-comment",
                        body: "See you next time!",
                        createdAt: Date().addingTimeInterval(-1_800),
                        author: SocialPersonDTO(id: "ui-test-maya", username: "maya", displayName: "Maya Chen", avatarUrl: nil),
                        canDelete: false
                    )]
                ),
            ]
        )
    }

    var unreadNotificationCount: Int { notifications.filter { $0.readAt == nil }.count }

    func refreshNotifications() async {
        if isUITestSeedData {
            notifications = notifications.isEmpty ? Self.uiTestNotifications : notifications
            return
        }
        do {
            notifications = try await api.fetchSocialNotifications().notifications
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func markNotificationsRead() async {
        if isUITestSeedData {
            notifications = notifications.map {
                SocialNotificationDTO(id: $0.id, type: $0.type, objectId: $0.objectId, message: $0.message, readAt: $0.readAt ?? Date(), createdAt: $0.createdAt, actor: $0.actor)
            }
            return
        }
        do {
            _ = try await api.markSocialNotificationsRead()
            await refreshNotifications()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reportPost(_ post: TogetherPostDTO, reason: String) async {
        do {
            _ = try await api.reportSocialContent(SocialReportRequestDTO(targetType: "post", targetId: post.id, reason: reason, details: nil))
            state = TogetherResponseDTO(upcomingRuns: state.upcomingRuns, clubs: state.clubs, posts: state.posts.filter { $0.id != post.id })
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func blockAuthor(of post: TogetherPostDTO) async {
        do {
            _ = try await api.blockSocialUser(id: post.user.id)
            await refreshConnections()
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshGroups() async {
        if isUITestSeedData {
            discoverableGroups = discoverableGroups.isEmpty ? Self.uiTestGroups : discoverableGroups
            return
        }
        do {
            discoverableGroups = try await api.fetchSocialGroups().groups
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleMembership(in group: SocialGroupDTO) async {
        if isUITestSeedData {
            discoverableGroups = discoverableGroups.map {
                guard $0.id == group.id else { return $0 }
                return SocialGroupDTO(id: $0.id, name: $0.name, description: $0.description, city: $0.city, memberCount: max(0, $0.memberCount + ($0.membershipRole == nil ? 1 : -1)), membershipRole: $0.membershipRole == nil ? "member" : nil)
            }
            return
        }
        do {
            if group.membershipRole == nil {
                _ = try await api.joinSocialGroup(id: group.id)
            } else {
                _ = try await api.leaveSocialGroup(id: group.id)
            }
            await refreshGroups()
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func groupRunDetail(id: String) async -> SocialGroupRunDetailDTO? {
        if isUITestSeedData {
            guard let run = state.upcomingRuns.first(where: { $0.id == id }) else { return nil }
            return Self.uiTestRunDetail(run: run, isGoing: false)
        }
        do {
            let detail = try await api.fetchSocialGroupRun(id: id)
            errorMessage = nil
            return detail
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func toggleRSVP(for run: SocialGroupRunDetailDTO) async -> SocialGroupRunDetailDTO? {
        if isUITestSeedData {
            guard let fixture = state.upcomingRuns.first(where: { $0.id == run.id }) else { return nil }
            return Self.uiTestRunDetail(run: fixture, isGoing: !run.currentUserGoing)
        }
        do {
            if run.currentUserGoing {
                _ = try await api.leaveSocialGroupRun(id: run.id)
            } else {
                _ = try await api.joinSocialGroupRun(id: run.id)
            }
            return await groupRunDetail(id: run.id)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func acceptRunInvitation(_ notification: SocialNotificationDTO) async {
        guard let invitationID = notification.objectId else { return }
        if isUITestSeedData {
            notifications.removeAll { $0.id == notification.id }
            return
        }
        do {
            _ = try await api.acceptSocialRunInvitation(id: invitationID)
            await refreshNotifications()
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deletePost(_ post: TogetherPostDTO) async {
        do {
            _ = try await api.deleteSocialPost(id: post.id)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reportComment(_ comment: TogetherCommentDTO) async {
        do {
            _ = try await api.reportSocialContent(SocialReportRequestDTO(targetType: "comment", targetId: comment.id, reason: "other", details: nil))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshBlocks() async {
        if isUITestSeedData {
            blocks = blocks.isEmpty ? Self.uiTestBlocks : blocks
            return
        }
        do {
            blocks = try await api.fetchSocialBlocks().blocks
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func unblock(_ block: SocialBlockDTO) async {
        if isUITestSeedData {
            blocks.removeAll { $0.id == block.id }
            return
        }
        do {
            _ = try await api.unblockSocialUser(id: block.person.id)
            await refreshBlocks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func replacing(post: TogetherPostDTO, cheered: Bool) -> TogetherResponseDTO {
        let posts = state.posts.map { current in
            guard current.id == post.id else { return current }
            return TogetherPostDTO(
                id: current.id,
                caption: current.caption,
                createdAt: current.createdAt,
                isCurrentUser: current.isCurrentUser,
                user: current.user,
                activity: current.activity,
                reactionCount: max(0, current.reactionCount + (cheered ? 1 : -1)),
                currentUserCheered: cheered,
                commentCount: current.commentCount,
                comments: current.comments
            )
        }
        return TogetherResponseDTO(upcomingRuns: state.upcomingRuns, clubs: state.clubs, posts: posts)
    }

    private func replaceConnection(_ connection: SocialConnectionDTO, status: String, direction: String) {
        connections = connections.map {
            $0.id == connection.id
                ? SocialConnectionDTO(id: $0.id, status: status, direction: direction, person: $0.person)
                : $0
        }
    }

    private static let uiTestConnections = [
        SocialConnectionDTO(id: "ui-connection-maya", status: "accepted", direction: "incoming", person: SocialPersonDTO(id: "ui-maya", username: "maya", displayName: "Maya Chen", avatarUrl: nil)),
        SocialConnectionDTO(id: "ui-connection-leo", status: "pending", direction: "incoming", person: SocialPersonDTO(id: "ui-leo", username: "leo.runs", displayName: "Leo Martinez", avatarUrl: nil)),
        SocialConnectionDTO(id: "ui-connection-priya", status: "pending", direction: "outgoing", person: SocialPersonDTO(id: "ui-priya", username: "priya.trails", displayName: "Priya Shah", avatarUrl: nil)),
    ]

    private static let uiTestPeople = [
        SocialPersonSearchResultDTO(id: "ui-jordan", username: "jordan.miles", displayName: "Jordan Miles", avatarUrl: nil, relationship: nil),
        SocialPersonSearchResultDTO(id: "ui-maya", username: "maya", displayName: "Maya Chen", avatarUrl: nil, relationship: SocialRelationshipDTO(id: "ui-connection-maya", status: "accepted", direction: "incoming")),
    ]

    private static let uiTestGroups = [
        SocialGroupDTO(id: "ui-test-club", name: "Golden Gate Run Club", description: "Friendly local miles for every pace.", city: "San Francisco", memberCount: 128, membershipRole: "member"),
        SocialGroupDTO(id: "ui-sunset-group", name: "Sunset Striders", description: "Easy evening runs by the ocean.", city: "San Francisco", memberCount: 42, membershipRole: nil),
    ]

    private static let uiTestNotifications = [
        SocialNotificationDTO(id: "ui-notification-request", type: "connectionRequest", objectId: "ui-connection-leo", message: "Leo Martinez wants to connect.", readAt: nil, createdAt: Date().addingTimeInterval(-600), actor: SocialPersonDTO(id: "ui-leo", username: "leo.runs", displayName: "Leo Martinez", avatarUrl: nil)),
        SocialNotificationDTO(id: "ui-notification-cheer", type: "cheer", objectId: "ui-test-post", message: "Maya Chen cheered your run.", readAt: nil, createdAt: Date().addingTimeInterval(-1_200), actor: SocialPersonDTO(id: "ui-maya", username: "maya", displayName: "Maya Chen", avatarUrl: nil)),
        SocialNotificationDTO(id: "ui-notification-run", type: "runInvitation", objectId: "ui-invitation-run", message: "Maya Chen invited you to Saturday waterfront 5K.", readAt: nil, createdAt: Date().addingTimeInterval(-1_800), actor: SocialPersonDTO(id: "ui-maya", username: "maya", displayName: "Maya Chen", avatarUrl: nil)),
    ]

    private static let uiTestBlocks = [
        SocialBlockDTO(id: "ui-block", person: SocialPersonDTO(id: "ui-blocked", username: "blocked.runner", displayName: "Blocked Runner", avatarUrl: nil)),
    ]

    private static func uiTestRunDetail(run: TogetherGroupRunDTO, isGoing: Bool) -> SocialGroupRunDetailDTO {
        SocialGroupRunDetailDTO(id: run.id, title: run.title, startsAt: run.startsAt, locationName: run.locationName, paceNote: run.paceNote, club: run.club, creator: run.creator, groups: run.groups, attendeeCount: isGoing ? 19 : 18, currentUserGoing: isGoing, compatibility: run.compatibility)
    }

    private static func uiTestComment(body: String) -> TogetherCommentDTO {
        TogetherCommentDTO(id: "ui-comment-\(UUID().uuidString)", body: body, createdAt: Date(), author: SocialPersonDTO(id: "ui-current", username: "ui.tester", displayName: "UI Test Runner", avatarUrl: nil), canDelete: true)
    }
}

struct ReferralLinkResponseDTO: Decodable {
    let code: String
    let url: URL
    let clickCount: Int
    let claimCount: Int
}

struct ReferralClaimResponseDTO: Decodable {
    let claimed: Bool
    let reason: String?
}
