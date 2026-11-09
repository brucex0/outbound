package com.plainstride.outbound.feature.today

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.plainstride.outbound.core.model.ActivitySuggestionEnvelope
import com.plainstride.outbound.core.model.PlannedWorkout
import com.plainstride.outbound.core.model.PlanningState
import com.plainstride.outbound.core.model.TrainingStimulus
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlin.math.ceil

@Composable
@OptIn(ExperimentalMaterial3Api::class)
internal fun ActivePlanDetailsSheet(
    planning: PlanningState,
    suggestion: ActivitySuggestionEnvelope?,
    suggestionStale: Boolean,
    units: com.plainstride.outbound.core.model.activity.MeasurementUnitSystem,
    onRaceGoalOpened: () -> Unit,
    onUpdateRaceGoal: suspend (String, com.plainstride.outbound.core.network.RaceGoalUpdateRequest) -> Boolean,
    busy: Boolean,
    stale: Boolean,
    onDismiss: () -> Unit,
    onChangePlan: () -> Unit,
    onEndPlan: () -> Unit,
    onEndConfirmation: () -> Unit,
    onRefresh: () -> Unit,
) {
    val plan = planning.plan ?: return
    val week = planning.planWeekSnapshot()
    val today = LocalDate.now()
    val todayWorkout = week?.workouts?.firstOrNull { it.isFor(today) && it.status !in TERMINAL_WORKOUT_STATUSES }
    val todaySuggestion = suggestion?.takeIf {
        !suggestionStale &&
            it.planContext?.planId == plan.id &&
            it.validForDate == today.toString()
    }
    var confirmsEnd by rememberSaveable(plan.id) { mutableStateOf(false) }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 24.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Row(Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.plan_details_title), Modifier.weight(1f).semantics { heading() }, style = MaterialTheme.typography.titleLarge)
                TextButton(onClick = onDismiss, modifier = Modifier.heightIn(min = 48.dp)) { Text(stringResource(R.string.today_done)) }
            }
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(planTitle(planning), Modifier.semantics { heading() }, style = MaterialTheme.typography.headlineSmall)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    TextButton(
                        onClick = onChangePlan,
                        enabled = !busy,
                        modifier = Modifier.heightIn(min = 48.dp),
                        contentPadding = androidx.compose.foundation.layout.PaddingValues(start = 0.dp, end = 12.dp, top = 8.dp, bottom = 8.dp),
                        colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.primary),
                    ) { Text(stringResource(R.string.plan_details_change)) }
                    TextButton(
                        onClick = { confirmsEnd = true; onEndConfirmation() },
                        enabled = !busy,
                        modifier = Modifier.heightIn(min = 48.dp),
                        contentPadding = androidx.compose.foundation.layout.PaddingValues(start = 0.dp, end = 12.dp, top = 8.dp, bottom = 8.dp),
                        colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                    ) { Text(stringResource(R.string.plan_details_end)) }
                }
                planning.currentVersion?.summary?.let { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            }
            if (stale) Text(stringResource(R.string.plan_details_cached), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.tertiary)
            if (week != null) {
                val stats = listOfNotNull(
                    stringResource(R.string.plan_details_length) to (week.totalWeeks?.let { stringResource(R.string.plan_details_week_count, it) } ?: stringResource(R.string.plan_details_length_unspecified)),
                    (stringResource(R.string.plan_details_current_week) to (week.totalWeeks?.let { stringResource(R.string.plan_details_week_of, week.currentWeek, it) } ?: week.currentWeek.toString())),
                    stringResource(R.string.plan_details_sessions) to week.targetSessions.toString(),
                    stringResource(R.string.plan_details_time) to stringResource(R.string.today_minutes, week.targetMinutes),
                )
                androidx.compose.foundation.layout.FlowRow(
                    modifier = Modifier.fillMaxWidth(),
                    maxItemsInEachRow = 2,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    stats.forEach { (label, value) ->
                        Card(Modifier.weight(1f)) {
                            Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                Text(value, style = MaterialTheme.typography.titleMedium)
                            }
                        }
                    }
                }
                planning.goal?.daysPerWeekTarget?.takeIf { it != week.targetSessions }?.let {
                    Text(stringResource(R.string.plan_details_preferred, it), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            if (planning.goal?.type == "eventPreparation") RaceGoalCard(planning, units, onRaceGoalOpened, onUpdateRaceGoal)
            if (week == null) {
                Text(stringResource(R.string.plan_details_loading), color = MaterialTheme.colorScheme.onSurfaceVariant)
                TextButton(onClick = onRefresh, enabled = !busy) { Text(stringResource(R.string.today_retry)) }
            } else {
                PlanSectionCard(title = stringResource(R.string.plan_details_this_week)) {
                    Text(stringResource(phaseLabel(plan.currentPhase)), color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.titleSmall)
                    Text(
                        stringResource(R.string.plan_details_progress, week.completedSessions, week.targetSessions, week.completedMinutes, week.targetMinutes),
                        style = MaterialTheme.typography.bodyMedium,
                    )
                    LinearProgressIndicator(progress = { week.progress }, modifier = Modifier.fillMaxWidth())
                    planning.latestAdjustment?.message?.takeIf { it.isNotBlank() }?.let {
                        Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                PlanSectionCard(title = stringResource(R.string.plan_details_today)) {
                    when {
                        todaySuggestion?.primary != null -> {
                            val envelope = todaySuggestion
                            val primary = envelope.primary!!
                            Text(primary.title, style = MaterialTheme.typography.titleMedium)
                            Text(
                                stringResource(R.string.plan_details_recommendation_detail, primary.durationMinutes, primary.effortLabel),
                                color = MaterialTheme.colorScheme.primary,
                                style = MaterialTheme.typography.labelLarge,
                            )
                            Text(envelope.guideLine, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(primary.why, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            if (envelope.relationship == "adjustedFromPlan") {
                                planning.latestAdjustment?.message?.takeIf { it.isNotBlank() }?.let {
                                    Text(it, color = MaterialTheme.colorScheme.tertiary, style = MaterialTheme.typography.bodySmall)
                                }
                            }
                            primary.steps.take(4).forEach { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall) }
                        }
                        todayWorkout != null -> {
                            Text(todayWorkout.title, style = MaterialTheme.typography.titleMedium)
                            Text(
                                stringResource(R.string.plan_details_recommendation_detail, ceil(todayWorkout.durationSeconds / 60.0).toInt(), stringResource(stimulusLabel(todayWorkout.stimulus))),
                                color = MaterialTheme.colorScheme.primary,
                                style = MaterialTheme.typography.labelLarge,
                            )
                            workoutDescription(todayWorkout)?.let { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                        }
                        else -> Text(stringResource(R.string.plan_details_no_session), style = MaterialTheme.typography.titleMedium)
                    }
                }
                PlanSectionCard(title = stringResource(R.string.plan_details_schedule)) {
                    if (week.workouts.isEmpty()) Text(stringResource(R.string.plan_details_empty), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    week.workouts.forEach { workout ->
                        Column(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text(
                                    "${workout.scheduledDate.localizedPlanDate()} · ${workout.title}",
                                    Modifier.weight(1f),
                                    style = MaterialTheme.typography.titleSmall,
                                )
                                if (workout.prescription?.get("optional")?.toString() == "true") {
                                    Text(stringResource(R.string.today_race_goal_optional), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                            Text(
                                stringResource(R.string.plan_details_workout_detail, ceil(workout.durationSeconds / 60.0).toInt(), stringResource(stimulusLabel(workout.stimulus))),
                                color = MaterialTheme.colorScheme.primary,
                                style = MaterialTheme.typography.labelMedium,
                            )
                            Text(stringResource(statusLabel(workout.status)), color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
                            workoutDescription(workout)?.let { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall) }
                        }
                    }
                }
            }
            Spacer(Modifier.height(20.dp))
        }
    }
    if (confirmsEnd) AlertDialog(
        onDismissRequest = { confirmsEnd = false },
        title = { Text(stringResource(R.string.plan_details_end_title)) },
        text = { Text(stringResource(R.string.plan_details_end_body)) },
        confirmButton = {
            TextButton(onClick = { confirmsEnd = false; onEndPlan() }, enabled = !busy, colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)) {
                Text(stringResource(R.string.plan_details_end))
            }
        },
        dismissButton = { TextButton(onClick = { confirmsEnd = false }) { Text(stringResource(R.string.today_cancel)) } },
    )
}

private val TERMINAL_WORKOUT_STATUSES = setOf("completed", "skipped", "missed", "cancelled", "canceled")

private fun PlannedWorkout.isFor(date: LocalDate): Boolean = planningLogicalDate(scheduledDate) == date

@Composable
private fun planTitle(planning: PlanningState): String = planning.goal?.targetEventName?.takeIf { it.isNotBlank() }
    ?: stringResource(when (planning.goal?.type) {
        "endurance" -> R.string.plan_details_goal_endurance
        "speed" -> R.string.plan_details_goal_speed
        "weightLoss" -> R.string.plan_details_goal_weight
        "healthEnergy" -> R.string.plan_details_goal_health
        "eventPreparation" -> R.string.plan_details_goal_event
        else -> R.string.plan_details_active_plan
    })

@Composable
private fun PlanSectionCard(title: String, content: @Composable ColumnScope.() -> Unit) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(title, Modifier.semantics { heading() }, style = MaterialTheme.typography.titleMedium)
            content()
        }
    }
}

@Composable
private fun workoutDescription(workout: PlannedWorkout): String? = workout.prescription
    ?.get("summary")?.let { it as? JsonPrimitive }?.contentOrNull?.takeIf { it.isNotBlank() }

private fun String.localizedPlanDate(): String = planningLogicalDate(this)
    ?.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)) ?: this

