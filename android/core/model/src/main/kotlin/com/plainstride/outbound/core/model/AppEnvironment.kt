package com.plainstride.outbound.core.model

import android.os.SystemClock

enum class AppEnvironment { Development, Staging, Production }

/** Wall time for protocol timestamps and persisted expiry instants. */
fun interface EpochClock { fun nowEpochMilliseconds(): Long }

object SystemEpochClock : EpochClock {
    override fun nowEpochMilliseconds(): Long = System.currentTimeMillis()
}

/** Monotonic elapsed time for durations, cooldowns, and retry windows. */
fun interface MonotonicClock { fun elapsedRealtimeMilliseconds(): Long }

object AndroidMonotonicClock : MonotonicClock {
    override fun elapsedRealtimeMilliseconds(): Long = SystemClock.elapsedRealtime()
}

interface FeatureFlags { val debugIdentityEnabled: Boolean }

data class StaticFeatureFlags(
    override val debugIdentityEnabled: Boolean,
) : FeatureFlags

enum class AppLocale(val apiValue: String) {
    English("en"),
    Spanish("es"),
    SimplifiedChinese("zh-Hans");

    companion object {
        fun fromLanguageTag(tag: String): AppLocale = when (tag.lowercase()) {
            "es", "es-es", "es-419" -> Spanish
            "zh", "zh-cn", "zh-sg", "zh-hans", "zh-hans-cn", "zh-hans-sg" -> SimplifiedChinese
            else -> English
        }
    }
}
