import CoreLocation
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
    var nextFeedCursor: String? = nil
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

struct SocialProfileResponseDTO: Codable, Sendable {
    let person: SocialPersonDTO
    let recognitions: [RecognitionAwardDTO]
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
    let isInActiveWorkout: Bool?

    init(
        id: String,
        status: String,
        direction: String,
        person: SocialPersonDTO,
        isInActiveWorkout: Bool? = nil
    ) {
        self.id = id
        self.status = status
        self.direction = direction
        self.person = person
        self.isInActiveWorkout = isInActiveWorkout
    }

    nonisolated var firstName: String {
        person.displayName
            .components(separatedBy: .whitespacesAndNewlines)
            .first(where: { !$0.isEmpty }) ?? person.displayName
    }

    nonisolated static func previewOrder(_ lhs: Self, _ rhs: Self) -> Bool {
        if (lhs.isInActiveWorkout == true) != (rhs.isInActiveWorkout == true) {
            return lhs.isInActiveWorkout == true
        }
        let firstNameOrder = lhs.firstName.localizedStandardCompare(rhs.firstName)
        if firstNameOrder != .orderedSame {
            return firstNameOrder == .orderedAscending
        }
        let displayNameOrder = lhs.person.displayName.localizedStandardCompare(rhs.person.displayName)
        if displayNameOrder != .orderedSame {
            return displayNameOrder == .orderedAscending
        }
        return lhs.id < rhs.id
    }
}

struct SocialConnectionsResponseDTO: Codable, Sendable {
    let connections: [SocialConnectionDTO]
    let nextCursor: String?
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
    let matchMode: String?
}

struct ConnectionLinkProfileResponseDTO: Decodable, Sendable {
    let person: SocialPersonSearchResultDTO
    let isSelf: Bool
}

struct ConnectionLinkProfilePreview: Identifiable, Sendable {
    let code: String
    let person: SocialPersonSearchResultDTO
    let isSelf: Bool

    var id: String { person.id }
}

struct SocialConnectionRequestDTO: Codable, Sendable {
    let userId: String
}

struct WorkoutPresenceRequestDTO: Encodable, Sendable {
    let clientSessionId: UUID
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

    var meetupCoordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude,
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    let title: String
    var activityType: String? = nil
    let startsAt: Date
    var endsAt: Date? = nil
    let locationName: String?
    var latitude: Double? = nil
    var longitude: Double? = nil
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

extension SessionIntent {
    func paired(with event: ActivityEventDTO, attendanceMode: String? = nil) -> SessionIntent {
        let eventDuration = event.endsAt.map { max(60, Int($0.timeIntervalSince(event.startsAt).rounded())) }
        let eventDetail = eventDuration.map { duration in
            String(
                localized: "social.event.paired_workout_duration",
                defaultValue: "Scheduled activity · \(max(1, duration / 60)) min"
            )
        } ?? String(
                localized: "social.event.scheduled_activity",
                defaultValue: "Scheduled activity"
            )

        // An activity event is a social commitment, not a wrapper around the
        // user's personal training plan. Do not carry workout steps, targets,
        // or workout references into the event: they would drive live coach
        // cues and make the event look like (and save as) the planned workout.
        return SessionIntent(
            id: "activity-event-\(event.id)-\(id)",
            sport: sport,
            title: event.title,
            detail: eventDetail,
            guideLine: String(
                localized: "social.event.paired_workout.guide",
                defaultValue: "Move together and settle into the group's agreed pace."
            ),
            startLabel: String(localized: "social.event.start", defaultValue: "Start activity"),
            targetDurationSeconds: eventDuration,
            routeName: nil,
            preparedRoute: nil,
            activityTypeOverride: activityTypeOverride,
            workoutSteps: [],
            coachingTarget: nil,
            workoutReference: nil,
            workoutCues: [],
            raceIntent: nil,
            activityEvent: ActivityEventLaunchContext(
                id: event.id,
                title: event.title,
                role: event.currentUserRole ?? "participant",
                attendanceMode: attendanceMode,
                organizerName: event.creator.displayName
            )
        )
    }
}

struct ActivityEventDetailDTO: Codable, Identifiable, Sendable {
    let id: String

