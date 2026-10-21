package com.plainstride.outbound.feature.today

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.plainstride.outbound.core.model.activity.ActivityType
import com.plainstride.outbound.core.model.activity.SavedActivity
import kotlin.math.pow
import kotlin.math.roundToInt

/** Wire values deliberately match iOS RaceExecutionIntent and the live coach contract. */
data class TodayRacePlan(
    val distanceMeters: Double,
    val goalTimeSeconds: Int?,
    val targetPaceSecondsPerKilometer: Double?,
    val pacingStrategy: String,
    val recommendationSource: String,
)

internal data class RaceRecommendation(val plan: TodayRacePlan, val evidenceCount: Int)

internal fun recommendRace(distance: Double, activities: List<SavedActivity>): RaceRecommendation {
    val eligible = activities.filter {
        it.type == ActivityType.running && it.distanceM >= 2_000 && it.durationSecs >= 600 &&
            it.distanceM >= distance * .5 && it.distanceM <= distance * 1.1
    }.take(30)
    val longest = eligible.maxOfOrNull { it.distanceM }
        ?: return RaceRecommendation(TodayRacePlan(distance, null, null, "effort_based", "insufficient_history"), 0)
    val comparable = eligible.filter { it.distanceM >= longest * .9 }
    val prediction = comparable.mapNotNull {
        val ratio = distance / it.distanceM
        if (ratio !in .9..2.0) null else {
            val projected = it.durationSecs * ratio.pow(1.08)
            if (it.distanceM >= distance * .95) maxOf(projected, it.durationSecs.toDouble()) else projected * 1.05
        }
    }.minOrNull() ?: return RaceRecommendation(TodayRacePlan(distance, null, null, "effort_based", "insufficient_history"), 0)
    val seconds = (prediction / 60).roundToInt() * 60
    return RaceRecommendation(TodayRacePlan(distance, seconds, seconds / (distance / 1_000), "negative_split", "training_history"), comparable.size)
}

internal fun raceDuration(seconds: Int): String = java.lang.String.format(java.util.Locale.getDefault(), "%02d:%02d:%02d", seconds / 3600, seconds % 3600 / 60, seconds % 60)

