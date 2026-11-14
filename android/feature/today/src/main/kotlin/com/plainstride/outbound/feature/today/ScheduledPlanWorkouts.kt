package com.plainstride.outbound.feature.today

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.RemoveCircleOutline
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.plainstride.outbound.core.model.ActivitySuggestion
import com.plainstride.outbound.core.model.ActivitySuggestionEnvelope
import com.plainstride.outbound.core.model.Modality
import com.plainstride.outbound.core.model.PlannedWorkout
import com.plainstride.outbound.core.model.PlanningState
import com.plainstride.outbound.core.model.TrainingStimulus
import com.plainstride.outbound.core.model.activity.MeasurementUnitSystem
import com.plainstride.outbound.core.model.activity.SessionFormatting
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.intOrNull
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.temporal.ChronoUnit
import java.time.temporal.TemporalAdjusters
import java.util.Locale

private val dateFormat: DateTimeFormatter get() = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)
private val fullDateFormat: DateTimeFormatter get() = DateTimeFormatter.ofLocalizedDate(FormatStyle.FULL)

internal val PlannedWorkout.isOptional: Boolean get() = prescription?.get("optional")?.toString() == "true"
private val PlannedWorkout.isOptionalMobility: Boolean get() = isOptional && (modality == Modality.mobility || stimulus == TrainingStimulus.mobility)

/** An optional add-on keeps its own prescription/status and belongs to only the first primary. */
internal fun PlanningState.optionalMobilityFor(workout: PlannedWorkout): List<PlannedWorkout> {
    val day = planningLogicalDate(workout.scheduledDate) ?: return emptyList()
    val sameDay = workouts.filter { planningLogicalDate(it.scheduledDate) == day }
    if (sameDay.firstOrNull { !it.isOptionalMobility }?.id != workout.id) return emptyList()
    return sameDay.filter { it.isOptionalMobility }
}

private data class IssuedWeek(val monday: LocalDate?, val number: Int?, val workouts: List<PlannedWorkout>)

private fun PlanningState.issuedWeeks(): List<IssuedWeek> {
    val zone = calendar?.zone() ?: ZoneId.systemDefault()
    val anchor = calendar?.planStartDate?.let(::planningLogicalDate)
        ?: (plan?.createdAt ?: goal?.createdAt)?.let { value ->
            try { Instant.parse(value).atZone(zone).toLocalDate() } catch (_: java.time.DateTimeException) {
                android.util.Log.w("PlainstridePlanning", "Plan schedule grouping failed category=invalid_creation_date")
                null
            }
        }
    val planMonday = anchor?.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
    return workouts.groupBy { planningLogicalDate(it.scheduledDate)?.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY)) }
        .entries.sortedWith(compareBy(nullsLast()) { it.key }).map { (monday, rows) ->
            IssuedWeek(monday, if (monday != null && planMonday != null) (ChronoUnit.WEEKS.between(planMonday, monday).toInt() + 1).coerceAtLeast(1) else null,
                rows.sortedBy { it.scheduledDate })
        }
}

