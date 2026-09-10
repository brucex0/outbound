package com.plainstride.outbound.feature.recording

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import java.io.File
import java.util.UUID
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import com.plainstride.outbound.core.designsystem.MapCoordinate
import com.plainstride.outbound.core.designsystem.PlainstrideRouteMap

data class RecordedActivityReview(
    val snapshot: RecordingSnapshot,
    val reflection: ReflectionChoice,
    /** App-private path; callers must not expose it without an explicit share action. */
    val photoPath: String?,
)

@Composable
fun RecordingRoute(
    accountId: String,
    launch: RecordingLaunchConfiguration,
    onSaved: (RecordedActivityReview) -> Unit,
    onExit: () -> Unit,
    modifier: Modifier = Modifier,
    sessionEffect: @Composable (RecordingSnapshot) -> Unit = {},
    viewModel: RecordingViewModel = hiltViewModel(),
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val ui by viewModel.state.collectAsStateWithLifecycle()
    val snapshot by viewModel.snapshot.collectAsStateWithLifecycle()
    val voiceListening by viewModel.voiceListening.collectAsStateWithLifecycle()
    sessionEffect(snapshot)
    var askedForLocation by remember { mutableStateOf(false) }
    var pendingResume by remember { mutableStateOf(false) }
    var showLocationEducation by remember { mutableStateOf(false) }
    var showCameraEducation by remember { mutableStateOf(false) }
    val saveSnackbar = remember { SnackbarHostState() }
    val saveFailedMessage = stringResource(R.string.recording_save_failed)

    fun permissionState(): LocationPermissionState {
        val precise = context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val approximate = context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        return when {
            precise -> LocationPermissionState.PRECISE
            approximate -> LocationPermissionState.APPROXIMATE
            askedForLocation -> LocationPermissionState.DENIED
            else -> LocationPermissionState.NOT_REQUESTED
        }
    }

    fun beginCountdown() {
        pendingResume = false
        val permission = permissionState()
        if (permission == LocationPermissionState.PRECISE || permission == LocationPermissionState.APPROXIMATE) {
            viewModel.updateCountdown(3)
        } else showLocationEducation = true
    }

    LaunchedEffect(launch) {
        viewModel.configure(launch)
        if (launch.startImmediately && snapshot.status == RecordingStatus.IDLE) beginCountdown()
    }

    LaunchedEffect(accountId) { viewModel.recover(accountId, permissionState()) }

    val locationPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) {
        askedForLocation = true
        viewModel.updatePermission(permissionState())
        if (permissionState() == LocationPermissionState.DENIED) showLocationEducation = true
        else if (pendingResume) { pendingResume = false; viewModel.resume() }
        else viewModel.updateCountdown(3)
    }
    val cameraPermissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        showCameraEducation = !granted
        if (granted) viewModel.setMode(RecordingSurfaceMode.CAMERA)
    }
    val microphonePermissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        viewModel.listen(granted)
    }
    fun listenForCommand() {
        val granted = context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        if (granted) viewModel.listen(true) else microphonePermissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
    }
    var pendingPhoto by remember { mutableStateOf<File?>(null) }
    val photoLauncher = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { saved ->
        val file = pendingPhoto
        if (saved && file != null) viewModel.setPhotoPath(file.absolutePath) else file?.delete()
        pendingPhoto = null
        viewModel.setPendingMedia(false)
    }
    fun capturePhoto() {
        viewModel.trackPhotoAttempt()
        if (context.checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            cameraPermissionLauncher.launch(Manifest.permission.CAMERA)
            return
        }
        val directory = File(context.filesDir, "activity_photos").apply { mkdirs() }
        val file = File(directory, "${UUID.randomUUID()}.jpg")
        pendingPhoto = file
        viewModel.setPendingMedia(true)
        val uri = androidx.core.content.FileProvider.getUriForFile(context, "${context.packageName}.activityphotos", file)
        photoLauncher.launch(uri)
    }

    LaunchedEffect(ui.countdown) {
        val current = ui.countdown ?: return@LaunchedEffect
        delay(1_000)
        if (current > 1) viewModel.updateCountdown(current - 1)
        else viewModel.start(accountId, permissionState())
    }

    val content: @Composable () -> Unit = {
        when {
            ui.countdown != null -> CountdownScreen(ui.countdown!!, onCancel = { viewModel.updateCountdown(null) })
            snapshot.status == RecordingStatus.AWAITING_SAVE -> ReflectionScreen(
                snapshot = snapshot,
                selected = ui.reflection,
                photoPath = ui.photoPath,
                onSelect = viewModel::setReflection,
                onTakePhoto = ::capturePhoto,
                onRemovePhoto = { ui.photoPath?.let(::File)?.delete(); viewModel.setPhotoPath(null) },
                onSave = {
                    val reflection = ui.reflection ?: return@ReflectionScreen
                    scope.launch {
                        val review = RecordedActivityReview(snapshot, reflection, ui.photoPath)
                        if (viewModel.saveFinished(review)) {
                            viewModel.markSaved()
                            onSaved(review)
                        } else {
                            saveSnackbar.showSnackbar(saveFailedMessage)
                        }
                    }
                },
                saving = ui.saving,
                onClose = viewModel::requestDiscard,
            )
            snapshot.status == RecordingStatus.ACTIVE || snapshot.status == RecordingStatus.PAUSED -> LiveRecordingScreen(
                snapshot = snapshot,
                configuration = ui.launch,
                mode = ui.mode,
                photoPath = ui.photoPath,
                onMode = { mode ->
                    if (mode == RecordingSurfaceMode.CAMERA && context.checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
                        cameraPermissionLauncher.launch(Manifest.permission.CAMERA)
                    } else viewModel.setMode(mode)
                },
                onTakePhoto = ::capturePhoto,
                onPhotoCaptured = viewModel::setPhotoPath,
                onPhotoPending = viewModel::setPendingMedia,
                onPause = viewModel::pause,
                onResume = {
                    val permission = permissionState()
                    if (permission == LocationPermissionState.PRECISE || permission == LocationPermissionState.APPROXIMATE) viewModel.resume()
                    else { pendingResume = true; showLocationEducation = true }
                },
                onFinish = viewModel::requestFinish,
                finishEnabled=!ui.pendingMedia,
                onListen = ::listenForCommand,
                voiceListening = voiceListening,
                onDashboardChanged = viewModel::trackDashboardChanged,
            )
            else -> ActivitySetupScreen(ui.launch, permissionState(), onStart = ::beginCountdown, onExit = onExit)
        }
    }

    Box(modifier.fillMaxSize()) {
        content()
        SnackbarHost(saveSnackbar, Modifier.align(Alignment.BottomCenter))
    }

    if (showLocationEducation) PermissionEducationDialog(
        title = stringResource(R.string.recording_location_permission_title),
        body = stringResource(if (askedForLocation) R.string.recording_location_permission_denied else R.string.recording_location_permission_body),
        confirm = stringResource(if (askedForLocation) R.string.recording_open_settings else R.string.recording_continue),
        onConfirm = {
            showLocationEducation = false
            if (askedForLocation) context.openAppSettings()
            else locationPermissionLauncher.launch(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION))
        },
        onDismiss = { showLocationEducation = false },
    )
    if (showCameraEducation) PermissionEducationDialog(
        title = stringResource(R.string.recording_camera_permission_title),
        body = stringResource(R.string.recording_camera_permission_body),
        confirm = stringResource(R.string.recording_open_settings),
        onConfirm = { showCameraEducation = false; context.openAppSettings() },
        onDismiss = { showCameraEducation = false },
    )
    if (ui.showFinishConfirmation) AlertDialog(
        onDismissRequest = viewModel::cancelFinish,
        title = { Text(stringResource(R.string.recording_finish_title)) },
        text = { Text(stringResource(R.string.recording_finish_body)) },
        confirmButton = { TextButton(onClick = viewModel::finish) { Text(stringResource(R.string.recording_finish)) } },
        dismissButton = { TextButton(onClick = viewModel::cancelFinish) { Text(stringResource(R.string.recording_keep_going)) } },
    )
    if (ui.showDiscardConfirmation) AlertDialog(
        onDismissRequest = viewModel::cancelDiscard,
        title = { Text(stringResource(R.string.recording_discard_title)) },
        text = { Text(stringResource(R.string.recording_discard_body)) },
        confirmButton = { TextButton(onClick = {
            ui.photoPath?.let(::File)?.delete()
            viewModel.discard()
            onExit()
        }) { Text(stringResource(R.string.recording_discard)) } },
        dismissButton = { TextButton(onClick = viewModel::cancelDiscard) { Text(stringResource(R.string.recording_cancel)) } },
    )
}

