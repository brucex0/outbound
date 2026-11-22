package com.plainstride.outbound.feature.community.planning

import android.annotation.SuppressLint
import android.content.Context
import android.location.Geocoder
import android.util.Log
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import com.plainstride.outbound.core.analytics.*
import com.plainstride.outbound.core.database.*
import com.plainstride.outbound.core.network.*
import com.plainstride.outbound.feature.community.*
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import kotlinx.coroutines.*
import kotlinx.coroutines.tasks.await
import kotlinx.serialization.encodeToString
import java.util.Locale

/** Provider DTOs, Android location, geocoding and durable snapshots stop at this adapter. */
class AndroidPlannerServices @Inject constructor(
    private val api: CommunityRoutesApi, private val tokens: AccessTokenProvider,
    private val cache: AccountCacheDao, private val analytics: ProductAnalytics,
    @ApplicationContext private val context: Context,
) : PlannerServices {
    override fun accountGuard(accountId: String): () -> Boolean { val owner=tokens.captureAccount(accountId);return { owner!=null && tokens.isCurrent(owner) } }
    override suspend fun search(query: String): List<PlannerPlace> = withContext(Dispatchers.IO) {
        if(!Geocoder.isPresent() || query.isBlank()) return@withContext emptyList()
        try {
            @Suppress("DEPRECATION")
            Geocoder(context, Locale.getDefault()).getFromLocationName(query.trim(),5).orEmpty().map {
                PlannerPlace(PlannerCoordinate(it.latitude,it.longitude),it.getAddressLine(0))
            }.filter{it.coordinate.valid}
        } catch(e: CancellationException){throw e} catch(e: Exception){Log.w("PlainstridePlanner","place_search failed type=${e.javaClass.simpleName}");throw e}
    }
    @SuppressLint("MissingPermission")
    override suspend fun currentLocation(): PlannerPlace? = try {
        val cancellation=CancellationTokenSource()
        val location=withTimeoutOrNull(12000) {
            LocationServices.getFusedLocationProviderClient(context).getCurrentLocation(Priority.PRIORITY_HIGH_ACCURACY,cancellation.token).await(cancellation)
        }
        val coordinate=location?.let { PlannerCoordinate(it.latitude,it.longitude) }
        val ageMs=location?.let { (android.os.SystemClock.elapsedRealtimeNanos()-it.elapsedRealtimeNanos)/1000000 }
        if(location==null)Log.w("PlainstridePlanner","current_location unavailable or timed_out")
        else if(coordinate?.valid!=true || ageMs==null || ageMs !in 0..60000 || !location.hasAccuracy() || !location.accuracy.isFinite() || location.accuracy !in 0f..100f) {
            Log.w("PlainstridePlanner","current_location rejected invalid_or_stale_or_imprecise")
        }
        if(location!=null && coordinate?.valid==true && ageMs!=null && ageMs in 0..60000 && location.hasAccuracy() && location.accuracy.isFinite() && location.accuracy in 0f..100f)PlannerPlace(coordinate) else null
    } catch(e: CancellationException){throw e} catch(e: Exception){Log.w("PlainstridePlanner","current_location failed type=${e.javaClass.simpleName}");null}
    override suspend fun candidates(accountId: String, request: PlannerRequest, onExisting: (List<PlannerCandidate>) -> Unit): PlannerResults = try { withContext(Dispatchers.Default) {
        val owner=tokens.captureAccount(accountId) ?: error("account_changed")
        val token=tokens.validAccessToken(owner) ?: error("signed_out")
        val auth="Bearer $token"
        val community=async {
            val nearby=apiCall { api.nearby(auth,request.start.latitude,request.start.longitude) }.also { if(!tokens.isCurrent(owner))throw CancellationException("account_changed") }
            val summaries=when(nearby) {
                is ApiResult.Success -> { cache.upsert(AccountCacheEntity(accountId,"route_planner.nearby","latest","und",PlainstrideJson.encodeToString(nearby.value),null,System.currentTimeMillis(),null));nearby.value.routes }
                is ApiResult.Failure -> { Log.w("PlainstridePlanner","nearby_routes failed status=${nearby.error.httpStatus} code=${nearby.error.code}");cache.get(accountId,"route_planner.nearby","latest","und")?.let { PlainstrideJson.decodeFromString<RoutesResponse>(it.payloadJson).routes }.orEmpty() }
            }
            summaries.filter { it.activityType.equals(request.activity.name,true) && it.routeShape.lowercase() in setOf("loop","round_trip","roundtrip") && it.distanceM in request.targetDistanceM*.9..request.targetDistanceM*1.1 }.take(12).mapNotNull { summary ->
                val detail=if(summary.geometry!=null) summary else when(val response=apiCall { api.detail(auth,summary.id) }.also { if(!tokens.isCurrent(owner))throw CancellationException("account_changed") }) {
                    is ApiResult.Success -> { cache.upsert(AccountCacheEntity(accountId,"routes.detail",summary.id,"und",PlainstrideJson.encodeToString(response.value),null,System.currentTimeMillis(),null)); response.value }
                    is ApiResult.Failure -> { Log.w("PlainstridePlanner","route_detail failed status=${response.error.httpStatus}");cache.get(accountId,"routes.detail",summary.id,"und")?.let { PlainstrideJson.decodeFromString<CommunityRoute>(it.payloadJson) } }
                }
                detail?.let { route ->
                    val points=route.guidancePoints().map { PlannerCoordinate(it.latitude,it.longitude,it.altitudeM) }
                    if(points.size<3 || points.any{!it.valid} || distanceBetween(points.first(),points.last())>150 || distanceBetween(request.start,points.first())>2500 || request.via?.let{via->distanceToRouteMeters(via,points)>100}==true) null
                    else PlannerCandidate(route.id,PlannerSource.COMMUNITY,route.name,request.activity,points,route.distanceM,route.elevationGainM,route.owner.displayName,request.start)
                }
            }
        }
        val generated=async {
            val response=apiCall { api.generate(auth,GenerateRouteRequest(request.start.dto(),request.via?.dto(),request.targetDistanceM,request.activity.name.lowercase(),if(request.lessClimbing) "less_climbing" else "balanced",request.variationSeed)) }
            when(response) {
                is ApiResult.Success -> response.value.candidates.map { candidate -> PlannerCandidate(candidate.id,PlannerSource.GENERATED,null,request.activity,candidate.points.map{PlannerCoordinate(it.latitude,it.longitude,it.altitude)},candidate.distanceM,candidate.elevationGainM,candidate.attribution,request.start) } to false
                is ApiResult.Failure -> { Log.w("PlainstridePlanner","generate_routes failed status=${response.error.httpStatus} code=${response.error.code}"); emptyList<PlannerCandidate>() to true }
            }
        }
        val existing=community.await(); withContext(Dispatchers.Main.immediate) { if(tokens.isCurrent(owner))onExisting(existing.take(3)) }; val (created,unavailable)=generated.await()
        check(tokens.isCurrent(owner))
        val unique=mutableListOf<PlannerCandidate>()
        // Alternate sources so a full generated response cannot hide suitable community loops.
        val pool=buildList { for(i in 0 until maxOf(existing.size,created.size)) { existing.getOrNull(i)?.let(::add);created.getOrNull(i)?.let(::add) } }
        val ranked=if(request.lessClimbing)pool.sortedBy{it.elevationGainM ?: Double.MAX_VALUE} else pool
        for(candidate in ranked) {
            if(candidate.distanceM !in request.targetDistanceM*.9..request.targetDistanceM*1.1 || candidate.points.size<3 || candidate.points.any{!it.valid} || distanceBetween(candidate.points.first(),candidate.points.last())>150 || request.via?.let{distanceToRouteMeters(it,candidate.points)>100}==true) continue
            if(unique.none { old->sameCorridor(candidate.points,old.points) }) unique.add(candidate)
            if(unique.size==3)break
        }
        PlannerResults(if(request.lessClimbing)unique.sortedBy{it.elevationGainM ?: Double.MAX_VALUE} else unique,unavailable)
    }
    } catch(e:CancellationException){throw e} catch(e:Exception){Log.w("PlainstridePlanner","plan_routes failed type=${e.javaClass.simpleName}");throw e}
    override suspend fun accept(accountId: String, candidate: PlannerCandidate): AcceptedPlannerRoute {
        val owner=tokens.captureAccount(accountId) ?: error("account_changed")
        check(tokens.isCurrent(owner))
        val accepted=AcceptedPlannerRoute(accountId,candidate)
        try { cache.upsert(AccountCacheEntity(accountId,"route_planner.accepted",candidate.id,"und",PlainstrideJson.encodeToString(accepted),null,System.currentTimeMillis(),null)) }
        catch(e: CancellationException){throw e} catch(e: Exception){Log.w("PlainstridePlanner","accept_route_save failed type=${e.javaClass.simpleName}");throw e}
        check(tokens.isCurrent(owner))
        return accepted
    }
    override fun event(result: String, activity: PlannerActivity, source: PlannerSource?) {
        analytics.record(AnalyticsEvent("route_planner_result",buildMap { put(AnalyticsProperty.Result,result);put(AnalyticsProperty.ActivityType,activity.name.lowercase());source?.let{put(AnalyticsProperty.Source,it.name.lowercase())} }))
    }
}
private fun PlannerCoordinate.dto() = GeneratedRouteCoordinate(latitude,longitude)
