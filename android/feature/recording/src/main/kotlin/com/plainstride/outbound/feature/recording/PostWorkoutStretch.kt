package com.plainstride.outbound.feature.recording

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.semantics.Role
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import kotlinx.coroutines.delay
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch

private enum class StretchPhase { SETUP, HOLD, TRANSITION }

@Composable
fun PostWorkoutStretchRoute(
    kind: ActivityKind,
    track: List<RecordedLocationSample>,
    sessionKey: String,
    onDone: () -> Unit,
    onShare: () -> Unit,
    onEvent: (StretchSessionEvent) -> Unit,
    fetchAudio: suspend (String, String) -> ByteArray?,
    isIndoor: Boolean = false,
) {
    StretchSessionRoute(
        launch = StretchLaunchContext(StretchEntryPoint.POST_SAVE, kind, isIndoor),
        sessionKey = sessionKey, onDone = onDone, onEvent = onEvent, fetchAudio = fetchAudio,
        header = { finish ->
            PostSaveCelebrationCard(track = track, sessionKey = sessionKey, modifier = Modifier.fillMaxWidth().height(205.dp))
            Text(stringResource(R.string.recording_post_save_message), style = MaterialTheme.typography.titleMedium)
            PostSaveActivityActions(onShare = onShare, onDone = finish)
        },
    )
}

