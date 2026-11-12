package com.plainstride.outbound

import com.plainstride.outbound.feature.today.toWorkoutLaunchIntent

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.Switch
import com.plainstride.outbound.core.model.RunningBenchmarkReport
import com.plainstride.outbound.core.network.RunningBenchmarkUpdateRequest
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import androidx.compose.runtime.DisposableEffect
import androidx.core.content.ContextCompat
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.plainstride.outbound.core.model.ActivitySuggestionEnvelope
import com.plainstride.outbound.core.model.PlanningState
import com.plainstride.outbound.core.network.PlainstrideJson
import com.plainstride.outbound.feature.recording.DebugRunningPhase
import com.plainstride.outbound.feature.today.DebugRunningPlanDetails
import com.plainstride.outbound.feature.today.debugLocalizeRunningSuggestion
import kotlinx.serialization.json.jsonObject

/** DEBUG launch only. Loads synthetic local API JSON; never saves or records an activity. */
@Composable
internal fun DebugRunningPlanHarness() {
    val context = LocalContext.current
    val intent = (context as? android.app.Activity)?.intent
    val pickerMode = intent?.getStringExtra("running_plan_picker")
    if (pickerMode != null) {
        val recommendations = remember {
            try {
                PlainstrideJson.decodeFromString(
                    com.plainstride.outbound.core.network.PlanRecommendationsResponse.serializer(),
                    java.io.File(context.filesDir, "plan-recommendations-fixture.json").readText(),
                ).recommendations
            } catch (error: Exception) {
                android.util.Log.e("planning_debug", "recommendation_fixture_load_failed category=invalid_or_missing_fixture")
                emptyList()
            }
        }
        var open by remember { mutableStateOf(true) }
        var dark by remember { mutableStateOf(intent.getBooleanExtra("running_plan_dark", false)) }
        DisposableEffect(context) {
            val receiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    dark = intent.getBooleanExtra("dark", false)
                }
            }
            // Registered only inside the DEBUG launch fixture. Shell broadcasts can change
            // appearance while the same production dialog and scroll state remain open.
            ContextCompat.registerReceiver(context, receiver,
                IntentFilter("com.plainstride.outbound.debug.PLAN_PREVIEW_APPEARANCE"),
                ContextCompat.RECEIVER_EXPORTED)
            onDispose { context.unregisterReceiver(receiver) }
        }
        com.plainstride.outbound.core.designsystem.PlainstrideTheme(
            theme = if (dark) com.plainstride.outbound.core.designsystem.PlainstrideThemeId.Ocean else com.plainstride.outbound.core.designsystem.PlainstrideThemeId.VictoryGold,
            darkTheme = dark,
        ) {
            if (open) com.plainstride.outbound.feature.today.DebugPlanPicker(
                recommendations, pickerMode,
                hasActivePlan = intent.getBooleanExtra("running_plan_active", false),
                onDismiss = { open = false },
            ) else Text("Synthetic picker dismissed")
        }
        return
    }
    fun loadFixture(filename: String): Pair<PlanningState, ActivitySuggestionEnvelope>? = try {
        val json = PlainstrideJson.parseToJsonElement(java.io.File(context.filesDir, filename).readText()).jsonObject
        PlainstrideJson.decodeFromJsonElement(PlanningState.serializer(), json.getValue("planning")) to
            debugLocalizeRunningSuggestion(context, PlainstrideJson.decodeFromJsonElement(ActivitySuggestionEnvelope.serializer(), json.getValue("suggestion")))
    } catch (error: Exception) {
        android.util.Log.e("planning_debug", "fixture_load_failed category=invalid_or_missing_fixture")
        null
    }
    var fixture by remember { mutableStateOf(loadFixture("planning-fixture.json")) }
    var failsNextBenchmarkSave by remember { mutableStateOf(false) }
    suspend fun saveSyntheticBenchmark(goalId: String, report: RunningBenchmarkReport?): Boolean {
        val request = RunningBenchmarkUpdateRequest(report)
        val encoded = PlainstrideJson.encodeToString(RunningBenchmarkUpdateRequest.serializer(), request)
        java.io.File(context.filesDir, "benchmark-request.json").writeText(encoded)
        val element = PlainstrideJson.parseToJsonElement(encoded).jsonObject["runningBenchmark"]
        val wireValid = if (report == null) element == JsonNull else element is JsonObject
            && element["activity"] == JsonPrimitive("run") && element["maximalEffort"] == JsonPrimitive(true)
        if (!wireValid) { android.util.Log.e("planning_debug", "benchmark_serialization_failed category=missing_required_fields"); return false }
        if (failsNextBenchmarkSave) { failsNextBenchmarkSave = false; throw com.plainstride.outbound.feature.today.TodayRepositoryException(com.plainstride.outbound.feature.today.TodayDataError.RunningBenchmarkInvalid) }
        val next = loadFixture(if (report == null) "planning-benchmark-removed.json" else "planning-benchmark-corrected.json") ?: return false
        fixture = next
        return true
    }
    var details by remember { mutableStateOf(true) }
    var phase by remember { mutableStateOf(0) }
    val primary = fixture?.second?.primary
    val launch = primary?.let {
        it.toWorkoutLaunchIntent("synthetic_fixture").toRecordingLaunch()
    }
    val phases = launch?.workoutSteps.orEmpty()
    Column(Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
        Text("Synthetic planning fixture")
        Text("Fail next benchmark save (synthetic)")
        Switch(checked = failsNextBenchmarkSave, onCheckedChange = { failsNextBenchmarkSave = it })
        if (phases.isNotEmpty()) {
            val elapsed = phases.take(phase).sumOf { (it.durationSeconds ?: 0).toLong() }
            DebugRunningPhase(elapsed, phases)
            TextButton(onClick = { phase = (phase + 1) % phases.size }) { Text("Next phase") }
            TextButton(onClick = { details = true }) { Text("Plan details") }
        } else Text("Add planning-fixture.json to app files, then relaunch.")
    }
    if (details && fixture != null) DebugRunningPlanDetails(fixture!!.first, fixture!!.second, onDismiss = { details = false }, onUpdateRunningBenchmark = ::saveSyntheticBenchmark)
}
