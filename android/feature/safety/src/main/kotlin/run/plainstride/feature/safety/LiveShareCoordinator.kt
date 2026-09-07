package run.plainstride.feature.safety

import javax.inject.Inject
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import android.os.SystemClock
import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import run.plainstride.core.network.PlainstrideJson
import run.plainstride.core.network.*
import run.plainstride.core.analytics.*

class LiveShareCoordinator @Inject constructor(private val api:SafetyApi,private val tokens:AccessTokenProvider,private val analytics:ProductAnalytics,@ApplicationContext context:Context){
 private val preferences=context.getSharedPreferences("live_share_state",Context.MODE_PRIVATE);private val lock=Mutex();private val mutableActive=MutableStateFlow(preferences.getString(ACTIVE,null)?.let{runCatching{PlainstrideJson.decodeFromString<LiveShare>(it)}.getOrNull()});val active=mutableActive.asStateFlow();private val mutableGroup=MutableStateFlow(preferences.getString(GROUP,null)?.let{runCatching{PlainstrideJson.decodeFromString<GroupRun>(it)}.getOrNull()});val group=mutableGroup.asStateFlow();private var armed:CreateLiveShareRequest?=preferences.getString(ARMED,null)?.let{runCatching{PlainstrideJson.decodeFromString<CreateLiveShareRequest>(it)}.getOrNull()};private var lastSentAt=0L;private var lastPoint:LiveLocation?=null
 fun arm(request:CreateLiveShareRequest){armed=request;preferences.edit().putString(ARMED,PlainstrideJson.encodeToString(request)).apply();analytics.record(AnalyticsEvent("live_share_armed"))}
 suspend fun recordingStarted(activityId:String?=null):Result<LiveShare?>{if(mutableActive.value!=null)return Result.success(mutableActive.value);val request=armed?:return Result.success(null);armed=null;preferences.edit().remove(ARMED).apply();return start(request.copy(activityId=activityId)).map{it}}
 suspend fun start(request:CreateLiveShareRequest):Result<LiveShare> = authenticated{apiCall{api.create(it,request)}}.onSuccess{mutableActive.value=it;preferences.edit().putString(ACTIVE,PlainstrideJson.encodeToString(it)).apply()}.also{result->analytics.record(AnalyticsEvent("live_share_started",mapOf(AnalyticsProperty.Result to if(result.isSuccess)"success" else "failure")))}
 suspend fun update(point:LiveLocation):Result<LiveShare?> = lock.withLock { val share=mutableActive.value?:return Result.success(null);val now=SystemClock.elapsedRealtime();val prior=lastPoint;if(now-lastSentAt<10_000&&prior!=null&&haversine(prior,point)<25)return Result.success(share);authenticated{apiCall{api.update(it,share.id,point)}}.onSuccess{mutableActive.value=it;lastPoint=point;lastSentAt=now} }
 suspend fun recordingEnded()=end()
 suspend fun end():Result<Unit>{val share=mutableActive.value?:return Result.success(Unit);return authenticated{apiCall{api.end(it,share.id)}}.map{clear();Unit}.also{result->analytics.record(AnalyticsEvent("live_share_ended",mapOf(AnalyticsProperty.Result to if(result.isSuccess)"success" else "failure")))}}
 fun clear(){armed=null;mutableActive.value=null;lastPoint=null;lastSentAt=0;preferences.edit().clear().apply()}
 suspend fun registerToken(token:String,bundle:String,locale:String)=authenticated{apiCall{api.register(it,PushDeviceRequest(token,appBundle=bundle,locale=locale))}}.map{Unit}
 suspend fun unregisterToken(token:String)=authenticated{apiCall{api.unregister(it,token)}}.map{Unit}
 suspend fun inbox()=authenticated{apiCall{api.inbox(it)}}
 suspend fun markInboxRead()=authenticated{apiCall{api.readAll(it)}}.map{Unit}
 suspend fun createGroupRun(request:CreateGroupRunRequest)=authenticated{apiCall{api.createGroupRun(it,request)}}.onSuccess(::saveGroup)
 suspend fun joinGroupRun(invite:String)=authenticated{apiCall{api.joinGroupRun(it,JoinGroupRunRequest(invite.trim()))}}.onSuccess(::saveGroup)
 suspend fun groupRun(id:String)=authenticated{apiCall{api.groupRun(it,id)}}.onSuccess(::saveGroup)
 suspend fun liveShare(id:String)=authenticated{apiCall{api.liveShare(it,id)}}.onSuccess{mutableActive.value=it;preferences.edit().putString(ACTIVE,PlainstrideJson.encodeToString(it)).apply()}
 suspend fun updateGroupRun(id:String,point:GroupLocationUpdate)=authenticated{apiCall{api.updateGroupLocation(it,id,point)}}.onSuccess(::saveGroup)
 suspend fun leaveGroupRun(id:String,finished:Boolean)=authenticated{auth->apiCall{if(finished)api.finishGroupRun(auth,id)else api.leaveGroupRun(auth,id)}}.onSuccess{clearGroup()}
 suspend fun updateRecording(point:LiveLocation,paceSecondsPerKilometer:Double?){update(point);mutableGroup.value?.let{group->updateGroupRun(group.id,GroupLocationUpdate(point.recordedAt,point.latitude,point.longitude,point.altitudeM,point.accuracyM,point.elapsedSeconds,point.distanceM,paceSecondsPerKilometer))}}
 private fun saveGroup(value:GroupRun){mutableGroup.value=value;preferences.edit().putString(GROUP,PlainstrideJson.encodeToString(value)).apply()}
 private fun clearGroup(){mutableGroup.value=null;preferences.edit().remove(GROUP).apply()}
 private suspend fun<T:Any>authenticated(call:suspend(String)->ApiResult<T>):Result<T>{val token=tokens.validAccessToken()?:return Result.failure(IllegalStateException("signed_out"));return when(val value=call("Bearer $token")){is ApiResult.Success->Result.success(value.value);is ApiResult.Failure->Result.failure(IllegalStateException(value.error.code.name))}}
 private fun haversine(a:LiveLocation,b:LiveLocation):Double{val p1=Math.toRadians(a.latitude);val p2=Math.toRadians(b.latitude);val dp=p2-p1;val dl=Math.toRadians(b.longitude-a.longitude);val h=kotlin.math.sin(dp/2)*kotlin.math.sin(dp/2)+kotlin.math.cos(p1)*kotlin.math.cos(p2)*kotlin.math.sin(dl/2)*kotlin.math.sin(dl/2);return 6371000*2*kotlin.math.atan2(kotlin.math.sqrt(h),kotlin.math.sqrt(1-h))}
 private companion object{const val ACTIVE="active";const val ARMED="armed";const val GROUP="group"}
}
