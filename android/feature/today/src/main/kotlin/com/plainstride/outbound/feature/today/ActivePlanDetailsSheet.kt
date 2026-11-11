package com.plainstride.outbound.feature.today

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.text.font.FontWeight
import com.plainstride.outbound.core.model.ActivitySuggestion
import com.plainstride.outbound.core.model.isCurrent
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
    onChangeWorkout: (() -> Unit)? = null,
    onRunningBenchmarkOpened: () -> Unit = {},
    onUpdateRunningBenchmark: suspend (String, com.plainstride.outbound.core.model.RunningBenchmarkReport?) -> Boolean = { _, _ -> false },
) {
    val plan = planning.plan ?: return
    val week = planning.planWeekSnapshot()
    val today = LocalDate.now(java.time.ZoneOffset.UTC)
    val todayWorkout = week?.workouts?.firstOrNull { it.isFor(today) && it.status !in TERMINAL_WORKOUT_STATUSES }
    val todaySuggestion = suggestion?.takeIf {
        !suggestionStale &&
            it.planContext?.planId == plan.id &&
            it.isCurrent()
    }
    var confirmsEnd by rememberSaveable(plan.id) { mutableStateOf(false) }
    PlanDetailsSheet(onDismiss = onDismiss) {
        PlanDetailsHeading(
            title = planTitle(planning),
            subtitle = planning.currentVersion?.summary,
            actions = {
                PlanDetailsAction(stringResource(R.string.plan_details_change), !busy, onClick = onChangePlan)
                PlanDetailsAction(stringResource(R.string.plan_details_end), !busy, destructive = true) {
                    confirmsEnd = true
                    onEndConfirmation()
                }
            },
        )
        planning.currentVersion?.engineDecision?.takeIf { it.programme != null || it.programmeDoseStatus == "needs_review" || it.programmeTimelineStatus == "needs_review" }?.let { RunningProgrammeNotice(it) }
        if (stale) Text(stringResource(R.string.plan_details_cached), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.tertiary)
        if (week != null) {
            val stats = listOfNotNull(
                stringResource(R.string.plan_details_length) to (week.totalWeeks?.let { stringResource(R.string.plan_details_week_count, it) } ?: stringResource(R.string.plan_details_length_unspecified)),
                (stringResource(R.string.plan_details_current_week) to (week.totalWeeks?.let { stringResource(R.string.plan_details_week_of, week.currentWeek, it) } ?: week.currentWeek.toString())),
                stringResource(R.string.plan_details_sessions) to week.targetSessions.toString(),
                stringResource(R.string.plan_details_time) to stringResource(R.string.today_minutes, week.targetMinutes),
            )
            PlanDetailsStats(stats)
            planning.goal?.daysPerWeekTarget?.takeIf { it != week.targetSessions }?.let {
                Text(stringResource(R.string.plan_details_preferred, it), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        planning.goal?.takeIf { com.plainstride.outbound.core.model.Modality.run in it.activities }?.let { RunningBenchmarkManagementRow(it, onUpdateRunningBenchmark, onRunningBenchmarkOpened) }
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
                        RecommendationDetails(primary, envelope.guideLine)
                        if (envelope.relationship == "adjustedFromPlan") {
                            planning.latestAdjustment?.message?.takeIf { it.isNotBlank() }?.let {
                                Text(it, color = MaterialTheme.colorScheme.tertiary, style = MaterialTheme.typography.bodySmall)
                            }
                        }
                        primary.steps.forEach { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall) }
                        onChangeWorkout?.let { change ->
                            PlanDetailsAction(stringResource(R.string.today_change_workout), !busy, onClick = change)
                        }
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
                        BenchmarkPhasePaces(workout, units)
                    }
                }
            }
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

@Composable
internal fun DailyRecommendationDetailsSheet(
    recommendation: ActivitySuggestionEnvelope,
    stale: Boolean,
    busy: Boolean,
    onDismiss: () -> Unit,
    onChangeWorkout: () -> Unit,
    onSetUpPlan: () -> Unit,
) {
    val workout = recommendation.primary ?: return
    PlanDetailsSheet(onDismiss = onDismiss) {
        PlanDetailsHeading(
            title = workout.title,
            subtitle = stringResource(R.string.plan_details_today),
            actions = {
                PlanDetailsAction(stringResource(R.string.today_change_workout), !busy, onClick = onChangeWorkout)
                PlanDetailsAction(stringResource(R.string.plan_details_set_up_training_plan), !busy, onClick = onSetUpPlan)
            },
        )
        if (stale) Text(
            stringResource(R.string.plan_details_recommendation_cached),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.tertiary,
        )
        PlanDetailsStats(listOf(
            stringResource(R.string.plan_details_duration) to stringResource(R.string.today_minutes, workout.durationMinutes),
            stringResource(R.string.plan_details_effort) to workout.effortLabel,
        ))
        PlanSectionCard(title = stringResource(R.string.plan_details_today)) {
            RecommendationDetails(workout, recommendation.guideLine)
        }
        if (workout.steps.isNotEmpty()) PlanSectionCard(title = stringResource(R.string.today_phases)) {
            workout.steps.forEachIndexed { index, step ->
                Column(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(stringResource(R.string.plan_details_step, index + 1), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
                    Text(step, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

/** Shared hierarchy for active plans and the daily recommendation, matching the iOS plan page. */
@Composable
@OptIn(ExperimentalMaterial3Api::class)
private fun PlanDetailsSheet(onDismiss: () -> Unit, content: @Composable ColumnScope.() -> Unit) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val density = LocalDensity.current
    val windowHeight = with(density) { LocalWindowInfo.current.containerSize.height.toDp() }
    val bottomInset = with(density) { maxOf(WindowInsets.ime.getBottom(this), WindowInsets.navigationBars.getBottom(this)).toDp() }
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = MaterialTheme.colorScheme.surfaceContainerLow,
        contentWindowInsets = { WindowInsets(0, 0, 0, 0) },
    ) {
        // Keep the sheet's measured height fixed while its animated offset changes. Measuring
        // against the moving sheet can feed its offset back into the sheet anchor calculation.
        Column(Modifier.fillMaxWidth().fillMaxHeight(.94f)) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                Spacer(Modifier.weight(1f))
                TextButton(onClick = onDismiss, modifier = Modifier.heightIn(min = 48.dp)) { Text(stringResource(R.string.today_done)) }
            }
            Text(
                stringResource(R.string.plan_details_title),
                Modifier.padding(horizontal = 16.dp).semantics { heading() },
                style = MaterialTheme.typography.headlineLarge,
                fontWeight = FontWeight.Bold,
            )
            Column(
                Modifier.weight(1f).layout { measurable, constraints ->
                    val offset = try { sheetState.requireOffset() } catch (_: IllegalStateException) { 0f }
                    val available = (windowHeight - bottomInset - 48.dp).roundToPx() - offset.toInt()
                    val height = available.coerceIn(0, constraints.maxHeight)
                    val placeable = measurable.measure(constraints.copy(minHeight = height, maxHeight = height))
                    layout(placeable.width, placeable.height) { placeable.placeRelative(0, 0) }
                }.verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 16.dp),
                verticalArrangement = Arrangement.spacedBy(20.dp),
                content = content,
            )
        }
    }
}

@Composable
private fun PlanDetailsHeading(title: String, subtitle: String?, actions: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(title, Modifier.semantics { heading() }, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(4.dp)) { actions() }
        subtitle?.takeIf { it.isNotBlank() }?.let {
            Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun PlanDetailsAction(label: String, enabled: Boolean, destructive: Boolean = false, onClick: () -> Unit) {
    TextButton(
        onClick = onClick,
        enabled = enabled,
        modifier = Modifier.heightIn(min = 48.dp),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(start = 0.dp, end = 12.dp, top = 8.dp, bottom = 8.dp),
        colors = ButtonDefaults.textButtonColors(contentColor = if (destructive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary),
    ) { Text(label) }
}

@Composable
private fun PlanDetailsStats(stats: List<Pair<String, String>>) {
    FlowRow(
        modifier = Modifier.fillMaxWidth(),
        maxItemsInEachRow = 2,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        stats.forEach { (label, value) ->
            Card(
                Modifier.weight(1f),
                shape = RoundedCornerShape(18.dp),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLowest),
            ) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(value, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}

@Composable
private fun RecommendationDetails(workout: ActivitySuggestion, guideLine: String) {
    Text(workout.title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
    Text(
        stringResource(R.string.plan_details_recommendation_detail, workout.durationMinutes, workout.effortLabel),
        color = MaterialTheme.colorScheme.primary,
        style = MaterialTheme.typography.labelLarge,
    )
    if (guideLine.isNotBlank()) Text(guideLine, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    if (workout.why.isNotBlank() && workout.why != guideLine) Text(workout.why, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

private val TERMINAL_WORKOUT_STATUSES = setOf("completed", "skipped", "missed", "cancelled", "canceled")

private fun PlannedWorkout.isFor(date: LocalDate): Boolean = planningLogicalDate(scheduledDate) == date

@Composable
private fun planTitle(planning: PlanningState): String {
    val type = planning.goal?.type.orEmpty().lowercase(Locale.ROOT)
    val distance = planning.goal?.targetDistanceMeters
    val focus = when (type) {
        "consistency" -> "consistency"
        "comeback" -> "comeback"
        "fivek" -> "5k"
        "tenk" -> "10k"
        "tenmile" -> "10mile"
        "halfmarathon" -> "half"
        "marathon" -> "marathon"
        else -> when {
            distance != null && distance >= 40_000 -> "marathon"
            distance != null && distance >= 20_000 -> "half"
            distance != null && distance >= 15_000 -> "10mile"
            distance != null && distance >= 9_000 -> "10k"
            distance != null && distance >= 4_000 -> "5k"
            "comeback" in type -> "comeback"
            "marathon" in type && "half" !in type -> "marathon"
            "half" in type -> "half"
            "10k" in type -> "10k"
            "5k" in type -> "5k"
            else -> "consistency"
        }
    }
    return stringResource(when (focus) {
        "comeback" -> R.string.plan_details_adaptive_comeback
        "5k" -> R.string.plan_details_adaptive_5k
        "10k" -> R.string.plan_details_adaptive_10k
        "10mile" -> R.string.plan_details_adaptive_10mile
        "half" -> R.string.plan_details_adaptive_half
        "marathon" -> R.string.plan_details_adaptive_marathon
        else -> R.string.plan_details_adaptive_consistency
    })
}

@Composable
private fun PlanSectionCard(title: String, content: @Composable ColumnScope.() -> Unit) {
    Card(
        Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLowest),
    ) {
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

/** Developer fixture adapter; the app exposes it only through its DEBUG launch flag. */
@Composable
fun DebugRunningPlanDetails(planning: PlanningState, suggestion: ActivitySuggestionEnvelope?, onDismiss: () -> Unit, onUpdateRunningBenchmark: suspend (String, com.plainstride.outbound.core.model.RunningBenchmarkReport?) -> Boolean = { _, _ -> false }) {
    ActivePlanDetailsSheet(planning, suggestion, false,
        com.plainstride.outbound.core.model.activity.MeasurementUnitSystem.metric,
        onRaceGoalOpened = {}, onUpdateRaceGoal = { _, _ -> false }, busy = false, stale = false,
        onDismiss = onDismiss, onChangePlan = {}, onEndPlan = {}, onEndConfirmation = {}, onRefresh = {}, onUpdateRunningBenchmark = onUpdateRunningBenchmark)
}

fun debugLocalizeRunningSuggestion(context: android.content.Context, value: ActivitySuggestionEnvelope): ActivitySuggestionEnvelope =
    StructuredWorkoutText(context, Locale.getDefault().toLanguageTag()).envelope(value)
