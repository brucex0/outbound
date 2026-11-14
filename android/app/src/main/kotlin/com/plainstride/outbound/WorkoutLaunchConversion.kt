package com.plainstride.outbound

import com.plainstride.outbound.core.model.Modality
import com.plainstride.outbound.feature.today.WorkoutLaunchIntent
import com.plainstride.outbound.feature.recording.ActivityKind
import com.plainstride.outbound.feature.recording.RecordingLaunchConfiguration
import com.plainstride.outbound.feature.recording.RecordingGoal
import com.plainstride.outbound.feature.recording.RecordingGoalType
import com.plainstride.outbound.feature.recording.StructuredWorkoutStep

internal fun WorkoutLaunchIntent.toRecordingLaunch(): RecordingLaunchConfiguration {
    val goal = when {
        targetCalories != null -> RecordingGoal(RecordingGoalType.CALORIES, targetCalories = targetCalories)
        distanceMeters != null -> RecordingGoal(RecordingGoalType.DISTANCE, targetDistanceMeters = distanceMeters)
        steps.isNotEmpty() -> RecordingGoal(RecordingGoalType.WORKOUT, targetDurationSeconds = durationSeconds.toLong())
        else -> RecordingGoal(RecordingGoalType.TIME, targetDurationSeconds = durationSeconds.toLong())
    }
    return RecordingLaunchConfiguration(
        activityKind = when (modality) {
            Modality.walk -> ActivityKind.WALKING
            Modality.bike -> ActivityKind.CYCLING
            Modality.swim -> ActivityKind.SWIMMING
            else -> ActivityKind.RUNNING
        },
        title = title,
        goal = goal,
        workoutSteps = if (targetCalories != null || distanceMeters != null) emptyList() else structuredSteps.map {
            StructuredWorkoutStep(title = it.label, detail = it.detail, durationSeconds = it.durationSeconds,
                phase = it.coachingTarget?.phase, recognizesTargetLock = it.coachingTarget?.recognizesTargetLock == true,
                targetPaceSecondsPerKilometer = it.coachingTarget?.pace?.targetSecondsPerKilometer,
                fasterToleranceSeconds = it.coachingTarget?.pace?.fasterToleranceSeconds,
                slowerToleranceSeconds = it.coachingTarget?.pace?.slowerToleranceSeconds)
        }.ifEmpty { steps.map { StructuredWorkoutStep(it) } },
        // Distance/calorie replacements are continuous targets. Only an authored
        // distance timeline supplies sections to an otherwise distance-only launch.
        guideInstructions = guideInstructions?.takeIf { instructions ->
            targetCalories == null && (distanceMeters == null || instructions.segments.any { it.trigger.type == "distance" })
        },
        entrySource = source,
        suggestionId = suggestionId,
        plannedWorkoutId = plannedWorkoutId,
        performedWorkoutReference = performedWorkoutReference,
        workoutDetail = effortLabel,
        workoutGuideline = guideLine ?: listOf(stimulus.name, intensityModel).filter(String::isNotBlank).joinToString(" · "),
    )
}
