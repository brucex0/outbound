package run.plainstride.feature.livecoach

import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import java.util.Locale
import java.util.UUID
import javax.inject.Inject
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import run.plainstride.core.analytics.AnalyticsEvent
import run.plainstride.core.analytics.AnalyticsProperty
import run.plainstride.core.analytics.ProductAnalytics
import run.plainstride.core.network.AccessTokenProvider
import run.plainstride.core.network.ApiResult
import run.plainstride.feature.livecoach.audio.AudioPackSelection
import run.plainstride.feature.livecoach.audio.FixedCueKeys
import run.plainstride.feature.livecoach.audio.LiveCoachPlaybackCoordinator
import run.plainstride.feature.livecoach.audio.LiveCoachPlaybackService
import run.plainstride.feature.livecoach.audio.LocalizedFallbackPhrases
import run.plainstride.feature.livecoach.audio.FixedAudioPackStore
import run.plainstride.feature.livecoach.network.*
import run.plainstride.feature.livecoach.policy.CoachSnapshot
import run.plainstride.feature.livecoach.policy.LiveCoachMomentPolicy
import run.plainstride.feature.recording.*

data class LiveCoachUiState(val preferences: LiveCoachPreferences = LiveCoachPreferences(), val catalog: LiveCoachCatalog? = null, val loading: Boolean = false, val error: Boolean = false)