@Composable
internal fun RacePlannerDialog(activities: List<SavedActivity>, unitSystem: com.plainstride.outbound.core.model.activity.MeasurementUnitSystem, onDismiss: () -> Unit, onUse: (TodayRacePlan) -> Unit) {
    var distance by rememberSaveable { mutableStateOf(21_097.5) }
    val recommendation = remember(distance, activities) { recommendRace(distance, activities) }
    var strategy by rememberSaveable { mutableStateOf(recommendation.plan.pacingStrategy) }
    var hours by rememberSaveable { mutableStateOf((recommendation.plan.goalTimeSeconds ?: 7200) / 3600) }
    var minutes by rememberSaveable { mutableStateOf((recommendation.plan.goalTimeSeconds ?: 7200) % 3600 / 60) }
    var editingTime by rememberSaveable { mutableStateOf(false) }
    val seconds = hours * 3600 + minutes * 60
    val plan = TodayRacePlan(distance, seconds, if (strategy == "effort_based") null else seconds / (distance / 1000), strategy,
        if (seconds == recommendation.plan.goalTimeSeconds) recommendation.plan.recommendationSource else "manual")
    AlertDialog(onDismissRequest = onDismiss, title = { Text(stringResource(R.string.race_planner_title)) }, text = {
        Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(stringResource(R.string.race_planner_distance), style = MaterialTheme.typography.titleSmall)
            val distances = listOf(5000.0 to "5K", 10000.0 to "10K", 21097.5 to stringResource(R.string.race_planner_half), 42195.0 to stringResource(R.string.race_planner_marathon))
            distances.forEach { (value, label) ->
                Row { RadioButton(distance == value, onClick = {
                    distance = value
                    val next = recommendRace(value, activities).plan
                    strategy = next.pacingStrategy
                    hours = (next.goalTimeSeconds ?: 7200) / 3600
                    minutes = (next.goalTimeSeconds ?: 7200) % 3600 / 60
                }); TextButton(onClick = {
                    distance = value
                    val next = recommendRace(value, activities).plan
                    strategy = next.pacingStrategy
                    hours = (next.goalTimeSeconds ?: 7200) / 3600
                    minutes = (next.goalTimeSeconds ?: 7200) % 3600 / 60
                }) { Text(label) } }
            }
            Text(stringResource(R.string.race_planner_recommendation), style = MaterialTheme.typography.titleSmall)
            Text(if (recommendation.evidenceCount > 0) stringResource(R.string.race_planner_based_on_history, recommendation.evidenceCount, raceDuration(recommendation.plan.goalTimeSeconds ?: 0)) else stringResource(R.string.race_planner_no_history))
            TextButton(onClick = { editingTime = true }) { Text(stringResource(R.string.race_planner_use_target) + " · " + raceDuration(seconds)) }
            Text(stringResource(R.string.race_planner_strategy), style = MaterialTheme.typography.titleSmall)
            listOf("negative_split" to R.string.race_planner_negative_split, "even" to R.string.race_planner_even, "effort_based" to R.string.race_planner_effort).forEach { (value, label) ->
                Row { RadioButton(strategy == value, onClick = { strategy = value }); TextButton(onClick = { strategy = value }) { Text(stringResource(label)) } }
            }
            Text(stringResource(R.string.race_planner_execution), style = MaterialTheme.typography.titleSmall)
            Text(raceExecution(plan, unitSystem))
        }
    }, confirmButton = { TextButton(onClick = { onUse(plan) }, enabled = seconds in 300..86400) { Text(stringResource(R.string.race_planner_use_plan)) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.race_common_cancel)) } })
    if (editingTime) AlertDialog(onDismissRequest = { editingTime = false }, title = { Text(stringResource(R.string.race_planner_use_target)) }, text = {
        Row {
            Column { Text(stringResource(R.string.race_planner_hours)); androidTimePicker(hours, 24) { hours = it } }
            Column { Text(stringResource(R.string.race_planner_minutes)); androidTimePicker(minutes, 60) { minutes = it } }
        }
    }, confirmButton = { TextButton(onClick = { editingTime = false }) { Text(stringResource(R.string.today_done)) } })
}

@Composable
private fun androidTimePicker(value: Int, limit: Int, onChange: (Int) -> Unit) {
    androidx.compose.ui.viewinterop.AndroidView(factory = { context -> android.widget.NumberPicker(context).apply {
        minValue = 0; maxValue = limit - 1; setOnValueChangedListener { _, _, next -> onChange(next) }
    } }, update = { it.value = value })
}

@Composable
internal fun raceExecution(plan: TodayRacePlan, unitSystem: com.plainstride.outbound.core.model.activity.MeasurementUnitSystem): String {
    val pace = plan.targetPaceSecondsPerKilometer ?: return stringResource(R.string.race_planner_execution_effort)
    return when (plan.pacingStrategy) {
        "negative_split" -> stringResource(R.string.race_planner_execution_negative_split, racePace(pace + 10, unitSystem), racePace(pace, unitSystem))
        "even" -> stringResource(R.string.race_planner_execution_even, racePace(pace, unitSystem))
        else -> stringResource(R.string.race_planner_execution_effort)
    }
}

private fun racePace(seconds: Double, unitSystem: com.plainstride.outbound.core.model.activity.MeasurementUnitSystem): String {
    val pace = requireNotNull(com.plainstride.outbound.core.model.activity.SessionFormatting.pace(seconds, unitSystem))
    return java.lang.String.format(java.util.Locale.getDefault(), "%d:%02d /%s", pace.minutes, pace.seconds, if (unitSystem == com.plainstride.outbound.core.model.activity.MeasurementUnitSystem.metric) "km" else "mi")
}
