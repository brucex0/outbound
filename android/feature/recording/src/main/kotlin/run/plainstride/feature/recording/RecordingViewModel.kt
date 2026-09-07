package run.plainstride.feature.recording

import android.content.Context
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

data class RecordingUiState(
    val launch: RecordingLaunchConfiguration = RecordingLaunchConfiguration(),
    val mode: RecordingSurfaceMode = RecordingSurfaceMode.MAP,
    val countdown: Int? = null,
    val reflection: ReflectionChoice? = null,
    val photoPath: String? = null,
    val showFinishConfirmation: Boolean = false,
    val showDiscardConfirmation: Boolean = false,
    val startRequested: Boolean = false,
)

@HiltViewModel
class RecordingViewModel @Inject constructor(
    @param:ApplicationContext private val context: Context,
    private val analytics: ProductAnalytics,
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

    override fun onCleared() {
        client.close()
        super.onCleared()
    }
}
