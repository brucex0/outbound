package com.plainstride.outbound

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.background
import androidx.compose.material3.MaterialTheme
import com.plainstride.outbound.core.designsystem.PlainstrideTheme
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.ViewModelStore
import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import com.plainstride.outbound.core.analytics.ProductAnalytics
import com.plainstride.outbound.core.analytics.AnalyticsSink
import com.plainstride.outbound.core.analytics.SanitizedAnalyticsEvent
import com.plainstride.outbound.core.data.ActivityMediaStore
import com.plainstride.outbound.core.data.ActivitySyncScheduler
import com.plainstride.outbound.core.data.GroupActivityRepository
import com.plainstride.outbound.core.network.AccessTokenProvider
import com.plainstride.outbound.core.network.PlanningApiService
import com.plainstride.outbound.core.music.MusicProvider
import com.plainstride.outbound.core.music.MusicState
import com.plainstride.outbound.core.music.MusicQueue
import com.plainstride.outbound.feature.recording.RecordingViewModel
import com.plainstride.outbound.feature.recording.RecordingVoiceCoordinator
import com.plainstride.outbound.feature.recording.RecordingCountdownAudio
import com.plainstride.outbound.feature.recording.RecordingSnapshot
import com.plainstride.outbound.feature.recording.RecordingStatus
import com.plainstride.outbound.feature.recording.RecordedActivityReview
import com.plainstride.outbound.core.designsystem.PlainstrideThemeId
import kotlinx.coroutines.flow.MutableStateFlow
import androidx.lifecycle.viewModelScope
import androidx.room.withTransaction
import com.plainstride.outbound.core.data.ActivityRepository
import com.plainstride.outbound.core.database.PlainstrideDatabase
import com.plainstride.outbound.core.model.activity.ActivityType
import com.plainstride.outbound.core.model.activity.SavedActivity
import com.plainstride.outbound.core.network.PlainstrideJson
import com.plainstride.outbound.feature.recording.WorkoutFeedbackSheet
import com.plainstride.outbound.feature.recording.ReflectionChoice
import com.plainstride.outbound.feature.recording.ContinuationCapacity
import dagger.hilt.android.lifecycle.HiltViewModel
import java.time.Instant
import java.util.UUID
import javax.inject.Inject
import kotlinx.coroutines.launch
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.intOrNull