@Composable
private fun ActivitySetupScreen(
    configuration: RecordingLaunchConfiguration,
    permission: LocationPermissionState,
    onStart: () -> Unit,
    onExit: () -> Unit,
) {
    Scaffold(contentWindowInsets = WindowInsets.safeDrawing) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding).padding(horizontal = 20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item {
                TextButton(onClick = onExit) { Text(stringResource(R.string.recording_close)) }
                Text(configuration.title ?: stringResource(R.string.recording_freestyle), style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold)
                Text(goalLabel(configuration.goal), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (configuration.workoutSteps.isNotEmpty()) {
                item { Text(stringResource(R.string.recording_workout_plan), style = MaterialTheme.typography.titleMedium) }
                itemsIndexed(configuration.workoutSteps) { index, step -> WorkoutStepRow(index, step) }
            }
            item {
                if (permission == LocationPermissionState.APPROXIMATE) {
                    PermissionBanner(stringResource(R.string.recording_approximate_warning))
                }
                Button(onClick = onStart, modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp)) {
                    Icon(Icons.Default.PlayArrow, null)
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(R.string.recording_start))
                }
                Spacer(Modifier.height(24.dp))
            }
        }
    }
}

@Composable
private fun CountdownScreen(value: Int, onCancel: () -> Unit) {
    Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.primary), contentAlignment = Alignment.Center) {
        Text(value.toString(), style = MaterialTheme.typography.displayLarge, color = MaterialTheme.colorScheme.onPrimary, fontWeight = FontWeight.Black,
            modifier = Modifier.semantics { contentDescription = value.toString() })
        TextButton(onClick = onCancel, modifier = Modifier.align(Alignment.BottomCenter).padding(32.dp)) {
            Text(stringResource(R.string.recording_cancel), color = MaterialTheme.colorScheme.onPrimary)
        }
    }
}

