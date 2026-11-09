package com.plainstride.outbound.feature.today

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
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
import com.plainstride.outbound.core.model.PlanningState
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlin.math.ceil

@Composable
@OptIn(ExperimentalMaterial3Api::class)
internal fun ActivePlanDetailsSheet(
    planning: PlanningState,
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
    var confirmsEnd by rememberSaveable(plan.id) { mutableStateOf(false) }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 24.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Row(Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.plan_details_title), Modifier.weight(1f).semantics { heading() }, style = MaterialTheme.typography.titleLarge)
                TextButton(onClick = onDismiss) { Text(stringResource(R.string.today_done)) }
            }
            Text(planning.goal?.targetEventName ?: stringResource(when (planning.goal?.type) {
                "endurance" -> R.string.plan_details_goal_endurance
                "speed" -> R.string.plan_details_goal_speed
                "weightLoss" -> R.string.plan_details_goal_weight
                "healthEnergy" -> R.string.plan_details_goal_health
                "eventPreparation" -> R.string.plan_details_goal_event
                else -> R.string.plan_details_active_plan
            }), style = MaterialTheme.typography.headlineSmall)
            planning.currentVersion?.summary?.let { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            if (stale) Text(stringResource(R.string.plan_details_cached), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.tertiary)
            if (week != null) {
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        week.totalWeeks?.let { PlanStat(stringResource(R.string.plan_details_length), String.format(Locale.getDefault(), "%d", it)) }
                        PlanStat(stringResource(R.string.plan_details_current_week), if (week.totalWeeks != null) stringResource(R.string.plan_details_week_of, week.currentWeek, week.totalWeeks) else week.currentWeek.toString())
                        PlanStat(stringResource(R.string.plan_details_sessions), String.format(Locale.getDefault(), "%d", week.targetSessions))
                        PlanStat(stringResource(R.string.plan_details_time), stringResource(R.string.today_minutes, week.targetMinutes))
                    }
                }
                planning.goal?.daysPerWeekTarget?.takeIf { it != week.targetSessions }?.let {
                    Text(stringResource(R.string.plan_details_preferred, it), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = onChangePlan, enabled = !busy, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                    Text(stringResource(R.string.plan_details_change))
                }
                OutlinedButton(
                    onClick = { confirmsEnd = true; onEndConfirmation() },
                    enabled = !busy,
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error),
                    modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                ) { Text(stringResource(R.string.plan_details_end)) }
            }
            if (week == null) {
                Text(stringResource(R.string.plan_details_loading), color = MaterialTheme.colorScheme.onSurfaceVariant)
                TextButton(onClick = onRefresh, enabled = !busy) { Text(stringResource(R.string.today_retry)) }
            } else {
                Text(stringResource(R.string.plan_details_this_week), Modifier.semantics { heading() }, style = MaterialTheme.typography.titleMedium)
                Text(stringResource(when (plan.currentPhase) {
                    "base" -> R.string.plan_details_phase_base
                    "build" -> R.string.plan_details_phase_build
                    "sharpen" -> R.string.plan_details_phase_sharpen
                    "taper" -> R.string.plan_details_phase_taper
                    else -> R.string.plan_details_active_plan
                }), color = MaterialTheme.colorScheme.primary)
                Text(stringResource(R.string.plan_details_progress, week.completedSessions, week.targetSessions, week.completedMinutes, week.targetMinutes))
                LinearProgressIndicator(progress = { week.progress }, modifier = Modifier.fillMaxWidth())
                Text(stringResource(R.string.plan_details_schedule), Modifier.semantics { heading() }, style = MaterialTheme.typography.titleMedium)
                if (week.workouts.isEmpty()) Text(stringResource(R.string.plan_details_empty), color = MaterialTheme.colorScheme.onSurfaceVariant)
                week.workouts.forEach { workout ->
                    Card(Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            planningLogicalDate(workout.scheduledDate)?.let {
                                Text(it.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)), style = MaterialTheme.typography.labelMedium)
                            }
                            Text(workout.title, style = MaterialTheme.typography.titleSmall)
                            Text(stringResource(R.string.today_minutes, ceil(workout.durationSeconds / 60.0).toInt()), color = MaterialTheme.colorScheme.primary)
                            Text(stringResource(when (workout.status) {
                                "completed" -> R.string.plan_details_completed
                                "skipped" -> R.string.plan_details_skipped
                                "missed" -> R.string.plan_details_missed
                                "cancelled", "canceled" -> R.string.plan_details_cancelled
                                else -> R.string.plan_details_planned
                            }), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
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

@Composable
private fun PlanStat(label: String, value: String) {
    // Stacked values retain their full width at large font sizes and in long translations.
    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.titleMedium)
    }
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
