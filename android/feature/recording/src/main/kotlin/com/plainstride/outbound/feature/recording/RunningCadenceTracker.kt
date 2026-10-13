package com.plainstride.outbound.feature.recording

import com.plainstride.outbound.core.model.activity.ActivityCadenceSample
import com.plainstride.outbound.core.model.activity.ActivityCadenceSummary
import kotlinx.serialization.Serializable
import kotlin.math.roundToInt

@Serializable
data class RunningCadenceState(
    val weightedTotal: Double = 0.0,
    val measuredSeconds: Double = 0.0,
    val maximum: Int = 0,
    val segment: Int = 0,
    val samples: List<ActivityCadenceSample> = emptyList(),
) {
    fun summary(): ActivityCadenceSummary? = if (measuredSeconds > 0) ActivityCadenceSummary(
        (weightedTotal / measuredSeconds).roundToInt(), maximum, samples,
    ) else null
}

/** Event time is monotonic; pauses, recovery and signal gaps cannot bridge intervals. */
internal class RunningCadenceTracker {
    var state = RunningCadenceState()
        private set
    private val recent = ArrayDeque<Long>()
    private var segmentStartedAtNanos = Long.MAX_VALUE
    private var lastStepNanos: Long? = null
    private var live: Int? = null

    fun restore(saved: RunningCadenceState?) {
        state = saved ?: RunningCadenceState()
        suspend()
    }

    fun begin(nowNanos: Long) {
        suspend()
        state = state.copy(segment = state.segment + 1)
        segmentStartedAtNanos = nowNanos
    }

    fun suspend() {
        recent.clear()
        lastStepNanos = null
        live = null
        segmentStartedAtNanos = Long.MAX_VALUE
    }

    fun current(nowNanos: Long): Int? = lastStepNanos?.let { lastStep ->
        live?.takeIf { nowNanos - lastStep in 0..10_000_000_000L }
    }

    fun ingest(stepNanos: Long, activeSeconds: Long, nowNanos: Long) {
        if (stepNanos < segmentStartedAtNanos || nowNanos - stepNanos !in 0..10_000_000_000L) return
        val previous = lastStepNanos
        if (previous != null && stepNanos <= previous) return
        val interval = previous?.let { (stepNanos - it) / 1_000_000_000.0 }
        if (interval != null && interval !in 0.2..2.0) {
            recent.clear()
            live = null
            state = state.copy(segment = state.segment + 1)
        }
        lastStepNanos = stepNanos
        while (recent.isNotEmpty() && stepNanos - recent.first() > 5_000_000_000L) recent.removeFirst()
        recent.addLast(stepNanos)
        if (recent.size < 4 || stepNanos - recent.first() < 1_000_000_000L) return
        val smoothed = ((recent.size - 1) * 60_000_000_000.0 / (stepNanos - recent.first())).roundToInt()
        if (smoothed !in 1..300 || interval == null || interval !in 0.2..2.0) return
        live = smoothed
        val elapsed = activeSeconds.coerceIn(0, Int.MAX_VALUE.toLong()).toInt()
        val last = state.samples.lastOrNull()
        val sample = ActivityCadenceSample(elapsed, smoothed, state.segment)
        state = state.copy(
            weightedTotal = state.weightedTotal + 60.0,
            measuredSeconds = state.measuredSeconds + interval,
            maximum = maxOf(state.maximum, (60.0 / interval).roundToInt()),
            samples = if (last == null || last.segment != state.segment || elapsed - last.elapsedSeconds >= 5)
                state.samples + sample else state.samples,
        )
    }
}
