package com.plainstride.outbound.feature.safety

import kotlinx.serialization.Serializable
import retrofit2.Response
import retrofit2.http.*
import okhttp3.OkHttpClient
import okhttp3.MediaType.Companion.toMediaType
import retrofit2.Retrofit
import retrofit2.converter.kotlinx.serialization.asConverterFactory
import com.plainstride.outbound.core.network.PlainstrideJson

@Serializable data class TrustedContact(val id:String,val displayName:String,val channel:String,val address:String,val isDefault:Boolean=false)
@Serializable data class DeliveryTarget(val channel:String,val label:String?=null,val address:String?=null)
@Serializable data class CreateLiveShareRequest(val activityId:String?=null,val recipientLabel:String?=null,val deliveryTargets:List<DeliveryTarget> = emptyList(),val sport:String?=null,val title:String?=null,val expiresInSeconds:Int=14400)
@Serializable data class LiveShare(val id:String,val shareURL:String?=null,val status:String,val startedAt:String,val expiresAt:String,val stale:Boolean=false)
@Serializable data class LiveLocation(val recordedAt:String,val latitude:Double,val longitude:Double,val altitudeM:Double?=null,val accuracyM:Double?=null,val elapsedSeconds:Int,val distanceM:Double)
@Serializable data class PushDeviceRequest(val token:String,val platform:String="android",val appBundle:String,val locale:String?=null)
@Serializable data class InboxActor(val id:String,val displayName:String,val avatarUrl:String?=null)
@Serializable data class InboxNotification(val id:String,val type:String,val objectId:String,val message:String,val readAt:String?=null,val actor:InboxActor?=null)
@Serializable data class InboxResponse(val notifications:List<InboxNotification> = emptyList())
@Serializable data class GroupRunParticipant(val id:String,val userId:String,val displayName:String,val status:String,val lastLocationAt:String?=null,val lastLocation:GroupRunPoint?=null,val lastActivitySnapshot:GroupRunProgress?=null)
@Serializable data class GroupRunPoint(val latitude:Double,val longitude:Double,val altitudeM:Double?=null,val accuracyM:Double?=null)
@Serializable data class GroupRunProgress(val elapsedSeconds:Int=0,val distanceM:Double=0.0,val paceSecondsPerKM:Double?=null)
@Serializable data class GroupRun(val id:String,val status:String,val title:String?=null,val sport:String?=null,val creatorUserId:String,val currentUserId:String,val startedAt:String,val expiresAt:String,val inviteURL:String?=null,val participants:List<GroupRunParticipant> = emptyList())
@Serializable data class CreateGroupRunRequest(val title:String?=null,val sport:String?=null,val expiresInSeconds:Int=14400)
@Serializable data class JoinGroupRunRequest(val invite:String)
@Serializable data class GroupLocationUpdate(val recordedAt:String,val latitude:Double,val longitude:Double,val altitudeM:Double?=null,val accuracyM:Double?=null,val elapsedSeconds:Int,val distanceM:Double,val paceSecondsPerKM:Double?=null)

interface SafetyApi {
 @POST("v1/safety/live-shares") suspend fun create(@Header("Authorization") auth:String,@Body body:CreateLiveShareRequest):Response<LiveShare>
 @GET("v1/safety/live-shares/{id}") suspend fun liveShare(@Header("Authorization") auth:String,@Path("id") id:String):Response<LiveShare>
 @PATCH("v1/safety/live-shares/{id}/location") suspend fun update(@Header("Authorization") auth:String,@Path("id") id:String,@Body body:LiveLocation):Response<LiveShare>
 @POST("v1/safety/live-shares/{id}/end") suspend fun end(@Header("Authorization") auth:String,@Path("id") id:String):Response<LiveShare>
 @PUT("v1/notifications/devices") suspend fun register(@Header("Authorization") auth:String,@Body body:PushDeviceRequest):Response<Unit>
 @DELETE("v1/notifications/devices/{token}") suspend fun unregister(@Header("Authorization") auth:String,@Path("token") token:String):Response<Unit>
 @GET("v1/social/notifications") suspend fun inbox(@Header("Authorization") auth:String):Response<InboxResponse>
 @POST("v1/social/notifications/read-all") suspend fun readAll(@Header("Authorization") auth:String):Response<Unit>
 @POST("v1/live/group-runs") suspend fun createGroupRun(@Header("Authorization") auth:String,@Body body:CreateGroupRunRequest):Response<GroupRun>
 @POST("v1/live/group-runs/join") suspend fun joinGroupRun(@Header("Authorization") auth:String,@Body body:JoinGroupRunRequest):Response<GroupRun>
 @GET("v1/live/group-runs/{id}") suspend fun groupRun(@Header("Authorization") auth:String,@Path("id") id:String):Response<GroupRun>
 @PATCH("v1/live/group-runs/{id}/participants/me/location") suspend fun updateGroupLocation(@Header("Authorization") auth:String,@Path("id") id:String,@Body body:GroupLocationUpdate):Response<GroupRun>
 @POST("v1/live/group-runs/{id}/participants/me/leave") suspend fun leaveGroupRun(@Header("Authorization") auth:String,@Path("id") id:String):Response<GroupRun>
 @POST("v1/live/group-runs/{id}/participants/me/finish") suspend fun finishGroupRun(@Header("Authorization") auth:String,@Path("id") id:String):Response<GroupRun>
}
fun createSafetyApi(baseUrl:String,client:OkHttpClient):SafetyApi=Retrofit.Builder().baseUrl(if(baseUrl.endsWith('/'))baseUrl else "$baseUrl/").client(client).addConverterFactory(PlainstrideJson.asConverterFactory("application/json".toMediaType())).build().create(SafetyApi::class.java)

sealed interface NotificationDestination { data object Connections:NotificationDestination; data object Inbox:NotificationDestination; data class Activity(val id:String):NotificationDestination; data class Post(val id:String):NotificationDestination; data class Event(val id:String):NotificationDestination; data class Invitation(val id:String):NotificationDestination; data class Circle(val id:String):NotificationDestination; data class Group(val id:String):NotificationDestination; data class Live(val id:String):NotificationDestination }
fun routeNotification(type:String,objectId:String):NotificationDestination=when(type){"connectionRequest","connectionAccepted"->NotificationDestination.Connections;"activity"->NotificationDestination.Activity(objectId);"cheer","comment"->NotificationDestination.Post(objectId);"runInvitation","circleInvitation"->NotificationDestination.Invitation(objectId);"invitationAccepted","activityEventJoined"->NotificationDestination.Event(objectId);"circleInvitationAccepted","circleCheer","circleWeeklyGoalCompleted","circleOwnershipTransferred"->NotificationDestination.Circle(objectId);"groupRunInvitation","groupRunStarted","groupRunUpdated"->NotificationDestination.Group(objectId);"liveShare","liveShareStarted","liveShareUpdated"->NotificationDestination.Live(objectId);else->NotificationDestination.Inbox}