@HiltViewModel
class DebugSessionEffortViewModel @Inject constructor(
    @param:ApplicationContext private val context: Context,
    api: com.plainstride.outbound.core.network.ActivitiesApiService,
    photos: com.plainstride.outbound.core.data.ActivityPhotoRepository,
    groups: GroupActivityRepository,
    media: ActivityMediaStore,
    planningApi: PlanningApiService,
) : ViewModel() {
    private val account = "__synthetic_session_effort_qa__"
    private val recordingStore = ViewModelStore()
    private var failsNextLocalSave = true
    private val noAnalytics = ProductAnalytics(object : AnalyticsSink {
        override fun setUserId(userId: String?) {}
        override fun record(event: SanitizedAnalyticsEvent) {}
    })
    private val database = androidx.room.Room.databaseBuilder(context, PlainstrideDatabase::class.java, "session-effort-fixture-v9.db").build()
    private val activities = com.plainstride.outbound.core.data.OfflineFirstActivityRepository(database, api,
        object : AccessTokenProvider { override suspend fun validAccessToken(): String? = null }, media, photos, noAnalytics, { account })
    private val localRepository = object : ActivityRepository by activities {
        override suspend fun save(activity: SavedActivity) {
            require(activity.accountId == account) // Never write another account through this fixture.
            if (failsNextLocalSave) {
                failsNextLocalSave = false
                android.util.Log.i("planning_debug", "recording_save_injected_failure category=local_persistence")
                throw java.io.IOException("synthetic local persistence failure")
            }
            activities.save(activity)
        }
    }
    private val voice = RecordingVoiceCoordinator(context, object : MusicProvider {
        override val state = MutableStateFlow(MusicState())
        override suspend fun connect() = Result.success(Unit)
        override suspend fun disconnect() {}
        override suspend fun setQueue(queue: MusicQueue) {}
        override suspend fun play(index: Int) = Result.success(Unit)
        override suspend fun pause() = Result.success(Unit)
        override suspend fun resume() = Result.success(Unit)
        override suspend fun skipNext() = Result.success(Unit)
        override fun close() {}
    }, noAnalytics, object : RecordingCountdownAudio {
        override fun setLocale(locale: String) {}
        override suspend fun prepare() = false
        override fun isReady() = false
        override suspend fun play(value: Int, minimumBeatMilliseconds: Long) {}
        override fun stop() {}
    })
    private val recording = ViewModelProvider(recordingStore, object : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            require(modelClass == RecordingViewModel::class.java)
            return RecordingViewModel(context, noAnalytics, groups, localRepository, media, ActivitySyncScheduler {}, voice,
                planningApi, object : AccessTokenProvider { override suspend fun validAccessToken(): String? = null }) as T
        }
    })[RecordingViewModel::class.java]
    val recordingState = recording.state
    fun setRating(value: Int?) = recording.setSessionEffortRating(value)
    fun setFit(value: ReflectionChoice) = recording.setReflection(value)
    fun setCapacity(value: ContinuationCapacity) = recording.setContinuationCapacity(value)
    private val syntheticSessionId = UUID.randomUUID().toString()
    private val syntheticSavedAt = Instant.now()
    private val receipt = com.plainstride.outbound.core.model.PerformedWorkoutReference(
        policyVersion = "performed-workout-v1", issuanceId = "synthetic-issued", revision = "a".repeat(64),
        plannedWorkoutId = "synthetic-slot", planVersionId = "synthetic-version", performedAsIssued = true)
    private var attempts = 0
    private var failurePreservedDraft = false

    /** Actual saveFinished, with no recorder start/finish/discard or provider call. */
    fun saveThroughRecordingReview() = viewModelScope.launch {
        attempts += 1
        val serialized = PlainstrideJson.encodeToString(com.plainstride.outbound.feature.recording.RecordingLaunchConfiguration.serializer(),
            com.plainstride.outbound.feature.recording.RecordingLaunchConfiguration(plannedWorkoutId = receipt.plannedWorkoutId, performedWorkoutReference = receipt))
        val restoredLaunch = PlainstrideJson.decodeFromString(com.plainstride.outbound.feature.recording.RecordingLaunchConfiguration.serializer(), serialized)
        recording.configure(restoredLaunch)
        val ratingBefore = recording.state.value.sessionEffortRating
        val review = RecordedActivityReview(
            RecordingSnapshot(sessionId = syntheticSessionId, accountId = account, status = RecordingStatus.AWAITING_SAVE,
                startedAtEpochMilliseconds = syntheticSavedAt.minusSeconds(1800).toEpochMilli(), recordedAtEpochMilliseconds = syntheticSavedAt.toEpochMilli(),
                elapsedSeconds = 1800, distanceMeters = 5000.0),
            recording.state.value.reflection, recording.state.value.continuationCapacity, emptyList(), emptySet(), ratingBefore)
        try {
            val saved = recording.saveFinished(review, savePhotoToAlbum = false)
            val draftRetained = recording.state.value.sessionEffortRating == ratingBefore
            val savingReset = !recording.state.value.saving
            if (!saved.saved) failurePreservedDraft = draftRetained && savingReset
            val persisted = saved.activity?.let { activities.activity(account, it.id) }
            val queued = database.syncOutboxDao().pending(account, Long.MAX_VALUE, 50).filter { it.aggregateId == saved.activity?.id }
            val outboxRetained = queued.isNotEmpty() && queued.all {
                PlainstrideJson.parseToJsonElement(it.payloadJson).jsonObject["clientData"]?.jsonObject?.get("sessionEffortRating")?.jsonPrimitive?.intOrNull == ratingBefore
            }
            val receiptRetained = persisted?.performedWorkoutReference == receipt && queued.isNotEmpty() && queued.all {
                val reference = PlainstrideJson.parseToJsonElement(it.payloadJson).jsonObject["clientData"]?.jsonObject?.get("performedWorkoutReference")
                reference != null && PlainstrideJson.decodeFromJsonElement(com.plainstride.outbound.core.model.PerformedWorkoutReference.serializer(), reference) == receipt
            }
            result = "Launch receipt reloaded: ${restoredLaunch.performedWorkoutReference == receipt}\nLocal/outbox receipt persisted: $receiptRetained\nActual recording save attempt: $attempts\nAccepted: ${saved.saved}\nSaving reset: $savingReset\nRating draft retained: $draftRetained\nFirst failure retained draft: $failurePreservedDraft\nLocal rating persisted: ${persisted != null && persisted.sessionEffortRating == ratingBefore}\nOutbox rating persisted: $outboxRetained"
        } catch (error: kotlinx.coroutines.CancellationException) { throw error }
        catch (error: Exception) {
            android.util.Log.e("planning_debug", "recording_save_fixture_failed category=${error.javaClass.simpleName}")
            result = "Recording save fixture failed"
        } finally { cleanupSyntheticRows() }
    }
    private suspend fun cleanupSyntheticRows() = kotlinx.coroutines.withContext(kotlinx.coroutines.NonCancellable) {
        try {
            database.withTransaction {
                database.syncOutboxDao().deleteForAccount(account)
                database.activityDao().deleteForAccount(account)
            }
        } catch (error: Exception) { android.util.Log.e("planning_debug", "session_effort_cleanup_failed category=${error.javaClass.simpleName}") }
    }
    override fun onCleared() {
        recordingStore.clear() // Closes this private voice/client and only unbinds the session service.
        super.onCleared()
    }
    var result by mutableStateOf<String?>(null)
        private set

    /** Isolated synthetic account; no scheduler/provider call and all fixture rows are removed. */
    fun roundtrip(rating: Int?) = viewModelScope.launch {
        val account = "__synthetic_session_effort_qa__"
        try {
            val now = Instant.now()
            val saved = SavedActivity(id = UUID.randomUUID().toString(), accountId = account, type = ActivityType.running,
                title = "Synthetic activity", reflection = null, createdAt = now.toString(), startedAt = now.minusSeconds(1800).toString(),
                endedAt = now.toString(), durationSecs = 1800, distanceM = 5000.0, localUpdatedAt = now.toString(), sessionEffortRating = rating)
            activities.save(saved)
            val first = requireNotNull(activities.activity(account, saved.id))
            val updated = first.copy(elevationGainM = 18.0, localUpdatedAt = now.plusMillis(1).toString())
            activities.save(updated)
            val loaded = requireNotNull(activities.activity(account, saved.id))
            val operations = database.syncOutboxDao().pending(account, Long.MAX_VALUE, 50).filter { it.aggregateId == saved.id }
            val privateRatings = operations.map { operation ->
                PlainstrideJson.parseToJsonElement(operation.payloadJson).jsonObject["clientData"]?.jsonObject?.get("sessionEffortRating")?.jsonPrimitive?.intOrNull
            }
            val json = PlainstrideJson.decodeFromString(SavedActivity.serializer(), PlainstrideJson.encodeToString(SavedActivity.serializer(), loaded))
            result = "Local save: ${first.sessionEffortRating == rating}\nOutbox: ${operations.isNotEmpty() && privateRatings.all { it == rating }}\nMetadata update: ${loaded.sessionEffortRating == rating}\nJSON roundtrip: ${json.sessionEffortRating == rating}"
        } catch (error: Exception) {
            android.util.Log.e("planning_debug", "session_effort_roundtrip_failed category=${error.javaClass.simpleName}")
            result = "Local roundtrip failed"
        } finally {
            try {
                database.withTransaction {
                    database.syncOutboxDao().deleteForAccount(account)
                    database.activityDao().deleteForAccount(account)
                }
            } catch (error: Exception) {
                android.util.Log.e("planning_debug", "session_effort_cleanup_failed category=${error.javaClass.simpleName}")
                result = "Synthetic cleanup failed"
            }
        }
    }
}

