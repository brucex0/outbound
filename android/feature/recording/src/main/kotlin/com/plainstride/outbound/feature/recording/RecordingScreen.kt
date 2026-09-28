package com.plainstride.outbound.feature.recording

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.util.Log
import android.provider.Settings
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CloudOff
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.automirrored.filled.DirectionsRun
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.foundation.Canvas
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import java.io.File
import java.util.UUID
import kotlinx.coroutines.delay
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeoutOrNull
import com.google.android.gms.location.CurrentLocationRequest
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import kotlin.math.roundToInt
import com.plainstride.outbound.core.designsystem.LocalPlainstrideThemeColors
import com.plainstride.outbound.core.designsystem.MapCoordinate
import com.plainstride.outbound.core.designsystem.LocationEnableChip
import com.plainstride.outbound.core.designsystem.LocationPermissionEducationDialog
import com.plainstride.outbound.core.location.LocationPermissionAccess
import com.plainstride.outbound.core.designsystem.MapRouteSegment
import com.plainstride.outbound.core.designsystem.PlainstrideRouteMap
import com.plainstride.outbound.core.model.activity.ActivityType
import com.plainstride.outbound.core.model.activity.DistanceUnit
import com.plainstride.outbound.core.model.activity.ElevationUnit
import com.plainstride.outbound.core.model.activity.MeasurementUnitSystem
import com.plainstride.outbound.core.model.activity.SessionFormatting
import com.plainstride.outbound.core.model.activity.WorkoutCalorieEstimator

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
    isOffline: Boolean = false,
    onSaved: (RecordedActivityReview, ActivityPhotoAlbumExportResult?) -> Unit,
    onSavedSideEffects: (RecordedActivityReview) -> Unit = {},
    onExit: () -> Unit,
    onOpenAssistant: () -> Unit = {},
    saveActivityPhotosToAlbum: Boolean = true,
    onPhotoAlbumPermissionDenied: () -> Unit = {},
    modifier: Modifier = Modifier,
    unitSystem: MeasurementUnitSystem = MeasurementUnitSystem.metric,
    weightKilograms: Double? = null,
    sessionEffect: @Composable (RecordingSnapshot) -> Unit = {},
    viewModel: RecordingViewModel = hiltViewModel(),
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val scope = rememberCoroutineScope()
    val ui by viewModel.state.collectAsStateWithLifecycle()
    val snapshot by viewModel.snapshot.collectAsStateWithLifecycle()
    val voiceListening by viewModel.voiceListening.collectAsStateWithLifecycle()
    sessionEffect(snapshot)
    var askedForLocation by remember(context) {
        mutableStateOf(LocationPermissionAccess.wasRequestedBefore(context))
    }
    var permissionRevision by remember { mutableIntStateOf(0) }
    var locationWaitJob by remember { mutableStateOf<Job?>(null) }
    var showGpsWait by remember { mutableStateOf(false) }
    var pendingStartAfterSettings by remember { mutableStateOf(false) }
    var pendingResume by remember { mutableStateOf(false) }
    var showLocationEducation by remember { mutableStateOf(false) }
    var showCameraEducation by remember { mutableStateOf(false) }
    var pendingPhotoAlbumSave by remember { mutableStateOf<RecordedActivityReview?>(null) }
    var postSaveStretchKind by remember { mutableStateOf<ActivityKind?>(null) }
    var postSaveReview by remember { mutableStateOf<RecordedActivityReview?>(null) }
    var postSavePhotoAlbumExport by remember { mutableStateOf<ActivityPhotoAlbumExportResult?>(null) }
    val saveSnackbar = remember { SnackbarHostState() }
    val saveFailedMessage = stringResource(R.string.recording_save_failed)

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                askedForLocation = LocationPermissionAccess.wasRequestedBefore(context)
                permissionRevision++
                viewModel.updatePermission(recordingLocationPermission(context, LocationPermissionAccess.wasRequestedBefore(context)))
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    val saveReview: (RecordedActivityReview, Boolean, ActivityPhotoAlbumExportResult?) -> Unit =
        { review, exportPhoto, overrideResult ->
            scope.launch {
                val result = viewModel.saveFinished(review, exportPhoto)
                if (result.saved) {
                    viewModel.markSaved(); onSavedSideEffects(review); val kind=review.snapshot.activityKind; if(PostWorkoutStretchCatalog.routine(kind)!=null){postSaveReview=review;postSavePhotoAlbumExport=overrideResult?:result.photoAlbumExport;postSaveStretchKind=kind}else onSaved(review,overrideResult?:result.photoAlbumExport)
                } else {
                    saveSnackbar.showSnackbar(saveFailedMessage)
                }
            }
        }

    val photoAlbumPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        val review = pendingPhotoAlbumSave ?: return@rememberLauncherForActivityResult
        pendingPhotoAlbumSave = null
        if (!granted) {
            viewModel.trackPhotoAlbumPermissionDenied()
            onPhotoAlbumPermissionDenied()
        }
        saveReview(
            review,
            granted,
            if (granted) null else ActivityPhotoAlbumExportResult.PERMISSION_DENIED,
        )
    }

    fun permissionState(): LocationPermissionState {
        permissionRevision
        return recordingLocationPermission(context, askedForLocation)
    }

    suspend fun waitForUsableLocation(): Boolean {
        val client = LocationServices.getFusedLocationProviderClient(context)
        fun isUsable(location: android.location.Location?): Boolean {
            if (location == null || !location.hasAccuracy() || location.accuracy > 80f) return false
            val ageNanos = SystemClock.elapsedRealtimeNanos() - location.elapsedRealtimeNanos
            return ageNanos in 0..15_000_000_000L
        }

        runCatching { client.lastLocation.await() }.getOrNull().takeIf(::isUsable)?.let { return true }
        while (true) {
            val permission = recordingLocationPermission(context, LocationPermissionAccess.wasRequestedBefore(context))
            if (permission != LocationPermissionState.PRECISE && permission != LocationPermissionState.APPROXIMATE) return false
            val current = withTimeoutOrNull(12_000L) {
                runCatching {
                    client.getCurrentLocation(
                        CurrentLocationRequest.Builder()
                            .setPriority(Priority.PRIORITY_HIGH_ACCURACY)
                            .setDurationMillis(10_000L)
                            .build(),
                        CancellationTokenSource().token,
                    ).await()
                }.getOrNull()
            }
            if (isUsable(current)) return true
            delay(500L)
        }
    }

    fun showLocationRequired() {
        showGpsWait = false
        showLocationEducation = true
    }

    fun beginCountdown() {
        pendingResume = false
        if (BuildConfig.DEBUG && ui.launch.simulatedRunEnabled) {
            val permission = permissionState()
            if (permission == LocationPermissionState.PRECISE || permission == LocationPermissionState.APPROXIMATE) {
                scope.launch { viewModel.beginCountdown() }
            } else showLocationRequired()
            return
        }
        val permission = permissionState()
        if (permission == LocationPermissionState.PRECISE || permission == LocationPermissionState.APPROXIMATE) {
            if (ui.launch.indoor) {
                scope.launch { viewModel.beginCountdown() }
            } else {
                locationWaitJob?.cancel()
                locationWaitJob = scope.launch {
                    showGpsWait = true
                    val ready = runCatching { waitForUsableLocation() }.getOrDefault(false)
                    showGpsWait = false
                    locationWaitJob = null
                    if (ready && permissionState().let { it == LocationPermissionState.PRECISE || it == LocationPermissionState.APPROXIMATE }) {
                        viewModel.beginCountdown()
                    } else if (permissionState() == LocationPermissionState.DENIED) showLocationRequired()
                }
            }
        } else showLocationRequired()
    }

    LaunchedEffect(permissionRevision) {
        if (!pendingStartAfterSettings) return@LaunchedEffect
        val permission = recordingLocationPermission(context, LocationPermissionAccess.wasRequestedBefore(context))
        pendingStartAfterSettings = false
        if (permission == LocationPermissionState.PRECISE || permission == LocationPermissionState.APPROXIMATE) beginCountdown()
        else if (launch.startImmediately || ui.launch.startImmediately) showLocationRequired()
    }

    LaunchedEffect(launch, unitSystem) {
        viewModel.configure(launch, unitSystem)
        if (launch.startImmediately && snapshot.status == RecordingStatus.IDLE) beginCountdown()
    }

    LaunchedEffect(accountId) { viewModel.recover(accountId, permissionState()) }

    val locationPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) {
        askedForLocation = true
        LocationPermissionAccess.markRequested(context)
        viewModel.updatePermission(permissionState())
        if (pendingResume) {
            pendingResume = false
            if (permissionState() == LocationPermissionState.PRECISE || permissionState() == LocationPermissionState.APPROXIMATE) viewModel.resume()
        } else if (permissionState() == LocationPermissionState.PRECISE || permissionState() == LocationPermissionState.APPROXIMATE) beginCountdown()
        else if (launch.startImmediately || ui.launch.startImmediately) showLocationRequired()
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
        if (BuildConfig.DEBUG) Log.d("RecordingStart", "countdown_step=$current voiceReady=${ui.countdownVoiceReady}")
        if (ui.countdownVoiceReady) {
            if (current == 0) viewModel.speakGo() else viewModel.speakCountdown(current)
        }
        delay(if (current == 0) 420L else 1_000L)
        if (current > 0) viewModel.updateCountdown(current - 1)
        else {
            val permission = permissionState()
            if (!ui.launch.indoor && !(BuildConfig.DEBUG && ui.launch.simulatedRunEnabled) && permission != LocationPermissionState.PRECISE && permission != LocationPermissionState.APPROXIMATE) {
                viewModel.clearCountdown()
                showLocationRequired()
            } else {
                if (!ui.launch.indoor && !(BuildConfig.DEBUG && ui.launch.simulatedRunEnabled)) {
                    showGpsWait = true
                    val ready = runCatching { waitForUsableLocation() }.getOrDefault(false)
                    showGpsWait = false
                    if (!ready) {
                        viewModel.clearCountdown()
                        if (permissionState() == LocationPermissionState.DENIED) showLocationRequired()
                        return@LaunchedEffect
                    }
                }
                viewModel.start(accountId, permission)
            }
        }
    }

    LaunchedEffect(snapshot.status) {
        if (snapshot.status != RecordingStatus.IDLE && ui.countdown != null) {
            if (ui.startRequested) viewModel.clearCountdown() else viewModel.cancelCountdown()
        }
    }

    BackHandler(enabled = !ui.showFinishConfirmation && !ui.showDiscardConfirmation) {
        when (snapshot.status) {
            RecordingStatus.ACTIVE, RecordingStatus.PAUSED -> viewModel.requestFinish()
            RecordingStatus.AWAITING_SAVE -> viewModel.requestDiscard()
            RecordingStatus.IDLE -> {
                if (!ui.startRequested) {
                    viewModel.cancelCountdown()
                    onExit()
                }
            }
        }
    }

    LaunchedEffect(snapshot.status, snapshot.saveEligibility) {
        if (snapshot.status == RecordingStatus.AWAITING_SAVE && snapshot.saveEligibility == ActivitySaveEligibility.TOO_SHORT) {
            viewModel.trackSaveIneligible()
        }
    }

    val content: @Composable () -> Unit = {
        when {
            snapshot.status == RecordingStatus.AWAITING_SAVE -> ReflectionScreen(
                snapshot = snapshot,
                launch = ui.launch,
                selected = ui.reflection,
                photoPath = ui.photoPath,
                onSelect = viewModel::setReflection,
                onTakePhoto = ::capturePhoto,
                onRemovePhoto = { ui.photoPath?.let(::File)?.delete(); viewModel.setPhotoPath(null) },
                onSave = {
                    val reflection = ui.reflection ?: ReflectionChoice.STEADY
                    val review = RecordedActivityReview(snapshot, reflection, ui.photoPath)
                    val needsLegacyStoragePermission = saveActivityPhotosToAlbum &&
                        ui.photoPath != null &&
                        Build.VERSION.SDK_INT <= Build.VERSION_CODES.P &&
                        context.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
                            PackageManager.PERMISSION_GRANTED
                    if (needsLegacyStoragePermission) {
                        pendingPhotoAlbumSave = review
                        photoAlbumPermissionLauncher.launch(Manifest.permission.WRITE_EXTERNAL_STORAGE)
                    } else {
                        saveReview(review, saveActivityPhotosToAlbum, null)
                    }
                },
                saving = ui.saving,
                onClose = viewModel::requestDiscard,
            )
            snapshot.status == RecordingStatus.ACTIVE || snapshot.status == RecordingStatus.PAUSED -> LiveRecordingScreen(
                snapshot = snapshot,
                configuration = ui.launch,
                locationPermission = permissionState(),
                unitSystem = unitSystem,
                weightKilograms = weightKilograms,
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
                onOpenAssistant = onOpenAssistant,
                voiceListening = voiceListening,
                onDashboardChanged = viewModel::trackDashboardChanged,
                runSimulation = snapshot.runSimulation,
                onSimulationRate = viewModel::setRunSimulationTimeRate,
                onSimulationSpeed = viewModel::adjustRunSimulationSpeed,
                onSimulationClock = viewModel::toggleRunSimulationClock,
                onSimulationAdvance = viewModel::advanceRunSimulation,
            )
            ui.countdown != null -> CountdownScreen(
                value = ui.countdown!!,
                snapshot = snapshot,
                configuration = ui.launch,
                locationPermission = permissionState(),
                runSimulation = snapshot.runSimulation,
                onCancel = {
                    viewModel.cancelCountdown()
                    onExit()
                },
            )
            launch.startImmediately || ui.launch.startImmediately -> StartingActivityScreen()
            else -> ActivitySetupScreen(
                configuration = ui.launch,
                permission = permissionState(),
                onStart = ::beginCountdown,
                onRequestLocationAccess = { showLocationEducation = true },
                onExit = onExit,
                onSimulationChanged = viewModel::configureSimulatedRun,
                onAutoPauseChanged = viewModel::setAutoPauseEnabled,
            )
        }
    }

    Box(modifier.fillMaxSize()) {
        if (postSaveStretchKind != null) {
            PostWorkoutStretchRoute(
                requireNotNull(postSaveStretchKind),
                { val review = postSaveReview; val export = postSavePhotoAlbumExport; postSaveReview = null; postSavePhotoAlbumExport = null; postSaveStretchKind = null; if (review != null) onSaved(review, export) },
                { name, result -> viewModel.trackStretchEvent(name, requireNotNull(postSaveStretchKind), result) },
            )
        } else {
            content()
            SnackbarHost(saveSnackbar, Modifier.align(Alignment.BottomCenter))
        }
        if (isOffline && postSaveStretchKind == null) {
            Surface(
                modifier = Modifier.align(Alignment.TopCenter).padding(top = 8.dp)
                    .semantics { contentDescription = context.getString(R.string.recording_offline_accessibility) },
                shape = RoundedCornerShape(50),
                color = MaterialTheme.colorScheme.surface.copy(alpha = 0.94f),
                shadowElevation = 6.dp,
            ) {
                Row(
                    Modifier.padding(horizontal = 14.dp).height(36.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(7.dp),
                ) {
                    Icon(Icons.Default.CloudOff, null, tint = MaterialTheme.colorScheme.tertiary, modifier = Modifier.size(16.dp))
                    Text(stringResource(R.string.recording_offline_status), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }

    if (showGpsWait) AlertDialog(
        onDismissRequest = {
            locationWaitJob?.cancel()
            locationWaitJob = null
            showGpsWait = false
            viewModel.cancelCountdown()
            if (launch.startImmediately || ui.launch.startImmediately) onExit()
        },
        title = { Text(stringResource(R.string.recording_acquiring_location)) },
        text = { CircularProgressIndicator() },
        confirmButton = { TextButton(onClick = {
            locationWaitJob?.cancel()
            locationWaitJob = null
            showGpsWait = false
            viewModel.cancelCountdown()
            if (launch.startImmediately || ui.launch.startImmediately) onExit()
        }) { Text(stringResource(R.string.recording_cancel)) } },
    )

    if (showLocationEducation) LocationPermissionEducationDialog(
        onEnable = {
            showLocationEducation = false
            if (askedForLocation) {
                pendingStartAfterSettings = true
                context.openAppSettings()
            }
            else {
                LocationPermissionAccess.markRequested(context)
                askedForLocation = true
                locationPermissionLauncher.launch(LocationPermissionAccess.requestPermissions)
            }
        },
        onClose = {
            showLocationEducation = false
            if (launch.startImmediately || ui.launch.startImmediately) onExit()
        },
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
        confirmButton = { TextButton(
            enabled = !ui.discarding,
            onClick = {
                scope.launch {
                    if (viewModel.discard()) {
                        ui.photoPath?.let(::File)?.delete()
                        onExit()
                    }
                }
            },
        ) { Text(stringResource(R.string.recording_discard)) } },
        dismissButton = { TextButton(onClick = viewModel::cancelDiscard) { Text(stringResource(R.string.recording_cancel)) } },
    )
}

@Composable
private fun ActivitySetupScreen(
    configuration: RecordingLaunchConfiguration,
    permission: LocationPermissionState,
    onStart: () -> Unit,
    onRequestLocationAccess: () -> Unit,
    onExit: () -> Unit,
    onSimulationChanged: (Boolean) -> Unit,
    onAutoPauseChanged: (Boolean) -> Unit,
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
            if (configuration.activityKind in setOf(ActivityKind.RUNNING, ActivityKind.CYCLING, ActivityKind.WALKING, ActivityKind.HIKING)) {
                item {
                    val autoPauseLabel = stringResource(R.string.auto_pause)
                    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer)) {
                        Row(
                            Modifier.fillMaxWidth().padding(16.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Text(stringResource(R.string.auto_pause), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                                Text(stringResource(R.string.auto_pause_detail), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            Switch(
                                checked = configuration.autoPauseEnabled ?: AutoPauseDefaults.enabled(configuration.activityKind),
                                onCheckedChange = onAutoPauseChanged,
                                modifier = Modifier.semantics { contentDescription = autoPauseLabel },
                            )
                        }
                    }
                }
            }
            if (BuildConfig.DEBUG) {
                item {
                    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer)) {
                        Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Column(Modifier.weight(1f)) {
                                    Text(stringResource(R.string.recording_simulation_testing_section), style = MaterialTheme.typography.labelLarge)
                                    Text(stringResource(R.string.recording_simulation_setup_title), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                                }
                                Switch(configuration.simulatedRunEnabled, onCheckedChange = onSimulationChanged)
                            }
                            Text(stringResource(R.string.recording_simulation_setup_detail), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            if (configuration.simulatedRunEnabled) {
                                Text(stringResource(R.string.recording_simulation_route_name), style = MaterialTheme.typography.labelMedium)
                            }
                        }
                    }
                }
            }
            item {
                if (!configuration.indoor && (permission == LocationPermissionState.NOT_REQUESTED || permission == LocationPermissionState.DENIED)) {
                    LocationEnableChip(onClick = onRequestLocationAccess)
                }
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
private fun CountdownScreen(
    value: Int,
    snapshot: RecordingSnapshot,
    configuration: RecordingLaunchConfiguration,
    locationPermission: LocationPermissionState,
    runSimulation: RunSimulationState?,
    onCancel: () -> Unit,
) {
    val progress = (4 - value.coerceIn(0, 3)) / 4f
    val label = if (value == 0) stringResource(R.string.recording_go) else value.toString()
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        TrackMap(snapshot, configuration, locationPermission, runSimulation, Modifier.fillMaxSize())
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.42f)))
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(20.dp)) {
            Box(Modifier.size(188.dp), contentAlignment = Alignment.Center) {
                Canvas(Modifier.fillMaxSize()) {
                    val stroke = 8.dp.toPx()
                    drawArc(
                        color = Color.White.copy(alpha = 0.2f),
                        startAngle = -90f,
                        sweepAngle = 360f,
                        useCenter = false,
                        style = Stroke(stroke),
                    )
                    drawArc(
                        color = Color(0xFFFF9F0A),
                        startAngle = -90f,
                        sweepAngle = 360f * progress,
                        useCenter = false,
                        style = Stroke(stroke, cap = StrokeCap.Round),
                    )
                }
                Text(
                    label,
                    style = if (value == 0) MaterialTheme.typography.displayMedium else MaterialTheme.typography.displayLarge,
                    color = Color.White,
                    fontWeight = FontWeight.Black,
                    maxLines = 1,
                    modifier = Modifier.semantics { contentDescription = label },
                )
            }
            Text("Plainstride", style = MaterialTheme.typography.titleMedium, color = Color.White.copy(alpha = 0.86f), fontWeight = FontWeight.SemiBold)
        }
        TextButton(onClick = onCancel, modifier = Modifier.align(Alignment.BottomCenter).padding(32.dp)) {
            Text(stringResource(R.string.recording_cancel), color = Color.White)
        }
    }
}

