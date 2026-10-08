package com.plainstride.outbound.feature.social

import kotlinx.serialization.Serializable
import kotlinx.serialization.SerialName
import kotlinx.serialization.json.JsonElement

@Serializable data class SocialPerson(
    val id: String,
    val displayName: String,
    val username: String? = null,
    val avatarUrl: String? = null,
    @SerialName("relationship") val relationshipDetails: SocialRelationship? = null,
    @kotlinx.serialization.Transient val relationship: String = relationshipDetails?.status ?: "none",
    val isActive: Boolean = false,
    val recognitions: List<RecognitionAward> = emptyList(),
    @kotlinx.serialization.Transient val connectionId: String? = relationshipDetails?.id,
    @kotlinx.serialization.Transient val connectionDirection: String? = relationshipDetails?.direction,
)
@Serializable data class SocialRelationship(val id: String, val status: String, val direction: String)
@Serializable data class RecognitionAward(
    val badgeId: String,
    @SerialName("earnedAt") val awardedAt: String,
    @SerialName("shareEligible") val shareable: Boolean = false,
)
@Serializable data class RoutePoint(val latitude: Double, val longitude: Double)
@Serializable data class FeedActivity(
    val id: String,
    val title: String = "Activity",
    val type: String = "running",
    val startedAt: String,
    val endedAt: String? = null,
    val distanceM: Double? = null,
    val durationSecs: Int? = null,
    val elevationM: Double? = null,
    val energyKilocalories: Int? = null,
    @SerialName("avgPace") val averagePaceSecsPerKm: Double? = null,
    val route: JsonElement? = null,
    val photos: List<ActivityPhoto> = emptyList(),
    val photoCount: Int? = null,
    val recognitions: List<ActivityRecognition> = emptyList(),
) {
    val totalPhotoCount: Int get() = photoCount ?: photos.size
}
@Serializable data class ActivityRecognition(val badgeId: String, val earnedAt: String? = null)
@Serializable data class ActivityPhoto(
    val id: String,
    val clientPhotoId: String = id,
    val url: String? = null,
    val thumbnailUrl: String? = null,
    val takenAt: String = "",
    val paceAtShot: Double? = null,
    val hrAtShot: Int? = null,
    val distAtShot: Double? = null,
    val latitude: Double? = null,
    val longitude: Double? = null,
    val captureContext: String? = null,
)
@Serializable data class SocialPostPhotosResponse(val photos: List<ActivityPhoto> = emptyList())
@Serializable data class SocialPost(
    val id: String,
    @SerialName("user")
    val author: SocialPerson,
    val activity: FeedActivity? = null,
    val caption: String? = null,
    @SerialName("reactionCount")
    val cheerCount: Int = 0,
    val commentCount: Int = 0,
    @SerialName("currentUserCheered")
    val viewerHasCheered: Boolean = false,
    val cheers: List<SocialPerson> = emptyList(),
    val isCurrentUser: Boolean = false,
    val createdAt: String? = null,
) {
    val activityTimestamp: String?
        get() {
            val currentActivity = activity ?: return createdAt
            return currentActivity.endedAt ?: runCatching {
                java.time.OffsetDateTime.parse(currentActivity.startedAt)
                    .plusSeconds((currentActivity.durationSecs ?: 0).toLong())
                    .toString()
            }.getOrDefault(currentActivity.startedAt)
        }
}
@Serializable data class SocialGroup(
    val id: String,
    val name: String,
    val description: String? = null,
    val city: String? = null,
    val memberCount: Int = 0,
    val joined: Boolean = false,
    val groupType: String? = null,
    val trustPolicy: String? = null,
    val canJoin: Boolean? = null,
    val contextLabel: String? = null,
)
@Serializable data class SocialEvent(
    val id: String,
    @SerialName("title") val name: String,
    val startsAt: String,
    val endsAt: String? = null,
    val locationName: String? = null,
    val participationMode: String = "hybrid",
    @SerialName("currentUserGoing") val joined: Boolean = false,
    val status: String = "scheduled",
    val note: String? = null,
    val attendeeCount: Int = 0,
    val currentUserRole: String = "viewer",
    val currentUserOutcome: String? = null,
    val currentUserAttendanceMode: String? = null,
    val source: SocialEventSource? = null,
    val paceNote: String? = null,
    val latitude: Double? = null,
    val longitude: Double? = null,
    val creator: SocialPerson? = null,
    val group: SocialGroup? = null,
    val activityType: String? = null,
    val attendeePreview: List<SocialPerson> = emptyList(),
    val participants: List<SocialEventParticipant> = emptyList(),
    val options: List<SocialEventOption> = emptyList(),
    val compatibility: SocialEventCompatibility? = null,
)
@Serializable data class SocialEventSource(val kind: String)
@Serializable data class SocialEventParticipant(val person: SocialPerson, val attendanceMode: String? = null, val status: String = "going")
@Serializable data class SocialEventOption(val id: String, val label: String, val distanceMeters: Double? = null)
@Serializable data class SocialEventCompatibility(val groupId: String, val explanation: String)
@Serializable data class SocialInvitation(val id: String, val kind: String, val title: String, val sender: SocialPerson, val objectId: String? = null)
@Serializable data class GroupCommitment(val targetCount: Int? = null, val skipped: Boolean = false)
@Serializable data class GroupMember(
    val id: String = "",
    @SerialName("user") val person: SocialPerson,
    val role: String = "member",
    val isCurrentUser: Boolean = false,
    @SerialName("contributedCount") val completed: Int = 0,
    val commitment: GroupCommitment? = null,
    val recentActivity: GroupRecentActivity? = null,
) {
    val target: Int? get() = commitment?.targetCount
    val skipped: Boolean get() = commitment?.skipped == true
}
@Serializable data class GroupRecentActivity(val type:String="running",val title:String?=null,val startedAt:String,val durationSecs:Int?=null,val distanceM:Double?=null,val elevationM:Double?=null,val avgPace:Double?=null,val avgHeartRate:Int?=null,val energyKilocalories:Int?=null)
@Serializable data class GroupFocus(val mode: String = "none", val focusConfigured: Boolean = false, val sharedTarget: Int? = null, val themeKey: String? = null, val themeTitle: String? = null, val themeNote: String? = null)
@Serializable data class GroupWeek(val id: String = "none", val focusMode: String = "none", val focusConfigured: Boolean = false, val contributedCount: Int = 0, val targetCount: Int? = null, val themeKey: String? = null, val themeTitle: String? = null, val themeNote: String? = null, val state: String = "open")
@Serializable data class GroupNotice(val id:String,val title:String?=null,val body:String,val pinned:Boolean=false,val publishedAt:String?=null,val editedAt:String?=null)
@Serializable data class GroupInvitationSnapshot(val id:String,val recipient:SocialPerson?=null,val status:String="pending")
@Serializable data class GroupCapability(val weeklyTheme:Boolean=false,val workoutContributions:Boolean=false,val presetCheers:Boolean=false,val notices:Boolean=false,val scheduledActivities:Boolean=true)
@Serializable data class GroupActivitySummary(val id:String,val title:String,val startsAt:String,val endsAt:String?=null,val locationName:String?=null,val paceNote:String?=null,val status:String="scheduled",val attendeeCount:Int=0,val currentUserGoing:Boolean=false)
@Serializable data class GroupMoment(val id:String,val type:String,val createdAt:String,val title:String?=null)
@Serializable data class GroupWeekHistory(val id:String,val startsAt:String,val themeKey:String?=null,val themeTitle:String?=null,val state:String="recorded")
@Serializable data class GroupPendingRequest(val status:String="pending")
@Serializable data class GroupSummary(
    val id: String,
    val name: String,
    val lifecycle: String,
    val role: String? = null,
    val membershipRole: String? = null,
    val trustPolicy: String? = null,
    val visibility: String? = null,
    val joinPolicy: String? = null,
    val description: String? = null,
    val city: String? = null,
    val resetWeekday: Int = 1,
    val timeZone: String = "",
    val memberLimit: Int = 500,
    val memberCount: Int = 0,
    val owner: SocialPerson? = null,
    val completionPresentationPending: Boolean = false,
    val currentUserMuted: Boolean = false,
    val eligibleForToday: Boolean = false,
    val upcomingFocus: GroupFocus = GroupFocus(),
    val week: GroupWeek = GroupWeek(),
    val members: List<GroupMember> = emptyList(),
    val invitations: List<GroupInvitationSnapshot> = emptyList(),
    val upcomingActivities: List<GroupActivitySummary> = emptyList(),
    val recentMoments: List<GroupMoment> = emptyList(),
    val history: List<GroupWeekHistory>? = null,
    val capabilities: GroupCapability = GroupCapability(),
    val notices: List<GroupNotice> = emptyList(),
    val unreadNoticeCount: Int = 0,
    val pendingRequest: GroupPendingRequest? = null,
    val invitationPreview: Boolean = false,
    val pendingInvitation: GroupInvitationDto? = null,
    val featured: Boolean = false,
    val organizationVerificationState: String = "unverified",
) {
    val currentUserRole: String? get() = role ?: membershipRole
    val focusMode: String get() = week.focusMode
    val completed: Int get() = week.contributedCount
    val target: Int? get() = week.targetCount
}
@Serializable data class SocialHome(
    val connections: List<SocialPerson> = emptyList(),
    val connectionNextCursor: String? = null,
    val posts: List<SocialPost> = emptyList(),
    val upcomingRuns: List<SocialEvent> = emptyList(),
    val pastEvents: List<SocialEvent> = emptyList(),
    val invitations: List<SocialInvitation> = emptyList(),
    val groups: List<GroupSummary> = emptyList(),
    val recognitions: List<RecognitionAward> = emptyList(),
    @SerialName("nextFeedCursor") val nextCursor: String? = null,
)
@Serializable data class SocialPage<T>(val items: List<T>, val nextCursor: String? = null)
@Serializable data class SocialComment(val id:String,val body:String,val author:SocialPerson,val createdAt:String,val canDelete:Boolean=false)
@Serializable data class EventInvitation(val id:String,val token:String?=null,val status:String="pending")

