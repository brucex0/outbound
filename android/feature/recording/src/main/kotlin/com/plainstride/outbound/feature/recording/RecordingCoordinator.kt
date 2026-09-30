package com.plainstride.outbound.feature.recording

import android.os.SystemClock
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import com.plainstride.outbound.core.analytics.AnalyticsEvent
import com.plainstride.outbound.core.analytics.AnalyticsProperty
import com.plainstride.outbound.core.analytics.ProductAnalytics
import com.plainstride.outbound.core.database.ActiveSessionJournalDao
import com.plainstride.outbound.core.database.ActiveSessionJournalEntity
import com.plainstride.outbound.core.model.activity.ActivityCompanionType
import java.util.UUID

internal interface RecordingClock {
    fun utcMillis(): Long
    fun elapsedRealtimeNanos(): Long
}

internal object AndroidRecordingClock : RecordingClock {
    override fun utcMillis() = System.currentTimeMillis()
    override fun elapsedRealtimeNanos() = SystemClock.elapsedRealtimeNanos()
}

/** Serialized state machine owned by [RecordingService]. */
class RecordingCoordinator internal constructor(
    private val journal: ActiveSessionJournalDao,
    private val locationSource: FusedRecordingLocationSource,
    private val permissionState: StateFlow<LocationPermissionState>,
    private val scope: CoroutineScope,
    private val analytics: ProductAnalytics,
    private val json: Json = Json { ignoreUnknownKeys = true },
    private val clock: RecordingClock = AndroidRecordingClock,
) {
    private val mutex = Mutex()
    private val handledCommandIds = LinkedHashSet<String>()
    private val _snapshot = MutableStateFlow(RecordingSnapshot())
    val snapshot: StateFlow<RecordingSnapshot> = _snapshot.asStateFlow()
    private val _events = MutableSharedFlow<RecordingEvent>(extraBufferCapacity = 16)
    val events: SharedFlow<RecordingEvent> = _events.asSharedFlow()
    // StateFlow conflates the one-second steps in accelerated simulations. Coaching
    // needs each step to establish separate, stable pace windows.
    private val _simulationSnapshots = MutableSharedFlow<RecordingSnapshot>(
        extraBufferCapacity = 512,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )
    val simulationSnapshots: SharedFlow<RecordingSnapshot> = _simulationSnapshots.asSharedFlow()

    private var tickJob: Job? = null
    private var locationJob: Job? = null
    private var simulationClockJob: Job? = null
    private var simulationSampler: RunSimulationRouteSampler? = null
    private var simulationStartElapsedRealtimeNanos: Long? = null
    private var activeSegmentStartedElapsedNanos: Long? = null
    private var accumulatedElapsedNanos = 0L
    private var autoPauseCandidateStartedAtNanos: Long? = null
    private var autoResumeCandidateStartedAtNanos: Long? = null
    private var latestReliableSpeedMetersPerSecond: Double? = null
    private var latestSpeedObservedAtNanos: Long? = null
    private var autoPauseProbeFilter: LocationTrackFilter? = null
    private val autoPauseProbeSamples = mutableListOf<RecordedLocationSample>()
    private var autoPauseProbeDistanceMeters = 0.0
    private var autoPauseProbePaceSecondsPerKilometer: Double? = null
    private var filter = LocationTrackFilter(ActivityKind.RUNNING)
    private var elevation = ElevationGainAccumulator()
    private var lastJournalUtcMillis = 0L

    suspend fun recover(accountId: String, commandId: String = UUID.randomUUID().toString()) = serialized(commandId) {
        val entity = journal.recoverable(accountId)
        if (entity == null) {
            ignored(commandId, "no_recoverable_session")
            return@serialized
        }
        val recovered = runCatching { json.decodeFromString<RecordingSnapshot>(entity.stateJson) }.getOrElse {
            _events.emit(RecordingEvent.Failure(commandId, "recover", it))
            return@serialized
        }
        accumulatedElapsedNanos = recovered.elapsedSeconds * NANOS_PER_SECOND
        activeSegmentStartedElapsedNanos = null
        rebuildProcessors(recovered)
        _snapshot.value = recovered.copy(
            status = if (recovered.status == RecordingStatus.AWAITING_SAVE) RecordingStatus.AWAITING_SAVE else RecordingStatus.PAUSED,
            autoPaused = false,
            revision = entity.revision,
            recordedAtEpochMilliseconds = clock.utcMillis(),
            recovered = true,
        )
        simulationSampler = restoredSimulationSampler(_snapshot.value)
        simulationStartElapsedRealtimeNanos = simulationSampler?.let {
            clock.elapsedRealtimeNanos() - _snapshot.value.runSimulation!!.elapsedSeconds * NANOS_PER_SECOND
        }
        _events.emit(RecordingEvent.CommandApplied(commandId, _snapshot.value.status))
    }

    suspend fun start(
        commandId: String,
        accountId: String,
        activityKind: ActivityKind,
        autoPauseEnabled: Boolean = AutoPauseDefaults.enabled(activityKind),
        sessionId: String = UUID.randomUUID().toString(),
        companionType: ActivityCompanionType? = null,
        simulatedRun: Boolean = false,
        simulatedRoute: FollowedRouteConfiguration? = null,
    ) = serialized(commandId) {
        if (_snapshot.value.status != RecordingStatus.IDLE) {
            ignored(commandId, "session_already_exists")
            return@serialized
        }
        // START_REDELIVER_INTENT can replay after process death. Treat the journal as
        // the authority so the same command cannot silently replace an active workout.
        journal.recoverable(accountId)?.let { existing ->
            val recovered = runCatching { json.decodeFromString<RecordingSnapshot>(existing.stateJson) }.getOrNull()
            if (recovered != null) {
                accumulatedElapsedNanos = recovered.elapsedSeconds * NANOS_PER_SECOND
                activeSegmentStartedElapsedNanos = null
                rebuildProcessors(recovered)
                _snapshot.value = recovered.copy(
                    status = if (recovered.status == RecordingStatus.AWAITING_SAVE) RecordingStatus.AWAITING_SAVE else RecordingStatus.PAUSED,
                    autoPaused = false,
                    revision = existing.revision,
                    recordedAtEpochMilliseconds = clock.utcMillis(),
                    recovered = true,
                )
                simulationSampler = restoredSimulationSampler(_snapshot.value)
                simulationStartElapsedRealtimeNanos = simulationSampler?.let {
                    clock.elapsedRealtimeNanos() - _snapshot.value.runSimulation!!.elapsedSeconds * NANOS_PER_SECOND
                }
                ignored(commandId, if (existing.sessionId == sessionId) "duplicate_start" else "recoverable_session_exists")
                return@serialized
            }
        }
        val nowUtc = clock.utcMillis()
        val sampler = if (BuildConfig.DEBUG && simulatedRun) {
            RunSimulationRouteSampler((simulatedRoute ?: HarvestRunSimulation.route).points)
        } else null
        simulationSampler = sampler
        simulationStartElapsedRealtimeNanos = sampler?.let { clock.elapsedRealtimeNanos() }
        filter = LocationTrackFilter(activityKind)
        elevation = ElevationGainAccumulator()
        accumulatedElapsedNanos = 0
        activeSegmentStartedElapsedNanos = clock.elapsedRealtimeNanos()
        autoPauseCandidateStartedAtNanos = null
        autoResumeCandidateStartedAtNanos = null
        resetAutoPauseProbe()
        latestReliableSpeedMetersPerSecond = null
        latestSpeedObservedAtNanos = null
        _snapshot.value = RecordingSnapshot(
            sessionId = sessionId,
            accountId = accountId,
            activityKind = activityKind,
            status = RecordingStatus.ACTIVE,
            autoPauseEnabled = autoPauseEnabled,
            revision = 1,
            startedAtEpochMilliseconds = nowUtc,
            recordedAtEpochMilliseconds = nowUtc,
            companionType = companionType,
            runSimulation = sampler?.let {
                RunSimulationState(routeDistanceMeters = it.totalDistanceMeters)
            },
        )
        beginCollection()
        if (sampler != null) {
            val initial = sampler.sample(
                0.0,
                _snapshot.value.runSimulation?.speedMetersPerSecond ?: 0.0,
                0,
                nowUtc,
                simulationStartElapsedRealtimeNanos ?: clock.elapsedRealtimeNanos(),
            )
            ingest(initial)
        }
        persist(force = true)
        analytics.record(
            AnalyticsEvent(
                name = "activity_recording_started",
                properties = mapOf(
                    AnalyticsProperty.ActivityType to activityKind.name.lowercase(),
                    AnalyticsProperty.AutoPauseEnabled to autoPauseEnabled,
                    AnalyticsProperty.Permission to permissionState.value.name.lowercase(),
                ),
            ),
        )
        if (sampler != null) analytics.record(
            AnalyticsEvent(
                name = "activity_simulation_started",
                properties = mapOf(
                    AnalyticsProperty.SourceType to "harvest_half",
                    AnalyticsProperty.DistanceBucket to distanceBucket(sampler.totalDistanceMeters),
                    AnalyticsProperty.SelectionType to HarvestRunSimulation.speedBucket(10.0),
                ),
            ),
        )
        _events.emit(RecordingEvent.CommandApplied(commandId, RecordingStatus.ACTIVE))
    }

    suspend fun pause(commandId: String) = serialized(commandId) {
        if (_snapshot.value.status != RecordingStatus.ACTIVE) {
            ignored(commandId, "session_not_active")
            return@serialized
        }
        applyPause(autoTriggered = false, commandId = commandId)
    }

    suspend fun resume(commandId: String) = serialized(commandId) {
        if (_snapshot.value.status != RecordingStatus.PAUSED) {
            ignored(commandId, "session_not_paused")
            return@serialized
        }
        activeSegmentStartedElapsedNanos = clock.elapsedRealtimeNanos()
        autoPauseCandidateStartedAtNanos = null
        autoResumeCandidateStartedAtNanos = null
        resetAutoPauseProbe()
        filter = LocationTrackFilter(_snapshot.value.activityKind)
        _snapshot.value = nextSnapshot(
            status = RecordingStatus.ACTIVE,
            autoPaused = false,
            trackSegmentStartIndices = _snapshot.value.trackSegmentStartIndices + _snapshot.value.track.size,
        )
        beginCollection()
        persist(force = true)
        analytics.record(AnalyticsEvent("activity_recording_resumed", mapOf(AnalyticsProperty.Trigger to "manual")))
        _events.emit(RecordingEvent.CommandApplied(commandId, RecordingStatus.ACTIVE))
    }

    suspend fun finish(commandId: String) = serialized(commandId) {
        val current = _snapshot.value
        if (current.status != RecordingStatus.ACTIVE && current.status != RecordingStatus.PAUSED) {
            ignored(commandId, "session_not_recording")
            return@serialized
        }
        freezeElapsed()
        stopSimulationClock()
        activeSegmentStartedElapsedNanos = null
        stopCollection()
        val finished = nextSnapshot(status = RecordingStatus.AWAITING_SAVE, autoPaused = false, runSimulation = null)
        simulationSampler = null
        simulationStartElapsedRealtimeNanos = null
        _snapshot.value = finished
        persist(force = true)
        analytics.record(
            AnalyticsEvent(
                "activity_recording_finished",
                mapOf(
                    AnalyticsProperty.DurationBucket to durationBucket(finished.elapsedSeconds),
                    AnalyticsProperty.DistanceBucket to distanceBucket(finished.distanceMeters),
                ),
            ),
        )
        _events.emit(RecordingEvent.SessionFinished(commandId, finished))
    }

    suspend fun discard(commandId: String) = serialized(commandId) {
        val current = _snapshot.value
        if (current.status == RecordingStatus.IDLE) {
            ignored(commandId, "no_session")
            return@serialized
        }
        stopCollection()
        stopSimulationClock()
        simulationSampler = null
        simulationStartElapsedRealtimeNanos = null
        current.accountId?.let { account -> current.sessionId?.let { journal.delete(account, it) } }
        _snapshot.value = RecordingSnapshot(recordedAtEpochMilliseconds = clock.utcMillis())
        accumulatedElapsedNanos = 0
        activeSegmentStartedElapsedNanos = null
        autoPauseCandidateStartedAtNanos = null
        autoResumeCandidateStartedAtNanos = null
        latestReliableSpeedMetersPerSecond = null
        latestSpeedObservedAtNanos = null
        resetAutoPauseProbe()
        analytics.record(AnalyticsEvent("activity_recording_discarded"))
        _events.emit(RecordingEvent.SessionDiscarded(commandId, current.sessionId))
    }

    /** Call after the awaiting-save snapshot has been durably written to the activity store. */
    suspend fun markSaved(commandId: String) = serialized(commandId) {
        val current = _snapshot.value
        if (current.status != RecordingStatus.AWAITING_SAVE) {
            ignored(commandId, "session_not_awaiting_save")
            return@serialized
        }
        current.accountId?.let { account -> current.sessionId?.let { journal.delete(account, it) } }
        stopSimulationClock()
        simulationSampler = null
        simulationStartElapsedRealtimeNanos = null
        _snapshot.value = RecordingSnapshot(recordedAtEpochMilliseconds = clock.utcMillis())
        accumulatedElapsedNanos = 0
        activeSegmentStartedElapsedNanos = null
        autoPauseCandidateStartedAtNanos = null
        autoResumeCandidateStartedAtNanos = null
        latestReliableSpeedMetersPerSecond = null
        latestSpeedObservedAtNanos = null
        analytics.record(AnalyticsEvent("activity_recording_saved"))
        _events.emit(RecordingEvent.CommandApplied(commandId, RecordingStatus.IDLE))
    }

    private suspend fun serialized(commandId: String, block: suspend () -> Unit) = mutex.withLock {
        if (!handledCommandIds.add(commandId)) {
            ignored(commandId, "duplicate_command")
            return@withLock
        }
        while (handledCommandIds.size > MAX_COMMAND_HISTORY) handledCommandIds.remove(handledCommandIds.first())
        runCatching { block() }.onFailure { _events.emit(RecordingEvent.Failure(commandId, "command", it)) }
    }

    private fun beginCollection() {
        locationJob?.cancel()
        if (_snapshot.value.runSimulation == null) {
            locationSource.start()
            locationJob = scope.launch {
                locationSource.samples.collect { raw -> mutex.withLock { ingest(raw) } }
            }
        } else {
            locationSource.stop()
        }
        tickJob?.cancel()
        if (_snapshot.value.runSimulation == null) {
            tickJob = scope.launch {
                while (true) {
                    delay(1_000)
                    mutex.withLock {
                        val now = clock.elapsedRealtimeNanos()
                        when {
                            _snapshot.value.status == RecordingStatus.ACTIVE -> {
                                evaluateAutoPause(now)
                                if (_snapshot.value.status == RecordingStatus.ACTIVE) {
                                    _snapshot.value = nextSnapshot()
                                    persist(force = false)
                                }
                            }
                            _snapshot.value.status == RecordingStatus.PAUSED && _snapshot.value.autoPaused ->
                                evaluateAutoResume(now)
                        }
                    }
                }
            }
        }
        if (_snapshot.value.runSimulation == null && (permissionState.value == LocationPermissionState.DENIED ||
            permissionState.value == LocationPermissionState.NOT_REQUESTED
        )) _events.tryEmit(RecordingEvent.LocationUnavailable(permissionState.value))
    }

    private fun stopCollection() {
        tickJob?.cancel()
        tickJob = null
        locationJob?.cancel()
        locationJob = null
        locationSource.stop()
    }

    private suspend fun ingest(raw: RecordedLocationSample) {
        val speedAccuracy = raw.speedAccuracyMetersPerSecond
        latestReliableSpeedMetersPerSecond = raw.speedMetersPerSecond?.takeIf {
            it.isFinite() && it >= 0.0 && speedAccuracy != null && speedAccuracy.isFinite() && speedAccuracy in 0.0..3.0
        }
        latestSpeedObservedAtNanos = raw.capturedAtElapsedRealtimeNanos
        when {
            _snapshot.value.status == RecordingStatus.ACTIVE -> evaluateAutoPause(raw.capturedAtElapsedRealtimeNanos)
            _snapshot.value.status == RecordingStatus.PAUSED && _snapshot.value.autoPaused -> {
                captureAutoPauseProbe(raw)
                evaluateAutoResume(raw.capturedAtElapsedRealtimeNanos)
            }
        }
        if (_snapshot.value.status != RecordingStatus.ACTIVE) return
        val output = filter.ingest(raw)
        val accepted = output.sample ?: return
        elevation.ingest(accepted)
        val distance = _snapshot.value.distanceMeters + output.distanceIncrementMeters
        val elapsed = elapsedSeconds()
        _snapshot.value = nextSnapshot(
            elapsedSeconds = elapsed,
            distanceMeters = distance,
            elevationGainMeters = elevation.gainMeters,
            currentPaceSecondsPerKilometer = output.estimatedSpeedMetersPerSecond
                ?.takeIf { it > 0.1 }
                ?.let { 1_000.0 / it },
            latestLocation = accepted,
            track = _snapshot.value.track + accepted,
        )
        persist(force = false)
    }

    private suspend fun evaluateAutoPause(nowNanos: Long) {
        val snapshot = _snapshot.value
        if (!(snapshot.autoPauseEnabled ?: AutoPauseDefaults.enabled(snapshot.activityKind)) || snapshot.runSimulation != null ||
            elapsedSeconds() < AUTO_PAUSE_WARMUP_NANOS / NANOS_PER_SECOND
        ) {
            autoPauseCandidateStartedAtNanos = null
            return
        }
        val speed = currentReliableSpeed(nowNanos)
        if (speed == null) {
            autoPauseCandidateStartedAtNanos = null
            return
        }
        if (speed < autoPauseThreshold(snapshot.activityKind)) {
            val startedAt = autoPauseCandidateStartedAtNanos
            if (startedAt == null) autoPauseCandidateStartedAtNanos = nowNanos
            else if (nowNanos - startedAt >= AUTO_PAUSE_DURATION_NANOS) applyPause(autoTriggered = true)
        } else {
            autoPauseCandidateStartedAtNanos = null
        }
    }

    private suspend fun evaluateAutoResume(nowNanos: Long) {
        val snapshot = _snapshot.value
        if (!(snapshot.autoPauseEnabled ?: AutoPauseDefaults.enabled(snapshot.activityKind))) {
            autoResumeCandidateStartedAtNanos = null
            return
        }
        val speed = currentReliableSpeed(nowNanos)
        if (speed == null) {
            autoResumeCandidateStartedAtNanos = null
            return
        }
        if (speed >= autoResumeThreshold(snapshot.activityKind)) {
            val startedAt = autoResumeCandidateStartedAtNanos
            if (startedAt == null) autoResumeCandidateStartedAtNanos = nowNanos
            else if (nowNanos - startedAt >= AUTO_RESUME_DURATION_NANOS) resumeAutomatically(nowNanos)
        } else {
            autoResumeCandidateStartedAtNanos = null
        }
    }

    private fun currentReliableSpeed(nowNanos: Long): Double? {
        val observedAt = latestSpeedObservedAtNanos ?: return null
        if (nowNanos - observedAt !in 0..MAX_SPEED_SAMPLE_AGE_NANOS) return null
        return latestReliableSpeedMetersPerSecond
    }

    private suspend fun applyPause(autoTriggered: Boolean, commandId: String? = null) {
        freezeElapsed()
        stopSimulationClock()
        activeSegmentStartedElapsedNanos = null
        autoPauseCandidateStartedAtNanos = null
        autoResumeCandidateStartedAtNanos = null
        _snapshot.value = nextSnapshot(status = RecordingStatus.PAUSED, autoPaused = autoTriggered)
        resetAutoPauseProbe()
        if (autoTriggered) autoPauseProbeFilter = LocationTrackFilter(_snapshot.value.activityKind)
        if (!autoTriggered) stopCollection()
        persist(force = true)
        analytics.record(AnalyticsEvent("activity_recording_paused", mapOf(
            AnalyticsProperty.Trigger to if (autoTriggered) "automatic" else "manual",
        )))
        if (commandId != null) _events.emit(RecordingEvent.CommandApplied(commandId, RecordingStatus.PAUSED))
    }

    private suspend fun resumeAutomatically(nowNanos: Long) {
        val promoted = promoteAutoPauseProbe()
        accumulatedElapsedNanos += promoted.durationNanos
        activeSegmentStartedElapsedNanos = nowNanos
        autoPauseCandidateStartedAtNanos = null
        autoResumeCandidateStartedAtNanos = null
        _snapshot.value = nextSnapshot(status = RecordingStatus.ACTIVE, autoPaused = false)
        persist(force = true)
        analytics.record(AnalyticsEvent("activity_recording_resumed", mapOf(AnalyticsProperty.Trigger to "automatic")))
    }

    private fun captureAutoPauseProbe(raw: RecordedLocationSample) {
        val probeFilter = autoPauseProbeFilter ?: LocationTrackFilter(_snapshot.value.activityKind).also {
            autoPauseProbeFilter = it
        }
        val output = probeFilter.ingest(raw)
        val accepted = output.sample ?: return
        autoPauseProbeSamples += accepted
        autoPauseProbeDistanceMeters += output.distanceIncrementMeters
        autoPauseProbePaceSecondsPerKilometer = output.estimatedSpeedMetersPerSecond
            ?.takeIf { it > 0.1 }
            ?.let { 1_000.0 / it }
    }

    private fun promoteAutoPauseProbe(): PromotedAutoPauseProbe {
        val samples = autoPauseProbeSamples.toList()
        var promotedDurationNanos = 0L
        for ((previous, current) in samples.zipWithNext()) {
            val intervalNanos = current.capturedAtElapsedRealtimeNanos - previous.capturedAtElapsedRealtimeNanos
            if (intervalNanos <= 0 || intervalNanos > MAX_PROBE_INTERVAL_NANOS) continue
            val speed = distanceMeters(previous, current) / (intervalNanos / NANOS_PER_SECOND.toDouble())
            if (speed >= autoPauseThreshold(_snapshot.value.activityKind)) promotedDurationNanos += intervalNanos
        }
        val snapshot = _snapshot.value
        val startIndex = snapshot.track.size
        if (samples.isNotEmpty()) {
            val track = snapshot.track + samples
            val distance = snapshot.distanceMeters + autoPauseProbeDistanceMeters
            for (sample in samples) {
                elevation.ingest(sample)
            }
            _snapshot.value = nextSnapshot(
                distanceMeters = distance,
                elevationGainMeters = elevation.gainMeters,
                currentPaceSecondsPerKilometer = autoPauseProbePaceSecondsPerKilometer ?: snapshot.currentPaceSecondsPerKilometer,
                latestLocation = samples.last(),
                track = track,
                trackSegmentStartIndices = snapshot.trackSegmentStartIndices + startIndex,
            )
        } else {
            _snapshot.value = nextSnapshot(trackSegmentStartIndices = snapshot.trackSegmentStartIndices + startIndex)
        }
        filter = LocationTrackFilter(snapshot.activityKind)
        resetAutoPauseProbe()
        return PromotedAutoPauseProbe(promotedDurationNanos)
    }

    private fun resetAutoPauseProbe() {
        autoPauseProbeFilter = null
        autoPauseProbeSamples.clear()
        autoPauseProbeDistanceMeters = 0.0
        autoPauseProbePaceSecondsPerKilometer = null
    }

    private fun autoPauseThreshold(activityKind: ActivityKind): Double = when (activityKind) {
        ActivityKind.CYCLING -> 1.5
        ActivityKind.WALKING, ActivityKind.HIKING -> 0.35
        ActivityKind.RUNNING -> 1.0
        ActivityKind.SWIMMING -> 0.2
    }

    private fun autoResumeThreshold(activityKind: ActivityKind): Double = when (activityKind) {
        ActivityKind.CYCLING -> 2.5
        ActivityKind.WALKING, ActivityKind.HIKING -> 0.75
        ActivityKind.RUNNING -> 1.5
        ActivityKind.SWIMMING -> 0.5
    }

    private fun rebuildProcessors(snapshot: RecordingSnapshot) {
        filter = LocationTrackFilter(snapshot.activityKind)
        elevation = ElevationGainAccumulator()
        snapshot.track.forEach { filter.ingest(it).sample?.let(elevation::ingest) }
    }

    private fun freezeElapsed() {
        val segmentStart = activeSegmentStartedElapsedNanos ?: return
        accumulatedElapsedNanos += (clock.elapsedRealtimeNanos() - segmentStart).coerceAtLeast(0)
    }

    private fun elapsedSeconds(): Long {
        _snapshot.value.runSimulation?.let { return it.elapsedSeconds.toLong() }
        val active = activeSegmentStartedElapsedNanos?.let {
            (clock.elapsedRealtimeNanos() - it).coerceAtLeast(0)
        } ?: 0
        return (accumulatedElapsedNanos + active) / NANOS_PER_SECOND
    }

    private fun nextSnapshot(
        status: RecordingStatus = _snapshot.value.status,
        elapsedSeconds: Long = elapsedSeconds(),
        distanceMeters: Double = _snapshot.value.distanceMeters,
        elevationGainMeters: Double = _snapshot.value.elevationGainMeters,
        currentPaceSecondsPerKilometer: Double? = _snapshot.value.currentPaceSecondsPerKilometer,
        latestLocation: RecordedLocationSample? = _snapshot.value.latestLocation,
        track: List<RecordedLocationSample> = _snapshot.value.track,
        trackSegmentStartIndices: Set<Int> = _snapshot.value.trackSegmentStartIndices,
        autoPaused: Boolean = _snapshot.value.autoPaused,
        runSimulation: RunSimulationState? = _snapshot.value.runSimulation,
    ) = _snapshot.value.copy(
        status = status,
        revision = _snapshot.value.revision + 1,
        recordedAtEpochMilliseconds = clock.utcMillis(),
        elapsedSeconds = elapsedSeconds,
        distanceMeters = distanceMeters,
        elevationGainMeters = elevationGainMeters,
        currentPaceSecondsPerKilometer = currentPaceSecondsPerKilometer,
        latestLocation = latestLocation,
        track = track,
        trackSegmentStartIndices = trackSegmentStartIndices,
        autoPaused = autoPaused,
        runSimulation = runSimulation,
    )

    suspend fun setRunSimulationTimeRate(rate: Int) = serialized("simulation_rate_${UUID.randomUUID()}") {
        if (!BuildConfig.DEBUG || rate !in listOf(1, 10, 60)) return@serialized
        val simulation = _snapshot.value.runSimulation ?: return@serialized
        _snapshot.value = nextSnapshot(runSimulation = simulation.copy(timeRate = rate))
        persist(force = true)
        if (simulation.isClockRunning) startSimulationClock(rate)
    }

    suspend fun adjustRunSimulationSpeed(deltaKilometersPerHour: Double) = serialized("simulation_speed_${UUID.randomUUID()}") {
        if (!BuildConfig.DEBUG) return@serialized
        val simulation = _snapshot.value.runSimulation ?: return@serialized
        val updated = simulation.copy(speedKilometersPerHour = (simulation.speedKilometersPerHour + deltaKilometersPerHour).coerceIn(4.0, 24.0))
        _snapshot.value = nextSnapshot(runSimulation = updated)
        persist(force = true)
    }

    suspend fun toggleRunSimulationClock() = serialized("simulation_clock_${UUID.randomUUID()}") {
        if (!BuildConfig.DEBUG || _snapshot.value.status != RecordingStatus.ACTIVE) return@serialized
        val simulation = _snapshot.value.runSimulation ?: return@serialized
        if (simulation.isComplete) return@serialized
        if (simulation.isClockRunning) stopSimulationClock() else startSimulationClock(simulation.timeRate)
        _snapshot.value = nextSnapshot(runSimulation = simulation.copy(isClockRunning = !simulation.isClockRunning))
        persist(force = true)
    }

    suspend fun advanceRunSimulation(seconds: Int) = serialized("simulation_advance_${UUID.randomUUID()}") {
        if (!BuildConfig.DEBUG || seconds <= 0 || _snapshot.value.status != RecordingStatus.ACTIVE) return@serialized
        val sampler = simulationSampler ?: return@serialized
        var simulation = _snapshot.value.runSimulation ?: return@serialized
        repeat(seconds.coerceAtMost(300)) {
            if (simulation.isComplete) return@repeat
            simulation = simulation.copy(
                elapsedSeconds = simulation.elapsedSeconds + 1,
                distanceMeters = (simulation.distanceMeters + simulation.speedMetersPerSecond).coerceAtMost(simulation.routeDistanceMeters),
            )
            _snapshot.value = nextSnapshot(runSimulation = simulation)
            ingest(sampler.sample(
                simulation.distanceMeters,
                simulation.speedMetersPerSecond,
                simulation.elapsedSeconds,
                _snapshot.value.startedAtEpochMilliseconds ?: clock.utcMillis(),
                simulationStartElapsedRealtimeNanos ?: clock.elapsedRealtimeNanos(),
            ))
            _simulationSnapshots.tryEmit(_snapshot.value.copy(track = emptyList()))
        }
        if (simulation.isComplete) {
            stopSimulationClock()
            _snapshot.value = nextSnapshot(runSimulation = simulation.copy(isClockRunning = false))
        }
        persist(force = true)
    }

    private fun startSimulationClock(rate: Int) {
        simulationClockJob?.cancel()
        simulationClockJob = scope.launch {
            while (true) {
                delay(1_000L / rate)
                advanceRunSimulation(1)
                if (_snapshot.value.runSimulation?.isComplete != false || _snapshot.value.status != RecordingStatus.ACTIVE) break
            }
        }
    }

    private fun stopSimulationClock() {
        simulationClockJob?.cancel()
        simulationClockJob = null
        _snapshot.value.runSimulation?.let { simulation ->
            if (simulation.isClockRunning) _snapshot.value = nextSnapshot(runSimulation = simulation.copy(isClockRunning = false))
        }
    }

    private fun restoredSimulationSampler(snapshot: RecordingSnapshot): RunSimulationRouteSampler? {
        if (!BuildConfig.DEBUG || snapshot.runSimulation == null) return null
        return runCatching { RunSimulationRouteSampler(HarvestRunSimulation.route.points) }.getOrNull()
    }

    private suspend fun persist(force: Boolean) {
        val value = _snapshot.value
        val accountId = value.accountId ?: return
        val sessionId = value.sessionId ?: return
        val now = clock.utcMillis()
        if (!force && now - lastJournalUtcMillis < JOURNAL_INTERVAL_MILLIS) return
        lastJournalUtcMillis = now
        journal.upsert(
            ActiveSessionJournalEntity(
                accountId = accountId,
                sessionId = sessionId,
                activityType = value.activityKind.name.lowercase(),
                status = when (value.status) {
                    RecordingStatus.AWAITING_SAVE -> "awaiting_save"
                    RecordingStatus.IDLE -> "completed"
                    else -> value.status.name.lowercase()
                },
                revision = value.revision,
                startedAtEpochMs = value.startedAtEpochMilliseconds ?: now,
                updatedAtEpochMs = now,
                stateJson = json.encodeToString(value),
            ),
        )
    }

    private suspend fun ignored(commandId: String, reason: String) {
        _events.emit(RecordingEvent.CommandIgnored(commandId, reason))
    }

    private companion object {
        const val NANOS_PER_SECOND = 1_000_000_000L
        const val AUTO_PAUSE_WARMUP_NANOS = 10L * NANOS_PER_SECOND
        const val AUTO_PAUSE_DURATION_NANOS = 12L * NANOS_PER_SECOND
        const val AUTO_RESUME_DURATION_NANOS = 6L * NANOS_PER_SECOND
        const val MAX_PROBE_INTERVAL_NANOS = 30L * NANOS_PER_SECOND
        const val MAX_SPEED_SAMPLE_AGE_NANOS = 10L * NANOS_PER_SECOND
        const val JOURNAL_INTERVAL_MILLIS = 10_000L
        const val MAX_COMMAND_HISTORY = 128
    }

    private data class PromotedAutoPauseProbe(val durationNanos: Long)
}

private fun durationBucket(seconds: Long): String = when {
    seconds < 60 -> "under_1m"
    seconds < 300 -> "1_5m"
    seconds < 1_800 -> "5_30m"
    seconds < 3_600 -> "30_60m"
    else -> "60m_plus"
}

private fun distanceBucket(meters: Double): String = when {
    meters < 500 -> "under_500m"
    meters < 1_000 -> "500m_1k"
    meters < 5_000 -> "1_5k"
    meters < 10_000 -> "5_10k"
    else -> "10k_plus"
}
