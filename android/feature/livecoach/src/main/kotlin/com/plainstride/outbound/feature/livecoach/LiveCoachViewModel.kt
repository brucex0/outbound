package com.plainstride.outbound.feature.livecoach

import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.plainstride.outbound.core.analytics.AnalyticsEvent
import com.plainstride.outbound.core.analytics.AnalyticsProperty
import com.plainstride.outbound.core.analytics.ProductAnalytics
import com.plainstride.outbound.core.model.activity.MeasurementUnitSystem
import com.plainstride.outbound.core.network.AccessTokenProvider
import com.plainstride.outbound.core.network.ApiResult
import com.plainstride.outbound.feature.livecoach.audio.AudioPackSelection
import com.plainstride.outbound.feature.livecoach.audio.FixedAudioPackStore
import com.plainstride.outbound.feature.livecoach.audio.FixedCueKeys
import com.plainstride.outbound.feature.livecoach.audio.LiveCoachPlaybackCoordinator
import com.plainstride.outbound.feature.livecoach.audio.LiveCoachPlaybackService
import com.plainstride.outbound.feature.livecoach.audio.LocalizedFallbackPhrases
import com.plainstride.outbound.feature.livecoach.audio.PlannedAudioCache
import com.plainstride.outbound.feature.livecoach.network.ClientWorkout
import com.plainstride.outbound.feature.livecoach.network.CoachingContract
import com.plainstride.outbound.feature.livecoach.network.CreateSessionRequest
import com.plainstride.outbound.feature.livecoach.network.CreateSessionResponse
import com.plainstride.outbound.feature.livecoach.network.CueRequest
import com.plainstride.outbound.feature.livecoach.network.EndSessionRequest
import com.plainstride.outbound.feature.livecoach.network.Environment
import com.plainstride.outbound.feature.livecoach.network.LiveCoachCatalog
import com.plainstride.outbound.feature.livecoach.network.LiveCoachConfig
import com.plainstride.outbound.feature.livecoach.network.LiveCoachMode
import com.plainstride.outbound.feature.livecoach.network.LiveCoachMoment
import com.plainstride.outbound.feature.livecoach.network.LiveCoachRepository
import com.plainstride.outbound.feature.livecoach.network.LiveState
import com.plainstride.outbound.feature.livecoach.network.Phrase
import com.plainstride.outbound.feature.livecoach.network.SessionIntent
import com.plainstride.outbound.feature.livecoach.network.WorkoutReference
import com.plainstride.outbound.feature.livecoach.network.WorkoutRoute
import com.plainstride.outbound.feature.livecoach.network.WorkoutStep
import com.plainstride.outbound.feature.livecoach.policy.CoachSnapshot
import com.plainstride.outbound.feature.livecoach.policy.DetectedMoment
import com.plainstride.outbound.feature.livecoach.policy.LiveCoachMomentPolicy
import com.plainstride.outbound.feature.livecoach.policy.LiveCoachSchedule
import com.plainstride.outbound.feature.livecoach.policy.ScheduledCue
import com.plainstride.outbound.feature.recording.ActivityKind
import com.plainstride.outbound.feature.recording.RecordingLaunchConfiguration
import com.plainstride.outbound.feature.recording.RecordingSessionClient
import com.plainstride.outbound.feature.recording.RecordingSnapshot
import com.plainstride.outbound.feature.recording.RecordingStatus
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import java.time.Instant
import java.time.ZoneId
import java.util.Locale
import java.util.UUID
import javax.inject.Inject
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

data class LiveCoachUiState(
    val preferences: LiveCoachPreferences = LiveCoachPreferences(),
    val catalog: LiveCoachCatalog? = null,
    val configuration: LiveCoachConfig? = null,
    val loading: Boolean = false,
    val error: Boolean = false,
)

private data class ActiveSegment(
    val index: Int?,
    val phase: String?,
    val elapsedSeconds: Int,
    val targetPace: Double?,
    val fasterTolerance: Double?,
    val slowerTolerance: Double?,
    val recognizesTargetLock: Boolean,
)

