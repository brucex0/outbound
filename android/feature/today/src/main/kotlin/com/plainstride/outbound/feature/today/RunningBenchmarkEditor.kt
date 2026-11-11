package com.plainstride.outbound.feature.today

import android.app.DatePickerDialog
import android.widget.Toast
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.plainstride.outbound.core.model.PlannedWorkout
import com.plainstride.outbound.core.model.runningBenchmarkLocalDate
import com.plainstride.outbound.core.model.runningBenchmarkDurationSeconds
import com.plainstride.outbound.core.model.RunningBenchmarkReport
import com.plainstride.outbound.core.model.TrainingGoal
import com.plainstride.outbound.core.model.activity.MeasurementUnitSystem
import com.plainstride.outbound.core.model.activity.SessionFormatting
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull

@Composable
internal fun RunningBenchmarkManagementRow(goal: TrainingGoal, onSave: suspend (String, RunningBenchmarkReport?) -> Boolean, onOpened: () -> Unit) {
    var editing by remember(goal.id) { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        TextButton(onClick = { editing = true; onOpened() }) { Text(stringResource(R.string.benchmark_title)) }
        goal.currentRunningFitness?.report?.let { report ->
            Text("${stringResource(if (report.source == "race") R.string.benchmark_race else R.string.benchmark_time_trial)} · ${LocalDate.parse(report.date).format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM))}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Text(stringResource(when (goal.currentRunningFitness?.status) {
            "eligible" -> R.string.benchmark_estimate_detail
            "stale" -> R.string.benchmark_stale
            else -> R.string.benchmark_fallback
        }), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
    if (editing) RunningBenchmarkEditor(goal, onDismiss = { editing = false }, onSave = onSave)
}

@Composable
internal fun RunningBenchmarkEditor(goal: TrainingGoal, onDismiss: () -> Unit, onSave: suspend (String, RunningBenchmarkReport?) -> Boolean) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val existing = goal.currentRunningFitness?.report
    var distance by remember(goal.id) { mutableStateOf(existing?.let { (it.distanceMeters / 1000).toString() } ?: "5") }
    var duration by remember(goal.id) { mutableStateOf(existing?.let { String.format(Locale.ROOT, "%d:%02d:%02d", it.durationSeconds / 3600, it.durationSeconds / 60 % 60, it.durationSeconds % 60) } ?: "") }
    var date by remember(goal.id) { mutableStateOf(existing?.date?.let { runCatching { LocalDate.parse(it) }.getOrNull() } ?: runningBenchmarkLocalDate(java.time.Instant.now(), java.time.ZoneId.systemDefault())) }
    var source by remember(goal.id) { mutableStateOf(existing?.source ?: "race") }
    var maximal by remember(goal.id) { mutableStateOf(existing?.maximalEffort ?: false) }
    var saving by remember { mutableStateOf(false) }
    var removing by remember { mutableStateOf(false) }
    val km = distance.replace(',', '.').toDoubleOrNull()
    val seconds = runningBenchmarkDurationSeconds(duration)
    val today = LocalDate.now(ZoneOffset.UTC)
    val valid = maximal && km != null && km.isFinite() && km in 1.5..30.0 && seconds != null && seconds in 1..86400 && !date.isAfter(today) && !date.isBefore(today.minusDays(84))
    fun submit(report: RunningBenchmarkReport?) {
        saving = true
        scope.launch {
            try {
                val success = onSave(goal.id, report)
                if (success) onDismiss()
                else Toast.makeText(context, context.getString(R.string.benchmark_failed), Toast.LENGTH_LONG).show()
            } catch (error: CancellationException) { throw error }
            catch (error: TodayRepositoryException) {
                Toast.makeText(context, context.getString(if (error.dataError == TodayDataError.RunningBenchmarkInvalid) R.string.benchmark_validation else R.string.benchmark_failed), Toast.LENGTH_LONG).show()
            } catch (error: Exception) {
                android.util.Log.e("Planning", "running_benchmark_editor_save_failed category=${error.javaClass.simpleName}")
                Toast.makeText(context, context.getString(R.string.benchmark_failed), Toast.LENGTH_LONG).show()
            } finally { saving = false }
        }
    }
    AlertDialog(
        onDismissRequest = { if (!saving) onDismiss() },
        title = { Text(stringResource(R.string.benchmark_title)) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(stringResource(R.string.benchmark_detail))
                Text(stringResource(R.string.benchmark_source), style = MaterialTheme.typography.titleSmall)
                listOf("race" to R.string.benchmark_race, "timeTrial" to R.string.benchmark_time_trial).forEach { (value, label) ->
                    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).selectable(selected = source == value, enabled = !saving, role = Role.RadioButton, onClick = { source = value }), verticalAlignment = Alignment.CenterVertically) {
                        RadioButton(selected = source == value, onClick = null, enabled = !saving)
                        Text(stringResource(label), Modifier.weight(1f).padding(start = 8.dp))
                    }
                }
                OutlinedTextField(value = distance, onValueChange = { distance = it }, label = { Text(stringResource(R.string.benchmark_distance)) }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), enabled = !saving)
                OutlinedTextField(value = duration, onValueChange = { duration = it }, label = { Text(stringResource(R.string.benchmark_duration)) }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Text), enabled = !saving)
                OutlinedButton(onClick = {
                    DatePickerDialog(context, { _, year, month, day -> date = LocalDate.of(year, month + 1, day) }, date.year, date.monthValue - 1, date.dayOfMonth).apply { datePicker.maxDate = today.plusDays(1).atStartOfDay(java.time.ZoneId.systemDefault()).toInstant().toEpochMilli() - 1 }.show()
                }, enabled = !saving) { Text("${stringResource(R.string.benchmark_date)}: ${date.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM))}") }
                Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).toggleable(value = maximal, enabled = !saving, role = Role.Checkbox, onValueChange = { maximal = it }), verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(checked = maximal, onCheckedChange = null, enabled = !saving)
                    Text(stringResource(R.string.benchmark_maximal), Modifier.weight(1f).padding(start = 8.dp))
                }
                Text(stringResource(R.string.benchmark_validation), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(stringResource(R.string.benchmark_estimate_detail), style = MaterialTheme.typography.bodySmall)
                if (goal.currentRunningFitness?.status != null && goal.currentRunningFitness?.status != "absent") TextButton(onClick = { removing = true }, enabled = !saving, colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)) { Text(stringResource(R.string.benchmark_remove)) }
            }
        },
        confirmButton = { TextButton(onClick = { if (valid) submit(RunningBenchmarkReport(source = source, distanceMeters = km!! * 1000, durationSeconds = seconds!!, date = date.toString())) }, enabled = !saving && valid) { Text(stringResource(R.string.today_race_goal_save)) } },
        dismissButton = { TextButton(onClick = onDismiss, enabled = !saving) { Text(stringResource(R.string.today_race_goal_cancel)) } },
    )
    if (removing) AlertDialog(onDismissRequest = { removing = false }, title = { Text(stringResource(R.string.benchmark_remove_title)) },
        text = { Text(stringResource(R.string.benchmark_remove_detail)) },
        confirmButton = { TextButton(onClick = { removing = false; submit(null) }) { Text(stringResource(R.string.benchmark_remove)) } },
        dismissButton = { TextButton(onClick = { removing = false }) { Text(stringResource(R.string.today_race_goal_cancel)) } })
}

