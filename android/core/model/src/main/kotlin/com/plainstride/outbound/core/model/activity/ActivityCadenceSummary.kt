package com.plainstride.outbound.core.model.activity

import kotlinx.serialization.Serializable

/** Matches the private iOS cadence client-data payload. */
@Serializable
data class ActivityCadenceSummary(
    val averageStepsPerMinute: Int? = null,
    val maxStepsPerMinute: Int? = null,
    val samples: List<ActivityCadenceSample> = emptyList(),
)

@Serializable
data class ActivityCadenceSample(val elapsedSeconds: Int, val stepsPerMinute: Int, val segment: Int)