@HiltViewModel
class LiveCoachViewModel @Inject constructor(
    @param:ApplicationContext private val context: Context,
    private val preferencesRepository: LiveCoachPreferencesRepository,
    private val repository: LiveCoachRepository,
    private val tokens: AccessTokenProvider,
    private val packs: FixedAudioPackStore,
    private val plannedCache: PlannedAudioCache,
    private val playback: LiveCoachPlaybackCoordinator,
    private val analytics: ProductAnalytics,
) : ViewModel() {
    private data class PendingCue(val moment: DetectedMoment, val scheduled: ScheduledCue? = null)

    private val mutableUi = MutableStateFlow(LiveCoachUiState())
    val ui: StateFlow<LiveCoachUiState> = mutableUi
    val preferences = preferencesRepository.preferences.stateIn(
        viewModelScope,
        SharingStarted.Eagerly,
        LiveCoachPreferences(),
    )
    private val client = RecordingSessionClient(context).apply { connect() }
    private val policy = LiveCoachMomentPolicy()
    private val schedule = LiveCoachSchedule()
    private val pendingCues = ArrayDeque<PendingCue>()
    private val phraseUseCounts = mutableMapOf<String, Int>()
    private var observer: Job? = null
    private var serverSession: CreateSessionResponse? = null
    private var activeClientSessionId: String? = null
    private var startAttemptedForSessionId: String? = null
    private var lastStatus: RecordingStatus? = null
    private var serviceStarted = false
    private var spokenCount = 0

    init {
        viewModelScope.launch {
            preferencesRepository.preferences.collect {
                mutableUi.value = mutableUi.value.copy(preferences = it)
            }
        }
    }

    fun loadCatalog() = viewModelScope.launch {
        mutableUi.value = mutableUi.value.copy(loading = true, error = false)
        val token = tokens.validAccessToken()
        val locale = supportedLocale()
        val configResult = token?.let { repository.config(it) }
        val catalogResult = token?.let { repository.catalog(it, locale) }
        val configuration = when (configResult) {
            is ApiResult.Success -> configResult.value
            else -> null
        }
        mutableUi.value = when (catalogResult) {
            is ApiResult.Success -> mutableUi.value.copy(
                catalog = catalogResult.value,
                configuration = configuration,
                loading = false,
            )
            else -> mutableUi.value.copy(loading = false, error = true)
        }
        analytics.record(
            AnalyticsEvent(
                "live_coach_catalog_loaded",
                mapOf(
                    AnalyticsProperty.Result to if (catalogResult is ApiResult.Success) "success" else "failure",
                    AnalyticsProperty.Locale to locale,
                ),
            ),
        )
    }

    fun savePreferences(value: LiveCoachPreferences) = viewModelScope.launch {
        preferencesRepository.save(value)
        analytics.record(
            AnalyticsEvent(
                "live_coach_preference_changed",
                mapOf(
                    AnalyticsProperty.Enabled to value.enabled,
                    AnalyticsProperty.Result to value.contract.wireValue,
                ),
            ),
        )
    }

    fun attachRecording(launch: RecordingLaunchConfiguration, unitSystem: MeasurementUnitSystem) {
        if (observer != null) return
        observer = viewModelScope.launch {
            client.snapshots.collect { snapshot -> process(snapshot, launch, unitSystem) }
        }
    }

    private suspend fun process(
        snapshot: RecordingSnapshot,
        launch: RecordingLaunchConfiguration,
        unitSystem: MeasurementUnitSystem,
    ) {
        val previousStatus = lastStatus
        lastStatus = snapshot.status
        val prefs = preferences.value
        if (!prefs.enabled) {
            if (activeClientSessionId != null) end("interrupted")
            return
        }

        when (snapshot.status) {
            RecordingStatus.ACTIVE -> processActive(snapshot, launch, unitSystem, prefs, previousStatus)
            RecordingStatus.PAUSED -> if (previousStatus != RecordingStatus.PAUSED && serviceStarted) {
                context.startService(LiveCoachPlaybackService.pauseIntent(context))
            }
            RecordingStatus.AWAITING_SAVE -> if (previousStatus != RecordingStatus.AWAITING_SAVE) end("completed")
            RecordingStatus.IDLE -> if (previousStatus != null && previousStatus != RecordingStatus.IDLE && activeClientSessionId != null) {
                end("discarded")
            }
        }
    }

    private suspend fun processActive(
        snapshot: RecordingSnapshot,
        launch: RecordingLaunchConfiguration,
        unitSystem: MeasurementUnitSystem,
        prefs: LiveCoachPreferences,
        previousStatus: RecordingStatus?,
    ) {
        val clientSessionId = snapshot.sessionId ?: return
        if (activeClientSessionId != clientSessionId) {
            if (activeClientSessionId != null) end("interrupted")
            resetForSession(clientSessionId)
        }
        if (startAttemptedForSessionId != clientSessionId) {
            startAttemptedForSessionId = clientSessionId
            startSession(snapshot, launch, unitSystem, prefs)
        }

        if (serverSession?.effectiveMode == LiveCoachMode.Disabled) {
            stopService()
            return
        }
        if (!serviceStarted) {
            ContextCompat.startForegroundService(context, LiveCoachPlaybackService.startIntent(context))
            serviceStarted = true
        } else if (previousStatus == RecordingStatus.PAUSED) {
            context.startService(LiveCoachPlaybackService.startIntent(context))
        }

        val coachSnapshot = snapshot.toCoachSnapshot(launch)
        val policyUpdate = policy.ingest(coachSnapshot, prefs.contract)
        policyUpdate.evaluatedCues.forEach { evaluated ->
            analytics.record(
                AnalyticsEvent(
                    "live_guidance_cue_evaluated",
                    mapOf(
                        AnalyticsProperty.MomentType to evaluated.moment.wireValue,
                        AnalyticsProperty.Result to evaluated.outcome.wireValue,
                    ),
                ),
            )
        }
        val scheduleUpdate = schedule.ingest(
            snapshot = snapshot,
            guidancePlan = serverSession?.guidancePlan,
            goal = launch.goal,
            activityKind = launch.activityKind,
            imperial = unitSystem == MeasurementUnitSystem.imperial,
        )
        scheduleUpdate.workoutCue?.let { enqueue(PendingCue(it.moment, it), priority = true, prefs.contract) }
        policyUpdate.nextMoment?.let { enqueue(PendingCue(it), priority = false, prefs.contract) }
        scheduleUpdate.progressCue?.let { enqueue(PendingCue(it.moment, it), priority = false, prefs.contract) }

        val pending = pendingCues.removeFirstOrNull() ?: return
        speak(pending, snapshot, launch, unitSystem, prefs, coachSnapshot)
    }

    private suspend fun speak(
        pending: PendingCue,
        snapshot: RecordingSnapshot,
        launch: RecordingLaunchConfiguration,
        unitSystem: MeasurementUnitSystem,
        prefs: LiveCoachPreferences,
        coachSnapshot: CoachSnapshot,
    ) {
        val moment = pending.moment
        val session = serverSession
        val phrase = if (moment.moment == LiveCoachMoment.Progress) null else {
            selectPhrase(session, moment, coachSnapshot.segmentPhase)
        }
        val fallback = when {
            pending.scheduled?.goalMilestone != null -> LocalizedFallbackPhrases.goal(
                context,
                supportedLocale(),
                pending.scheduled.goalMilestone,
                unitSystem.name,
            )
            moment.moment == LiveCoachMoment.Progress -> LocalizedFallbackPhrases.progress(
                context,
                supportedLocale(),
                snapshot,
                unitSystem.name,
                pending.scheduled?.includePace ?: true,
            )
            moment.preferredText != null -> moment.preferredText
            phrase != null -> phrase.text
            else -> LocalizedFallbackPhrases.phrase(context, supportedLocale(), moment.moment)
        }
        val request = CueRequest(
            cueRequestId = UUID.randomUUID().toString(),
            moment = moment.moment,
            detectedAtElapsedSeconds = moment.detectedAtElapsedSeconds,
            validForMilliseconds = session?.limits?.cueValidityMilliseconds?.coerceIn(1_000, 10_000) ?: 5_000,
            selectedPhraseId = phrase?.id,
            liveState = snapshot.toLiveState(
                launch,
                coachSnapshot,
                policy.rollingPaceSecondsPerKilometer(),
                policy.rollingGradePercent,
            ),
        )
        val activeMode = when {
            session == null || session.isExpired() -> LiveCoachMode.FixedOnly
            moment.moment != LiveCoachMoment.Progress && phrase == null -> LiveCoachMode.FixedOnly
            else -> session.effectiveMode
        }
        val token = if (session == null) null else tokens.validAccessToken()
        val result = playback.play(
            token = token,
            sessionId = session?.sessionId,
            planHash = session?.guidancePlanHash,
            phraseId = phrase?.id,
            request = request,
            mode = activeMode,
            accessReason = session?.access?.reason ?: "feature_disabled",
            selection = prefs.selection(),
            fallbackText = fallback,
            fixedCueKey = when {
                moment.fixedCueKey != null -> moment.fixedCueKey
                moment.preferredText != null || moment.moment == LiveCoachMoment.Progress -> null
                else -> FixedCueKeys.forMoment(moment.moment)
            },
        )
        if (!result.played) return
        spokenCount++
        policy.recordSpoken(moment)
        schedule.recordGuideSpeech(moment.detectedAtElapsedSeconds)
        pending.scheduled?.let(schedule::recordSpoken)
        analytics.record(
            AnalyticsEvent(
                "live_guidance_cue_spoken",
                mapOf(
                    AnalyticsProperty.MomentType to moment.moment.wireValue,
                    AnalyticsProperty.CoachingContract to prefs.contract.wireValue,
                ),
            ),
        )
    }

    private fun enqueue(cue: PendingCue, priority: Boolean, contract: CoachingContract) {
        val key = queueKey(cue)
        if (pendingCues.any { queueKey(it) == key }) return
        if (priority) pendingCues.addFirst(cue) else pendingCues.addLast(cue)
        while (pendingCues.size > MAX_PENDING_CUES) pendingCues.removeLast()
        analytics.record(
            AnalyticsEvent(
                "live_guidance_moment_detected",
                mapOf(
                    AnalyticsProperty.MomentType to cue.moment.moment.wireValue,
                    AnalyticsProperty.CoachingContract to contract.wireValue,
                ),
            ),
        )
    }

    private fun queueKey(cue: PendingCue) = listOf(
        cue.moment.moment.wireValue,
        cue.moment.instructionId.orEmpty(),
        cue.scheduled?.goalMilestone.orEmpty(),
    ).joinToString("|")

    private suspend fun startSession(
        snapshot: RecordingSnapshot,
        launch: RecordingLaunchConfiguration,
        unitSystem: MeasurementUnitSystem,
        prefs: LiveCoachPreferences,
    ) {
        val token = tokens.validAccessToken()
        if (token == null) {
            recordSessionStartFailure()
            return
        }
        val request = CreateSessionRequest(
            clientSessionId = snapshot.sessionId ?: return,
            workoutId = launch.plannedWorkoutId,
            workoutRef = launch.standaloneWorkoutId?.let {
                WorkoutReference(id = it, version = launch.standaloneWorkoutCatalogVersion)
            },
            locale = supportedLocale(),
            coachPersonaId = prefs.personaId,
            voiceProfileId = prefs.voiceProfileId,
            coachingContract = prefs.contract,
            measurementUnitSystem = unitSystem.name,
            sessionIntent = SessionIntent(
                activityType = launch.activityKind.name.lowercase(Locale.ROOT),
                goalType = launch.goalType(),
            ),
            clientWorkout = launch.clientWorkout(),
            environment = Environment(
                timeZoneIdentifier = ZoneId.systemDefault().id,
                indoor = launch.indoor,
            ),
        )
        when (val result = repository.createSession(token, request)) {
            is ApiResult.Success -> {
                serverSession = result.value
                policy.reset()
                schedule.reset()
                pendingCues.clear()
                phraseUseCounts.clear()
                spokenCount = 0
                preload(result.value, prefs, token)
                analytics.record(
                    AnalyticsEvent(
                        "live_coach_session_started",
                        mapOf(
                            AnalyticsProperty.Result to "success",
                            AnalyticsProperty.AudioMode to result.value.effectiveMode.wireValue,
                            AnalyticsProperty.AccessReason to result.value.access.reason,
                        ),
                    ),
                )
            }
            is ApiResult.Failure -> recordSessionStartFailure()
        }
    }

    private fun recordSessionStartFailure() {
        analytics.record(
            AnalyticsEvent(
                "live_coach_session_started",
                mapOf(
                    AnalyticsProperty.Result to "failure",
                    AnalyticsProperty.AudioMode to LiveCoachMode.FixedOnly.wireValue,
                    AnalyticsProperty.AccessReason to "feature_disabled",
                ),
            ),
        )
    }

    private fun preload(session: CreateSessionResponse, prefs: LiveCoachPreferences, token: String) {
        val fixedKeys = session.guidancePlan.cues.map { FixedCueKeys.forMoment(it.moment) }.distinct()
        viewModelScope.launch {
            packs.refresh(session.audioPack.manifestUrl, session.audioPack.manifestVersion, MANIFEST_KEYS)
            packs.preload(fixedKeys, prefs.selection())
        }
        if (session.effectiveMode != LiveCoachMode.Dynamic || session.planner.status != "generated") return
        val preferredMoments = listOf(
            LiveCoachMoment.EarlyOverpace,
            LiveCoachMoment.PaceAboveTarget,
            LiveCoachMoment.PaceBelowTarget,
            LiveCoachMoment.PaceDrift,
            LiveCoachMoment.RaceStartRestraint,
            LiveCoachMoment.RaceHalfwayAssessment,
            LiveCoachMoment.RaceLateFade,
            LiveCoachMoment.RaceFinalKilometer,
            LiveCoachMoment.RecoveryTooHard,
            LiveCoachMoment.ClimbStart,
            LiveCoachMoment.SegmentTransition,
            LiveCoachMoment.FinishOpportunity,
        )
        val workoutPhrases = session.guidancePlan.cues
            .filter { it.moment == LiveCoachMoment.WorkoutInstruction }
            .mapNotNull { it.phrases.firstOrNull() }
        val reactivePhrases = preferredMoments.mapNotNull { moment ->
            session.guidancePlan.cues.firstOrNull { it.moment == moment }?.phrases?.firstOrNull()
        }
        viewModelScope.launch {
            (workoutPhrases + reactivePhrases).distinctBy(Phrase::id).take(MAX_PREWARM_PHRASES).forEach { phrase ->
                if (plannedCache.audio(session.guidancePlanHash, prefs.voiceProfileId, phrase.id) != null) return@forEach
                repository.phraseAudio(token, session.sessionId, phrase.id).getOrNull()?.let { audio ->
                    plannedCache.store(audio, session.guidancePlanHash, prefs.voiceProfileId, phrase.id)
                }
            }
        }
    }

    private fun selectPhrase(session: CreateSessionResponse?, moment: DetectedMoment, phase: String?): Phrase? {
        val plan = session?.guidancePlan ?: return null
        val eligible = plan.cues.filter { cue ->
            cue.moment == moment.moment
                && (moment.instructionId == null || cue.instructionId == moment.instructionId)
                && (phase == null || "any" in cue.phases || phase in cue.phases)
        }.flatMap { it.phrases }
        val selected = eligible.minWithOrNull(
            compareBy<Phrase> { phraseUseCounts[it.id] ?: 0 }.thenBy(Phrase::id),
        ) ?: return null
        phraseUseCounts[selected.id] = (phraseUseCounts[selected.id] ?: 0) + 1
        return selected
    }

    private suspend fun end(outcome: String) {
        val session = serverSession
        serverSession = null
        if (session != null) {
            tokens.validAccessToken()?.let { token ->
                repository.endSession(
                    token,
                    session.sessionId,
                    EndSessionRequest(
                        spokenCueCount = spokenCount.coerceAtMost(100),
                        helpfulCueCount = policy.helpfulCueCount.coerceAtMost(spokenCount).coerceAtMost(100),
                        outcome = outcome,
                    ),
                )
            }
        }
        stopService()
        policy.reset()
        schedule.reset()
        pendingCues.clear()
        phraseUseCounts.clear()
        activeClientSessionId = null
        startAttemptedForSessionId = null
        analytics.record(
            AnalyticsEvent(
                "live_coach_session_ended",
                mapOf(
                    AnalyticsProperty.Result to outcome,
                    AnalyticsProperty.CountBucket to countBucket(spokenCount),
                ),
            ),
        )
        spokenCount = 0
    }

    private fun resetForSession(clientSessionId: String) {
        activeClientSessionId = clientSessionId
        startAttemptedForSessionId = null
        serverSession = null
        policy.reset()
        schedule.reset()
        pendingCues.clear()
        phraseUseCounts.clear()
        spokenCount = 0
    }

    private fun stopService() {
        if (serviceStarted) context.startService(LiveCoachPlaybackService.stopIntent(context))
        serviceStarted = false
    }

    override fun onCleared() {
        observer?.cancel()
        client.close()
        context.stopService(Intent(context, LiveCoachPlaybackService::class.java))
        super.onCleared()
    }

    private fun supportedLocale(): String {
        val locale = context.resources.configuration.locales[0]
        return when (locale.language) {
            "es" -> "es"
            "zh" -> "zh-Hans"
            else -> "en"
        }
    }

    private fun LiveCoachPreferences.selection() = AudioPackSelection(
        locale = supportedLocale(),
        voiceProfileId = voiceProfileId,
        coachPersonaId = personaId,
        scriptStyleId = scriptStyleId,
    )

    private fun countBucket(value: Int) = when (value) {
        0 -> "none"
        in 1..3 -> "one_to_three"
        in 4..8 -> "four_to_eight"
        else -> "nine_plus"
    }

    private companion object {
        const val MAX_PENDING_CUES = 8
        const val MAX_PREWARM_PHRASES = 8
        val MANIFEST_KEYS = mapOf(
            "live-coach-audio-2026-v1" to """-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEzOQ+dtpteVzDRG6ZgAWsbl2a9nDV
IUWXep0GWK1xUNtuIIF8P3nGVvnucyHGP/UclpLUmFDXgR1DNAiFJkHXuQ==
-----END PUBLIC KEY-----""",
        )
    }
}

