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

    private var tickJob: Job? = null
    private var locationJob: Job? = null
    private var activeSegmentStartedElapsedNanos: Long? = null
    private var accumulatedElapsedNanos = 0L
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
            revision = entity.revision,
            recordedAtEpochMilliseconds = clock.utcMillis(),
            recovered = true,
        )
        _events.emit(RecordingEvent.CommandApplied(commandId, _snapshot.value.status))
    }

    suspend fun start(
        commandId: String,
        accountId: String,
        activityKind: ActivityKind,
        sessionId: String = UUID.randomUUID().toString(),
        companionType: ActivityCompanionType? = null,
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
                    revision = existing.revision,
                    recordedAtEpochMilliseconds = clock.utcMillis(),
                    recovered = true,
                )
                ignored(commandId, if (existing.sessionId == sessionId) "duplicate_start" else "recoverable_session_exists")
                return@serialized
            }
        }
        val nowUtc = clock.utcMillis()
        filter = LocationTrackFilter(activityKind)
        elevation = ElevationGainAccumulator()
        accumulatedElapsedNanos = 0
        activeSegmentStartedElapsedNanos = clock.elapsedRealtimeNanos()
        _snapshot.value = RecordingSnapshot(
            sessionId = sessionId,
            accountId = accountId,
            activityKind = activityKind,
            status = RecordingStatus.ACTIVE,
            revision = 1,
            startedAtEpochMilliseconds = nowUtc,
            recordedAtEpochMilliseconds = nowUtc,
            companionType = companionType,
        )
        beginCollection()
        persist(force = true)
        analytics.record(
            AnalyticsEvent(
                name = "activity_recording_started",
                properties = mapOf(
                    AnalyticsProperty.ActivityType to activityKind.name.lowercase(),
                    AnalyticsProperty.Permission to permissionState.value.name.lowercase(),
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
        freezeElapsed()
        activeSegmentStartedElapsedNanos = null
        _snapshot.value = nextSnapshot(status = RecordingStatus.PAUSED)
        stopCollection()
        persist(force = true)
        analytics.record(AnalyticsEvent("activity_recording_paused", mapOf(AnalyticsProperty.Trigger to "manual")))
        _events.emit(RecordingEvent.CommandApplied(commandId, RecordingStatus.PAUSED))
    }

    suspend fun resume(commandId: String) = serialized(commandId) {
        if (_snapshot.value.status != RecordingStatus.PAUSED) {
            ignored(commandId, "session_not_paused")
            return@serialized
        }
        activeSegmentStartedElapsedNanos = clock.elapsedRealtimeNanos()
        _snapshot.value = nextSnapshot(status = RecordingStatus.ACTIVE)
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
        activeSegmentStartedElapsedNanos = null
        stopCollection()
        val finished = nextSnapshot(status = RecordingStatus.AWAITING_SAVE)
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
        current.accountId?.let { account -> current.sessionId?.let { journal.delete(account, it) } }
        _snapshot.value = RecordingSnapshot(recordedAtEpochMilliseconds = clock.utcMillis())
        accumulatedElapsedNanos = 0
        activeSegmentStartedElapsedNanos = null
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
        _snapshot.value = RecordingSnapshot(recordedAtEpochMilliseconds = clock.utcMillis())
        accumulatedElapsedNanos = 0
        activeSegmentStartedElapsedNanos = null
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
        locationSource.start()
        locationJob?.cancel()
        locationJob = scope.launch {
            locationSource.samples.collect { raw -> mutex.withLock { ingest(raw) } }
        }
        tickJob?.cancel()
        tickJob = scope.launch {
            while (true) {
                delay(1_000)
                mutex.withLock {
                    if (_snapshot.value.status == RecordingStatus.ACTIVE) {
                        _snapshot.value = nextSnapshot()
                        persist(force = false)
                    }
                }
            }
        }
        if (permissionState.value == LocationPermissionState.DENIED ||
            permissionState.value == LocationPermissionState.NOT_REQUESTED
        ) _events.tryEmit(RecordingEvent.LocationUnavailable(permissionState.value))
    }

    private fun stopCollection() {
        tickJob?.cancel()
        tickJob = null
        locationJob?.cancel()
        locationJob = null
        locationSource.stop()
    }

    private suspend fun ingest(raw: RecordedLocationSample) {
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
    )

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
        const val JOURNAL_INTERVAL_MILLIS = 10_000L
        const val MAX_COMMAND_HISTORY = 128
    }
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
