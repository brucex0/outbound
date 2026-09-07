package run.plainstride.wear

import android.app.*
import android.content.*
import androidx.core.app.NotificationCompat
import androidx.health.services.client.ExerciseUpdateCallback
import androidx.health.services.client.HealthServices
import androidx.health.services.client.data.*
import androidx.lifecycle.LifecycleService
import androidx.lifecycle.lifecycleScope
import java.util.concurrent.Executors
import kotlinx.coroutines.launch
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import run.plainstride.core.model.activity.*

class ExerciseService : LifecycleService() {
    private val client by lazy { HealthServices.getClient(this).exerciseClient }
    private val prefs by lazy { getSharedPreferences("wear_session", MODE_PRIVATE) }
    private val executor = Executors.newSingleThreadExecutor()
    private var state: SessionStateEnvelope? = null
    private val callback = object : ExerciseUpdateCallback {
        override fun onExerciseUpdateReceived(update: ExerciseUpdate) {
            val old = state ?: return
            val distance = update.latestMetrics.getData(DataType.DISTANCE_TOTAL)?.total ?: old.distanceMeters
            val heartRate = update.latestMetrics.getData(DataType.HEART_RATE_BPM).lastOrNull()?.value ?: old.heartRateBpm
            val location = update.latestMetrics.getData(DataType.LOCATION).lastOrNull()
            val now = System.currentTimeMillis()
            location?.value?.let { fix -> trackFile(old.sessionId).appendText(Json.encodeToString(WearTrackPoint(now, fix.latitude, fix.longitude, fix.altitude.takeIf { it.isFinite() && it in -500.0..10_000.0 })) + "\n") }
            store(old.copy(distanceMeters = distance, heartRateBpm = heartRate, elapsedSeconds = (now - old.startedAtEpochMs) / 1000, revision = old.revision + 1, updatedAtEpochMs = now))
        }
        override fun onLapSummaryReceived(lapSummary: ExerciseLapSummary) = Unit
        override fun onAvailabilityChanged(dataType: DataType<*, *>, availability: Availability) = Unit
        override fun onRegistered() = Unit
        override fun onRegistrationFailed(throwable: Throwable) = stopSelf()
    }

    override fun onCreate() {
        super.onCreate(); createChannel()
        state = prefs.getString("state", null)?.let { runCatching { Json.decodeFromString<SessionStateEnvelope>(it) }.getOrNull() }
        state?.let { WearSessionStateStore.state.value = it }
        client.setUpdateCallback(executor, callback)
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId); startForeground(10, notification())
        intent?.getStringExtra(EXTRA)?.let { runCatching { Json.decodeFromString<SessionCommandEnvelope>(it) }.getOrNull() }?.let(::handle)
        return START_STICKY
    }
    private fun handle(command: SessionCommandEnvelope) {
        val old = state
        if (command.commandId in (old?.handledCommandIds ?: emptyList())) return
        if (old != null && old.owner != command.owner && old.phase != SessionPhase.FINISHED) return
        lifecycleScope.launch {
            withContext(Dispatchers.IO) { when (command.command) {
                SessionProtocolCommand.START, SessionProtocolCommand.CLAIM_OWNER -> {
                    trackFile(command.sessionId).delete()
                    client.startExerciseAsync(ExerciseConfig.builder(ExerciseType.RUNNING).setDataTypes(setOf(DataType.DISTANCE_TOTAL, DataType.HEART_RATE_BPM, DataType.LOCATION)).setIsAutoPauseAndResumeEnabled(false).build()).get()
                    store(SessionStateEnvelope(command.sessionId, SessionOwner.WATCH, SessionPhase.ACTIVE, command.revision, System.currentTimeMillis(), 0, 0.0, null, System.currentTimeMillis(), listOf(command.commandId)))
                }
                SessionProtocolCommand.PAUSE -> { client.pauseExerciseAsync().get(); transition(command, SessionPhase.PAUSED) }
                SessionProtocolCommand.RESUME -> { client.resumeExerciseAsync().get(); transition(command, SessionPhase.ACTIVE) }
                SessionProtocolCommand.FINISH, SessionProtocolCommand.RELEASE_OWNER -> { client.endExerciseAsync().get(); finish(command); stopSelf() }
            } }
        }
    }
    private fun transition(command: SessionCommandEnvelope, phase: SessionPhase) = state?.let { store(it.copy(phase = phase, revision = maxOf(it.revision + 1, command.revision), updatedAtEpochMs = System.currentTimeMillis(), handledCommandIds = (it.handledCommandIds + command.commandId).takeLast(64))) }
    private suspend fun finish(command: SessionCommandEnvelope) {
        val current = state ?: return
        val points = trackFile(current.sessionId).takeIf { it.exists() }?.useLines { lines -> lines.mapNotNull { runCatching { Json.decodeFromString<WearTrackPoint>(it) }.getOrNull() }.toList() }.orEmpty()
        val chunks = points.chunked(200)
        chunks.forEachIndexed { index, chunk -> WearSessionGatewayImpl.publishTrack(this, WearTrackChunk(current.sessionId, index, chunk)) }
        val finished = current.copy(phase = SessionPhase.FINISHED, revision = maxOf(current.revision + 1, command.revision), updatedAtEpochMs = System.currentTimeMillis(), handledCommandIds = (current.handledCommandIds + command.commandId).takeLast(64), trackChunkCount = chunks.size)
        state = finished
        WearSessionStateStore.state.value = finished
        prefs.edit().putString("state", Json.encodeToString(finished)).commit()
        WearSessionGatewayImpl.publish(this, finished)
    }
    private fun trackFile(sessionId: String) = java.io.File(filesDir, "track-$sessionId.jsonl")
    private fun store(value: SessionStateEnvelope) {
        state = value; WearSessionStateStore.state.value = value
        prefs.edit().putString("state", Json.encodeToString(value)).apply()
        lifecycleScope.launch { runCatching { WearSessionGatewayImpl.publish(this@ExerciseService, value) } }
    }
    private fun notification() = NotificationCompat.Builder(this, CHANNEL).setSmallIcon(R.drawable.ic_plainstride).setContentTitle(getString(R.string.workout_in_progress)).setOngoing(true).setContentIntent(PendingIntent.getActivity(this, 0, Intent(this, WearMainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)).build()
    private fun createChannel() = getSystemService(NotificationManager::class.java).createNotificationChannel(NotificationChannel(CHANNEL, getString(R.string.workout_channel), NotificationManager.IMPORTANCE_LOW))
    override fun onDestroy() { client.clearUpdateCallbackAsync(callback); executor.shutdown(); super.onDestroy() }
    companion object {
        private const val EXTRA = "command"; private const val CHANNEL = "workout"
        fun start(context: Context, command: SessionCommandEnvelope) { context.startForegroundService(intent(context, command)) }
        fun command(context: Context, command: SessionCommandEnvelope) { context.startService(intent(context, command)) }
        private fun intent(context: Context, command: SessionCommandEnvelope) = Intent(context, ExerciseService::class.java).putExtra(EXTRA, Json.encodeToString(command))
    }
}
