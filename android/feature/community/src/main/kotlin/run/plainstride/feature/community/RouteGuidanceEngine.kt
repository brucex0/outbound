package run.plainstride.feature.community

import kotlin.math.*

data class GuidancePoint(val latitude: Double, val longitude: Double, val altitudeM: Double? = null)
data class GuidanceFix(val point: GuidancePoint, val accuracyM: Double, val courseDegrees: Double? = null)
enum class GuidanceSignal { ACQUIRING, ON_ROUTE, DEVIATED, REJOINED, WRONG_WAY, ARRIVED }
data class GuidanceState(val signal: GuidanceSignal, val progress: Double, val remainingM: Double, val nearestDistanceM: Double)

/** Exact-polyline, deterministic guidance. It never invents maneuvers, road names, or reroutes. */
class RouteGuidanceEngine(points: List<GuidancePoint>, reverse: Boolean = false) {
 private val route = (if (reverse) points.reversed() else points).also { require(it.size in 2..50_000) }
 private val cumulative = DoubleArray(route.size).also { values -> for (i in 1 until route.size) values[i] = values[i - 1] + distance(route[i - 1], route[i]) }
 private val total = cumulative.last()
 private var acquired = false; private var priorProgress = 0.0; private var deviationCount = 0; private var onRouteCount = 0; private var arrived = false

 fun update(fix: GuidanceFix): GuidanceState {
  if (arrived) return GuidanceState(GuidanceSignal.ARRIVED, 1.0, 0.0, distance(fix.point, route.last()))
  val nearest = route.indices.minBy { distance(fix.point, route[it]) }
  val offset = distance(fix.point, route[nearest]); val raw = cumulative[nearest] / total
  if (!acquired) { acquired = distance(fix.point, route.first()) <= max(45.0, fix.accuracyM * 2); if (!acquired) return GuidanceState(GuidanceSignal.ACQUIRING, 0.0, total, offset) }
  val bounded = raw.coerceIn((priorProgress - .015).coerceAtLeast(0.0), (priorProgress + .12).coerceAtMost(1.0))
  val threshold = max(35.0, fix.accuracyM * 1.5); if (offset > threshold) { deviationCount++; onRouteCount = 0 } else { onRouteCount++; deviationCount = 0 }
  val rejoined = onRouteCount == 3 && priorProgress > 0
  priorProgress = max(priorProgress, bounded)
  arrived = priorProgress >= .92 && distance(fix.point, route.last()) <= max(35.0, fix.accuracyM * 1.5)
  val signal = when { arrived -> GuidanceSignal.ARRIVED; deviationCount >= 3 -> GuidanceSignal.DEVIATED; rejoined -> GuidanceSignal.REJOINED; else -> GuidanceSignal.ON_ROUTE }
  return GuidanceState(signal, priorProgress, (total * (1 - priorProgress)).coerceAtLeast(0.0), offset)
 }
 private fun distance(a: GuidancePoint, b: GuidancePoint): Double { val p1 = Math.toRadians(a.latitude); val p2 = Math.toRadians(b.latitude); val dp = p2-p1; val dl = Math.toRadians(b.longitude-a.longitude); val h=sin(dp/2).pow(2)+cos(p1)*cos(p2)*sin(dl/2).pow(2); return 6371000*2*atan2(sqrt(h),sqrt(1-h)) }
}
