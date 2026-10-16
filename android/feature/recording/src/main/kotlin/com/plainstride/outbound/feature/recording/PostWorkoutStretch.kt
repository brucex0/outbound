package com.plainstride.outbound.feature.recording

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import kotlinx.coroutines.delay

data class StretchMovement(
    val id: String,
    val title: Int,
    val instruction: Int,
    val side: Int?,
    val seconds: Int,
)

private enum class StretchPhase { SETUP, HOLD, TRANSITION }

data class StretchRoutine(
    val id: String,
    val title: Int,
    val durationLabel: Int,
    val movements: List<StretchMovement>,
)

object PostWorkoutStretchCatalog {
    fun routines(kind: ActivityKind): List<StretchRoutine>? {
        val prefix = when (kind) {
            ActivityKind.RUNNING -> "run"
            ActivityKind.CYCLING -> "bike"
            ActivityKind.HIKING -> "hike"
            ActivityKind.SWIMMING -> "swim"
            ActivityKind.WALKING -> return null
        }

        val cooldown = bilateral(prefix, "glute", 30) +
            bilateral(prefix, "hamstring", 30) +
            listOf(movement(prefix, "inner_thigh", "both", 30)) +
            bilateral(prefix, "calf", 30) +
            bilateral(prefix, "quad", 30)
        val hipsAndHamstrings = bilateral(prefix, "hip_flexor", 20) +
            bilateral(prefix, "hamstring", 20) +
            bilateral(prefix, "glute", 20)

        return listOf(
            StretchRoutine(
                id = "post_save_${prefix}_cooldown_v2",
                title = R.string.recording_post_save_program_full_body,
                durationLabel = R.string.recording_post_save_program_full_body_duration,
                movements = cooldown,
            ),
            StretchRoutine(
                id = "post_save_${prefix}_hips_hamstrings_v2",
                title = R.string.recording_post_save_program_hips_hamstrings,
                durationLabel = R.string.recording_post_save_program_hips_hamstrings_duration,
                movements = hipsAndHamstrings,
            ),
        )
    }

    private fun bilateral(prefix: String, movementId: String, seconds: Int) = listOf(
        movement(prefix, movementId, "left", seconds),
        movement(prefix, movementId, "right", seconds),
    )

    private fun movement(prefix: String, id: String, side: String, seconds: Int): StretchMovement {
        val title = when (id) {
            "calf" -> R.string.recording_stretch_movement_calf
            "glute" -> R.string.recording_stretch_movement_glute
            "hamstring" -> R.string.recording_stretch_movement_hamstring
            "hip_flexor" -> R.string.recording_stretch_movement_hip_flexor
            "inner_thigh" -> R.string.recording_stretch_movement_inner_thigh
            else -> R.string.recording_stretch_movement_quad
        }
        val instruction = when (id) {
            "calf" -> R.string.recording_stretch_instruction_calf
            "glute" -> R.string.recording_stretch_instruction_glute
            "hamstring" -> R.string.recording_stretch_instruction_hamstring
            "hip_flexor" -> R.string.recording_stretch_instruction_hip_flexor
            "inner_thigh" -> R.string.recording_stretch_instruction_inner_thigh
            else -> R.string.recording_stretch_instruction_quad
        }
        val sideResource = when (side) {
            "left" -> R.string.recording_stretch_side_left
            "right" -> R.string.recording_stretch_side_right
            else -> R.string.recording_stretch_side_both
        }
        return StretchMovement("${prefix}_${id}_${side}", title, instruction, sideResource, seconds)
    }
}

