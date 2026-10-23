package com.plainstride.outbound.feature.recording

import android.util.Log
import java.util.UUID
import com.plainstride.outbound.feature.social.SocialException
import com.plainstride.outbound.feature.social.SocialRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/** Service-owned presence survives UI navigation and includes paused recordings, as on iOS. */
internal class WorkoutPresenceController(private val repository: SocialRepository) {
    fun observe(snapshots: StateFlow<RecordingSnapshot>, scope: CoroutineScope) = scope.launch {
        snapshots.map { snapshot ->
            snapshot.sessionId.takeIf { snapshot.status == RecordingStatus.ACTIVE || snapshot.status == RecordingStatus.PAUSED }
        }.distinctUntilChanged().collectLatest { recordingSessionId ->
            if (recordingSessionId == null) return@collectLatest
            // A fresh presence identity prevents a delayed teardown from clearing a recovered session.
            val sessionId = UUID.randomUUID().toString()
            try {
                while (true) {
                    update(sessionId, active = true)
                    delay(60_000)
                }
            } finally {
                // Finish/delete must follow an in-flight heartbeat, including service teardown.
                // A failed end is bounded by the backend's three-minute presence expiry.
                withContext(NonCancellable) {
                    if (withTimeoutOrNull(15_000) { update(sessionId, active = false); true } == null) {
                        Log.w(TAG, "workout_presence_end failed category=timeout")
                    }
                }
            }
        }
    }

    private suspend fun update(sessionId: String, active: Boolean) {
        val operation = if (active) "heartbeat" else "end"
        try {
            val result = repository.setWorkoutPresence(sessionId, active)
            currentCoroutineContext().ensureActive()
            result.onFailure { logFailure(operation, it) }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            logFailure(operation, error)
        }
    }

    private fun logFailure(operation: String, error: Throwable) {
        if (error is CancellationException) throw error
        Log.w(TAG, "workout_presence_$operation failed category=${(error as? SocialException)?.reason ?: error.javaClass.simpleName} status=${(error as? SocialException)?.httpStatus}")
    }

    private companion object { const val TAG = "PlainstridePresence" }
}
