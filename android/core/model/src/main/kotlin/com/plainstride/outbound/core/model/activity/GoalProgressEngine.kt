package com.plainstride.outbound.core.model.activity

import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.math.ceil

enum class GoalKind { weeklySessions, weeklyMinutes }
enum class GoalFocusTheme { consistency, comeback, lightMovement }
enum class MotivationPhase { firstSession, steady, comeback, momentum, completedToday }

data class GoalDefinition(
    val kind: GoalKind,
    val theme: GoalFocusTheme,
    val targetValue: Int,
    val weekStart: Instant,
)

data class GoalProgressSnapshot(
    val currentValue: Int,
    val targetValue: Int,
    val percentComplete: Double,
    val isComplete: Boolean,
    val remainingValue: Int,
)

/** Progress semantics only. Localized summary and guide copy belongs to the presentation layer. */
object GoalProgressEngine {
    fun makeProgress(
        goal: GoalDefinition,
        activities: List<ActivityFacts>,
        addingSummary: ActivitySummaryFacts? = null,
        zoneId: ZoneId,
    ): GoalProgressSnapshot {
        val weekEnd = ZonedDateTime.ofInstant(goal.weekStart, zoneId).plusDays(7).toInstant()
        val inRange = activities.filter { !it.startedAt.isBefore(goal.weekStart) && it.startedAt.isBefore(weekEnd) }
        val baseValue = when (goal.kind) {
            GoalKind.weeklySessions -> inRange.size
            GoalKind.weeklyMinutes -> ceil(inRange.sumOf { it.durationSeconds } / 60.0).toInt()
        }
        val extraValue = when (goal.kind) {
            GoalKind.weeklySessions -> if (addingSummary == null) 0 else 1
            GoalKind.weeklyMinutes -> addingSummary?.let { ceil(it.durationSeconds / 60.0).toInt() } ?: 0
        }
        val currentValue = baseValue + extraValue
        return GoalProgressSnapshot(
            currentValue = currentValue,
            targetValue = goal.targetValue,
            percentComplete = minOf(1.0, if (goal.targetValue > 0) currentValue.toDouble() / goal.targetValue else 1.0),
            isComplete = currentValue >= goal.targetValue,
            remainingValue = maxOf(0, goal.targetValue - currentValue),
        )
    }

    fun suggestedTarget(
        theme: GoalFocusTheme,
        activities: List<ActivityFacts>,
        phase: MotivationPhase,
        weekStart: Instant,
        weekEnd: Instant,
    ): Int {
        val recentWeekCount = activities.count { !it.startedAt.isBefore(weekStart) && it.startedAt.isBefore(weekEnd) }
        return when (theme) {
            GoalFocusTheme.lightMovement -> if (recentWeekCount >= 3 || phase == MotivationPhase.momentum) 45 else 20
            GoalFocusTheme.comeback -> if (recentWeekCount >= 2) 3 else 2
            GoalFocusTheme.consistency -> when { phase == MotivationPhase.momentum -> 4; recentWeekCount >= 2 -> 3; else -> 2 }
        }
    }
}
