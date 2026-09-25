import Foundation

struct GroupListResponseDTO: Codable, Sendable {
    let groups: [GroupDTO]
    let nextCursor: String?
    let policy: GroupPolicyDTO
}

struct GroupPolicyDTO: Codable, Sendable {
    let memberLimit: Int
}

struct GroupDTO: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let lifecycle: String
    let role: String?
    let owner: GroupPersonDTO
    let resetWeekday: Int
    let timeZone: String
    let memberLimit: Int
    let memberCount: Int
    let eligibleForToday: Bool
    let members: [GroupMemberDTO]
    let upcomingFocus: GroupUpcomingFocusDTO
    let week: GroupWeekDTO
    let currentUserMuted: Bool
    let completionPresentationPending: Bool
    let cheers: [GroupCheerDTO]
    let invitations: [GroupInvitationDTO]
    let upcomingActivities: [GroupActivityEventDTO]
    let recentMoments: [GroupMomentDTO]
    let history: [GroupWeekHistoryDTO]?
    var normalizedName: String? = nil
    var description: String? = nil
    var city: String? = nil
    var activityInterests: [String] = []
    var trustPolicy: String = "trusted_private"
    var visibility: String = "private"
    var joinPolicy: String = "invite_only"
    var featured: Bool = false
    var organizationVerificationState: String = "unverified"
    var capabilities: GroupCapabilitiesDTO = .privateDefaults
    var notices: [GroupNoticeDTO] = []
    var unreadNoticeCount: Int = 0
    var pendingRequest: GroupPendingRequestDTO? = nil
}

extension GroupDTO {
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
        case normalizedName, description, city, activityInterests, trustPolicy, visibility, joinPolicy, featured, organizationVerificationState, capabilities, notices, unreadNoticeCount, pendingRequest
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        lifecycle = try container.decode(String.self, forKey: .lifecycle)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        owner = try container.decodeIfPresent(GroupPersonDTO.self, forKey: .owner) ?? GroupPersonDTO(id: "system", displayName: "Plainstride", avatarUrl: nil)
        resetWeekday = try container.decodeIfPresent(Int.self, forKey: .resetWeekday) ?? 1
        timeZone = try container.decodeIfPresent(String.self, forKey: .timeZone) ?? TimeZone.current.identifier
        memberLimit = try container.decodeIfPresent(Int.self, forKey: .memberLimit) ?? 100
        memberCount = try container.decodeIfPresent(Int.self, forKey: .memberCount) ?? 0
        eligibleForToday = try container.decodeIfPresent(Bool.self, forKey: .eligibleForToday) ?? false
        members = try container.decodeIfPresent([GroupMemberDTO].self, forKey: .members) ?? []
        upcomingFocus = try container.decodeIfPresent(GroupUpcomingFocusDTO.self, forKey: .upcomingFocus) ?? .empty
        week = try container.decodeIfPresent(GroupWeekDTO.self, forKey: .week) ?? .empty
        currentUserMuted = try container.decodeIfPresent(Bool.self, forKey: .currentUserMuted) ?? false
        completionPresentationPending = try container.decodeIfPresent(Bool.self, forKey: .completionPresentationPending) ?? false
        cheers = try container.decodeIfPresent([GroupCheerDTO].self, forKey: .cheers) ?? []
        invitations = try container.decodeIfPresent([GroupInvitationDTO].self, forKey: .invitations) ?? []
        upcomingActivities = try container.decodeIfPresent(
            [GroupActivityEventDTO].self,
            forKey: .upcomingActivities
        ) ?? []
        recentMoments = try container.decodeIfPresent([GroupMomentDTO].self, forKey: .recentMoments) ?? []
        history = try container.decodeIfPresent([GroupWeekHistoryDTO].self, forKey: .history)
        normalizedName = try container.decodeIfPresent(String.self, forKey: .normalizedName)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        city = try container.decodeIfPresent(String.self, forKey: .city)
        activityInterests = try container.decodeIfPresent([String].self, forKey: .activityInterests) ?? []
        trustPolicy = try container.decodeIfPresent(String.self, forKey: .trustPolicy) ?? "trusted_private"
        visibility = try container.decodeIfPresent(String.self, forKey: .visibility) ?? "private"
        joinPolicy = try container.decodeIfPresent(String.self, forKey: .joinPolicy) ?? "invite_only"
        featured = try container.decodeIfPresent(Bool.self, forKey: .featured) ?? false
        organizationVerificationState = try container.decodeIfPresent(String.self, forKey: .organizationVerificationState) ?? "unverified"
        capabilities = try container.decodeIfPresent(GroupCapabilitiesDTO.self, forKey: .capabilities) ?? .privateDefaults
        notices = try container.decodeIfPresent([GroupNoticeDTO].self, forKey: .notices) ?? []
        unreadNoticeCount = try container.decodeIfPresent(Int.self, forKey: .unreadNoticeCount) ?? 0
        pendingRequest = try container.decodeIfPresent(GroupPendingRequestDTO.self, forKey: .pendingRequest)
    }
}

