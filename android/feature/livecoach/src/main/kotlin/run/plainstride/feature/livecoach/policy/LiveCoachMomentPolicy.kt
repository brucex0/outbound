package run.plainstride.feature.livecoach.policy

import run.plainstride.feature.livecoach.network.CoachingContract
import run.plainstride.feature.livecoach.network.LiveCoachMoment
import kotlin.math.abs

data class CoachSnapshot(
    val elapsedSeconds: Int, val distanceMeters: Double, val paceSecondsPerKilometer: Double?,
    val targetPaceSecondsPerKilometer: Double? = null, val gradePercent: Double? = null,
    val segmentIndex: Int? = null, val segmentPhase: String? = null, val isMoving: Boolean = true,
    val targetDistanceMeters: Double? = null, val targetDurationSeconds: Int? = null,
)
data class DetectedMoment(val moment: LiveCoachMoment, val detectedAtElapsedSeconds: Int, val baselinePaceSecondsPerKilometer: Double? = null, val targetPaceSecondsPerKilometer: Double? = null, val evaluationDelaySeconds: Int = 75)

/** Pure, bounded state machine shared by recording and preview clients. It never stores location or health data. */
class LiveCoachMomentPolicy {
    private val history = ArrayDeque<CoachSnapshot>()
    private val oneShots = mutableSetOf<LiveCoachMoment>()
    private var lastMomentAt: Int? = null
    private var lastSegment: Int? = null
    private var lastMoving = true
    private var climb = false
    private var climbStartMeters: Double? = null

    fun reset() { history.clear(); oneShots.clear(); lastMomentAt = null; lastSegment = null; lastMoving = true; climb = false; climbStartMeters = null }

    fun ingest(snapshot: CoachSnapshot, contract: CoachingContract): DetectedMoment? {
        val pace = snapshot.paceSecondsPerKilometer?.takeIf { it in 60.0..3600.0 }
        history.addLast(snapshot.copy(paceSecondsPerKilometer = pace))
        while (history.size > 240) history.removeFirst()

        movement(snapshot)?.let { return emit(it, snapshot.elapsedSeconds) }
        segment(snapshot)?.let { return emit(it, snapshot.elapsedSeconds) }
        terrain(snapshot)?.let { return emit(it, snapshot.elapsedSeconds) }
        val cooldown = when (contract) { CoachingContract.Quiet -> return null; CoachingContract.Responsive -> 180; CoachingContract.CoachMe -> 90 }
        if (lastMomentAt?.let { snapshot.elapsedSeconds - it < cooldown } == true) return null
        if (abs(snapshot.gradePercent ?: 0.0) >= 2.5) return null
        val moment = earlyOverpace(snapshot) ?: targetDeviation(snapshot) ?: finish(snapshot) ?: drift(snapshot) ?: instability(snapshot) ?: targetLocked(snapshot)
        return moment?.also { lastMomentAt = snapshot.elapsedSeconds }
    }