/** Reusable standalone stretch flow; Today supplies only launch context and audio/analytics adapters. */
@Composable
fun StretchSessionRoute(
    launch: StretchLaunchContext = StretchLaunchContext(),
    sessionKey: String,
    onDone: () -> Unit,
    onEvent: (StretchSessionEvent) -> Unit,
    fetchAudio: suspend (String, String) -> ByteArray?,
    header: @Composable (() -> Unit) -> Unit = { _ -> },
) {
    val kind = launch.kind
    val isIndoor = launch.isIndoor
    val context = androidx.compose.ui.platform.LocalContext.current
    val preferences = remember { context.getSharedPreferences("stretch_preferences_v1", android.content.Context.MODE_PRIVATE) }
    var routines by remember(kind, launch.entryPoint) { mutableStateOf(StretchCatalog.routines(context, kind, launch.entryPoint)) }
    val initialRoutine = remember(kind, isIndoor, launch.entryPoint) {
        val remembered = preferences.getString(if (isIndoor) "last_routine" else "last_standing_routine", null)
        routines.firstOrNull { it.preferenceId == remembered && (isIndoor || it.isStanding) }
            ?: routines.firstOrNull { it.preferenceId == (if (kind == ActivityKind.SWIMMING) "upper_body" else "standing_quick") && (isIndoor || it.isStanding) }
            ?: routines.firstOrNull { isIndoor || it.isStanding }
            ?: StretchCatalog.outdoorFallback()
    }
    if (initialRoutine == null) {
        LaunchedEffect(Unit) { onDone() }
        return
    }

    var selectedRoutine by remember(kind) { mutableStateOf(initialRoutine) }
    var editing by remember { mutableStateOf(false) }
    var chosen by remember { mutableStateOf(false) }
    var movementIndex by remember { mutableIntStateOf(0) }
    var secondsLeft by remember(selectedRoutine.id) { mutableIntStateOf(selectedRoutine.movements.first().seconds) }
    var running by remember { mutableStateOf(false) }
    var complete by remember { mutableStateOf(false) }
    var confirmEnd by remember { mutableStateOf(false) }
    var phase by remember { mutableStateOf(StretchPhase.SETUP) }
    var speaks by remember { mutableStateOf(true) }
    var feedback by remember { mutableStateOf(false) }
    var preview by remember { mutableStateOf(false) }
    var skipped by remember { mutableIntStateOf(0) }
    var stepHeld by remember { mutableIntStateOf(0) }
    var totalHeld by remember { mutableIntStateOf(0) }
    var moreRoutines by remember { mutableStateOf(!initialRoutine.isStanding) }
    fun emit(name: String, routineID: String?, result: String?, seconds: Int?) {
        onEvent(StretchSessionEvent(name, routineID, result, seconds, launch.entryPoint, selectedRoutine.customized, selectedRoutine.entries.size, selectedRoutine.totalSeconds))
    }
    val audio = remember { StretchAudio(context) }
    val view = LocalView.current
    val owner = LocalLifecycleOwner.current
    val movement = selectedRoutine.movements[movementIndex]

    fun advance(skip: Boolean) {
        emit("post_workout_stretch_step_ended", selectedRoutine.id, if (skip) "skipped" else "held", stepHeld)
        if (skip) skipped += 1
        stepHeld = 0
        if (movementIndex == selectedRoutine.movements.lastIndex) {
            complete = true
            running = false
            view.keepScreenOn = false
            if (speaks) audio.play("release")
            emit("post_workout_stretch_completed", selectedRoutine.id, if (skipped == 0) "fully_held" else "with_skips", totalHeld)
        } else {
            movementIndex += 1
            phase = StretchPhase.TRANSITION
            secondsLeft = 5
        }
    }

    fun finish(result: String?) {
        audio.stop()
        running = false
        view.keepScreenOn = false
        result?.let { emit("post_workout_stretch_dismissed", selectedRoutine.id, it, totalHeld) }
        onDone()
    }

    DisposableEffect(owner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP || event == Lifecycle.Event.ON_PAUSE) {
                running = false
                audio.stop()
                view.keepScreenOn = false
            }
        }
        owner.lifecycle.addObserver(observer)
        onDispose {
            audio.close()
            owner.lifecycle.removeObserver(observer)
            view.keepScreenOn = false
        }
    }

    LaunchedEffect(selectedRoutine.movements.map { it.cue }) {
        audio.preload(selectedRoutine.movements.map { it.cue }.distinct(), fetchAudio)
    }
    LaunchedEffect(speaks) { if (!speaks) audio.stop() }
    LaunchedEffect(running, movementIndex, selectedRoutine.id, phase, speaks) {
        coroutineScope {
            val intervalPhase = phase
            // Narration and visible preparation time advance together. Never
            // subtract speech duration afterward: that makes 0:05 jump to 0:01.
            val announcement = if (running && intervalPhase != StretchPhase.HOLD) launch {
                if (feedback && intervalPhase == StretchPhase.TRANSITION) {
                    view.performHapticFeedback(android.view.HapticFeedbackConstants.CLOCK_TICK)
                    view.playSoundEffect(android.view.SoundEffectConstants.CLICK)
                }
                if (speaks) audio.playAndWait(movement.cue, intervalPhase == StretchPhase.TRANSITION)
            } else null
            while (running && !complete && phase == intervalPhase) {
                if (intervalPhase == StretchPhase.HOLD && secondsLeft in 1..5 && speaks) audio.tick()
                delay(1_000)
                if (intervalPhase == StretchPhase.HOLD) { stepHeld += 1; totalHeld += 1 }
                if (secondsLeft > 1) secondsLeft -= 1
                else if (intervalPhase != StretchPhase.HOLD) {
                    // Keep the last preparation second visible if a long title
                    // is still playing; a hold must never overlap narration.
                    if (announcement?.isActive != true) {
                        phase = StretchPhase.HOLD
                        secondsLeft = movement.seconds
                    }
                } else advance(false)
            }
        }
    }

    LaunchedEffect(sessionKey) {
        emit("post_workout_stretch_offered", initialRoutine.id, null, null)
    }

    BackHandler {
        if (complete) {
            finish(null)
        } else if (running) {
            confirmEnd = true
        } else {
            finish(if (chosen) "ended_early" else "not_started")
        }
    }

    Column(
        modifier = Modifier.fillMaxSize().safeDrawingPadding().padding(horizontal = 24.dp).then(if (chosen && !complete) Modifier.verticalScroll(rememberScrollState()) else Modifier),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        if (!chosen) {
            Column(
                modifier = Modifier.fillMaxWidth().weight(1f).verticalScroll(rememberScrollState()).padding(vertical = 20.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                header { finish("not_started") }
                if (launch.entryPoint != StretchEntryPoint.POST_SAVE) TextButton(onClick = { finish("not_started") }) { Text(stringResource(R.string.stretch_done)) }
                Text(stringResource(if (launch.entryPoint == StretchEntryPoint.POST_SAVE) R.string.stretch_offer_title else R.string.stretch_catalog_ui_choose), style = MaterialTheme.typography.headlineSmall)
                if (launch.entryPoint == StretchEntryPoint.POST_SAVE) Text(stringResource(R.string.stretch_offer_body))
                Text(stringResource(R.string.recording_post_save_program_title), style = MaterialTheme.typography.titleMedium)

                if (routines.none { it.id == selectedRoutine.id }) { StretchRoutineOption(selectedRoutine, true) {} }
                routines.filter { it.isStanding }.forEach { routine ->
                    StretchRoutineOption(routine, selectedRoutine.id == routine.id) {
                        selectedRoutine = routine
                        movementIndex = 0
                        emit("post_workout_stretch_program_selected", routine.id, null, null)
                    }
                }
                TextButton(onClick = { moreRoutines = !moreRoutines }) { Text(stringResource(R.string.stretch_more_routines)) }
                if (moreRoutines) routines.filterNot { it.isStanding }.forEach { routine ->
                    StretchRoutineOption(routine, selectedRoutine.id == routine.id) {
                        selectedRoutine = routine
                        movementIndex = 0
                        emit("post_workout_stretch_program_selected", routine.id, null, null)
                    }
                }

                TextButton(onClick = { editing = true; emit("stretch_routine_edited", selectedRoutine.id, "opened", null) }) { Text(stringResource(R.string.stretch_catalog_ui_customize)) }
                Text("≈ ${selectedRoutine.totalSeconds / 60}:${(selectedRoutine.totalSeconds % 60).toString().padStart(2, '0')} · ${selectedRoutine.requirements(context)}")
                TextButton(onClick = { preview = !preview }) { Text(stringResource(R.string.stretch_preview)) }
                if (preview) selectedRoutine.movements.forEach { step ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(16.dp),
                    ) {
                        StretchIllustration(step.id, Modifier.size(56.dp))
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text(stringResource(step.title) + " · " + (step.side?.let { stringResource(it) } ?: ""))
                            Text(stringResource(step.instruction), style = MaterialTheme.typography.bodySmall)
                        }
                    }
                }
                StretchSettingToggle(stringResource(R.string.stretch_voice), speaks) { speaks = it }
                StretchSettingToggle(stringResource(R.string.stretch_feedback), feedback) { feedback = it }
                Button(
                    onClick = {
                        secondsLeft = 3
                        phase = StretchPhase.SETUP
                        preferences.edit().putString("last_routine", selectedRoutine.preferenceId).apply()
                        if (selectedRoutine.isStanding) preferences.edit().putString("last_standing_routine", selectedRoutine.preferenceId).apply()
                        chosen = true
                        running = true
                        view.keepScreenOn = true
                        emit("post_workout_stretch_started", selectedRoutine.id, null, null)
                    },
                    modifier = Modifier.fillMaxWidth().height(52.dp),
                ) {
                    Text(stringResource(R.string.stretch_catalog_ui_start))
                }

                Text(stringResource(R.string.stretch_disclaimer), style = MaterialTheme.typography.bodySmall)
            }
        } else if (complete) {
            Spacer(Modifier.weight(1f))
            Icon(Icons.Default.CheckCircle, contentDescription = null, modifier = Modifier.size(72.dp), tint = MaterialTheme.colorScheme.primary)
            Text(stringResource(R.string.stretch_complete_title), style = MaterialTheme.typography.headlineMedium)
            Button(onClick = { finish(null) }) { Text(stringResource(R.string.stretch_done)) }
            Spacer(Modifier.weight(1f))
        } else {
            Spacer(Modifier.weight(1f))
            StretchIllustration(movement.id, Modifier.size(150.dp))
            if (phase != StretchPhase.HOLD) Text(stringResource(if (phase == StretchPhase.TRANSITION) R.string.stretch_transition else R.string.stretch_get_ready))
            Text(stringResource(movement.title), style = MaterialTheme.typography.headlineMedium)
            movement.side?.let { Text(stringResource(it), style = MaterialTheme.typography.titleMedium) }
            Text(stringResource(if (selectedRoutine.isWarmup) R.string.stretch_catalog_ui_move else R.string.stretch_catalog_ui_hold))
            Text(stringResource(movement.instruction))
            Text(
                text = "${secondsLeft / 60}:${(secondsLeft % 60).toString().padStart(2, '0')}",
                style = MaterialTheme.typography.displayMedium,
            )
            LinearProgressIndicator(
                progress = { (movementIndex + if (phase == StretchPhase.HOLD) 1f - secondsLeft.toFloat() / movement.seconds else 0f) / selectedRoutine.movements.size },
                modifier = Modifier.fillMaxWidth(),
            )
            Text(stringResource(R.string.stretch_safety))
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Button(onClick = {
                    audio.stop()
                    running = !running
                    view.keepScreenOn = running
                }) {
                    Text(stringResource(if (running) R.string.stretch_pause else R.string.stretch_resume))
                }
                OutlinedButton(onClick = {
                    audio.stop()
                    if (phase != StretchPhase.HOLD) {
                        phase = StretchPhase.HOLD
                        secondsLeft = movement.seconds
                    } else advance(true)
                }) {
                    Text(stringResource(if (phase != StretchPhase.HOLD) R.string.stretch_start_now else R.string.stretch_next))
                }
            }
            if (movementIndex < selectedRoutine.movements.lastIndex) {
                val next = selectedRoutine.movements[movementIndex + 1]
                Text(stringResource(R.string.stretch_up_next) + ": " + stringResource(next.title) + " · " + (next.side?.let { stringResource(it) } ?: ""))
            }
            StretchSettingToggle(stringResource(R.string.stretch_voice), speaks) { speaks = it }
            TextButton(onClick = { if (running) confirmEnd = true else finish("ended_early") }) {
                Text(stringResource(R.string.stretch_end))
            }
            Spacer(Modifier.weight(1f))
        }
    }

    if (editing) {
        StretchRoutineEditor(selectedRoutine, onDismiss = { editing = false }, onAction = { action -> emit("stretch_routine_edited", selectedRoutine.id, action, null) }) { entries ->
            val saved = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) { StretchCustomizationStore(context).save(selectedRoutine.preferenceId, entries) }
            if (saved) {
                routines = StretchCatalog.routines(context, kind, launch.entryPoint)
                selectedRoutine = routines.first { it.preferenceId == selectedRoutine.preferenceId }
                movementIndex = 0
                moreRoutines = !selectedRoutine.isStanding
            }
            saved
        }
    }
    if (confirmEnd) {
        AlertDialog(
            onDismissRequest = { confirmEnd = false },
            title = { Text(stringResource(R.string.stretch_end_title)) },
            text = { Text(stringResource(R.string.stretch_end_message)) },
            confirmButton = {
                TextButton(onClick = { confirmEnd = false; finish("ended_early") }) {
                    Text(stringResource(R.string.stretch_end_confirm))
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmEnd = false }) { Text(stringResource(R.string.recording_cancel)) }
            },
        )
    }
}