@Composable
private fun LiveRecordingScreen(
    snapshot: RecordingSnapshot,
    configuration: RecordingLaunchConfiguration,
    mode: RecordingSurfaceMode,
    photoPath: String?,
    onMode: (RecordingSurfaceMode) -> Unit,
    onTakePhoto: () -> Unit,
    onPhotoCaptured: (String) -> Unit,
    onPhotoPending:(Boolean)->Unit,
    onPause: () -> Unit,
    onResume: () -> Unit,
    onFinish: () -> Unit,
    finishEnabled:Boolean,
    onListen: () -> Unit,
    voiceListening: Boolean,
    onDashboardChanged: (Boolean) -> Unit,
) {
    var dashboardExpanded by remember { mutableStateOf(false) }
    Box(Modifier.fillMaxSize().background(if (mode == RecordingSurfaceMode.CAMERA) Color.Black else MaterialTheme.colorScheme.surface)) {
        if (mode == RecordingSurfaceMode.MAP) TrackMap(snapshot.track, Modifier.fillMaxSize())
        else CameraSurface(photoPath, onPhotoCaptured, onTakePhoto,onPhotoPending, Modifier.fillMaxSize())

        Row(Modifier.align(Alignment.TopEnd).padding(16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Surface(shape = CircleShape, tonalElevation = 6.dp) {
                IconButton(onClick = onListen) {
                    Icon(
                        Icons.Default.Mic,
                        contentDescription = stringResource(R.string.recording_voice_command),
                        tint = if (voiceListening) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
                    )
                }
            }
            Surface(shape = CircleShape, tonalElevation = 6.dp) {
                IconButton(onClick = { onMode(if (mode == RecordingSurfaceMode.MAP) RecordingSurfaceMode.CAMERA else RecordingSurfaceMode.MAP) }) {
                    Icon(if (mode == RecordingSurfaceMode.MAP) Icons.Default.CameraAlt else Icons.Default.Map,
                        contentDescription = stringResource(if (mode == RecordingSurfaceMode.MAP) R.string.recording_show_camera else R.string.recording_show_map))
                }
            }
        }
        SessionDashboard(snapshot, configuration, dashboardExpanded, {
            dashboardExpanded = it
            onDashboardChanged(it)
        }, Modifier.align(Alignment.BottomCenter), onPause, onResume, onFinish, finishEnabled)
    }
}

@Composable
private fun TrackMap(track: List<RecordedLocationSample>, modifier: Modifier = Modifier) {
    PlainstrideRouteMap(track.map { MapCoordinate(it.latitude, it.longitude) }, modifier)
    Box(modifier, contentAlignment = Alignment.Center) {
        if (track.isEmpty()) Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(Icons.Default.MyLocation, null)
            Text(stringResource(R.string.recording_acquiring_location))
        }
    }
}

