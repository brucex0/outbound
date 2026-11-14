package com.plainstride.outbound.feature.livecoach.policy

import com.plainstride.outbound.core.model.GuideInstructions
import com.plainstride.outbound.feature.livecoach.network.CueTrigger
import com.plainstride.outbound.feature.livecoach.network.GuidancePlan
import com.plainstride.outbound.feature.livecoach.network.LiveCoachMoment
import com.plainstride.outbound.feature.livecoach.network.PlanCue
import com.plainstride.outbound.feature.livecoach.network.ProgressPolicy
import com.plainstride.outbound.feature.recording.ActivityKind
import com.plainstride.outbound.feature.recording.RecordingGoal
import com.plainstride.outbound.feature.recording.RecordingSnapshot

data class ScheduledCue(
    val moment: DetectedMoment,
    val goalMilestone: String? = null,
    val includePace: Boolean = true,
    val trigger: CueTrigger? = null,
)

data class ScheduleUpdate(
    val workoutCue: ScheduledCue? = null,
    val progressCue: ScheduledCue? = null,
)

/** Reproduces the iOS workout-trigger, goal-milestone, and periodic-progress cadence. */
class LiveCoachSchedule {
    private val processedWorkoutCueIds = mutableSetOf<String>()
    private val spokenGoalMilestones = mutableSetOf<String>()
    private var lastProgressAnnouncementAt: Int? = null
    private var lastGuideSpeechAt: Int? = null
    private var lastProgressTimeMilestone = 0
    private var lastProgressDistanceMilestone = 0

    fun reset() {
        processedWorkoutCueIds.clear()
        spokenGoalMilestones.clear()
        lastProgressAnnouncementAt = null
        lastGuideSpeechAt = null
        lastProgressTimeMilestone = 0
        lastProgressDistanceMilestone = 0
    }

    fun ingest(
        snapshot: RecordingSnapshot,
        guidancePlan: GuidancePlan?,
        goal: RecordingGoal,
        activityKind: ActivityKind,
        imperial: Boolean,
        aiCoachEnabled: Boolean = true,
        localInstructions: GuideInstructions? = null,
    ): ScheduleUpdate {
        val workout = nextWorkoutCue(snapshot, guidancePlan, aiCoachEnabled, localInstructions)
        val progress = nextGoalCue(snapshot, goal, guidancePlan?.progressPolicy, activityKind, imperial)
            ?: nextPeriodicProgress(snapshot, guidancePlan?.progressPolicy, activityKind, imperial)
        return ScheduleUpdate(workout, progress)
    }

    fun recordSpoken(cue: ScheduledCue) {
        val elapsed = cue.moment.detectedAtElapsedSeconds
        lastGuideSpeechAt = elapsed
        if (cue.moment.moment == LiveCoachMoment.Progress) {
            lastProgressAnnouncementAt = elapsed
            cue.goalMilestone?.let(spokenGoalMilestones::add)
        }
    }

    fun recordGuideSpeech(elapsedSeconds: Int) {
        lastGuideSpeechAt = elapsedSeconds
    }

    private fun nextWorkoutCue(snapshot: RecordingSnapshot, plan: GuidancePlan?, aiCoachEnabled: Boolean, local: GuideInstructions?): ScheduledCue? {
        // Local catalog sections remain execution instructions with AI Coach off/offline.
        // Use the semantic instruction ID across local, fallback and refreshed server plans.
        val localCues = local?.segments.orEmpty().map { instruction ->
            PlanCue(id = instruction.id, moment = LiveCoachMoment.WorkoutInstruction, instructionId = instruction.id,
                trigger = instruction.trigger.let { CueTrigger(it.type, it.startMeters, it.endMeters, it.startSeconds, it.endSeconds) },
                phases = listOf("any"), priority = "high", cooldownSeconds = 0,
                phrases = listOf(com.plainstride.outbound.feature.livecoach.network.Phrase(instruction.id, instruction.cue.ifBlank { instruction.instruction })))
        }
        val cues = (localCues + plan?.cues.orEmpty()).distinctBy { it.instructionId ?: it.id }
        for (cue in cues) {
            val key = cue.instructionId ?: cue.id
            if (cue.moment != LiveCoachMoment.WorkoutInstruction || cue.trigger == null || key in processedWorkoutCueIds) continue
            when (triggerState(cue.trigger, snapshot)) {
                TriggerState.NotReached -> continue
                TriggerState.Missed -> { processedWorkoutCueIds += key; continue }
                TriggerState.Due -> {
                    processedWorkoutCueIds += key
                    if (!aiCoachEnabled && key.startsWith("execution_coaching.")) continue
                    return ScheduledCue(
                        DetectedMoment(moment = LiveCoachMoment.WorkoutInstruction,
                            detectedAtElapsedSeconds = snapshot.elapsedSeconds.toInt(), evaluationDelaySeconds = 0,
                            preferredText = cue.phrases.firstOrNull()?.text, instructionId = cue.instructionId, fixedCueKey = null),
                        trigger = cue.trigger,
                    )
                }
            }
        }
        return null
    }

