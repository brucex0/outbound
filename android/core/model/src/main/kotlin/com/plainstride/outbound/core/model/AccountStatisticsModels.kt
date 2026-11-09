package com.plainstride.outbound.core.model

/** Complete account statistics; independent of prescribed-workout completion. */
data class WeeklyRunGoal(
    val completedRuns: Int,
    val targetRuns: Int?,
    val scheduledRunsByToday: Int?,
)
