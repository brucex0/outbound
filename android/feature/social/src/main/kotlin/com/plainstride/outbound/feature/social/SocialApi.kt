package com.plainstride.outbound.feature.social

import kotlinx.serialization.Serializable
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import retrofit2.Response
import retrofit2.Retrofit
import retrofit2.converter.kotlinx.serialization.asConverterFactory
import retrofit2.http.*
import com.plainstride.outbound.core.network.PlainstrideJson

@Serializable data class FeedResponse(val posts: List<SocialPost> = emptyList(), val nextCursor: String? = null)
@Serializable data class ConnectionDto(val id: String, val status: String, val direction: String, val person: SocialPerson, val isInActiveWorkout: Boolean = false)
@Serializable data class ConnectionsResponse(val connections: List<ConnectionDto> = emptyList(), val nextCursor: String? = null)
@Serializable data class PeopleResponse(val people: List<SocialPerson> = emptyList(), val matchMode: String = "unknown")
@Serializable data class ProfileResponse(val person: SocialPerson, val recognitions: List<RecognitionAward> = emptyList())
@Serializable data class GroupsResponse(val groups: List<GroupSummary> = emptyList(), val nextCursor: String? = null)
@Serializable data class AwardsResponse(val awards: List<RecognitionAward> = emptyList())
@Serializable data class IdBody(val userId: String)
@Serializable data class CaptionBody(val caption: String? = null, val visibility: String = "connections")
@Serializable data class ReportBody(val targetType: String, val targetId: String, val reason: String)
@Serializable data class CheerBody(val recipientUserId: String, val presetType: String = "encouragement")
@Serializable data class CommentsResponse(val comments:List<SocialComment> = emptyList())
@Serializable data class CommentBody(val body:String)
@Serializable data class AttendanceBody(val attendanceMode:String="in_person")
@Serializable data class EventInviteBody(val recipientUserId:String?=null)
@Serializable data class CreateGroupBody(val template:String="motivation",val name:String?=null,val description:String?=null,val city:String?=null,val activityInterests:List<String> = emptyList(),val memberUserIds:List<String> = emptyList(),val timeZone:String?=null,val resetWeekday:Int?=null,val idempotencyKey:String?=null)
@Serializable data class GroupInviteBody(val recipientUserIds:List<String>,val idempotencyKey:String?=null)
@Serializable data class GroupFocusBody(val mode:String,val sharedTarget:Int?=null,val apply:String="now")
@Serializable data class RenameGroupBody(val name:String)
@Serializable data class GroupCommitmentBody(val targetCount:Int?=null,val skipped:Boolean=false)
@Serializable data class GroupMuteBody(val muted:Boolean)
@Serializable data class GroupMutationResponse(val group:GroupSummary)
@Serializable data class GroupInvitationGroup(val id:String,val name:String)
@Serializable data class GroupInvitationDto(val id:String,val sender:SocialPerson,val group:GroupInvitationGroup)
@Serializable data class GroupInvitationsResponse(val invitations:List<GroupInvitationDto> = emptyList())
@Serializable data class BlocksResponse(val blocks: List<BlockedAccount> = emptyList())
@Serializable data class NotificationsResponse(val notifications: List<SocialNotification> = emptyList())
@Serializable data class PresenceBody(val clientSessionId: String)
@Serializable data class CreateEventBody(val title:String,val startsAt:String,val durationMinutes:Int=60,val locationName:String?=null,val latitude:Double?=null,val longitude:Double?=null,val note:String?=null,val groupId:String?=null)
@Serializable data class EventInviteBatchBody(val recipientUserIds:List<String>)
@Serializable data class LinkActivityBody(val activityId:String)

