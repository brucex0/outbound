import Foundation

enum ActivityEventTiming {
    static let defaultDurationMinutes = 60
    static let reconciliationWindow: TimeInterval = 4 * 60 * 60
}

struct TogetherResponseDTO: Codable, Sendable {
    let upcomingRuns: [ActivityEventDTO]
    var pastEvents: [ActivityEventDTO] = []
    let clubs: [TogetherClubDTO]
    let posts: [TogetherPostDTO]
}

struct TogetherPersonDTO: Codable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let avatarUrl: String?
}

struct SocialPersonDTO: Codable, Identifiable, Sendable {
    let id: String
    let username: String
    let displayName: String
    let avatarUrl: String?
}

struct SocialRelationshipDTO: Codable, Sendable {
    let id: String
    let status: String
    let direction: String
}

struct SocialConnectionDTO: Codable, Identifiable, Sendable {
    let id: String
    let status: String
    let direction: String
    let person: SocialPersonDTO
}

struct SocialConnectionsResponseDTO: Codable, Sendable {
    let connections: [SocialConnectionDTO]
}

struct SocialPersonSearchResultDTO: Codable, Identifiable, Sendable {
    let id: String
    let username: String
    let displayName: String
    let avatarUrl: String?
    let relationship: SocialRelationshipDTO?
}

struct SocialPeopleSearchResponseDTO: Codable, Sendable {
    let people: [SocialPersonSearchResultDTO]
}

struct SocialConnectionRequestDTO: Codable, Sendable {
    let userId: String
}

struct SocialConnectionMutationDTO: Codable, Sendable {
    let id: String?
    let status: String?
    let ok: Bool?
}

struct TogetherClubDTO: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let description: String?
    let city: String?
    let role: String?
}

struct SocialGroupDTO: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let description: String?
    let city: String?
    let memberCount: Int
    let membershipRole: String?
}

struct SocialGroupsResponseDTO: Codable, Sendable { let groups: [SocialGroupDTO] }

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

struct ActivityEventDTO: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let startsAt: Date
    var endsAt: Date? = nil
    let locationName: String?
    let paceNote: String?
    let club: TogetherClubDTO?
    let creator: TogetherPersonDTO
    let groups: [TogetherRunGroupDTO]
    let compatibility: TogetherCompatibilityDTO?
    var source: ActivityEventSourceDTO? = nil
    var attendeeCount: Int? = nil
    var attendeePreview: [TogetherPersonDTO]? = nil
    var currentUserGoing: Bool? = nil
    var status: String? = nil
    var participationMode: String? = nil
    var currentUserRole: String? = nil
}

struct ActivityEventDetailDTO: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let startsAt: Date
    var endsAt: Date? = nil
    let locationName: String?
    let paceNote: String?
    let club: TogetherClubDTO?
    let creator: TogetherPersonDTO
    let groups: [TogetherRunGroupDTO]
    let attendeeCount: Int
    let currentUserGoing: Bool
    let compatibility: TogetherCompatibilityDTO?
    var source: ActivityEventSourceDTO? = nil
    var attendeePreview: [TogetherPersonDTO]? = nil
    var participants: [ActivityEventParticipantDTO]? = nil
    var status: String? = nil
    var currentUserOutcome: String? = nil
    var currentUserAttendanceMode: String? = nil
    var participationMode: String? = nil
    var invitedUserIds: [String]? = nil
    var pendingInvitations: [ActivityEventPendingInvitationDTO]? = nil
    var currentUserRole: String? = nil
}

struct ActivityEventPendingInvitationDTO: Codable, Identifiable, Sendable {
    let id: String
    let recipient: TogetherPersonDTO
    let createdAt: Date
}

struct ActivityEventSourceDTO: Codable, Sendable {
    let kind: String
    let label: String
}

struct ActivityEventParticipantDTO: Codable, Identifiable, Sendable {
    var id: String { person.id }
    let person: TogetherPersonDTO
    let status: String
    let outcome: String?
    var attendanceMode: String? = nil
}

