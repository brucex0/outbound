package com.plainstride.outbound.feature.safety

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import android.util.Log
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import com.plainstride.outbound.feature.social.SocialPerson
import com.google.gson.JsonElement
import org.json.JSONObject
import java.time.Instant

@HiltViewModel class SafetySettingsViewModel @Inject constructor(
 private val contacts:TrustedContactStore,
 private val liveShare:LiveShareCoordinator,
 private val analytics:com.plainstride.outbound.core.analytics.ProductAnalytics,
):ViewModel(){
 private val mutableContacts=MutableStateFlow<List<TrustedContact>>(emptyList());val trustedContacts=mutableContacts.asStateFlow()
 private val mutableDefaultSharing=MutableStateFlow(false);val sharesWithTrustedContactsByDefault=mutableDefaultSharing.asStateFlow()
 val activeShare=liveShare.active
 val groupRun=liveShare.group
 val groupJoining=liveShare.groupJoining
 val selectedRecipientIds=liveShare.selectedRecipientIds
 private val mutableFollower=MutableStateFlow<InvitedLiveShare?>(null);val follower=mutableFollower.asStateFlow()
 private val mutableFollowerTrack=MutableStateFlow<List<LiveRoutePoint>>(emptyList());val followerTrack=mutableFollowerTrack.asStateFlow()
 private val mutableFollowerLoading=MutableStateFlow(false);val followerLoading=mutableFollowerLoading.asStateFlow()
 private val mutableFollowerMessage=MutableStateFlow<String?>(null);val followerMessage=mutableFollowerMessage.asStateFlow()
 private var connectionNames:Map<String,String> = emptyMap()
 private var activeAccountId:String?=null
 private var followerRefreshJob:Job?=null
 private var followerTrackShareId:String?=null

 init{reload()}

 /** Server pulls (screen open / account change) flow through here so the list survives reinstall. */
 fun onAccountActivated(accountId:String?)=viewModelScope.launch{
  activeAccountId=accountId
  contacts.migrateToServerBackedContacts()
  if(accountId==null){mutableDefaultSharing.value=false;return@launch}
  mutableDefaultSharing.value=contacts.sharesWithTrustedContactsByDefault(accountId)
  contacts.pull(accountId)
  reload()
 }

 /** Fresh connection roster so cached rows can be re-labelled after a reinstall. */
 fun onConnectionsUpdated(people:List<SocialPerson>){connectionNames=people.associate{it.id to it.displayName};reload()}

 fun add(contact:TrustedContact)=viewModelScope.launch{
  val makeDefault=mutableContacts.value.isEmpty()
  contacts.save(if(makeDefault)contact.copy(isDefault=true)else contact)
  contacts.push()
  reload()
 }
 fun remove(contact:TrustedContact)=viewModelScope.launch{contacts.remove(contact.id);contacts.push();reload()}
 fun setTrusted(person:SocialPerson,isTrusted:Boolean)=viewModelScope.launch{
  if(isTrusted)contacts.save(TrustedContact(person.id,person.displayName,"push","",false)) else contacts.remove(person.id)
  contacts.push()
  reload()
  analytics.record(com.plainstride.outbound.core.analytics.AnalyticsEvent("preference_changed",mapOf(
   com.plainstride.outbound.core.analytics.AnalyticsProperty.ChangeType to "trusted_contact",
   com.plainstride.outbound.core.analytics.AnalyticsProperty.SelectionType to if(isTrusted)"added" else "removed",
  )))
 }
 fun setSharesWithTrustedContactsByDefault(enabled:Boolean)=viewModelScope.launch{
  val accountId=activeAccountId?:return@launch
  if(enabled&&mutableContacts.value.isEmpty())return@launch
  contacts.setSharesWithTrustedContactsByDefault(accountId,enabled)
  mutableDefaultSharing.value=enabled
  analytics.record(com.plainstride.outbound.core.analytics.AnalyticsEvent("preference_changed",mapOf(
   com.plainstride.outbound.core.analytics.AnalyticsProperty.ChangeType to "trusted_contacts_default_share",
   com.plainstride.outbound.core.analytics.AnalyticsProperty.SelectionType to if(enabled)"on" else "off",
  )))
 }
 fun arm(){val ids=mutableContacts.value.map{it.id};if(ids.isNotEmpty())liveShare.arm(CreateLiveShareRequest(recipientUserIds=ids))}
 fun applyTrustedContactDefault(){
  if(!mutableDefaultSharing.value)return
  liveShare.applyDefaultRecipients(mutableContacts.value.map{it.id})
 }
 fun configureCheerRecipients(ids:Set<String>){liveShare.configureRecipients(ids.toList())}
 fun createGroup()=viewModelScope.launch{liveShare.createGroupRun(CreateGroupRunRequest())}
 fun joinGroup(invite:String)=viewModelScope.launch{liveShare.joinGroupRun(invite)}
 fun openGroup(id:String)=viewModelScope.launch{liveShare.groupRun(id)}
 fun refreshGroup(id:String)=viewModelScope.launch{liveShare.groupRun(id)}
 fun joinActivityGroupRun(activityEventId:String)=viewModelScope.launch{liveShare.joinActivityGroupRun(activityEventId)}
 fun isSharingEvent(activityEventId:String)=liveShare.isSharingEvent(activityEventId)
 fun hasDifferentActiveGroup(activityEventId:String)=liveShare.hasDifferentActiveGroup(activityEventId)
 fun stopGroupSharing()=viewModelScope.launch{liveShare.leaveGroupRun(false)}
 fun openLiveShare(id:String) {
  if(BuildConfig.DEBUG) Log.d(REALTIME_TAG,"follower_open_requested")
  if(followerTrackShareId!=id){followerTrackShareId=id;mutableFollowerTrack.value=emptyList()}
  followerRefreshJob?.cancel()
  followerRefreshJob=null
  viewModelScope.launch {
   analytics.record(com.plainstride.outbound.core.analytics.AnalyticsEvent("live_cheer_follower_opened",mapOf(com.plainstride.outbound.core.analytics.AnalyticsProperty.Source to "notification")))
   mutableFollowerMessage.value=null
   mutableFollowerLoading.value=mutableFollower.value?.id!=id
   liveShare.invitedShare(id).onSuccess { initial ->
    mutableFollower.value=initial
    seedFollowerTrack(initial)
    if(BuildConfig.DEBUG) Log.d(REALTIME_TAG,"follower_snapshot_loaded active=${initial.status=="active"} has_location=${initial.lastLocation!=null}")
    if(initial.status=="active") {
     liveShare.watchFollower(
      id=id,
      onEvent={name,data ->
       when(name) {
        "location" -> applyFollowerLocation(data)
        "cheer.available" -> viewModelScope.launch { refreshFollowerSnapshot(id) }
       }
      },
      onChannelAttached={viewModelScope.launch { refreshFollowerSnapshot(id) }},
     )
     followerRefreshJob=viewModelScope.launch {
      while(mutableFollower.value?.id==id&&mutableFollower.value?.status=="active") {
       delay(FOLLOWER_REFRESH_INTERVAL_MS)
       if(mutableFollower.value?.id!=id||mutableFollower.value?.status!="active") break
       refreshFollowerSnapshot(id)
      }
     }
    } else {
     liveShare.stopWatchingFollower()
    }
   }.onFailure {
    if(BuildConfig.DEBUG) Log.e(REALTIME_TAG,"follower_snapshot_load_failed error=${it.javaClass.simpleName}")
    if(mutableFollower.value?.id!=id) mutableFollowerMessage.value="load_failed"
   }
   mutableFollowerLoading.value=false
  }
 }

 fun stopWatchingLiveShare() {
  followerRefreshJob?.cancel()
  followerRefreshJob=null
  liveShare.stopWatchingFollower()
 }

 private suspend fun refreshFollowerSnapshot(id:String) {
  liveShare.invitedShare(id).onSuccess { refreshed ->
   val current=mutableFollower.value
   if(current?.id!=id) return@onSuccess
   val newerOrEqual=isAtLeastAsRecent(refreshed.lastLocationAt,current.lastLocationAt)
   if(BuildConfig.DEBUG) Log.d(REALTIME_TAG,"follower_snapshot_received active=${refreshed.status=="active"} has_location=${refreshed.lastLocation!=null} location_is_at_least_as_recent=$newerOrEqual")
   if(refreshed.status!="active"||current.status!="active"||
    newerOrEqual) {
    mutableFollower.value=refreshed
    refreshed.lastLocation?.let(::appendFollowerTrack)
    if(refreshed.status!="active") liveShare.stopWatchingFollower()
   }
  }.onFailure { if(BuildConfig.DEBUG) Log.e(REALTIME_TAG,"follower_snapshot_refresh_failed error=${it.javaClass.simpleName}") }
 }

 private fun applyFollowerLocation(value:Any?) {
  val payload=when(value) {
   is Map<*,*> -> value
   is JSONObject -> value
   is String -> runCatching { JSONObject(value) }.getOrNull()
   is JsonElement -> value.takeIf { it.isJsonObject }?.let { runCatching { JSONObject(it.toString()) }.getOrNull() }
   else -> null
  } ?: run { if(BuildConfig.DEBUG) Log.w(REALTIME_TAG,"follower_location_rejected reason=unsupported_payload type=${value?.javaClass?.simpleName ?: "null"}");return }
  fun field(name:String):Any?=when(payload) {
   is Map<*,*> -> payload[name]
   is JSONObject -> payload.opt(name)
   else -> null
  }
  fun number(name:String):Double?=when(val field=field(name)) {
   is Number -> field.toDouble()
   is String -> field.toDoubleOrNull()
   else -> null
  }
  val old=mutableFollower.value?:return
  val latitude=number("latitude")?:run { if(BuildConfig.DEBUG) Log.w(REALTIME_TAG,"follower_location_rejected reason=missing_latitude");return }
  val longitude=number("longitude")?:run { if(BuildConfig.DEBUG) Log.w(REALTIME_TAG,"follower_location_rejected reason=missing_longitude");return }
  val recordedAt=field("recordedAt") as? String?:run { if(BuildConfig.DEBUG) Log.w(REALTIME_TAG,"follower_location_rejected reason=missing_recorded_at");return }
  if(!isAtLeastAsRecent(recordedAt,old.lastLocationAt)) {
   if(BuildConfig.DEBUG) Log.d(REALTIME_TAG,"follower_location_ignored reason=older_than_current")
   return
  }
  mutableFollower.value=old.copy(
   lastLocation=LiveRoutePoint(recordedAt,latitude,longitude),
   lastLocationAt=recordedAt,
   elapsedSeconds=number("elapsedSeconds")?.toInt()?:old.elapsedSeconds,
   distanceM=number("distanceM")?:old.distanceM,
   currentPaceSecsPerKm=number("currentPaceSecsPerKm"),
   heartRate=number("heartRate")?.toInt(),
  )
  appendFollowerTrack(LiveRoutePoint(recordedAt,latitude,longitude))
  if(BuildConfig.DEBUG) Log.d(REALTIME_TAG,"follower_location_applied route_points=${mutableFollowerTrack.value.size}")
 }

 private fun seedFollowerTrack(share:InvitedLiveShare) {
  val current=mutableFollowerTrack.value
  if(current.isEmpty()) mutableFollowerTrack.value=share.routePreview.takeLast(MAX_FOLLOWER_ROUTE_POINTS)
  share.lastLocation?.let(::appendFollowerTrack)
 }

 private fun appendFollowerTrack(point:LiveRoutePoint) {
  val current=mutableFollowerTrack.value
  val last=current.lastOrNull()
  if(last!=null&&last.recordedAt==point.recordedAt&&last.latitude==point.latitude&&last.longitude==point.longitude)return
  mutableFollowerTrack.value=(current+point).takeLast(MAX_FOLLOWER_ROUTE_POINTS)
 }

 private fun isAtLeastAsRecent(candidate:String?,current:String?):Boolean {
  if(candidate==null) return false
  if(current==null) return true
  val candidateInstant=runCatching { Instant.parse(candidate) }.getOrNull()?:return candidate>=current
  val currentInstant=runCatching { Instant.parse(current) }.getOrNull()?:return candidate>=current
  return !candidateInstant.isBefore(currentInstant)
 }
 fun sendVoiceCheer(audioBase64:String,durationMs:Int)=viewModelScope.launch{val id=mutableFollower.value?.id?:return@launch;mutableFollowerMessage.value=null;liveShare.sendVoiceCheer(id,audioBase64,durationMs).onSuccess{mutableFollowerMessage.value="sent"}.onFailure{mutableFollowerMessage.value="send_failed"}}
 fun leaveGroup()=viewModelScope.launch{liveShare.group.value?.let{liveShare.leaveGroupRun(it.id,false)}}
 private fun reload()=viewModelScope.launch{mutableContacts.value=contacts.contacts().map{contact->connectionNames[contact.id]?.takeIf(String::isNotBlank)?.let{contact.copy(displayName=it)}?:contact}}

 private companion object { const val FOLLOWER_REFRESH_INTERVAL_MS=5_000L;const val MAX_FOLLOWER_ROUTE_POINTS=3_000;const val REALTIME_TAG="PlainstrideRealtime" }
}