@Composable
internal fun IssuedPlanSchedule(
    planning: PlanningState,
    todaySuggestion: ActivitySuggestionEnvelope?,
    today: LocalDate,
    units: MeasurementUnitSystem,
    onOpen: (PlannedWorkout) -> Unit,
) {
    planning.issuedWeeks().forEach { week ->
        Column(Modifier.fillMaxWidth().padding(top = 6.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            val range = week.monday?.let { "${it.format(dateFormat)}–${it.plusDays(6).format(dateFormat)}" }
            Text(
                when {
                    range == null -> stringResource(R.string.plan_workout_undated)
                    week.number != null -> stringResource(R.string.plan_workout_week, week.number, range)
                    else -> range
                },
                Modifier.semantics { heading() },
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            week.workouts.groupBy { planningLogicalDate(it.scheduledDate)?.toString() ?: "undated-${it.id}" }.forEach { (_, day) ->
                val primary = day.filterNot { it.isOptionalMobility }
                (primary.ifEmpty { day }).forEach { workout ->
                    val adapted = todaySuggestion?.primary?.takeIf { workout.isFor(today) && it.plannedWorkoutId == workout.id }
                    ScheduledWorkoutRow(workout, adapted, units) { onOpen(workout) }
                }
            }
        }
    }
}

@Composable
private fun ScheduledWorkoutRow(workout: PlannedWorkout, adapted: ActivitySuggestion?, units: MeasurementUnitSystem, onOpen: () -> Unit) {
    val openHint = stringResource(R.string.plan_workout_open_hint)
    Row(
        Modifier.fillMaxWidth().clickable(role = Role.Button, onClickLabel = openHint, onClick = onOpen)
            .semantics(mergeDescendants = true) {}.heightIn(min = 64.dp).padding(vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val date = planningLogicalDate(workout.scheduledDate)
        val spokenDate = date?.format(fullDateFormat) ?: stringResource(R.string.plan_workout_date_unavailable)
        Column(
            Modifier.widthIn(min = 54.dp).heightIn(min = 60.dp)
                .background(MaterialTheme.colorScheme.surfaceContainer, RoundedCornerShape(12.dp))
                .padding(horizontal = 8.dp, vertical = 8.dp).clearAndSetSemantics { contentDescription = spokenDate },
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            if (date != null) {
                Text(date.format(DateTimeFormatter.ofPattern("EEE", Locale.getDefault())), style = MaterialTheme.typography.labelLarge)
                Text(date.format(DateTimeFormatter.ofPattern("d", Locale.getDefault())), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            } else Icon(Icons.Default.CalendarMonth, null)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(adapted?.effectiveWorkout?.title ?: adapted?.title ?: workout.title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
            Text(workoutTargetLine(workout, adapted, units), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (workout.isOptional) Text(stringResource(R.string.today_race_goal_optional), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        WorkoutStatusIcon(workout.status)
        Icon(Icons.Default.ChevronRight, null, Modifier.size(20.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
internal fun CompactPlanPhaseSummary(planning: PlanningState, today: LocalDate, onShown: () -> Unit) {
    val roadmap = planning.roadmap ?: return
    val phases = roadmap.phases.filter { planningLogicalDate(it.endDate)?.let { end -> end >= today } == true }
    if (phases.isEmpty()) return
    LaunchedEffect(planning.plan?.id) { onShown() }
    PlanSectionCard(stringResource(R.string.plan_workout_training_phases)) {
        phases.forEach { phase ->
            val start = planningLogicalDate(phase.startDate)
            val end = planningLogicalDate(phase.endDate)
            val issuedDates = planning.workouts.filterNot { it.isOptional }.mapNotNull { planningLogicalDate(it.scheduledDate) }
                .filter { start != null && end != null && it >= start && it <= end }
            val first = issuedDates.minOrNull()
            val last = issuedDates.maxOrNull()
            Column(Modifier.semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(stringResource(phaseLabel(phase.phase)), style = MaterialTheme.typography.bodyLarge,
                    fontWeight = if (phase.phase == roadmap.currentPhase) FontWeight.SemiBold else FontWeight.Normal)
                Text(
                    when {
                        first != null && last != null -> stringResource(R.string.plan_workout_phase_scheduled,
                            if (first == last) first.format(dateFormat) else "${first.format(dateFormat)}–${last.format(dateFormat)}")
                        start != null && start > today -> stringResource(R.string.plan_workout_phase_later)
                        else -> stringResource(R.string.plan_workout_phase_empty)
                    },
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

/** A separate dialog leaves the sheet and its scroll state composed underneath. */
@Composable
internal fun ScheduledPlanWorkoutPage(
    workout: PlannedWorkout,
    suggestion: ActivitySuggestionEnvelope?,
    mobility: List<PlannedWorkout>,
    adjustment: String?,
    units: MeasurementUnitSystem,
    onBack: () -> Unit,
    onDone: () -> Unit,
    onChangeWorkout: (() -> Unit)?,
    busy: Boolean,
) {
    val adapted = suggestion?.primary
    PlanPage(title = stringResource(R.string.plan_workout_title), onDismiss = onBack, onBack = onBack, onDone = onDone, contentSpacing = 24.dp) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top) {
                Text(adapted?.effectiveWorkout?.title ?: adapted?.title ?: workout.title, Modifier.weight(1f), style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
                WorkoutStatusIcon(workout.status)
            }
            Text(planningLogicalDate(workout.scheduledDate)?.format(fullDateFormat) ?: stringResource(R.string.plan_workout_date_unavailable), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(workoutTargetLine(workout, adapted, units), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
            if (workout.isOptional) Text(stringResource(R.string.today_race_goal_optional), style = MaterialTheme.typography.bodyLarge)
            if (workout.status !in setOf("planned", "completed")) Text(stringResource(statusLabel(workout.status)), color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (suggestion != null && adapted != null) Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            suggestion.guideLine.takeIf { it.isNotBlank() }?.let { Text(it, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            adapted.why.takeIf { it.isNotBlank() && it != suggestion.guideLine }?.let { Text(it, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            if (suggestion.relationship == "adjustedFromPlan") {
                // Backend adjustment keys are not display prose. The localized suggestion
                // already supplies the current reason when no human-readable message exists.
                adjustment?.takeIf { it.isNotBlank() && !it.startsWith("today.") && it != suggestion.guideLine && it != adapted.why }?.let {
                    Text(it, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.primary)
                }
            }
            onChangeWorkout?.let { change -> TextButton(onClick = change, enabled = !busy) { Text(stringResource(R.string.today_change_workout)) } }
        }
        val summary = if (adapted != null) adapted.effectiveWorkout?.detail else workoutDescription(workout)
        summary?.takeIf { it.isNotBlank() && it != suggestion?.guideLine && it != adapted?.why }?.let { Text(it, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        val phases = workout.detailPhases(adapted)
        WorkoutPhaseCards(phases, units)
        if (mobility.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(stringResource(R.string.plan_workout_optional_mobility), Modifier.semantics { heading() }, style = MaterialTheme.typography.titleLarge)
                mobility.forEach { support ->
                    PlanSectionCard(support.title) {
                        WorkoutStatusIcon(support.status)
                        Text(workoutTargetLine(support, null, units), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        if (support.status !in setOf("planned", "completed")) Text(stringResource(statusLabel(support.status)), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        workoutDescription(support)?.let { Text(it, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                        WorkoutPhaseCards(support.detailPhases(null), units)
                    }
                }
            }
        }
    }
}

private data class DetailPhase(val label: String, val durationSeconds: Int?, val distanceMeters: Double? = null, val detail: String?, val target: JsonObject? = null, val rpe: IntRange? = null)

private fun PlannedWorkout.detailPhases(adapted: ActivitySuggestion?): List<DetailPhase> {
    // Open calorie/distance catalog goals do not promise a timed execution recipe.
    if ((if (adapted != null) adapted.targetCalories else targetCalories) != null) return emptyList()
    if (adapted != null) {
        val effective = adapted.effectiveWorkout
        if (effective?.targetDistanceMeters != null) return emptyList()
        if (effective != null) return effective.steps.map { step ->
            val effort = effective.guideInstructions.segments.firstOrNull { it.id == step.id }?.effort
            val coaching = step.coachingTarget
            val pace = coaching?.pace
            val target = if (coaching?.paceEstimatePolicy == "reported-maximal-running-v1" && pace != null) JsonObject(mapOf(
                "paceEstimatePolicy" to JsonPrimitive(coaching.paceEstimatePolicy),
                "pace" to JsonObject(buildMap {
                    pace.targetSecondsPerKilometer?.let { put("targetSecondsPerKilometer", JsonPrimitive(it)) }
                    put("fasterToleranceSeconds", JsonPrimitive(pace.fasterToleranceSeconds))
                    pace.slowerToleranceSeconds?.let { put("slowerToleranceSeconds", JsonPrimitive(it)) }
                }),
            )) else null
            DetailPhase(step.label, step.durationSeconds, detail = step.detail, target = target,
                rpe = effort?.takeIf { it.rpeMin in 1..10 && it.rpeMax in it.rpeMin..10 }?.let { it.rpeMin..it.rpeMax })
        }
        // Authored prose steps have no exact timing: do not invent equal phase durations.
        return adapted.steps.map { DetailPhase(it, null, detail = null) }
    }
    return blocks.flatMap { block ->
        if (block.steps.isEmpty()) listOf(DetailPhase("", block.durationSeconds, block.distanceMeters, null))
        // A block total is not an exact duration for each untimed child step.
        else block.steps.map { step -> DetailPhase(step.label, step.durationSeconds, step.distanceMeters, step.detail, step.target, step.target.rpeRange()) }
    }
}

private fun JsonObject?.rpeRange(): IntRange? {
    val value = this?.get("rpe")
    val numbers = if (value is JsonArray) value.mapNotNull { (it as? JsonPrimitive)?.intOrNull } else listOfNotNull((value as? JsonPrimitive)?.intOrNull)
    val low = numbers.firstOrNull() ?: (this?.get("min") as? JsonPrimitive)?.intOrNull ?: return null
    val high = numbers.lastOrNull() ?: (this?.get("max") as? JsonPrimitive)?.intOrNull ?: low
    return (low..high).takeIf { low in 1..10 && high in low..10 }
}

@Composable
private fun WorkoutPhaseCards(phases: List<DetailPhase>, units: MeasurementUnitSystem) {
    if (phases.isEmpty()) return
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(stringResource(R.string.today_phases), Modifier.semantics { heading() }, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
        if (phases.any { it.rpe != null }) Text(stringResource(R.string.plan_workout_effort_scale), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        phases.forEachIndexed { index, phase ->
            Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(16.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLowest)) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(phase.label.ifBlank { stringResource(R.string.plan_details_step, index + 1) }, style = MaterialTheme.typography.titleMedium)
                        val dose = listOfNotNull(phase.durationSeconds?.takeIf { it > 0 }?.let { workoutDuration(it) }, phase.distanceMeters?.let { workoutDistance(it, units) }).joinToString(" · ")
                        if (dose.isNotBlank()) Text(dose, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
                    }
                    phase.detail?.takeIf { it.isNotBlank() }?.let { Text(it, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                    phase.target?.let { PhasePace(it, units) }
                    phase.rpe?.let { range ->
                        Text(stringResource(if (range.last <= 3) R.string.plan_workout_effort_easy else R.string.plan_workout_effort_range, range.first, range.last), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}

@Composable
private fun PhasePace(target: JsonObject, units: MeasurementUnitSystem) {
    val (lower, upper) = estimatedPhasePace(target, units) ?: return
    val unit = stringResource(if (units == MeasurementUnitSystem.metric) R.string.benchmark_per_km else R.string.benchmark_per_mile)
    val faster = String.format(Locale.getDefault(), "%d:%02d%s", lower.minutes, lower.seconds, unit)
    val slower = String.format(Locale.getDefault(), "%d:%02d%s", upper.minutes, upper.seconds, unit)
    Text(stringResource(R.string.plan_workout_pace_range, faster, slower), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

@Composable
private fun workoutTargetLine(workout: PlannedWorkout, adapted: ActivitySuggestion?, units: MeasurementUnitSystem): String {
    val calories = if (adapted != null) adapted.targetCalories else workout.targetCalories
    val distance = if (adapted != null) adapted.distanceMeters else workout.distanceMeters
    val duration = adapted?.effectiveWorkout?.targetDurationSeconds ?: adapted?.durationSeconds ?: adapted?.durationMinutes?.times(60) ?: workout.durationSeconds
    val goal = calories?.let { stringResource(R.string.plan_workout_calories, it) } ?: distance?.takeIf { it > 0 }?.let { workoutDistance(it, units) }
    val effort = adapted?.effortLabel ?: workout.intensityTarget.rpeRange()?.let {
        stringResource(R.string.plan_workout_effort_range, it.first, it.last)
    } ?: stringResource(stimulusLabel(workout.stimulus))
    return listOfNotNull(goal, duration.takeIf { it > 0 }?.let { workoutDuration(it) }, effort.takeIf { it.isNotBlank() }).joinToString(" · ")
}

@Composable
internal fun workoutDistance(meters: Double, units: MeasurementUnitSystem): String {
    val distance = SessionFormatting.distance(meters, units)
    return stringResource(if (units == MeasurementUnitSystem.metric) R.string.plan_workout_kilometers else R.string.plan_workout_miles, String.format(Locale.getDefault(), "%.1f", distance.value))
}

@Composable
private fun workoutDuration(seconds: Int): String = when {
    seconds % 60 == 0 -> stringResource(R.string.today_minutes, seconds / 60)
    seconds < 60 -> stringResource(R.string.plan_workout_seconds, seconds)
    else -> stringResource(R.string.plan_workout_minutes_seconds, seconds / 60, seconds % 60)
}

@Composable
private fun WorkoutStatusIcon(status: String) {
    if (status !in setOf("completed", "skipped", "missed", "cancelled", "canceled", "pending", "pending_sync", "sync_conflict")) return
    Icon(
        when (status) {
            "completed" -> Icons.Default.CheckCircle
            "skipped", "missed", "cancelled", "canceled" -> Icons.Default.RemoveCircleOutline
            else -> Icons.Default.Schedule
        },
        contentDescription = stringResource(statusLabel(status)),
        modifier = Modifier.size(22.dp),
        tint = if (status == "completed") MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
    )
}
