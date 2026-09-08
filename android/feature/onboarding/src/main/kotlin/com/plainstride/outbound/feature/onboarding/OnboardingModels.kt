package com.plainstride.outbound.feature.onboarding

import androidx.annotation.StringRes
import kotlinx.serialization.Serializable
import java.time.LocalDate

@Serializable
enum class OnboardingStep { Identity, Goal, Baseline, Week, Profile, Ready }

@Serializable
enum class RunningGoal(@param:StringRes val label: Int) {
    Consistency(R.string.onboarding_goal_consistency),
    Start(R.string.onboarding_goal_start),
    Comeback(R.string.onboarding_goal_comeback),
    Race(R.string.onboarding_goal_race),
    Faster(R.string.onboarding_goal_faster),
}

@Serializable
enum class RunningFrequency(@param:StringRes val label: Int, val sessionsPerWeek: Int) {
    None(R.string.onboarding_frequency_none, 0),
    Occasional(R.string.onboarding_frequency_occasional, 1),
    OneOrTwo(R.string.onboarding_frequency_one_two, 2),
    ThreePlus(R.string.onboarding_frequency_three_plus, 3),
}

@Serializable
enum class SexAtBirth(@param:StringRes val label: Int) {
    NotProvided(R.string.onboarding_sex_not_provided),
    Female(R.string.onboarding_sex_female),
    Male(R.string.onboarding_sex_male),
}

@Serializable
data class OnboardingDraft(
    val accountId: String,
    val step: OnboardingStep = OnboardingStep.Goal,
    val displayName: String = "",
    val username: String = "",
    val email: String = "",
    val goal: RunningGoal = RunningGoal.Consistency,
    val frequency: RunningFrequency = RunningFrequency.OneOrTwo,
    val comfortableMinutes: Int = 30,
    val runsPerWeek: Int = 3,
    val availableMinutes: Int = 30,
    val birthDate: String = LocalDate.now().minusYears(30).toString(),
    val heightCentimeters: String = "",
    val weightKilograms: String = "",
    val sexAtBirth: SexAtBirth = SexAtBirth.NotProvided,
)

data class OnboardingAccount(
    val id: String,
    val displayName: String?,
    val username: String?,
    val verifiedEmail: String?,
    val onboardingCompleted: Boolean,
) {
    val needsIdentity: Boolean
        get() = displayName.isNullOrBlank() || displayName.equals("Runner", ignoreCase = true) || verifiedEmail.isNullOrBlank()
}

data class TrainingProfileInput(
    val birthDate: String?,
    val heightCentimeters: Double?,
    val weightKilograms: Double?,
    val sexAtBirth: SexAtBirth?,
)

data class RunnerProfileInput(
    val goal: RunningGoal,
    val recentSessionsPerWeek: Int,
    val comfortableMinutes: Int,
    val targetSessionsPerWeek: Int,
    val availableMinutes: Int,
    val preferredLongRunDay: String = "saturday",
)

data class ImportedHealthProfile(
    val trainingProfile: TrainingProfileInput,
    val recentSessionsPerWeek: Int?,
    val comfortableMinutes: Int?,
)
