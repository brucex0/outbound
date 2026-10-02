package com.plainstride.outbound.feature.recording

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.graphics.Bitmap
import android.graphics.Matrix
import android.media.ExifInterface
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
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
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
import androidx.compose.ui.window.Dialog
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
import java.io.FileOutputStream
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
import com.plainstride.outbound.core.model.activity.SharedLiveRun
import com.plainstride.outbound.core.model.activity.SessionFormatting
import com.plainstride.outbound.core.model.activity.WorkoutCalorieEstimator

data class RecordedActivityReview(
    val snapshot: RecordingSnapshot,
    val reflection: ReflectionChoice?,
    val continuationCapacity: ContinuationCapacity?,
    /** App-private path; callers must not expose it without an explicit share action. */
    val photoPaths: List<String>,
    val importedPhotoPaths: Set<String>,
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
    onCheerMeOn: () -> Unit = {},
    cheerSelectedName: String? = null,
    cheerSelectedCount: Int = 0,
    saveActivityPhotosToAlbum: Boolean = true,
    onPhotoAlbumPermissionDenied: () -> Unit = {},
    onPrepareActivityStart: () -> Unit = {},
    modifier: Modifier = Modifier,
    unitSystem: MeasurementUnitSystem = MeasurementUnitSystem.metric,
    weightKilograms: Double? = null,
    sessionEffect: @Composable (RecordingSnapshot) -> Unit = {},
    groupRun: SharedLiveRun? = null,
    groupRunJoining: Boolean = false,
    onToggleActivityLiveMap: () -> Unit = {},
    onStopActivityLiveMap: () -> Unit = {},
    viewModel: RecordingViewModel = hiltViewModel(),
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val scope = rememberCoroutineScope()
    val ui by viewModel.state.collectAsStateWithLifecycle()
    val snapshot by viewModel.snapshot.collectAsStateWithLifecycle()
    val voiceListening by viewModel.voiceListening.collectAsStateWithLifecycle()
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
    var postSaveCelebrationReview by remember { mutableStateOf<RecordedActivityReview?>(null) }
    var didDismissPostSaveCelebration by remember { mutableStateOf(false) }
    val saveSnackbar = remember { SnackbarHostState() }
    val saveFailedMessage = stringResource(R.string.recording_save_failed)
    val eventGroupRun = groupRun?.takeIf { run ->
        launch.activityEventId != null && run.activityEventId == launch.activityEventId
    }
    val eventGroupSharing = eventGroupRun?.participants?.any { participant ->
        participant.userId == eventGroupRun.currentUserId && participant.status in setOf("active", "stale")
    } == true
    val otherActiveGroupRun = groupRun?.takeIf { run ->
        run.status == "active" && run.activityEventId != launch.activityEventId && run.participants.any { participant ->
            participant.userId == run.currentUserId && participant.status in setOf("active", "stale")
        }
    }

    fun finishPostSaveCelebration() {
        if (didDismissPostSaveCelebration) return
        didDismissPostSaveCelebration = true
        postSaveCelebrationReview = null
        if (postSaveStretchKind == null) {
            val review = postSaveReview ?: return
            val export = postSavePhotoAlbumExport
            postSaveReview = null
            postSavePhotoAlbumExport = null
            onSaved(review, export)
        }
    }

    LaunchedEffect(postSaveCelebrationReview?.snapshot?.sessionId) {
        if (postSaveCelebrationReview != null) {
            didDismissPostSaveCelebration = false
            viewModel.trackPostSaveCelebrationExposed()
        }
    }

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
                val result = viewModel.saveFinished(review, exportPhoto, weightKilograms)
                if (result.saved) {
                    viewModel.markSaved()
                    onSavedSideEffects(review)
                    postSaveReview = review
                    postSavePhotoAlbumExport = overrideResult ?: result.photoAlbumExport
                    postSaveStretchKind = review.snapshot.activityKind.takeIf { PostWorkoutStretchCatalog.routines(it) != null }
                    postSaveCelebrationReview = review
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
        onPrepareActivityStart()
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
        if (saved && file != null) viewModel.addFinishPhoto(file.absolutePath) else file?.delete()
        pendingPhoto = null
        viewModel.setPendingMedia(false)
    }
    val importPhotoLauncher = rememberLauncherForActivityResult(ActivityResultContracts.GetMultipleContents()) { uris ->
        if (uris.isNotEmpty()) scope.launch {
            val directory = File(context.filesDir, "activity_photos").apply { mkdirs() }
            val imported = uris.mapNotNull { uri ->
                importFinishPhoto(context, uri, directory)?.absolutePath
            }
            if (imported.isNotEmpty()) {
                viewModel.addImportedFinishPhotos(imported)
            }
        }
    }
    fun capturePhoto(sourceType: String = "recording") {
        viewModel.trackPhotoAttempt(sourceType)
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
    fun closeReview() {
        if (snapshot.saveEligibility == ActivitySaveEligibility.ELIGIBLE) {
            viewModel.requestDiscard()
        } else {
            scope.launch {
                ui.photoPaths.forEach { File(it).delete() }
                if (viewModel.discard()) onExit()
            }
        }
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
            RecordingStatus.AWAITING_SAVE -> closeReview()
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
                unitSystem = unitSystem,
                weightKilograms = weightKilograms,
                selected = ui.reflection,
                photoPaths = ui.photoPaths,
                importedPhotoPaths = ui.importedPhotoPaths,
                continuationCapacity = ui.continuationCapacity,
                onSelect = viewModel::setReflection,
                onCapacitySelect = viewModel::setContinuationCapacity,
                onTakePhoto = { capturePhoto("finish_review") },
                onImportPhotos = { viewModel.trackPhotoAttempt("finish_photo_library"); importPhotoLauncher.launch("image/*") },
                onPhotoPreviewed = viewModel::trackPhotoPreviewed,
                onRemovePhotos = { paths -> paths.forEach { File(it).delete() }; viewModel.setPhotoPaths(ui.photoPaths - paths.toSet()); viewModel.trackPhotoRemoved() },
                onReorderPhotos = { paths -> viewModel.setPhotoPaths(paths); viewModel.trackPhotoReordered() },
                onSave = {
                    val reflection = ui.reflection
                    val review = RecordedActivityReview(snapshot, reflection, ui.continuationCapacity, ui.photoPaths, ui.importedPhotoPaths)
                    val needsLegacyStoragePermission = saveActivityPhotosToAlbum &&
                        ui.photoPaths.isNotEmpty() &&
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
                onClose = ::closeReview,
            )
            snapshot.status == RecordingStatus.ACTIVE || snapshot.status == RecordingStatus.PAUSED -> LiveRecordingScreen(
                snapshot = snapshot,
                configuration = ui.launch,
                groupRun = eventGroupRun?.takeIf { eventGroupSharing },
                locationPermission = permissionState(),
                unitSystem = unitSystem,
                weightKilograms = weightKilograms,
                mode = ui.mode,
                photoPath = ui.photoPaths.lastOrNull(),
                onMode = { mode ->
                    if (mode == RecordingSurfaceMode.CAMERA && context.checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
                        cameraPermissionLauncher.launch(Manifest.permission.CAMERA)
                    } else viewModel.setMode(mode)
                },
                onTakePhoto = { capturePhoto("recording") },
                onPhotoCaptured = { path -> viewModel.addFinishPhoto(path, "recording") },
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
                onStopActivityLiveMap = onStopActivityLiveMap,
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
                activityLiveMapEnabled = eventGroupSharing,
                activityLiveMapJoining = groupRunJoining,
                activityLiveMapBlocked = otherActiveGroupRun != null,
                onToggleActivityLiveMap = onToggleActivityLiveMap,
                onStopActivityLiveMap = onStopActivityLiveMap,
                permission = permissionState(),
                onStart = ::beginCountdown,
                onRequestLocationAccess = { showLocationEducation = true },
                onCheerMeOn = onCheerMeOn,
                cheerSelectedName = cheerSelectedName,
                cheerSelectedCount = cheerSelectedCount,
                onExit = onExit,
                onSimulationChanged = viewModel::configureSimulatedRun,
                onAutoPauseChanged = viewModel::setAutoPauseEnabled,
            )
        }
    }

    Box(modifier.fillMaxSize()) {
        if (postSaveStretchKind != null) {
            val review = requireNotNull(postSaveReview)
            val export = postSavePhotoAlbumExport
            PostWorkoutStretchRoute(
                kind = requireNotNull(postSaveStretchKind),
                track = review.snapshot.track,
                sessionKey = review.snapshot.sessionId ?: review.snapshot.recordedAtEpochMilliseconds.toString(),
                onDone = {
                    postSaveCelebrationReview = null
                    postSaveReview = null
                    postSavePhotoAlbumExport = null
                    postSaveStretchKind = null
                    onSaved(review, export)
                },
                onEvent = { name, routineId, result ->
                    viewModel.trackStretchEvent(name, requireNotNull(postSaveStretchKind), routineId, result)
                },
            )
        } else if (postSaveCelebrationReview != null) {
            val review = requireNotNull(postSaveCelebrationReview)
            PostSaveCelebration(
                track = review.snapshot.track,
                sessionKey = review.snapshot.sessionId ?: review.snapshot.recordedAtEpochMilliseconds.toString(),
                onDone = ::finishPostSaveCelebration,
            )
        } else {
            content()
            SnackbarHost(saveSnackbar, Modifier.align(Alignment.BottomCenter))
        }
        if (isOffline && postSaveStretchKind == null && postSaveCelebrationReview == null) {
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
        sessionEffect(snapshot)
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
        title = { Text(stringResource(R.string.recording_discard_review_title)) },
        text = { Text(stringResource(R.string.recording_discard_review_message)) },
        confirmButton = { TextButton(
            enabled = !ui.discarding,
            onClick = {
                scope.launch {
                    if (viewModel.discard()) {
                        ui.photoPaths.forEach { File(it).delete() }
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
    activityLiveMapEnabled: Boolean,
    activityLiveMapJoining: Boolean,
    activityLiveMapBlocked: Boolean,
    onToggleActivityLiveMap: () -> Unit,
    onStopActivityLiveMap: () -> Unit,
    permission: LocationPermissionState,
    onStart: () -> Unit,
    onRequestLocationAccess: () -> Unit,
    onCheerMeOn: () -> Unit,
    cheerSelectedName: String?,
    cheerSelectedCount: Int,
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
            configuration.activityEventId?.let { eventId ->
                item {
                    val sharing = activityLiveMapEnabled
                    val liveShareAccessibilityLabel = stringResource(R.string.recording_group_share)
                    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer)) {
                        Row(Modifier.fillMaxWidth().padding(16.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(12.dp)) {
                            Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(4.dp)) {
                                Text(stringResource(if(sharing) R.string.recording_group_shared else R.string.recording_group_share),style=MaterialTheme.typography.titleSmall,fontWeight=FontWeight.SemiBold)
                                Text(stringResource(R.string.recording_group_share_detail),style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            when {
                                sharing -> TextButton(onClick=onStopActivityLiveMap){Text(stringResource(R.string.recording_group_stop_sharing))}
                                activityLiveMapBlocked -> Row(
                                    Modifier.weight(1f),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                                ) {
                                    Text(
                                        stringResource(R.string.recording_group_active_elsewhere),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.error,
                                        modifier = Modifier.weight(1f),
                                    )
                                    TextButton(onClick = onStopActivityLiveMap) {
                                        Text(stringResource(R.string.recording_group_stop_sharing))
                                    }
                                }
                                else -> Switch(
                                    checked = false,
                                    onCheckedChange = { onToggleActivityLiveMap() },
                                    enabled = !activityLiveMapJoining && !activityLiveMapBlocked,
                                    modifier = Modifier.semantics {
                                        contentDescription = liveShareAccessibilityLabel
                                    },
                                )
                            }
                        }
                    }
                    if(activityLiveMapJoining)LinearProgressIndicator(Modifier.fillMaxWidth())
                }
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
            item {
                val hasCheerRecipients = cheerSelectedCount > 0
                OutlinedButton(
                    onClick = onCheerMeOn,
                    modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp),
                    colors = ButtonDefaults.outlinedButtonColors(
                        containerColor = if (hasCheerRecipients) MaterialTheme.colorScheme.primaryContainer else Color.Transparent,
                        contentColor = if (hasCheerRecipients) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.primary,
                    ),
                ) {
                    Icon(if (hasCheerRecipients) Icons.Default.Check else Icons.Default.Mic, null)
                    Spacer(Modifier.width(10.dp))
                    Column(Modifier.weight(1f), horizontalAlignment = Alignment.Start) {
                        Text(stringResource(R.string.recording_cheer_on), fontWeight = FontWeight.SemiBold)
                        Text(
                            when {
                                cheerSelectedCount > 1 -> stringResource(R.string.recording_cheer_selected_count, cheerSelectedCount)
                                cheerSelectedName != null -> stringResource(R.string.recording_cheer_selected, cheerSelectedName)
                                cheerSelectedCount == 1 -> stringResource(R.string.recording_cheer_generic)
                                else -> stringResource(R.string.recording_cheer_off)
                            },
                            style = MaterialTheme.typography.bodySmall,
                            color = if (hasCheerRecipients) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurfaceVariant,
                        )
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
    groupRun: SharedLiveRun?,
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
    onStopActivityLiveMap: () -> Unit = {},
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
        groupRun?.let { run ->
            ActivityGroupLiveMapCard(run,Modifier.align(Alignment.TopStart).padding(top=16.dp,start=16.dp,end=16.dp),onStopActivityLiveMap)
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
private fun ActivityGroupLiveMapCard(run:SharedLiveRun,modifier:Modifier=Modifier,onStop:()->Unit){
 val participants=run.participants.filter{it.status in setOf("active","stale")}
 val mapPoints=participants.mapNotNull{participant->participant.latitude?.let{latitude->participant.longitude?.let{longitude->MapCoordinate(latitude,longitude)}}}
 Surface(modifier=modifier.fillMaxWidth(),shape=RoundedCornerShape(18.dp),color=MaterialTheme.colorScheme.surface.copy(alpha=.96f),shadowElevation=8.dp){
  Column(Modifier.padding(12.dp),verticalArrangement=Arrangement.spacedBy(6.dp)){
   Row(verticalAlignment=Alignment.CenterVertically){Text(stringResource(R.string.recording_group_participants),Modifier.weight(1f),style=MaterialTheme.typography.titleSmall,fontWeight=FontWeight.SemiBold);TextButton(onClick=onStop){Text(stringResource(R.string.recording_group_stop_sharing))}}
   if(mapPoints.isNotEmpty())PlainstrideRouteMap(points=mapPoints,modifier=Modifier.fillMaxWidth().height(150.dp),showUserLocation=false,preciseLocationGranted=false,focusOnUser=false,fitRouteOnChange=true,markers=participants.mapNotNull{participant->participant.latitude?.let{latitude->participant.longitude?.let{longitude->com.plainstride.outbound.core.designsystem.MapRouteMarker(id=participant.id,coordinate=MapCoordinate(latitude,longitude),title=participant.displayName,selected=participant.userId==run.currentUserId)}}})
   participants.forEach{participant->
    val freshness=participant.lastLocationAt?.let{raw->runCatching{java.time.Duration.between(java.time.Instant.parse(raw),java.time.Instant.now()).seconds.coerceAtLeast(0)}.getOrNull()}
    val status=when{participant.latitude==null||participant.longitude==null->stringResource(R.string.recording_group_waiting);freshness!=null&&freshness>60->stringResource(R.string.recording_group_stale,formatDuration(freshness));else->"${formatDistance(participant.distanceMeters,MeasurementUnitSystem.metric)} · ${formatDuration(participant.elapsedSeconds.toLong())}"}
    Text("${participant.displayName} · $status",style=MaterialTheme.typography.bodySmall,maxLines=1,overflow=TextOverflow.Ellipsis)
   }
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

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ReflectionScreen(
    snapshot: RecordingSnapshot,
    launch: RecordingLaunchConfiguration,
    unitSystem: MeasurementUnitSystem,
    weightKilograms: Double?,
    selected: ReflectionChoice?,
    photoPaths: List<String>,
    importedPhotoPaths: Set<String>,
    continuationCapacity: ContinuationCapacity?,
    onSelect: (ReflectionChoice) -> Unit,
    onCapacitySelect: (ContinuationCapacity) -> Unit,
    onTakePhoto: () -> Unit,
    onImportPhotos: () -> Unit,
    onPhotoPreviewed: () -> Unit,
    onRemovePhotos: (List<String>) -> Unit,
    onReorderPhotos: (List<String>) -> Unit,
    onSave: () -> Unit,
    saving: Boolean,
    onClose: () -> Unit,
) {
    var selectedPhotos by remember(photoPaths) { mutableStateOf(emptySet<String>()) }
    var previewPhoto by remember { mutableStateOf<String?>(null) }
    val paceSecondsPerKm = snapshot.distanceMeters.takeIf { it > 0 }
        ?.let { snapshot.elapsedSeconds / (it / 1_000.0) }
    val calories = WorkoutCalorieEstimator.estimate(
        activityType = snapshot.activityKind.toActivityType(),
        distanceMeters = snapshot.distanceMeters,
        durationSeconds = snapshot.elapsedSeconds.coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
        elevationGainMeters = snapshot.elevationGainMeters,
        weightKilograms = weightKilograms,
    )
    val heroPageCount = (if (snapshot.track.size > 1) 1 else 0) + photoPaths.size
    val pagerState = rememberPagerState(pageCount = { maxOf(1, heroPageCount) })
    Scaffold(contentWindowInsets = WindowInsets.safeDrawing) { padding ->
        LazyColumn(Modifier.fillMaxSize().padding(padding), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            item {
                Box(Modifier.fillMaxWidth().height(280.dp).background(MaterialTheme.colorScheme.primaryContainer)) {
                    HorizontalPager(state = pagerState, modifier = Modifier.fillMaxSize()) { page ->
                        if (snapshot.track.size > 1 && page == 0) {
                            PlainstrideRouteMap(
                                points = snapshot.track.map { MapCoordinate(it.latitude, it.longitude) },
                                modifier = Modifier.fillMaxSize(),
                                interactive = false,
                            )
                        } else if (photoPaths.isNotEmpty()) {
                            val photoIndex = page - if (snapshot.track.size > 1) 1 else 0
                            val path = photoPaths.getOrNull(photoIndex)
                            val bitmap = remember(path) { path?.let { BitmapFactory.decodeFile(it) } }
                            bitmap?.let { Image(it.asImageBitmap(), stringResource(R.string.recording_activity_photo), Modifier.fillMaxSize(), contentScale = ContentScale.Crop) }
                        } else {
                            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                                Icon(Icons.AutoMirrored.Filled.DirectionsRun, null, Modifier.size(72.dp), tint = MaterialTheme.colorScheme.primary)
                            }
                        }
                    }
                    if (pagerState.pageCount > 1) {
                        Text("${pagerState.currentPage + 1} / ${pagerState.pageCount}", Modifier.align(Alignment.BottomCenter).padding(12.dp), color = Color.White, style = MaterialTheme.typography.labelMedium)
                    }
                    Surface(shape = CircleShape, tonalElevation = 6.dp, modifier = Modifier.align(Alignment.TopStart).padding(16.dp)) {
                        IconButton(onClick = onClose, enabled = !saving) { Icon(Icons.Default.Close, stringResource(R.string.recording_discard)) }
                    }
                    Button(
                        onClick = onSave,
                        enabled = snapshot.saveEligibility == ActivitySaveEligibility.ELIGIBLE && !saving,
                        modifier = Modifier.align(Alignment.TopEnd).padding(16.dp).heightIn(min = 48.dp),
                    ) {
                        Text(stringResource(if (saving) R.string.recording_saving_activity else if (snapshot.saveEligibility == ActivitySaveEligibility.ELIGIBLE) R.string.recording_save_activity else R.string.recording_too_short_to_save))
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
                Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(stringResource(R.string.recording_reflection_prompt), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        ReflectionChoice.entries.forEach { choice ->
                            val label = stringResource(when (choice) {
                                ReflectionChoice.EASY -> R.string.recording_reflection_easy
                                ReflectionChoice.ABOUT_RIGHT -> R.string.recording_reflection_about_right
                                ReflectionChoice.TOO_HARD -> R.string.recording_reflection_too_hard
                            })
                            if (selected == choice) Button(onClick = { onSelect(choice) }, modifier = Modifier.weight(1f)) { Text(label) }
                            else OutlinedButton(onClick = { onSelect(choice) }, modifier = Modifier.weight(1f)) { Text(label) }
                        }
                    }
                    if (selected == ReflectionChoice.EASY) {
                        Text(stringResource(R.string.recording_capacity_prompt), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            ContinuationCapacity.entries.forEach { capacity ->
                                val label = stringResource(when (capacity) {
                                    ContinuationCapacity.NONE -> R.string.recording_capacity_none
                                    ContinuationCapacity.TEN_MINUTES -> R.string.recording_capacity_ten_minutes
                                    ContinuationCapacity.MUCH_LONGER -> R.string.recording_capacity_much_longer
                                })
                                if (continuationCapacity == capacity) Button(onClick = { onCapacitySelect(capacity) }, modifier = Modifier.weight(1f)) { Text(label) }
                                else OutlinedButton(onClick = { onCapacitySelect(capacity) }, modifier = Modifier.weight(1f)) { Text(label) }
                            }
                        }
                    }
                    Text(stringResource(R.string.recording_reflection_optional), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            item {
                Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(stringResource(R.string.recording_review_photo_section_title), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                        Spacer(Modifier.weight(1f))
                        if (selectedPhotos.isNotEmpty()) {
                            TextButton(onClick = { onRemovePhotos(selectedPhotos.toList()); selectedPhotos = emptySet() }) { Text(stringResource(R.string.recording_review_photo_delete_selected)) }
                            TextButton(onClick = { selectedPhotos = emptySet() }) { Text(stringResource(R.string.recording_cancel)) }
                        } else {
                            TextButton(onClick = onTakePhoto) { Text(stringResource(R.string.recording_review_photo_take)) }
                            TextButton(onClick = onImportPhotos) { Text(stringResource(R.string.recording_review_photo_import)) }
                        }
                    }
                    if (photoPaths.isEmpty()) {
                        Text(stringResource(R.string.recording_review_photo_empty), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    } else {
                        androidx.compose.foundation.lazy.LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            itemsIndexed(photoPaths, key = { _, path -> path }) { index, path ->
                                val bitmap = remember(path) { BitmapFactory.decodeFile(path) }
                                Box(
                                    Modifier.size(width = 116.dp, height = 104.dp)
                                        .clip(RoundedCornerShape(12.dp))
                                        .combinedClickable(
                                            onClick = {
                                                if (selectedPhotos.isEmpty()) { previewPhoto = path; onPhotoPreviewed() }
                                                else selectedPhotos = if (path in selectedPhotos) selectedPhotos - path else selectedPhotos + path
                                            },
                                            onLongClick = { selectedPhotos = selectedPhotos + path },
                                        )
                                        .border(if (path in selectedPhotos) 3.dp else 0.dp, if (path in selectedPhotos) MaterialTheme.colorScheme.primary else Color.Transparent, RoundedCornerShape(12.dp))
                                ) {
                                    bitmap?.let { Image(it.asImageBitmap(), stringResource(R.string.recording_activity_photo), Modifier.fillMaxSize(), contentScale = ContentScale.Crop) }
                                    Text(
                                        finishPhotoCaption(path, index, photoPaths.lastIndex, path in importedPhotoPaths, snapshot, unitSystem),
                                        Modifier.align(Alignment.BottomStart).fillMaxWidth().background(Color.Black.copy(alpha = .65f)).padding(8.dp),
                                        color = Color.White,
                                        style = MaterialTheme.typography.labelSmall,
                                    )
                                }
                                if (path in selectedPhotos) {
                                    Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                                        TextButton(enabled = index > 0, onClick = { val updated = photoPaths.toMutableList(); updated.removeAt(index); updated.add(index - 1, path); onReorderPhotos(updated) }) { Text("↑") }
                                        TextButton(enabled = index < photoPaths.lastIndex, onClick = { val updated = photoPaths.toMutableList(); updated.removeAt(index); updated.add(index + 1, path); onReorderPhotos(updated) }) { Text("↓") }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            item {
                Card(Modifier.fillMaxWidth().padding(horizontal = 20.dp)) { Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                        val distance = SessionFormatting.distance(snapshot.distanceMeters, unitSystem)
                        Metric(stringResource(R.string.recording_distance), "%.2f %s".format(distance.value, distance.unit.shortLabel))
                        Metric(stringResource(R.string.recording_time), formatDuration(snapshot.elapsedSeconds))
                        Metric(stringResource(R.string.recording_avg_pace), formatPace(paceSecondsPerKm, unitSystem))
                    }
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                        val elevation = SessionFormatting.elevation(snapshot.elevationGainMeters, unitSystem)
                        Metric(stringResource(R.string.recording_elevation), "${elevation.value.toInt()} ${if (unitSystem == MeasurementUnitSystem.metric) "m" else "ft"}")
                        Metric(stringResource(R.string.recording_review_calories), calories.kilocalories?.toString() ?: "—")
                    }
                } }
            }
            item {
                if (snapshot.saveEligibility == ActivitySaveEligibility.TOO_SHORT) {
                    Text(stringResource(R.string.recording_save_ineligible_explanation), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 8.dp))
                }
            }
        }
    }
    previewPhoto?.let {
        Dialog(onDismissRequest = { previewPhoto = null }) {
            Box(Modifier.fillMaxSize().background(Color.Black), contentAlignment = Alignment.Center) {
                val selectedIndex = photoPaths.indexOf(it).coerceAtLeast(0)
                val previewPager = rememberPagerState(initialPage = selectedIndex, pageCount = { photoPaths.size })
                HorizontalPager(state = previewPager, modifier = Modifier.fillMaxSize()) { page ->
                    val path = photoPaths.getOrNull(page)
                    val bitmap = remember(path) { path?.let { BitmapFactory.decodeFile(it) } }
                    bitmap?.let { Image(it.asImageBitmap(), stringResource(R.string.recording_activity_photo), Modifier.fillMaxSize(), contentScale = ContentScale.Fit) }
                }
                IconButton(onClick = { previewPhoto = null }, modifier = Modifier.align(Alignment.TopEnd)) { Icon(Icons.Default.Close, stringResource(R.string.recording_close), tint = Color.White) }
            }
        }
    }
}

@Composable
private fun finishPhotoCaption(
    path: String,
    index: Int,
    lastIndex: Int,
    isImported: Boolean,
    snapshot: RecordingSnapshot,
    unitSystem: MeasurementUnitSystem,
): String {
    val takenAt = remember(path) {
        val raw = runCatching { ExifInterface(path).getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL) }.getOrNull()
            ?: runCatching { ExifInterface(path).getAttribute(ExifInterface.TAG_DATETIME) }.getOrNull()
        raw?.let { runCatching { java.text.SimpleDateFormat("yyyy:MM:dd HH:mm:ss", java.util.Locale.US).parse(it)?.time }.getOrNull() }
    }
    if (takenAt != null) {
        val startedAt = snapshot.startedAtEpochMilliseconds ?: takenAt
        if (takenAt < startedAt) return stringResource(R.string.recording_review_photo_start)
        val captureContext = when {
            takenAt < (snapshot.startedAtEpochMilliseconds ?: takenAt) -> "pre_activity"
            takenAt >= snapshot.recordedAtEpochMilliseconds -> "paused"
            else -> "active"
        }
        if (isImported) {
            if (captureContext == "pre_activity") return stringResource(R.string.recording_review_photo_start)
            if (captureContext == "paused") return stringResource(R.string.recording_review_photo_finish)
        } else {
            if (captureContext == "pre_activity") return stringResource(R.string.recording_review_photo_start)
            if (captureContext == "paused" || index == lastIndex) return stringResource(R.string.recording_review_photo_finish)
        }
        val points = snapshot.track
        var cumulative = 0.0
        val distances = mutableListOf<Double>()
        points.forEachIndexed { pointIndex, point ->
            if (pointIndex > 0 && pointIndex !in snapshot.trackSegmentStartIndices) {
                val previous = points[pointIndex - 1]
                cumulative += routeDistanceMeters(previous.latitude, previous.longitude, point.latitude, point.longitude)
            }
            distances += cumulative
        }
        val shotDistance = when {
            points.isEmpty() -> snapshot.distanceMeters
            takenAt <= points.first().capturedAtEpochMilliseconds -> distances.first()
            takenAt >= points.last().capturedAtEpochMilliseconds -> distances.last()
            else -> {
                val upper = points.indexOfFirst { it.capturedAtEpochMilliseconds >= takenAt }.coerceAtLeast(1)
                val before = points[upper - 1]
                val after = points[upper]
                val duration = (after.capturedAtEpochMilliseconds - before.capturedAtEpochMilliseconds).coerceAtLeast(1)
                val progress = (takenAt - before.capturedAtEpochMilliseconds).toDouble() / duration
                distances[upper - 1] + (distances[upper] - distances[upper - 1]) * progress
            }
        }
        val distance = SessionFormatting.distance(shotDistance, unitSystem)
        return "%.1f %s".format(distance.value, distance.unit.shortLabel)
    }
    return stringResource(R.string.recording_review_photo_finish)
}

private fun routeDistanceMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
    val p1 = Math.toRadians(lat1)
    val p2 = Math.toRadians(lat2)
    val deltaLat = p2 - p1
    val deltaLon = Math.toRadians(lon2 - lon1)
    val a = kotlin.math.sin(deltaLat / 2).let { it * it } + kotlin.math.cos(p1) * kotlin.math.cos(p2) * kotlin.math.sin(deltaLon / 2).let { it * it }
    return 6_371_000.0 * 2 * kotlin.math.atan2(kotlin.math.sqrt(a), kotlin.math.sqrt(1 - a))
}

private fun importFinishPhoto(context: Context, uri: Uri, directory: File): File? {
    val source = File(directory, "${UUID.randomUUID()}.source")
    val destination = File(directory, "${UUID.randomUUID()}.jpg")
    return runCatching {
        context.contentResolver.openInputStream(uri)?.use { input -> source.outputStream().use(input::copyTo) }
            ?: return null
        val originalExif = ExifInterface(source)
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(source.absolutePath, bounds)
        var sample = 1
        while (maxOf(bounds.outWidth / sample, bounds.outHeight / sample) > 2048 * 2) sample *= 2
        val decoded = BitmapFactory.decodeFile(source.absolutePath, BitmapFactory.Options().apply { inSampleSize = sample })
            ?: return null
        val scale = minOf(1.0, 2048.0 / maxOf(decoded.width, decoded.height))
        val scaled = if (scale < 1.0) Bitmap.createScaledBitmap(decoded, (decoded.width * scale).toInt().coerceAtLeast(1), (decoded.height * scale).toInt().coerceAtLeast(1), true) else decoded
        val transform = Matrix()
        when (originalExif.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
            ExifInterface.ORIENTATION_ROTATE_90 -> transform.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> transform.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> transform.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> transform.preScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> transform.preScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> { transform.preScale(-1f, 1f); transform.postRotate(270f) }
            ExifInterface.ORIENTATION_TRANSVERSE -> { transform.preScale(-1f, 1f); transform.postRotate(90f) }
        }
        val oriented = if (!transform.isIdentity) Bitmap.createBitmap(scaled, 0, 0, scaled.width, scaled.height, transform, true) else scaled
        FileOutputStream(destination).use { output -> oriented.compress(Bitmap.CompressFormat.JPEG, 90, output) }
        val normalizedExif = ExifInterface(destination)
        listOf(
            ExifInterface.TAG_DATETIME_ORIGINAL, ExifInterface.TAG_DATETIME_DIGITIZED, ExifInterface.TAG_DATETIME,
            ExifInterface.TAG_OFFSET_TIME_ORIGINAL, ExifInterface.TAG_OFFSET_TIME_DIGITIZED, ExifInterface.TAG_OFFSET_TIME,
            ExifInterface.TAG_GPS_LATITUDE, ExifInterface.TAG_GPS_LATITUDE_REF, ExifInterface.TAG_GPS_LONGITUDE,
            ExifInterface.TAG_GPS_LONGITUDE_REF, ExifInterface.TAG_GPS_ALTITUDE, ExifInterface.TAG_GPS_ALTITUDE_REF,
            ExifInterface.TAG_GPS_TIMESTAMP, ExifInterface.TAG_GPS_DATESTAMP,
        ).forEach { tag -> originalExif.getAttribute(tag)?.let { normalizedExif.setAttribute(tag, it) } }
        normalizedExif.setAttribute(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL.toString())
        normalizedExif.saveAttributes()
        if (decoded !== scaled) decoded.recycle()
        if (scaled !== oriented && scaled !== decoded) scaled.recycle()
        if (oriented !== scaled) oriented.recycle()
        destination
    }.getOrElse { destination.delete(); null }.also { source.delete() }
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
