import Combine
import Foundation

struct SocialPeopleSearchOutcome: Sendable {
    let count: Int
    let matchMode: String
}

@MainActor
final class TogetherStore: ObservableObject {
    @Published private(set) var state: TogetherResponseDTO
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMorePosts = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var latestInvitationURL: URL?
    @Published private(set) var connections: [SocialConnectionDTO] = []
    @Published private(set) var hasLoadedConnections = false
    @Published private(set) var peopleResults: [SocialPersonSearchResultDTO] = []
    @Published private(set) var isConnectionsLoading = false
    @Published private(set) var isLoadingMoreConnections = false
    @Published private(set) var pendingConnectionIDs: Set<String> = []
    @Published private(set) var commentsByPostID: [String: [TogetherCommentDTO]] = [:]
    @Published private(set) var isSocialMutationPending = false
    @Published private(set) var notifications: [SocialNotificationDTO] = []
    @Published private(set) var discoverableGroups: [SocialGroupDTO] = []
    @Published private(set) var blocks: [SocialBlockDTO] = []
    @Published private(set) var resultsByActivityEventID: [String: ActivityEventResultDTO] = [:]
    @Published private(set) var recordingActivityEventID: String?

    private let api: APIClient
    private let defaults: UserDefaults
    private let cacheKey = "together_state_v1"
    private var nextConnectionsCursor: String?
    private var latestPeopleSearchQuery = ""

    var hasMoreConnections: Bool {
        nextConnectionsCursor != nil
    }

