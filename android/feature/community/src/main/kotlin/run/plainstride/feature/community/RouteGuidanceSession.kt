package run.plainstride.feature.community

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import run.plainstride.core.analytics.AnalyticsEvent
import run.plainstride.core.analytics.AnalyticsProperty
import run.plainstride.core.analytics.ProductAnalytics

/** Recording-facing adapter: feed accepted GPS fixes and persist [completed] with the activity. */
class RouteGuidanceSession(
 private val routeId:String,
 points:List<GuidancePoint>,
 reverse:Boolean,
 private val analytics:ProductAnalytics,
){
 private val engine=RouteGuidanceEngine(points,reverse);private val mutableState=MutableStateFlow<GuidanceState?>(null);val state=mutableState.asStateFlow()
 val completed:Boolean get()=mutableState.value?.signal==GuidanceSignal.ARRIVED
 fun onLocation(fix:GuidanceFix):GuidanceState{val prior=mutableState.value?.signal;val next=engine.update(fix);mutableState.value=next;if(next.signal!=prior&&next.signal in setOf(GuidanceSignal.DEVIATED,GuidanceSignal.REJOINED,GuidanceSignal.WRONG_WAY,GuidanceSignal.ARRIVED))analytics.record(AnalyticsEvent("route_guidance_signal",mapOf(AnalyticsProperty.Result to next.signal.name.lowercase())));return next}
 fun result()=FollowedRouteResult(routeId,completed)
}

data class FollowedRouteResult(val routeId:String,val completed:Boolean)