struct GroupCapabilitiesDTO: Codable, Sendable {
    let weeklyTheme: Bool
    let workoutContributions: Bool
    let presetCheers: Bool
    let notices: Bool
    let scheduledActivities: Bool

    static let privateDefaults = GroupCapabilitiesDTO(weeklyTheme: true, workoutContributions: true, presetCheers: true, notices: false, scheduledActivities: true)
}

struct GroupNoticeDTO: Codable, Identifiable, Sendable {
    let id: String
    let title: String?
    let body: String
    let activityEventId: String?
    let pinned: Bool
    let publishedAt: Date
    let editedAt: Date?
}

struct GroupNoticeRequestDTO: Encodable, Sendable {
    let title: String?
    let body: String
    let activityEventId: String?
    let pinned: Bool
}

struct GroupNoticeMutationResponseDTO: Codable, Sendable {
    let group: GroupDTO
}

typealias GroupNoticeReadResponseDTO = GroupNoticeMutationResponseDTO

struct GroupInviteLinkDTO: Codable, Sendable {
    let id: String
    let token: String?
    let url: String?
    let expiresAt: Date?
}

struct GroupInviteConsumeResponseDTO: Codable, Sendable {
    let status: String
    let group: GroupDTO
}

struct GroupPendingRequestDTO: Codable, Sendable {
    let id: String
    let status: String
}

struct GroupUpcomingFocusDTO: Codable, Sendable {
    let mode: String
    let focusConfigured: Bool
    let sharedTarget: Int?
    let themeKey: String?
    let themeTitle: String?
    let themeNote: String?
}

extension GroupUpcomingFocusDTO {
    static let empty = GroupUpcomingFocusDTO(mode: "none", focusConfigured: false, sharedTarget: nil, themeKey: nil, themeTitle: nil, themeNote: nil)
}

struct GroupPersonDTO: Codable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let avatarUrl: String?
}

struct GroupMemberDTO: Codable, Identifiable, Sendable {
    let id: String
    let user: GroupPersonDTO
    let role: String
    let isCurrentUser: Bool
    let commitment: GroupCommitmentDTO?
    let contributedCount: Int
    let recentActivity: GroupActivitySummaryDTO?

    init(id: String, user: GroupPersonDTO, role: String, isCurrentUser: Bool, commitment: GroupCommitmentDTO?, contributedCount: Int, recentActivity: GroupActivitySummaryDTO?) {
        self.id = id; self.user = user; self.role = role; self.isCurrentUser = isCurrentUser; self.commitment = commitment; self.contributedCount = contributedCount; self.recentActivity = recentActivity
    }

    private enum CodingKeys: String, CodingKey { case id, user, role, isCurrentUser, commitment, contributedCount, recentActivity }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        user = try container.decode(GroupPersonDTO.self, forKey: .user)
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? "member"
        isCurrentUser = try container.decodeIfPresent(Bool.self, forKey: .isCurrentUser) ?? false
        commitment = try container.decodeIfPresent(GroupCommitmentDTO.self, forKey: .commitment)
        contributedCount = try container.decodeIfPresent(Int.self, forKey: .contributedCount) ?? 0
        recentActivity = try container.decodeIfPresent(GroupActivitySummaryDTO.self, forKey: .recentActivity)
    }
}

struct GroupActivitySummaryDTO: Codable, Sendable {
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

struct GroupCommitmentDTO: Codable, Sendable {
    let targetCount: Int?
    let skipped: Bool
}

struct GroupWeekDTO: Codable, Identifiable, Sendable {
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

extension GroupWeekDTO {
    static let empty = GroupWeekDTO(id: "none", startsAt: .distantPast, endsAt: .distantPast, focusMode: "none", focusConfigured: false, sharedTarget: nil, themeKey: nil, themeTitle: nil, themeNote: nil, state: "open", contributedCount: 0, targetCount: nil)
}

struct GroupWeekHistoryDTO: Codable, Identifiable, Sendable {
    let id: String
    let startsAt: Date
    let endsAt: Date
    let focusMode: String
    let themeKey: String?
    let themeTitle: String?
    let themeNote: String?
    let state: String
}

struct GroupInvitationDTO: Codable, Identifiable, Sendable {
    let id: String
    let groupId: String
    let group: GroupInvitationGroupDTO
    let sender: GroupPersonDTO
    let recipient: GroupPersonDTO?
    let status: String
    let createdAt: Date
    let expiresAt: Date?
}

struct GroupCheerDTO: Codable, Identifiable, Sendable {
    let id: String
    let senderUserId: String
    let recipientUserId: String
    let presetType: String
    let createdAt: Date
}

struct GroupMomentDTO: Codable, Identifiable, Sendable {
    let id: String
    let type: String
    let createdAt: Date
    let title: String?
}

struct GroupActivityEventDTO: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let startsAt: Date
    let endsAt: Date?
    let locationName: String?
    let paceNote: String?
    let status: String
    let creator: GroupPersonDTO
    let attendeeCount: Int
    let currentUserGoing: Bool
    let currentUserRole: String