private fun RecordingSnapshot.toCoachSnapshot(launch: RecordingLaunchConfiguration): CoachSnapshot {
    val segment = launch.activeSegment(elapsedSeconds.toInt())
    val location = latestLocation
    return CoachSnapshot(
        elapsedSeconds = elapsedSeconds.toInt(),
        distanceMeters = distanceMeters,
        paceSecondsPerKilometer = currentPaceSecondsPerKilometer,
        targetPaceSecondsPerKilometer = segment?.targetPace,
        fasterToleranceSeconds = segment?.fasterTolerance,
        slowerToleranceSeconds = segment?.slowerTolerance,
        recognizesTargetLock = segment?.recognizesTargetLock == true,
        segmentIndex = segment?.index,
        segmentPhase = segment?.phase,
        segmentElapsedSeconds = segment?.elapsedSeconds,
        targetDistanceMeters = launch.goal.targetDistanceMeters,
        targetDurationSeconds = launch.goal.targetDurationSeconds?.toInt(),
        isRunning = launch.activityKind == ActivityKind.RUNNING,
        latitude = location?.latitude,
        longitude = location?.longitude,
        altitudeMeters = location?.altitudeMeters,
        horizontalAccuracyMeters = location?.horizontalAccuracyMeters,
        verticalAccuracyMeters = location?.verticalAccuracyMeters,
    )
}