    private fun triggerState(trigger: CueTrigger, current: RecordingSnapshot): TriggerState = when (trigger.type) {
        "elapsed_time" -> {
            val start = trigger.startSeconds
            val end = trigger.endSeconds
            when {
                start == null || start < 0 -> TriggerState.Missed
                current.elapsedSeconds < start -> TriggerState.NotReached
                end != null && (end <= start || current.elapsedSeconds >= end) -> TriggerState.Missed
                current.elapsedSeconds - start <= 20 -> TriggerState.Due
                else -> TriggerState.Missed
            }
        }
        "distance" -> {
            val start = trigger.startMeters
            val end = trigger.endMeters
            when {
                start == null || !start.isFinite() || start < 0 -> TriggerState.Missed
                current.distanceMeters < start -> TriggerState.NotReached
                end != null && (!end.isFinite() || end <= start || current.distanceMeters >= end) -> TriggerState.Missed
                start == 0.0 && current.distanceMeters <= 75 -> TriggerState.Due
                current.distanceMeters - start > 75 -> TriggerState.Missed
                !hasReliableDistanceProgress(current) -> TriggerState.NotReached
                else -> TriggerState.Due
            }
        }
        else -> TriggerState.Missed
    }

    private fun nextGoalCue(
        snapshot: RecordingSnapshot,
        goal: RecordingGoal,
        progressPolicy: ProgressPolicy?,
        activityKind: ActivityKind,
        imperial: Boolean,
    ): ScheduledCue? {
        val milestone = nextDistanceMilestone(snapshot, goal, imperial)
            ?: nextDurationMilestone(snapshot, goal)
            ?: return null
        if (lastProgressAnnouncementAt?.let { snapshot.elapsedSeconds - it < MINIMUM_PROGRESS_GAP_SECONDS } == true && !isFinishCue(milestone)) return null
        if (lastGuideSpeechAt?.let { snapshot.elapsedSeconds - it < MINIMUM_STAT_SPEECH_GAP_SECONDS } == true && !isFinishCue(milestone)) return null
        spokenGoalMilestones += milestone
        rememberProgressMilestones(snapshot, progressPolicy, activityKind, imperial)
        return ScheduledCue(
            moment = DetectedMoment(
                moment = LiveCoachMoment.Progress,
                detectedAtElapsedSeconds = snapshot.elapsedSeconds.toInt(),
                evaluationDelaySeconds = 0,
                instructionId = "goal:$milestone",
                fixedCueKey = fixedCueKey(milestone),
            ),
            goalMilestone = milestone,
            includePace = false,
        )
    }

    private fun nextDistanceMilestone(snapshot: RecordingSnapshot, goal: RecordingGoal, imperial: Boolean): String? {
        val target = goal.targetDistanceMeters?.takeIf { it > 0 } ?: return null
        if (!hasReliableDistanceProgress(snapshot)) return null
        val progress = snapshot.distanceMeters / target
        val remaining = target - snapshot.distanceMeters
        val lastUnit = if (imperial) 1_609.344 else 1_000.0
        val short = if (imperial) 160.9344 else 100.0
        val medium = if (imperial) 402.336 else 300.0
        val candidates = listOf(
            "distance_complete" to (progress >= 1),
            "distance_100_remaining" to (target > short * 4 && remaining in Double.MIN_VALUE..short),
            "distance_300_remaining" to (target > medium * 2 && remaining > short && remaining <= medium),
            "distance_last_unit" to (target > lastUnit * 1.5 && remaining in Double.MIN_VALUE..lastUnit),
            "distance_two_thirds" to (progress >= 2.0 / 3.0),
            "distance_halfway" to (progress >= .5),
            "distance_one_third" to (progress >= 1.0 / 3.0),
        )
        return candidates.firstOrNull { (key, reached) -> reached && key !in spokenGoalMilestones }?.first
    }

