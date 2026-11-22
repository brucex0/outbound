package com.plainstride.outbound.feature.community.planning

import kotlinx.serialization.Serializable
import kotlin.math.*

@Serializable data class PlannerCoordinate(val latitude: Double, val longitude: Double, val altitude: Double? = null) {
    val valid get() = latitude.isFinite() && longitude.isFinite() && latitude in -90.0..90.0 && longitude in -180.0..180.0
}
@Serializable data class PlannerPlace(val coordinate: PlannerCoordinate, val name: String? = null)
@Serializable enum class PlannerActivity { RUNNING, WALKING, HIKING, CYCLING }
@Serializable enum class PlannerSource { COMMUNITY, GENERATED }
@Serializable data class PlannerCandidate(
    val id: String, val source: PlannerSource, val name: String?, val activity: PlannerActivity,
    val points: List<PlannerCoordinate>, val distanceM: Double, val elevationGainM: Double?,
    val attribution: String?, val requestedStart: PlannerCoordinate,
) { val startDisplacementM get() = points.firstOrNull()?.let { distanceBetween(requestedStart, it) } ?: 0.0 }
data class PlannerRequest(val start: PlannerCoordinate, val via: PlannerCoordinate?, val targetDistanceM: Double, val activity: PlannerActivity, val lessClimbing: Boolean, val variationSeed: Int)
@Serializable data class AcceptedPlannerRoute(val accountId: String, val candidate: PlannerCandidate)
data class PlannerResults(val candidates: List<PlannerCandidate>, val generationUnavailable: Boolean = false)
interface PlannerServices {
    fun accountGuard(accountId: String): () -> Boolean
    suspend fun search(query: String): List<PlannerPlace>
    suspend fun currentLocation(): PlannerPlace?
    suspend fun candidates(accountId: String, request: PlannerRequest, onExisting: (List<PlannerCandidate>) -> Unit): PlannerResults
    suspend fun accept(accountId: String, candidate: PlannerCandidate): AcceptedPlannerRoute
    fun event(result: String, activity: PlannerActivity, source: PlannerSource? = null)
}
fun distanceBetween(a: PlannerCoordinate, b: PlannerCoordinate): Double {
    val lat = Math.toRadians(b.latitude-a.latitude); val lon = Math.toRadians(b.longitude-a.longitude)
    val h = sin(lat/2).pow(2)+cos(Math.toRadians(a.latitude))*cos(Math.toRadians(b.latitude))*sin(lon/2).pow(2)
    return 6371000*2*asin(sqrt(h.coerceIn(0.0,1.0)))
}
/** Metric samples and point-to-segment corridor distance ignore provider vertex density. */
fun sameCorridor(a: List<PlannerCoordinate>, b: List<PlannerCoordinate>): Boolean {
    if(a.size<2 || b.size<2) return false
    fun samples(points: List<PlannerCoordinate>): List<PlannerCoordinate> = buildList {
        add(points.first())
        var remaining=50.0
        points.zipWithNext().forEach { (start,end) ->
            val length=distanceBetween(start,end)
            var travelled=remaining
            while(travelled<length && size<1200) {
                val fraction=travelled/length
                add(PlannerCoordinate(start.latitude+(end.latitude-start.latitude)*fraction,start.longitude+(end.longitude-start.longitude)*fraction))
                travelled+=50
            }
            remaining=(travelled-length).coerceAtLeast(.001)
        }
        add(points.last())
    }
    val one=samples(a);val two=samples(b)
    return one.count{distanceToRouteMeters(it,b)<60}.toDouble()/one.size>.8 && two.count{distanceToRouteMeters(it,a)<60}.toDouble()/two.size>.8
}

fun distanceToRouteMeters(point: PlannerCoordinate, line: List<PlannerCoordinate>): Double = line.zipWithNext().minOfOrNull { (start,end) ->
    val scale=cos(Math.toRadians(point.latitude))*111195.0
    val ax=(start.longitude-point.longitude)*scale; val ay=(start.latitude-point.latitude)*111195
    val bx=(end.longitude-point.longitude)*scale; val by=(end.latitude-point.latitude)*111195
    val dx=bx-ax;val dy=by-ay;val length=dx*dx+dy*dy
    val t=if(length==0.0)0.0 else (-(ax*dx+ay*dy)/length).coerceIn(0.0,1.0)
    hypot(ax+t*dx,ay+t*dy)
} ?: Double.POSITIVE_INFINITY