@Composable
internal fun BenchmarkPhasePaces(workout: PlannedWorkout, units: MeasurementUnitSystem) {
    val phases = workout.blocks.flatMap { it.steps }.filter { (it.target?.get("paceEstimatePolicy") as? JsonPrimitive)?.content == "reported-maximal-running-v1" }.distinctBy { it.kind to it.target }
    if (phases.isEmpty()) return
    Text(stringResource(R.string.benchmark_phase_paces), style = MaterialTheme.typography.labelMedium)
    phases.forEach { step ->
        val target = step.target ?: return@forEach
        val pace = target["pace"] as? JsonObject ?: return@forEach
        fun number(key: String) = (pace[key] as? JsonPrimitive)?.doubleOrNull
        val center = number("targetSecondsPerKilometer") ?: return@forEach
        val fast = number("fasterToleranceSeconds") ?: return@forEach
        val slow = number("slowerToleranceSeconds") ?: fast
        val lower = SessionFormatting.pace(center - fast, units) ?: return@forEach
        val upper = SessionFormatting.pace(center + slow, units) ?: return@forEach
        val unit = stringResource(if (units == MeasurementUnitSystem.metric) R.string.benchmark_per_km else R.string.benchmark_per_mile)
        val faster = String.format(Locale.getDefault(), "%d:%02d%s", lower.minutes, lower.seconds, unit)
        val slower = String.format(Locale.getDefault(), "%d:%02d%s", upper.minutes, upper.seconds, unit)
        Text(stringResource(R.string.benchmark_phase_range, step.label, faster, slower), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        (target["rpe"] as? JsonArray)?.takeIf { it.isNotEmpty() }?.let { rpe ->
            Text(stringResource(R.string.benchmark_phase_effort, rpe.joinToString("–") { (it as? JsonPrimitive)?.content ?: "" }), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
