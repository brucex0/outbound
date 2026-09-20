package com.plainstride.outbound.feature.recording

import android.content.Context
import java.io.File
import java.security.MessageDigest
import java.time.Instant
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import java.util.UUID
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.stateIn
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
import kotlinx.serialization.json.Json
import kotlinx.coroutines.withTimeoutOrNull

data class RecordingUiState(
    val launch: RecordingLaunchConfiguration = RecordingLaunchConfiguration(),
    val mode: RecordingSurfaceMode = RecordingSurfaceMode.MAP,
    val countdown: Int? = null,
    val countdownVoiceReady: Boolean = false,
    val reflection: ReflectionChoice? = null,
    val photoPath: String? = null,
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
    private var presentationUnitSystem = MeasurementUnitSystem.metric
    val voiceListening: StateFlow<Boolean> = voice.listening
    init { voice.observe(viewModelScope, snapshot = { snapshot.value }, ::pause, ::resume, ::requestFinish) }
    fun listen(permissionGranted: Boolean) = voice.listen(permissionGranted)

    fun configure(configuration: RecordingLaunchConfiguration, unitSystem: MeasurementUnitSystem = MeasurementUnitSystem.metric) {
        if (mutableState.value.startRequested) return
        presentationUnitSystem = unitSystem
        val restored=context.getSharedPreferences(LAUNCH_PREFERENCES,Context.MODE_PRIVATE).getString(LAUNCH_KEY,null)?.let{runCatching{launchJson.decodeFromString<RecordingLaunchConfiguration>(it)}.getOrNull()}
        val effective=restored?:configuration
        mutableState.value = mutableState.value.copy(launch = effective)
        analytics.record(AnalyticsEvent("activity_setup_viewed", mapOf(
            AnalyticsProperty.Source to effective.entrySource,
            AnalyticsProperty.ActivityType to effective.activityKind.name.lowercase(),
            AnalyticsProperty.GoalType to effective.goal.type.name.lowercase(),
            AnalyticsProperty.UnitSystem to unitSystem.name,
        )))
    }

    suspend fun beginCountdown() {
        if (preparingCountdown || mutableState.value.countdown != null || mutableState.value.startRequested || snapshot.value.status != RecordingStatus.IDLE) return
        preparingCountdown = true
        val voiceGuideEnabled = mutableState.value.launch.voiceGuideEnabled
        try {
            val voiceReady = voiceGuideEnabled && voice.prepare()
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
        mutableState.value = mutableState.value.copy(startRequested = true, countdown = null, countdownVoiceReady = false)
        context.getSharedPreferences(LAUNCH_PREFERENCES,Context.MODE_PRIVATE).edit().putString(LAUNCH_KEY,launchJson.encodeToString(launch)).apply()
        client.start(accountId, launch.activityKind, permission, newCommandId(), launch.companionType)
        analytics.record(AnalyticsEvent("activity_started", mapOf(
            AnalyticsProperty.Source to launch.entrySource,
            AnalyticsProperty.ActivityType to launch.activityKind.name.lowercase(),
            AnalyticsProperty.GoalType to launch.goal.type.name.lowercase(),
            AnalyticsProperty.Permission to permission.name.lowercase(),
            AnalyticsProperty.VoiceGuideEnabled to launch.voiceGuideEnabled,
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
    fun pause() = client.pause(newCommandId())
    fun resume() = client.resume(newCommandId())
    fun requestFinish() { mutableState.value = mutableState.value.copy(showFinishConfirmation = true) }
    fun cancelFinish() { mutableState.value = mutableState.value.copy(showFinishConfirmation = false) }
    fun finish() {
        mutableState.value = mutableState.value.copy(showFinishConfirmation = false)
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
        analytics.record(AnalyticsEvent("activity_discard_prompted"))
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
        mutableState.value = RecordingUiState(launch = mutableState.value.launch)
        clearLaunch()
        analytics.record(AnalyticsEvent("activity_discarded"))
        return true
    }

    fun speakCountdown(value: Int) = voice.speakCountdown(value)
    fun speakGo() = voice.speakGo()
    fun setMode(mode: RecordingSurfaceMode) {
        mutableState.value = mutableState.value.copy(mode = mode)
        analytics.record(AnalyticsEvent("activity_surface_changed", mapOf(AnalyticsProperty.Result to mode.name.lowercase())))
    }
    fun setReflection(choice: ReflectionChoice) { mutableState.value = mutableState.value.copy(reflection = choice) }
    fun setPhotoPath(path: String?) {
        mutableState.value = mutableState.value.copy(photoPath = path,pendingMedia=false)
        analytics.record(AnalyticsEvent(if (path == null) "activity_photo_deleted" else "activity_photo_captured", mapOf(
            AnalyticsProperty.Result to "success",
        )))
    }
    fun setPendingMedia(pending:Boolean){mutableState.value=mutableState.value.copy(pendingMedia=pending)}
    fun trackPhotoAttempt() = analytics.record(AnalyticsEvent("activity_photo_capture_attempted", mapOf(
        AnalyticsProperty.Source to "recording",
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
    fun trackStretchEvent(name: String, kind: ActivityKind, result: String?) { val routine=PostWorkoutStretchCatalog.routine(kind)?:return; val p=mutableMapOf<AnalyticsProperty,Any>(AnalyticsProperty.ActivityType to kind.name.lowercase(),AnalyticsProperty.RoutineId to routine.id); result?.let{p[AnalyticsProperty.Result]=it}; if(name.startsWith("post_workout_stretch_")) analytics.record(AnalyticsEvent(name,p)) }
    fun trackDashboardChanged(expanded: Boolean) = analytics.record(AnalyticsEvent(
        "activity_dashboard_changed",
        mapOf(AnalyticsProperty.Result to if (expanded) "expanded" else "compact"),
    ))
    fun newCommandId(): String = UUID.randomUUID().toString()
    fun markSaved(){client.markSaved(newCommandId());clearLaunch()}
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
    ): RecordedActivitySaveResult {
        if (mutableState.value.saving) return RecordedActivitySaveResult(saved = false)
        mutableState.value = mutableState.value.copy(saving = true)
        val sourcePhoto = review.photoPath?.let(::File)?.takeIf(File::isFile)
        var persistedPhotoPath: String? = null
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
                    track = snapshot.track.mapIndexed { index, point ->
                        RecordedTrackPointDraft(
                            timestampEpochMs = point.capturedAtEpochMilliseconds,
                            latitude = point.latitude,
                            longitude = point.longitude,
                            altitude = point.altitudeMeters,
                            verticalAccuracy = point.verticalAccuracyMeters,
                            startsNewSegment = index == 0,
                        )
                    },
                    companionType = mutableState.value.launch.companionType,
                ),
                savedAt,
            )
            val photo = sourcePhoto?.let { file ->
                val bytes = file.readBytes()
                persistedPhotoPath = media.write(accountId, sessionId, bytes)
                ActivityPhoto(
                    id = UUID.randomUUID().toString(),
                    takenAt = savedAt.toString(),
                    captureContext = "review",
                    localRelativePath = persistedPhotoPath,
                    byteSize = bytes.size.toLong(),
                    sha256 = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) },
                )
            }
            val reflectionLabel = context.getString(when (review.reflection) {
                ReflectionChoice.STRONG -> R.string.recording_reflection_strong
                ReflectionChoice.STEADY -> R.string.recording_reflection_steady
                ReflectionChoice.TOUGH -> R.string.recording_reflection_tough
            })
            activities.save(base.copy(
                title = savedActivityTitle(mutableState.value.launch),
                companionType = mutableState.value.launch.companionType,
                gearJson=mutableState.value.launch.gearId?.let { "{\"id\":\"$it\"}" },
                indoorJson="{\"indoor\":${mutableState.value.launch.indoor}}",
                followedRouteId=mutableState.value.launch.followedRoute?.id,
                followedRouteCompleted=mutableState.value.launch.followedRoute?.let{route->snapshot.latestLocation?.let{last->route.points.lastOrNull()?.let{end->distanceMeters(last.latitude,last.longitude,end.latitude,end.longitude)<=50}}}==true,
                reflection = ActivityReflection(
                    title = context.getString(R.string.recording_reflection_title),
                    body = reflectionLabel,
                    highlight = reflectionLabel,
                ),
                photos = listOfNotNull(photo),
            ))
            syncScheduler.schedule(accountId)
            val photoAlbumExport = if (savePhotoToAlbum && sourcePhoto != null) {
                runCatching {
                    photoAlbumExporter.export(sourcePhoto, sessionId, savedAt.toEpochMilli())
                }.getOrDefault(ActivityPhotoAlbumExportResult.FAILED).also { result ->
                    analytics.record(AnalyticsEvent("photo_album_export_completed", mapOf(
                        AnalyticsProperty.Result to when (result) {
                            ActivityPhotoAlbumExportResult.SAVED -> "success"
                            ActivityPhotoAlbumExportResult.ALREADY_SAVED -> "already_saved"
                            ActivityPhotoAlbumExportResult.PERMISSION_DENIED -> "permission_denied"
                            ActivityPhotoAlbumExportResult.FAILED -> "failure"
                        },
                        AnalyticsProperty.SourceType to "automatic",
                        AnalyticsProperty.CountBucket to "one",
                    )))
                }
            } else {
                null
            }
            sourcePhoto?.delete()
            analytics.record(AnalyticsEvent("activity_saved_locally", mapOf(
                AnalyticsProperty.Result to "success",
                AnalyticsProperty.ActivityType to snapshot.activityKind.name.lowercase(),
                AnalyticsProperty.DogCompanionEnabled to (mutableState.value.launch.companionType != null),
            )))
            RecordedActivitySaveResult(saved = true, photoAlbumExport = photoAlbumExport)
        }.getOrElse {
            persistedPhotoPath?.let(media::delete)
            analytics.record(AnalyticsEvent("activity_saved_locally", mapOf(AnalyticsProperty.Result to "failure")))
            RecordedActivitySaveResult(saved = false)
        }.also { mutableState.value = mutableState.value.copy(saving = false) }
    }

    override fun onCleared() {
        voice.close()
        client.close()
        super.onCleared()
    }
    private companion object{const val LAUNCH_PREFERENCES="recording_launch";const val LAUNCH_KEY="active"}
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

private fun distanceMeters(aLat:Double,aLon:Double,bLat:Double,bLon:Double):Double{val p1=Math.toRadians(aLat);val p2=Math.toRadians(bLat);val dp=p2-p1;val dl=Math.toRadians(bLon-aLon);val h=kotlin.math.sin(dp/2)*kotlin.math.sin(dp/2)+kotlin.math.cos(p1)*kotlin.math.cos(p2)*kotlin.math.sin(dl/2)*kotlin.math.sin(dl/2);return 6371000*2*kotlin.math.atan2(kotlin.math.sqrt(h),kotlin.math.sqrt(1-h))}

private fun ActivityKind.toActivityType() = ActivityType.valueOf(name.lowercase())