    init(api: APIClient? = nil, defaults: UserDefaults = .standard) {
        self.api = api ?? .shared
        self.defaults = defaults
        state = ProcessInfo.processInfo.arguments.contains("-OutboundUITestSeedData")
            ? Self.uiTestFixture
            : Self.decode(TogetherResponseDTO.self, from: defaults.data(forKey: cacheKey))
                ?? TogetherResponseDTO(upcomingRuns: [], clubs: [], posts: [])
        if isUITestSeedData {
            connections = Self.uiTestConnections
            hasLoadedConnections = true
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

    func loadMorePosts() async -> Int? {
        guard !isLoading, !isLoadingMorePosts, let cursor = state.nextFeedCursor else { return 0 }
        isLoadingMorePosts = true
        defer { isLoadingMorePosts = false }
        do {
            let page = try await api.fetchTogether(feedCursor: cursor)
            let existingIDs = Set(state.posts.map(\.id))
            let appendedPosts = page.posts.filter { !existingIDs.contains($0.id) }
            state = TogetherResponseDTO(
                upcomingRuns: state.upcomingRuns,
                pastEvents: state.pastEvents,
                clubs: state.clubs,
                posts: state.posts + appendedPosts,
                nextFeedCursor: page.nextFeedCursor
            )
            persist()
            errorMessage = nil
            return appendedPosts.count
        } catch {
            return nil
        }
    }

    func invite(to run: ActivityEventDTO) async {
        if isUITestSeedData {
            latestInvitationURL = URL(string: "https://plainstride.app/invite/ui-test-run")
            return
        }
        do {
            let invitation = try await api.createTogetherInvitation(runID: run.id)
            latestInvitationURL = PlainstrideLinks.activityEventInvitation(token: invitation.token)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func invitationURL(forActivityEvent id: String) async -> URL? {
        do {
            let invitation = try await api.createTogetherInvitation(runID: id)
            let url = PlainstrideLinks.activityEventInvitation(token: invitation.token)
            latestInvitationURL = url
            return url
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func invite(_ connection: SocialConnectionDTO, to run: ActivityEventDTO) async -> Bool {
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

    func createActivityEvent(_ request: CreateActivityEventRequestDTO) async -> ActivityEventDetailDTO? {
        do {
            let created = try await api.createActivityEvent(request)
            await refresh()
            errorMessage = nil
            return created
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func inviteConnections(_ userIDs: [String], toActivityEvent id: String) async -> Bool {
        guard !userIDs.isEmpty else { return true }
        do {
            _ = try await api.inviteConnections(userIDs, toActivityEvent: id)
            await refreshNotifications()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func loadActivityEventResults(id: String) async {
        do {
            resultsByActivityEventID[id] = try await api.fetchActivityEventResults(id: id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func markActivityEventWithoutRecording(id: String) async -> Bool {
        do {
            _ = try await api.markActivityEventWithoutRecording(id: id)
            await loadActivityEventResults(id: id)
            await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func prepareToRecord(activityEventID: String) {
        recordingActivityEventID = activityEventID
    }

    func acceptActivityEventInvitation(token: String) async -> Bool {
        do {
            _ = try await api.acceptActivityEventInvitation(token: token)
            await refresh()
            await refreshNotifications()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func consumeRecordingActivityEventID() -> String? {
        defer { recordingActivityEventID = nil }
        return recordingActivityEventID
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

    @discardableResult
    func toggleCheer(on post: TogetherPostDTO) async -> Bool {
        guard !isSocialMutationPending else { return false }
        let originalState = state
        state = replacing(post: post, cheered: !post.currentUserCheered)
        if isUITestSeedData {
            return true
        }
        isSocialMutationPending = true
        defer { isSocialMutationPending = false }
        do {
            if post.currentUserCheered {
                _ = try await api.removeCheerFromSocialPost(postID: post.id)
            } else {
                _ = try await api.cheerSocialPost(postID: post.id)
            }
            persist()
            return true
        } catch {
            state = originalState
            errorMessage = error.localizedDescription
            return false
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

    @discardableResult
    func addComment(_ body: String, to post: TogetherPostDTO) async -> Bool {
        let cleaned = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return false }
        let originalComments = commentsByPostID[post.id]
        let originalState = state
        let optimisticComment = TogetherCommentDTO(
            id: "pending-\(UUID().uuidString)",
            body: cleaned,
            createdAt: Date(),
            author: SocialPersonDTO(id: "current-user", username: "you", displayName: "You", avatarUrl: nil),
            canDelete: false
        )
        var comments = commentsByPostID[post.id] ?? post.comments
        comments.append(optimisticComment)
        commentsByPostID[post.id] = comments
        state = replacing(post: post, commentCountDelta: 1)
        if isUITestSeedData {
            return true
        }
        do {
            _ = try await api.commentOnSocialPost(postID: post.id, body: cleaned)
            await loadComments(for: post)
            persist()
            return true
        } catch {
            commentsByPostID[post.id] = originalComments
            state = originalState
            errorMessage = error.localizedDescription
            return false
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
            hasLoadedConnections = true
            nextConnectionsCursor = nil
            return
        }
        guard !isConnectionsLoading, !isLoadingMoreConnections else { return }
        isConnectionsLoading = true
        defer { isConnectionsLoading = false }
        do {
            let page = try await api.fetchSocialConnections()
            connections = page.connections
            hasLoadedConnections = true
            nextConnectionsCursor = page.nextCursor
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func loadMoreConnections() async -> Int? {
        guard !isConnectionsLoading, !isLoadingMoreConnections,
              let cursor = nextConnectionsCursor else { return 0 }
        isLoadingMoreConnections = true
        defer { isLoadingMoreConnections = false }
        do {
            let page = try await api.fetchSocialConnections(cursor: cursor)
            let existingIDs = Set(connections.map(\.id))
            let appended = page.connections.filter { !existingIDs.contains($0.id) }
            connections.append(contentsOf: appended)
            nextConnectionsCursor = page.nextCursor
            errorMessage = nil
            return appended.count
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func loadRemainingConnections() async {
        while nextConnectionsCursor != nil {
            guard await loadMoreConnections() != nil else { return }
        }
    }

    @discardableResult
    func searchPeople(_ query: String) async -> SocialPeopleSearchOutcome? {
        let cleaned = Self.normalizedPeopleSearchQuery(query)
        latestPeopleSearchQuery = cleaned
        guard !cleaned.isEmpty else {
            peopleResults = []
            return SocialPeopleSearchOutcome(count: 0, matchMode: "none")
        }
        if isUITestSeedData {
            peopleResults = Self.uiTestPeople.filter {
                $0.displayName.localizedCaseInsensitiveContains(cleaned)
                    || $0.username.localizedCaseInsensitiveContains(cleaned)
            }
            return SocialPeopleSearchOutcome(
                count: peopleResults.count,
                matchMode: peopleResults.isEmpty ? "none" : "literal"
            )
        }
        do {
            let response = try await api.searchSocialPeople(query: cleaned)
            guard latestPeopleSearchQuery == cleaned else { return nil }
            peopleResults = response.people
            errorMessage = nil
            return SocialPeopleSearchOutcome(
                count: peopleResults.count,
                matchMode: Self.analyticsSearchMatchMode(response.matchMode)
            )
        } catch {
            guard latestPeopleSearchQuery == cleaned else { return nil }
            errorMessage = error.localizedDescription
            return nil
        }
    }

    nonisolated static func normalizedPeopleSearchQuery(_ query: String) -> String {
        query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCompatibilityMapping
    }

    nonisolated private static func analyticsSearchMatchMode(_ value: String?) -> String {
        switch value {
        case "none", "literal", "fuzzy", "mixed": value ?? "unknown"
        default: "unknown"
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
        guard pendingConnectionIDs.insert(connection.id).inserted else { return }
        defer { pendingConnectionIDs.remove(connection.id) }
        if isUITestSeedData {
            replaceConnection(connection, status: "accepted", direction: "incoming")
            return
        }
        do {
            _ = try await api.acceptSocialConnection(id: connection.id)
            replaceConnection(connection, status: "accepted", direction: "incoming")
            notifications.removeAll { $0.type == "connectionRequest" && $0.objectId == connection.id }
            errorMessage = nil
            await refreshConnections()
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeConnection(_ connection: SocialConnectionDTO) async {
        guard pendingConnectionIDs.insert(connection.id).inserted else { return }
        defer { pendingConnectionIDs.remove(connection.id) }
        if isUITestSeedData {
            connections.removeAll { $0.id == connection.id }
            return
        }
        do {
            _ = try await api.removeSocialConnection(id: connection.id)
            connections.removeAll { $0.id == connection.id }
            notifications.removeAll { $0.type == "connectionRequest" && $0.objectId == connection.id }
            errorMessage = nil
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
                ActivityEventDTO(
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
                    activity: TogetherActivityDTO(id: "ui-test-social-activity", title: "Presidio Morning Run", durationSecs: 2_040, distanceM: 5_800, avgPace: 352, route: nil),
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
    var pendingInvitationCount: Int {
        connections.filter { $0.status == "pending" && $0.direction == "incoming" }.count
            + notifications.filter { $0.type == "runInvitation" }.count
    }
    var showsNotificationBadge: Bool {
        unreadNotificationCount > 0 || pendingInvitationCount > 0
    }

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
            state = TogetherResponseDTO(upcomingRuns: state.upcomingRuns, pastEvents: state.pastEvents, clubs: state.clubs, posts: state.posts.filter { $0.id != post.id }, nextFeedCursor: state.nextFeedCursor)
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

    @discardableResult
    func toggleMembership(in group: SocialGroupDTO) async -> Bool {
        if isUITestSeedData {
            discoverableGroups = discoverableGroups.map {
                guard $0.id == group.id else { return $0 }
                return SocialGroupDTO(id: $0.id, name: $0.name, description: $0.description, city: $0.city, memberCount: max(0, $0.memberCount + ($0.membershipRole == nil ? 1 : -1)), membershipRole: $0.membershipRole == nil ? "member" : nil)
            }
            return true
        }
        do {
            if group.membershipRole == nil {
                _ = try await api.joinSocialGroup(id: group.id)
            } else {
                _ = try await api.leaveSocialGroup(id: group.id)
            }
            await refreshGroups()
            await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func activityEventDetail(id: String) async -> ActivityEventDetailDTO? {
        if isUITestSeedData {
            guard let run = state.upcomingRuns.first(where: { $0.id == id }) else { return nil }
            return Self.uiTestRunDetail(run: run, isGoing: false)
        }
        do {
            let detail = try await api.fetchActivityEvent(id: id)
            errorMessage = nil
            return detail
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func toggleRSVP(for run: ActivityEventDetailDTO, attendanceMode: String? = nil) async -> ActivityEventDetailDTO? {
        if isUITestSeedData {
            guard let fixture = state.upcomingRuns.first(where: { $0.id == run.id }) else { return nil }
            return Self.uiTestRunDetail(run: fixture, isGoing: !run.currentUserGoing)
        }
        do {
            if run.currentUserGoing {
                _ = try await api.leaveActivityEvent(id: run.id)
            } else {
                guard let attendanceMode else { return nil }
                _ = try await api.joinActivityEvent(id: run.id, attendanceMode: attendanceMode)
            }
            return await activityEventDetail(id: run.id)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func deleteActivityEventInvitation(id invitationID: String, activityEventID: String) async -> ActivityEventDetailDTO? {
        if isUITestSeedData {
            guard var detail = await activityEventDetail(id: activityEventID) else { return nil }
            detail.pendingInvitations?.removeAll { $0.id == invitationID }
            return detail
        }
        do {
            _ = try await api.deleteActivityEventInvitation(id: invitationID, activityEventID: activityEventID)
            errorMessage = nil
            return await activityEventDetail(id: activityEventID)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func acceptRunInvitation(_ notification: SocialNotificationDTO, attendanceMode: String) async {
        guard let invitationID = notification.objectId else { return }
        if isUITestSeedData {
            notifications.removeAll { $0.id == notification.id }
            return
        }
        do {
            _ = try await api.acceptSocialRunInvitation(id: invitationID, attendanceMode: attendanceMode)
            notifications.removeAll { $0.id == notification.id }
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
        return TogetherResponseDTO(upcomingRuns: state.upcomingRuns, pastEvents: state.pastEvents, clubs: state.clubs, posts: posts, nextFeedCursor: state.nextFeedCursor)
    }

    private func replacing(post: TogetherPostDTO, commentCountDelta: Int) -> TogetherResponseDTO {
        let posts = state.posts.map { current in
            guard current.id == post.id else { return current }
            return TogetherPostDTO(
                id: current.id,
                caption: current.caption,
                createdAt: current.createdAt,
                isCurrentUser: current.isCurrentUser,
                user: current.user,
                activity: current.activity,
                reactionCount: current.reactionCount,
                currentUserCheered: current.currentUserCheered,
                commentCount: max(0, current.commentCount + commentCountDelta),
                comments: current.comments
            )
        }
        return TogetherResponseDTO(upcomingRuns: state.upcomingRuns, pastEvents: state.pastEvents, clubs: state.clubs, posts: posts, nextFeedCursor: state.nextFeedCursor)
    }

    private func replaceConnection(_ connection: SocialConnectionDTO, status: String, direction: String) {
        connections = connections.map {
            $0.id == connection.id
                ? SocialConnectionDTO(
                    id: $0.id,
                    status: status,
                    direction: direction,
                    person: $0.person,
                    isInActiveWorkout: status == "accepted" ? $0.isInActiveWorkout : false
                )
                : $0
        }
    }

    private static let uiTestConnections = [
        SocialConnectionDTO(id: "ui-connection-maya", status: "accepted", direction: "incoming", person: SocialPersonDTO(id: "ui-maya", username: "maya", displayName: "Maya Chen", avatarUrl: nil), isInActiveWorkout: true),
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

    private static func uiTestRunDetail(run: ActivityEventDTO, isGoing: Bool) -> ActivityEventDetailDTO {
        ActivityEventDetailDTO(id: run.id, title: run.title, startsAt: run.startsAt, locationName: run.locationName, paceNote: run.paceNote, club: run.club, creator: run.creator, groups: run.groups, attendeeCount: isGoing ? 19 : 18, currentUserGoing: isGoing, compatibility: run.compatibility)
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
