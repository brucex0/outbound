import Foundation

struct TogetherResponseDTO: Codable, Sendable {
    let upcomingRuns: [TogetherGroupRunDTO]
    let clubs: [TogetherClubDTO]
    let posts: [TogetherPostDTO]
}

struct TogetherPersonDTO: Codable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let avatarUrl: String?
}

struct TogetherClubDTO: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let description: String?
    let city: String?
    let role: String?
}

struct TogetherRunGroupDTO: Codable, Identifiable, Sendable {
    let id: String
    let label: String
    let distanceMeters: Double?
    let paceMinSeconds: Int?
    let paceMaxSeconds: Int?
}

struct TogetherCompatibilityDTO: Codable, Sendable {
    let groupId: String
    let explanation: String
}

struct TogetherGroupRunDTO: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let startsAt: Date
    let locationName: String?
    let paceNote: String?
    let club: TogetherClubDTO?
    let creator: TogetherPersonDTO
    let groups: [TogetherRunGroupDTO]
    let compatibility: TogetherCompatibilityDTO?
}

struct TogetherActivityDTO: Codable, Sendable {
    let id: String
    let title: String?
    let durationSecs: Int?
    let distanceM: Double?
    let avgPace: Double?
}

struct TogetherPostDTO: Codable, Identifiable, Sendable {
    let id: String
    let caption: String?
    let createdAt: Date
    let user: TogetherPersonDTO
    let activity: TogetherActivityDTO?
    let reactions: [TogetherReactionDTO]
    let comments: [TogetherCommentDTO]
}

struct TogetherReactionDTO: Codable, Identifiable, Sendable {
    let id: String
    let type: String
}

struct TogetherCommentDTO: Codable, Identifiable, Sendable {
    let id: String
    let body: String
}

struct TogetherReactionRequestDTO: Codable, Sendable { let type: String }
struct TogetherCommentRequestDTO: Codable, Sendable { let body: String }
struct TogetherInvitationRequestDTO: Codable, Sendable { let recipientUserId: String? }

struct TogetherInvitationResponseDTO: Codable, Sendable {
    let id: String
    let token: String
    let status: String
}
