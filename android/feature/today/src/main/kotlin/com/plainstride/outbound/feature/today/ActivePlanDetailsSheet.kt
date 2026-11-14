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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ExpandLess
import androidx.compose.material.icons.outlined.ExpandMore
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
import androidx.compose.ui.semantics.stateDescription
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
import java.util.Locale

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
    onWorkoutDetailsOpened: () -> Unit = {},
    onPhaseSummaryShown: () -> Unit = {},
    onChangeWorkout: (() -> Unit)? = null,
    onRunningBenchmarkOpened: () -> Unit = {},
    onUpdateRunningBenchmark: suspend (String, com.plainstride.outbound.core.model.RunningBenchmarkReport?) -> Boolean = { _, _ -> false },
) {
    val plan = planning.plan ?: return
    val today = LocalDate.now(planning.calendar?.zone() ?: java.time.ZoneId.systemDefault())
    val todaySuggestion = suggestion?.takeIf {
        !suggestionStale && it.planContext?.planId == plan.id &&
            it.isCurrent(zone = planning.calendar?.zone() ?: java.time.ZoneOffset.UTC)
    }
    var selectedWorkoutId by rememberSaveable(plan.id) { mutableStateOf<String?>(null) }
    var showsRaceGoal by rememberSaveable(plan.id) { mutableStateOf(false) }
    var confirmsEnd by rememberSaveable(plan.id) { mutableStateOf(false) }
    PlanDetailsSheet(onDismiss = onDismiss) {
        PlanDetailsHeading(
            title = listOfNotNull(planTitle(planning), planning.goal?.targetDistanceMeters?.let { workoutDistance(it, units) }).joinToString(" · "),
            subtitle = null,
            actions = {
                PlanDetailsAction(stringResource(R.string.plan_details_change), !busy, onClick = onChangePlan)
                PlanDetailsAction(stringResource(R.string.plan_details_end), !busy, destructive = true) {
                    confirmsEnd = true
                    onEndConfirmation()
                }
            },
        )
        if (planning.goal?.targetDate != null) {
            val disclosureState = stringResource(if (showsRaceGoal) R.string.plan_workout_expanded else R.string.plan_workout_collapsed)
            PlanDetailsAction(
                stringResource(R.string.plan_workout_race_goal_details),
                true,
                modifier = Modifier.semantics { stateDescription = disclosureState },
                trailingContent = {
                    Icon(
                        imageVector = if (showsRaceGoal) Icons.Outlined.ExpandLess else Icons.Outlined.ExpandMore,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                    )
                },
            ) { showsRaceGoal = !showsRaceGoal }
            if (showsRaceGoal) RaceGoalCard(planning, units, onRaceGoalOpened, onUpdateRaceGoal)
        } else planning.goal?.daysPerWeekTarget?.let {
            Text(stringResource(R.string.plan_workout_weekly_rhythm, it), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (stale) {
            Text(stringResource(R.string.plan_details_cached), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.tertiary)
            TextButton(onClick = onRefresh, enabled = !busy) { Text(stringResource(R.string.today_retry)) }
        }
        PlanSectionCard(title = stringResource(R.string.plan_workout_your_schedule)) {
            // Only an unmatched same-day recommendation needs its own summary. A matched
            // adaptation belongs to its issued row and detail, with the original status.
            if (todaySuggestion?.primary != null && planning.issuedPlanWorkouts().none { it.id == todaySuggestion.primary?.plannedWorkoutId }) {
                RecommendationDetails(todaySuggestion.primary!!, todaySuggestion.guideLine)
                onChangeWorkout?.let { change -> PlanDetailsAction(stringResource(R.string.today_change_workout), !busy, onClick = change) }
            }
            if (planning.issuedPlanWorkouts().isEmpty()) {
                val syncing = !planning.cachedScheduleCoverageAvailable || planning.currentVersion == null
                Text(stringResource(if (syncing) R.string.plan_details_loading else R.string.plan_workout_none_scheduled), color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (syncing) TextButton(onClick = onRefresh, enabled = !busy) { Text(stringResource(R.string.today_retry)) }
            }
            IssuedPlanSchedule(planning, todaySuggestion, today, units) { workout ->
                selectedWorkoutId = workout.id
                onWorkoutDetailsOpened()
            }
        }
        if (planning.goal?.targetDate != null) {
            if (planning.roadmap != null) CompactPlanPhaseSummary(planning, today, onPhaseSummaryShown)
            else Text(stringResource(R.string.plan_details_roadmap_syncing), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        } else PlanSectionCard(title = stringResource(R.string.plan_details_what_comes_next)) {
            planning.currentVersion?.summary?.takeIf { it.isNotBlank() }?.let {
                Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text(stringResource(R.string.plan_details_rolling_outlook), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        planning.currentVersion?.engineDecision?.takeIf { it.programme != null || it.programmeDoseStatus == "needs_review" || it.programmeTimelineStatus == "needs_review" }?.let {
            PlanSectionCard(stringResource(R.string.plan_workout_training_context)) { RunningProgrammeNotice(it) }
        }
        planning.goal?.takeIf { com.plainstride.outbound.core.model.Modality.run in it.activities }?.let {
            PlanSectionCard(stringResource(R.string.plan_workout_benchmark)) { RunningBenchmarkManagementRow(it, onUpdateRunningBenchmark, onRunningBenchmarkOpened) }
        }
    }
    planning.issuedPlanWorkouts().firstOrNull { it.id == selectedWorkoutId }?.let { workout ->
        ScheduledPlanWorkoutPage(
            workout = workout,
            suggestion = todaySuggestion?.takeIf { workout.isFor(today) && it.primary?.plannedWorkoutId == workout.id },
            mobility = planning.optionalMobilityFor(workout),
            adjustment = planning.latestAdjustment?.message,
            units = units,
            onBack = { selectedWorkoutId = null },
            onDone = onDismiss,
            onChangeWorkout = onChangeWorkout?.takeIf { workout.isFor(today) && workout.status !in TERMINAL_WORKOUT_STATUSES },
            busy = busy,
        )
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
private fun PlanDetailsAction(
    label: String,
    enabled: Boolean,
    destructive: Boolean = false,
    modifier: Modifier = Modifier,
    trailingContent: @Composable (() -> Unit)? = null,
    onClick: () -> Unit,
) {
    TextButton(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier.heightIn(min = 48.dp),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(start = 0.dp, end = 12.dp, top = 8.dp, bottom = 8.dp),
        colors = ButtonDefaults.textButtonColors(contentColor = if (destructive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary),
    ) {
        if (trailingContent == null) {
            Text(label)
        } else {
            Text(label, modifier = Modifier.weight(1f, fill = false))
            Spacer(Modifier.width(8.dp))
            trailingContent()
        }
    }
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

private val TERMINAL_WORKOUT_STATUSES = setOf("completed", "pending", "skipped", "missed", "cancelled", "canceled")

internal fun PlannedWorkout.isFor(date: LocalDate): Boolean = planningLogicalDate(scheduledDate) == date

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
internal fun PlanSectionCard(title: String, content: @Composable ColumnScope.() -> Unit) {
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
internal fun workoutDescription(workout: PlannedWorkout): String? = workout.prescription
    ?.get("summary")?.let { it as? JsonPrimitive }?.contentOrNull?.takeIf { it.isNotBlank() }

internal fun phaseLabel(phase: String): Int = when (phase) {
    "base" -> R.string.plan_details_phase_base
    "build" -> R.string.plan_details_phase_build
    "sharpen" -> R.string.plan_details_phase_sharpen
    "taper" -> R.string.plan_details_phase_taper
    "recovery" -> R.string.today_race_goal_recovery
    "maintenance" -> R.string.today_race_goal_maintenance
    else -> R.string.plan_details_active_plan
}

internal fun stimulusLabel(stimulus: TrainingStimulus): Int = when (stimulus) {
    TrainingStimulus.easyAerobic -> R.string.plan_details_stimulus_easy
    TrainingStimulus.longEndurance -> R.string.plan_details_stimulus_long
    TrainingStimulus.threshold -> R.string.plan_details_stimulus_threshold
    TrainingStimulus.speed -> R.string.plan_details_stimulus_speed
    TrainingStimulus.strength, TrainingStimulus.hypertrophy, TrainingStimulus.power -> R.string.plan_details_stimulus_strength
    TrainingStimulus.recovery -> R.string.plan_details_stimulus_recovery
    TrainingStimulus.mobility -> R.string.plan_details_stimulus_mobility
    TrainingStimulus.skill -> R.string.plan_details_stimulus_skill
}

internal fun statusLabel(status: String): Int = when (status) {
    "pending", "pending_sync" -> R.string.plan_details_pending
    "sync_conflict" -> R.string.plan_workout_sync_conflict
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