@Composable
private fun CameraSurface(photoPath: String?, onCaptured: (String) -> Unit, onTakePhoto: () -> Unit,onPending:(Boolean)->Unit, modifier: Modifier = Modifier) {
    Box(modifier, contentAlignment = Alignment.Center) {
        val bitmap = remember(photoPath) { photoPath?.let { BitmapFactory.decodeFile(it) } }
        if (bitmap != null) Image(bitmap.asImageBitmap(), contentDescription = stringResource(R.string.recording_activity_photo), modifier = Modifier.fillMaxSize())
        else InAppCamera({onPending(false);onCaptured(it)},{onPending(false);onTakePhoto()},onPending,Modifier.fillMaxSize())
    }
}

@Composable
private fun SessionDashboard(
    snapshot: RecordingSnapshot,
    configuration: RecordingLaunchConfiguration,
    expanded: Boolean,
    onExpandedChanged: (Boolean) -> Unit,
    modifier: Modifier,
    onPause: () -> Unit,
    onResume: () -> Unit,
    onFinish: () -> Unit,
    finishEnabled:Boolean,
) {
    Card(
        modifier.fillMaxWidth()
            .then(if (expanded) Modifier.fillMaxSize().padding(top = 72.dp) else Modifier.padding(12.dp))
            .pointerInput(expanded) {
                detectVerticalDragGestures { _, amount ->
                    if (amount < -12) onExpandedChanged(true)
                    if (amount > 12) onExpandedChanged(false)
                }
            },
        shape = if (expanded) RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp) else RoundedCornerShape(28.dp),
        elevation = CardDefaults.cardElevation(10.dp),
    ) {
        Column(Modifier.padding(horizontal = 20.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(if (expanded) 24.dp else 12.dp)) {
            IconButton(onClick = { onExpandedChanged(!expanded) }, modifier = Modifier.align(Alignment.CenterHorizontally).size(36.dp)) {
                Icon(
                    if (expanded) Icons.Default.ExpandMore else Icons.Default.ExpandLess,
                    contentDescription = stringResource(R.string.recording_activity_in_progress),
                )
            }
            Text(configuration.title ?: stringResource(R.string.recording_activity_in_progress), style = MaterialTheme.typography.titleMedium)
            PrimaryGoalMetric(snapshot, configuration.goal, expanded)
            if (expanded) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Metric(stringResource(R.string.recording_time), formatDuration(snapshot.elapsedSeconds))
                    Metric(stringResource(R.string.recording_distance), formatDistance(snapshot.distanceMeters))
                    Metric(stringResource(R.string.recording_pace), formatPace(snapshot.currentPaceSecondsPerKilometer))
                }
                configuration.workoutSteps.firstOrNull()?.let { step ->
                    Text(step.title, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary)
                    step.detail?.let { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                }
                configuration.followedRoute?.let { Text(it.name, style = MaterialTheme.typography.titleMedium) }
            }
            goalProgress(snapshot, configuration.goal)?.let { progress ->
                androidx.compose.material3.LinearProgressIndicator(progress = { progress }, modifier = Modifier.fillMaxWidth())
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Button(onClick = if (snapshot.status == RecordingStatus.ACTIVE) onPause else onResume, modifier = Modifier.weight(1f).heightIn(min = 56.dp)) {
                    Icon(if (snapshot.status == RecordingStatus.ACTIVE) Icons.Default.Pause else Icons.Default.PlayArrow, null)
                    Spacer(Modifier.width(8.dp)); Text(stringResource(if (snapshot.status == RecordingStatus.ACTIVE) R.string.recording_pause else R.string.recording_resume))
                }
                if (snapshot.status == RecordingStatus.PAUSED) FilledIconButton(onClick = onFinish,enabled=finishEnabled, modifier = Modifier.size(56.dp)) {
                    Icon(Icons.Default.Stop, stringResource(R.string.recording_finish))
                }
            }
        }
    }
}

