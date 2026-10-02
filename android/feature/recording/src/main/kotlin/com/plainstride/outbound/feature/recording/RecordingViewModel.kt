package com.plainstride.outbound.feature.recording

import android.content.Context
import android.util.Log
import android.media.ExifInterface
import java.io.File
import java.security.MessageDigest
import java.time.Instant
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import java.util.UUID
import java.util.Locale
import java.text.SimpleDateFormat
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import com.plainstride.outbound.core.analytics.AnalyticsEvent
import com.plainstride.outbound.core.analytics.AnalyticsProperty
import com.plainstride.outbound.core.analytics.ProductAnalytics
import com.plainstride.outbound.core.data.ActivityMediaStore
import com.plainstride.outbound.core.data.ActivityRepository
import com.plainstride.outbound.core.data.ActivitySyncScheduler
import com.plainstride.outbound.core.data.RecordedActivityDraft
import com.plainstride.outbound.core.data.RecordedActivityFactory
import com.plainstride.outbound.core.data.RecordedTrackPointDraft
import com.plainstride.outbound.core.model.activity.ActivityCompanionType
import com.plainstride.outbound.core.model.activity.ActivityPhoto
import com.plainstride.outbound.core.model.activity.ActivityReflection
import com.plainstride.outbound.core.model.activity.ActivityType
import com.plainstride.outbound.core.model.activity.MeasurementUnitSystem
import com.plainstride.outbound.core.model.activity.WorkoutCalorieEstimator
import com.plainstride.outbound.core.network.AccessTokenProvider
import com.plainstride.outbound.core.network.PlanningApiService
import com.plainstride.outbound.core.network.WorkoutFeedbackRequest
import kotlinx.serialization.json.Json
import kotlinx.coroutines.withTimeoutOrNull

data class RecordingUiState(
    val launch: RecordingLaunchConfiguration = RecordingLaunchConfiguration(),
    val mode: RecordingSurfaceMode = RecordingSurfaceMode.MAP,
    val countdown: Int? = null,
    val countdownVoiceReady: Boolean = false,
    val reflection: ReflectionChoice? = null,
    val continuationCapacity: ContinuationCapacity? = null,
    val photoPaths: List<String> = emptyList(),
    val importedPhotoPaths: Set<String> = emptySet(),
    val showFinishConfirmation: Boolean = false,
    val showDiscardConfirmation: Boolean = false,
    val startRequested: Boolean = false,
    val saving: Boolean = false,
    val discarding: Boolean = false,
    val pendingMedia:Boolean=false,
)

data class RecordedActivitySaveResult(
    val saved: Boolean,
    val photoAlbumExport: ActivityPhotoAlbumExportResult? = null,
)

