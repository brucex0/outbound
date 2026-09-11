package com.plainstride.outbound.feature.livecoach.policy

import com.plainstride.outbound.feature.livecoach.network.CoachingContract
import com.plainstride.outbound.feature.livecoach.network.LiveCoachMoment
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

data class CoachSnapshot(
    val elapsedSeconds: Int,
    val distanceMeters: Double,
    val paceSecondsPerKilometer: Double?,
    val targetPaceSecondsPerKilometer: Double? = null,
    val fasterToleranceSeconds: Double? = null,
    val slowerToleranceSeconds: Double? = null,
    val recognizesTargetLock: Boolean = false,
    val segmentIndex: Int? = null,
    val segmentPhase: String? = null,
    val segmentElapsedSeconds: Int? = null,
    val targetDistanceMeters: Double? = null,
    val targetDurationSeconds: Int? = null,
    val isRunning: Boolean = true,
    val latitude: Double? = null,
    val longitude: Double? = null,
    val altitudeMeters: Double? = null,
    val horizontalAccuracyMeters: Double? = null,
    val verticalAccuracyMeters: Double? = null,
)

data class DetectedMoment(
    val moment: LiveCoachMoment,
    val detectedAtElapsedSeconds: Int,
    val baselinePaceSecondsPerKilometer: Double? = null,
    val targetPaceSecondsPerKilometer: Double? = null,
    val evaluationDelaySeconds: Int = 75,
    val preferredText: String? = null,
    val instructionId: String? = null,
    val fixedCueKey: String? = null,
)

enum class CueOutcome(val wireValue: String) {
    Pending("pending"),
    Stabilized("stabilized"),
    Improved("improved"),
    Unchanged("unchanged"),
    Worsened("worsened"),
    NotMeasured("not_measured"),
}

data class EvaluatedCue(val moment: LiveCoachMoment, val outcome: CueOutcome)
data class PolicyUpdate(val nextMoment: DetectedMoment?, val evaluatedCues: List<EvaluatedCue>)

/** Pure bounded state machine matching the iOS live-guidance detector where Android has the same signals. */
class LiveCoachMomentPolicy {
    private data class CueRecord(
        val moment: LiveCoachMoment,
        val spokenAt: Int,
        val baseline: Double?,
        val target: Double?,
        val delay: Int,
        var outcome: CueOutcome,
    )

    private val history = ArrayDeque<CoachSnapshot>()
    private val records = mutableListOf<CueRecord>()
    private val oneShots = mutableSetOf<LiveCoachMoment>()
    private val segmentMoments = mutableSetOf<String>()
    private var lastMomentAt: Int? = null
    private var lastDriftAt: Int? = null
    private var lastInstabilityAt: Int? = null
    private var onClimb = false
    private var climbCandidateStartMeters: Double? = null
    var rollingGradePercent: Double? = null
        private set

    val helpfulCueCount: Int get() = records.count { it.outcome == CueOutcome.Stabilized || it.outcome == CueOutcome.Improved }

    fun reset() {
        history.clear()
        records.clear()
        oneShots.clear()
        segmentMoments.clear()
        lastMomentAt = null
        lastDriftAt = null
        lastInstabilityAt = null
        onClimb = false
        climbCandidateStartMeters = null
        rollingGradePercent = null
    }

    fun ingest(snapshot: CoachSnapshot, contract: CoachingContract): PolicyUpdate {
        val pace = snapshot.paceSecondsPerKilometer?.takeIf { it.isFinite() && it in 60.0..3_600.0 }
        history.addLast(snapshot.copy(paceSecondsPerKilometer = pace))
        while (history.size > MAX_HISTORY) history.removeFirst()
        rollingGradePercent = terrainGrade(history.filter { it.elapsedSeconds >= snapshot.elapsedSeconds - 45 })

        val evaluation = evaluatePending(snapshot)
        evaluation.recovery?.let { return PolicyUpdate(it, evaluation.records) }

        val cooldown = when (contract) {
            CoachingContract.Quiet -> return PolicyUpdate(null, evaluation.records)
            CoachingContract.Responsive -> 180
            CoachingContract.CoachMe -> 90
        }
        if (lastMomentAt?.let { snapshot.elapsedSeconds - it < cooldown } == true) {
            return PolicyUpdate(null, evaluation.records)
        }

        val grade = rollingGradePercent
        val moment = terrain(snapshot, grade)
            ?: earlyOverpace(snapshot, contract, grade)
            ?: targetDeviation(snapshot, grade)
            ?: finish(snapshot)
            ?: drift(snapshot, contract, grade)
            ?: instability(snapshot, grade)
            ?: targetLocked(snapshot, grade)
        if (moment != null) lastMomentAt = snapshot.elapsedSeconds
        return PolicyUpdate(moment, evaluation.records)
    }

