package com.plainstride.outbound.feature.safety

import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import android.os.SystemClock
import android.content.Context
import android.util.Log
import java.time.Duration
import java.time.Instant
import dagger.hilt.android.qualifiers.ApplicationContext
import com.plainstride.outbound.core.network.PlainstrideJson
import com.plainstride.outbound.core.network.*
import com.plainstride.outbound.core.analytics.*

@Singleton
class LiveShareCoordinator @Inject constructor(
    private val api: SafetyApi,
    private val tokens: AccessTokenProvider,
    private val analytics: ProductAnalytics,
    @ApplicationContext context: Context,
) {
    private val preferences = context.getSharedPreferences("live_share_state", Context.MODE_PRIVATE)
    private val realtimeScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val lock = Mutex()
    private val mutableActive = MutableStateFlow(preferences.getString(ACTIVE, null)?.let {
        runCatching { PlainstrideJson.decodeFromString<LiveShare>(it) }.getOrNull()
    })
    val active = mutableActive.asStateFlow()
    private val mutableGroup = MutableStateFlow(preferences.getString(GROUP, null)?.let {
        runCatching { PlainstrideJson.decodeFromString<GroupRun>(it) }.getOrNull()
    })
    val group = mutableGroup.asStateFlow()
    private val mutableArmed = MutableStateFlow(preferences.getString(ARMED, null)?.let {
        runCatching { PlainstrideJson.decodeFromString<CreateLiveShareRequest>(it) }.getOrNull()
    })
    private val mutableSelectedRecipients = MutableStateFlow(mutableArmed.value?.recipientUserIds.orEmpty())
    val selectedRecipientIds = mutableSelectedRecipients.asStateFlow()
    private var armed: CreateLiveShareRequest? = mutableArmed.value
    private var lastSentAt = 0L
    private var lastSentRecordedAt: Instant? = null
    private var lastPoint: LiveLocation? = null
    private var lastShareCheckpointAt = 0L
    private var shareRealtime: AblySessionTransport? = null
    private var shareRealtimeId: String? = null
    private var followerRealtime: AblySessionTransport? = null
    private val mutableCheerSignals = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    val cheerSignals = mutableCheerSignals
    private var lastGroupSentAt = 0L
    private var lastGroupPoint: LiveLocation? = null
    private var groupRealtime: AblySessionTransport? = null
    private var groupRealtimeId: String? = null
    private var lastGroupCheckpointAt = 0L
    private val mutableGroupJoining = MutableStateFlow(false)
    val groupJoining = mutableGroupJoining.asStateFlow()
    init {
        mutableGroup.value?.takeIf { it.status == "active" }?.let { connectGroupRealtime(it.id) }
        mutableActive.value?.takeIf { it.status == "active" }?.let { connectShareRealtime(it.id) }
    }

 private fun saveArmed(request:CreateLiveShareRequest){armed=request;mutableArmed.value=request;preferences.edit().putString(ARMED,PlainstrideJson.encodeToString(request)).apply()}
 fun arm(request:CreateLiveShareRequest){mutableSelectedRecipients.value=request.recipientUserIds.distinct();saveArmed(request);analytics.record(AnalyticsEvent("live_share_armed"))}
 fun configureRecipients(ids:List<String>){
  val recipients=ids.distinct()
  mutableSelectedRecipients.value=recipients
  if(recipients.isEmpty()){
   armed=null;mutableArmed.value=null;preferences.edit().remove(ARMED).apply()
  }else {val request=CreateLiveShareRequest(recipientUserIds=recipients);armed=request;mutableArmed.value=request;preferences.edit().putString(ARMED,PlainstrideJson.encodeToString(request)).apply()}
  analytics.record(AnalyticsEvent("live_cheer_invitation_configured",mapOf(AnalyticsProperty.ParticipantCountBucket to when(recipients.size){0->"0";1->"1";in 2..3->"2_3";in 4..7->"4_7";else->"8_plus"})))
 }
 /** Applies the user's default trusted contacts for a new activity without recording a picker change. */
 fun applyDefaultRecipients(ids:List<String>){
  val recipients=ids.distinct()
  mutableSelectedRecipients.value=recipients
  if(recipients.isEmpty()){
   armed=null;mutableArmed.value=null;preferences.edit().remove(ARMED).apply()
  }else saveArmed(CreateLiveShareRequest(recipientUserIds=recipients))
 }
 suspend fun recordingStarted(activityId:String?=null):Result<LiveShare?>{if(mutableActive.value!=null)return Result.success(mutableActive.value);val request=armed?:return Result.success(null);armed=null;mutableArmed.value=null;preferences.edit().remove(ARMED).apply();return start(request.copy(activityId=activityId)).map{it}}
 suspend fun start(request:CreateLiveShareRequest):Result<LiveShare> = authenticated{apiCall{api.create(it,request)}}.onSuccess{lastShareCheckpointAt=0;lastPoint=null;lastSentAt=0;lastSentRecordedAt=null;saveActive(it)}.also{result->analytics.record(AnalyticsEvent("live_share_started",mapOf(AnalyticsProperty.Result to if(result.isSuccess)"success" else "failure")))}
 suspend fun update(point:LiveLocation):Result<LiveShare?> = lock.withLock {
  val share=mutableActive.value?:return Result.success(null)
  val now=SystemClock.elapsedRealtime()
  val recordedAt=runCatching{Instant.parse(point.recordedAt)}.getOrNull()
  val priorRecordedAt=lastSentRecordedAt
  val recordedAtDeltaMs=if(recordedAt!=null&&priorRecordedAt!=null)runCatching{Duration.between(priorRecordedAt,recordedAt).toMillis()}.getOrNull()else null
  val tooSoon=recordedAtDeltaMs?.let{it<1_000L}?: (lastSentAt!=0L&&now-lastSentAt<1_000L)
  if(point.recordedAt==lastPoint?.recordedAt||tooSoon)return Result.success(share)
  shareRealtime?.publishLocation(mapOf("recordedAt" to point.recordedAt,"latitude" to point.latitude,"longitude" to point.longitude,"altitudeM" to point.altitudeM,"accuracyM" to point.accuracyM,"elapsedSeconds" to point.elapsedSeconds,"distanceM" to point.distanceM,"currentPaceSecsPerKm" to point.currentPaceSecsPerKm,"heartRate" to point.heartRate))
  lastPoint=point
  lastSentAt=now
  if(recordedAt!=null)lastSentRecordedAt=recordedAt
  if(lastShareCheckpointAt==0L||now-lastShareCheckpointAt>=60_000){authenticated{apiCall{api.update(it,share.id,point)}}.onSuccess{mutableActive.value=it;lastShareCheckpointAt=now}}
  Result.success(share)
 }
 suspend fun recordingEnded()=end()
 suspend fun end():Result<Unit>{val share=mutableActive.value?:return Result.success(Unit);return authenticated{apiCall{api.end(it,share.id)}}.map{clear();Unit}.also{result->analytics.record(AnalyticsEvent("live_share_ended",mapOf(AnalyticsProperty.Result to if(result.isSuccess)"success" else "failure")))}}
 fun clear(){shareRealtime?.close();shareRealtime=null;shareRealtimeId=null;followerRealtime?.close();followerRealtime=null;armed=null;mutableArmed.value=null;mutableActive.value=null;lastPoint=null;lastShareCheckpointAt=0;lastSentAt=0;lastSentRecordedAt=null;preferences.edit().clear().apply()}
 suspend fun registerToken(token:String,bundle:String,locale:String)=authenticated{apiCall{api.register(it,PushDeviceRequest(token,appBundle=bundle,locale=locale))}}.map{Unit}
 suspend fun unregisterToken(token:String)=authenticated{apiCall{api.unregister(it,token)}}.map{Unit}
 suspend fun inbox()=authenticated{apiCall{api.inbox(it)}}
 suspend fun markInboxRead()=authenticated{apiCall{api.readAll(it)}}.map{Unit}
 suspend fun createGroupRun(request:CreateGroupRunRequest)=authenticated{apiCall{api.createGroupRun(it,request)}}.onSuccess(::saveGroup)
 suspend fun joinGroupRun(invite:String)=authenticated{apiCall{api.joinGroupRun(it,JoinGroupRunRequest(invite.trim()))}}.onSuccess(::saveGroup)
 suspend fun groupRun(id:String)=authenticated{apiCall{api.groupRun(it,id)}}.onSuccess(::saveGroup)
 suspend fun refreshGroup(id:String)=groupRun(id)
 suspend fun joinActivityGroupRun(activityEventId:String):Result<GroupRun>{
  if(hasDifferentActiveGroup(activityEventId))return Result.failure(IllegalStateException("another_group_active"))
  mutableGroupJoining.value=true
  return try{authenticated{apiCall{api.joinActivityGroupRun(it,activityEventId)}}.onSuccess(::saveGroup)}finally{mutableGroupJoining.value=false}
 }
 fun isSharingEvent(activityEventId:String):Boolean=mutableGroup.value?.let{run->run.status=="active"&&run.activityEventId==activityEventId&&run.participants.any{it.userId==run.currentUserId&&it.status in setOf("active","stale")}}==true
 fun hasDifferentActiveGroup(activityEventId:String):Boolean=mutableGroup.value?.let{run->run.status=="active"&&run.activityEventId!=activityEventId&&run.participants.any{it.userId==run.currentUserId&&it.status in setOf("active","stale")}}==true
 suspend fun finishRecordingGroupRun(activityEventId:String?){
  val run=mutableGroup.value?:return
  if(activityEventId==null||run.activityEventId!=activityEventId)return
  if(run.participants.none{it.userId==run.currentUserId&&it.status in setOf("active","stale")}){clearGroup();return}
  leaveGroupRun(run.id,true)
 }
 suspend fun liveShare(id:String)=authenticated{apiCall{api.liveShare(it,id)}}.onSuccess(::saveActive)
 suspend fun invitedShares()=authenticated{apiCall{api.invitedShares(it)}}.map{it.sessions}
 suspend fun invitedShare(id:String)=authenticated{apiCall{api.invitedShare(it,id)}}
 suspend fun sendVoiceCheer(id:String,audioBase64:String,durationMs:Int)=authenticated{apiCall{api.sendVoiceCheer(it,id,VoiceCheerRequest(audioBase64=audioBase64,durationMs=durationMs.coerceIn(250,15_000)))}}.also{result->analytics.record(AnalyticsEvent("live_voice_cheer_sent",mapOf(AnalyticsProperty.Result to if(result.isSuccess)"success" else "failure")))}
 suspend fun pendingVoiceCheer():Result<VoiceCheer?> {
  val share=mutableActive.value?:return Result.success(null)
  return authenticated { apiCall { api.voiceCheers(it,share.id) } }.map { it.cheers.firstOrNull() }
 }
 suspend fun markVoiceCheerPlayed(cheer:VoiceCheer):Result<VoiceCheerReceipt> {
  val share=mutableActive.value?:return Result.failure(IllegalStateException("share_ended"))
  return authenticated { apiCall { api.markVoiceCheerPlayed(it,share.id,cheer.id) } }
 }
 suspend fun acknowledgeVoiceCheer(shareId:String,cheerId:String)=authenticated { apiCall { api.acknowledgeVoiceCheer(it,shareId,cheerId) } }
 suspend fun updateGroupRun(id:String,point:GroupLocationUpdate)=authenticated{apiCall{api.updateGroupLocation(it,id,point)}}.onSuccess(::saveGroup)
 suspend fun leaveGroupRun(finished:Boolean):Result<Unit>{
  val run=mutableGroup.value?:return Result.success(Unit)
  return leaveGroupRun(run.id,finished).map{Unit}
 }
 suspend fun leaveGroupRun(id:String,finished:Boolean)=authenticated{auth->apiCall{if(finished)api.finishGroupRun(auth,id)else api.leaveGroupRun(auth,id)}}.onSuccess{clearGroup()}
 suspend fun updateRecording(point:LiveLocation,paceSecondsPerKilometer:Double?,activityEventId:String?=null){
  update(point.copy(currentPaceSecsPerKm=paceSecondsPerKilometer))
  val run=mutableGroup.value?:return
  if(activityEventId==null||run.activityEventId!=activityEventId)return
  val now=SystemClock.elapsedRealtime()
  val current=mutableGroup.value?:run
  if(current.participants.none{it.userId==current.currentUserId&&it.status in setOf("active","stale")})return
  val prior=lastGroupPoint
  if(now-lastGroupSentAt<10_000&&prior!=null&&haversine(prior,point)<25)return
  groupRealtime?.publishLocation(mapOf("recordedAt" to point.recordedAt,"latitude" to point.latitude,"longitude" to point.longitude,"altitudeM" to point.altitudeM,"accuracyM" to point.accuracyM,"elapsedSeconds" to point.elapsedSeconds,"distanceM" to point.distanceM,"paceSecondsPerKM" to paceSecondsPerKilometer))
  if(lastGroupCheckpointAt==0L||now-lastGroupCheckpointAt>=60_000){
   updateGroupRun(current.id,GroupLocationUpdate(point.recordedAt,point.latitude,point.longitude,point.altitudeM,point.accuracyM,point.elapsedSeconds,point.distanceM,paceSecondsPerKilometer)).onSuccess{lastGroupCheckpointAt=now}
  }
  lastGroupSentAt=now;lastGroupPoint=point
 }
 private fun saveGroup(value:GroupRun){
  mutableGroup.value=value
  preferences.edit().putString(GROUP,PlainstrideJson.encodeToString(value)).apply()
  if(value.status=="active")connectGroupRealtime(value.id)
  if(value.participants.none{it.userId==value.currentUserId&&it.status in setOf("active","stale")}){
   groupRealtime?.close();groupRealtime=null;groupRealtimeId=null
   lastGroupPoint=null
   lastGroupSentAt=0
  }
 }
 private fun saveActive(value:LiveShare){mutableActive.value=value;preferences.edit().putString(ACTIVE,PlainstrideJson.encodeToString(value)).apply();connectShareRealtime(value.id)}
 private fun connectShareRealtime(id:String){if(shareRealtimeId==id)return;shareRealtime?.close();shareRealtimeId=id;shareRealtime=AblySessionTransport.connect(channelName="plainstride:live_share:$id",tokenProvider={issueRealtimeToken("live_share",id)},onMessage={name,_,_->if(name=="cheer.available")mutableCheerSignals.tryEmit(Unit)})}
 fun watchFollower(id:String,onEvent:(String,Any?)->Unit,onChannelAttached:()->Unit={}) {
  if(BuildConfig.DEBUG) Log.d(REALTIME_TAG,"follower_socket_start_requested")
  followerRealtime?.close()
  followerRealtime=runCatching {
   AblySessionTransport.connect(
    channelName="plainstride:live_share:$id",
    tokenProvider={issueRealtimeToken("live_share",id)},
    onMessage={name,_,data->onEvent(name,data)},
    onChannelAttached=onChannelAttached,
   )
  }.onFailure { if(BuildConfig.DEBUG) Log.e(REALTIME_TAG,"follower_socket_start_failed error=${it.javaClass.simpleName}") }.getOrNull()
  if(BuildConfig.DEBUG) Log.d(REALTIME_TAG,"follower_socket_transport_created=${followerRealtime!=null}")
 }
 fun stopWatchingFollower(){followerRealtime?.close();followerRealtime=null}
 private fun clearGroup(){groupRealtime?.close();groupRealtime=null;groupRealtimeId=null;mutableGroup.value=null;lastGroupPoint=null;lastGroupSentAt=0;preferences.edit().remove(GROUP).apply()}
 private fun connectGroupRealtime(id:String){
  if(groupRealtimeId==id)return
  groupRealtime?.close();groupRealtimeId=id
  lastGroupCheckpointAt=0;lastGroupSentAt=0;lastGroupPoint=null
  groupRealtime=AblySessionTransport.connect(channelName="plainstride:group_run:$id",tokenProvider={issueRealtimeToken("group_run",id)},onMessage={name,clientId,data->
   if(name=="location"&&clientId!=null)applyGroupLocation(clientId,data)
   else if(name=="participant.changed")realtimeScope.launch{groupRun(id)}
  })
 }
 private suspend fun issueRealtimeToken(kind:String,id:String):RealtimeToken = authenticated{auth->apiCall{api.realtimeToken(auth,RealtimeTokenRequest(kind,id))}}.getOrThrow()
 private fun applyGroupLocation(senderId:String,value:Any?){
  val map=value as? Map<*,*>?:return
  val old=mutableGroup.value?:return
  val lat=(map["latitude"] as? Number)?.toDouble()?:return;val lon=(map["longitude"] as? Number)?.toDouble()?:return
  val timestamp=map["recordedAt"] as? String?:return
  mutableGroup.value=old.copy(participants=old.participants.map{p->if(p.userId!=senderId)p else p.copy(status="active",lastLocationAt=timestamp,lastLocation=GroupRunPoint(lat,lon,(map["altitudeM"] as? Number)?.toDouble(),(map["accuracyM"] as? Number)?.toDouble()),lastActivitySnapshot=GroupRunProgress((map["elapsedSeconds"] as? Number)?.toInt()?:0,(map["distanceM"] as? Number)?.toDouble()?:0.0,(map["paceSecondsPerKM"] as? Number)?.toDouble()))})
 }
 private suspend fun<T:Any>authenticated(call:suspend(String)->ApiResult<T>):Result<T>{val token=tokens.validAccessToken()?:return Result.failure(IllegalStateException("signed_out"));return when(val value=call("Bearer $token")){is ApiResult.Success->Result.success(value.value);is ApiResult.Failure->Result.failure(IllegalStateException(value.error.code.name))}}
 private fun haversine(a:LiveLocation,b:LiveLocation):Double{val p1=Math.toRadians(a.latitude);val p2=Math.toRadians(b.latitude);val dp=p2-p1;val dl=Math.toRadians(b.longitude-a.longitude);val h=kotlin.math.sin(dp/2)*kotlin.math.sin(dp/2)+kotlin.math.cos(p1)*kotlin.math.cos(p2)*kotlin.math.sin(dl/2)*kotlin.math.sin(dl/2);return 6371000*2*kotlin.math.atan2(kotlin.math.sqrt(h),kotlin.math.sqrt(1-h))}
 private companion object{const val ACTIVE="active";const val ARMED="armed";const val GROUP="group";const val REALTIME_TAG="PlainstrideRealtime"}
}
