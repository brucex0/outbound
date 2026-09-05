import Foundation

struct CircleListResponseDTO: Codable, Sendable {
    let circles: [CircleDTO]
    let primaryCircleId: String?
    let policy: CirclePolicyDTO
}

struct CirclePolicyDTO: Codable, Sendable {
    let memberLimit: Int
}

struct CircleDTO: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let lifecycle: String
    let role: String?
    let owner: CirclePersonDTO
    let resetWeekday: Int
    let timeZone: String
    let memberLimit: Int
    let memberCount: Int
    let eligibleForToday: Bool
    let members: [CircleMemberDTO]
    let upcomingFocus: CircleUpcomingFocusDTO
    let week: CircleWeekDTO
    let currentUserMuted: Bool
    let completionPresentationPending: Bool
    let cheers: [CircleCheerDTO]
    let invitations: [CircleInvitationDTO]
    let recentMoments: [CircleMomentDTO]
    let history: [CircleWeekHistoryDTO]?
}

struct CircleUpcomingFocusDTO: Codable, Sendable {
    let mode: String
    let focusConfigured: Bool
    let sharedTarget: Int?
}

struct CirclePersonDTO: Codable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let avatarUrl: String?
}

struct CircleMemberDTO: Codable, Identifiable, Sendable {
    let id: String
    let user: CirclePersonDTO
    let role: String
    let isCurrentUser: Bool
    let commitment: CircleCommitmentDTO?
    let contributedCount: Int
    let recentActivity: CircleActivitySummaryDTO?
}

struct CircleActivitySummaryDTO: Codable, Sendable {
    let type: String
    let title: String?
    let startedAt: Date
    let durationSecs: Int?
    let distanceM: Double?
    let elevationM: Double?
    let avgPace: Double?
    let avgHeartRate: Int?
    let energyKilocalories: Int?
}

struct CircleCommitmentDTO: Codable, Sendable {
    let targetCount: Int?
    let skipped: Bool
}

struct CircleWeekDTO: Codable, Identifiable, Sendable {
    let id: String
    let startsAt: Date
    let endsAt: Date
    let focusMode: String
    let focusConfigured: Bool
    let sharedTarget: Int?
    let state: String
    let contributedCount: Int
    let targetCount: Int?
}

struct CircleWeekHistoryDTO: Codable, Identifiable, Sendable {
    let id: String
    let startsAt: Date
    let endsAt: Date
    let focusMode: String
    let state: String
}

struct CircleInvitationDTO: Codable, Identifiable, Sendable {
    let id: String
    let circleId: String
    let circle: CircleInvitationCircleDTO
    let sender: CirclePersonDTO
    let recipient: CirclePersonDTO?
    let status: String
    let createdAt: Date
    let expiresAt: Date?
}

struct CircleCheerDTO: Codable, Identifiable, Sendable {
    let id: String
    let senderUserId: String
    let recipientUserId: String
    let presetType: String
    let createdAt: Date
}

struct CircleMomentDTO: Codable, Identifiable, Sendable {
    let id: String
    let type: String
    let createdAt: Date
    let title: String?
}

struct CircleInvitationCircleDTO: Codable, Identifiable, Sendable {
    let id: String
    let name: String
}

struct CircleInvitationListResponseDTO: Codable, Sendable {
    let invitations: [CircleInvitationDTO]
}

struct CircleInvitationMutationResponseDTO: Codable, Sendable {
    let circle: CircleDTO
}

struct CircleCreateRequestDTO: Encodable, Sendable {
    let name: String?
    let memberUserIds: [String]
    let timeZone: String?
    let resetWeekday: Int?
}

struct CircleInviteRequestDTO: Encodable, Sendable {
    let recipientUserIds: [String]
    let idempotencyKey: String
}

struct CircleFocusRequestDTO: Encodable, Sendable {
    let mode: String
    let sharedTarget: Int?
    let apply: String
}

struct CircleCommitmentRequestDTO: Encodable, Sendable {
    let targetCount: Int?
    let skipped: Bool
}

struct CircleCheerRequestDTO: Encodable, Sendable {
    let recipientUserId: String
    let presetType: String
}

struct CirclePrimaryResponseDTO: Codable, Sendable {
    let primaryCircleId: String
    let circle: CircleDTO?
}

struct CircleInvitationCancellationResponseDTO: Codable, Sendable {
    let status: String
    let circle: CircleDTO
}

struct CircleMuteRequestDTO: Encodable, Sendable {
    let muted: Bool
}

struct CircleTransferRequestDTO: Encodable, Sendable {
    let recipientUserId: String
}

struct CirclePresentationResponseDTO: Codable, Sendable {
    let presented: Bool
}

struct CircleConnectionMutationDTO: Codable, Sendable {
    let status: String?
    let ok: Bool?
}

struct CircleCheerResponseDTO: Codable, Sendable {
    let id: String
    let status: String
    let circle: CircleDTO
}

struct CircleMutationResponseDTO: Codable, Sendable {
    let status: String?
    let ok: Bool?
    let lifecycle: String?
}

struct CircleMuteResponseDTO: Codable, Sendable {
    let muted: Bool
}

struct CircleCalendarRequestDTO: Encodable, Sendable {
    let resetWeekday: Int
    let timeZone: String
    let apply: String
}

struct CircleContributionDTO: Codable, Sendable {
    let circleId: String
    let circleName: String
    let weekId: String
    let contributedCount: Int
    let targetCount: Int?
    let focusMode: String
    let memberCount: Int
    let completed: Bool
    let primary: Bool
}

struct CircleContributionReceipt: Sendable {
    let primary: CircleContributionDTO
    let additionalCircleCount: Int
}
