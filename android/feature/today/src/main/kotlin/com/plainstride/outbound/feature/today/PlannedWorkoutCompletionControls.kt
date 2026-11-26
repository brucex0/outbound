package com.plainstride.outbound.feature.today

import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.plainstride.outbound.core.model.PlannedWorkout
import com.plainstride.outbound.core.model.activity.MeasurementUnitSystem
import com.plainstride.outbound.core.network.RemoteActivityDto
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun PlannedWorkoutCompletionControls(
    workout: PlannedWorkout,
    dateEligible: Boolean,
    accountZone: ZoneId,
    units: MeasurementUnitSystem,
    loadCandidates: suspend (PlannedWorkout) -> List<RemoteActivityDto>,
    complete: suspend (String, String, String?) -> Boolean,
) {
    if (!dateEligible || (workout.status !in setOf("planned", "missed") && workout.completionMode?.startsWith("manual_") != true)) return
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var busy by remember(workout.id) { mutableStateOf(false) }
    var candidates by remember(workout.id) { mutableStateOf<List<RemoteActivityDto>?>(null) }
    var confirmation by remember(workout.id) { mutableStateOf<String?>(null) }
    fun showToast(success: Boolean) { Toast.makeText(context, if (success) R.string.plan_completion_saved else R.string.plan_completion_failed, Toast.LENGTH_LONG).show() }
    fun apply(action: String, activityId: String? = null) {
        scope.launch {
            busy = true
            try { showToast(complete(workout.id, action, activityId)) }
            catch (error: Exception) {
                if (error is CancellationException) throw error
                android.util.Log.w("PlainstridePlanning", "manual_completion_failed category=${error.javaClass.simpleName}")
                showToast(false)
            } finally { busy = false }
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(enabled = !busy, onClick = {
                scope.launch {
                    busy = true
                    try { candidates = loadCandidates(workout) }
                    catch (error: Exception) {
                        if (error is CancellationException) throw error
                        android.util.Log.w("PlainstridePlanning", "manual_candidates_failed category=${error.javaClass.simpleName}")
                        showToast(false)
                    } finally { busy = false }
                }
            }) { Text(stringResource(R.string.plan_completion_link)) }
            OutlinedButton(enabled = !busy, onClick = { confirmation = if (workout.status == "completed") "undo" else "complete" }) {
                Text(stringResource(if (workout.status == "completed") R.string.plan_completion_undo else R.string.plan_completion_manual))
            }
        }
        if (busy) CircularProgressIndicator()
    }
    confirmation?.let { action ->
        AlertDialog(onDismissRequest = { confirmation = null },
            title = { Text(stringResource(if (action == "undo") R.string.plan_completion_undo_title else R.string.plan_completion_manual_title)) },
            text = { Text(stringResource(if (action == "undo") R.string.plan_completion_undo_message else R.string.plan_completion_manual_message)) },
            confirmButton = { TextButton(onClick = { confirmation = null; apply(action) }) { Text(stringResource(if (action == "undo") R.string.plan_completion_undo else R.string.plan_completion_manual)) } },
            dismissButton = { TextButton(onClick = { confirmation = null }) { Text(stringResource(android.R.string.cancel)) } })
    }
    candidates?.let { rows ->
        ModalBottomSheet(onDismissRequest = { candidates = null }) {
            Column(Modifier.verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(stringResource(R.string.plan_completion_link), style = MaterialTheme.typography.titleLarge)
                Text(stringResource(R.string.plan_completion_choose_message), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (rows.isEmpty()) Text(stringResource(R.string.plan_completion_empty), style = MaterialTheme.typography.bodyMedium)
                rows.forEach { candidate ->
                    OutlinedButton(onClick = { candidates = null; apply("link", candidate.id) }) {
                        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(candidate.title, style = MaterialTheme.typography.titleMedium)
                            Text(Instant.parse(candidate.startedAt).atZone(accountZone).format(DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)), style = MaterialTheme.typography.bodyMedium)
                            Text(workoutDistance(candidate.distanceM, units) + " · " + "%d:%02d".format(candidate.durationSecs / 60, candidate.durationSecs % 60), style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                }
            }
        }
    }
}
