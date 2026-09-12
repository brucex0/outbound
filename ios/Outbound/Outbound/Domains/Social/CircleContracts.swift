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
    let upcomingActivities: [CircleActivityEventDTO]
    let recentMoments: [CircleMomentDTO]
    let history: [CircleWeekHistoryDTO]?
}

extension CircleDTO {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case lifecycle
        case role
        case owner
        case resetWeekday
        case timeZone
        case memberLimit
        case memberCount
        case eligibleForToday
        case members
        case upcomingFocus
        case week
        case currentUserMuted
        case completionPresentationPending
        case cheers
        case invitations
        case upcomingActivities
        case recentMoments
        case history
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        lifecycle = try container.decode(String.self, forKey: .lifecycle)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        owner = try container.decode(CirclePersonDTO.self, forKey: .owner)
        resetWeekday = try container.decode(Int.self, forKey: .resetWeekday)
        timeZone = try container.decode(String.self, forKey: .timeZone)
        memberLimit = try container.decode(Int.self, forKey: .memberLimit)
        memberCount = try container.decode(Int.self, forKey: .memberCount)
        eligibleForToday = try container.decode(Bool.self, forKey: .eligibleForToday)
        members = try container.decode([CircleMemberDTO].self, forKey: .members)
        upcomingFocus = try container.decode(CircleUpcomingFocusDTO.self, forKey: .upcomingFocus)
        week = try container.decode(CircleWeekDTO.self, forKey: .week)
        currentUserMuted = try container.decode(Bool.self, forKey: .currentUserMuted)
        completionPresentationPending = try container.decode(Bool.self, forKey: .completionPresentationPending)
        cheers = try container.decode([CircleCheerDTO].self, forKey: .cheers)
        invitations = try container.decode([CircleInvitationDTO].self, forKey: .invitations)
        upcomingActivities = try container.decodeIfPresent(
            [CircleActivityEventDTO].self,
            forKey: .upcomingActivities
        ) ?? []
        recentMoments = try container.decode([CircleMomentDTO].self, forKey: .recentMoments)
        history = try container.decodeIfPresent([CircleWeekHistoryDTO].self, forKey: .history)
    }
}

struct CircleUpcomingFocusDTO: Codable, Sendable {
    let mode: String
    let focusConfigured: Bool
    let sharedTarget: Int?
    let themeKey: String?
    let themeTitle: String?
    let themeNote: String?
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
    let themeKey: String?
    let themeTitle: String?
    let themeNote: String?
    let state: String
    let contributedCount: Int
    let targetCount: Int?
}

struct CircleWeekHistoryDTO: Codable, Identifiable, Sendable {
    let id: String
    let startsAt: Date
    let endsAt: Date
    let focusMode: String
    let themeKey: String?
    let themeTitle: String?
    let themeNote: String?
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

struct CircleActivityEventDTO: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let startsAt: Date
    let endsAt: Date?
    let locationName: String?
    let paceNote: String?
    let status: String
    let creator: CirclePersonDTO
    let attendeeCount: Int
    let currentUserGoing: Bool
    let currentUserRole: String

    var activityEvent: ActivityEventDTO {
        ActivityEventDTO(
            id: id,
            title: title,
            startsAt: startsAt,
            endsAt: endsAt,
            locationName: locationName,
            paceNote: paceNote,
            club: nil,
            creator: TogetherPersonDTO(
                id: creator.id,
                displayName: creator.displayName,
                avatarUrl: creator.avatarUrl
            ),
            groups: [],
            compatibility: nil,
            source: ActivityEventSourceDTO(kind: "circle", label: "Circle"),
            attendeeCount: attendeeCount,
            attendeePreview: nil,
            currentUserGoing: currentUserGoing,
            status: status,
            participationMode: "hybrid",
            currentUserRole: currentUserRole
        )
    }
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
    let themeKey: String?
    let customThemeTitle: String?
    let customThemeNote: String?
    let apply: String
}

struct CircleCommitmentRequestDTO: Encodable, Sendable {
    let targetCount: Int?
    let skipped: Bool
    let clear: Bool
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