private fun RecordingSnapshot.toLiveState(
    launch: RecordingLaunchConfiguration,
    coach: CoachSnapshot,
    rollingPace: Double?,
    gradePercent: Double?,
) = LiveState(
    elapsedSeconds = elapsedSeconds.toInt(),
    distanceMeters = distanceMeters,
    remainingDistanceMeters = launch.goal.targetDistanceMeters?.let { (it - distanceMeters).coerceAtLeast(0.0) },
    currentPaceSecondsPerKilometer = currentPaceSecondsPerKilometer.validPace(),
    rollingPaceSecondsPerKilometer = rollingPace.validPace(),
    targetPaceSecondsPerKilometer = coach.targetPaceSecondsPerKilometer.validPace(),
    gradePercent = gradePercent?.takeIf { it.isFinite() && it in -40.0..40.0 },
    workoutSegmentIndex = coach.segmentIndex,
    workoutSegmentPhase = coach.segmentPhase,
    routeGuidanceActive = launch.followedRoute != null,
)

private fun RecordingLaunchConfiguration.activeSegment(elapsedSeconds: Int): ActiveSegment? {
    val timedSteps = workoutSteps.filter { (it.durationSeconds ?: 0) > 0 }
    var start = 0
    timedSteps.forEachIndexed { index, step ->
        val duration = step.durationSeconds ?: return@forEachIndexed
        val end = start + duration
        if (elapsedSeconds < end) {
            val phase = step.phase?.takeIf(::isSupportedPhase)
            val target = step.targetPaceSecondsPerKilometer.validPace()
            if (phase == null && target == null) return null
            return ActiveSegment(
                index = index,
                phase = phase,
                elapsedSeconds = (elapsedSeconds - start).coerceAtLeast(0),
                targetPace = target,
                fasterTolerance = step.fasterToleranceSeconds?.takeIf { it.isFinite() && it >= 0 },
                slowerTolerance = step.slowerToleranceSeconds?.takeIf { it.isFinite() && it >= 0 },
                recognizesTargetLock = step.recognizesTargetLock,
            )
        }
        start = end
    }
    timedSteps.lastOrNull()?.let { step ->
        val duration = step.durationSeconds ?: 0
        val phase = step.phase?.takeIf(::isSupportedPhase)
        val target = step.targetPaceSecondsPerKilometer.validPace()
        if (phase != null || target != null) {
            return ActiveSegment(
                index = timedSteps.lastIndex,
                phase = phase,
                elapsedSeconds = (elapsedSeconds - (start - duration).coerceAtLeast(0)).coerceAtLeast(0),
                targetPace = target,
                fasterTolerance = step.fasterToleranceSeconds?.takeIf { it.isFinite() && it >= 0 },
                slowerTolerance = step.slowerToleranceSeconds?.takeIf { it.isFinite() && it >= 0 },
                recognizesTargetLock = step.recognizesTargetLock,
            )
        }
    }
    val target = workoutTargetPaceSecondsPerKilometer.validPace()
    val phase = workoutPhase?.takeIf(::isSupportedPhase)
    if (target == null && phase == null) return null
    return ActiveSegment(
        index = null,
        phase = phase,
        elapsedSeconds = elapsedSeconds.coerceAtLeast(0),
        targetPace = target,
        fasterTolerance = workoutFasterToleranceSeconds?.takeIf { it.isFinite() && it >= 0 },
        slowerTolerance = workoutSlowerToleranceSeconds?.takeIf { it.isFinite() && it >= 0 },
        recognizesTargetLock = workoutRecognizesTargetLock,
    )
}