private fun phaseLabel(phase: String): Int = when (phase) {
    "base" -> R.string.plan_details_phase_base
    "build" -> R.string.plan_details_phase_build
    "sharpen" -> R.string.plan_details_phase_sharpen
    "taper" -> R.string.plan_details_phase_taper
    else -> R.string.plan_details_active_plan
}

private fun stimulusLabel(stimulus: TrainingStimulus): Int = when (stimulus) {
    TrainingStimulus.easyAerobic -> R.string.plan_details_stimulus_easy
    TrainingStimulus.longEndurance -> R.string.plan_details_stimulus_long
    TrainingStimulus.threshold -> R.string.plan_details_stimulus_threshold
    TrainingStimulus.speed -> R.string.plan_details_stimulus_speed
    TrainingStimulus.strength, TrainingStimulus.hypertrophy, TrainingStimulus.power -> R.string.plan_details_stimulus_strength
    TrainingStimulus.recovery -> R.string.plan_details_stimulus_recovery
    TrainingStimulus.mobility -> R.string.plan_details_stimulus_mobility
    TrainingStimulus.skill -> R.string.plan_details_stimulus_skill
}

private fun statusLabel(status: String): Int = when (status) {
    "completed" -> R.string.plan_details_completed
    "skipped" -> R.string.plan_details_skipped
    "missed" -> R.string.plan_details_missed
    "cancelled", "canceled" -> R.string.plan_details_cancelled
    else -> R.string.plan_details_planned
}

@Composable
@OptIn(ExperimentalMaterial3Api::class)
internal fun PlanDetailsSyncingSheet(onDismiss: () -> Unit, onRefresh: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text(stringResource(R.string.plan_details_title), style = MaterialTheme.typography.titleLarge)
            Text(stringResource(R.string.plan_details_syncing), color = MaterialTheme.colorScheme.onSurfaceVariant)
            OutlinedButton(onClick = onRefresh, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                Text(stringResource(R.string.today_retry))
            }
            TextButton(onClick = onDismiss, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                Text(stringResource(R.string.today_done))
            }
        }
    }
}
