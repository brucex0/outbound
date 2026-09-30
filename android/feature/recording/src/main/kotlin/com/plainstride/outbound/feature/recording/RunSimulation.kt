package com.plainstride.outbound.feature.recording

import kotlinx.serialization.Serializable
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

@Serializable
data class RunSimulationState(
    val speedKilometersPerHour: Double = 10.0,
    val timeRate: Int = 10,
    val isClockRunning: Boolean = false,
    val elapsedSeconds: Int = 0,
    val distanceMeters: Double = 0.0,
    val routeDistanceMeters: Double,
) {
    val isComplete: Boolean get() = distanceMeters >= routeDistanceMeters
    val speedMetersPerSecond: Double get() = speedKilometersPerHour / 3.6
}

/** DEBUG fixture matching iOS HarvestHalfMarathonSimulation.route. */
object HarvestRunSimulation {
    const val ROUTE_ID = "debug-redmond-harvest-half-marathon"

    val route = FollowedRouteConfiguration(
        id = ROUTE_ID,
        name = "Redmond Harvest Half Marathon",
        shape = "out_and_back",
        points = listOf(
            RecordingRoutePoint(47.6705, -122.1215, 42.0),
            RecordingRoutePoint(47.6730, -122.1215, 42.0),
            RecordingRoutePoint(47.6730, -122.1280, 35.0),
            RecordingRoutePoint(47.6780, -122.1310, 32.0),
            RecordingRoutePoint(47.6900, -122.1395, 30.0),
            RecordingRoutePoint(47.7050, -122.1480, 28.0),
            RecordingRoutePoint(47.7200, -122.1550, 25.0),
            RecordingRoutePoint(47.7350, -122.1580, 24.0),
            RecordingRoutePoint(47.7450, -122.1610, 22.0),
            RecordingRoutePoint(47.7350, -122.1580, 24.0),
            RecordingRoutePoint(47.7200, -122.1550, 25.0),
            RecordingRoutePoint(47.7050, -122.1480, 28.0),
            RecordingRoutePoint(47.6900, -122.1395, 30.0),
            RecordingRoutePoint(47.6780, -122.1310, 32.0),
            RecordingRoutePoint(47.6705, -122.1215, 42.0),
        ),
    )

    fun speedBucket(speedKilometersPerHour: Double): String = when {
        speedKilometersPerHour < 8 -> "under_8kph"
        speedKilometersPerHour < 12 -> "8_12kph"
        else -> "12kph_plus"
    }
}

internal class RunSimulationRouteSampler(points: List<RecordingRoutePoint>) {
    private data class Segment(
        val start: RecordingRoutePoint,
        val end: RecordingRoutePoint,
        val startDistance: Double,
        val length: Double,
        val course: Double,
    )

    private val segments: List<Segment>
    val totalDistanceMeters: Double

    init {
        var cumulative = 0.0
        segments = points.zipWithNext().mapNotNull { (start, end) ->
            val length = distance(start, end)
            if (length <= 0) return@mapNotNull null
            val segment = Segment(start, end, cumulative, length, course(start, end))
            cumulative += length
            segment
        }
        require(segments.isNotEmpty()) { "A simulated route needs at least two distinct points." }
        totalDistanceMeters = cumulative
    }

    fun sample(
        distanceMeters: Double,
        speedMetersPerSecond: Double,
        elapsedSeconds: Int,
        startEpochMilliseconds: Long,
        startElapsedRealtimeNanos: Long,
    ): RecordedLocationSample {
        val clampedDistance = distanceMeters.coerceIn(0.0, totalDistanceMeters)
        val segment = segments.lastOrNull { it.startDistance <= clampedDistance } ?: segments.first()
        val progress = ((clampedDistance - segment.startDistance) / segment.length).coerceIn(0.0, 1.0)
        val altitude = when {
            segment.start.altitudeMeters != null && segment.end.altitudeMeters != null ->
                segment.start.altitudeMeters + (segment.end.altitudeMeters - segment.start.altitudeMeters) * progress
            segment.start.altitudeMeters != null -> segment.start.altitudeMeters
            else -> segment.end.altitudeMeters ?: 0.0
        }
        return RecordedLocationSample(
            latitude = segment.start.latitude + (segment.end.latitude - segment.start.latitude) * progress,
            longitude = segment.start.longitude + (segment.end.longitude - segment.start.longitude) * progress,
            altitudeMeters = altitude,
            horizontalAccuracyMeters = 3.0,
            verticalAccuracyMeters = 3.0,
            speedMetersPerSecond = if (clampedDistance >= totalDistanceMeters) 0.0 else speedMetersPerSecond,
            speedAccuracyMetersPerSecond = 0.1,
            capturedAtEpochMilliseconds = startEpochMilliseconds + elapsedSeconds * 1_000L,
            capturedAtElapsedRealtimeNanos = startElapsedRealtimeNanos + elapsedSeconds * 1_000_000_000L,
        )
    }

    private fun distance(a: RecordingRoutePoint, b: RecordingRoutePoint): Double {
        val lat1 = Math.toRadians(a.latitude)
        val lat2 = Math.toRadians(b.latitude)
        val deltaLat = lat2 - lat1
        val deltaLon = Math.toRadians(b.longitude - a.longitude)
        val h = sin(deltaLat / 2).let { it * it } + cos(lat1) * cos(lat2) * sin(deltaLon / 2).let { it * it }
        return 6_371_000.0 * 2 * atan2(sqrt(h), sqrt(1 - h))
    }

    private fun course(a: RecordingRoutePoint, b: RecordingRoutePoint): Double {
        val lat1 = Math.toRadians(a.latitude)
        val lat2 = Math.toRadians(b.latitude)
        val deltaLon = Math.toRadians(b.longitude - a.longitude)
        val y = sin(deltaLon) * cos(lat2)
        val x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        return (Math.toDegrees(atan2(y, x)) + 360.0) % 360.0
    }
}
