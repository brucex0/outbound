package com.plainstride.outbound.feature.recording

import kotlinx.serialization.Serializable

/** Unknown observations and background gaps count as moving time. */
@Serializable
data class MovingTimeTracker(
    val stoppedSeconds: Long = 0,
    val candidateSeconds: Long = 0,
    val lastActiveSeconds: Long? = null,
) {
    fun update(activeSeconds: Long, stationary: Boolean?): MovingTimeTracker {
        val delta = lastActiveSeconds?.let { activeSeconds - it }
        if (delta == null || delta !in 0..5 || stationary != true)
            return copy(candidateSeconds = 0, lastActiveSeconds = activeSeconds)
        val candidate = candidateSeconds + delta
        return copy(
            candidateSeconds = candidate,
            lastActiveSeconds = activeSeconds,
            stoppedSeconds = stoppedSeconds + if (candidate >= 10) {
                if (candidateSeconds < 10) candidate else delta
            } else 0,
        )
    }
    fun suspend() = copy(candidateSeconds = 0, lastActiveSeconds = null)
}