@Composable
private fun PrimaryGoalMetric(snapshot: RecordingSnapshot, goal: RecordingGoal, expanded: Boolean) {
    val (label, value) = when (goal.type) {
        RecordingGoalType.TIME -> stringResource(R.string.recording_time) to "${formatDuration(snapshot.elapsedSeconds)} / ${formatDuration(goal.targetDurationSeconds ?: 0)}"
        RecordingGoalType.DISTANCE -> stringResource(R.string.recording_distance) to "${formatDistance(snapshot.distanceMeters)} / ${formatDistance(goal.targetDistanceMeters ?: 0.0)}"
        RecordingGoalType.CALORIES -> stringResource(R.string.recording_goal_workout) to stringResource(R.string.recording_goal_calories, goal.targetCalories ?: 0)
        RecordingGoalType.FREESTYLE, RecordingGoalType.WORKOUT -> stringResource(R.string.recording_distance) to formatDistance(snapshot.distanceMeters)
    }
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, style = if (expanded) MaterialTheme.typography.displayMedium else MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Black)
        Text(label, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable private fun Metric(label: String, value: String) = Column(horizontalAlignment = Alignment.CenterHorizontally) {
    Text(value, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
    Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

@Composable
private fun ReflectionScreen(
    snapshot: RecordingSnapshot,
    selected: ReflectionChoice?,
    photoPath: String?,
    onSelect: (ReflectionChoice) -> Unit,
    onTakePhoto: () -> Unit,
    onRemovePhoto: () -> Unit,
    onSave: () -> Unit,
    saving: Boolean,
    onClose: () -> Unit,
) {
    Scaffold(contentWindowInsets = WindowInsets.safeDrawing) { padding ->
        LazyColumn(Modifier.fillMaxSize().padding(padding).padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            item {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.recording_nice_work), style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold)
                    IconButton(onClick = onClose) { Icon(Icons.Default.Delete, stringResource(R.string.recording_close)) }
                }
                Text(stringResource(R.string.recording_reflection_prompt), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            item {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Metric(stringResource(R.string.recording_time), formatDuration(snapshot.elapsedSeconds))
                    Metric(stringResource(R.string.recording_distance), formatDistance(snapshot.distanceMeters))
                    Metric(stringResource(R.string.recording_elevation), "${snapshot.elevationGainMeters.toInt()} m")
                }
            }
            item {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    ReflectionChoice.entries.forEach { choice ->
                        val label = stringResource(when (choice) {
                            ReflectionChoice.STRONG -> R.string.recording_reflection_strong
                            ReflectionChoice.STEADY -> R.string.recording_reflection_steady
                            ReflectionChoice.TOUGH -> R.string.recording_reflection_tough
                        })
                        if (selected == choice) Button(onClick = { onSelect(choice) }, modifier = Modifier.weight(1f)) { Text(label) }
                        else OutlinedButton(onClick = { onSelect(choice) }, modifier = Modifier.weight(1f)) { Text(label) }
                    }
                }
            }
            item {
                if (photoPath == null) OutlinedButton(onClick = onTakePhoto, modifier = Modifier.fillMaxWidth()) {
                    Icon(Icons.Default.CameraAlt, null); Spacer(Modifier.width(8.dp)); Text(stringResource(R.string.recording_add_photo))
                } else Card(Modifier.fillMaxWidth().clickable(onClick = onTakePhoto)) {
                    val bitmap = remember(photoPath) { BitmapFactory.decodeFile(photoPath) }
                    bitmap?.let { Image(it.asImageBitmap(), stringResource(R.string.recording_activity_photo), Modifier.fillMaxWidth().aspectRatio(16f / 9f)) }
                    TextButton(onClick = onRemovePhoto) { Text(stringResource(R.string.recording_remove_photo)) }
                }
            }
            item {
                Button(onClick = onSave, enabled = selected != null && !saving, modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp)) {
                    Text(stringResource(if (saving) R.string.recording_saving_activity else R.string.recording_save_activity))
                }
                if (snapshot.saveEligibility == ActivitySaveEligibility.TOO_SHORT) {
                    Text(stringResource(R.string.recording_short_activity), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(top = 8.dp))
                }
            }
        }
    }
}

