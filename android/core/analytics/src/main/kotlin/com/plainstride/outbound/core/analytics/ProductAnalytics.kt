package com.plainstride.outbound.core.analytics

enum class AnalyticsProperty(val wireName: String) {
    Source("source"),
    SourceType("source_type"),
    SelectionType("selection_type"),
    ChangeType("change_type"),
    Result("result"),
    Trigger("trigger"),
    ActivityType("activity_type"),
    GoalType("goal_type"),
    Permission("permission"),
    ErrorCategory("error_category"),
    CountBucket("count_bucket"),
    DurationBucket("duration_bucket"),
    DistanceBucket("distance_bucket"),
    PageDepthBucket("page_depth_bucket"),
    Locale("locale"),
    UnitSystem("unit_system"),
    Enabled("enabled"),
    Destination("destination"),
    EntrySource("entry_source"),
    Feature("feature"),
    Section("section"),
    Category("category"),
    VoiceGuideEnabled("voice_guide_enabled"),
    DogCompanionEnabled("dog_companion_enabled"),
    MomentType("moment_type"),
    CoachingContract("coaching_contract"),
    AudioMode("audio_mode"),
    AccessReason("access_reason"),
    LatencyBucket("latency_bucket"),
}

data class AnalyticsEvent(
    val name: String,
    val properties: Map<AnalyticsProperty, Any> = emptyMap(),
)

data class SanitizedAnalyticsEvent(
    val name: String,
    val properties: Map<String, Any>,
)

interface AnalyticsSink {
    fun setUserId(userId: String?)
    fun record(event: SanitizedAnalyticsEvent)
}

class ProductAnalytics(
    private val sink: AnalyticsSink,
) {
    @Volatile
    private var hasValidUserId = false

    @Synchronized
    fun setUserId(userId: String?) {
        val validUserId = userId?.takeIf(String::isNotBlank)?.take(MAX_USER_ID_LENGTH)
        hasValidUserId = false
        sink.setUserId(validUserId)
        hasValidUserId = validUserId != null
    }

    fun record(event: AnalyticsEvent) {
        if (!hasValidUserId) return
        val safeName = event.name.takeIf(EVENT_NAME::matches) ?: return
        val safeProperties = buildMap {
            put("platform", "android")
            event.properties.forEach { (key, rawValue) ->
                sanitize(key, rawValue)?.let { put(key.wireName, it) }
            }
        }
        sink.record(SanitizedAnalyticsEvent(safeName, safeProperties))
    }

    private fun sanitize(property: AnalyticsProperty, value: Any): Any? = when (value) {
        is Boolean -> value
        is Int -> value.coerceIn(-1_000, 1_000)
        is Long -> value.coerceIn(-1_000, 1_000)
        is String -> value.take(MAX_VALUE_LENGTH).takeIf {
            if (property == AnalyticsProperty.Locale) LOCALE_VALUE.matches(it) else SAFE_VALUE.matches(it)
        }
        else -> null
    }

    private companion object {
        const val MAX_VALUE_LENGTH = 40
        const val MAX_USER_ID_LENGTH = 256
        val EVENT_NAME = Regex("[a-z][a-z0-9_]{1,39}")
        val SAFE_VALUE = Regex("[a-z0-9_\\-]{1,40}")
        val LOCALE_VALUE = Regex("[a-z]{2,3}(?:-[A-Za-z]{2,8}){0,2}")
    }
}
