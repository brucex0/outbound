package com.plainstride.outbound.feature.onboarding

import javax.inject.Inject
import com.plainstride.outbound.core.auth.SessionCoordinator
import com.plainstride.outbound.core.model.PrimaryMotivation
import com.plainstride.outbound.core.model.RunGoalType
import com.plainstride.outbound.core.network.AccountApiService
import com.plainstride.outbound.core.network.ApiResult
import com.plainstride.outbound.core.network.PlanningApiService
import com.plainstride.outbound.core.network.RunnerProfileRequest
import com.plainstride.outbound.core.network.TrainingProfileRequest
import com.plainstride.outbound.core.network.UpdateAccountRequest
import com.plainstride.outbound.core.network.apiCall

class DefaultOnboardingRepository @Inject constructor(
    private val accounts: AccountApiService,
    private val personalization: PlanningApiService,
    private val sessions: SessionCoordinator,
    private val health: HealthProfileImporter,
) : OnboardingRepository {
    override suspend fun currentAccount(): OnboardingAccount {
        val authorization = authorization()
        val account = apiCall { accounts.currentAccount(authorization) }.valueOrThrow()
        return OnboardingAccount(
            account.id,
            account.displayName,
            account.username,
            account.normalizedEmail,
            account.onboardingCompleted == true,
        )
    }

    override suspend fun updateIdentity(displayName: String, username: String, contactEmail: String?): Result<OnboardingAccount> = runCatching {
        val account = apiCall { accounts.updateAccount(authorization(), UpdateAccountRequest(username, displayName, contactEmail)) }.valueOrThrow()
        OnboardingAccount(account.id, account.displayName, account.username, account.normalizedEmail, account.onboardingCompleted == true)
    }

    override suspend fun updateTrainingProfile(input: TrainingProfileInput): Result<Unit> = runCatching {
        val authorization = authorization()
        val current = apiCall { personalization.trainingProfile(authorization) }.valueOrThrow()
        apiCall { personalization.updateTrainingProfile(authorization, TrainingProfileRequest(input.sexAtBirth?.name?.lowercase(), input.birthDate, input.heightCentimeters, input.weightKilograms, current.primaryMotivation, current.preferredRunGoalType)) }.valueOrThrow()
        Unit
    }

    override suspend fun importHealthProfile(): Result<ImportedHealthProfile> = runCatching { currentAccount().id }.fold(
        onSuccess = { health.import(it) },
        onFailure = { Result.failure(it) },
    )

    override suspend fun completeOnboarding(input: RunnerProfileInput): Result<Unit> = runCatching {
        apiCall {
            personalization.updateProfile(
                authorization(),
                RunnerProfileRequest(
                    goalSummary = input.goal.goalSummary,
                    scheduleSummary = "${input.targetSessionsPerWeek} sessions/week; up to ${input.availableMinutes} minutes on weekdays",
                    comfortableDurationMinutes = input.comfortableMinutes,
                    recentSessionsPerWeek = input.recentSessionsPerWeek,
                    targetSessionsPerWeek = input.targetSessionsPerWeek,
                    preferredLongRunDay = input.preferredLongRunDay,
                    guidanceDetail = "balanced",
                    primaryMotivation = input.goal.motivation,
                    preferredRunGoalType = RunGoalType.time,
                    constraints = mapOf("maxWeekdayMinutes" to input.availableMinutes.toString()),
                    complete = true,
                ),
            )
        }.valueOrThrow()
        Unit
    }

    private suspend fun authorization(): String = sessions.validAccessToken()?.let { "Bearer $it" } ?: throw OnboardingDataException.SignedOut
}

sealed class OnboardingDataException : Exception() {
    data object SignedOut : OnboardingDataException()
    data class Api(val failure: com.plainstride.outbound.core.network.ApiFailure) : OnboardingDataException()
}

private fun <T> ApiResult<T>.valueOrThrow(): T = when (this) {
    is ApiResult.Success -> value
    is ApiResult.Failure -> throw OnboardingDataException.Api(error)
}

private val RunningGoal.goalSummary: String get() = when (this) {
    RunningGoal.Consistency -> "Build a consistent running habit"
    RunningGoal.Start -> "Start running safely"
    RunningGoal.Comeback -> "Return to running consistently"
    RunningGoal.Race -> "Prepare for a race"
    RunningGoal.Faster -> "Improve running performance"
}

private val RunningGoal.motivation: PrimaryMotivation get() = when (this) {
    RunningGoal.Consistency, RunningGoal.Comeback -> PrimaryMotivation.consistency
    RunningGoal.Race, RunningGoal.Faster -> PrimaryMotivation.performance
    RunningGoal.Start -> PrimaryMotivation.generalFitness
}
