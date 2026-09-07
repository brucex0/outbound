package run.plainstride.feature.today

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import java.util.Locale
import javax.inject.Inject
import run.plainstride.core.weather.R as WeatherR
import run.plainstride.core.weather.WeatherImpact
import run.plainstride.core.weather.WeatherRepository
import run.plainstride.core.weather.WeatherResult

interface TodayWeatherPolicy {
    /** Missing permission or provider data never mutates the planned workout. */
    suspend fun guidance(): TodayWeatherResult
}

sealed interface TodayWeatherResult {
    data class Available(val guidance: WeatherGuidance) : TodayWeatherResult
    data object PermissionRequired : TodayWeatherResult
    data object Unavailable : TodayWeatherResult
}

data class WeatherGuidance(
    val headline: String,
    val detail: String,
    val attribution: String,
    val attributionUrl: String,
    val unsafe: Boolean,
)

class DefaultTodayWeatherPolicy @Inject constructor(
    @param:ApplicationContext private val context: Context,
    private val repository: WeatherRepository,
) : TodayWeatherPolicy {
    override suspend fun guidance(): TodayWeatherResult = when (
        val result = repository.refresh(ACCOUNT_SCOPE, Locale.getDefault().toLanguageTag())
    ) {
        is WeatherResult.Available -> {
            val snapshot = result.snapshot
            TodayWeatherResult.Available(
                WeatherGuidance(
                    headline = context.getString(headlineResource(snapshot.headlineKey)),
                    detail = snapshot.guidanceKey?.let { context.getString(guidanceResource(it)) }
                        ?: snapshot.condition.replaceFirstChar { it.titlecase(Locale.getDefault()) },
                    attribution = context.getString(WeatherR.string.weather_attribution),
                    attributionUrl = snapshot.attribution.url,
                    unsafe = snapshot.impact == WeatherImpact.unsafe,
                ),
            )
        }
        WeatherResult.PermissionRequired -> TodayWeatherResult.PermissionRequired
        WeatherResult.LocationUnavailable, is WeatherResult.Failed -> TodayWeatherResult.Unavailable
    }

    private fun headlineResource(key: String): Int = when (key) {
        "weather.headline.unsafe" -> WeatherR.string.weather_headline_unsafe
        "weather.headline.heat" -> WeatherR.string.weather_headline_heat
        "weather.headline.cold" -> WeatherR.string.weather_headline_cold
        "weather.headline.wind" -> WeatherR.string.weather_headline_wind
        "weather.headline.slippery" -> WeatherR.string.weather_headline_slippery
        "weather.headline.rain" -> WeatherR.string.weather_headline_rain
        else -> WeatherR.string.weather_headline_good
    }

    private fun guidanceResource(key: String): Int = when (key) {
        "weather.guidance.unsafe" -> WeatherR.string.weather_guidance_unsafe
        "weather.guidance.heat" -> WeatherR.string.weather_guidance_heat
        "weather.guidance.cold" -> WeatherR.string.weather_guidance_cold
        "weather.guidance.wind" -> WeatherR.string.weather_guidance_wind
        "weather.guidance.slippery" -> WeatherR.string.weather_guidance_slippery
        else -> WeatherR.string.weather_guidance_rain
    }

    private companion object { const val ACCOUNT_SCOPE = "authenticated_account" }
}
