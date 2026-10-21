package com.plainstride.outbound.feature.recording

import kotlinx.serialization.Serializable
import kotlin.math.*

/** Stop accounting follows GPS observations, never foreground timer frequency. */
@Serializable
data class MovingTimeTracker(
    val stoppedSeconds: Long = 0,
    private val enabled: Boolean = true,
    private val candidateSeconds: Long = 0,
    private val lastActiveSeconds: Long? = null,
    private val anchor: MovingTimePosition? = null,
) {
    fun observe(activeSeconds: Long, sample: RecordedLocationSample, stationarySpeedThreshold: Double): MovingTimeTracker {
        if (!enabled || activeSeconds < 0 || (lastActiveSeconds != null && activeSeconds <= lastActiveSeconds)) return this
        val position = MovingTimePosition(sample.latitude, sample.longitude)
        val baseline = copy(candidateSeconds = 0, lastActiveSeconds = activeSeconds, anchor = position)
        if (!sample.latitude.isFinite() || !sample.longitude.isFinite() ||
            sample.latitude !in -90.0..90.0 || sample.longitude !in -180.0..180.0 ||
            sample.horizontalAccuracyMeters !in 0.0..20.0
        ) return baseline.copy(anchor = null)
        val delta = lastActiveSeconds?.let { activeSeconds - it }
        if (delta == null || delta > 30 || anchor == null) return baseline
        val minimumNativeSpeed = sample.speedMetersPerSecond?.takeIf {
            it.isFinite() && it >= 0 && sample.speedAccuracyMetersPerSecond?.let { accuracy -> accuracy in 0.0..3.0 } == true
        }?.let { (it - requireNotNull(sample.speedAccuracyMetersPerSecond)).coerceAtLeast(0.0) }
        // Accumulate displacement against a fixed anchor to preserve slow climbs.
        if (position.distanceFrom(anchor) >= 3 || (minimumNativeSpeed != null && minimumNativeSpeed > stationarySpeedThreshold)) return baseline
        val candidate = candidateSeconds + delta
        return copy(
            candidateSeconds = candidate,
            lastActiveSeconds = activeSeconds,
            stoppedSeconds = stoppedSeconds + if (candidate >= 20) {
                if (candidateSeconds < 20) candidate else delta
            } else 0,
        )
    }

    fun suspend() = copy(candidateSeconds = 0, lastActiveSeconds = null, anchor = null)
}

@Serializable
data class MovingTimePosition(val latitude: Double, val longitude: Double) {
    fun distanceFrom(other: MovingTimePosition): Double {
        val radians = PI / 180
        val dLat = (latitude - other.latitude) * radians
        val dLon = (longitude - other.longitude) * radians
        val a = sin(dLat / 2).pow(2) + cos(latitude * radians) * cos(other.latitude * radians) * sin(dLon / 2).pow(2)
        return 6_371_000 * 2 * asin(sqrt(a.coerceIn(0.0, 1.0)))
    }
}
