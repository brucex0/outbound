package run.plainstride.feature.safety

import javax.inject.Inject
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import run.plainstride.core.network.*
import run.plainstride.core.analytics.*

class LiveShareCoordinator @Inject constructor(private val api:SafetyApi,private val tokens:AccessTokenProvider,private val analytics:ProductAnalytics){
 private val lock=Mutex(); private var active:LiveShare?=null; private var lastSentAt=0L; private var lastPoint:LiveLocation?=null
 suspend fun start(request:CreateLiveShareRequest):Result<LiveShare> = authenticated{apiCall{api.create(it,request)}}.onSuccess{active=it}.also{result->analytics.record(AnalyticsEvent("live_share_started",mapOf(AnalyticsProperty.Result to if(result.isSuccess)"success" else "failure")))}
 suspend fun update(point:LiveLocation):Result<LiveShare?> = lock.withLock { val share=active?:return Result.success(null); val now=System.currentTimeMillis(); val prior=lastPoint; if(now-lastSentAt<10_000 && prior!=null && haversine(prior,point)<25)return Result.success(share); authenticated{apiCall{api.update(it,share.id,point)}}.onSuccess{active=it;lastPoint=point;lastSentAt=now} }
 suspend fun end():Result<Unit>{val share=active?:return Result.success(Unit);return authenticated{apiCall{api.end(it,share.id)}}.map{active=null;Unit}.also{result->analytics.record(AnalyticsEvent("live_share_ended",mapOf(AnalyticsProperty.Result to if(result.isSuccess)"success" else "failure")))}}
 suspend fun registerToken(token:String,bundle:String,locale:String)=authenticated{apiCall{api.register(it,PushDeviceRequest(token,appBundle=bundle,locale=locale))}}.map{Unit}
 suspend fun inbox()=authenticated{apiCall{api.inbox(it)}}
 suspend fun markInboxRead()=authenticated{apiCall{api.readAll(it)}}.map{Unit}
 private suspend fun<T:Any>authenticated(call:suspend(String)->ApiResult<T>):Result<T>{val token=tokens.validAccessToken()?:return Result.failure(IllegalStateException("signed_out"));return when(val value=call("Bearer $token")){is ApiResult.Success->Result.success(value.value);is ApiResult.Failure->Result.failure(IllegalStateException(value.error.code.name))}}
 private fun haversine(a:LiveLocation,b:LiveLocation):Double{val p1=Math.toRadians(a.latitude);val p2=Math.toRadians(b.latitude);val dp=p2-p1;val dl=Math.toRadians(b.longitude-a.longitude);val h=kotlin.math.sin(dp/2)*kotlin.math.sin(dp/2)+kotlin.math.cos(p1)*kotlin.math.cos(p2)*kotlin.math.sin(dl/2)*kotlin.math.sin(dl/2);return 6371000*2*kotlin.math.atan2(kotlin.math.sqrt(h),kotlin.math.sqrt(1-h))}
}
