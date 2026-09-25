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
    val distanceM: Double? = null,
    val durationSecs: Int? = null,
    @SerialName("avgPace") val averagePaceSecsPerKm: Double? = null,
    val route: JsonElement? = null,
    val photos: List<ActivityPhoto> = emptyList(),
)
@Serializable data class ActivityPhoto(val id: String, val url: String? = null)
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
    val isCurrentUser: Boolean = false,
    val createdAt: String? = null,
)
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
    val currentUserAttendanceMode: String? = null,
)
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
@Serializable data class GroupFocus(val mode: String = "none", val focusConfigured: Boolean = false, val sharedTarget: Int? = null)
@Serializable data class GroupWeek(val focusMode: String = "none", val contributedCount: Int = 0, val targetCount: Int? = null)
@Serializable data class GroupNotice(val id:String,val title:String?=null,val body:String,val pinned:Boolean=false,val publishedAt:String?=null,val editedAt:String?=null)
@Serializable data class GroupCapability(val weeklyTheme:Boolean=false,val workoutContributions:Boolean=false,val presetCheers:Boolean=false,val notices:Boolean=false,val scheduledActivities:Boolean=true)
@Serializable data class GroupSummary(
    val id: String,
    val name: String,
    val lifecycle: String,
    val role: String? = null,
    val trustPolicy: String? = null,
    val visibility: String? = null,
    val joinPolicy: String? = null,
    val description: String? = null,
    val city: String? = null,
    val memberLimit: Int = 6,
    val memberCount: Int = 0,
    val currentUserMuted: Boolean = false,
    val eligibleForToday: Boolean = false,
    val upcomingFocus: GroupFocus = GroupFocus(),
    val week: GroupWeek = GroupWeek(),
    val members: List<GroupMember> = emptyList(),
    val capabilities: GroupCapability = GroupCapability(),
    val notices: List<GroupNotice> = emptyList(),
    val unreadNoticeCount: Int = 0,
    val featured: Boolean = false,
    val organizationVerificationState: String = "unverified",
) {
    val focusMode: String get() = week.focusMode
    val completed: Int get() = week.contributedCount
    val target: Int? get() = week.targetCount
}
@Serializable data class SocialHome(
    val connections: List<SocialPerson> = emptyList(),
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
class SocialException(val reason: SocialError) : Exception(reason.name)

@Serializable data class BlockedAccount(val person: SocialPerson, val blockedAt: String? = null)
@Serializable data class ConnectionLink(val code: String, val url: String)
@Serializable data class ConnectionLinkPreview(val person: SocialPerson, val isSelf: Boolean = false)
@Serializable data class ConnectionLinkResult(val result: String, val person: SocialPerson, val relationship: SocialRelationship? = null)
@Serializable data class SocialNotification(val id: String, val type: String, val objectId: String, val message: String, val readAt: String? = null)
@Serializable data class EventParticipant(val person: SocialPerson, val status: String, val outcome: String? = null, val attendanceMode: String? = null, val recordedActivity: FeedActivity? = null)
@Serializable data class ActivityEventResult(val event: SocialEvent? = null, val participants: List<EventParticipant> = emptyList())