enum class ReportReason(val wireValue:String){ HARASSMENT("harassment"),HATE("hate"),SPAM("spam"),SEXUAL("sexual"),VIOLENCE("violence"),PRIVACY("privacy"),OTHER("other") }

enum class SocialError { SIGNED_OUT, OFFLINE, FORBIDDEN, NOT_FOUND, CONFLICT, RATE_LIMITED, SERVER, INVALID_RESPONSE, UNEXPECTED }
class SocialException(val reason: SocialError, val httpStatus: Int? = null) : Exception(reason.name)

@Serializable data class BlockedAccount(val person: SocialPerson, val blockedAt: String? = null)
@Serializable data class ConnectionLink(val code: String, val url: String)
@Serializable data class ConnectionLinkPreview(val person: SocialPerson, val isSelf: Boolean = false)
@Serializable data class ConnectionLinkResult(val result: String, val person: SocialPerson, val relationship: SocialRelationship? = null)
@Serializable data class SocialNotification(val id: String, val type: String, val objectId: String, val message: String, val readAt: String? = null)
@Serializable data class EventParticipant(val person: SocialPerson, val status: String, val outcome: String? = null, val attendanceMode: String? = null, val recordedActivity: FeedActivity? = null)
@Serializable data class ActivityEventResult(val event: SocialEvent? = null, val participants: List<EventParticipant> = emptyList())
