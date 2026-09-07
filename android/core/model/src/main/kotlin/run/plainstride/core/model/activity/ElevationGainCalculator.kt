package run.plainstride.core.model.activity

import kotlin.math.abs
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

data class ElevationLocation(
    val latitude: Double,
    val longitude: Double,
    val altitudeMeters: Double,
    val verticalAccuracyMeters: Double,
    val timestampMillis: Long,
)

object ElevationGainCalculator {
    private const val MAXIMUM_VERTICAL_ACCURACY_METERS = 20.0
    private const val MAXIMUM_VERTICAL_SPEED_METERS_PER_SECOND = 3.0
    private const val MINIMUM_DISTANCE_FOR_GRADE_CHECK_METERS = 3.0
    private const val MAXIMUM_GRADE = 0.50
    private const val MEDIAN_WINDOW_SIZE = 5

    class StreamingRangeAccumulator {
        private var previousAcceptedLocation: ElevationLocation? = null
        private val altitudeWindow = ArrayDeque<Double>()
        private var minimumFilteredAltitude: Double? = null
        private var maximumFilteredAltitude: Double? = null
        private var climbFloorAltitude: Double? = null
        private var climbPeakAltitude: Double? = null
        private var committedGainMeters = 0.0

        var rangeMeters: Double = 0.0
            private set
        var gainMeters: Double = 0.0
            private set

        fun reset() {
            previousAcceptedLocation = null
            altitudeWindow.clear()
            minimumFilteredAltitude = null
            maximumFilteredAltitude = null
            climbFloorAltitude = null
            climbPeakAltitude = null
            committedGainMeters = 0.0
            rangeMeters = 0.0
            gainMeters = 0.0
        }

        fun startNewSegment() {
            val activeClimb = max(0.0, (climbPeakAltitude ?: 0.0) - (climbFloorAltitude ?: 0.0))
            if (activeClimb >= 2.5) committedGainMeters += activeClimb
            previousAcceptedLocation = null
            altitudeWindow.clear()
            climbFloorAltitude = null
            climbPeakAltitude = null
            gainMeters = committedGainMeters
        }

        fun ingest(location: ElevationLocation) {
            if (!location.altitudeMeters.isFinite() || location.verticalAccuracyMeters !in 0.0..MAXIMUM_VERTICAL_ACCURACY_METERS) return
            previousAcceptedLocation?.let { if (!isPlausibleTransition(it, location)) return }
            previousAcceptedLocation = location
            altitudeWindow.addLast(location.altitudeMeters)
            if (altitudeWindow.size > MEDIAN_WINDOW_SIZE) altitudeWindow.removeFirst()
            val sorted = altitudeWindow.sorted()
            val filteredAltitude = sorted[sorted.size / 2]
            minimumFilteredAltitude = min(minimumFilteredAltitude ?: filteredAltitude, filteredAltitude)
            maximumFilteredAltitude = max(maximumFilteredAltitude ?: filteredAltitude, filteredAltitude)
            rangeMeters = max(0.0, (maximumFilteredAltitude ?: 0.0) - (minimumFilteredAltitude ?: 0.0))
            ingestFilteredAltitude(filteredAltitude)
        }

        private fun ingestFilteredAltitude(altitude: Double) {
            val floor = climbFloorAltitude
            val peak = climbPeakAltitude
            if (floor == null || peak == null) {
                climbFloorAltitude = altitude
                climbPeakAltitude = altitude
                return
            }
            if (altitude > peak) {
                climbPeakAltitude = altitude
            } else if (peak - altitude >= 2.5) {
                val completedClimb = peak - floor
                if (completedClimb >= 2.5) committedGainMeters += completedClimb
                climbFloorAltitude = altitude
                climbPeakAltitude = altitude
            } else if (altitude < floor) {
                climbFloorAltitude = altitude
                climbPeakAltitude = max(peak, altitude)
            }
            val activeClimb = max(0.0, (climbPeakAltitude ?: altitude) - (climbFloorAltitude ?: altitude))
            gainMeters = committedGainMeters + if (activeClimb >= 2.5) activeClimb else 0.0
        }
    }

    fun sanitizedElevationGainMeters(locations: List<ElevationLocation>): Double =
        StreamingRangeAccumulator().also { accumulator -> locations.forEach(accumulator::ingest) }.gainMeters

    fun sanitizedElevationRangeMeters(locations: List<ElevationLocation>): Double {
        val altitudes = sanitizedAltitudes(locations)
        val minimum = altitudes.minOrNull() ?: return 0.0
        val maximum = altitudes.maxOrNull() ?: return 0.0
        return if (maximum > minimum) maximum - minimum else 0.0
    }

    fun sanitizedAltitudes(locations: List<ElevationLocation>): List<Double> {
        val accepted = buildList {
            var previous: ElevationLocation? = null
            locations.forEach { location ->
                if (!location.altitudeMeters.isFinite() || location.verticalAccuracyMeters !in 0.0..MAXIMUM_VERTICAL_ACCURACY_METERS) return@forEach
                val previousLocation = previous
                if (previousLocation != null && !isPlausibleTransition(previousLocation, location)) return@forEach
                add(location.altitudeMeters)
                previous = location
            }
        }
        if (accepted.size < 2) return accepted
        return rollingMedian(accepted, MEDIAN_WINDOW_SIZE)
    }

    private fun isPlausibleTransition(previous: ElevationLocation, current: ElevationLocation): Boolean {
        val altitudeDelta = abs(current.altitudeMeters - previous.altitudeMeters)
        val durationSeconds = (current.timestampMillis - previous.timestampMillis) / 1_000.0
        if (durationSeconds > 0.0 && altitudeDelta / durationSeconds > MAXIMUM_VERTICAL_SPEED_METERS_PER_SECOND) return false
        val distanceMeters = haversineDistanceMeters(previous, current)
        if (distanceMeters >= MINIMUM_DISTANCE_FOR_GRADE_CHECK_METERS && altitudeDelta / distanceMeters > MAXIMUM_GRADE) return false
        return true
    }

    private fun rollingMedian(values: List<Double>, windowSize: Int): List<Double> {
        if (windowSize <= 1 || values.size <= 2) return values
        val radius = windowSize / 2
        return values.indices.map { index ->
            val lower = max(0, index - radius)
            val upper = min(values.size, index + radius + 1)
            values.subList(lower, upper).sorted()[((upper - lower) / 2)]
        }
    }

    private fun haversineDistanceMeters(first: ElevationLocation, second: ElevationLocation): Double {
        val latitudeDelta = Math.toRadians(second.latitude - first.latitude)
        val longitudeDelta = Math.toRadians(second.longitude - first.longitude)
        val firstLatitude = Math.toRadians(first.latitude)
        val secondLatitude = Math.toRadians(second.latitude)
        val a = sin(latitudeDelta / 2) * sin(latitudeDelta / 2) +
            cos(firstLatitude) * cos(secondLatitude) * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        return 6_371_000.0 * 2.0 * asin(sqrt(a))
    }
}
