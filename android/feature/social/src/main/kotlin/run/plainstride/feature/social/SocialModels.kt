package run.plainstride.feature.social

import kotlinx.serialization.Serializable
import kotlinx.serialization.SerialName
import kotlinx.serialization.json.JsonElement

@Serializable data class SocialPerson(
    val id: String,
    val displayName: String,
    val username: String? = null,
    val avatarUrl: String? = null,
    val relationship: String = "none",
    val isActive: Boolean = false,
    val recognitions: List<RecognitionAward> = emptyList(),
    val connectionId: String? = null,
    val connectionDirection: String? = null,
)
@Serializable data class RecognitionAward(val badgeId: String, val awardedAt: String, val shareable: Boolean = false)
@Serializable data class RoutePoint(val latitude: Double, val longitude: Double)
@Serializable data class FeedActivity(
    val id: String,
    val title: String,
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
)
@Serializable data class SocialGroup(val id: String, val name: String, val description: String? = null, val memberCount: Int = 0, val joined: Boolean = false)
@Serializable data class SocialEvent(
    val id: String,
    @SerialName("title") val name: String,
    val startsAt: String,
    val endsAt: String? = null,
    val locationName: String? = null,
    val participationMode: String = "hybrid",
    @SerialName("currentUserGoing") val joined: Boolean = false,
)
@Serializable data class SocialInvitation(val id: String, val kind: String, val title: String, val sender: SocialPerson, val objectId: String? = null)
@Serializable data class CircleMember(val person: SocialPerson, val completed: Int = 0, val target: Int? = null, val skipped: Boolean = false)
@Serializable data class CircleSummary(
    val id: String,
    val name: String,
    val lifecycle: String,
    val primary: Boolean = false,
    val eligibleForToday: Boolean = false,
    val focusMode: String = "none",
    val completed: Int = 0,
    val target: Int? = null,
    val members: List<CircleMember> = emptyList(),
)
@Serializable data class SocialHome(
    val connections: List<SocialPerson> = emptyList(),
    val posts: List<SocialPost> = emptyList(),
    @SerialName("clubs") val groups: List<SocialGroup> = emptyList(),
    val upcomingRuns: List<SocialEvent> = emptyList(),
    val pastEvents: List<SocialEvent> = emptyList(),
    val invitations: List<SocialInvitation> = emptyList(),
    val circles: List<CircleSummary> = emptyList(),
    val recognitions: List<RecognitionAward> = emptyList(),
    @SerialName("nextFeedCursor") val nextCursor: String? = null,
)
@Serializable data class SocialPage<T>(val items: List<T>, val nextCursor: String? = null)
@Serializable data class SocialComment(val id:String,val body:String,val author:SocialPerson,val createdAt:String,val canDelete:Boolean=false)
@Serializable data class EventInvitation(val id:String,val token:String?=null,val status:String="pending")

enum class ReportReason(val wireValue:String){ HARASSMENT("harassment"),HATE("hate"),SPAM("spam"),SEXUAL("sexual"),VIOLENCE("violence"),PRIVACY("privacy"),OTHER("other") }

enum class SocialError { SIGNED_OUT, OFFLINE, FORBIDDEN, NOT_FOUND, CONFLICT, RATE_LIMITED, SERVER, INVALID_RESPONSE, UNEXPECTED }
class SocialException(val reason: SocialError) : Exception(reason.name)