/** One accessible switch target with an explicit control-to-label gap. */
@Composable
private fun StretchSettingToggle(label: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)
            .toggleable(value = checked, role = Role.Switch, onValueChange = onCheckedChange)
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        androidx.compose.material3.Switch(checked = checked, onCheckedChange = null)
        Text(label, modifier = Modifier.weight(1f))
    }
}

@Composable
private fun StretchRoutineOption(routine: StretchRoutine, selected: Boolean, onClick: () -> Unit) {
    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(
            containerColor = if (selected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceVariant,
        ),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(stringResource(routine.title), style = MaterialTheme.typography.titleSmall)
                val duration = routine.movements.sumOf { it.seconds } + 3 + (routine.movements.size - 1) * 5
                Text("≈ ${duration / 60}:${(duration % 60).toString().padStart(2, '0')}", style = MaterialTheme.typography.bodySmall)
                Text(routine.requirements(androidx.compose.ui.platform.LocalContext.current), style = MaterialTheme.typography.bodySmall)
                if (routine.customized) Text(stringResource(R.string.stretch_catalog_ui_your_version), style = MaterialTheme.typography.bodySmall)
            }
            Spacer(Modifier.width(8.dp))
            RadioButton(selected = selected, onClick = onClick)
        }
    }
}

@Composable
internal fun StretchIllustration(id: String, modifier: Modifier) {
    val movementId = id.removeSuffix("_left").removeSuffix("_right").removeSuffix("_both")
    val artworkDefinition = StretchCatalog.definition(movementId)
    val artwork = artworkDefinition?.artwork
    if (artwork != null) {
        androidx.compose.foundation.Image(
            painter = androidx.compose.ui.res.painterResource(artwork), contentDescription = null,
            modifier = modifier.then(Modifier.graphicsLayer { scaleX = if (if (artworkDefinition.artworkSide == "right") id.endsWith("_left") else id.endsWith("_right")) -1f else 1f }),
            contentScale = androidx.compose.ui.layout.ContentScale.Fit,
        )
        return
    }
    val color = MaterialTheme.colorScheme.onSurface
    val accent = MaterialTheme.colorScheme.primary
    androidx.compose.foundation.Canvas(modifier) {
        val cue = id
        val movementId = cue.removeSuffix("_left").removeSuffix("_right").removeSuffix("_both")
        val definition = StretchCatalog.definition(movementId) ?: return@Canvas
        val lines = definition.paths
        val scale = minOf(size.width, size.height) / 100f
        val first = lines.first().first()
        val lying = definition.lying
        val headX = first.first + if (lying) -7f else 0f
        val headY = first.second + if (lying) 0f else -7f
        drawCircle(color, 6f * scale, androidx.compose.ui.geometry.Offset((if (cue.endsWith("right")) 100f - headX else headX) * scale, headY * scale), style = androidx.compose.ui.graphics.drawscope.Stroke(3f * scale))
        lines.forEachIndexed { index, points ->
            points.zipWithNext().forEach { (a,b) ->
                fun point(p: Pair<Float, Float>) = androidx.compose.ui.geometry.Offset((if (cue.endsWith("right")) 100f - p.first else p.first) * scale, p.second * scale)
                drawLine(if (index == lines.lastIndex) accent else color, point(a), point(b), 4f * scale, androidx.compose.ui.graphics.StrokeCap.Round)
            }
        }
    }
}