private fun RecordingLaunchConfiguration.goalType(): String = when {
    plannedWorkoutId != null || standaloneWorkoutId != null || workoutSteps.isNotEmpty() -> "workout"
    else -> goal.type.name.lowercase(Locale.ROOT)
}

private fun RecordingLaunchConfiguration.clientWorkout(): ClientWorkout? {
    if (title.isNullOrBlank() && workoutSteps.isEmpty() && followedRoute == null) return null
    return ClientWorkout(
        title = title?.takeIf(String::isNotBlank) ?: activityKind.name.lowercase(Locale.ROOT),
        detail = workoutDetail.orEmpty(),
        guideLine = listOfNotNull(
            workoutGuideline?.takeIf(String::isNotBlank),
            privateTrainingSignal?.takeIf(String::isNotBlank)?.let { "private_training_signal:$it" },
        ).joinToString(" · "),
        targetDistanceMeters = goal.targetDistanceMeters,
        targetDurationSeconds = goal.targetDurationSeconds?.toInt(),
        targetCalories = goal.targetCalories,
        steps = workoutSteps.map { step ->
            WorkoutStep(
                label = step.title,
                durationSeconds = step.durationSeconds ?: 0,
                detail = step.detail,
                phase = step.phase?.takeIf(::isSupportedPhase),
                targetPaceSecondsPerKilometer = step.targetPaceSecondsPerKilometer.validPace(),
            )
        },
        route = followedRoute?.let { route ->
            WorkoutRoute(
                name = route.name,
                shape = route.shape,
                direction = if (route.reverse) "reverse" else "forward",
                distanceMeters = route.distanceMeters,
                elevationGainMeters = route.elevationGainMeters,
                approximateStartLatitude = route.points.firstOrNull()?.latitude,
                approximateStartLongitude = route.points.firstOrNull()?.longitude,
                approximateStartAltitudeMeters = route.points.firstOrNull()?.altitudeMeters,
            )
        },
    )
}

private fun Double?.validPace() = this?.takeIf { it.isFinite() && it in 60.0..3_600.0 }
private fun isSupportedPhase(value: String) = value in setOf("warmup", "easy", "work", "recovery", "walk", "cooldown", "open")
private fun CreateSessionResponse.isExpired() = runCatching { !Instant.parse(expiresAt).isAfter(Instant.now()) }.getOrDefault(true)
