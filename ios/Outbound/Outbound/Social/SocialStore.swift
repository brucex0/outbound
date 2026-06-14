#if OUTBOUND_ENABLE_SOCIAL
import Combine
import Foundation

enum SocialVisibility: String, CaseIterable, Identifiable {
    case squad = "Squad"
    case clubs = "Clubs"
    case privatePreview = "Private"

    var id: String { rawValue }
}

struct SocialComment: Identifiable, Equatable {
    let id: UUID
    let postID: String
    let authorName: String
    let text: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        postID: String,
        authorName: String,
        text: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.postID = postID
        self.authorName = authorName
        self.text = text
        self.createdAt = createdAt
    }
}

struct SocialRelayInvite: Identifiable, Equatable {
    let id: UUID
    let routeLabel: String
    let windowLabel: String
    let audienceLabel: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        routeLabel: String,
        windowLabel: String,
        audienceLabel: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.routeLabel = routeLabel
        self.windowLabel = windowLabel
        self.audienceLabel = audienceLabel
        self.createdAt = createdAt
    }
}

@MainActor
final class SocialStore: ObservableObject {
    @Published private(set) var cheeredPostIDs: Set<String> = ["maya-waterfront"]
    @Published private(set) var commentsByPostID: [String: [SocialComment]] = [
        "maya-waterfront": [
            SocialComment(postID: "maya-waterfront", authorName: "Chen", text: "I am taking a shot at this tonight."),
            SocialComment(postID: "maya-waterfront", authorName: "You", text: "That last kilometer is spicy.")
        ],
        "leo-relay": [
            SocialComment(postID: "leo-relay", authorName: "Maya", text: "Joining for the next ten.")
        ]
    ]
    @Published var defaultVisibility: SocialVisibility = .squad
    @Published private(set) var relayInvites: [SocialRelayInvite] = []
    @Published private(set) var joinedChallengeIDs: Set<String> = ["seven-day-chain"]
    @Published private(set) var reportedContentIDs: Set<String> = []
    @Published private(set) var blockedPersonIDs: Set<String> = []

    func toggleCheer(for postID: String) -> Bool {
        if cheeredPostIDs.contains(postID) {
            cheeredPostIDs.remove(postID)
            return false
        }

        cheeredPostIDs.insert(postID)
        return true
    }

    func comments(for postID: String) -> [SocialComment] {
        commentsByPostID[postID, default: []]
    }

    func commentCount(for post: SocialFeedPost) -> Int {
        post.comments + comments(for: post.id).count
    }

    func addComment(_ text: String, to postID: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        commentsByPostID[postID, default: []].append(
            SocialComment(postID: postID, authorName: "You", text: trimmed)
        )
    }

    func createRelay(routeLabel: String, windowLabel: String, audienceLabel: String) {
        relayInvites.insert(
            SocialRelayInvite(routeLabel: routeLabel, windowLabel: windowLabel, audienceLabel: audienceLabel),
            at: 0
        )
    }

    func toggleChallenge(_ challengeID: String) {
        if joinedChallengeIDs.contains(challengeID) {
            joinedChallengeIDs.remove(challengeID)
        } else {
            joinedChallengeIDs.insert(challengeID)
        }
    }

    func reportContent(_ contentID: String) {
        reportedContentIDs.insert(contentID)
    }

    func blockPerson(_ personID: String) {
        blockedPersonIDs.insert(personID)
    }
}
#endif