@Composable
private fun StartingActivityScreen() {
    Box(
        Modifier.fillMaxSize().background(MaterialTheme.colorScheme.primary),
        contentAlignment = Alignment.Center,
    ) {
        CircularProgressIndicator(color = MaterialTheme.colorScheme.onPrimary)
    }
}

@Composable
private fun LiveRecordingScreen(
    snapshot: RecordingSnapshot,
    configuration: RecordingLaunchConfiguration,
    locationPermission: LocationPermissionState,
    unitSystem: MeasurementUnitSystem,
    weightKilograms: Double?,
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
    onOpenAssistant: () -> Unit,
    voiceListening: Boolean,
    onDashboardChanged: (Boolean) -> Unit,
    runSimulation: RunSimulationState?,
    onSimulationRate: (Int) -> Unit,
    onSimulationSpeed: (Double) -> Unit,
    onSimulationClock: () -> Unit,
    onSimulationAdvance: (Int) -> Unit,
) {
    var dashboardExpanded by remember { mutableStateOf(false) }
    val energyKilocalories = WorkoutCalorieEstimator.liveEnergyKilocalories(
        activityType = snapshot.activityKind.toActivityType(),
        distanceMeters = snapshot.distanceMeters,
        durationSeconds = snapshot.elapsedSeconds.coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
        elevationGainMeters = snapshot.elevationGainMeters,
        weightKilograms = weightKilograms,
    )
    Box(Modifier.fillMaxSize().background(if (mode == RecordingSurfaceMode.CAMERA) Color.Black else MaterialTheme.colorScheme.surface).pointerInput(mode) {
        detectHorizontalDragGestures { _, amount ->
            if (amount < -18 && mode == RecordingSurfaceMode.CAMERA) onMode(RecordingSurfaceMode.MAP)
            if (amount > 18 && mode == RecordingSurfaceMode.MAP) onMode(RecordingSurfaceMode.CAMERA)
        }
    }) {
        if (mode == RecordingSurfaceMode.MAP) TrackMap(snapshot, configuration, locationPermission, runSimulation, Modifier.fillMaxSize())
        else CameraSurface(photoPath, onPhotoCaptured, onTakePhoto,onPhotoPending, Modifier.fillMaxSize())

        if (!dashboardExpanded) Row(Modifier.align(Alignment.TopEnd).padding(16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            val controlColor = if (mode == RecordingSurfaceMode.CAMERA) Color.Black.copy(alpha = 0.52f) else MaterialTheme.colorScheme.surface.copy(alpha = 0.94f)
            val controlContentColor = if (mode == RecordingSurfaceMode.CAMERA) Color.White else MaterialTheme.colorScheme.onSurface
            Surface(
                shape = CircleShape,
                color = if (voiceListening) MaterialTheme.colorScheme.primary else controlColor,
                contentColor = if (voiceListening) MaterialTheme.colorScheme.onPrimary else controlContentColor,
                tonalElevation = 6.dp,
            ) {
                IconButton(onClick = onListen) {
                    Icon(Icons.Default.Mic, contentDescription = stringResource(R.string.recording_voice_command))
                }
            }
            Surface(shape = CircleShape, color = controlColor, contentColor = controlContentColor, tonalElevation = 6.dp) {
                IconButton(onClick = onOpenAssistant) {
                    Icon(Icons.Default.AutoAwesome, contentDescription = stringResource(R.string.recording_open_assistant))
                }
            }
            Surface(shape = CircleShape, color = controlColor, contentColor = controlContentColor, tonalElevation = 6.dp) {
                IconButton(onClick = { onMode(if (mode == RecordingSurfaceMode.MAP) RecordingSurfaceMode.CAMERA else RecordingSurfaceMode.MAP) }) {
                    Icon(if (mode == RecordingSurfaceMode.MAP) Icons.Default.CameraAlt else Icons.Default.Map,
                        contentDescription = stringResource(if (mode == RecordingSurfaceMode.MAP) R.string.recording_show_camera else R.string.recording_show_map))
                }
            }
        }
        if (BuildConfig.DEBUG && runSimulation != null) {
            RunSimulationControls(
                state = runSimulation,
                isActive = snapshot.status == RecordingStatus.ACTIVE,
                onRate = onSimulationRate,
                onSpeed = onSimulationSpeed,
                onClock = onSimulationClock,
                onAdvance = onSimulationAdvance,
                modifier = Modifier.align(Alignment.TopCenter).padding(top = 58.dp, start = 12.dp, end = 12.dp),
            )
        }
        SessionDashboard(snapshot, configuration, unitSystem, energyKilocalories, dashboardExpanded, {
            if (dashboardExpanded != it) {
                dashboardExpanded = it
                onDashboardChanged(it)
            }
        }, Modifier.align(Alignment.BottomCenter), onPause, onResume, onFinish, finishEnabled)
    }
}

@Composable
private fun RunSimulationControls(
    state: RunSimulationState,
    isActive: Boolean,
    onRate: (Int) -> Unit,
    onSpeed: (Double) -> Unit,
    onClock: () -> Unit,
    onAdvance: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val timeRateLabel = stringResource(R.string.recording_simulation_time_rate)
    val decreaseSpeedLabel = stringResource(R.string.recording_simulation_speed_decrease)
    val increaseSpeedLabel = stringResource(R.string.recording_simulation_speed_increase)
    var showRateMenu by remember { mutableStateOf(false) }
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(18.dp),
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.96f),
        shadowElevation = 8.dp,
        border = androidx.compose.foundation.BorderStroke(1.dp, Color(0xFFFF9800).copy(alpha = 0.6f)),
    ) {
        Column(Modifier.padding(10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                Icon(Icons.AutoMirrored.Filled.DirectionsRun, contentDescription = null, tint = Color(0xFFEF6C00))
                Text(stringResource(R.string.recording_simulation_title), style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold)
                Spacer(Modifier.weight(1f))
                Text(formatDuration(state.elapsedSeconds.toLong()), style = MaterialTheme.typography.labelMedium, fontFamily = FontFamily.Monospace)
                Button(onClick = onClock, enabled = isActive && !state.isComplete) {
                    Icon(if (state.isClockRunning) Icons.Default.Pause else Icons.Default.PlayArrow, contentDescription = null)
                    Text(stringResource(if (state.isClockRunning) R.string.recording_simulation_pause_button else R.string.recording_simulation_start_button))
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(timeRateLabel, style = MaterialTheme.typography.labelMedium)
                Box {
                    OutlinedButton(onClick = { showRateMenu = true }, enabled = !state.isComplete,
                        modifier = Modifier.semantics { contentDescription = "$timeRateLabel ${state.timeRate}×" },
                        contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 8.dp)) {
                        Text("${state.timeRate}×")
                        Icon(Icons.Default.ArrowDropDown, contentDescription = null)
                    }
                    DropdownMenu(expanded = showRateMenu, onDismissRequest = { showRateMenu = false }) {
                        listOf(1, 10, 60).forEach { rate ->
                            DropdownMenuItem(
                                text = { Text("${rate}×") },
                                leadingIcon = { if (rate == state.timeRate) Icon(Icons.Default.Check, contentDescription = null) },
                                onClick = { onRate(rate); showRateMenu = false },
                            )
                        }
                    }
                }
                Spacer(Modifier.weight(1f))
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                TextButton(
                    onClick = { onSpeed(-1.0) },
                    modifier = Modifier.semantics { contentDescription = decreaseSpeedLabel },
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 7.dp),
                ) { Text("−") }
                Text(String.format(java.util.Locale.getDefault(), stringResource(R.string.recording_simulation_speed_format), state.speedKilometersPerHour), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace)
                TextButton(
                    onClick = { onSpeed(1.0) },
                    modifier = Modifier.semantics { contentDescription = increaseSpeedLabel },
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 7.dp),
                ) { Text("+") }
                Spacer(Modifier.weight(1f))
                OutlinedButton(onClick = { onAdvance(60) }, enabled = isActive && !state.isComplete, contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 8.dp)) {
                    Text(stringResource(R.string.recording_simulation_advance_one_minute))
                }
                OutlinedButton(onClick = { onAdvance(300) }, enabled = isActive && !state.isComplete, contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 8.dp)) {
                    Text(stringResource(R.string.recording_simulation_advance_five_minutes))
                }
            }
        }
    }
}

