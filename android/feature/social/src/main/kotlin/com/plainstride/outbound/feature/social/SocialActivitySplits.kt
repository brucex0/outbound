package com.plainstride.outbound.feature.social

import android.util.Log
import com.plainstride.outbound.core.model.activity.MeasurementUnitSystem
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.decodeFromJsonElement

@Serializable
internal data class RecordedSocialSplit(
    val number: Int,
    val distanceMeters: Double,
    val timeSeconds: Double,
    val elevationChangeM: Double? = null,
) {
    val paceSecondsPerKm: Double get() = timeSeconds / distanceMeters * 1_000.0
}

@Serializable
private data class RecordedSocialSplits(
    val metric: List<RecordedSocialSplit>,
    val imperial: List<RecordedSocialSplit>,
)

private val splitJson = Json { ignoreUnknownKeys = true }

// Map previews have no recorded point timestamps. Use the full-route summaries
// from the server, including when the route JSON is restored from offline cache.
internal fun JsonElement?.recordedSocialSplits(unitSystem: MeasurementUnitSystem): List<RecordedSocialSplit> {
    val payload = (this as? JsonObject)?.get("splits") ?: return emptyList()
    val recorded = try {
        splitJson.decodeFromJsonElement<RecordedSocialSplits>(payload)
    } catch (error: SerializationException) {
        Log.w("PlainstrideSocial", "Recorded splits decode failed type=${error.javaClass.simpleName}")
        return emptyList()
    }
    val splits = if (unitSystem == MeasurementUnitSystem.metric) recorded.metric else recorded.imperial
    if (splits.any { it.number <= 0 || !it.distanceMeters.isFinite() || it.distanceMeters <= 0
            || !it.timeSeconds.isFinite() || it.timeSeconds < 0 || !it.paceSecondsPerKm.isFinite() }) {
        Log.w("PlainstrideSocial", "Recorded splits validation failed unit=${unitSystem.name}")
        return emptyList()
    }
    return splits
}
