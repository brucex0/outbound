package com.plainstride.outbound.feature.recording

import androidx.compose.runtime.collectAsState
import com.plainstride.outbound.core.data.AccountConfigurationStore
import com.plainstride.outbound.core.data.AccountConfigurationValue

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.background
import androidx.compose.material3.*
import androidx.compose.material.icons.filled.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
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
    voiceProfileId: String?,
    fetchAudio: suspend (String, String, String) -> ByteArray?,
    isIndoor: Boolean = false,
) {
    StretchSessionRoute(
        launch = StretchLaunchContext(StretchEntryPoint.POST_SAVE, kind, isIndoor),
        sessionKey = sessionKey, onDone = onDone, onEvent = onEvent, fetchAudio = fetchAudio,
        voiceProfileId = voiceProfileId,
        header = { finish ->
            PostSaveCelebrationCard(track = track, sessionKey = sessionKey, modifier = Modifier.fillMaxWidth().height(205.dp))
            Text(stringResource(R.string.recording_post_save_message), style = MaterialTheme.typography.titleMedium)
            PostSaveActivityActions(onShare = onShare, onDone = finish)
        },
    )
}

/** Reusable standalone stretch flow; Today supplies only launch context and audio/analytics adapters. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StretchSessionRoute(
    launch: StretchLaunchContext = StretchLaunchContext(),
    sessionKey: String,
    onDone: () -> Unit,
    onEvent: (StretchSessionEvent) -> Unit,
    voiceProfileId: String?,
    fetchAudio: suspend (String, String, String) -> ByteArray?,
    header: @Composable (() -> Unit) -> Unit = { _ -> },
) {
    val kind = launch.kind
    val isIndoor = launch.isIndoor
    val context = androidx.compose.ui.platform.LocalContext.current
    var routines by remember(kind, launch.entryPoint) { mutableStateOf(StretchCatalog.routines(context, kind, launch.entryPoint)) }
    val initialRoutine = remember(kind, isIndoor, launch.entryPoint) {
        val remembered = AccountConfigurationStore.record(if (isIndoor) "stretch/last" else "stretch/standing")?.value?.selection
        routines.firstOrNull { it.preferenceId == remembered && (isIndoor || it.isStanding) }
            ?: routines.firstOrNull { it.preferenceId == (if (kind == ActivityKind.SWIMMING) "upper_body" else "standing_quick") && (isIndoor || it.isStanding) }
            ?: routines.firstOrNull { isIndoor || it.isStanding }
            ?: StretchCatalog.outdoorFallback()
    }
    if (initialRoutine == null) {
        LaunchedEffect(Unit) { onDone() }
        return
    }

    var didChooseRoutine by remember { mutableStateOf(false) }
    val configurationRevision by AccountConfigurationStore.changes.collectAsState()
    var selectedRoutine by remember(kind) { mutableStateOf(initialRoutine) }
    var editing by remember { mutableStateOf(false) }
    var chosen by remember { mutableStateOf(false) }
    var movementIndex by remember { mutableIntStateOf(0) }
    var secondsLeft by remember(selectedRoutine.id) { mutableIntStateOf(selectedRoutine.movements.first().seconds) }
    var running by remember { mutableStateOf(false) }
    var complete by remember { mutableStateOf(false) }
    var confirmEnd by remember { mutableStateOf(false) }
    var phase by remember { mutableStateOf(StretchPhase.SETUP) }
    val playerPreferences = remember(context) { context.getSharedPreferences("stretch_player_options_v1", android.content.Context.MODE_PRIVATE) }
    var speaks by remember { mutableStateOf(playerPreferences.getBoolean("voice", true)) }
    var feedback by remember { mutableStateOf(playerPreferences.getBoolean("feedback", false)) }
    var showingDetails by remember { mutableStateOf(false) }
    var showingLibrary by remember { mutableStateOf(false) }
    var showingOptions by remember { mutableStateOf(false) }
    var instruction by remember { mutableStateOf<StretchMovement?>(null) }
    var skipped by remember { mutableIntStateOf(0) }
    var stepHeld by remember { mutableIntStateOf(0) }
    var totalHeld by remember { mutableIntStateOf(0) }
    LaunchedEffect(configurationRevision) {
        if (!chosen && !editing) {
            routines = StretchCatalog.routines(context, kind, launch.entryPoint)
            if (!didChooseRoutine) {
                val remembered = AccountConfigurationStore.record(if (isIndoor) "stretch/last" else "stretch/standing")?.value?.selection
                selectedRoutine = routines.firstOrNull { it.preferenceId == remembered && (isIndoor || it.isStanding) }
                    ?: routines.firstOrNull { it.preferenceId == (if (kind == ActivityKind.SWIMMING) "upper_body" else "standing_quick") && (isIndoor || it.isStanding) }
                    ?: routines.firstOrNull { isIndoor || it.isStanding } ?: StretchCatalog.outdoorFallback()
                movementIndex = 0
            }
        }
    }

    fun emit(name: String, routineID: String?, result: String?, seconds: Int?) {
        onEvent(StretchSessionEvent(name, routineID, result, seconds, launch.entryPoint, selectedRoutine.customized, selectedRoutine.entries.size, selectedRoutine.totalSeconds))
    }
    val audio = remember(context, voiceProfileId) { StretchAudio(context, voiceProfileId) }
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

    DisposableEffect(owner, audio) {
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

    LaunchedEffect(selectedRoutine.movements.map { it.cue }, audio) {
        if (voiceProfileId != null) {
            val ready = audio.preload(selectedRoutine.movements.map { it.cue }.distinct(), fetchAudio)
            emit("stretch_interface_used", selectedRoutine.id, if (ready) "audio_ready" else "audio_unavailable", null)
        }
    }
    LaunchedEffect(speaks, audio) { if (!speaks) audio.stop() }
    LaunchedEffect(running, movementIndex, selectedRoutine.id, phase, speaks, audio) {
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

    fun pauseForSheet() {
        running = false
        audio.stop()
        view.keepScreenOn = false
    }
    fun closeScreen() {
        when {
            complete -> finish(null)
            running -> confirmEnd = true
            chosen -> finish("ended_early")
            launch.entryPoint == StretchEntryPoint.POST_SAVE && showingDetails -> showingDetails = false
            else -> finish("not_started")
        }
    }
    fun showInstructions(step: StretchMovement) {
        if (chosen) pauseForSheet()
        instruction = step
        emit("stretch_interface_used", selectedRoutine.id, "instructions_opened", null)
    }
    BackHandler(onBack = ::closeScreen)

    Surface(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().safeDrawingPadding(), horizontalAlignment = Alignment.CenterHorizontally) {
            if (!complete && (chosen || launch.entryPoint != StretchEntryPoint.POST_SAVE || showingDetails)) {
                StretchScreenHeader(
                    title = if (chosen) stringResource(R.string.stretch_ui_step, movementIndex + 1, selectedRoutine.movements.size) else stringResource(selectedRoutine.title),
                    onClose = ::closeScreen,
                    onOptions = {
                        if (chosen) pauseForSheet()
                        showingOptions = true
                        emit("stretch_interface_used", selectedRoutine.id, "options_opened", null)
                    },
                )
            }
            if (!chosen) {
                Column(
                    Modifier.weight(1f).widthIn(max = 560.dp).fillMaxWidth().verticalScroll(rememberScrollState()).padding(24.dp),
                    verticalArrangement = Arrangement.spacedBy(20.dp),
                ) {
                    if (launch.entryPoint == StretchEntryPoint.POST_SAVE && !showingDetails) {
                        header { finish("not_started") }
                        Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.07f)), shape = RoundedCornerShape(24.dp)) {
                            Column(Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                Text(stringResource(R.string.stretch_offer_title), style = MaterialTheme.typography.headlineSmall)
                                Text(stringResource(selectedRoutine.title), style = MaterialTheme.typography.titleMedium)
                                Text("≈ ${stretchClock(selectedRoutine.totalSeconds)} · ${selectedRoutine.requirements(context)}", style = MaterialTheme.typography.bodyMedium)
                                TextButton(onClick = { showingDetails = true }) { Text(stringResource(R.string.stretch_ui_change)) }
                            }
                        }
                    } else {
                        StretchRoutineDetails(selectedRoutine,
                            onChange = { showingLibrary = true; emit("stretch_interface_used", selectedRoutine.id, "routines_opened", null) },
                            onEdit = { didChooseRoutine = true; editing = true; emit("stretch_routine_edited", selectedRoutine.id, "opened", null) },
                            onInstructions = ::showInstructions,
                        )
                    }
                    Text(stringResource(R.string.stretch_disclaimer), Modifier.fillMaxWidth(), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
                }
                Surface(shadowElevation = 3.dp) {
                    Button(onClick = {
                        secondsLeft = 3
                        phase = StretchPhase.SETUP
                        AccountConfigurationStore.set("stretch/last", AccountConfigurationValue(selection = selectedRoutine.preferenceId))
                        if (selectedRoutine.isStanding) AccountConfigurationStore.set("stretch/standing", AccountConfigurationValue(selection = selectedRoutine.preferenceId))
                        chosen = true
                        running = true
                        view.keepScreenOn = true
                        emit("post_workout_stretch_started", selectedRoutine.id, null, null)
                    }, modifier = Modifier.padding(horizontal = 24.dp, vertical = 12.dp).widthIn(max = 512.dp).fillMaxWidth().heightIn(min = 52.dp)) {
                        Text(stringResource(R.string.stretch_catalog_ui_start))
                    }
                }
            } else if (complete) {
                Spacer(Modifier.weight(1f))
                Icon(Icons.Default.CheckCircle, null, Modifier.size(72.dp), tint = MaterialTheme.colorScheme.primary)
                Text(stringResource(R.string.stretch_complete_title), style = MaterialTheme.typography.headlineMedium, modifier = Modifier.padding(20.dp))
                Button(onClick = { finish(null) }) { Text(stringResource(R.string.stretch_done)) }
                Spacer(Modifier.weight(1f))
            } else {
                BoxWithConstraints(Modifier.weight(1f).widthIn(max = 560.dp).fillMaxWidth()) {
                    val illustrationHeight = (maxHeight * 0.43f).coerceIn(180.dp, 320.dp)
                    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 28.dp, vertical = 12.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                        StretchIllustration(movement.id, Modifier.fillMaxWidth().height(illustrationHeight).background(MaterialTheme.colorScheme.primary.copy(alpha = 0.05f), RoundedCornerShape(32.dp)).padding(12.dp))
                        if (phase != StretchPhase.HOLD) Text(stringResource(if (phase == StretchPhase.TRANSITION) R.string.stretch_transition else R.string.stretch_get_ready), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(stringResource(movement.title), style = MaterialTheme.typography.headlineSmall, textAlign = TextAlign.Center)
                        movement.side?.let { Text(stringResource(it), style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary) }
                        if (selectedRoutine.isWarmup) Text(stringResource(R.string.stretch_catalog_ui_move), style = MaterialTheme.typography.labelLarge)
                        Text(stretchClock(secondsLeft), style = MaterialTheme.typography.displayLarge, fontWeight = FontWeight.SemiBold)
                        LinearProgressIndicator(progress = { (movementIndex + if (phase == StretchPhase.HOLD) 1f - secondsLeft.toFloat() / movement.seconds else 0f) / selectedRoutine.movements.size }, modifier = Modifier.fillMaxWidth())
                        val requirement = selectedRoutine.copy(entries = listOf(selectedRoutine.entries.first { movement.id.startsWith(it.movementID + "_") })).requirements(context)
                        if (requirement != stringResource(R.string.stretch_catalog_ui_none)) Text(requirement, style = MaterialTheme.typography.labelMedium, textAlign = TextAlign.Center)
                        Text(stringResource(R.string.stretch_safety), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
                    }
                }
                Column(Modifier.widthIn(max = 560.dp).fillMaxWidth().padding(horizontal = 24.dp, vertical = 16.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    if (movementIndex < selectedRoutine.movements.lastIndex) {
                        val next = selectedRoutine.movements[movementIndex + 1]
                        Text(stringResource(R.string.stretch_up_next) + ": " + stringResource(next.title) + " · " + (next.side?.let { stringResource(it) } ?: ""), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(24.dp), verticalAlignment = Alignment.CenterVertically) {
                        IconButton(onClick = { showInstructions(movement) }) { Icon(Icons.Default.Info, stringResource(R.string.stretch_ui_instructions)) }
                        FilledIconButton(onClick = { audio.stop(); running = !running; view.keepScreenOn = running }, modifier = Modifier.size(76.dp), shape = CircleShape) {
                            Icon(if (running) Icons.Default.Pause else Icons.Default.PlayArrow, stringResource(if (running) R.string.stretch_pause else R.string.stretch_resume), Modifier.size(32.dp))
                        }
                        IconButton(onClick = {
                            audio.stop()
                            if (phase != StretchPhase.HOLD) { phase = StretchPhase.HOLD; secondsLeft = movement.seconds } else advance(true)
                        }) { Icon(Icons.Default.SkipNext, stringResource(if (phase != StretchPhase.HOLD) R.string.stretch_start_now else R.string.stretch_next)) }
                    }
                }
            }
        }
    }

    if (showingLibrary) {
        StretchSheet(stringResource(R.string.stretch_ui_routines), { showingLibrary = false }) {
            Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                val choices = if (routines.none { it.id == selectedRoutine.id }) listOf(selectedRoutine) + routines else routines
                choices.forEach { routine ->
                    StretchRoutineOption(routine, selectedRoutine.id == routine.id) {
                        if (selectedRoutine.id != routine.id) {
                            didChooseRoutine = true
                            selectedRoutine = routine
                            movementIndex = 0
                            emit("post_workout_stretch_program_selected", routine.id, null, null)
                        }
                        showingLibrary = false
                    }
                }
            }
        }
    }
    if (showingOptions) {
        StretchSheet(stringResource(R.string.stretch_ui_options), { showingOptions = false }) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                StretchSettingToggle(stringResource(R.string.stretch_voice), speaks) {
                    speaks = it
                    playerPreferences.edit().putBoolean("voice", it).apply()
                    emit("stretch_interface_used", selectedRoutine.id, if (it) "voice_enabled" else "voice_disabled", null)
                }
                StretchSettingToggle(stringResource(R.string.stretch_feedback), feedback) {
                    feedback = it
                    playerPreferences.edit().putBoolean("feedback", it).apply()
                    emit("stretch_interface_used", selectedRoutine.id, if (it) "feedback_enabled" else "feedback_disabled", null)
                }
            }
        }
    }
    instruction?.let { step -> StretchSheet(stringResource(R.string.stretch_ui_instructions), { instruction = null }) {
        Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            StretchIllustration(step.id, Modifier.fillMaxWidth().height(260.dp))
            Text(stringResource(step.title), style = MaterialTheme.typography.headlineSmall)
            Text(stringResource(step.instruction))
            Text(stringResource(R.string.stretch_safety), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    } }

    if (editing) {
        StretchRoutineEditor(selectedRoutine, onDismiss = { editing = false }, onAction = { action -> emit("stretch_routine_edited", selectedRoutine.id, action, null) }) { entries ->
            val saved = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) { StretchCustomizationStore(context).save(selectedRoutine.preferenceId, entries) }
            if (saved) {
                routines = StretchCatalog.routines(context, kind, launch.entryPoint)
                selectedRoutine = routines.first { it.preferenceId == selectedRoutine.preferenceId }
                movementIndex = 0
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

internal fun stretchClock(seconds: Int): String = String.format(java.util.Locale.getDefault(), "%d:%02d", seconds / 60, seconds % 60)

@Composable
private fun StretchScreenHeader(title: String, onClose: () -> Unit, onOptions: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = onClose) { Icon(Icons.Default.Close, stringResource(R.string.stretch_done)) }
        Text(title, Modifier.weight(1f), style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
        IconButton(onClick = onOptions) { Icon(Icons.Default.MoreHoriz, stringResource(R.string.stretch_ui_options)) }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun StretchSheet(title: String, onDismiss: () -> Unit, content: @Composable () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(title, Modifier.weight(1f).semantics { heading() }, style = MaterialTheme.typography.titleLarge)
                TextButton(onClick = onDismiss) { Text(stringResource(R.string.stretch_done)) }
            }
            content()
        }
    }
}

@Composable
private fun StretchRoutineDetails(routine: StretchRoutine, onChange: () -> Unit, onEdit: () -> Unit, onInstructions: (StretchMovement) -> Unit) {
    val context = androidx.compose.ui.platform.LocalContext.current
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("≈ ${stretchClock(routine.totalSeconds)}", style = MaterialTheme.typography.headlineSmall)
            Text(routine.requirements(context), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (routine.customized) Text(stringResource(R.string.stretch_catalog_ui_your_version), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
        }
        TextButton(onClick = onChange) { Text(stringResource(R.string.stretch_ui_change)) }
    }
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(stringResource(R.string.stretch_ui_movements), Modifier.weight(1f).semantics { heading() }, style = MaterialTheme.typography.titleMedium)
        TextButton(onClick = onEdit) { Text(stringResource(R.string.stretch_catalog_ui_customize)) }
    }
    Column {
        routine.entries.forEachIndexed { index, entry ->
            val definition = StretchCatalog.definition(entry.movementID) ?: return@forEachIndexed
            val step = routine.movements.first { it.id.startsWith(entry.movementID + "_") }
            Surface(onClick = { onInstructions(step) }) {
                Row(Modifier.fillMaxWidth().padding(vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
                    StretchIllustration(step.id, Modifier.size(72.dp, 80.dp).background(MaterialTheme.colorScheme.primary.copy(alpha = 0.05f), RoundedCornerShape(16.dp)).padding(4.dp))
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                        Text(stringResource(definition.title), style = MaterialTheme.typography.titleSmall)
                        Text(stretchClock(entry.seconds) + if (definition.bilateral) " · " + stringResource(R.string.stretch_ui_each_side) else "", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Icon(Icons.Default.Info, null, Modifier.size(20.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            if (index != routine.entries.lastIndex) HorizontalDivider()
        }
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