@Composable
private fun TrackMap(
    snapshot: RecordingSnapshot,
    configuration: RecordingLaunchConfiguration,
    locationPermission: LocationPermissionState,
    runSimulation: RunSimulationState?,
    modifier: Modifier = Modifier,
) {
    val recorded = snapshot.track.map { MapCoordinate(it.latitude, it.longitude) }
    val planned = configuration.followedRoute?.points.orEmpty().map { MapCoordinate(it.latitude, it.longitude) }
    val framingPoints = planned.takeIf { it.size > 1 } ?: recorded
    val recordedSegments = buildList {
        val starts = (snapshot.trackSegmentStartIndices + 0).filter { it in recorded.indices }.sorted()
        starts.forEachIndexed { index, start ->
            val end = starts.getOrNull(index + 1) ?: recorded.size
            if (end - start > 1) add(MapRouteSegment(recorded.subList(start, end), MaterialTheme.colorScheme.primary))
        }
    }
    val routeSegments = buildList {
        if (planned.size > 1) add(MapRouteSegment(planned, Color(0xFFFF5200)))
        addAll(recordedSegments)
    }
    PlainstrideRouteMap(
        points = framingPoints,
        modifier = modifier,
        showUserLocation = runSimulation == null,
        preciseLocationGranted = locationPermission == LocationPermissionState.PRECISE || locationPermission == LocationPermissionState.APPROXIMATE,
        focusOnUser = runSimulation == null,
        showEndpointMarkers = planned.size > 1,
        routeSegments = routeSegments,
        markers = listOfNotNull(snapshot.latestLocation?.takeIf { runSimulation != null }?.let { location ->
            com.plainstride.outbound.core.designsystem.MapRouteMarker(
                id = "simulated-location",
                coordinate = MapCoordinate(location.latitude, location.longitude),
                title = stringResource(R.string.recording_simulation_location),
                selected = true,
            )
        }),
        bottomContentPadding = 128.dp,
        fitRouteOnChange = true,
        followCoordinate = snapshot.latestLocation?.takeIf { (runSimulation?.elapsedSeconds ?: 0) > 0 }?.let {
            MapCoordinate(it.latitude, it.longitude)
        },
    )
    Box(modifier, contentAlignment = Alignment.Center) {
        if (snapshot.latestLocation == null) Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(Icons.Default.MyLocation, null)
            Text(stringResource(R.string.recording_acquiring_location))
        }
    }
}