interface SocialApiService {
    @GET("v1/social/home") suspend fun home(@Header("Authorization") auth: String): Response<SocialHome>
    @GET("v1/social/home") suspend fun feed(@Header("Authorization") auth: String, @Query("feedCursor") cursor: String? = null): Response<SocialHome>
    @GET("v1/social/connections") suspend fun connections(@Header("Authorization") auth: String, @Query("cursor") cursor: String? = null): Response<ConnectionsResponse>
    @GET("v1/social/people/search") suspend fun search(@Header("Authorization") auth: String, @Query("q") query: String): Response<PeopleResponse>
    @GET("v1/social/users/{id}/profile") suspend fun profile(@Header("Authorization") auth: String, @Path("id") id: String): Response<ProfileResponse>
    @POST("v1/social/connections") suspend fun connect(@Header("Authorization") auth: String, @Body body: IdBody): Response<Unit>
    @POST("v1/social/connections/{id}/accept") suspend fun accept(@Header("Authorization") auth: String, @Path("id") id: String): Response<Unit>
    @DELETE("v1/social/connections/{id}") suspend fun removeConnection(@Header("Authorization") auth: String, @Path("id") id: String): Response<Unit>
    @POST("v1/social/groups/{id}/join-requests") suspend fun joinGroup(@Header("Authorization") auth: String, @Path("id") id: String): Response<Unit>
    @POST("v1/social/groups/{id}/leave") suspend fun leaveGroup(@Header("Authorization") auth: String, @Path("id") id: String): Response<Unit>
    @PUT("v1/social/posts/{id}/cheer") suspend fun cheer(@Header("Authorization") auth: String, @Path("id") id: String): Response<Unit>
    @DELETE("v1/social/posts/{id}/cheer") suspend fun removeCheer(@Header("Authorization") auth: String, @Path("id") id: String): Response<Unit>
    @DELETE("v1/social/posts/{id}") suspend fun deletePost(@Header("Authorization") auth: String, @Path("id") id: String): Response<Unit>
    @POST("v1/social/reports") suspend fun reportPost(@Header("Authorization") auth: String, @Body body: ReportBody): Response<Unit>
    @POST("v1/social/users/{id}/block") suspend fun block(@Header("Authorization") auth: String, @Path("id") id: String): Response<Unit>
    @DELETE("v1/social/users/{id}/block") suspend fun unblock(@Header("Authorization") auth: String, @Path("id") id: String): Response<Unit>
    @GET("v1/social/blocks") suspend fun blocks(@Header("Authorization") auth: String): Response<BlocksResponse>
    @POST("v1/social/connection-links") suspend fun connectionLink(@Header("Authorization") auth: String): Response<ConnectionLink>
    @GET("v1/social/connection-links/{code}") suspend fun connectionLinkPreview(@Header("Authorization") auth: String, @Path("code") code: String): Response<ConnectionLinkPreview>
    @POST("v1/social/connection-links/{code}/request") suspend fun consumeConnectionLink(@Header("Authorization") auth: String, @Path("code") code: String): Response<ConnectionLinkResult>
    @POST("v1/social/referrals") suspend fun referralLink(@Header("Authorization") auth: String): Response<ConnectionLink>
    @PUT("v1/social/workout-presence") suspend fun setPresence(@Header("Authorization") auth: String, @Body body: PresenceBody): Response<Unit>
    @DELETE("v1/social/workout-presence/{id}") suspend fun clearPresence(@Header("Authorization") auth: String, @Path("id") clientSessionId: String): Response<Unit>
    @GET("v1/social/notifications") suspend fun notifications(@Header("Authorization") auth: String): Response<NotificationsResponse>
    @POST("v1/social/notifications/read-all") suspend fun readNotifications(@Header("Authorization") auth: String): Response<Unit>
    @GET("v1/social/posts/{id}/comments") suspend fun comments(@Header("Authorization") auth:String,@Path("id") id:String):Response<CommentsResponse>
    @POST("v1/social/posts/{id}/comments") suspend fun comment(@Header("Authorization") auth:String,@Path("id") id:String,@Body body:CommentBody):Response<SocialComment>
    @DELETE("v1/social/comments/{id}") suspend fun deleteComment(@Header("Authorization") auth:String,@Path("id") id:String):Response<Unit>
    @POST("v1/social/activity-events/{id}/rsvp") suspend fun rsvp(@Header("Authorization") auth:String,@Path("id") id:String,@Body body:AttendanceBody):Response<Unit>
    @DELETE("v1/social/activity-events/{id}/rsvp") suspend fun leaveEvent(@Header("Authorization") auth:String,@Path("id") id:String):Response<Unit>
    @POST("v1/social/activity-events/{id}/invitations") suspend fun inviteEvent(@Header("Authorization") auth:String,@Path("id") id:String,@Body body:EventInviteBody):Response<EventInvitation>
    @GET("v1/social/activity-events/{id}") suspend fun event(@Header("Authorization") auth:String,@Path("id") id:String):Response<SocialEvent>
    @POST("v1/social/activity-events") suspend fun createEvent(@Header("Authorization") auth:String,@Body body:CreateEventBody):Response<SocialEvent>
    @POST("v1/social/activity-events/{id}/invitations/batch") suspend fun inviteEventBatch(@Header("Authorization") auth:String,@Path("id") id:String,@Body body:EventInviteBatchBody):Response<Unit>
    @DELETE("v1/social/activity-events/{eventId}/invitations/{invitationId}") suspend fun cancelEventInvitation(@Header("Authorization") auth:String,@Path("eventId") eventId:String,@Path("invitationId") invitationId:String):Response<Unit>
    @POST("v1/social/activity-events/{id}/link-activity") suspend fun linkActivity(@Header("Authorization") auth:String,@Path("id") id:String,@Body body:LinkActivityBody):Response<Unit>
    @POST("v1/social/activity-events/{id}/no-recording") suspend fun noRecording(@Header("Authorization") auth:String,@Path("id") id:String):Response<Unit>
    @GET("v1/social/activity-events/{id}/results") suspend fun eventResults(@Header("Authorization") auth:String,@Path("id") id:String):Response<ActivityEventResult>
    @POST("v1/social/invitations/{id}/accept") suspend fun acceptEventInvitation(@Header("Authorization") auth:String,@Path("id") id:String,@Body body:AttendanceBody=AttendanceBody()):Response<Unit>
    @POST("v1/social/invitations/{id}/decline") suspend fun declineEventInvitation(@Header("Authorization") auth:String,@Path("id") id:String):Response<Unit>
    @GET("v1/social/groups") suspend fun groups(@Header("Authorization") auth: String, @Query("scope") scope: String = "mine", @Query("query") query: String? = null, @Query("city") city: String? = null, @Query("cursor") cursor: String? = null): Response<GroupsResponse>
    @GET("v1/social/groups/{id}") suspend fun group(@Header("Authorization") auth: String, @Path("id") id: String): Response<GroupSummary>
    @PATCH("v1/social/groups/{id}") suspend fun renameGroup(@Header("Authorization") auth:String,@Path("id") id:String,@Body body:RenameGroupBody):Response<GroupSummary>
    @PUT("v1/social/groups/{id}/commitment") suspend fun groupCommitment(@Header("Authorization") auth:String,@Path("id") id:String,@Body body:GroupCommitmentBody):Response<GroupSummary>
    @PUT("v1/social/groups/{id}/notifications") suspend fun muteGroup(@Header("Authorization") auth:String,@Path("id") id:String,@Body body:GroupMuteBody):Response<GroupSummary>
    @DELETE("v1/social/groups/{id}/members/{userId}") suspend fun removeGroupMember(@Header("Authorization") auth:String,@Path("id") id:String,@Path("userId") userId:String):Response<GroupSummary>
    @POST("v1/social/groups/{id}/cheers") suspend fun groupCheer(@Header("Authorization") auth: String, @Path("id") id: String, @Body body: CheerBody): Response<Unit>
    @POST("v1/social/groups") suspend fun createGroup(@Header("Authorization") auth:String,@Body body:CreateGroupBody):Response<GroupSummary>
    @POST("v1/social/groups/{id}/invitations") suspend fun inviteGroup(@Header("Authorization") auth:String,@Path("id") id:String,@Body body:GroupInviteBody):Response<GroupMutationResponse>
    @POST("v1/social/groups/{id}/focus") suspend fun focusGroup(@Header("Authorization") auth:String,@Path("id") id:String,@Body body:GroupFocusBody):Response<GroupSummary>
    @POST("v1/social/groups/{id}/archive") suspend fun archiveGroup(@Header("Authorization") auth:String,@Path("id") id:String):Response<GroupSummary>
    @POST("v1/social/groups/{id}/reactivate") suspend fun reactivateGroup(@Header("Authorization") auth:String,@Path("id") id:String):Response<GroupSummary>
    @POST("v1/social/groups/invitations/{id}/accept") suspend fun acceptGroupInvitation(@Header("Authorization") auth:String,@Path("id") id:String):Response<GroupSummary>
    @POST("v1/social/groups/invitations/{id}/decline") suspend fun declineGroupInvitation(@Header("Authorization") auth:String,@Path("id") id:String):Response<Unit>
    @GET("v1/social/groups/invitations/inbox") suspend fun groupInvitations(@Header("Authorization") auth:String):Response<GroupInvitationsResponse>
    @POST("invite/group/{token}/consume") suspend fun consumeGroupInvite(@Header("Authorization") auth:String,@Path("token") token:String):Response<GroupSummary>
    @GET("v1/recognition") suspend fun awards(@Header("Authorization") auth: String): Response<AwardsResponse>
}

fun createSocialApi(baseUrl: String, client: OkHttpClient): SocialApiService = Retrofit.Builder()
    .baseUrl(if (baseUrl.endsWith('/')) baseUrl else "$baseUrl/")
    .client(client)
    .addConverterFactory(PlainstrideJson.asConverterFactory("application/json".toMediaType()))
    .build().create(SocialApiService::class.java)