@Composable private fun WorkoutStepRow(index: Int, step: StructuredWorkoutStep) = Card(Modifier.fillMaxWidth()) {
    Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
        Surface(shape = CircleShape, color = MaterialTheme.colorScheme.primaryContainer) { Text("${index + 1}", Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) }
        Spacer(Modifier.width(12.dp)); Column { Text(step.title, fontWeight = FontWeight.SemiBold); step.detail?.let { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant) } }
    }
}

@Composable private fun PermissionBanner(text: String) = Surface(color = MaterialTheme.colorScheme.secondaryContainer, shape = RoundedCornerShape(16.dp)) {
    Text(text, Modifier.fillMaxWidth().padding(16.dp), color = MaterialTheme.colorScheme.onSecondaryContainer)
}

@Composable private fun PermissionEducationDialog(title: String, body: String, confirm: String, onConfirm: () -> Unit, onDismiss: () -> Unit) = AlertDialog(
    onDismissRequest = onDismiss,
    title = { Text(title) }, text = { Text(body) },
    confirmButton = { TextButton(onClick = onConfirm) { Text(confirm) } },
    dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.recording_not_now)) } },
)

@Composable private fun goalLabel(goal: RecordingGoal): String = when (goal.type) {
    RecordingGoalType.FREESTYLE -> stringResource(R.string.recording_goal_freestyle)
    RecordingGoalType.DISTANCE -> stringResource(R.string.recording_goal_distance, formatDistance(goal.targetDistanceMeters ?: 0.0))
    RecordingGoalType.TIME -> stringResource(R.string.recording_goal_time, formatDuration(goal.targetDurationSeconds ?: 0))
    RecordingGoalType.CALORIES -> stringResource(R.string.recording_goal_calories, goal.targetCalories ?: 0)
    RecordingGoalType.WORKOUT -> stringResource(R.string.recording_goal_workout)
}

private fun goalProgress(snapshot: RecordingSnapshot, goal: RecordingGoal): Float? = when (goal.type) {
    RecordingGoalType.DISTANCE -> goal.targetDistanceMeters?.takeIf { it > 0 }?.let { (snapshot.distanceMeters / it).toFloat().coerceIn(0f, 1f) }
    RecordingGoalType.TIME -> goal.targetDurationSeconds?.takeIf { it > 0 }?.let { (snapshot.elapsedSeconds.toDouble() / it).toFloat().coerceIn(0f, 1f) }
    else -> null
}

internal fun formatDuration(seconds: Long): String = "%d:%02d:%02d".format(seconds / 3600, seconds / 60 % 60, seconds % 60)
internal fun formatDistance(meters: Double): String = "%.2f km".format(meters / 1_000)
internal fun formatPace(seconds: Double?): String = seconds?.takeIf { it.isFinite() && it < 3_600 }?.let { "%d:%02d /km".format(it.toInt() / 60, it.toInt() % 60) } ?: "—"
private fun Context.openAppSettings() = startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
