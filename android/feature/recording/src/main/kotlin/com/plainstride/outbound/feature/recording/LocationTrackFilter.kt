package com.plainstride.outbound.feature.recording

import com.plainstride.outbound.core.model.activity.ElevationGainCalculator
import com.plainstride.outbound.core.model.activity.ElevationLocation
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

internal data class FilterOutput(
    val sample: RecordedLocationSample?,
    val distanceIncrementMeters: Double,
    val estimatedSpeedMetersPerSecond: Double?,
)

/** Language-neutral port of iOS LocationTrackFilter and elevation rules. */
internal class LocationTrackFilter(private val activityKind: ActivityKind) {
    private var anchor: RecordedLocationSample? = null
    private var filtered: RecordedLocationSample? = null

    private val maximumSpeed = when (activityKind) {
        ActivityKind.CYCLING -> 25.0
        ActivityKind.WALKING, ActivityKind.HIKING -> 7.0
        ActivityKind.RUNNING -> 10.0
        ActivityKind.SWIMMING -> 5.0
    }
    private val stationarySpeed = when (activityKind) {
        ActivityKind.CYCLING -> 1.0
        ActivityKind.WALKING, ActivityKind.HIKING -> 0.45
        ActivityKind.RUNNING -> 0.65
        ActivityKind.SWIMMING -> 0.35
    }

    fun ingest(raw: RecordedLocationSample): FilterOutput {
        if (!raw.latitude.isFinite() || !raw.longitude.isFinite() ||
            raw.latitude !in -90.0..90.0 || raw.longitude !in -180.0..180.0 ||
            !raw.horizontalAccuracyMeters.isFinite() || raw.horizontalAccuracyMeters !in 0.0..50.0
        ) return FilterOutput(null, 0.0, null)

        val oldAnchor = anchor
        val oldFiltered = filtered
        if (oldAnchor == null || oldFiltered == null) {
            anchor = raw
            filtered = raw
            return FilterOutput(raw, 0.0, reliableSpeed(raw))
        }
        val intervalSeconds = (raw.capturedAtElapsedRealtimeNanos - oldAnchor.capturedAtElapsedRealtimeNanos) / 1e9
        if (intervalSeconds <= 0.0) return FilterOutput(null, 0.0, null)

        val reportedSpeed = reliableSpeed(raw)
        val speedAccuracy = raw.speedAccuracyMetersPerSecond?.takeIf { it.isFinite() && it >= 0 } ?: 0.0
        if (reportedSpeed != null && reportedSpeed - speedAccuracy > maximumSpeed) {
            return FilterOutput(null, 0.0, null)
        }
        val rawDistance = distanceMeters(oldAnchor, raw)
        val uncertainty = hypot(oldAnchor.horizontalAccuracyMeters.coerceAtLeast(0.0), raw.horizontalAccuracyMeters)
        val plausibleMinimum = max(0.0, rawDistance - min(30.0, uncertainty * 0.7))
        if (plausibleMinimum / intervalSeconds > maximumSpeed * 1.2) return FilterOutput(null, 0.0, null)

        val movementThreshold = max(1.5, min(9.0, uncertainty * 0.2))
        val couldBeStationary = reportedSpeed?.let { it <= stationarySpeed + speedAccuracy } ?: true
        if (rawDistance < movementThreshold && couldBeStationary) return FilterOutput(null, 0.0, reportedSpeed ?: 0.0)

        // Android's fused provider already performs sensor fusion. An uncertainty-weighted
        // coordinate blend removes residual jitter without introducing a platform map type.
        val alpha = when {
            raw.horizontalAccuracyMeters <= 5 -> 0.88
            raw.horizontalAccuracyMeters <= 10 -> 0.76
            raw.horizontalAccuracyMeters <= 20 -> 0.58
            raw.horizontalAccuracyMeters <= 35 -> 0.40
            else -> 0.28
        }
        val next = raw.copy(
            latitude = oldFiltered.latitude + (raw.latitude - oldFiltered.latitude) * alpha,
            longitude = normalizeLongitude(
                oldFiltered.longitude + shortestLongitudeDelta(oldFiltered.longitude, raw.longitude) * alpha,
            ),
        )
        val increment = distanceMeters(oldFiltered, next)
        anchor = raw
        filtered = next
        return FilterOutput(next, increment, reportedSpeed ?: increment / intervalSeconds)
    }

    private fun reliableSpeed(sample: RecordedLocationSample): Double? {
        val speed = sample.speedMetersPerSecond ?: return null
        val accuracy = sample.speedAccuracyMetersPerSecond ?: return null
        return speed.takeIf { it.isFinite() && it >= 0 && accuracy.isFinite() && accuracy in 0.0..3.0 }
    }
}

internal class ElevationGainAccumulator {
    private val accumulator = ElevationGainCalculator.StreamingRangeAccumulator()
    val gainMeters: Double get() = accumulator.gainMeters

    fun startNewSegment() = accumulator.startNewSegment()

    fun ingest(sample: RecordedLocationSample) {
        accumulator.ingest(ElevationLocation(
            latitude = sample.latitude, longitude = sample.longitude,
            altitudeMeters = sample.altitudeMeters ?: return,
            verticalAccuracyMeters = sample.verticalAccuracyMeters ?: return,
            timestampMillis = sample.capturedAtEpochMilliseconds,
        ))
    }
}

internal fun distanceMeters(a: RecordedLocationSample, b: RecordedLocationSample): Double {
    val earthRadius = 6_371_000.0
    val lat1 = Math.toRadians(a.latitude)
    val lat2 = Math.toRadians(b.latitude)
    val deltaLat = lat2 - lat1
    val deltaLon = Math.toRadians(shortestLongitudeDelta(a.longitude, b.longitude))
    val h = sin(deltaLat / 2) * sin(deltaLat / 2) + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
    return earthRadius * 2 * asin(min(1.0, sqrt(h)))
}

private fun shortestLongitudeDelta(from: Double, to: Double): Double = ((to - from + 540.0) % 360.0) - 180.0

private fun normalizeLongitude(value: Double): Double = ((value + 540.0) % 360.0) - 180.0