    fun recordSpoken(moment: DetectedMoment) {
        val measurable = moment.baselinePaceSecondsPerKilometer != null && moment.targetPaceSecondsPerKilometer != null
        records += CueRecord(
            moment = moment.moment,
            spokenAt = moment.detectedAtElapsedSeconds,
            baseline = moment.baselinePaceSecondsPerKilometer,
            target = moment.targetPaceSecondsPerKilometer,
            delay = moment.evaluationDelaySeconds,
            outcome = if (measurable) CueOutcome.Pending else CueOutcome.NotMeasured,
        )
    }

    fun rollingPaceSecondsPerKilometer(): Double? = history.takeLast(6)
        .mapNotNull { it.paceSecondsPerKilometer }
        .takeIf(List<Double>::isNotEmpty)
        ?.average()

    private fun earlyOverpace(s: CoachSnapshot, contract: CoachingContract, grade: Double?): DetectedMoment? {
        if (s.elapsedSeconds !in 75..240 || meaningfulGrade(grade) || LiveCoachMoment.EarlyOverpace in oneShots) return null
        val target = s.targetPaceSecondsPerKilometer ?: return null
        val recent = averagePace(s.elapsedSeconds - 30, s.elapsedSeconds) ?: return null
        val threshold = s.fasterToleranceSeconds ?: if (contract == CoachingContract.CoachMe) 15.0 else 25.0
        if (target - recent < threshold) return null
        oneShots += LiveCoachMoment.EarlyOverpace
        return DetectedMoment(LiveCoachMoment.EarlyOverpace, s.elapsedSeconds, recent, target)
    }

    private fun targetDeviation(s: CoachSnapshot, grade: Double?): DetectedMoment? {
        if ((s.segmentElapsedSeconds ?: 0) < 45 || meaningfulGrade(grade)) return null
        val target = s.targetPaceSecondsPerKilometer ?: return null
        val recent = averagePace(s.elapsedSeconds - 30, s.elapsedSeconds) ?: return null
        val isRecovery = s.segmentPhase in setOf("recovery", "warmup", "cooldown")
        val above = if (isRecovery) LiveCoachMoment.RecoveryTooHard else LiveCoachMoment.PaceAboveTarget
        val key = segmentKey(above, s)
        if (target - recent >= (s.fasterToleranceSeconds ?: 25.0) && key !in segmentMoments) {
            segmentMoments += key
            return DetectedMoment(above, s.elapsedSeconds, recent, target)
        }
        val belowKey = segmentKey(LiveCoachMoment.PaceBelowTarget, s)
        val slowerTolerance = s.slowerToleranceSeconds
        if (slowerTolerance != null && recent - target >= slowerTolerance && belowKey !in segmentMoments) {
            segmentMoments += belowKey
            return DetectedMoment(LiveCoachMoment.PaceBelowTarget, s.elapsedSeconds, recent, target)
        }
        return null
    }

    private fun drift(s: CoachSnapshot, contract: CoachingContract, grade: Double?): DetectedMoment? {
        if (s.elapsedSeconds < 300 || s.segmentPhase in setOf("work", "recovery") || meaningfulGrade(grade)) return null
        if (lastDriftAt?.let { s.elapsedSeconds - it < 600 } == true) return null
        val earlier = averagePace(s.elapsedSeconds - 100, s.elapsedSeconds - 45) ?: return null
        val recent = averagePace(s.elapsedSeconds - 30, s.elapsedSeconds) ?: return null
        val threshold = if (contract == CoachingContract.CoachMe) 18.0 else 25.0
        if (recent - earlier < threshold) return null
        lastDriftAt = s.elapsedSeconds
        return DetectedMoment(LiveCoachMoment.PaceDrift, s.elapsedSeconds, recent, earlier)
    }

