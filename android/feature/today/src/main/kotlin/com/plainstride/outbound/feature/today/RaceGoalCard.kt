package com.plainstride.outbound.feature.today

import android.app.DatePickerDialog
import android.widget.Toast
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.dp
import com.plainstride.outbound.core.model.PlanningState
import com.plainstride.outbound.core.model.TrainingGoal
import com.plainstride.outbound.core.model.activity.MeasurementUnitSystem
import com.plainstride.outbound.core.network.RaceGoalUpdateRequest
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.temporal.ChronoUnit
import java.util.Locale
import kotlinx.coroutines.launch

private fun goalDate(value: String?): LocalDate? = value?.take(10)?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
private fun clock(seconds: Int) = String.format(Locale.ROOT, "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
private fun displayDate(date: LocalDate) = date.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM))

@Composable
internal fun RaceGoalCard(state: PlanningState, units: MeasurementUnitSystem, onOpen: () -> Unit, onSave: suspend (String, RaceGoalUpdateRequest) -> Boolean) {
    val goal = state.goal ?: return
    var editing by rememberSaveable(goal.id) { mutableStateOf(false) }
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(stringResource(R.string.today_race_goal_title), style = MaterialTheme.typography.titleMedium)
            goal.targetDistanceMeters?.let { meters ->
                val metric = units == MeasurementUnitSystem.metric
                val value = if (metric) meters / 1000 else meters / 1609.344
                Text(String.format(Locale.getDefault(), "%.1f %s", value, if (metric) "km" else "mi"), style = MaterialTheme.typography.titleLarge)
            }
            goalDate(goal.targetDate)?.let { date ->
                Text(displayDate(date))
                Text(stringResource(R.string.today_race_goal_countdown, ChronoUnit.DAYS.between(LocalDate.now(), date).coerceAtLeast(0).toInt()))
            }
            Text(if (goal.eventIntent == "targetTime") "${stringResource(R.string.today_race_goal_finish_time)}: ${clock(goal.targetTimeSeconds ?: 0)}" else stringResource(if (goal.eventIntent == "perform") R.string.today_race_goal_perform else R.string.today_race_goal_finish))
            val roadmap = state.roadmap
            if (roadmap != null) {
                Text(stringResource(R.string.today_race_goal_phase, phaseTitle(roadmap.currentPhase)), style = MaterialTheme.typography.titleSmall)
                Text(stringResource(R.string.today_race_goal_roadmap), style = MaterialTheme.typography.titleMedium)
                roadmap.phases.forEach { phase ->
                    Text(phaseTitle(phase.phase), style = if (phase.phase == roadmap.currentPhase) MaterialTheme.typography.titleSmall else MaterialTheme.typography.bodyMedium)
                    val start = goalDate(phase.startDate); val end = goalDate(phase.endDate)
                    if (start != null && end != null) Text("${displayDate(start)} – ${displayDate(end)}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                goalDate(roadmap.detailedThroughDate)?.let { Text(stringResource(R.string.today_race_goal_window, displayDate(it)), style = MaterialTheme.typography.bodyMedium) }
                Text(stringResource(R.string.today_race_goal_rolling), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            val adjustmentKey = state.latestAdjustment?.message
            val adjustmentLabel = when {
                state.latestAdjustment?.eventType in listOf("workoutMissed", "workoutSkipped") -> R.string.today_race_goal_missed
                adjustmentKey == "today.race_goal.policy_updated" -> R.string.today_race_goal_policy_updated
                adjustmentKey == "today.race_goal.goal_updated" -> R.string.today_race_goal_goal_updated
                adjustmentKey == "today.race_goal.refilled" -> R.string.today_race_goal_refilled
                else -> null
            }
            adjustmentLabel?.let { Text(stringResource(it), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            if (state.plan?.source == "generated") OutlinedButton(onClick = { editing = true; onOpen() }) { Text(stringResource(R.string.today_race_goal_edit)) }
        }
    }
    if (editing) RaceGoalEditor(goal, onDismiss = { editing = false }, onSave = onSave)
}

@Composable
private fun phaseTitle(phase: String): String = stringResource(when (phase) {
    "build" -> R.string.today_race_goal_build
    "sharpen" -> R.string.today_race_goal_sharpen
    "taper" -> R.string.today_race_goal_taper
    "recovery" -> R.string.today_race_goal_recovery
    "maintenance" -> R.string.today_race_goal_maintenance
    else -> R.string.today_race_goal_base
})

@Composable
private fun RaceGoalEditor(goal: TrainingGoal, onDismiss: () -> Unit, onSave: suspend (String, RaceGoalUpdateRequest) -> Boolean) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var distance by rememberSaveable(goal.id) { mutableStateOf(((goal.targetDistanceMeters ?: 10000.0) / 1000).toString()) }
    var dateText by rememberSaveable(goal.id) { mutableStateOf(goal.targetDate?.take(10) ?: LocalDate.now().toString()) }
    var intent by rememberSaveable(goal.id) { mutableStateOf(goal.eventIntent ?: "finish") }
    var timeInput by rememberSaveable(goal.id) { mutableStateOf(clock(goal.targetTimeSeconds ?: 3600)) }
    var days by rememberSaveable(goal.id) { mutableIntStateOf(goal.daysPerWeekTarget ?: 3) }
    var cap by rememberSaveable(goal.id) { mutableIntStateOf((goal.maxSessionMinutes ?: 30).coerceAtLeast(if (goal.shortRunSessions) 10 else 25)) }
    var short by rememberSaveable(goal.id) { mutableStateOf(goal.shortRunSessions) }
    var mobility by rememberSaveable(goal.id) { mutableStateOf(goal.optionalMobility) }
    var saving by remember { mutableStateOf(false) }
    val distanceValue = distance.replace(',', '.').toDoubleOrNull()
    val date = goalDate(dateText)
    val timeParts = timeInput.split(':').map { it.toIntOrNull() }
    val targetTime = if (timeParts.size == 3 && timeParts.all { it != null } && timeParts[0]!! in 0..48 && timeParts[1]!! in 0..59 && timeParts[2]!! in 0..59) timeParts[0]!! * 3600 + timeParts[1]!! * 60 + timeParts[2]!! else null
    val valid = (intent != "targetTime" || (targetTime != null && targetTime in 1..172800)) && distanceValue != null && distanceValue.isFinite() && distanceValue > 0 && distanceValue <= 500 && date != null && !date.isBefore(LocalDate.now())
    AlertDialog(
        onDismissRequest = { if (!saving) onDismiss() },
        title = { Text(stringResource(R.string.today_race_goal_edit)) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(value = distance, onValueChange = { distance = it }, label = { Text(stringResource(R.string.today_race_goal_km)) }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), enabled = !saving)
                OutlinedButton(onClick = {
                    val initial = date ?: LocalDate.now()
                    DatePickerDialog(context, { _, year, month, day -> dateText = LocalDate.of(year, month + 1, day).toString() }, initial.year, initial.monthValue - 1, initial.dayOfMonth).apply { datePicker.minDate = System.currentTimeMillis() - 86400000; show() }
                }, enabled = !saving) { Text("${stringResource(R.string.today_race_goal_date)}: ${date?.let(::displayDate) ?: dateText}") }
                Text(stringResource(R.string.today_race_goal_intent), style = MaterialTheme.typography.titleSmall)
                listOf("finish" to R.string.today_race_goal_finish, "perform" to R.string.today_race_goal_perform, "targetTime" to R.string.today_race_goal_target_time).forEach { (value, label) ->
                    FilterChip(selected = intent == value, onClick = { intent = value }, label = { Text(stringResource(label)) }, enabled = !saving)
                }
                if (intent == "targetTime") OutlinedTextField(value = timeInput, onValueChange = { timeInput = it }, label = { Text(stringResource(R.string.today_race_goal_finish_time_input)) }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Ascii), enabled = !saving)
                GoalNumberControl(stringResource(R.string.today_race_goal_days, days), days, 1, 6, 1, !saving) { days = it }
                GoalNumberControl(stringResource(R.string.today_race_goal_cap, cap), cap, if (short) 10 else 25, 180, 5, !saving) { cap = it }
                Text(stringResource(R.string.today_race_goal_duration_detail), style = MaterialTheme.typography.bodySmall)
                GoalToggle(stringResource(R.string.today_race_goal_short), short, !saving) { short = it; if (!it) cap = cap.coerceAtLeast(25) }
                Text(stringResource(R.string.today_race_goal_short_detail), style = MaterialTheme.typography.bodySmall)
                GoalToggle(stringResource(R.string.today_race_goal_mobility), mobility, !saving) { mobility = it }
                Text(stringResource(R.string.today_race_goal_mobility_detail), style = MaterialTheme.typography.bodySmall)
            }
        },
        confirmButton = { TextButton(enabled = valid && !saving, onClick = {
            val request = RaceGoalUpdateRequest(dateText, distanceValue!! * 1000, intent, targetTime?.takeIf { intent == "targetTime" }, days, cap, short, mobility)
            saving = true
            scope.launch {
                val success = onSave(goal.id, request)
                Toast.makeText(context, context.getString(if (success) R.string.today_race_goal_saved else R.string.today_race_goal_failed), Toast.LENGTH_SHORT).show()
                saving = false
                if (success) onDismiss()
            }
        }) { Text(stringResource(R.string.today_race_goal_save)) } },
        dismissButton = { TextButton(onClick = onDismiss, enabled = !saving) { Text(stringResource(R.string.today_race_goal_cancel)) } },
    )
}

@Composable
private fun GoalNumberControl(label: String, value: Int, min: Int, max: Int, step: Int, enabled: Boolean, onChange: (Int) -> Unit) {
    val decrease = stringResource(R.string.today_race_goal_decrease, label)
    val increase = stringResource(R.string.today_race_goal_increase, label)
    Column {
        Text(label)
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedButton(onClick = { onChange((value - step).coerceAtLeast(min)) }, enabled = enabled && value > min, modifier = Modifier.semantics { contentDescription = decrease }) { Text("−") }
            OutlinedButton(onClick = { onChange((value + step).coerceAtMost(max)) }, enabled = enabled && value < max, modifier = Modifier.semantics { contentDescription = increase }) { Text("+") }
        }
    }
}

@Composable
private fun GoalToggle(label: String, value: Boolean, enabled: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, Modifier.weight(1f))
        Switch(modifier = Modifier.semantics { contentDescription = label }, checked = value, onCheckedChange = onChange, enabled = enabled)
    }
}