@HiltViewModel
class LiveCoachViewModel @Inject constructor(
    @param:ApplicationContext private val context: Context,
    private val preferencesRepository: LiveCoachPreferencesRepository,
    private val repository: LiveCoachRepository,
    private val tokens: AccessTokenProvider,
    private val packs: FixedAudioPackStore,
    private val playback: LiveCoachPlaybackCoordinator,
    private val analytics: ProductAnalytics,
) : ViewModel() {
    private val mutableUi = MutableStateFlow(LiveCoachUiState())
    val ui: StateFlow<LiveCoachUiState> = mutableUi
    val preferences = preferencesRepository.preferences.stateIn(viewModelScope, SharingStarted.Eagerly, LiveCoachPreferences())
    private val client = RecordingSessionClient(context).apply { connect() }
    private val policy = LiveCoachMomentPolicy()
    private var observer: Job? = null
    private var serverSession: CreateSessionResponse? = null
    private var spokenCount = 0

    init { viewModelScope.launch { preferencesRepository.preferences.collect { mutableUi.value = mutableUi.value.copy(preferences = it) } } }

    fun loadCatalog() = viewModelScope.launch {
        mutableUi.value = mutableUi.value.copy(loading = true, error = false)
        val token = tokens.validAccessToken()
        val locale = supportedLocale()
        val result = token?.let { repository.catalog(it, locale) }
        mutableUi.value = when (result) {
            is ApiResult.Success -> mutableUi.value.copy(catalog = result.value, loading = false)
            else -> mutableUi.value.copy(loading = false, error = true)
        }
        analytics.record(AnalyticsEvent("live_coach_catalog_loaded", mapOf(AnalyticsProperty.Result to if (result is ApiResult.Success) "success" else "failure", AnalyticsProperty.Locale to locale)))
    }

    fun savePreferences(value: LiveCoachPreferences) = viewModelScope.launch {
        preferencesRepository.save(value)
        analytics.record(AnalyticsEvent("live_coach_preference_changed", mapOf(AnalyticsProperty.Enabled to value.enabled, AnalyticsProperty.Result to value.contract.name.lowercase())))
    }

    fun attachRecording(launch: RecordingLaunchConfiguration) {
        if (observer != null) return
        observer = viewModelScope.launch { client.snapshots.collect { snapshot -> process(snapshot, launch) } }
    }

    private suspend fun process(snapshot: RecordingSnapshot, launch: RecordingLaunchConfiguration) {
        val prefs = preferences.value
        if (!prefs.enabled) return
        when (snapshot.status) {
            RecordingStatus.ACTIVE -> {
                if (serverSession == null && snapshot.sessionId != null) startSession(snapshot, launch, prefs)
                ContextCompat.startForegroundService(context, LiveCoachPlaybackService.startIntent(context))
                val session = serverSession ?: return
                val moment = policy.ingest(snapshot.toCoachSnapshot(launch), prefs.contract) ?: return
                val token = tokens.validAccessToken() ?: return
                val request = CueRequest(cueRequestId = UUID.randomUUID().toString(), moment = moment.moment, detectedAtElapsedSeconds = moment.detectedAtElapsedSeconds, validForMilliseconds = session.limits.cueValidityMilliseconds, liveState = snapshot.toLiveState(launch))
                val fallback = LocalizedFallbackPhrases.phrase(context, supportedLocale(), moment.moment)
                val result = playback.play(token, session.sessionId, request, session.effectiveMode, prefs.selection(), fallback)
                if (result.played) spokenCount++
            }
            RecordingStatus.PAUSED -> context.startService(LiveCoachPlaybackService.pauseIntent(context))
            RecordingStatus.AWAITING_SAVE -> end("completed")
            RecordingStatus.IDLE -> if (serverSession != null) end("discarded")
        }
    }

    private suspend fun startSession(snapshot: RecordingSnapshot, launch: RecordingLaunchConfiguration, prefs: LiveCoachPreferences) {
        val token = tokens.validAccessToken() ?: return
        val request = CreateSessionRequest(
            clientSessionId = snapshot.sessionId ?: return, locale = supportedLocale(), coachPersonaId = prefs.personaId,
            voiceProfileId = prefs.voiceProfileId, coachingContract = prefs.contract, measurementUnitSystem = if (Locale.getDefault().country == "US") "imperial" else "metric",
            sessionIntent = SessionIntent(launch.activityKind.name.lowercase(), launch.goal.type.name.lowercase()),
            workoutId=launch.plannedWorkoutId,
            workoutRef=launch.plannedWorkoutId?.let{WorkoutReference(id=it)},
            clientWorkout = launch.title?.let { ClientWorkout(it, launch.workoutDetail ?: launch.workoutSteps.mapNotNull{step->step.detail}.joinToString(" · "), listOfNotNull(launch.workoutGuideline,launch.privateTrainingSignal?.let{"private_training_signal:$it"}).joinToString(" · "), launch.goal.targetDistanceMeters, launch.goal.targetDurationSeconds?.toInt(), launch.goal.targetCalories, launch.workoutSteps.map{step->WorkoutStep(step.title,step.durationSeconds?:0,step.detail,step.phase,step.targetPaceSecondsPerKilometer)},launch.followedRoute?.let{route->WorkoutRoute(route.name,route.shape,if(route.reverse)"reverse" else "forward",route.distanceMeters,route.elevationGainMeters,route.points.firstOrNull()?.latitude,route.points.firstOrNull()?.longitude,route.points.firstOrNull()?.altitudeMeters)}) },
        )
        when (val result = repository.createSession(token, request)) {
            is ApiResult.Success -> {
                serverSession = result.value; policy.reset(); spokenCount = 0
                val keys = result.value.guidancePlan.cues.map { FixedCueKeys.forMoment(it.moment) }.distinct()
                viewModelScope.launch {
                    packs.refresh(result.value.audioPack.manifestUrl, result.value.audioPack.manifestVersion, MANIFEST_KEYS)
                    packs.preload(keys, prefs.selection())
                }
                analytics.record(AnalyticsEvent("live_coach_session_started", mapOf(AnalyticsProperty.Result to result.value.effectiveMode.name.lowercase())))
            }
            is ApiResult.Failure -> analytics.record(AnalyticsEvent("live_coach_session_started", mapOf(AnalyticsProperty.Result to "failure")))
        }
    }

    private suspend fun end(outcome: String) {
        val session = serverSession ?: return
        serverSession = null
        tokens.validAccessToken()?.let { repository.endSession(it, session.sessionId, EndSessionRequest(spokenCueCount = spokenCount, helpfulCueCount = 0, outcome = outcome)) }
        context.startService(LiveCoachPlaybackService.stopIntent(context)); policy.reset()
        analytics.record(AnalyticsEvent("live_coach_session_ended", mapOf(AnalyticsProperty.Result to outcome, AnalyticsProperty.CountBucket to countBucket(spokenCount))))
    }
    override fun onCleared() { observer?.cancel(); client.close(); context.stopService(Intent(context, LiveCoachPlaybackService::class.java)); super.onCleared() }
    private fun supportedLocale() = when (Locale.getDefault().toLanguageTag()) { "es", "zh-Hans" -> Locale.getDefault().toLanguageTag(); else -> if (Locale.getDefault().language == "es") "es" else if (Locale.getDefault().language == "zh") "zh-Hans" else "en" }
    private fun LiveCoachPreferences.selection() = AudioPackSelection(supportedLocale(), voiceProfileId, personaId, scriptStyleId)
    private fun countBucket(value: Int) = when (value) { 0 -> "none"; in 1..3 -> "one_to_three"; in 4..8 -> "four_to_eight"; else -> "nine_plus" }
    private companion object {
        val MANIFEST_KEYS = mapOf("live-coach-audio-2026-v1" to """-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEzOQ+dtpteVzDRG6ZgAWsbl2a9nDV
IUWXep0GWK1xUNtuIIF8P3nGVvnucyHGP/UclpLUmFDXgR1DNAiFJkHXuQ==
-----END PUBLIC KEY-----""")
    }
}

private fun RecordingSnapshot.toCoachSnapshot(launch: RecordingLaunchConfiguration) = CoachSnapshot(elapsedSeconds.toInt(), distanceMeters, currentPaceSecondsPerKilometer, targetDistanceMeters = launch.goal.targetDistanceMeters, targetDurationSeconds = launch.goal.targetDurationSeconds?.toInt(), isMoving = status == RecordingStatus.ACTIVE)
private fun RecordingSnapshot.toLiveState(launch:RecordingLaunchConfiguration) = LiveState(elapsedSeconds.toInt(), distanceMeters, currentPaceSecondsPerKilometer, currentPaceSecondsPerKilometer, routeGuidanceActive = launch.followedRoute!=null)
