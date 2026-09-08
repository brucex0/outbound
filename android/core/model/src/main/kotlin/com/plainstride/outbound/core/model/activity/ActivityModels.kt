package com.plainstride.outbound.core.model.activity

import java.time.Instant
import kotlinx.serialization.Serializable

@Serializable
enum class ActivityType {
    running,
    cycling,
    hiking,
    walking,
    swimming,
}

data class ActivityFacts(
    val activityType: ActivityType,
    val startedAt: Instant,
    val durationSeconds: Int,
    val distanceMeters: Double,
    val averagePaceSecondsPerKilometer: Double? = null,
    val elevationGainMeters: Double = 0.0,
    val energyKilocalories: Int? = null,
)

data class ActivitySummaryFacts(
    val durationSeconds: Int,
    val distanceMeters: Double,
    val elevationGainMeters: Double = 0.0,
)
