package run.plainstride.feature.recording

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
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.stateIn
import run.plainstride.core.analytics.AnalyticsEvent
import run.plainstride.core.analytics.AnalyticsProperty
import run.plainstride.core.analytics.ProductAnalytics
import run.plainstride.core.data.ActivityMediaStore
import run.plainstride.core.data.ActivityRepository
import run.plainstride.core.data.ActivitySyncScheduler
import run.plainstride.core.data.RecordedActivityDraft
import run.plainstride.core.data.RecordedActivityFactory
import run.plainstride.core.data.RecordedTrackPointDraft
import run.plainstride.core.model.activity.ActivityPhoto
import run.plainstride.core.model.activity.ActivityReflection
import run.plainstride.core.model.activity.ActivityType

data class RecordingUiState(
    val launch: RecordingLaunchConfiguration = RecordingLaunchConfiguration(),
    val mode: RecordingSurfaceMode = RecordingSurfaceMode.MAP,
    val countdown: Int? = null,
    val reflection: ReflectionChoice? = null,
    val photoPath: String? = null,
    val showFinishConfirmation: Boolean = false,
    val showDiscardConfirmation: Boolean = false,
    val startRequested: Boolean = false,
    val saving: Boolean = false,
)

@HiltViewModel
class RecordingViewModel @Inject constructor(
    @param:ApplicationContext private val context: Context,
    private val analytics: ProductAnalytics,
    private val activities: ActivityRepository,
    private val media: ActivityMediaStore,
    private val syncScheduler: ActivitySyncScheduler,
) : ViewModel() {
    private val client = RecordingSessionClient(context).apply { connect() }
    private val mutableState = MutableStateFlow(RecordingUiState())
    val state: StateFlow<RecordingUiState> = mutableState.asStateFlow()
    val snapshot: StateFlow<RecordingSnapshot> = client.snapshots.stateIn(
        viewModelScope,
        SharingStarted.WhileSubscribed(5_000),
        RecordingSnapshot(),
    )
    private var recoveryAccountId: String? = null

    fun configure(configuration: RecordingLaunchConfiguration) {
        if (mutableState.value.startRequested) return
        mutableState.value = mutableState.value.copy(launch = configuration)
        analytics.record(AnalyticsEvent("activity_setup_viewed", mapOf(
            AnalyticsProperty.Source to configuration.entrySource,
            AnalyticsProperty.ActivityType to configuration.activityKind.name.lowercase(),
            AnalyticsProperty.GoalType to configuration.goal.type.name.lowercase(),
        )))
    }

    fun updateCountdown(value: Int?) { mutableState.value = mutableState.value.copy(countdown = value) }

    fun start(accountId: String, permission: LocationPermissionState) {
        val launch = mutableState.value.launch
        mutableState.value = mutableState.value.copy(startRequested = true, countdown = null)
        client.start(accountId, launch.activityKind, permission, newCommandId())
        analytics.record(AnalyticsEvent("activity_started", mapOf(
            AnalyticsProperty.Source to launch.entrySource,
            AnalyticsProperty.ActivityType to launch.activityKind.name.lowercase(),
            AnalyticsProperty.GoalType to launch.goal.type.name.lowercase(),
            AnalyticsProperty.Permission to permission.name.lowercase(),
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
    }
    fun requestDiscard() {
        mutableState.value = mutableState.value.copy(showDiscardConfirmation = true)
        analytics.record(AnalyticsEvent("activity_discard_warning_shown"))
    }
    fun cancelDiscard() { mutableState.value = mutableState.value.copy(showDiscardConfirmation = false) }
    fun discard() {
        mutableState.value = RecordingUiState(launch = mutableState.value.launch)
        client.discard(newCommandId())
        analytics.record(AnalyticsEvent("activity_discard_confirmed"))
    }
    fun setMode(mode: RecordingSurfaceMode) {
        mutableState.value = mutableState.value.copy(mode = mode)
        analytics.record(AnalyticsEvent("activity_surface_changed", mapOf(AnalyticsProperty.Result to mode.name.lowercase())))
    }
    fun setReflection(choice: ReflectionChoice) { mutableState.value = mutableState.value.copy(reflection = choice) }
    fun setPhotoPath(path: String?) {
        mutableState.value = mutableState.value.copy(photoPath = path)
        analytics.record(AnalyticsEvent(if (path == null) "activity_photo_deleted" else "activity_photo_captured", mapOf(
            AnalyticsProperty.Result to "success",
        )))
    }
    fun trackPhotoAttempt() = analytics.record(AnalyticsEvent("activity_photo_capture_attempted", mapOf(
        AnalyticsProperty.Source to "recording",
    )))
    fun newCommandId(): String = UUID.randomUUID().toString()
    fun markSaved() = client.markSaved(newCommandId())

    /** Returns only after the activity and its outbox operation are committed to Room. */
    suspend fun saveFinished(review: RecordedActivityReview): Boolean {
        if (mutableState.value.saving) return false
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
                    title = mutableState.value.launch.title ?: context.getString(R.string.recording_default_activity_title),
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
                reflection = ActivityReflection(
                    title = context.getString(R.string.recording_reflection_title),
                    body = reflectionLabel,
                    highlight = reflectionLabel,
                ),
                photos = listOfNotNull(photo),
            ))
            syncScheduler.schedule(accountId)
            sourcePhoto?.delete()
            analytics.record(AnalyticsEvent("activity_saved_locally", mapOf(
                AnalyticsProperty.Result to "success",
                AnalyticsProperty.ActivityType to snapshot.activityKind.name.lowercase(),
            )))
            true
        }.getOrElse {
            persistedPhotoPath?.let(media::delete)
            analytics.record(AnalyticsEvent("activity_saved_locally", mapOf(AnalyticsProperty.Result to "failure")))
            false
        }.also { mutableState.value = mutableState.value.copy(saving = false) }
    }

    override fun onCleared() {
        client.close()
        super.onCleared()
    }
}

private fun ActivityKind.toActivityType() = ActivityType.valueOf(name.lowercase())
