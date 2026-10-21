package com.plainstride.outbound.feature.livecoach.policy

import kotlin.math.abs
import kotlin.math.max

/** Distinct trusted GPS speed evidence, independent of profile and display pace. */
class SuddenSpeedChangeDetector {
    private data class Sample(val second: Int, val evidence: Long, val speed: Double)
    private val samples = mutableListOf<Sample>()
    private var baseline: Double? = null
    private var candidateSince: Int? = null
    private var candidateDirection: Int? = null
    private var lastAlert: Int? = null
    private var segment: String? = null
    fun resetEvidence() { samples.clear(); baseline = null; candidateSince = null; candidateDirection = null }
    fun ingest(second: Int, evidence: Long?, speed: Double?, segmentId: String?, phase: String?, segmentSeconds: Int?): Int? {
        if (segment != segmentId) { resetEvidence(); segment = segmentId }
        if (evidence == null || speed == null || !speed.isFinite() || speed !in 0.0..15.0) { resetEvidence(); return null }
        samples.lastOrNull()?.let { last ->
            if (evidence == last.evidence) return null
            if (evidence < last.evidence || evidence - last.evidence > 5000 || second <= last.second || second - last.second > 5) resetEvidence()
        }
        samples += Sample(second, evidence, speed)
        samples.removeAll { it.second < second - 25 }
        if (segmentSeconds != null && segmentSeconds < 30) { baseline = null; candidateSince = null; return null }
        if (lastAlert?.let { second-it < 60 } == true) {
            baseline = null; candidateSince = null; candidateDirection = null; return null
        }
        val recent = samples.filter { it.second >= second - 4 }
        if (recent.size < 4 || second - recent.first().second < 3) return null
        fun median(values: List<Double>): Double { val s = values.sorted(); return (s[(s.size-1)/2]+s[s.size/2])/2 }
        val current = median(recent.map { it.speed })
        val reference = baseline ?: run {
            val earlier = samples.filter { it.second in second-24..second-5 }
            if (earlier.size < 8 || earlier.last().second - earlier.first().second < 14) return null
            val value = median(earlier.map { it.speed })
            if (value < 1.5 || earlier.any { abs(it.speed-value) > value*0.2 }) return null
            value
        }
        val delta = current-reference
        val direction = if (delta > 0) 1 else -1
        if (abs(delta) < max(reference*0.4,3.0/3.6) || (direction < 0 && phase in setOf("warmup","recovery","cooldown","walk"))) {
            baseline = null; candidateSince = null; candidateDirection = null; return null
        }
        if (candidateDirection != direction) { baseline = reference; candidateSince = second; candidateDirection = direction }
        if (second - (candidateSince ?: second) < 5 || lastAlert?.let { second-it < 60 } == true) return null
        lastAlert = second
        resetEvidence()
        return direction
    }
}
