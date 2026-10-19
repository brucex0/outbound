package com.plainstride.outbound.core.model.activity

import java.time.Instant
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/** Matches the iOS request shape; terrain smoothing/gain remain owned by the shared backend. */
data class TerrainElevationPosition(val lower: Int, val upper: Int, val fraction: Double)
data class SampledTerrainRoute(val points: List<ActivityTrackPoint>, val positions: List<TerrainElevationPosition>)

object TerrainElevationSampling {
    const val ALGORITHM_VERSION = "terrain-v2"
    private const val MAXIMUM_POINTS = 450
    private const val MINIMUM_SPACING_METERS = 20.0

    fun sample(points: List<ActivityTrackPoint>): SampledTerrainRoute {
        require(points.all { it.latitude.isFinite() && it.latitude in -85.0..85.0 && it.longitude.isFinite() && it.longitude in -180.0..180.0 })
        if (points.size < 2) return SampledTerrainRoute(points, points.indices.map { TerrainElevationPosition(it, it, 0.0) })
        val starts = points.indices.filter { it == 0 || points[it].startsNewSegment }
        val segments = starts.mapIndexed { index, start -> points.subList(start, starts.getOrNull(index + 1) ?: points.size) }
        val reserved = segments.sumOf { min(2, it.size) }
        require(reserved <= MAXIMUM_POINTS) { "terrain_too_many_segments" }
        val totalDistance = segments.sumOf { segment -> segment.zipWithNext().sumOf { (a, b) -> distance(a, b) } }
        val spacing = max(MINIMUM_SPACING_METERS, totalDistance / max(1, MAXIMUM_POINTS - reserved))
        val result = ArrayList<ActivityTrackPoint>()
        val positions = ArrayList<TerrainElevationPosition>()
        for (segment in segments) {
            val offset = result.size
            val sampleDistances = mutableListOf(0.0)
            val originalDistances = mutableListOf(0.0)
            result += segment.first().copy(startsNewSegment = true)
            var traversed = 0.0
            var nextSample = spacing
            for ((a, b) in segment.zipWithNext()) {
                val length = distance(a, b)
                while (length > 0 && nextSample < traversed + length) {
                    val fraction = (nextSample - traversed) / length
                    val longitudeDelta = (b.longitude - a.longitude + 540) % 360 - 180
                    val start = Instant.parse(a.timestamp).toEpochMilli()
                    val end = Instant.parse(b.timestamp).toEpochMilli()
                    sampleDistances += nextSample
                    result += ActivityTrackPoint(
                        timestamp = Instant.ofEpochMilli(start + ((end - start) * fraction).toLong()).toString(),
                        latitude = a.latitude + (b.latitude - a.latitude) * fraction,
                        longitude = (a.longitude + longitudeDelta * fraction + 540) % 360 - 180,
                        altitude = if (a.altitude != null && b.altitude != null) a.altitude + (b.altitude - a.altitude) * fraction else null,
                        verticalAccuracy = if (a.verticalAccuracy != null && b.verticalAccuracy != null) max(a.verticalAccuracy, b.verticalAccuracy) else null,
                    )
                    nextSample += spacing
                }
                traversed += length
                originalDistances += traversed
            }
            if (segment.size > 1) {
                result += segment.last().copy(startsNewSegment = false)
                sampleDistances += traversed
            }
            for (distance in originalDistances) {
                val search = sampleDistances.binarySearch(distance)
                val lower = (if (search >= 0) search else -search - 2).coerceIn(0, sampleDistances.lastIndex)
                val upper = min(lower + 1, sampleDistances.lastIndex)
                val span = sampleDistances[upper] - sampleDistances[lower]
                positions += TerrainElevationPosition(offset + lower, offset + upper,
                    if (span > 0) ((distance - sampleDistances[lower]) / span).coerceIn(0.0, 1.0) else 0.0)
            }
        }
        require(result.size <= MAXIMUM_POINTS) { "terrain_too_many_segments" }
        return SampledTerrainRoute(result, positions)
    }

    private fun distance(a: ActivityTrackPoint, b: ActivityTrackPoint): Double {
        val latitude = Math.toRadians(b.latitude - a.latitude)
        val longitude = Math.toRadians(b.longitude - a.longitude)
        val h = sin(latitude / 2) * sin(latitude / 2) + cos(Math.toRadians(a.latitude)) * cos(Math.toRadians(b.latitude)) * sin(longitude / 2) * sin(longitude / 2)
        return 6_371_000 * 2 * asin(sqrt(h.coerceIn(0.0, 1.0)))
    }
}
