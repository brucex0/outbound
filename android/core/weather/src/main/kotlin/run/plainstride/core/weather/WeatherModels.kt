package run.plainstride.core.weather

import kotlinx.serialization.Serializable

@Serializable
enum class WeatherImpact { none, advisory, caution, unsafe }

@Serializable
data class WeatherAttribution(
    val provider: String,
    val text: String,
    val url: String,
    val license: String,
    val modified: Boolean,
)

@Serializable
data class RunningWeatherSnapshot(
    val fetchedAt: String,
    val placeName: String? = null,
    val symbolName: String,
    val condition: String,
    val temperatureCelsius: Double,
    val apparentTemperatureCelsius: Double,
    val windKilometersPerHour: Double,
    val precipitationChance: Double,
    val impact: WeatherImpact,
    val headlineKey: String,
    val guidanceKey: String? = null,
    val bestWindowStart: String? = null,
    val attribution: WeatherAttribution,
)

data class ApproximateLocation(
    val latitude: Double,
    val longitude: Double,
    val altitudeMeters: Double?,
) {
    fun rounded(): ApproximateLocation = copy(
        latitude = roundedCoordinate(latitude),
        longitude = roundedCoordinate(longitude),
        altitudeMeters = altitudeMeters?.let { kotlin.math.round(it) },
    )

    private fun roundedCoordinate(value: Double): Double = kotlin.math.round(value * 100.0) / 100.0
}

sealed interface WeatherResult {
    data class Available(val snapshot: RunningWeatherSnapshot, val source: Source) : WeatherResult
    data object PermissionRequired : WeatherResult
    data object LocationUnavailable : WeatherResult
    data class Failed(val cached: RunningWeatherSnapshot?) : WeatherResult

    enum class Source { MemoryCache, DiskCache, Network, StaleCache }
}
