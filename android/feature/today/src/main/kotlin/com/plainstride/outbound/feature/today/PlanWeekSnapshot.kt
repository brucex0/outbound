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
    val weekStart: LocalDate,
    val weekEnd: LocalDate,
    val isPartialWeek: Boolean,
) {
    private val required: List<PlannedWorkout> get() = workouts.filter { it.prescription?.get("optional")?.toString() != "true" }
    val targetSessions: Int get() = required.size
    val targetMinutes: Int get() = required.sumOf { ceil(it.durationSeconds / 60.0).toInt() }
    val pendingSessions: Int get() = required.count { it.status == "pending" }
    val completedSessions: Int get() = required.count { it.status == "completed" }
    val completedMinutes: Int get() = required.filter { it.status == "completed" }.sumOf { ceil(it.durationSeconds / 60.0).toInt() }
    val progress: Float get() = max(
        completedSessions.toFloat() / targetSessions.coerceAtLeast(1),
        completedMinutes.toFloat() / targetMinutes.coerceAtLeast(1),
    ).coerceIn(0f, 1f)
}

/** Account-local Monday buckets; logical workout dates never shift by timezone. */
internal fun PlanningState.planWeekSnapshot(
    today: LocalDate = LocalDate.now(calendar?.zone() ?: ZoneId.systemDefault()),
    zone: ZoneId = calendar?.zone() ?: ZoneId.systemDefault(),
): PlanWeekSnapshot? {
    val activePlan = plan ?: return null
    val created = activePlan.createdAt ?: goal?.createdAt ?: return null
    val start = try {
        calendar?.planStartDate?.let(LocalDate::parse) ?: Instant.parse(created).atZone(zone).toLocalDate()
    } catch (_: java.time.DateTimeException) {
        android.util.Log.w("PlainstridePlanning", "Plan week mapping failed category=invalid_creation_date")
        return null
    }
    val planMonday = start.with(java.time.temporal.TemporalAdjusters.previousOrSame(java.time.DayOfWeek.MONDAY))
    // A repository projection owns rollover; views use the period attached to its counts.
    val index = calendar?.planWeekIndex ?: ((ChronoUnit.DAYS.between(planMonday, today).coerceAtLeast(0) / 7).toInt() + 1)
    val weekStart = calendar?.let { Instant.parse(it.weekStart).atZone(zone).toLocalDate() }
        ?: planMonday.plusWeeks((index - 1).toLong())
    val weekEnd = calendar?.let { Instant.parse(it.weekEnd).atZone(zone).toLocalDate() } ?: weekStart.plusDays(7)
    val eventWeeks = goal?.targetDate?.let(::planningLogicalDate)?.let {
        ceil((ChronoUnit.DAYS.between(planMonday, it) + 1).coerceAtLeast(1) / 7.0).toInt()
    }
    val totalWeeks = if (activePlan.source == "generated") goal?.reviewHorizonWeeks ?: eventWeeks else eventWeeks
    return PlanWeekSnapshot(
        currentWeek = index,
        totalWeeks = totalWeeks,
        weekStart = weekStart,
        weekEnd = weekEnd,
        isPartialWeek = calendar?.isPartialWeek ?: (index == 1 && start.dayOfWeek != java.time.DayOfWeek.MONDAY),
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
