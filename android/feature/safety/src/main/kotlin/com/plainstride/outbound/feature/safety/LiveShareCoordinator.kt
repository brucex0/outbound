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
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import android.os.SystemClock
import android.content.Context
import android.util.Log
import java.time.Duration
import java.time.Instant
import dagger.hilt.android.qualifiers.ApplicationContext
import com.plainstride.outbound.core.network.PlainstrideJson
import com.plainstride.outbound.core.network.*
import com.plainstride.outbound.core.analytics.*

/** A complete accepted-connection roster fetched successfully for this signed-in account. */
data class CheerRecipientRoster(val accountId: String, val eligibleRecipientIds: Set<String>)

@Singleton
class LiveShareCoordinator @Inject constructor(
    private val api: SafetyApi,
    private val tokens: AccessTokenProvider,
    private val analytics: ProductAnalytics,
    @ApplicationContext context: Context,
) {
    // Follower location snapshots stay in memory and are cleared with the account.
    private val followerSnapshots = java.util.concurrent.ConcurrentHashMap<String, InvitedLiveShare>()
    private val applicationContext = context.applicationContext
    private val groupSnapshots = java.util.concurrent.ConcurrentHashMap<String, GroupRun>()
    fun cachedGroupRun(id: String) = mutableGroup.value?.takeIf { it.id == id } ?: groupSnapshots[id]
    suspend fun groupRunDetail(id: String) = authenticated { auth -> apiCall { api.groupRun(auth, id) } }.onSuccess {
        if (groupSnapshots.size >= 32) groupSnapshots.clear()
        groupSnapshots[id] = it
        // Viewing another session must not replace the user's active participation.
        if (mutableGroup.value?.id == id) saveGroup(it)
    }.onFailure { if ((it as? SafetyRequestException)?.status in setOf(403, 404)) groupSnapshots.remove(id) }
    fun cachedInvitedShare(id: String) = followerSnapshots[id]
    private val preferences = context.getSharedPreferences("live_share_state", Context.MODE_PRIVATE)
    private val realtimeScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val lock = Mutex()
    @Volatile private var activeAccountId: String? = null
    private var accountActivated = false
    private val mutableActive = MutableStateFlow<LiveShare?>(null)
    val active = mutableActive.asStateFlow()
    private val mutableGroup = MutableStateFlow<GroupRun?>(null)
    val group = mutableGroup.asStateFlow()
    private val mutableArmed = MutableStateFlow<CreateLiveShareRequest?>(null)
    private val mutableSelectedRecipients = MutableStateFlow<List<String>>(emptyList())
    val selectedRecipientIds = mutableSelectedRecipients.asStateFlow()
    private var armed: CreateLiveShareRequest? = null
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
    private var groupRosterTask: Job? = null
    private val groupRosterLock = Mutex()
    private var lastGroupCheckpointAt = 0L
    private val groupConsentRevision = java.util.concurrent.atomic.AtomicLong()
    private val mutableGroupJoining = MutableStateFlow(false)
    val groupJoining = mutableGroupJoining.asStateFlow()
    /** No saved consent or realtime connection is exposed before its owner signs in. */
    @Synchronized fun activateAccount(accountId: String?) {
        if (accountActivated && activeAccountId == accountId) return
        val restore = !accountActivated && accountId != null && preferences.getString(OWNER, null) == accountId
        val savedActive = if (restore) preferences.getString(ACTIVE, null) else null
        val savedGroup = if (restore) preferences.getString(GROUP, null) else null
        val savedArmed = if (restore) preferences.getString(ARMED, null) else null
        val explicit = restore && preferences.getBoolean(EXPLICIT_RECIPIENTS, false)
        activeAccountId = accountId
        accountActivated = true
        groupConsentRevision.incrementAndGet()
        clear()
        clearGroup()
        mutableGroupJoining.value = false
        lastGroupCheckpointAt = 0L
        if (accountId == null) return
        preferences.edit().putString(OWNER, accountId).putBoolean(EXPLICIT_RECIPIENTS, explicit).apply()
        savedArmed?.let { raw -> decodeSaved<CreateLiveShareRequest>(raw)?.let(::saveArmed) }
        mutableSelectedRecipients.value = armed?.recipientUserIds.orEmpty()
        savedGroup?.let { raw -> decodeSaved<GroupRun>(raw)?.let { saveGroup(it, allowConsent = true) } }
        savedActive?.let { raw -> decodeSaved<LiveShare>(raw)?.takeIf { it.status == "active" }?.let(::saveActive) }
    }
    private inline fun <reified T> decodeSaved(raw: String): T? = try {
        PlainstrideJson.decodeFromString<T>(raw)
    } catch (error: Exception) {
        Log.w(REALTIME_TAG, "sharing_state_decode failed type=${error.javaClass.simpleName}")
        null
    }

 private fun saveArmed(request:CreateLiveShareRequest){armed=request;mutableArmed.value=request;preferences.edit().putString(ARMED,PlainstrideJson.encodeToString(request)).apply()}
 fun arm(accountId:String,request:CreateLiveShareRequest){if(activeAccountId!=accountId)return;preferences.edit().putBoolean(EXPLICIT_RECIPIENTS,true).apply();mutableSelectedRecipients.value=request.recipientUserIds.distinct();saveArmed(request);analytics.record(AnalyticsEvent("live_share_armed"))}
 private var recordingSessionId: String? = null
 private val recipientChangeLock = kotlinx.coroutines.sync.Mutex()
 suspend fun configureLiveRecipients(accountId: String, ids: List<String>): Result<Unit> = recipientChangeLock.withLock {
  if(activeAccountId!=accountId)return@withLock Result.failure(IllegalStateException("account_changed"))
  if (ids.toSet() == mutableSelectedRecipients.value.toSet() && mutableActive.value != null) return@withLock Result.success(Unit)
  val sessionId = recordingSessionId
  if (sessionId != null && mutableActive.value != null) {
   val ended = end(preserveGroup = true)
   if (ended.isFailure) return@withLock ended
  }
  if (sessionId != recordingSessionId) return@withLock Result.failure(IllegalStateException("recording_ended"))
  configureRecipients(ids)
  // A live picker confirmation is explicit consent for its displayed accepted recipients.
  if (sessionId != null && ids.isNotEmpty()) startArmedRecording(sessionId, ids.toSet()).map { Unit } else Result.success(Unit)
 }
 private fun configureRecipients(ids:List<String>){
  preferences.edit().putBoolean(EXPLICIT_RECIPIENTS,true).apply()
  val recipients=ids.distinct()
  mutableSelectedRecipients.value=recipients
  if(recipients.isEmpty()){
   armed=null;mutableArmed.value=null;preferences.edit().remove(ARMED).apply()
  }else {val request=CreateLiveShareRequest(recipientUserIds=recipients);armed=request;mutableArmed.value=request;preferences.edit().putString(ARMED,PlainstrideJson.encodeToString(request)).apply()}
  analytics.record(AnalyticsEvent("live_cheer_invitation_configured",mapOf(AnalyticsProperty.ParticipantCountBucket to when(recipients.size){0->"0";1->"1";in 2..3->"2_3";in 4..7->"4_7";else->"8_plus"})))
 }
 /** Applies the user's default trusted contacts for a new activity without recording a picker change. */
 fun applyDefaultRecipients(accountId:String,ids:List<String>){
  if(activeAccountId!=accountId)return
  // Done, including an empty choice, overrides the default for this activity.
  if(preferences.getBoolean(EXPLICIT_RECIPIENTS,false) || recordingSessionId!=null || mutableActive.value!=null)return
  val recipients=ids.distinct()
  mutableSelectedRecipients.value=recipients
  if(recipients.isEmpty()){
   armed=null;mutableArmed.value=null;preferences.edit().remove(ARMED).apply()
  }else saveArmed(CreateLiveShareRequest(recipientUserIds=recipients))
 }
 suspend fun recordingStarted(activityId:String?, accountId:String?, roster:CheerRecipientRoster?):Result<LiveShare?> = recipientChangeLock.withLock {
  if(accountId==null || activeAccountId!=accountId)return@withLock Result.success(null)
  recordingSessionId=activityId
  if(mutableActive.value!=null)return@withLock Result.success(mutableActive.value)
  if(armed==null)return@withLock Result.success(null)
  if(roster==null || roster.accountId!=accountId){
   // Loading/offline failure is not an empty roster. Preserve consent and retry
   // when the recording effect receives this account's first authoritative roster.
   analytics.record(AnalyticsEvent("live_cheer_start_eligibility",mapOf(AnalyticsProperty.Result to "deferred")))
   return@withLock Result.success(null)
  }
  startArmedRecording(activityId,roster.eligibleRecipientIds)
 }
 private suspend fun startArmedRecording(activityId:String?, eligibleRecipientIds:Set<String>):Result<LiveShare?> {
  val request=armed?:return Result.success(null)
  val recipients=request.recipientUserIds.distinct().filter { it in eligibleRecipientIds }
  mutableSelectedRecipients.value=recipients
  analytics.record(AnalyticsEvent("live_cheer_start_eligibility",mapOf(AnalyticsProperty.Result to if(recipients.isEmpty())"empty" else "eligible")))
  if(recipients.isEmpty()){
   armed=null;mutableArmed.value=null;preferences.edit().remove(ARMED).apply()
   return Result.success(null)
  }
  val eligibleRequest=request.copy(recipientUserIds=recipients)
  saveArmed(eligibleRequest)
  return start(eligibleRequest.copy(activityId=activityId)).onSuccess {
   armed=null;mutableArmed.value=null;preferences.edit().remove(ARMED).apply()
  }.onFailure {
   Log.w(REALTIME_TAG,"live_share_start failed type=${it.javaClass.simpleName} status=${(it as? SafetyRequestException)?.status} category=${(it as? SafetyRequestException)?.category}")
  }.map{it}
 }
 suspend fun start(request:CreateLiveShareRequest):Result<LiveShare> = authenticated{apiCall{api.create(it,request)}}.onSuccess{lastShareCheckpointAt=0;lastPoint=null;lastSentAt=0;lastSentRecordedAt=null;saveActive(it)}.also{result->analytics.record(AnalyticsEvent("live_share_started",mapOf(AnalyticsProperty.Result to if(result.isSuccess)"success" else "failure")))}
 suspend fun update(point:LiveLocation):Result<LiveShare?> = lock.withLock {
  val share=mutableActive.value?:return Result.success(null)
  if(!isFreshMeasurement(point))return Result.success(share)
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
  if(lastShareCheckpointAt==0L||now-lastShareCheckpointAt>=60_000){
   lastShareCheckpointAt=now
   // Recovery writes must not delay group publication or be cancelled by the next GPS effect.
   realtimeScope.launch {
    authenticated{apiCall{api.update(it,share.id,point)}}.onSuccess{response->
     if(mutableActive.value?.id==share.id)mutableActive.value=response
    }.onFailure{
     if(mutableActive.value?.id==share.id)lastShareCheckpointAt=0L
     Log.w(REALTIME_TAG,"live_share_checkpoint failed type=${it.javaClass.simpleName} status=${(it as? SafetyRequestException)?.status}")
    }
   }
  }
  Result.success(share)
 }
 suspend fun recordingEnded(accountId:String?):Result<Unit>{
  if(accountId==null || activeAccountId!=accountId)return Result.success(Unit)
  recordingSessionId=null
  return end().onSuccess {
   // The next activity may use its default; no pending invitation survives Finish.
   armed=null;mutableArmed.value=null;mutableSelectedRecipients.value=emptyList()
   preferences.edit().remove(ARMED).remove(EXPLICIT_RECIPIENTS).apply()
  }
 }
 suspend fun end(preserveGroup: Boolean = false):Result<Unit>{val share=mutableActive.value?:return Result.success(Unit);return authenticated{apiCall{api.end(it,share.id)}}.map{val currentRecording=recordingSessionId;if (preserveGroup) clearCurrentShare() else clear();recordingSessionId=currentRecording;Unit}.also{result->analytics.record(AnalyticsEvent("live_share_ended",mapOf(AnalyticsProperty.Result to if(result.isSuccess)"success" else "failure")))}}
 private fun clearCurrentShare() {
  shareRealtime?.close(); shareRealtime=null; shareRealtimeId=null
  armed=null; mutableArmed.value=null; mutableActive.value=null
  lastPoint=null; lastShareCheckpointAt=0; lastSentAt=0; lastSentRecordedAt=null
  preferences.edit().remove(ACTIVE).remove(ARMED).apply()
 }
 fun clear(){recordingSessionId=null;mutableSelectedRecipients.value=emptyList();groupSnapshots.clear();followerSnapshots.clear();shareRealtime?.close();shareRealtime=null;shareRealtimeId=null;followerRealtime?.close();followerRealtime=null;armed=null;mutableArmed.value=null;mutableActive.value=null;lastPoint=null;lastShareCheckpointAt=0;lastSentAt=0;lastSentRecordedAt=null;preferences.edit().clear().putString(OWNER,activeAccountId).apply()}
 suspend fun registerToken(token:String,bundle:String,locale:String)=authenticated{apiCall{api.register(it,PushDeviceRequest(token,appBundle=bundle,locale=locale))}}.map{Unit}
 suspend fun unregisterToken(token:String)=authenticated{apiCall{api.unregister(it,token)}}.map{Unit}
 suspend fun inbox()=authenticated{apiCall{api.inbox(it)}}
 suspend fun markInboxRead()=authenticated{apiCall{api.readAll(it)}}.map{Unit}
 suspend fun createGroupRun(request:CreateGroupRunRequest)=authenticated{apiCall{api.createGroupRun(it,request)}}.onSuccess { saveGroup(it,allowConsent=true) }
 suspend fun joinGroupRun(invite:String)=authenticated{apiCall{api.joinGroupRun(it,JoinGroupRunRequest(invite.trim()))}}.onSuccess { saveGroup(it,allowConsent=true) }
 suspend fun groupRun(id:String):Result<GroupRun> {
  val revision=groupConsentRevision.get()
  return authenticated{apiCall{api.groupRun(it,id)}}.onSuccess{if(groupConsentRevision.get()==revision)saveGroup(it)}
 }
 suspend fun refreshGroup(id:String)=groupRun(id)
 suspend fun joinActivityGroupRun(activityEventId:String):Result<GroupRun>{
  val revision=groupConsentRevision.incrementAndGet()
  if(hasDifferentActiveGroup(activityEventId))return Result.failure(IllegalStateException("another_group_active"))
  mutableGroupJoining.value=true
  analytics.record(AnalyticsEvent("group_activity_location_sharing_changed",mapOf(AnalyticsProperty.SelectionType to "on",AnalyticsProperty.Result to "requested")))
  analytics.record(AnalyticsEvent("group_run_join_attempted"))
  return try {
   authenticated { auth ->
    val result = apiCall { api.joinActivityGroupRun(auth, activityEventId) }
    currentCoroutineContext().ensureActive()
    if (result is ApiResult.Failure) Log.w(REALTIME_TAG, "event_live_map_join status=${result.error.httpStatus} category=${result.error.code}")
    result
   }.onSuccess { run ->
    if(groupConsentRevision.get()!=revision) {
     authenticated{auth->apiCall{api.leaveGroupRun(auth,run.id)}}.onFailure{Log.w(REALTIME_TAG,"cancelled_event_join_leave failed type=${it.javaClass.simpleName}")}
     return@onSuccess
    }
    saveGroup(run,allowConsent=true)
    val count = when(run.participants.size) { 0 -> "0"; 1 -> "1"; in 2..3 -> "2_3"; in 4..7 -> "4_7"; else -> "8_plus" }
    analytics.record(AnalyticsEvent("group_run_joined", mapOf(AnalyticsProperty.ParticipantCountBucket to count)))
   }
  } finally { mutableGroupJoining.value=false }
 }
 fun isSharingEvent(activityEventId:String):Boolean=mutableGroup.value?.let{run->run.status=="active"&&run.activityEventId==activityEventId&&run.participants.any{it.userId==run.currentUserId&&it.status in setOf("active","stale")}}==true
 fun hasDifferentActiveGroup(activityEventId:String):Boolean=mutableGroup.value?.let{run->run.status=="active"&&run.activityEventId!=activityEventId&&run.participants.any{it.userId==run.currentUserId&&it.status in setOf("active","stale")}}==true
 suspend fun finishRecordingGroupRun(accountId:String?){
  if(accountId==null || activeAccountId!=accountId)return
  groupConsentRevision.incrementAndGet()
  val run=mutableGroup.value?:return
  run.activityEventId?.let { event ->
   val prefs=applicationContext.getSharedPreferences("group_recording_${accountId}",Context.MODE_PRIVATE)
   prefs.edit().putStringSet("completed_events",prefs.getStringSet("completed_events",emptySet()).orEmpty()+event).remove("selected_event").apply()
  }
  if(run.participants.none{it.userId==run.currentUserId&&it.status in setOf("active","stale")})return
  leaveGroupRun(run.id,true)
 }
 suspend fun liveShare(id:String)=authenticated{apiCall{api.liveShare(it,id)}}.onSuccess(::saveActive)
 suspend fun invitedShares()=authenticated{apiCall{api.invitedShares(it)}}.map{it.sessions}
 suspend fun invitedShare(id:String)=authenticated{apiCall{api.invitedShare(it,id)}}.onSuccess {
  if(followerSnapshots.size>=32) followerSnapshots.clear()
  followerSnapshots[id]=it
 }.onFailure { if((it as? SafetyRequestException)?.status in setOf(403,404)) followerSnapshots.remove(id) }
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
 suspend fun updateGroupRun(id:String,point:GroupLocationUpdate):Result<GroupRun> {
  val revision=groupConsentRevision.get()
  return authenticated{apiCall{api.updateGroupLocation(it,id,point)}}.onSuccess{response->
  if(groupConsentRevision.get()==revision && mutableGroup.value?.let{run->run.id==id&&run.participants.any{it.userId==run.currentUserId&&it.status in setOf("active","stale")}}==true)saveGroup(response)
  }
 }
 suspend fun leaveGroupRun(finished:Boolean):Result<Unit>{
  val run=mutableGroup.value?:return Result.success(Unit)
  return leaveGroupRun(run.id,finished).map{Unit}
 }
 suspend fun leaveGroupRun(id:String,finished:Boolean):Result<GroupRun> {
  groupConsentRevision.incrementAndGet()
  mutableGroupJoining.value=true
  try {
  val run=mutableGroup.value?.takeIf{it.id==id}
  if(run!=null) {
   run.activityEventId?.let { eventId ->
    applicationContext.getSharedPreferences("group_recording_${run.currentUserId}", Context.MODE_PRIVATE)
     .edit().putBoolean("share_default_applied_${eventId}", true).apply()
   }
   saveGroup(run.copy(participants=run.participants.map{if(it.userId==run.currentUserId)it.copy(status=if(finished)"finished" else "left",lastLocationAt=null,lastLocation=null,lastActivitySnapshot=null)else it}))
  }
  val result=authenticated{auth->apiCall{if(finished)api.finishGroupRun(auth,id)else api.leaveGroupRun(auth,id)}}
  result.onFailure{Log.w(REALTIME_TAG,"event_sharing_leave failed type=${it.javaClass.simpleName}")}
  analytics.record(AnalyticsEvent("group_activity_location_sharing_changed",mapOf(AnalyticsProperty.SelectionType to "off",AnalyticsProperty.Result to if(result.isSuccess)"success" else "failure")))
  return result
  } finally { mutableGroupJoining.value=false }
 }
 suspend fun updateRecording(point:LiveLocation,paceSecondsPerKilometer:Double?,activityEventId:String?=null,isSimulated:Boolean=false){
  update(point.copy(currentPaceSecsPerKm=paceSecondsPerKilometer))
  val run=mutableGroup.value?:return
  if(run.activityEventId!=activityEventId)return
  val now=SystemClock.elapsedRealtime()
  val current=mutableGroup.value?:run
  if(current.participants.none{it.userId==current.currentUserId&&it.status in setOf("active","stale")})return
  if(!isFreshMeasurement(point))return
  val prior=lastGroupPoint
  val measuredAt=Instant.parse(point.recordedAt)
  if(prior!=null && (!measuredAt.isAfter(Instant.parse(prior.recordedAt)) || now-lastGroupSentAt<1_000))return
  if(prior==null)analytics.record(AnalyticsEvent("live_location_stream_started",mapOf(AnalyticsProperty.SourceType to "group_run",AnalyticsProperty.SelectionType to if(isSimulated)"one_second_simulated" else "one_second_gps")))
  groupRealtime?.publishLocation(mapOf("recordedAt" to point.recordedAt,"latitude" to point.latitude,"longitude" to point.longitude,"altitudeM" to point.altitudeM,"accuracyM" to point.accuracyM,"elapsedSeconds" to point.elapsedSeconds,"distanceM" to point.distanceM,"paceSecondsPerKM" to paceSecondsPerKilometer))
  lastGroupSentAt=now;lastGroupPoint=point
  if(lastGroupCheckpointAt==0L||now-lastGroupCheckpointAt>=60_000){
   lastGroupCheckpointAt=now
   realtimeScope.launch {
    updateGroupRun(current.id,GroupLocationUpdate(point.recordedAt,point.latitude,point.longitude,point.altitudeM,point.accuracyM,point.elapsedSeconds,point.distanceM,paceSecondsPerKilometer)).onFailure{
     if(mutableGroup.value?.id==current.id)lastGroupCheckpointAt=0L
     Log.w(REALTIME_TAG,"group_location_checkpoint failed type=${it.javaClass.simpleName} status=${(it as? SafetyRequestException)?.status}")
    }
   }
  }
 }
 private fun saveGroup(response:GroupRun,allowConsent:Boolean=false){
  val previous=mutableGroup.value?.takeIf{it.id==response.id}?.participants?.firstOrNull{it.userId==response.currentUserId}
  val currentRun=mutableGroup.value?.takeIf{it.id==response.id}
  val merged=response.copy(participants=response.participants.map { incoming ->
   val old=currentRun?.participants?.firstOrNull{it.userId==incoming.userId}
   if(incoming.status in setOf("active","stale") && old?.status in setOf("active","stale") && old?.lastLocationAt!=null &&
      (incoming.lastLocationAt==null || isOlderMeasurement(incoming.lastLocationAt,old.lastLocationAt))) incoming.copy(status=old.status,lastLocationAt=old.lastLocationAt,lastLocation=old.lastLocation,lastActivitySnapshot=old.lastActivitySnapshot) else incoming
  })
  val value=if(!allowConsent&&previous!=null&&previous.status !in setOf("active","stale"))merged.copy(participants=merged.participants.map{if(it.userId==response.currentUserId)previous else it})else merged
  mutableGroup.value=value
  preferences.edit().putString(GROUP,PlainstrideJson.encodeToString(value)).apply()
  if(value.status=="active"&&value.participants.any{it.userId==value.currentUserId&&it.status in setOf("active","stale")})connectGroupRealtime(value.id)
  if(value.status!="active" || value.participants.none{it.userId==value.currentUserId&&it.status in setOf("active","stale")}){
   groupRosterTask?.cancel();groupRosterTask=null
   groupRealtime?.close();groupRealtime=null;groupRealtimeId=null
   lastGroupPoint=null
   lastGroupSentAt=0
  }
 }
 private fun saveActive(value:LiveShare){mutableActive.value=value;preferences.edit().putString(ACTIVE,PlainstrideJson.encodeToString(value)).apply();connectShareRealtime(value.id)}
 private fun connectShareRealtime(id:String){if(shareRealtimeId==id)return;shareRealtime?.close();shareRealtimeId=id;shareRealtime=AblySessionTransport.connect(channelName="plainstride:live_share:$id",tokenProvider={issueRealtimeToken("live_share",id)},onMessage={name,_,_->if(name=="cheer.available")mutableCheerSignals.tryEmit(Unit)},onPublishResult={trackLocationPublishResult("live_share",it)})}
 private fun trackLocationPublishResult(source:String,succeeded:Boolean){
  analytics.record(AnalyticsEvent("live_location_publish_result",mapOf(AnalyticsProperty.SourceType to source,AnalyticsProperty.Result to if(succeeded)"success" else "failure")))
 }
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
 private fun clearGroup(){groupRosterTask?.cancel();groupRosterTask=null;groupRealtime?.close();groupRealtime=null;groupRealtimeId=null;mutableGroup.value=null;lastGroupPoint=null;lastGroupSentAt=0;preferences.edit().remove(GROUP).apply()}
 private fun connectGroupRealtime(id:String){
  if(groupRealtimeId==id)return
  groupRosterTask?.cancel()
  groupRealtime?.close();groupRealtimeId=id
  lastGroupCheckpointAt=0;lastGroupSentAt=0;lastGroupPoint=null
  groupRealtime=AblySessionTransport.connect(channelName="plainstride:group_run:$id",tokenProvider={issueRealtimeToken("group_run",id)},onMessage={name,clientId,data->
   if(mutableGroup.value?.let{it.id==id&&it.participants.any{p->p.userId==it.currentUserId&&p.status in setOf("active","stale")}}!=true)return@connect
   if(name=="location"&&clientId!=null) {
    if(mutableGroup.value?.participants?.any{it.userId==clientId&&it.status in setOf("active","stale")}==true)applyGroupLocation(clientId,data)
    else realtimeScope.launch { refreshGroupRoster(id); if(groupRealtimeId==id)applyGroupLocation(clientId,data) }
   } else if(name=="participant.changed")realtimeScope.launch{refreshGroupRoster(id)}
  },onChannelAttached={realtimeScope.launch{refreshGroupRoster(id)}},onPublishResult={trackLocationPublishResult("group_run",it)})
  // Recovery must continue while paused; no outgoing location/checkpoint is required.
  groupRosterTask=realtimeScope.launch {
   while(groupRealtimeId==id) { refreshGroupRoster(id); delay(15_000) }
  }
 }
 private suspend fun refreshGroupRoster(id:String) {
  if(!groupRosterLock.tryLock())return
  try {
   if(groupRealtimeId!=id)return
   val revision=groupConsentRevision.get()
   groupRun(id).onFailure { error ->
    if(groupRealtimeId!=id || groupConsentRevision.get()!=revision)return@onFailure
    val status=(error as? SafetyRequestException)?.status
    Log.w(REALTIME_TAG,"group_roster_refresh failed type=${error.javaClass.simpleName} status=$status")
    if(status in setOf(403,404,410))clearGroup()
   }
  } finally { groupRosterLock.unlock() }
 }
 private suspend fun issueRealtimeToken(kind:String,id:String):RealtimeToken = authenticated{auth->apiCall{api.realtimeToken(auth,RealtimeTokenRequest(kind,id))}}.getOrThrow()
 private fun applyGroupLocation(senderId:String,value:Any?){
  val map=value as? Map<*,*>?:return
  val old=mutableGroup.value?:return
  if(old.participants.none{it.userId==senderId&&it.status in setOf("active","stale")})return
  val lat=(map["latitude"] as? Number)?.toDouble()?:return;val lon=(map["longitude"] as? Number)?.toDouble()?:return
  val timestamp=map["recordedAt"] as? String?:return
  val measuredAt=runCatching{Instant.parse(timestamp)}.getOrNull()?:return
  if(!lat.isFinite()||!lon.isFinite()||lat !in -90.0..90.0||lon !in -180.0..180.0)return
  val previous=old.participants.firstOrNull{it.userId==senderId}?.lastLocationAt?.let{runCatching{Instant.parse(it)}.getOrNull()}
  if(previous!=null && !measuredAt.isAfter(previous))return
  mutableGroup.value=old.copy(participants=old.participants.map{p->if(p.userId!=senderId)p else p.copy(status="active",lastLocationAt=timestamp,lastLocation=GroupRunPoint(lat,lon,(map["altitudeM"] as? Number)?.toDouble(),(map["accuracyM"] as? Number)?.toDouble()),lastActivitySnapshot=GroupRunProgress((map["elapsedSeconds"] as? Number)?.toInt()?:0,(map["distanceM"] as? Number)?.toDouble()?:0.0,(map["paceSecondsPerKM"] as? Number)?.toDouble()))})
 }
 private suspend fun<T:Any>authenticated(call:suspend(String)->ApiResult<T>):Result<T>{
  val account=activeAccountId?:return Result.failure(IllegalStateException("signed_out"))
  val requestContext=tokens.captureAccount(account)?:return Result.failure(IllegalStateException("signed_out"))
  val token=tokens.validAccessToken(requestContext)?:return Result.failure(IllegalStateException("signed_out"))
  if(activeAccountId!=account || !tokens.isCurrent(requestContext))throw kotlinx.coroutines.CancellationException("safety_account_changed")
  val value=call("Bearer $token")
  if(activeAccountId!=account || !tokens.isCurrent(requestContext))throw kotlinx.coroutines.CancellationException("safety_account_changed")
  return when(value){is ApiResult.Success->Result.success(value.value);is ApiResult.Failure->Result.failure(SafetyRequestException(value.error.code.name,value.error.httpStatus))}
 }
 private fun isFreshMeasurement(point:LiveLocation):Boolean {
  val measuredAt=runCatching{Instant.parse(point.recordedAt)}.getOrNull()?:return false
  val age=Duration.between(measuredAt,Instant.now()).toMillis()
  return age in -5_000L..15_000L
 }
 private fun isOlderMeasurement(incoming:String,previous:String):Boolean {
  val next=runCatching{Instant.parse(incoming)}.getOrNull()?:return true
  val old=runCatching{Instant.parse(previous)}.getOrNull()?:return false
  return next.isBefore(old)
 }

 private companion object{const val OWNER="owner_account";const val EXPLICIT_RECIPIENTS="explicit_recipients";const val ACTIVE="active";const val ARMED="armed";const val GROUP="group";const val REALTIME_TAG="PlainstrideRealtime"}
}

class SafetyRequestException(val category: String, val status: Int?) : Exception(category)
