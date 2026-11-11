package com.plainstride.outbound.feature.today

import com.plainstride.outbound.core.model.ActivitySuggestion
import com.plainstride.outbound.core.model.Modality
import com.plainstride.outbound.core.model.TrainingStimulus

data class WorkoutLaunchIntent(
    val suggestionId: String,
    val plannedWorkoutId: String?,
    val title: String,
    val modality: Modality,
    val stimulus: TrainingStimulus,
    val durationSeconds: Int,
    val distanceMeters: Double?,
    val targetCalories: Int?,
    val effortLabel: String,
    val intensityModel: String,
    val steps: List<String>,
    val source: String,
    val guideLine: String? = null,
    val structuredSteps: List<com.plainstride.outbound.core.model.StandaloneWorkoutStep> = emptyList(),
    val performedWorkoutReference: com.plainstride.outbound.core.model.PerformedWorkoutReference? = null,
)

/** One pure conversion shared by Today and isolated fixture verification. */
fun ActivitySuggestion.toWorkoutLaunchIntent(source: String): WorkoutLaunchIntent = WorkoutLaunchIntent(
        suggestionId = this.id,
        plannedWorkoutId = this.plannedWorkoutId,
        performedWorkoutReference = this.performedWorkoutReference,
        title = this.title,
        modality = this.modality,
        stimulus = this.stimulus,
        durationSeconds = this.durationSeconds ?: this.durationMinutes * 60,
        distanceMeters = this.distanceMeters,
        targetCalories = this.targetCalories,
        effortLabel = this.effortLabel,
        intensityModel = this.intensityModel,
        steps = this.steps.toList(),
        structuredSteps = this.effectiveWorkout?.steps.orEmpty(),
        source = source,
    )
