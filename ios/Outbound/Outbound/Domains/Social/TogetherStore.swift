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
        do {
            let invitation = try await api.createTogetherInvitation(runID: run.id)
            latestInvitationURL = PlainstrideLinks.scheduledRunInvitation(token: invitation.token)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func invite(_ connection: SocialConnectionDTO, to run: TogetherGroupRunDTO) async -> Bool {
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
        do {
            _ = try await api.acceptSocialConnection(id: connection.id)
            await refreshConnections()
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeConnection(_ connection: SocialConnectionDTO) async {
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
        do {
            notifications = try await api.fetchSocialNotifications().notifications
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func markNotificationsRead() async {
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
        do {
            discoverableGroups = try await api.fetchSocialGroups().groups
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleMembership(in group: SocialGroupDTO) async {
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
        do {
            blocks = try await api.fetchSocialBlocks().blocks
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func unblock(_ block: SocialBlockDTO) async {
        do {
            _ = try await api.unblockSocialUser(id: block.person.id)
            await refreshBlocks()
        } catch {
            errorMessage = error.localizedDescription
        }
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