@HiltViewModel
class RecordingViewModel @Inject constructor(
    @param:ApplicationContext private val context: Context,
    private val analytics: ProductAnalytics,
    private val activities: ActivityRepository,
    private val media: ActivityMediaStore,
    private val syncScheduler: ActivitySyncScheduler,
    private val voice: RecordingVoiceCoordinator,
    private val planningApi: PlanningApiService,
    private val accessTokens: AccessTokenProvider,
) : ViewModel() {
    private val photoAlbumExporter = ActivityPhotoAlbumExporter(context)
    private val launchJson=Json{ignoreUnknownKeys=true;explicitNulls=false}
    private val client = RecordingSessionClient(context).apply { connect() }
    private val mutableState = MutableStateFlow(RecordingUiState())
    val state: StateFlow<RecordingUiState> = mutableState.asStateFlow()
    val snapshot: StateFlow<RecordingSnapshot> = client.snapshots.stateIn(
        viewModelScope,
        SharingStarted.WhileSubscribed(5_000),
        RecordingSnapshot(),
    )
    private var recoveryAccountId: String? = null
    private var preparingCountdown = false
    private var didAutoPauseAtGoal = false
    private var routeBeforeSimulation: FollowedRouteConfiguration? = null
    private var presentationUnitSystem = MeasurementUnitSystem.metric
    val voiceListening: StateFlow<Boolean> = voice.listening
    init { voice.observe(viewModelScope, snapshot = { snapshot.value }, ::pause, ::resume, ::requestFinish) }
    fun listen(permissionGranted: Boolean) = voice.listen(permissionGranted)

    fun configure(configuration: RecordingLaunchConfiguration, unitSystem: MeasurementUnitSystem = MeasurementUnitSystem.metric) {
        if (mutableState.value.startRequested) return
        presentationUnitSystem = unitSystem
        val isDebugHarvestLaunch = BuildConfig.DEBUG &&
            configuration.followedRoute?.id == HarvestRunSimulation.ROUTE_ID
        val restored=context.getSharedPreferences(LAUNCH_PREFERENCES,Context.MODE_PRIVATE).getString(LAUNCH_KEY,null)?.let{runCatching{launchJson.decodeFromString<RecordingLaunchConfiguration>(it)}.getOrNull()}
        // A direct or scheduled Group-event launch carries explicit activity choices; don't
        // restore a stale launch over its event id or consent context.
        val base = if (configuration.startImmediately || isDebugHarvestLaunch || configuration.activityEventId != null) configuration
            else restored?.takeIf { it.activityKind == configuration.activityKind } ?: configuration
        val autoPauseEnabled = context.getSharedPreferences(LAUNCH_PREFERENCES, Context.MODE_PRIVATE)
            .getBoolean(autoPauseKey(base.activityKind), AutoPauseDefaults.enabled(base.activityKind))
        val effective = base.copy(
            autoPauseEnabled = autoPauseEnabled,
            autoStopAtGoal = configuration.autoStopAtGoal ?: base.autoStopAtGoal,
            // This is a navigation-time decision from Today, not a persisted setup preference.
            startImmediately = configuration.startImmediately,
            simulatedRunEnabled = isDebugHarvestLaunch || (BuildConfig.DEBUG && base.simulatedRunEnabled),
            followedRoute = if (isDebugHarvestLaunch) {
                HarvestRunSimulation.route.copy(reverse = configuration.followedRoute.reverse)
            } else base.followedRoute,
        )
        mutableState.value = mutableState.value.copy(launch = effective)
        if (isDebugHarvestLaunch) analytics.record(AnalyticsEvent("activity_configuration_changed", mapOf(
            AnalyticsProperty.ChangeType to "run_simulation",
            AnalyticsProperty.SelectionType to "enabled",
        )))
        debugLog("configure source=${effective.entrySource} direct=${configuration.startImmediately} restoredApplied=${!configuration.startImmediately && restored?.activityKind == configuration.activityKind} requestedVoice=${configuration.voiceGuideEnabled} restoredVoice=${restored?.voiceGuideEnabled} effectiveVoice=${effective.voiceGuideEnabled}")
        if (!effective.startImmediately) analytics.record(AnalyticsEvent("activity_setup_viewed", mapOf(
                AnalyticsProperty.Source to effective.entrySource,
                AnalyticsProperty.ActivityType to effective.activityKind.name.lowercase(),
                AnalyticsProperty.GoalType to effective.goal.type.name.lowercase(),
                AnalyticsProperty.UnitSystem to unitSystem.name,
            )))
    }

    suspend fun beginCountdown() {
        if (preparingCountdown || mutableState.value.countdown != null || mutableState.value.startRequested || snapshot.value.status != RecordingStatus.IDLE) {
            debugLog("countdown_begin_skipped preparing=$preparingCountdown countdown=${mutableState.value.countdown != null} startRequested=${mutableState.value.startRequested} status=${snapshot.value.status}")
            return
        }
        preparingCountdown = true
        val voiceGuideEnabled = mutableState.value.launch.voiceGuideEnabled
        debugLog("countdown_begin voiceEnabled=$voiceGuideEnabled indoor=${mutableState.value.launch.indoor} source=${mutableState.value.launch.entrySource}")
        try {
            val voiceReady = if (voiceGuideEnabled) {
                runCatching { voice.prepare() }.onFailure {
                    logError("countdown_voice_prepare_exception type=${it.javaClass.simpleName}")
                }.getOrDefault(false)
            } else false
            debugLog("countdown_voice_ready enabled=$voiceGuideEnabled ready=$voiceReady")
            if (mutableState.value.startRequested || snapshot.value.status != RecordingStatus.IDLE) return
            mutableState.value = mutableState.value.copy(countdown = 3, countdownVoiceReady = voiceReady)
            if (voiceGuideEnabled) analytics.record(AnalyticsEvent(
                "activity_countdown_voice_prepared",
                mapOf(AnalyticsProperty.Result to if (voiceReady) "success" else "unavailable"),
            ))
        } finally {
            preparingCountdown = false
        }
    }

    fun updateCountdown(value: Int) { mutableState.value = mutableState.value.copy(countdown = value) }

    fun cancelCountdown() {
        voice.stopSpeech()
        clearCountdown()
    }

    fun clearCountdown() {
        mutableState.value = mutableState.value.copy(countdown = null, countdownVoiceReady = false)
    }

    fun start(accountId: String, permission: LocationPermissionState) {
        val launch = mutableState.value.launch
        didAutoPauseAtGoal = false
        mutableState.value = mutableState.value.copy(startRequested = true, countdown = null, countdownVoiceReady = false)
        context.getSharedPreferences(LAUNCH_PREFERENCES,Context.MODE_PRIVATE).edit().putString(LAUNCH_KEY,launchJson.encodeToString(launch)).apply()
        client.start(
            accountId,
            launch.activityKind,
            permission,
            newCommandId(),
            autoPauseEnabled = launch.autoPauseEnabled ?: AutoPauseDefaults.enabled(launch.activityKind),
            companionType = launch.companionType,
            simulatedRun = BuildConfig.DEBUG && launch.simulatedRunEnabled,
            simulatedRoute = launch.followedRoute,
        )
        analytics.record(AnalyticsEvent("activity_started", mapOf(
            AnalyticsProperty.Source to launch.entrySource,
            AnalyticsProperty.ActivityType to launch.activityKind.name.lowercase(),
            AnalyticsProperty.GoalType to launch.goal.type.name.lowercase(),
            AnalyticsProperty.Permission to permission.name.lowercase(),
            AnalyticsProperty.VoiceGuideEnabled to launch.voiceGuideEnabled,
            AnalyticsProperty.AutoPauseEnabled to (launch.autoPauseEnabled ?: AutoPauseDefaults.enabled(launch.activityKind)),
            AnalyticsProperty.AutoStopAtGoal to (launch.autoStopAtGoal ?: false),
            AnalyticsProperty.DogCompanionEnabled to (launch.companionType != null),
            AnalyticsProperty.UnitSystem to presentationUnitSystem.name,
        )))
    }

    fun recover(accountId: String, permission: LocationPermissionState) {
        if (recoveryAccountId == accountId) return
        recoveryAccountId = accountId
        client.recover(accountId, permission, newCommandId())
    }
    fun updatePermission(permission: LocationPermissionState) = client.updatePermission(permission)
    fun setAutoPauseEnabled(enabled: Boolean) {
        val current = mutableState.value.launch
        if (current.activityKind !in AUTO_PAUSE_ACTIVITY_KINDS) return
        context.getSharedPreferences(LAUNCH_PREFERENCES, Context.MODE_PRIVATE)
            .edit().putBoolean(autoPauseKey(current.activityKind), enabled).apply()
        mutableState.value = mutableState.value.copy(launch = current.copy(autoPauseEnabled = enabled))
        analytics.record(AnalyticsEvent("activity_configuration_changed", mapOf(
            AnalyticsProperty.ChangeType to "auto_pause",
            AnalyticsProperty.SelectionType to if (enabled) "enabled" else "disabled",
            AnalyticsProperty.ActivityType to current.activityKind.name.lowercase(),
        )))
    }
    fun pause() = client.pause(newCommandId())
    fun resume() = client.resume(newCommandId())
    fun requestFinish() { mutableState.value = mutableState.value.copy(showFinishConfirmation = true) }
    fun pauseAtGoal(distanceGoalMeters: Double?) {
        if (didAutoPauseAtGoal || mutableState.value.launch.autoStopAtGoal != true || snapshot.value.status != RecordingStatus.ACTIVE) return
        didAutoPauseAtGoal = true
        client.pauseAtGoal(distanceGoalMeters, newCommandId())
    }
    fun cancelFinish() { mutableState.value = mutableState.value.copy(showFinishConfirmation = false) }
    fun finish() {
        mutableState.value = mutableState.value.copy(showFinishConfirmation = false)
        mutableState.value = mutableState.value.copy(launch = mutableState.value.launch.copy(simulatedRunEnabled = false))
        client.finish(newCommandId())
        val current = snapshot.value
        analytics.record(AnalyticsEvent("activity_finished", mapOf(
            AnalyticsProperty.ActivityType to current.activityKind.name.lowercase(),
            AnalyticsProperty.DurationBucket to durationBucket(current.elapsedSeconds),
            AnalyticsProperty.DistanceBucket to distanceBucket(current.distanceMeters),
        )))
    }
    fun requestDiscard() {
        mutableState.value = mutableState.value.copy(showDiscardConfirmation = true)
        val current = snapshot.value
        analytics.record(AnalyticsEvent("activity_discard_prompted", mapOf(
            AnalyticsProperty.DurationBucket to durationBucket(current.elapsedSeconds),
            AnalyticsProperty.DistanceBucket to distanceBucket(current.distanceMeters),
            AnalyticsProperty.PhotoCountBucket to photoCountBucket(mutableState.value.photoPaths.size),
        )))
    }
    fun cancelDiscard() { mutableState.value = mutableState.value.copy(showDiscardConfirmation = false) }
    suspend fun discard(): Boolean {
        if (mutableState.value.discarding) return false
        mutableState.value = mutableState.value.copy(showDiscardConfirmation = false, discarding = true)
        client.discard(newCommandId())
        val discarded = withTimeoutOrNull(5_000) {
            snapshot.first { it.status == RecordingStatus.IDLE }
        } != null
        if (!discarded) {
            mutableState.value = mutableState.value.copy(discarding = false, showDiscardConfirmation = true)
            return false
        }
        val finishedSnapshot = snapshot.value
        analytics.record(AnalyticsEvent("activity_discarded", mapOf(
            AnalyticsProperty.DurationBucket to durationBucket(finishedSnapshot.elapsedSeconds),
            AnalyticsProperty.DistanceBucket to distanceBucket(finishedSnapshot.distanceMeters),
            AnalyticsProperty.PhotoCountBucket to photoCountBucket(mutableState.value.photoPaths.size),
        )))
        mutableState.value = RecordingUiState(launch = mutableState.value.launch)
        clearLaunch()
        return true
    }

    fun speakCountdown(value: Int) = voice.speakCountdown(value)
    fun speakGo() = voice.speakGo()
    fun setMode(mode: RecordingSurfaceMode) {
        mutableState.value = mutableState.value.copy(mode = mode)
        analytics.record(AnalyticsEvent("activity_surface_changed", mapOf(AnalyticsProperty.Result to mode.name.lowercase())))
    }
    fun setReflection(choice: ReflectionChoice) {
        mutableState.value = mutableState.value.copy(
            reflection = choice,
            continuationCapacity = if (choice == ReflectionChoice.EASY) mutableState.value.continuationCapacity else null,
        )
    }
    fun setContinuationCapacity(capacity: ContinuationCapacity) { mutableState.value = mutableState.value.copy(continuationCapacity = capacity) }
    fun setPhotoPaths(paths: List<String>) {
        mutableState.value = mutableState.value.copy(photoPaths = paths, importedPhotoPaths = mutableState.value.importedPhotoPaths.intersect(paths.toSet()), pendingMedia = false)
    }
    fun addFinishPhoto(path: String, sourceType: String = "finish_review", isImported: Boolean = false) {
        val current = mutableState.value
        mutableState.value = current.copy(
            photoPaths = current.photoPaths + path,
            importedPhotoPaths = if (isImported) current.importedPhotoPaths + path else current.importedPhotoPaths,
            pendingMedia = false,
        )
        analytics.record(AnalyticsEvent("photo_captured", mapOf(
            AnalyticsProperty.SourceType to sourceType,
            AnalyticsProperty.LocationAttached to (snapshot.value.latestLocation != null),
        )))
    }
    fun addImportedFinishPhotos(paths: List<String>) {
        if (paths.isEmpty()) return
        val current = mutableState.value
        mutableState.value = current.copy(
            photoPaths = current.photoPaths + paths,
            importedPhotoPaths = current.importedPhotoPaths + paths,
            pendingMedia = false,
        )
        val locationAttached = paths.any { path -> finishPhotoMetadata(File(path), snapshot.value).latitude != null }
        analytics.record(AnalyticsEvent("photo_captured", mapOf(
            AnalyticsProperty.SourceType to "finish_photo_library",
            AnalyticsProperty.LocationAttached to locationAttached,
        )))
    }
    fun trackPhotoRemoved() = analytics.record(AnalyticsEvent("photo_removed", mapOf(AnalyticsProperty.SourceType to "finish_review")))
    fun trackPhotoPreviewed() = analytics.record(AnalyticsEvent("photo_previewed", mapOf(AnalyticsProperty.SourceType to "finish_review")))
    fun trackPhotoReordered() = analytics.record(AnalyticsEvent("photo_reordered", mapOf(AnalyticsProperty.SourceType to "finish_review")))
    fun setPendingMedia(pending:Boolean){mutableState.value=mutableState.value.copy(pendingMedia=pending)}
    fun trackPhotoAttempt(sourceType: String = "finish_review") = analytics.record(AnalyticsEvent("photo_capture_attempted", mapOf(
        AnalyticsProperty.SourceType to sourceType,
    )))
    fun trackPhotoAlbumPermissionDenied() = analytics.record(AnalyticsEvent(
        "photo_album_export_completed",
        mapOf(
            AnalyticsProperty.Result to "permission_denied",
            AnalyticsProperty.SourceType to "automatic",
            AnalyticsProperty.CountBucket to "one",
        ),
    ))
    fun trackSaveIneligible() {
        val current = snapshot.value
        analytics.record(AnalyticsEvent("activity_save_ineligible_shown", mapOf(
            AnalyticsProperty.ActivityType to current.activityKind.name.lowercase(),
            AnalyticsProperty.DurationBucket to durationBucket(current.elapsedSeconds),
            AnalyticsProperty.DistanceBucket to distanceBucket(current.distanceMeters),
        )))
    }
    fun trackStretchEvent(name: String, kind: ActivityKind, routineId: String?, result: String?) {
        val routine = PostWorkoutStretchCatalog.routines(kind).orEmpty().firstOrNull { it.id == routineId } ?: return
        val properties = mutableMapOf<AnalyticsProperty, Any>(
            AnalyticsProperty.ActivityType to kind.name.lowercase(),
            AnalyticsProperty.RoutineId to routine.id,
        )
        result?.let { properties[AnalyticsProperty.Result] = it }
        if (name.startsWith("post_workout_stretch_")) analytics.record(AnalyticsEvent(name, properties))
    }

    fun trackPostSaveCelebrationExposed() {
        analytics.record(AnalyticsEvent("feature_exposed", mapOf(
            AnalyticsProperty.Feature to "activity_post_save_celebration",
        )))
    }
    fun trackDashboardChanged(expanded: Boolean) = analytics.record(AnalyticsEvent(
        "activity_dashboard_changed",
        mapOf(AnalyticsProperty.Result to if (expanded) "expanded" else "compact"),
    ))
    fun newCommandId(): String = UUID.randomUUID().toString()
    fun markSaved(){client.markSaved(newCommandId());clearLaunch()}
    fun configureSimulatedRun(enabled: Boolean) {
        if (!BuildConfig.DEBUG || snapshot.value.status != RecordingStatus.IDLE) return
        val current = mutableState.value.launch
        if (enabled) routeBeforeSimulation = current.followedRoute
        val route = if (enabled) HarvestRunSimulation.route else if (current.followedRoute?.id == HarvestRunSimulation.ROUTE_ID) routeBeforeSimulation else current.followedRoute
        mutableState.value = mutableState.value.copy(
            launch = current.copy(
                activityKind = ActivityKind.RUNNING,
                title = null,
                goal = RecordingGoal(),
                workoutSteps = emptyList(),
                suggestionId = null,
                plannedWorkoutId = null,
                standaloneWorkoutId = null,
                standaloneWorkoutCatalogVersion = null,
                workoutDetail = null,
                workoutGuideline = null,
                privateTrainingSignal = null,
                workoutPhase = null,
                workoutTargetPaceSecondsPerKilometer = null,
                workoutFasterToleranceSeconds = null,
                workoutSlowerToleranceSeconds = null,
                workoutRecognizesTargetLock = false,
                raceIntent = null,
                simulatedRunEnabled = enabled,
                followedRoute = route,
                indoor = false,
            ),
        )
        analytics.record(AnalyticsEvent("activity_configuration_changed", mapOf(
            AnalyticsProperty.ChangeType to "run_simulation",
            AnalyticsProperty.SelectionType to if (enabled) "enabled" else "disabled",
        )))
        if (!enabled) routeBeforeSimulation = null
    }
    fun setRunSimulationTimeRate(rate: Int) {
        if (!BuildConfig.DEBUG) return
        client.setRunSimulationTimeRate(rate)
        trackSimulationControl("time_rate", "rate_${rate}x")
    }
    fun adjustRunSimulationSpeed(deltaKilometersPerHour: Double) {
        if (!BuildConfig.DEBUG) return
        client.adjustRunSimulationSpeed(deltaKilometersPerHour)
        val speed = snapshot.value.runSimulation?.speedKilometersPerHour ?: 10.0
        trackSimulationControl("speed", HarvestRunSimulation.speedBucket((speed + deltaKilometersPerHour).coerceIn(4.0, 24.0)))
    }
    fun toggleRunSimulationClock() {
        if (!BuildConfig.DEBUG) return
        val wasRunning = snapshot.value.runSimulation?.isClockRunning == true
        client.toggleRunSimulationClock()
        trackSimulationControl("clock", if (wasRunning) "paused" else "playing")
    }
    fun advanceRunSimulation(seconds: Int) {
        if (!BuildConfig.DEBUG) return
        client.advanceRunSimulation(seconds)
        trackSimulationControl("time_advance", if (seconds == 60) "1m" else "5m")
    }
    private fun trackSimulationControl(control: String, selection: String) = analytics.record(AnalyticsEvent(
        "activity_simulation_control_used",
        mapOf(AnalyticsProperty.Control to control, AnalyticsProperty.SelectionType to selection),
    ))
    private fun clearLaunch(){context.getSharedPreferences(LAUNCH_PREFERENCES,Context.MODE_PRIVATE).edit().remove(LAUNCH_KEY).apply()}

    private fun companionTitleRes(kind: ActivityKind): Int = when (kind) {
        ActivityKind.WALKING -> R.string.recording_companion_title_walk
        ActivityKind.HIKING -> R.string.recording_companion_title_hike
        ActivityKind.CYCLING -> R.string.recording_companion_title_ride
        else -> R.string.recording_companion_title_run
    }

    /** Freestyle saves earn a localized Dog run/walk/hike/ride title; planned and curated keep theirs. */
    private fun savedActivityTitle(launch: RecordingLaunchConfiguration): String = launch.title
        ?: launch.companionType?.let { context.getString(companionTitleRes(launch.activityKind)) }
        ?: context.getString(R.string.recording_default_activity_title)

    /** Returns only after the activity and its outbox operation are committed to Room. */
    suspend fun saveFinished(
        review: RecordedActivityReview,
        savePhotoToAlbum: Boolean,
        weightKilograms: Double? = null,
    ): RecordedActivitySaveResult {
        if (mutableState.value.saving) return RecordedActivitySaveResult(saved = false)
        mutableState.value = mutableState.value.copy(saving = true)
        val sourcePhotos = review.photoPaths.mapNotNull { it.let(::File).takeIf(File::isFile) }
        val persistedPhotoPaths = mutableListOf<String>()
        return runCatching {
            val snapshot = review.snapshot
            val accountId = requireNotNull(snapshot.accountId)
            val sessionId = requireNotNull(snapshot.sessionId)
            val startedAt = requireNotNull(snapshot.startedAtEpochMilliseconds)
            val savedAt = Instant.now()
            val base = RecordedActivityFactory.create(
                RecordedActivityDraft(
                    sessionId = sessionId,
                    accountId = accountId,
                    type = snapshot.activityKind.toActivityType(),
                    title = savedActivityTitle(mutableState.value.launch),
                    startedAtEpochMs = startedAt,
                    endedAtEpochMs = snapshot.recordedAtEpochMilliseconds,
                    durationSecs = snapshot.elapsedSeconds.coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
                    distanceM = snapshot.distanceMeters,
                    elevationGainM = snapshot.elevationGainMeters,
                    energyKilocalories = WorkoutCalorieEstimator.estimate(
                        activityType = snapshot.activityKind.toActivityType(),
                        distanceMeters = snapshot.distanceMeters,
                        durationSeconds = snapshot.elapsedSeconds.coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
                        elevationGainMeters = snapshot.elevationGainMeters,
                        weightKilograms = weightKilograms,
                    ).kilocalories,
                    track = snapshot.track.mapIndexed { index, point ->
                        RecordedTrackPointDraft(
                            timestampEpochMs = point.capturedAtEpochMilliseconds,
                            latitude = point.latitude,
                            longitude = point.longitude,
                            altitude = point.altitudeMeters,
                            verticalAccuracy = point.verticalAccuracyMeters,
                        startsNewSegment = index == 0 || index in snapshot.trackSegmentStartIndices,
                        )
                    },
                    companionType = mutableState.value.launch.companionType,
                ),
                savedAt,
            ).copy(activityEventId = mutableState.value.launch.activityEventId)
            val photos = sourcePhotos.map { file ->
                val bytes = file.readBytes()
                val persistedPhotoPath = media.write(accountId, sessionId, bytes)
                persistedPhotoPaths += persistedPhotoPath
                val photoMetadata = finishPhotoMetadata(file, snapshot)
                ActivityPhoto(
                    id = UUID.randomUUID().toString(),
                    takenAt = photoMetadata.takenAt.toString(),
                    paceAtShot = photoMetadata.pace,
                    heartRateAtShot = null,
                    distanceAtShotM = photoMetadata.distanceMeters,
                    latitude = photoMetadata.latitude,
                    longitude = photoMetadata.longitude,
                    captureContext = photoMetadata.captureContext,
                    localRelativePath = persistedPhotoPath,
                    byteSize = bytes.size.toLong(),
                    sha256 = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) },
                )
            }
            val shortSession = snapshot.elapsedSeconds <= 600
            val reflectionTitle = context.getString(if (shortSession) R.string.recording_reflection_promise_title else R.string.recording_nice_work)
            val reflectionBody = context.getString(if (shortSession) R.string.recording_reflection_promise_body else R.string.recording_reflection_body)
            activities.save(base.copy(
                title = savedActivityTitle(mutableState.value.launch),
                companionType = mutableState.value.launch.companionType,
                gearJson=mutableState.value.launch.gearId?.let { "{\"id\":\"$it\"}" },
                indoorJson="{\"indoor\":${mutableState.value.launch.indoor}}",
                followedRouteId=mutableState.value.launch.followedRoute?.id,
                followedRouteCompleted=mutableState.value.launch.followedRoute?.let{route->snapshot.latestLocation?.let{last->route.points.lastOrNull()?.let{end->distanceMeters(last.latitude,last.longitude,end.latitude,end.longitude)<=50}}}==true,
                reflection = ActivityReflection(
                    title = reflectionTitle,
                    body = reflectionBody,
                    highlight = context.getString(R.string.recording_reflection_highlight, formatDuration(snapshot.elapsedSeconds)),
                    progressNote = mutableState.value.launch.workoutGuideline?.takeIf(String::isNotBlank),
                ),
                photos = photos,
            ))
            syncScheduler.schedule(accountId)
            val photoAlbumExport = if (savePhotoToAlbum && sourcePhotos.isNotEmpty()) {
                runCatching {
                    photoAlbumExporter.export(sourcePhotos.first(), sessionId, savedAt.toEpochMilli())
                }.getOrDefault(ActivityPhotoAlbumExportResult.FAILED).also { result ->
                    analytics.record(AnalyticsEvent("photo_album_export_completed", mapOf(
                        AnalyticsProperty.Result to when (result) {
                            ActivityPhotoAlbumExportResult.SAVED -> "success"
                            ActivityPhotoAlbumExportResult.ALREADY_SAVED -> "already_saved"
                            ActivityPhotoAlbumExportResult.PERMISSION_DENIED -> "permission_denied"
                            ActivityPhotoAlbumExportResult.FAILED -> "failure"
                        },
                        AnalyticsProperty.SourceType to "automatic",
                        AnalyticsProperty.CountBucket to sourcePhotos.size.coerceAtMost(10).toString(),
                    )))
                }
            } else {
                null
            }
            sourcePhotos.forEach(File::delete)
            if (review.reflection != null) viewModelScope.launch { submitWorkoutFeedback(review) }
            analytics.record(AnalyticsEvent("activity_saved_locally", mapOf(
                AnalyticsProperty.Result to "success",
                AnalyticsProperty.ActivityType to snapshot.activityKind.name.lowercase(),
                AnalyticsProperty.DogCompanionEnabled to (mutableState.value.launch.companionType != null),
            )))
            val currentLaunch = mutableState.value.launch
            analytics.record(AnalyticsEvent("activity_saved", mapOf(
                AnalyticsProperty.ActivityType to snapshot.activityKind.name.lowercase(),
                AnalyticsProperty.GoalType to currentLaunch.goal.type.name.lowercase(),
                AnalyticsProperty.DurationBucket to durationBucket(snapshot.elapsedSeconds),
                AnalyticsProperty.DistanceBucket to distanceBucket(snapshot.distanceMeters),
                AnalyticsProperty.PhotoCountBucket to photoCountBucket(review.photoPaths.size),
                AnalyticsProperty.RouteSelected to (currentLaunch.followedRoute != null),
                AnalyticsProperty.ShoeSelected to (currentLaunch.gearId != null),
                AnalyticsProperty.Indoor to currentLaunch.indoor,
                AnalyticsProperty.DogCompanionEnabled to (currentLaunch.companionType != null),
            )))
            RecordedActivitySaveResult(saved = true, photoAlbumExport = photoAlbumExport)
        }.getOrElse {
            persistedPhotoPaths.forEach(media::delete)
            analytics.record(AnalyticsEvent("activity_saved_locally", mapOf(AnalyticsProperty.Result to "failure")))
            RecordedActivitySaveResult(saved = false)
        }.also { mutableState.value = mutableState.value.copy(saving = false) }
    }

    private suspend fun submitWorkoutFeedback(review: RecordedActivityReview) {
        val effortChoice = review.reflection ?: return
        val workoutId = mutableState.value.launch.plannedWorkoutId
            ?: mutableState.value.launch.suggestionId
            ?: mutableState.value.launch.standaloneWorkoutId
            ?: "freestyle-run"
        val token = accessTokens.validAccessToken()?.let { "Bearer $it" } ?: return
        val effort = when (effortChoice) {
            ReflectionChoice.EASY -> "easy"
            ReflectionChoice.ABOUT_RIGHT -> "aboutRight"
            ReflectionChoice.TOO_HARD -> "tooHard"
        }
        val continuationCapacity = review.continuationCapacity?.let {
            when (it) {
                ContinuationCapacity.NONE -> "none"
                ContinuationCapacity.TEN_MINUTES -> "tenMinutes"
                ContinuationCapacity.MUCH_LONGER -> "muchLonger"
            }
        }
        runCatching {
            planningApi.feedback(
                token,
                workoutId,
                WorkoutFeedbackRequest(
                    idempotencyKey = UUID.randomUUID().toString(),
                    workoutId = workoutId,
                    recordedAt = Instant.now().toString(),
                    effort = effort,
                    continuationCapacity = continuationCapacity,
                ),
            ).also { check(it.isSuccessful) }
        }.onSuccess {
            analytics.record(AnalyticsEvent("workout_feedback_submitted", mapOf(AnalyticsProperty.Result to "success")))
        }.onFailure {
            analytics.record(AnalyticsEvent("workout_feedback_submitted", mapOf(AnalyticsProperty.Result to "failure")))
        }
    }

    private data class FinishPhotoMetadata(
        val takenAt: Instant,
        val pace: Double?,
        val distanceMeters: Double,
        val latitude: Double?,
        val longitude: Double?,
        val captureContext: String,
    )

    private fun finishPhotoMetadata(file: File, snapshot: RecordingSnapshot): FinishPhotoMetadata {
        val exif = runCatching { ExifInterface(file) }.getOrNull()
        val exifTime = exif?.getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL)
            ?: exif?.getAttribute(ExifInterface.TAG_DATETIME_DIGITIZED)
            ?: exif?.getAttribute(ExifInterface.TAG_DATETIME)
        val parsedDate = exifTime?.let { raw ->
            runCatching {
                val localDate = SimpleDateFormat("yyyy:MM:dd HH:mm:ss", Locale.US).parse(raw) ?: return@runCatching null
                val offset = exif?.getAttribute(ExifInterface.TAG_OFFSET_TIME_ORIGINAL)
                    ?: exif?.getAttribute(ExifInterface.TAG_OFFSET_TIME_DIGITIZED)
                    ?: exif?.getAttribute(ExifInterface.TAG_OFFSET_TIME)
                offset?.let {
                    java.time.LocalDateTime.ofInstant(localDate.toInstant(), java.time.ZoneId.systemDefault())
                        .atOffset(java.time.ZoneOffset.of(it)).toInstant()
                }
                    ?: localDate.toInstant()
            }.getOrNull()
        }
        val takenAt = parsedDate ?: Instant.now()
        val samples = snapshot.track
        val start = snapshot.startedAtEpochMilliseconds?.let(Instant::ofEpochMilli) ?: takenAt
        val end = Instant.ofEpochMilli(snapshot.recordedAtEpochMilliseconds)
        val nearest = samples.minByOrNull { kotlin.math.abs(it.capturedAtEpochMilliseconds - takenAt.toEpochMilli()) }
        val routeCoordinate = nearest?.let { it.latitude to it.longitude }
        val exifCoordinate = FloatArray(2).let { out ->
            if (exif?.getLatLong(out) == true) out[0].toDouble() to out[1].toDouble() else null
        }
        val embeddedCoordinate = exifCoordinate?.takeIf { candidate ->
            routeCoordinate != null && distanceMeters(candidate.first, candidate.second, routeCoordinate.first, routeCoordinate.second) <= 500.0
        }
        // Camera photos often have no GPS EXIF. Their capture time still identifies a
        // route sample, including the first sample for a pre-run photo.
        val attachedCoordinate = embeddedCoordinate ?: routeCoordinate
        val captureContext = when {
            takenAt.isBefore(start) -> "pre_activity"
            !takenAt.isBefore(end) -> "paused"
            else -> "active"
        }
        val cumulativeDistances = DoubleArray(samples.size)
        for (index in 1 until samples.size) {
            cumulativeDistances[index] = cumulativeDistances[index - 1]
            if (index !in snapshot.trackSegmentStartIndices) {
                val before = samples[index - 1]
                val after = samples[index]
                cumulativeDistances[index] += distanceMeters(before.latitude, before.longitude, after.latitude, after.longitude)
            }
        }
        val distanceAtShot = when {
            samples.isEmpty() -> 0.0
            takenAt.toEpochMilli() <= samples.first().capturedAtEpochMilliseconds -> cumulativeDistances.first()
            takenAt.toEpochMilli() >= samples.last().capturedAtEpochMilliseconds -> cumulativeDistances.last()
            else -> {
                val upper = samples.indexOfFirst { it.capturedAtEpochMilliseconds >= takenAt.toEpochMilli() }.coerceAtLeast(1)
                val before = samples[upper - 1]
                val after = samples[upper]
                val fraction = ((takenAt.toEpochMilli() - before.capturedAtEpochMilliseconds).toDouble() /
                    (after.capturedAtEpochMilliseconds - before.capturedAtEpochMilliseconds).coerceAtLeast(1)).coerceIn(0.0, 1.0)
                cumulativeDistances[upper - 1] + (cumulativeDistances[upper] - cumulativeDistances[upper - 1]) * fraction
            }
        }
        val averagePace = snapshot.distanceMeters.takeIf { it > 0.0 }
            ?.let { snapshot.elapsedSeconds / (it / 1_000.0) }
        return FinishPhotoMetadata(takenAt, averagePace, distanceAtShot, attachedCoordinate?.first, attachedCoordinate?.second, captureContext)
    }

    private fun distanceMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val radius = 6_371_000.0
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val a = kotlin.math.sin(dLat / 2).let { it * it } + kotlin.math.cos(Math.toRadians(lat1)) * kotlin.math.cos(Math.toRadians(lat2)) * kotlin.math.sin(dLon / 2).let { it * it }
        return radius * 2 * kotlin.math.atan2(kotlin.math.sqrt(a), kotlin.math.sqrt(1 - a))
    }

    override fun onCleared() {
        voice.close()
        client.close()
        super.onCleared()
    }
    private companion object {
        const val TAG = "RecordingStart"
        val AUTO_PAUSE_ACTIVITY_KINDS = setOf(ActivityKind.RUNNING, ActivityKind.CYCLING, ActivityKind.WALKING, ActivityKind.HIKING)
        fun autoPauseKey(activityKind: ActivityKind) = "auto_pause_enabled_${activityKind.name.lowercase()}"
        const val LAUNCH_PREFERENCES = "recording_launch"
        const val LAUNCH_KEY = "active"
    }

    private fun debugLog(message: String) {
        if (BuildConfig.DEBUG) Log.d(TAG, message)
    }

    private fun logError(message: String) {
        if (BuildConfig.DEBUG) Log.e(TAG, message)
    }
}