    private fun nextDurationMilestone(snapshot: RecordingSnapshot, goal: RecordingGoal): String? {
        val target = goal.targetDurationSeconds?.takeIf { it > 0 } ?: return null
        val progress = snapshot.elapsedSeconds.toDouble() / target
        val remaining = target - snapshot.elapsedSeconds
        val candidates = listOf(
            "duration_complete" to (progress >= 1),
            "duration_one_remaining" to (target > 120 && remaining in 1L..60L),
            "duration_five_remaining" to (target > 600 && remaining in 61L..300L),
            "duration_two_thirds" to (progress >= 2.0 / 3.0),
            "duration_halfway" to (progress >= .5),
            "duration_one_third" to (progress >= 1.0 / 3.0),
        )
        return candidates.firstOrNull { (key, reached) -> reached && key !in spokenGoalMilestones }?.first
    }

    private fun nextPeriodicProgress(
        snapshot: RecordingSnapshot,
        progressPolicy: ProgressPolicy?,
        activityKind: ActivityKind,
        imperial: Boolean,
    ): ScheduledCue? {
        val intervalSeconds = progressPolicy?.announceEverySeconds?.takeIf { it > 0 } ?: 180
        val intervalMeters = progressPolicy?.announceEveryMeters?.takeIf { it > 0 }
            ?: when (activityKind) {
                ActivityKind.CYCLING -> if (imperial) 8_046.72 else 5_000.0
                else -> if (imperial) 1_609.344 else 1_000.0
            }
        val timeMilestone = snapshot.elapsedSeconds.toInt() / intervalSeconds
        val distanceMilestone = (snapshot.distanceMeters / intervalMeters).toInt()
        val reachedTime = timeMilestone > lastProgressTimeMilestone
        val reachedDistance = distanceMilestone > lastProgressDistanceMilestone && hasReliableDistanceProgress(snapshot)
        if (!reachedTime && !reachedDistance) return null
        if (lastProgressAnnouncementAt?.let { snapshot.elapsedSeconds - it < MINIMUM_PROGRESS_GAP_SECONDS } == true) return null
        if (!reachedDistance && (snapshot.elapsedSeconds < 300 || snapshot.distanceMeters < 400)) {
            lastProgressTimeMilestone = maxOf(lastProgressTimeMilestone, timeMilestone)
            return null
        }
        if (lastGuideSpeechAt?.let { snapshot.elapsedSeconds - it < MINIMUM_STAT_SPEECH_GAP_SECONDS } == true) return null
        lastProgressTimeMilestone = timeMilestone
        lastProgressDistanceMilestone = distanceMilestone
        return ScheduledCue(
            moment = DetectedMoment(
                moment = LiveCoachMoment.Progress,
                detectedAtElapsedSeconds = snapshot.elapsedSeconds.toInt(),
                evaluationDelaySeconds = 0,
                fixedCueKey = null,
            ),
            includePace = progressPolicy?.includePace ?: true,
        )
    }

    private fun rememberProgressMilestones(
        snapshot: RecordingSnapshot,
        progressPolicy: ProgressPolicy?,
        activityKind: ActivityKind,
        imperial: Boolean,
    ) {
        val intervalSeconds = progressPolicy?.announceEverySeconds?.takeIf { it > 0 } ?: 180
        val intervalMeters = progressPolicy?.announceEveryMeters?.takeIf { it > 0 }
            ?: if (activityKind == ActivityKind.CYCLING) {
                if (imperial) 8_046.72 else 5_000.0
            } else if (imperial) 1_609.344 else 1_000.0
        lastProgressTimeMilestone = snapshot.elapsedSeconds.toInt() / intervalSeconds
        lastProgressDistanceMilestone = (snapshot.distanceMeters / intervalMeters).toInt()
    }

    private fun hasReliableDistanceProgress(snapshot: RecordingSnapshot): Boolean {
        if (snapshot.distanceMeters <= 0 || snapshot.elapsedSeconds < 30) return false
        val maximumSpeed = if (snapshot.activityKind == ActivityKind.CYCLING) 25.0 else 10.0
        return snapshot.distanceMeters / snapshot.elapsedSeconds.coerceAtLeast(1) <= maximumSpeed
    }

    private fun isFinishCue(milestone: String) = milestone in setOf(
        "distance_300_remaining",
        "distance_100_remaining",
        "distance_complete",
        "duration_complete",
    )

    private fun fixedCueKey(milestone: String) = when (milestone) {
        "distance_one_third", "duration_one_third" -> "progress.one_third"
        "distance_halfway", "duration_halfway" -> "progress.halfway"
        "distance_two_thirds", "duration_two_thirds" -> "progress.two_thirds"
        "distance_complete", "duration_complete" -> "workout.complete"
        else -> "progress.finish_soon"
    }

    private enum class TriggerState { NotReached, Due, Missed }

    private companion object {
        const val MINIMUM_PROGRESS_GAP_SECONDS = 30
        const val MINIMUM_STAT_SPEECH_GAP_SECONDS = 20
    }
}