    private fun instability(s: CoachSnapshot, grade: Double?): DetectedMoment? {
        if ((s.segmentElapsedSeconds ?: 0) < 120 || meaningfulGrade(grade)) return null
        if (lastInstabilityAt?.let { s.elapsedSeconds - it < 600 } == true) return null
        val target = s.targetPaceSecondsPerKilometer ?: return null
        val values = paceValues(s.elapsedSeconds - 90, s.elapsedSeconds)
        if (values.size < 8) return null
        val sorted = values.sorted()
        val spread = percentile(.9, sorted) - percentile(.1, sorted)
        if (spread < max(60.0, target * .15)) return null
        lastInstabilityAt = s.elapsedSeconds
        return DetectedMoment(LiveCoachMoment.PaceInstability, s.elapsedSeconds, values.average(), target)
    }

    private fun targetLocked(s: CoachSnapshot, grade: Double?): DetectedMoment? {
        if (!s.recognizesTargetLock || (s.segmentElapsedSeconds ?: 0) < 90 || meaningfulGrade(grade)) return null
        val key = segmentKey(LiveCoachMoment.TargetLocked, s)
        if (key in segmentMoments) return null
        val target = s.targetPaceSecondsPerKilometer ?: return null
        val values = paceValues(s.elapsedSeconds - 60, s.elapsedSeconds)
        if (values.size < 8) return null
        val sorted = values.sorted()
        if (abs(values.average() - target) > 12 || percentile(.9, sorted) - percentile(.1, sorted) > 25) return null
        segmentMoments += key
        return DetectedMoment(LiveCoachMoment.TargetLocked, s.elapsedSeconds)
    }

    private fun terrain(s: CoachSnapshot, grade: Double?): DetectedMoment? {
        if (!s.isRunning || s.elapsedSeconds < 300 || grade == null) {
            climbCandidateStartMeters = null
            return null
        }
        if (!onClimb && grade >= 3.5) {
            val start = climbCandidateStartMeters
            if (start == null) {
                climbCandidateStartMeters = s.distanceMeters
                return null
            }
            if (s.distanceMeters - start < 30) return null
            onClimb = true
            climbCandidateStartMeters = null
            return DetectedMoment(LiveCoachMoment.ClimbStart, s.elapsedSeconds)
        }
        if (!onClimb) climbCandidateStartMeters = null
        if (onClimb && grade <= 1.25) {
            onClimb = false
            return DetectedMoment(LiveCoachMoment.CrestRecovery, s.elapsedSeconds)
        }
        return null
    }

    private fun finish(s: CoachSnapshot): DetectedMoment? {
        if (s.elapsedSeconds < 300 || LiveCoachMoment.FinishOpportunity in oneShots) return null
        val distanceWindow = s.targetDistanceMeters?.takeIf { it > 0 }?.let { target ->
            val remaining = target - s.distanceMeters
            remaining > 300 && remaining <= minOf(800.0, target * .12)
        } == true
        val timeWindow = s.targetDurationSeconds?.takeIf { it > 0 }?.let { target ->
            val remaining = target - s.elapsedSeconds
            remaining > 120 && remaining <= minOf(300, (target * .12).toInt())
        } == true
        if (!distanceWindow && !timeWindow) return null
        oneShots += LiveCoachMoment.FinishOpportunity
        return DetectedMoment(LiveCoachMoment.FinishOpportunity, s.elapsedSeconds)
    }