    init(id: String, title: String, startsAt: Date, endsAt: Date?, locationName: String?, paceNote: String?, status: String, creator: GroupPersonDTO, attendeeCount: Int, currentUserGoing: Bool, currentUserRole: String) {
        self.id = id; self.title = title; self.startsAt = startsAt; self.endsAt = endsAt; self.locationName = locationName; self.paceNote = paceNote; self.status = status; self.creator = creator; self.attendeeCount = attendeeCount; self.currentUserGoing = currentUserGoing; self.currentUserRole = currentUserRole
    }

    private enum CodingKeys: String, CodingKey { case id, title, startsAt, endsAt, locationName, paceNote, status, creator, attendeeCount, currentUserGoing, currentUserRole }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        startsAt = try container.decode(Date.self, forKey: .startsAt)
        endsAt = try container.decodeIfPresent(Date.self, forKey: .endsAt)
        locationName = try container.decodeIfPresent(String.self, forKey: .locationName)
        paceNote = try container.decodeIfPresent(String.self, forKey: .paceNote)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "scheduled"
        creator = try container.decodeIfPresent(GroupPersonDTO.self, forKey: .creator) ?? GroupPersonDTO(id: "system", displayName: "Organizer", avatarUrl: nil)
        attendeeCount = try container.decodeIfPresent(Int.self, forKey: .attendeeCount) ?? 0
        currentUserGoing = try container.decodeIfPresent(Bool.self, forKey: .currentUserGoing) ?? false
        currentUserRole = try container.decodeIfPresent(String.self, forKey: .currentUserRole) ?? "viewer"
    }

    var activityEvent: ActivityEventDTO {
        ActivityEventDTO(
            id: id,
            title: title,
            startsAt: startsAt,
            endsAt: endsAt,
            locationName: locationName,
            paceNote: paceNote,
            group: nil,
            creator: TogetherPersonDTO(
                id: creator.id,
                displayName: creator.displayName,
                avatarUrl: creator.avatarUrl
            ),
            groups: [],
            compatibility: nil,
            source: ActivityEventSourceDTO(kind: "group", label: "Group"),
            attendeeCount: attendeeCount,
            attendeePreview: nil,
            currentUserGoing: currentUserGoing,
            status: status,
            participationMode: "hybrid",
            currentUserRole: currentUserRole
        )
    }
}

struct GroupInvitationGroupDTO: Codable, Identifiable, Sendable {
    let id: String
    let name: String
}

struct GroupInvitationListResponseDTO: Codable, Sendable {
    let invitations: [GroupInvitationDTO]
}

struct GroupInvitationMutationResponseDTO: Codable, Sendable {
    let group: GroupDTO
}

struct GroupCreateRequestDTO: Encodable, Sendable {
    let template: String
    let name: String?
    let description: String?
    let city: String?
    let activityInterests: [String]
    let memberUserIds: [String]
    let timeZone: String?
    let resetWeekday: Int?
}

struct GroupInviteRequestDTO: Encodable, Sendable {
    let recipientUserIds: [String]
    let idempotencyKey: String
}

struct GroupFocusRequestDTO: Encodable, Sendable {
    let mode: String
    let sharedTarget: Int?
    let themeKey: String?
    let customThemeTitle: String?
    let customThemeNote: String?
    let apply: String
}

struct GroupCommitmentRequestDTO: Encodable, Sendable {
    let targetCount: Int?
    let skipped: Bool
    let clear: Bool
}

struct GroupCheerRequestDTO: Encodable, Sendable {
    let recipientUserId: String
    let presetType: String
}

struct GroupInvitationCancellationResponseDTO: Codable, Sendable {
    let status: String
    let group: GroupDTO
}

struct GroupMuteRequestDTO: Encodable, Sendable {
    let muted: Bool
}

struct GroupTransferRequestDTO: Encodable, Sendable {
    let recipientUserId: String
}

struct GroupPresentationResponseDTO: Codable, Sendable {
    let presented: Bool
}

struct GroupConnectionMutationDTO: Codable, Sendable {
    let status: String?
    let ok: Bool?
}

struct GroupCheerResponseDTO: Codable, Sendable {
    let id: String
    let status: String
    let group: GroupDTO
}

struct GroupMutationResponseDTO: Codable, Sendable {
    let status: String?
    let ok: Bool?
    let lifecycle: String?
}

struct GroupMuteResponseDTO: Codable, Sendable {
    let muted: Bool
}

struct GroupCalendarRequestDTO: Encodable, Sendable {
    let resetWeekday: Int
    let timeZone: String
    let apply: String
}

struct GroupContributionDTO: Codable, Sendable {
    let groupId: String
    let groupName: String
    let weekId: String
    let contributedCount: Int
    let targetCount: Int?
    let focusMode: String
    let memberCount: Int
    let completed: Bool
}

struct GroupContributionReceipt: Sendable {
    let primary: GroupContributionDTO
    let additionalGroupCount: Int
}