    var meetupCoordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude,
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    let title: String
    var activityType: String? = nil
    let startsAt: Date
    var endsAt: Date? = nil
    let locationName: String?
    var latitude: Double? = nil
    var longitude: Double? = nil
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
    var activityType: String = "running"
    let startsAt: Date
    let locationName: String?
    var latitude: Double? = nil
    var longitude: Double? = nil
    let note: String?
    var durationMinutes: Int = ActivityEventTiming.defaultDurationMinutes
    var sourceCircleId: String? = nil
    var participationMode: String = "hybrid"
}

struct UpdateActivityEventRequestDTO: Codable, Sendable {
    let title: String
    var activityType: String? = nil
    let startsAt: Date
    let locationName: String?
    var latitude: Double? = nil
    var longitude: Double? = nil
    let note: String?
    let durationMinutes: Int
    var participationMode: String = "hybrid"
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
    let type: String?
    let title: String?
    let startedAt: Date?
    let endedAt: Date?
    let durationSecs: Int?
    let distanceM: Double?
    let elevationM: Double?
    let avgPace: Double?
    let energyKilocalories: Int?
    let route: TogetherActivityRouteDTO?
    let photos: [TogetherActivityPhotoDTO]?

    init(
        id: String,
        type: String? = nil,
        title: String?,
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        durationSecs: Int?,
        distanceM: Double?,
        elevationM: Double? = nil,
        avgPace: Double?,
        energyKilocalories: Int? = nil,
        route: TogetherActivityRouteDTO?,
        photos: [TogetherActivityPhotoDTO]? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSecs = durationSecs
        self.distanceM = distanceM
        self.elevationM = elevationM
        self.avgPace = avgPace
        self.energyKilocalories = energyKilocalories
        self.route = route
        self.photos = photos
    }
}

struct TogetherActivityPhotoDTO: Codable, Sendable {
    let id: String
    let clientPhotoId: String
    let url: URL?
    let takenAt: Date
    let paceAtShot: Double?
    let hrAtShot: Int?
    let distAtShot: Double?
    let latitude: Double?
    let longitude: Double?
    let captureContext: String?
}

struct TogetherActivityRouteDTO: Codable, Sendable {
    let format: String
    let encodedPolyline: String
    let pointCount: Int
    let bounds: TogetherActivityRouteBoundsDTO

    nonisolated var coordinates: [[Double]] {
        guard format == "polyline5", (2...120).contains(pointCount) else { return [] }
        let bytes = Array(encodedPolyline.utf8)
        var index = 0
        var latitude = 0
        var longitude = 0
        var decoded: [[Double]] = []
        decoded.reserveCapacity(pointCount)
        while index < bytes.count,
              let latitudeDelta = Self.decodeDelta(bytes, index: &index),
              let longitudeDelta = Self.decodeDelta(bytes, index: &index) {
            latitude += latitudeDelta
            longitude += longitudeDelta
            decoded.append([Double(longitude) / 100_000, Double(latitude) / 100_000])
        }
        return decoded.count == pointCount && index == bytes.count ? decoded : []
    }

    nonisolated private static func decodeDelta(_ bytes: [UInt8], index: inout Int) -> Int? {
        var result = 0
        var shift = 0
        while index < bytes.count, shift <= 30 {
            let value = Int(bytes[index]) - 63
            index += 1
            guard (0...63).contains(value) else { return nil }
            result |= (value & 0x1f) << shift
            if value < 0x20 {
                return (result & 1) == 0 ? result >> 1 : ~(result >> 1)
            }
            shift += 5
        }
        return nil
    }
}

struct TogetherActivityRouteBoundsDTO: Codable, Sendable {
    let south: Double
    let west: Double
    let north: Double
    let east: Double
}

struct TogetherPostDTO: Codable, Identifiable, Sendable {
    let id: String
    let caption: String?
    let createdAt: Date
    let isCurrentUser: Bool
    let user: TogetherPersonDTO
    let activity: TogetherActivityDTO?
    let reactionCount: Int
    let cheers: [SocialPersonDTO]
    let currentUserCheered: Bool
    let commentCount: Int
    let comments: [TogetherCommentDTO]

    var activityTimestamp: Date {
        activity?.startedAt ?? createdAt
    }
}

extension TogetherPostDTO {
    /// Tolerates older servers that predate the cheers payload so a contract
    /// mismatch degrades to an empty cheerer list instead of failing the whole
    /// `/social/home` decode and bricking the Social feed refresh.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        caption = try container.decodeIfPresent(String.self, forKey: .caption)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        isCurrentUser = try container.decode(Bool.self, forKey: .isCurrentUser)
        user = try container.decode(TogetherPersonDTO.self, forKey: .user)
        activity = try container.decodeIfPresent(TogetherActivityDTO.self, forKey: .activity)
        reactionCount = try container.decode(Int.self, forKey: .reactionCount)
        cheers = try container.decodeIfPresent([SocialPersonDTO].self, forKey: .cheers) ?? []
        currentUserCheered = try container.decode(Bool.self, forKey: .currentUserCheered)
        commentCount = try container.decode(Int.self, forKey: .commentCount)
        comments = try container.decode([TogetherCommentDTO].self, forKey: .comments)
    }
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
