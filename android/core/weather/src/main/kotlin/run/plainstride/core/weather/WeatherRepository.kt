package run.plainstride.core.weather

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import java.security.MessageDigest
import kotlinx.coroutines.flow.first
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import run.plainstride.core.analytics.AnalyticsEvent
import run.plainstride.core.analytics.AnalyticsProperty
import run.plainstride.core.analytics.ProductAnalytics
import run.plainstride.core.network.AccessTokenProvider

interface WeatherRepository {
    suspend fun refresh(accountId: String, locale: String, force: Boolean = false): WeatherResult
}

class DefaultWeatherRepository(
    private val locationSource: WeatherLocationSource,
    private val api: WeatherApiService,
    private val accessTokens: AccessTokenProvider,
    private val dataStore: DataStore<Preferences>,
    private val analytics: ProductAnalytics,
    private val nowEpochMilliseconds: () -> Long = System::currentTimeMillis,
) : WeatherRepository {
    private var memoryCache: CachedSnapshot? = null

    override suspend fun refresh(accountId: String, locale: String, force: Boolean): WeatherResult {
        if (!locationSource.hasPermission()) {
            record("weather_permission_needed")
            return WeatherResult.PermissionRequired
        }
        val location = locationSource.currentApproximateLocation()?.rounded()
            ?: return WeatherResult.LocationUnavailable.also { record("weather_location_unavailable") }
        val key = cacheKey(accountId, locale, location)
        val cached = memoryCache?.takeIf { it.key == key } ?: diskCache()?.takeIf { it.key == key }
        if (!force && cached?.isFresh(nowEpochMilliseconds()) == true) {
            val source = if (cached === memoryCache) WeatherResult.Source.MemoryCache else WeatherResult.Source.DiskCache
            memoryCache = cached
            record("weather_loaded", "cache")
            return WeatherResult.Available(cached.snapshot, source)
        }
        val token = accessTokens.validAccessToken()
            ?: return WeatherResult.Failed(cached?.snapshot).also { record("weather_load_failed", "unauthenticated") }
        return try {
            val response = api.current(
                authorization = "Bearer $token",
                locale = locale,
                latitude = location.latitude,
                longitude = location.longitude,
                altitudeMeters = location.altitudeMeters?.toInt(),
                force = force.takeIf { it },
            )
            if (!response.isSuccessful) error("http_${response.code()}")
            val snapshot = requireNotNull(response.body())
            val entry = CachedSnapshot(key, nowEpochMilliseconds(), snapshot)
            memoryCache = entry
            dataStore.edit { it[CACHE] = Json.encodeToString(entry) }
            record("weather_loaded", "network")
            WeatherResult.Available(snapshot, WeatherResult.Source.Network)
        } catch (_: Exception) {
            record("weather_load_failed", if (cached == null) "network" else "stale_cache")
            cached?.let { WeatherResult.Available(it.snapshot, WeatherResult.Source.StaleCache) }
                ?: WeatherResult.Failed(null)
        }
    }

    private suspend fun diskCache(): CachedSnapshot? = dataStore.data.first()[CACHE]?.let {
        runCatching { Json.decodeFromString<CachedSnapshot>(it) }.getOrNull()
    }

    private fun record(name: String, result: String? = null) {
        analytics.record(AnalyticsEvent(name, result?.let { mapOf(AnalyticsProperty.Result to it) }.orEmpty()))
    }

    private fun cacheKey(accountId: String, locale: String, location: ApproximateLocation): String {
        val input = "$accountId|$locale|${location.latitude}|${location.longitude}|${location.altitudeMeters ?: ""}"
        return MessageDigest.getInstance("SHA-256").digest(input.toByteArray()).joinToString("") { "%02x".format(it) }
    }

    @Serializable
    private data class CachedSnapshot(val key: String, val storedAt: Long, val snapshot: RunningWeatherSnapshot) {
        fun isFresh(now: Long): Boolean = now - storedAt in 0 until CACHE_TTL_MILLIS
    }

    private companion object {
        val CACHE = stringPreferencesKey("weather_snapshot_v1")
        const val CACHE_TTL_MILLIS = 30 * 60 * 1_000L
    }
}
