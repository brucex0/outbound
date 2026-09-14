package com.plainstride.outbound.feature.onboarding

import androidx.annotation.StringRes
import java.time.LocalDate
import kotlinx.serialization.Serializable
import com.plainstride.outbound.core.model.Modality

@Serializable
enum class PlanBuilderSource(val analyticsValue: String) {
    Onboarding("onboarding"),
    PlannedButton("planned_button"),
    AllPlans("all_plans"),
    Settings("settings"),
}

@Serializable
enum class OnboardingStatus { pending, skipped, completed }

@Serializable
enum class OnboardingStep {
    Identity,
    Welcome,
    Objective,
    Activities,
    Baseline,
    Week,
    Profile,
    Review,
    Creating,
    Result,
}

@Serializable
enum class PlanObjective(@param:StringRes val label: Int) {
    EventPreparation(R.string.plan_builder_objective_event),
    Endurance(R.string.plan_builder_objective_endurance),
    Speed(R.string.plan_builder_objective_speed),
    WeightLoss(R.string.plan_builder_objective_weight_loss),
    HealthEnergy(R.string.plan_builder_objective_health),
}

@Serializable
enum class PlanActivity(@param:StringRes val label: Int, val modality: Modality) {
    Run(R.string.plan_builder_activity_run, Modality.run),
    Walk(R.string.plan_builder_activity_walk_hike, Modality.walk),
    Bike(R.string.plan_builder_activity_bike, Modality.bike),
}

@Serializable
enum class PlanBaselineContext(@param:StringRes val label: Int) {
    StartingOut(R.string.plan_builder_baseline_starting),
    CurrentlyActive(R.string.plan_builder_baseline_active),
    ReturningAfterBreak(R.string.plan_builder_baseline_returning),
}

@Serializable
enum class MeasurementSystem { Metric, Imperial }

@Serializable
enum class SexAtBirth(@param:StringRes val label: Int) {
    NotProvided(R.string.onboarding_sex_not_provided),
    Female(R.string.onboarding_sex_female),
    Male(R.string.onboarding_sex_male),
}

@Serializable
data class OnboardingDraft(
    val accountId: String,
    val step: OnboardingStep = OnboardingStep.Welcome,
    val displayName: String = "",
    val username: String = "",
    val email: String = "",
    val objective: PlanObjective = PlanObjective.Endurance,
    val activities: List<PlanActivity> = listOf(PlanActivity.Run),
    val eventDistanceMeters: Double? = 5_000.0,
    val eventDate: String? = defaultEventDate(),
    val eventIntent: String = "finish",
    val targetTimeSeconds: Int? = null,
    val reviewHorizonWeeks: Int = 8,
    val successSignal: String = "",
    val goalDescription: String = "",
    val intakeContextVersion: String? = null,
    val observedBaselineConfirmed: Boolean? = null,
    val baselineContext: PlanBaselineContext = PlanBaselineContext.CurrentlyActive,
    val recentSessionsPerWeek: Int = 2,
    val comfortableMinutes: Int = 30,
    val sessionsPerWeek: Int = 3,
    val availableMinutes: Int = 30,
    val preferredDays: List<String> = emptyList(),
    val constraints: String = "",
    val birthDate: String = "",
    val height: String = "",
    val weight: String = "",
    val sexAtBirth: SexAtBirth = SexAtBirth.NotProvided,
    val measurementSystem: MeasurementSystem = MeasurementSystem.Metric,
)

data class OnboardingAccount(
    val id: String,
    val displayName: String?,
    val username: String?,
    val verifiedEmail: String?,
    val onboardingStatus: OnboardingStatus,
) {
    val needsIdentity: Boolean
        get() = displayName.isNullOrBlank() || displayName.equals("Runner", ignoreCase = true) || verifiedEmail.isNullOrBlank()
}

data class TrainingProfileInput(
    val birthDate: String?,
    val heightCentimeters: Double?,
    val weightKilograms: Double?,
    val sexAtBirth: SexAtBirth?,
    val objective: PlanObjective,
)

data class PlanBuilderInput(
    val objective: PlanObjective,
    val activities: List<PlanActivity>,
    val eventDistanceMeters: Double?,
    val eventDate: String?,
    val eventIntent: String,
    val targetTimeSeconds: Int?,
    val reviewHorizonWeeks: Int,
    val successSignal: String,
    val goalDescription: String,
    val intakeContextVersion: String?,
    val baselineContext: PlanBaselineContext,
    val recentSessionsPerWeek: Int,
    val comfortableMinutes: Int,
    val sessionsPerWeek: Int,
    val availableMinutes: Int,
    val preferredDays: List<String>,
    val constraints: String,
)

data class ImportedHealthProfile(
    val trainingProfile: TrainingProfileInput,
    val recentSessionsPerWeek: Int?,
    val comfortableMinutes: Int?,
    val recentActivityCount: Int,
)

internal fun defaultEventDate(): String = LocalDate.now().plusWeeks(8).toString()

internal fun OnboardingDraft.requiredBodyProfileComplete(): Boolean {
    val birth = runCatching { LocalDate.parse(birthDate) }.getOrNull() ?: return false
    val age = java.time.Period.between(birth, LocalDate.now()).years
    val rawWeight = weight.trim().replace(',', '.').toDoubleOrNull() ?: return false
    val kilograms = if (measurementSystem == MeasurementSystem.Metric) rawWeight else rawWeight * 0.45359237
    return age in 13..100 && kilograms in 25.0..350.0 && sexAtBirth != SexAtBirth.NotProvided
}