private fun durationBucket(seconds: Long) = when {
    seconds < 300 -> "under_5m"
    seconds < 1_800 -> "5_29m"
    seconds < 3_600 -> "30_59m"
    else -> "60m_plus"
}

private fun distanceBucket(meters: Double) = when {
    meters < 500 -> "under_500m"
    meters < 5_000 -> "500m_4k"
    meters < 10_000 -> "5k_9k"
    else -> "10k_plus"
}

private fun photoCountBucket(count: Int) = when (count.coerceAtLeast(0)) {
    0 -> "0"
    1 -> "1"
    in 2..3 -> "2_3"
    in 4..7 -> "4_7"
    else -> "8_plus"
}

private fun distanceMeters(aLat:Double,aLon:Double,bLat:Double,bLon:Double):Double{val p1=Math.toRadians(aLat);val p2=Math.toRadians(bLat);val dp=p2-p1;val dl=Math.toRadians(bLon-aLon);val h=kotlin.math.sin(dp/2)*kotlin.math.sin(dp/2)+kotlin.math.cos(p1)*kotlin.math.cos(p2)*kotlin.math.sin(dl/2)*kotlin.math.sin(dl/2);return 6371000*2*kotlin.math.atan2(kotlin.math.sqrt(h),kotlin.math.sqrt(1-h))}

private fun ActivityKind.toActivityType() = ActivityType.valueOf(name.lowercase())
