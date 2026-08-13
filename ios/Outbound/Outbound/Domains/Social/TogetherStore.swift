import Combine
import Foundation

@MainActor
final class TogetherStore: ObservableObject {
    @Published private(set) var state: TogetherResponseDTO
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var latestInvitationURL: URL?

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
        do {
            _ = try await api.reactToTogetherPost(postID: post.id, type: "heart")
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
                    user: maya,
                    activity: TogetherActivityDTO(id: "ui-test-social-activity", title: "Presidio Morning Run", durationSecs: 2_040, distanceM: 5_800, avgPace: 352),
                    reactions: [TogetherReactionDTO(id: "ui-test-heart-1", type: "heart"), TogetherReactionDTO(id: "ui-test-heart-2", type: "heart")],
                    comments: [TogetherCommentDTO(id: "ui-test-comment", body: "See you next time!")]
                ),
            ]
        )
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
