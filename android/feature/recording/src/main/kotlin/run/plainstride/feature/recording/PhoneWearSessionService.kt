package run.plainstride.feature.recording

import com.google.android.gms.wearable.*
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.tasks.await
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import run.plainstride.core.model.activity.*
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject
import java.time.Instant
import run.plainstride.core.auth.SessionCoordinator
import run.plainstride.core.auth.SessionState
import run.plainstride.core.data.*

/** Phone bridge that owns protocol coordination and durably imports completed watch workouts. */
@AndroidEntryPoint
class PhoneWearSessionService : WearableListenerService() {
    @Inject lateinit var activities: ActivityRepository
    @Inject lateinit var sessions: SessionCoordinator
    @Inject lateinit var sync: ActivitySyncScheduler
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val client by lazy { RecordingSessionClient(this).apply { connect() } }
    private val handled = ConcurrentHashMap.newKeySet<String>()
    @Volatile private var phoneState: SessionStateEnvelope? = null

    override fun onCreate() {
        super.onCreate()
        getSharedPreferences(PREFS, MODE_PRIVATE).getStringSet(HANDLED, emptySet())?.let(handled::addAll)
        scope.launch { client.snapshots.collectLatest { snapshot ->
            if (snapshot.sessionId != null) {
                phoneState = snapshot.toProtocol()
                publish(phoneState!!)
            }
        } }
    }

    override fun onMessageReceived(event: MessageEvent) {
        if (event.path != COMMAND_PATH) return
        val command = runCatching { Json.decodeFromString<SessionCommandEnvelope>(event.data.decodeToString()) }.getOrNull() ?: return
        if (!handled.add(command.commandId)) return
        persistHandled()
        val current = phoneState
        // An active phone recording is authoritative; a watch cannot claim a second workout.
        if (current != null && current.phase != SessionPhase.FINISHED && current.owner == SessionOwner.PHONE && command.owner != SessionOwner.PHONE) {
            scope.launch { publish(current.copy(revision = maxOf(current.revision + 1, command.revision))) }
            return
        }
        if (command.owner == SessionOwner.PHONE) when (command.command) {
            SessionProtocolCommand.PAUSE -> client.pause(command.commandId)
            SessionProtocolCommand.RESUME -> client.resume(command.commandId)
            SessionProtocolCommand.FINISH, SessionProtocolCommand.RELEASE_OWNER -> client.finish(command.commandId)
            else -> Unit // Starting requires the phone's account and permission gate.
        }
        // Watch-owned sessions are mirrored, never recorded again on the phone.
        if (command.owner == SessionOwner.WATCH) {
            val phase = when (command.command) { SessionProtocolCommand.START, SessionProtocolCommand.RESUME, SessionProtocolCommand.CLAIM_OWNER -> SessionPhase.ACTIVE; SessionProtocolCommand.PAUSE -> SessionPhase.PAUSED; else -> SessionPhase.FINISHED }
            val mirrored = SessionStateEnvelope(command.sessionId, SessionOwner.WATCH, phase, command.revision, System.currentTimeMillis(), 0, 0.0, null, System.currentTimeMillis(), listOf(command.commandId))
            getSharedPreferences(PREFS, MODE_PRIVATE).edit().putString(WATCH_STATE, Json.encodeToString(mirrored)).apply()
        }
    }

    override fun onDataChanged(events: DataEventBuffer) {
        events.forEach { event ->
            if (event.dataItem.uri.path != STATE_PATH || event.type != DataEvent.TYPE_CHANGED) return@forEach
            val encoded = DataMapItem.fromDataItem(event.dataItem).dataMap.getString(STATE_KEY) ?: return@forEach
            val state = runCatching { Json.decodeFromString<SessionStateEnvelope>(encoded) }.getOrNull() ?: return@forEach
            if (state.owner == SessionOwner.WATCH) {
                getSharedPreferences(PREFS, MODE_PRIVATE).edit().putString(WATCH_STATE, encoded).apply()
                if (state.phase == SessionPhase.FINISHED) scope.launch { importFinished(state) }
            }
        }
    }

    private suspend fun importFinished(state: SessionStateEnvelope) {
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        if (prefs.getStringSet(IMPORTED, emptySet())?.contains(state.sessionId) == true) return
        val accountId = (sessions.state.value as? SessionState.SignedIn)?.accountId ?: return
        val saved = RecordedActivityFactory.create(RecordedActivityDraft(
            sessionId = state.sessionId, accountId = accountId, type = run.plainstride.core.model.activity.ActivityType.running,
            title = getString(R.string.recording_default_activity_title), startedAtEpochMs = state.startedAtEpochMs,
            endedAtEpochMs = state.updatedAtEpochMs, durationSecs = state.elapsedSeconds.coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
            distanceM = state.distanceMeters, elevationGainM = 0.0,
            track = state.track.mapIndexed { index, point -> RecordedTrackPointDraft(point.timestampEpochMs, point.latitude, point.longitude, point.altitudeMeters, null, index == 0) },
        ), Instant.now()).copy(averageHeartRateBpm = state.heartRateBpm?.toInt())
        activities.save(saved)
        prefs.edit().putStringSet(IMPORTED, (prefs.getStringSet(IMPORTED, emptySet()).orEmpty() + state.sessionId).toList().takeLast(128).toSet()).apply()
        sync.schedule(accountId)
    }

    override fun onPeerConnected(peer: Node) { phoneState?.let { scope.launch { publish(it) } } }
    private suspend fun publish(state: SessionStateEnvelope) {
        val request = PutDataMapRequest.create(STATE_PATH).apply { dataMap.putString(STATE_KEY, Json.encodeToString(state)); dataMap.putLong("revision", state.revision) }.asPutDataRequest().setUrgent()
        Wearable.getDataClient(this).putDataItem(request).await()
    }
    private fun persistHandled() = getSharedPreferences(PREFS, MODE_PRIVATE).edit().putStringSet(HANDLED, handled.toList().takeLast(128).toSet()).apply()
    override fun onDestroy() { client.close(); scope.cancel(); super.onDestroy() }

    private fun RecordingSnapshot.toProtocol() = SessionStateEnvelope(
        sessionId = requireNotNull(sessionId), owner = SessionOwner.PHONE,
        phase = when (status) { RecordingStatus.ACTIVE -> SessionPhase.ACTIVE; RecordingStatus.PAUSED, RecordingStatus.AWAITING_SAVE -> SessionPhase.PAUSED; RecordingStatus.IDLE -> SessionPhase.FINISHED },
        revision = revision, startedAtEpochMs = startedAtEpochMilliseconds ?: recordedAtEpochMilliseconds,
        elapsedSeconds = elapsedSeconds, distanceMeters = distanceMeters, heartRateBpm = null,
        updatedAtEpochMs = recordedAtEpochMilliseconds,
    )

    companion object {
        const val COMMAND_PATH = "/plainstride/session/command"; const val STATE_PATH = "/plainstride/session/state"; const val STATE_KEY = "state"
        private const val PREFS = "phone_wear_session"; private const val HANDLED = "handled"; private const val WATCH_STATE = "watch_state"; private const val IMPORTED = "imported_sessions"
    }
}