@Composable
fun PostWorkoutStretchRoute(
    kind: ActivityKind,
    track: List<RecordedLocationSample>,
    sessionKey: String,
    onDone: () -> Unit,
    onEvent: (String, String?, String?, Int?) -> Unit,
    fetchAudio: suspend (String, String) -> ByteArray?,
) {
    val routines = remember(kind) { PostWorkoutStretchCatalog.routines(kind) }
    val initialRoutine = routines?.firstOrNull()
    if (initialRoutine == null) {
        onDone()
        return
    }

    var selectedRoutine by remember(kind) { mutableStateOf(initialRoutine) }
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
    val context = androidx.compose.ui.platform.LocalContext.current
    val audio = remember { StretchAudio(context) }
    val view = LocalView.current
    val owner = LocalLifecycleOwner.current
    val movement = selectedRoutine.movements[movementIndex]

    fun advance(skip: Boolean) {
        onEvent("post_workout_stretch_step_ended", selectedRoutine.id, if (skip) "skipped" else "held", stepHeld)
        if (skip) skipped += 1
        stepHeld = 0
        if (movementIndex == selectedRoutine.movements.lastIndex) {
            complete = true
            running = false
            view.keepScreenOn = false
            if (speaks) audio.play("release")
            onEvent("post_workout_stretch_completed", selectedRoutine.id, if (skipped == 0) "fully_held" else "with_skips", totalHeld)
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
        result?.let { onEvent("post_workout_stretch_dismissed", selectedRoutine.id, it, totalHeld) }
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

    LaunchedEffect(selectedRoutine.id) {
        audio.preload(selectedRoutine.movements.map { it.id.substringAfter('_') }.distinct(), fetchAudio)
    }
    LaunchedEffect(speaks) { if (!speaks) audio.stop() }
    LaunchedEffect(running, movementIndex, selectedRoutine.id, phase, speaks) {
        if (running && phase != StretchPhase.HOLD) {
            if (feedback && phase == StretchPhase.TRANSITION) {
                view.performHapticFeedback(android.view.HapticFeedbackConstants.CLOCK_TICK)
                view.playSoundEffect(android.view.SoundEffectConstants.CLICK)
            }
            if (speaks) {
                val started = android.os.SystemClock.elapsedRealtime()
                audio.playAndWait(movement.id.substringAfter('_'), phase == StretchPhase.TRANSITION)
                secondsLeft = maxOf(1, secondsLeft - ((android.os.SystemClock.elapsedRealtime() - started) / 1000).toInt())
            }
        }
        while (running && !complete) {
            if (phase == StretchPhase.HOLD && secondsLeft in 1..5 && speaks) {
                audio.play(listOf("one", "two", "three", "four", "five")[secondsLeft - 1])
            }
            delay(1_000)
            if (phase == StretchPhase.HOLD) { stepHeld += 1; totalHeld += 1 }
            if (secondsLeft <= 1) {
                if (phase != StretchPhase.HOLD) {
                    phase = StretchPhase.HOLD
                    secondsLeft = movement.seconds
                } else advance(false)
            } else secondsLeft -= 1
        }
    }

    LaunchedEffect(sessionKey) {
        onEvent("post_workout_stretch_offered", initialRoutine.id, null, null)
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
    ) {
        if (!chosen) {
            Column(
                modifier = Modifier.fillMaxWidth().weight(1f).verticalScroll(rememberScrollState()).padding(vertical = 20.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                PostSaveCelebrationCard(
                    track = track,
                    sessionKey = sessionKey,
                    modifier = Modifier.fillMaxWidth().height(205.dp),
                )
                Text(
                    stringResource(R.string.recording_post_save_message),
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Text(stringResource(R.string.stretch_offer_title), style = MaterialTheme.typography.headlineSmall)
                Text(stringResource(R.string.stretch_offer_body))
                Text(stringResource(R.string.recording_post_save_program_title), style = MaterialTheme.typography.titleMedium)

                routines.orEmpty().forEach { routine ->
                    StretchRoutineOption(
                        routine = routine,
                        selected = selectedRoutine.id == routine.id,
                        onClick = {
                            selectedRoutine = routine
                            movementIndex = 0
                            onEvent("post_workout_stretch_program_selected", routine.id, null, null)
                        },
                    )
                }

                TextButton(onClick = { preview = !preview }) { Text(stringResource(R.string.stretch_preview)) }
                if (preview) selectedRoutine.movements.forEach { step ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        StretchIllustration(step.id, Modifier.size(56.dp))
                        Column {
                            Text(stringResource(step.title) + " · " + (step.side?.let { stringResource(it) } ?: ""))
                            Text(stringResource(step.instruction), style = MaterialTheme.typography.bodySmall)
                        }
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    androidx.compose.material3.Switch(checked = speaks, onCheckedChange = { speaks = it })
                    Text(stringResource(R.string.stretch_voice))
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    androidx.compose.material3.Switch(checked = feedback, onCheckedChange = { feedback = it })
                    Text(stringResource(R.string.stretch_feedback))
                }
                Button(
                    onClick = {
                        secondsLeft = 3
                        phase = StretchPhase.SETUP
                        chosen = true
                        running = true
                        view.keepScreenOn = true
                        onEvent("post_workout_stretch_started", selectedRoutine.id, null, null)
                    },
                    modifier = Modifier.fillMaxWidth().height(52.dp),
                ) {
                    Text(stringResource(R.string.stretch_start))
                }
                OutlinedButton(
                    onClick = { finish("not_started") },
                    modifier = Modifier.fillMaxWidth().height(48.dp),
                ) {
                    Text(stringResource(R.string.stretch_done))
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
            if (phase != StretchPhase.HOLD) Text(stringResource(R.string.stretch_get_ready))
            Text(stringResource(movement.title), style = MaterialTheme.typography.headlineMedium)
            movement.side?.let { Text(stringResource(it), style = MaterialTheme.typography.titleMedium) }
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
            Row(verticalAlignment = Alignment.CenterVertically) {
                androidx.compose.material3.Switch(checked = speaks, onCheckedChange = { speaks = it })
                Text(stringResource(R.string.stretch_voice))
            }
            TextButton(onClick = { if (running) confirmEnd = true else finish("ended_early") }) {
                Text(stringResource(R.string.stretch_end))
            }
            Spacer(Modifier.weight(1f))
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
            }
            Spacer(Modifier.width(8.dp))
            RadioButton(selected = selected, onClick = onClick)
        }
    }
}

@Composable
private fun StretchIllustration(id: String, modifier: Modifier) {
    val color = MaterialTheme.colorScheme.onSurface
    val accent = MaterialTheme.colorScheme.primary
    androidx.compose.foundation.Canvas(modifier) {
        val cue = id.substringAfter('_')
        val lines = when {
            cue.startsWith("glute") -> listOf(listOf(15f to 75f,35f to 75f,55f to 60f,75f to 60f),listOf(35f to 75f,45f to 45f,60f to 55f),listOf(45f to 45f,70f to 40f,75f to 60f),listOf(55f to 60f,55f to 80f,80f to 80f))
            cue.startsWith("hamstring") -> listOf(listOf(15f to 80f,45f to 80f),listOf(30f to 80f,50f to 55f,57f to 50f),listOf(45f to 80f,80f to 80f),listOf(45f to 80f,60f to 35f))
            cue.startsWith("inner") -> listOf(listOf(50f to 20f,50f to 55f),listOf(50f to 35f,30f to 60f),listOf(50f to 55f,30f to 80f,50f to 75f),listOf(50f to 55f,70f to 80f,50f to 75f))
            cue.startsWith("calf") -> listOf(listOf(65f to 20f,50f to 55f),listOf(60f to 30f,85f to 35f),listOf(50f to 55f,70f to 75f,85f to 75f),listOf(50f to 55f,25f to 85f,15f to 85f))
            cue.startsWith("quad") -> listOf(listOf(50f to 15f,50f to 55f),listOf(50f to 55f,50f to 90f),listOf(50f to 30f,30f to 55f,35f to 65f),listOf(50f to 55f,25f to 80f,35f to 65f))
            else -> listOf(listOf(50f to 15f,50f to 55f),listOf(50f to 35f,70f to 55f),listOf(50f to 55f,70f to 60f,70f to 85f),listOf(50f to 55f,30f to 85f,15f to 85f))
        }
        val scale = minOf(size.width, size.height) / 100f
        val first = lines.first().first()
        val lying = cue.startsWith("glute") || cue.startsWith("hamstring")
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