    private fun movement(s: CoachSnapshot): LiveCoachMoment? {
        val value = when { lastMoving && !s.isMoving && s.elapsedSeconds >= 30 -> LiveCoachMoment.UnexpectedStop; !lastMoving && s.isMoving -> LiveCoachMoment.ResumeAfterBreak; else -> null }
        lastMoving = s.isMoving
        return value
    }
    private fun segment(s: CoachSnapshot): LiveCoachMoment? {
        val changed = lastSegment != null && s.segmentIndex != null && lastSegment != s.segmentIndex
        lastSegment = s.segmentIndex ?: lastSegment
        return LiveCoachMoment.SegmentTransition.takeIf { changed }
    }
    private fun terrain(s: CoachSnapshot): LiveCoachMoment? {
        val grade = s.gradePercent ?: return null
        if (!climb && grade >= 3.5) {
            climbStartMeters = climbStartMeters ?: s.distanceMeters
            if (s.distanceMeters - (climbStartMeters ?: s.distanceMeters) >= 80) { climb = true; climbStartMeters = null; return LiveCoachMoment.ClimbStart }
        } else if (!climb) climbStartMeters = null
        if (climb && grade <= 1.0) { climb = false; return LiveCoachMoment.CrestRecovery }
        return null
    }
    private fun earlyOverpace(s: CoachSnapshot): DetectedMoment? {
        if (s.elapsedSeconds !in 75..240) return null
        val target = s.targetPaceSecondsPerKilometer ?: return null
        val avg = averagePace(s.elapsedSeconds - 30) ?: return null
        return DetectedMoment(LiveCoachMoment.EarlyOverpace, s.elapsedSeconds, avg, target).takeIf { avg < target - 18 && oneShots.add(LiveCoachMoment.EarlyOverpace) }
    }
    private fun targetDeviation(s: CoachSnapshot): DetectedMoment? {
        val target = s.targetPaceSecondsPerKilometer ?: return null
        val avg = averagePace(s.elapsedSeconds - 45) ?: return null
        val delta = avg - target
        val type = when { delta < -18 -> LiveCoachMoment.PaceAboveTarget; delta > 25 -> if (s.segmentPhase == "recovery") LiveCoachMoment.RecoveryTooHard else LiveCoachMoment.PaceBelowTarget; else -> null } ?: return null
        return DetectedMoment(type, s.elapsedSeconds, avg, target)
    }
    private fun finish(s: CoachSnapshot): DetectedMoment? {
        val nearDistance = s.targetDistanceMeters?.let { it > 0 && s.distanceMeters / it >= .9 } == true
        val nearTime = s.targetDurationSeconds?.let { it > 0 && s.elapsedSeconds.toDouble() / it >= .9 } == true
        return DetectedMoment(LiveCoachMoment.FinishOpportunity, s.elapsedSeconds).takeIf { (nearDistance || nearTime) && oneShots.add(LiveCoachMoment.FinishOpportunity) }
    }
    private fun drift(s: CoachSnapshot): DetectedMoment? {
        if (s.elapsedSeconds < 300) return null
        val recent = averagePace(s.elapsedSeconds - 60) ?: return null
        val prior = history.filter { it.elapsedSeconds in (s.elapsedSeconds - 300)..(s.elapsedSeconds - 120) }.mapNotNull { it.paceSecondsPerKilometer }.averageOrNull() ?: return null
        return DetectedMoment(LiveCoachMoment.PaceDrift, s.elapsedSeconds, recent, prior).takeIf { recent - prior >= 18 }
    }
    private fun instability(s: CoachSnapshot): DetectedMoment? {
        if (s.elapsedSeconds < 120) return null
        val values = history.filter { it.elapsedSeconds >= s.elapsedSeconds - 90 }.mapNotNull { it.paceSecondsPerKilometer }
        if (values.size < 8) return null
        val average = values.average(); val spread = (values.maxOrNull() ?: 0.0) - (values.minOrNull() ?: 0.0)
        return DetectedMoment(LiveCoachMoment.PaceInstability, s.elapsedSeconds, average).takeIf { spread >= 60 || spread >= average * .15 }
    }
    private fun targetLocked(s: CoachSnapshot): DetectedMoment? {
        if (s.elapsedSeconds < 90 || LiveCoachMoment.TargetLocked in oneShots) return null
        val target = s.targetPaceSecondsPerKilometer ?: return null
        val values = history.filter { it.elapsedSeconds >= s.elapsedSeconds - 90 }.mapNotNull { it.paceSecondsPerKilometer }
        if (values.size < 8) return null
        val avg = values.average(); val spread = (values.maxOrNull() ?: 0.0) - (values.minOrNull() ?: 0.0)
        return DetectedMoment(LiveCoachMoment.TargetLocked, s.elapsedSeconds, avg, target).takeIf { abs(avg - target) <= 12 && spread <= 25 && oneShots.add(LiveCoachMoment.TargetLocked) }
    }
    private fun averagePace(after: Int) = history.filter { it.elapsedSeconds >= after }.mapNotNull { it.paceSecondsPerKilometer }.takeIf { it.size >= 4 }?.average()
    private fun emit(moment: LiveCoachMoment, elapsed: Int) = DetectedMoment(moment, elapsed).also { lastMomentAt = elapsed }
    private fun List<Double>.averageOrNull() = takeIf { isNotEmpty() }?.average()
}
