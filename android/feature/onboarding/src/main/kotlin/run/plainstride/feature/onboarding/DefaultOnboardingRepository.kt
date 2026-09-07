package run.plainstride.feature.onboarding

import javax.inject.Inject
import run.plainstride.core.auth.SessionCoordinator
import run.plainstride.core.model.PrimaryMotivation
import run.plainstride.core.model.RunGoalType
import run.plainstride.core.network.AccountApiService
import run.plainstride.core.network.ApiResult
import run.plainstride.core.network.PlanningApiService
import run.plainstride.core.network.RunnerProfileRequest
import run.plainstride.core.network.TrainingProfileRequest
import run.plainstride.core.network.UpdateAccountRequest
import run.plainstride.core.network.apiCall

class DefaultOnboardingRepository @Inject constructor(
    private val accounts: AccountApiService,
    private val personalization: PlanningApiService,
    private val sessions: SessionCoordinator,
    private val health: HealthProfileImporter,
) : OnboardingRepository {
    override suspend fun currentAccount(): OnboardingAccount {
        val authorization = authorization()
        val account = apiCall { accounts.currentAccount(authorization) }.valueOrThrow()
        val snapshot = apiCall { personalization.personalization(authorization) }.valueOrThrow()
        return OnboardingAccount(account.id, account.displayName, account.username, account.normalizedEmail, snapshot.calibration.status.name != "notStarted")
    }

    override suspend fun updateIdentity(displayName: String, username: String, contactEmail: String?): Result<OnboardingAccount> = runCatching {
        val account = apiCall { accounts.updateAccount(authorization(), UpdateAccountRequest(username, displayName, contactEmail)) }.valueOrThrow()
        OnboardingAccount(account.id, account.displayName, account.username, account.normalizedEmail, false)
    }

    override suspend fun updateTrainingProfile(input: TrainingProfileInput): Result<Unit> = runCatching {
        val authorization = authorization()
        val current = apiCall { personalization.trainingProfile(authorization) }.valueOrThrow()
        apiCall { personalization.updateTrainingProfile(authorization, TrainingProfileRequest(input.sexAtBirth?.name?.lowercase(), input.birthDate, input.heightCentimeters, input.weightKilograms, current.primaryMotivation, current.preferredRunGoalType)) }.valueOrThrow()
        Unit
    }

    override suspend fun importHealthProfile(): Result<ImportedHealthProfile> = health.import()

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
    data class Api(val failure: run.plainstride.core.network.ApiFailure) : OnboardingDataException()
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
