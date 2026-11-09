package com.plainstride.outbound.feature.today

import com.plainstride.outbound.core.model.PlannedWorkout
import com.plainstride.outbound.core.model.PlanningState
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import kotlin.math.ceil
import kotlin.math.max

internal data class PlanWeekSnapshot(
    val currentWeek: Int,
    val totalWeeks: Int?,
    val workouts: List<PlannedWorkout>,
) {
    val targetSessions: Int get() = workouts.size
    val targetMinutes: Int get() = workouts.sumOf { ceil(it.durationSeconds / 60.0).toInt() }
    val completedSessions: Int get() = workouts.count { it.status == "completed" }
    val completedMinutes: Int get() = workouts.filter { it.status == "completed" }.sumOf { ceil(it.durationSeconds / 60.0).toInt() }
    val progress: Float get() = max(
        completedSessions.toFloat() / targetSessions.coerceAtLeast(1),
        completedMinutes.toFloat() / targetMinutes.coerceAtLeast(1),
    ).coerceIn(0f, 1f)
}

/** Creation-anchored seven-day blocks; logical workout dates never shift by timezone. */
internal fun PlanningState.planWeekSnapshot(
    today: LocalDate = LocalDate.now(),
    zone: ZoneId = ZoneId.systemDefault(),
): PlanWeekSnapshot? {
    val activePlan = plan ?: return null
    val created = activePlan.createdAt ?: goal?.createdAt ?: return null
    val start = try {
        Instant.parse(created).atZone(zone).toLocalDate()
    } catch (_: java.time.DateTimeException) {
        android.util.Log.w("PlainstridePlanning", "Plan week mapping failed category=invalid_creation_date")
        return null
    }
    val index = (ChronoUnit.DAYS.between(start, today).coerceAtLeast(0) / 7).toInt() + 1
    val weekStart = start.plusWeeks((index - 1).toLong())
    val weekEnd = weekStart.plusDays(7)
    val eventWeeks = goal?.targetDate?.let(::planningLogicalDate)?.let {
        ceil((ChronoUnit.DAYS.between(start, it) + 1).coerceAtLeast(1) / 7.0).toInt()
    }
    val totalWeeks = if (activePlan.source == "generated") goal?.reviewHorizonWeeks ?: eventWeeks else eventWeeks
    return PlanWeekSnapshot(
        currentWeek = totalWeeks?.let { index.coerceAtMost(it) } ?: index,
        totalWeeks = totalWeeks,
        workouts = workouts.filter { workout ->
            planningLogicalDate(workout.scheduledDate)?.let { it >= weekStart && it < weekEnd } == true
        }.sortedBy { it.scheduledDate },
    )
}

internal fun planningLogicalDate(value: String): LocalDate? = try {
    LocalDate.parse(value.take(10))
} catch (_: java.time.DateTimeException) {
    android.util.Log.w("PlainstridePlanning", "Plan week mapping failed category=invalid_logical_date")
    null
}
