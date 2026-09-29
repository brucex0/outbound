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
    onEvent: (String, String?, String?) -> Unit,
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
    val view = LocalView.current
    val owner = LocalLifecycleOwner.current
    val movement = selectedRoutine.movements[movementIndex]

    fun finish(result: String?) {
        running = false
        view.keepScreenOn = false
        result?.let { onEvent("post_workout_stretch_dismissed", selectedRoutine.id, it) }
        onDone()
    }

    DisposableEffect(owner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP || event == Lifecycle.Event.ON_PAUSE) {
                running = false
                view.keepScreenOn = false
            }
        }
        owner.lifecycle.addObserver(observer)
        onDispose {
            owner.lifecycle.removeObserver(observer)
            view.keepScreenOn = false
        }
    }

    LaunchedEffect(running, movementIndex, selectedRoutine.id) {
        while (running && !complete) {
            delay(1_000)
            if (secondsLeft <= 1) {
                if (movementIndex == selectedRoutine.movements.lastIndex) {
                    complete = true
                    running = false
                    view.keepScreenOn = false
                    onEvent("post_workout_stretch_completed", selectedRoutine.id, null)
                } else {
                    movementIndex += 1
                    secondsLeft = selectedRoutine.movements[movementIndex].seconds
                }
            } else {
                secondsLeft -= 1
            }
        }
    }

    LaunchedEffect(sessionKey) {
        onEvent("post_workout_stretch_offered", initialRoutine.id, null)
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
        modifier = Modifier.fillMaxSize().safeDrawingPadding().padding(horizontal = 24.dp),
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
                            onEvent("post_workout_stretch_program_selected", routine.id, null)
                        },
                    )
                }

                Button(
                    onClick = {
                        chosen = true
                        running = true
                        view.keepScreenOn = true
                        onEvent("post_workout_stretch_started", selectedRoutine.id, null)
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
            Text(stringResource(movement.title), style = MaterialTheme.typography.headlineMedium)
            movement.side?.let { Text(stringResource(it), style = MaterialTheme.typography.titleMedium) }
            Text(stringResource(movement.instruction))
            Text(
                text = "${secondsLeft / 60}:${(secondsLeft % 60).toString().padStart(2, '0')}",
                style = MaterialTheme.typography.displayMedium,
            )
            LinearProgressIndicator(
                progress = { movementIndex.toFloat() / selectedRoutine.movements.size },
                modifier = Modifier.fillMaxWidth(),
            )
            Text(stringResource(R.string.stretch_safety))
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Button(onClick = {
                    running = !running
                    view.keepScreenOn = running
                }) {
                    Text(stringResource(if (running) R.string.stretch_pause else R.string.stretch_resume))
                }
                OutlinedButton(onClick = {
                    if (movementIndex == selectedRoutine.movements.lastIndex) {
                        complete = true
                        running = false
                        view.keepScreenOn = false
                        onEvent("post_workout_stretch_completed", selectedRoutine.id, null)
                    } else {
                        movementIndex += 1
                        secondsLeft = selectedRoutine.movements[movementIndex].seconds
                    }
                }) {
                    Text(stringResource(if (movementIndex == selectedRoutine.movements.lastIndex) R.string.stretch_finish else R.string.stretch_next))
                }
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
                Text(stringResource(routine.durationLabel), style = MaterialTheme.typography.bodySmall)
            }
            Spacer(Modifier.width(8.dp))
            RadioButton(selected = selected, onClick = onClick)
        }
    }
}