@Composable
private fun CameraSurface(photoPath: String?, onCaptured: (String) -> Unit, onTakePhoto: () -> Unit,onPending:(Boolean)->Unit, modifier: Modifier = Modifier) {
    Box(modifier) {
        val bitmap = remember(photoPath) { photoPath?.let { BitmapFactory.decodeFile(it) } }
        InAppCamera({onPending(false);onCaptured(it)},{onPending(false);onTakePhoto()},onPending,Modifier.fillMaxSize())
        if (bitmap != null) Image(
            bitmap = bitmap.asImageBitmap(),
            contentDescription = stringResource(R.string.recording_activity_photo),
            contentScale = ContentScale.Crop,
            modifier = Modifier
                .align(Alignment.CenterEnd)
                .padding(end = 28.dp, bottom = 164.dp)
                .size(58.dp)
                .clip(RoundedCornerShape(12.dp))
                .border(2.dp, Color.White, RoundedCornerShape(12.dp)),
        )
    }
}

@Composable
private fun SessionDashboard(
    snapshot: RecordingSnapshot,
    configuration: RecordingLaunchConfiguration,
    unitSystem: MeasurementUnitSystem,
    energyKilocalories: Double?,
    expanded: Boolean,
    onExpandedChanged: (Boolean) -> Unit,
    modifier: Modifier,
    onPause: () -> Unit,
    onResume: () -> Unit,
    onFinish: () -> Unit,
    finishEnabled:Boolean,
) {
    val theme = LocalPlainstrideThemeColors.current
    Card(
        modifier = if (expanded) {
            modifier.fillMaxSize()
        } else {
            modifier.padding(horizontal = 16.dp, vertical = 18.dp).fillMaxWidth().height(92.dp)
        },
        shape = if (expanded) RoundedCornerShape(0.dp) else RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(if (expanded) 0.dp else 10.dp),
    ) {
        if (expanded) ExpandedSessionDashboard(
            snapshot = snapshot,
            configuration = configuration,
            unitSystem = unitSystem,
            energyKilocalories = energyKilocalories,
            onCollapse = { onExpandedChanged(false) },
            onPause = onPause,
            onResume = onResume,
            onFinish = onFinish,
            finishEnabled = finishEnabled,
            actionColor = theme.action,
            finishColor = theme.secondary,
        ) else CompactSessionDashboard(
            snapshot = snapshot,
            configuration = configuration,
            unitSystem = unitSystem,
            energyKilocalories = energyKilocalories,
            onExpand = { onExpandedChanged(true) },
            onPause = onPause,
            onResume = onResume,
            onFinish = onFinish,
            finishEnabled = finishEnabled,
            actionColor = theme.action,
        )
    }
}