struct ActivityEventAttendanceRequestDTO: Codable, Sendable {
    let attendanceMode: String
}

struct CreateActivityEventRequestDTO: Codable, Sendable {
    let title: String
    let startsAt: Date
    let locationName: String?
    let note: String?
    var durationMinutes: Int = ActivityEventTiming.defaultDurationMinutes
}

struct ActivityEventInvitationBatchRequestDTO: Codable, Sendable {
    let recipientUserIds: [String]
}

struct ActivityEventInvitationBatchResponseDTO: Codable, Sendable {
    let invitations: [ActivityEventInvitationBatchItemDTO]
}

struct ActivityEventInvitationBatchItemDTO: Codable, Sendable {
    let id: String
    let recipientUserId: String
    let status: String
}

struct ActivityEventResultDTO: Codable, Sendable {
    let activityEventId: String
    let status: String
    let goingCount: Int
    let resolvedCount: Int
    let combinedDistanceMeters: Double
    let combinedDurationSeconds: Int
    let participants: [ActivityEventResultParticipantDTO]
}

struct ActivityEventResultParticipantDTO: Codable, Identifiable, Sendable {
    var id: String { person.id }
    let person: TogetherPersonDTO
    let outcome: String?
    let result: TogetherActivityDTO?
}

struct LinkActivityEventRequestDTO: Codable, Sendable { let activityId: String }

struct TogetherActivityDTO: Codable, Sendable {
    let id: String
    let title: String?
    let durationSecs: Int?
    let distanceM: Double?
    let avgPace: Double?
    let route: TogetherActivityRouteDTO?
}

struct TogetherActivityRouteDTO: Codable, Sendable {
    let geometry: TogetherActivityRouteGeometryDTO
}

struct TogetherActivityRouteGeometryDTO: Codable, Sendable {
    let coordinates: [[Double]]
}

struct TogetherPostDTO: Codable, Identifiable, Sendable {
    let id: String
    let caption: String?
    let createdAt: Date
    let isCurrentUser: Bool
    let user: TogetherPersonDTO
    let activity: TogetherActivityDTO?
    let reactionCount: Int
    let currentUserCheered: Bool
    let commentCount: Int
    let comments: [TogetherCommentDTO]
}

struct SocialReportRequestDTO: Codable, Sendable {
    let targetType: String
    let targetId: String
    let reason: String
    let details: String?
}

struct SocialReportResponseDTO: Codable, Sendable {
    let id: String
    let status: String
}

struct SocialNotificationDTO: Codable, Identifiable, Sendable {
    let id: String
    let type: String
    let objectId: String?
    let message: String
    let readAt: Date?
    let createdAt: Date
    let actor: SocialPersonDTO?
}

extension SocialNotificationDTO: Hashable {
    static func == (lhs: SocialNotificationDTO, rhs: SocialNotificationDTO) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct SocialNotificationsResponseDTO: Codable, Sendable {
    let notifications: [SocialNotificationDTO]
}

struct SocialBlockDTO: Codable, Identifiable, Sendable {
    let id: String
    let person: SocialPersonDTO
}

struct SocialBlocksResponseDTO: Codable, Sendable { let blocks: [SocialBlockDTO] }

struct TogetherReactionDTO: Codable, Identifiable, Sendable {
    let id: String
    let type: String
}

struct TogetherCommentDTO: Codable, Identifiable, Sendable {
    let id: String
    let body: String
    let createdAt: Date
    let author: SocialPersonDTO
    let canDelete: Bool
}

struct TogetherReactionRequestDTO: Codable, Sendable { let type: String }
struct TogetherCommentRequestDTO: Codable, Sendable { let body: String }
struct TogetherCommentsResponseDTO: Codable, Sendable { let comments: [TogetherCommentDTO] }
struct SocialActivityShareRequestDTO: Codable, Sendable {
    let activityId: String
    let caption: String?
    let visibility: String
}
struct TogetherInvitationRequestDTO: Codable, Sendable { let recipientUserId: String? }

struct TogetherInvitationResponseDTO: Codable, Sendable {
    let id: String
    let token: String
    let status: String
}