@Composable
internal fun DebugSessionEffortHarness(viewModel: DebugSessionEffortViewModel = hiltViewModel()) {
    val recording by viewModel.recordingState.collectAsState()
    var feedback by remember { mutableStateOf(true) }
    var theme by remember { mutableStateOf(PlainstrideThemeId.VictoryGold) }
    var dark by remember { mutableStateOf(false) }
    PlainstrideTheme(theme = theme, darkTheme = dark) {
    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text("Synthetic session effort")
        TextButton(onClick = { feedback = true }) { Text("Feedback") }
        TextButton(onClick = { viewModel.roundtrip(recording.sessionEffortRating) }) { Text("Check local save and outbox") }
        TextButton(onClick = { viewModel.saveThroughRecordingReview() }, enabled = !recording.saving) { Text("Save through actual recording review (first fails)") }
        viewModel.result?.let { Text(it) }
    }
    if (feedback) WorkoutFeedbackSheet(selected = recording.reflection, continuationCapacity = recording.continuationCapacity, onSelect = viewModel::setFit,
        onCapacitySelect = viewModel::setCapacity, onDismiss = { feedback = false }, sessionEffortRating = recording.sessionEffortRating, onSessionEffortRating = viewModel::setRating,
        previewControls = { DebugEffortThemeControls(theme, dark, onTheme = { theme = it }, onDark = { dark = it }) })
    }
}


@Composable
private fun DebugEffortThemeControls(theme: PlainstrideThemeId, dark: Boolean, onTheme: (PlainstrideThemeId) -> Unit, onDark: (Boolean) -> Unit) {
    Column {
        Text("Local production-theme preview (no settings sync)")
        TextButton(onClick = { onTheme(if (theme == PlainstrideThemeId.VictoryGold) PlainstrideThemeId.NeonPulse else PlainstrideThemeId.VictoryGold) }) { Text("Theme: $theme") }
        TextButton(onClick = { onDark(!dark) }) { Text("Appearance: ${if (dark) "Dark" else "Light"}") }
    }
}