    private fun evaluatePending(s: CoachSnapshot): Evaluation {
        val evaluated = mutableListOf<EvaluatedCue>()
        var recovery: DetectedMoment? = null
        records.filter { it.outcome == CueOutcome.Pending }.forEach { record ->
            if (s.elapsedSeconds - record.spokenAt < record.delay) return@forEach
            val baseline = record.baseline ?: return@forEach
            val target = record.target ?: return@forEach
            val current = averagePace(s.elapsedSeconds - 30, s.elapsedSeconds) ?: return@forEach
            val baselineError = abs(baseline - target)
            val currentError = abs(current - target)
            record.outcome = when {
                currentError <= 10 -> CueOutcome.Stabilized
                currentError + 8 < baselineError -> CueOutcome.Improved
                currentError > baselineError + 10 -> CueOutcome.Worsened
                else -> CueOutcome.Unchanged
            }
            evaluated += EvaluatedCue(record.moment, record.outcome)
            if (recovery == null && record.outcome in setOf(CueOutcome.Stabilized, CueOutcome.Improved)
                && record.moment in setOf(LiveCoachMoment.EarlyOverpace, LiveCoachMoment.PaceAboveTarget, LiveCoachMoment.PaceBelowTarget, LiveCoachMoment.PaceDrift, LiveCoachMoment.RecoveryTooHard)
            ) {
                recovery = DetectedMoment(LiveCoachMoment.RhythmRecovery, s.elapsedSeconds)
            }
        }
        return Evaluation(evaluated, recovery)
    }

    private fun averagePace(start: Int, end: Int) = paceValues(start, end).takeIf { it.size >= 4 }?.average()
    private fun paceValues(start: Int, end: Int) = history.filter { it.elapsedSeconds in start..end }.mapNotNull { it.paceSecondsPerKilometer }
    private fun segmentKey(moment: LiveCoachMoment, s: CoachSnapshot) = "${moment.wireValue}|${s.segmentIndex ?: s.segmentPhase ?: "overall"}"
    private fun meaningfulGrade(grade: Double?) = grade?.let { abs(it) >= 2.5 } == true
    private fun percentile(fraction: Double, sorted: List<Double>): Double {
        if (sorted.isEmpty()) return 0.0
        val index = (sorted.lastIndex * fraction).roundToInt().coerceIn(0, sorted.lastIndex)
        return sorted[index]
    }

    private data class Evaluation(val records: List<EvaluatedCue>, val recovery: DetectedMoment?)

    private companion object { const val MAX_HISTORY = 240 }
}

private fun terrainGrade(snapshots: List<CoachSnapshot>): Double? {
    val reliable = snapshots.filter {
        it.latitude != null && it.longitude != null && it.altitudeMeters != null
            && it.horizontalAccuracyMeters?.let { value -> value in 0.0..20.0 } == true
            && it.verticalAccuracyMeters?.let { value -> value in 0.0..8.0 } == true
    }
    if (reliable.size < 8 || reliable.last().elapsedSeconds - reliable.first().elapsedSeconds < 30) return null
    val endpointCount = minOf(5, reliable.size / 2)
    val start = endpoint(reliable.take(endpointCount))
    val end = endpoint(reliable.takeLast(endpointCount))
    val traveled = end.distance - start.distance
    val displacement = haversine(start.latitude, start.longitude, end.latitude, end.longitude)
    val altitudeDelta = end.altitude - start.altitude
    if (traveled < 75 || displacement < 40 || abs(altitudeDelta) < max(6.0, max(start.verticalAccuracy, end.verticalAccuracy))) return null
    val grade = altitudeDelta / traveled * 100
    return grade.takeIf { it.isFinite() && abs(it) <= 40 }
}

private data class GradeEndpoint(val latitude: Double, val longitude: Double, val altitude: Double, val distance: Double, val verticalAccuracy: Double)
private fun endpoint(values: List<CoachSnapshot>): GradeEndpoint {
    val count = values.size.toDouble()
    return GradeEndpoint(
        values.sumOf { it.latitude!! } / count,
        values.sumOf { it.longitude!! } / count,
        values.sumOf { it.altitudeMeters!! } / count,
        values.sumOf { it.distanceMeters } / count,
        values.sumOf { it.verticalAccuracyMeters!! } / count,
    )
}

private fun haversine(latitudeA: Double, longitudeA: Double, latitudeB: Double, longitudeB: Double): Double {
    val radians = Math.PI / 180
    val latitudeDelta = (latitudeB - latitudeA) * radians
    val longitudeDelta = (longitudeB - longitudeA) * radians
    val firstLatitude = latitudeA * radians
    val secondLatitude = latitudeB * radians
    val value = sin(latitudeDelta / 2) * sin(latitudeDelta / 2) + cos(firstLatitude) * cos(secondLatitude) * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
    return 6_371_000 * 2 * atan2(sqrt(value), sqrt(max(0.0, 1 - value)))
}