@Composable
private fun DashboardGrabber(expanded: Boolean, onExpandedChanged: (Boolean) -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .height(if (expanded) 76.dp else 28.dp)
            .padding(top = if (expanded) 48.dp else 0.dp)
            .clickable { onExpandedChanged(!expanded) }
            .pointerInput(expanded) {
                detectVerticalDragGestures { _, amount ->
                    if (amount < -12) onExpandedChanged(true)
                    if (amount > 12) onExpandedChanged(false)
                }
            },
        verticalArrangement = Arrangement.spacedBy(2.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(Modifier.size(width = 42.dp, height = 5.dp).background(MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.38f), CircleShape))
        Icon(
            if (expanded) Icons.Default.ExpandMore else Icons.Default.ExpandLess,
            contentDescription = stringResource(R.string.recording_activity_in_progress),
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(14.dp),
        )
    }
}

@Composable
private fun CompactSessionDashboard(
    snapshot: RecordingSnapshot,
    configuration: RecordingLaunchConfiguration,
    unitSystem: MeasurementUnitSystem,
    energyKilocalories: Double?,
    onExpand: () -> Unit,
    onPause: () -> Unit,
    onResume: () -> Unit,
    onFinish: () -> Unit,
    finishEnabled: Boolean,
    actionColor: Color,
) {
    Column {
        DashboardGrabber(false) { onExpand() }
        Row(
            Modifier.fillMaxWidth().height(50.dp).padding(horizontal = 14.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            CompactMetric(liveElapsedText(snapshot, configuration.goal), Modifier.weight(1f))
            FilledIconButton(
                onClick = if (snapshot.status == RecordingStatus.ACTIVE) onPause else onResume,
                modifier = Modifier.size(48.dp),
                colors = IconButtonDefaults.filledIconButtonColors(containerColor = actionColor, contentColor = Color.White),
            ) {
                Icon(
                    if (snapshot.status == RecordingStatus.ACTIVE) Icons.Default.Pause else Icons.Default.PlayArrow,
                    contentDescription = stringResource(if (snapshot.status == RecordingStatus.ACTIVE) R.string.recording_pause else R.string.recording_resume),
                )
            }
            if (configuration.companionType != null) {
                Text(
                    stringResource(R.string.recording_companion_accessibility),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.padding(horizontal = 4.dp),
                )
            }
            if (snapshot.status == RecordingStatus.PAUSED) FilledIconButton(
                onClick = onFinish,
                enabled = finishEnabled,
                modifier = Modifier.size(48.dp).alpha(if (finishEnabled) 1f else 0.55f),
                colors = IconButtonDefaults.filledIconButtonColors(containerColor = actionColor, contentColor = Color.White),
            ) { Icon(Icons.Default.Stop, stringResource(R.string.recording_finish)) }
            CompactMetric(liveDistanceText(snapshot, configuration.goal, unitSystem, energyKilocalories), Modifier.weight(1f))
        }
    }
}

@Composable
private fun ExpandedSessionDashboard(
    snapshot: RecordingSnapshot,
    configuration: RecordingLaunchConfiguration,
    unitSystem: MeasurementUnitSystem,
    energyKilocalories: Double?,
    onCollapse: () -> Unit,
    onPause: () -> Unit,
    onResume: () -> Unit,
    onFinish: () -> Unit,
    finishEnabled: Boolean,
    actionColor: Color,
    finishColor: Color,
) {
    val paused = snapshot.status == RecordingStatus.PAUSED
    Column(Modifier.fillMaxSize()) {
        DashboardGrabber(true) { onCollapse() }
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp).clickable(onClick = onCollapse),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Box(Modifier.size(8.dp).background(if (paused) finishColor else actionColor, CircleShape))
            if (configuration.companionType != null) {
                Text(
                    stringResource(R.string.recording_companion_accessibility),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
            Column(Modifier.weight(1f)) {
                Text(
                    configuration.title ?: stringResource(R.string.recording_activity_in_progress),
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    stringResource(if (paused) R.string.recording_notification_paused else R.string.recording_activity_in_progress),
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            PrimaryGoalMetric(snapshot, configuration.goal, unitSystem, energyKilocalories)
            ExpandedMetricGrid(snapshot, unitSystem)
            CurrentWorkoutStep(snapshot.elapsedSeconds, configuration.workoutSteps)
            configuration.followedRoute?.let { route ->
                Surface(shape = RoundedCornerShape(14.dp), color = MaterialTheme.colorScheme.surfaceVariant) {
                    Row(Modifier.fillMaxWidth().padding(14.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Icon(Icons.Default.Map, null, tint = MaterialTheme.colorScheme.primary)
                        Text(route.name, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 24.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Button(
                onClick = if (paused) onResume else onPause,
                modifier = Modifier.weight(1f).height(62.dp),
                shape = RoundedCornerShape(18.dp),
                colors = ButtonDefaults.buttonColors(containerColor = actionColor, contentColor = Color.White),
            ) {
                Icon(if (paused) Icons.Default.PlayArrow else Icons.Default.Pause, null)
                Spacer(Modifier.width(8.dp))
                Text(stringResource(if (paused) R.string.recording_resume else R.string.recording_pause), fontWeight = FontWeight.Bold)
            }
            if (paused) Button(
                onClick = onFinish,
                enabled = finishEnabled,
                modifier = Modifier.weight(1f).height(62.dp).alpha(if (finishEnabled) 1f else 0.55f),
                shape = RoundedCornerShape(18.dp),
                colors = ButtonDefaults.buttonColors(containerColor = finishColor, contentColor = Color.White),
            ) {
                Icon(Icons.Default.Stop, null)
                Spacer(Modifier.width(8.dp))
                Text(stringResource(R.string.recording_finish), fontWeight = FontWeight.Bold)
            }
        }
    }
}

@Composable
private fun PrimaryGoalMetric(
    snapshot: RecordingSnapshot,
    goal: RecordingGoal,
    unitSystem: MeasurementUnitSystem,
    energyKilocalories: Double?,
) {
    val (label, value) = when (goal.type) {
        RecordingGoalType.TIME -> stringResource(R.string.recording_time) to liveElapsedText(snapshot, goal)
        RecordingGoalType.DISTANCE -> stringResource(R.string.recording_distance) to liveDistanceText(snapshot, goal, unitSystem, energyKilocalories)
        RecordingGoalType.CALORIES -> stringResource(R.string.recording_goal_calories, goal.targetCalories ?: 0) to liveDistanceText(snapshot, goal, unitSystem, energyKilocalories)
        RecordingGoalType.WORKOUT -> stringResource(R.string.recording_time) to liveElapsedText(snapshot, goal)
        RecordingGoalType.FREESTYLE -> stringResource(R.string.recording_distance) to liveDistanceText(snapshot, goal, unitSystem, energyKilocalories)
    }
    Column(Modifier.fillMaxWidth().padding(vertical = 8.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            value,
            style = MaterialTheme.typography.displayMedium,
            fontWeight = FontWeight.Black,
            fontFamily = FontFamily.Monospace,
            maxLines = 1,
        )
        Text(label, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
        goalProgress(snapshot, goal, energyKilocalories)?.let { progress ->
            LinearProgressIndicator(progress = { progress }, modifier = Modifier.width(260.dp))
        }
    }
}

@Composable
private fun ExpandedMetricGrid(snapshot: RecordingSnapshot, unitSystem: MeasurementUnitSystem) {
    val pace = if (snapshot.status == RecordingStatus.PAUSED && snapshot.distanceMeters > 0) {
        snapshot.elapsedSeconds / (snapshot.distanceMeters / 1_000.0)
    } else snapshot.currentPaceSecondsPerKilometer
    val metrics = listOf(
        stringResource(R.string.recording_time) to formatDuration(snapshot.elapsedSeconds),
        stringResource(R.string.recording_distance) to formatDistance(snapshot.distanceMeters, unitSystem),
        stringResource(if (snapshot.status == RecordingStatus.PAUSED) R.string.recording_avg_pace else R.string.recording_pace) to formatPace(pace, unitSystem),
        stringResource(R.string.recording_elevation) to formatElevation(snapshot.elevationGainMeters, unitSystem),
    )
    val columns = if (LocalDensity.current.fontScale >= 1.3f) 2 else 3
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        metrics.chunked(columns).forEach { rowMetrics ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                rowMetrics.forEach { (label, value) -> ExpandedMetric(label, value, Modifier.weight(1f)) }
                repeat(columns - rowMetrics.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

@Composable
private fun ExpandedMetric(label: String, value: String, modifier: Modifier = Modifier) {
    Surface(modifier = modifier.heightIn(min = 72.dp), shape = RoundedCornerShape(14.dp), color = MaterialTheme.colorScheme.surfaceVariant) {
        Column(Modifier.padding(horizontal = 6.dp, vertical = 12.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(value, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace, maxLines = 1)
            Text(label, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
        }
    }
}

@Composable
private fun CompactMetric(value: String, modifier: Modifier = Modifier) {
    Text(
        value,
        modifier = modifier,
        style = MaterialTheme.typography.titleMedium,
        fontWeight = FontWeight.Bold,
        fontFamily = FontFamily.Monospace,
        textAlign = TextAlign.Center,
        maxLines = 1,
    )
}

private data class WorkoutStepProgress(
    val index: Int,
    val count: Int,
    val step: StructuredWorkoutStep,
    val remainingSeconds: Long,
)

@Composable
private fun CurrentWorkoutStep(elapsedSeconds: Long, steps: List<StructuredWorkoutStep>) {
    val progress = currentWorkoutStep(elapsedSeconds, steps) ?: return
    Surface(shape = RoundedCornerShape(14.dp), color = MaterialTheme.colorScheme.surfaceVariant) {
        Row(Modifier.fillMaxWidth().padding(14.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Surface(shape = CircleShape, color = MaterialTheme.colorScheme.primaryContainer) {
                Text("${progress.index + 1}/${progress.count}", Modifier.padding(horizontal = 9.dp, vertical = 5.dp), color = MaterialTheme.colorScheme.onPrimaryContainer, fontWeight = FontWeight.Bold)
            }
            Column(Modifier.weight(1f)) {
                Text(progress.step.title, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                progress.step.detail?.takeIf(String::isNotBlank)?.let { Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis) }
            }
            Text(formatDuration(progress.remainingSeconds), fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold)
        }
    }
}

private fun currentWorkoutStep(elapsedSeconds: Long, steps: List<StructuredWorkoutStep>): WorkoutStepProgress? {
    val timed = steps.filter { (it.durationSeconds ?: 0) > 0 }
    if (timed.isEmpty()) return null
    var remainingElapsed = elapsedSeconds
    timed.forEachIndexed { index, step ->
        val duration = step.durationSeconds!!.toLong()
        if (remainingElapsed < duration) return WorkoutStepProgress(index, timed.size, step, duration - remainingElapsed)
        remainingElapsed -= duration
    }
    return WorkoutStepProgress(timed.lastIndex, timed.size, timed.last(), 0)
}

private fun liveElapsedText(snapshot: RecordingSnapshot, goal: RecordingGoal): String {
    val current = formatDuration(snapshot.elapsedSeconds)
    val target = goal.targetDurationSeconds?.takeIf {
        (goal.type == RecordingGoalType.TIME || goal.type == RecordingGoalType.WORKOUT) && it > 0
    } ?: return current
    return "$current/${compactDuration(target)}"
}

private fun liveDistanceText(
    snapshot: RecordingSnapshot,
    goal: RecordingGoal,
    unitSystem: MeasurementUnitSystem,
    energyKilocalories: Double?,
): String {
    if (goal.type == RecordingGoalType.CALORIES) return "${(energyKilocalories ?: 0.0).roundToInt()}/${goal.targetCalories ?: 0}kcal"
    val currentDistance = SessionFormatting.distance(snapshot.distanceMeters, unitSystem)
    val currentValue = currentDistance.value
    val unit = currentDistance.unit.shortLabel
    val targetMeters = goal.targetDistanceMeters?.takeIf { goal.type == RecordingGoalType.DISTANCE && it > 0 }
        ?: return "%.2f%s".format(currentValue, unit)
    val targetValue = SessionFormatting.distance(targetMeters, unitSystem).value
    val current = if (currentValue < 1) "%.2f".format(currentValue) else "%.1f".format(currentValue).trimEnd('0').trimEnd('.')
    val target = if (targetValue % 1.0 == 0.0) "%.0f".format(targetValue) else "%.1f".format(targetValue).trimEnd('0').trimEnd('.')
    return "$current/$target$unit"
}

private fun compactDuration(seconds: Long): String = when {
    seconds < 60 -> "${seconds}s"
    seconds < 3_600 -> if (seconds % 60 == 0L) "${seconds / 60}min" else "${seconds / 60}:${(seconds % 60).toString().padStart(2, '0')}"
    seconds % 3_600 == 0L -> "${seconds / 3_600}h"
    else -> "${seconds / 3_600}h${seconds % 3_600 / 60}m"
}

private val DistanceUnit.shortLabel: String get() = if (this == DistanceUnit.kilometer) "km" else "mi"

private fun ActivityKind.toActivityType(): ActivityType = when (this) {
    ActivityKind.RUNNING -> ActivityType.running
    ActivityKind.WALKING -> ActivityType.walking
    ActivityKind.HIKING -> ActivityType.hiking
    ActivityKind.CYCLING -> ActivityType.cycling
    ActivityKind.SWIMMING -> ActivityType.swimming
}

@Composable private fun Metric(label: String, value: String) = Column(horizontalAlignment = Alignment.CenterHorizontally) {
    Text(value, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
    Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

@Composable
private fun ReflectionScreen(
    snapshot: RecordingSnapshot,
    launch: RecordingLaunchConfiguration,
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
        LazyColumn(Modifier.fillMaxSize().padding(padding), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            item {
                Box(Modifier.fillMaxWidth().height(200.dp).background(MaterialTheme.colorScheme.primaryContainer)) {
                    if (snapshot.track.size > 1) PlainstrideRouteMap(
                        points = snapshot.track.map { MapCoordinate(it.latitude, it.longitude) },
                        modifier = Modifier.fillMaxSize(),
                        interactive = false,
                    )
                    else Icon(Icons.AutoMirrored.Filled.DirectionsRun, null, Modifier.size(72.dp).align(Alignment.Center), tint = MaterialTheme.colorScheme.primary)
                    Surface(shape = CircleShape, tonalElevation = 6.dp, modifier = Modifier.align(Alignment.TopStart).padding(16.dp)) {
                        IconButton(onClick = onClose, enabled = !saving) { Icon(Icons.Default.Close, stringResource(R.string.recording_discard)) }
                    }
                    Button(
                        onClick = onSave,
                        enabled = snapshot.saveEligibility == ActivitySaveEligibility.ELIGIBLE && !saving,
                        modifier = Modifier.align(Alignment.TopEnd).padding(16.dp).heightIn(min = 48.dp),
                    ) {
                        Text(stringResource(if (saving) R.string.recording_saving_activity else R.string.recording_save_activity))
                    }
                }
            }
            item {
                val shortSession = snapshot.elapsedSeconds <= 600
                Card(
                    Modifier.fillMaxWidth().padding(horizontal = 20.dp),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.55f)),
                ) {
                    Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(stringResource(if (shortSession) R.string.recording_reflection_promise_title else R.string.recording_nice_work), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                        Text(stringResource(if (shortSession) R.string.recording_reflection_promise_body else R.string.recording_reflection_body), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        launch.workoutGuideline?.takeIf(String::isNotBlank)?.let { Text(it, fontWeight = FontWeight.SemiBold) }
                        Text(stringResource(R.string.recording_reflection_highlight, formatDuration(snapshot.elapsedSeconds)), color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Bold)
                    }
                }
            }
            item {
                Card(Modifier.fillMaxWidth().padding(horizontal = 20.dp)) { Column(Modifier.padding(16.dp)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Metric(stringResource(R.string.recording_distance), formatDistance(snapshot.distanceMeters))
                    Metric(stringResource(R.string.recording_time), formatDuration(snapshot.elapsedSeconds))
                    Metric(stringResource(R.string.recording_avg_pace), formatPace(snapshot.distanceMeters.takeIf { it > 0 }?.let { snapshot.elapsedSeconds / (it / 1000.0) }))
                }
                Spacer(Modifier.height(12.dp))
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                    Metric(stringResource(R.string.recording_elevation), "${snapshot.elevationGainMeters.toInt()} m")
                }
                } }
            }
            item {
                Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(stringResource(R.string.recording_reflection_prompt), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
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
                Text(stringResource(R.string.recording_reflection_optional), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            item {
                if (photoPath == null) OutlinedButton(onClick = onTakePhoto, modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp)) {
                    Icon(Icons.Default.CameraAlt, null); Spacer(Modifier.width(8.dp)); Text(stringResource(R.string.recording_add_photo))
                } else Card(Modifier.fillMaxWidth().padding(horizontal = 20.dp).clickable(onClick = onTakePhoto)) {
                    val bitmap = remember(photoPath) { BitmapFactory.decodeFile(photoPath) }
                    bitmap?.let { Image(it.asImageBitmap(), stringResource(R.string.recording_activity_photo), Modifier.fillMaxWidth().aspectRatio(16f / 9f)) }
                    TextButton(onClick = onRemovePhoto) { Text(stringResource(R.string.recording_remove_photo)) }
                }
            }
            item {
                if (snapshot.saveEligibility == ActivitySaveEligibility.TOO_SHORT) {
                    Text(stringResource(R.string.recording_save_ineligible_explanation), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 8.dp))
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

private fun goalProgress(snapshot: RecordingSnapshot, goal: RecordingGoal, energyKilocalories: Double? = null): Float? = when (goal.type) {
    RecordingGoalType.DISTANCE -> goal.targetDistanceMeters?.takeIf { it > 0 }?.let { (snapshot.distanceMeters / it).toFloat().coerceIn(0f, 1f) }
    RecordingGoalType.TIME -> goal.targetDurationSeconds?.takeIf { it > 0 }?.let { (snapshot.elapsedSeconds.toDouble() / it).toFloat().coerceIn(0f, 1f) }
    RecordingGoalType.WORKOUT -> goal.targetDurationSeconds?.takeIf { it > 0 }?.let { (snapshot.elapsedSeconds.toDouble() / it).toFloat().coerceIn(0f, 1f) }
    RecordingGoalType.CALORIES -> goal.targetCalories?.takeIf { it > 0 }?.let { ((energyKilocalories ?: 0.0) / it).toFloat().coerceIn(0f, 1f) }
    else -> null
}

internal fun formatDuration(seconds: Long): String = if (seconds >= 3_600) {
    "%d:%02d:%02d".format(seconds / 3_600, seconds / 60 % 60, seconds % 60)
} else {
    "%d:%02d".format(seconds / 60, seconds % 60)
}
internal fun formatDistance(meters: Double): String = "%.2f km".format(meters / 1_000)
private fun formatDistance(meters: Double, unitSystem: MeasurementUnitSystem): String {
    val distance = SessionFormatting.distance(meters, unitSystem)
    return "%.2f %s".format(distance.value, distance.unit.shortLabel)
}
internal fun formatPace(seconds: Double?): String = seconds?.takeIf { it.isFinite() && it < 3_600 }?.let { "%d:%02d /km".format(it.toInt() / 60, it.toInt() % 60) } ?: "—"
private fun formatPace(seconds: Double?, unitSystem: MeasurementUnitSystem): String = seconds
    ?.takeIf { it.isFinite() && it < 3_600 }
    ?.let { SessionFormatting.pace(it, unitSystem) }
    ?.let { "%d:%02d /%s".format(it.minutes, it.seconds, it.unit.shortLabel) }
    ?: "—"
private fun formatElevation(meters: Double, unitSystem: MeasurementUnitSystem): String {
    val elevation = SessionFormatting.elevation(meters, unitSystem)
    val unit = if (elevation.unit == ElevationUnit.meter) "m" else "ft"
    return "%.0f %s".format(elevation.value, unit)
}
private fun Context.openAppSettings() = startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))

private fun recordingLocationPermission(context: Context, askedBefore: Boolean): LocationPermissionState = when {
    LocationPermissionAccess.hasPrecisePermission(context) -> LocationPermissionState.PRECISE
    LocationPermissionAccess.hasApproximatePermission(context) -> LocationPermissionState.APPROXIMATE
    askedBefore || LocationPermissionAccess.wasRequestedBefore(context) -> LocationPermissionState.DENIED
    else -> LocationPermissionState.NOT_REQUESTED
}
