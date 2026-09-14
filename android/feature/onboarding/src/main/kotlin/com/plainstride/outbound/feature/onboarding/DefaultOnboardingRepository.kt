package com.plainstride.outbound.feature.onboarding

import javax.inject.Inject
import com.plainstride.outbound.core.auth.SessionCoordinator
import com.plainstride.outbound.core.model.PrimaryMotivation
import com.plainstride.outbound.core.model.RunGoalType
import com.plainstride.outbound.core.model.PlanningState
import com.plainstride.outbound.core.network.AccountApiService
import com.plainstride.outbound.core.network.ApiResult
import com.plainstride.outbound.core.network.CreateTrainingGoalRequest
import com.plainstride.outbound.core.network.PlanningApiService
import com.plainstride.outbound.core.network.PlanIntakeContext
import com.plainstride.outbound.core.network.PlanIntakeInterpretRequest
import com.plainstride.outbound.core.network.PlanIntakeInterpretation
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
            account.resolvedOnboardingStatus(),
        )
    }

    override suspend fun updateIdentity(displayName: String, username: String, contactEmail: String?): Result<OnboardingAccount> = runCatching {
        val account = apiCall {
            accounts.updateAccount(
                authorization(),
                UpdateAccountRequest(username = username, displayName = displayName, contactEmail = contactEmail),
            )
        }.valueOrThrow()
        OnboardingAccount(account.id, account.displayName, account.username, account.normalizedEmail, account.resolvedOnboardingStatus())
    }

    override suspend fun updateTrainingProfile(input: TrainingProfileInput): Result<Unit> = runCatching {
        val authorization = authorization()
        apiCall {
            personalization.updateTrainingProfile(
                authorization,
                TrainingProfileRequest(
                    input.sexAtBirth?.name?.lowercase(),
                    input.birthDate,
                    input.heightCentimeters,
                    input.weightKilograms,
                    input.objective.primaryMotivation,
                    input.objective.preferredRunGoalType,
                ),
            )
        }.valueOrThrow()
        Unit
    }

    override suspend fun importHealthProfile(): Result<ImportedHealthProfile> = runCatching { currentAccount().id }.fold(
        onSuccess = { health.import(it) },
        onFailure = { Result.failure(it) },
    )

    override suspend fun skipOnboarding(): Result<OnboardingStatus> = runCatching {
        apiCall { accounts.skipOnboarding(authorization()) }.valueOrThrow().onboardingStatus.toStatus()
    }

    override suspend fun createPlan(input: PlanBuilderInput): Result<PlanningState> = runCatching {
        apiCall {
            personalization.createGoal(
                authorization(),
                CreateTrainingGoalRequest(
                    type = input.objective.wireValue,
                    activities = input.activities.map { it.modality },
                    baselineContext = input.baselineContext.wireValue,
                    targetDate = input.eventDate.takeIf { input.objective == PlanObjective.EventPreparation },
                    targetDistanceMeters = input.eventDistanceMeters.takeIf { input.objective == PlanObjective.EventPreparation },
                    eventIntent = input.eventIntent.takeIf { input.objective == PlanObjective.EventPreparation },
                    targetTimeSeconds = input.targetTimeSeconds.takeIf { input.objective == PlanObjective.EventPreparation },
                    reviewHorizonWeeks = input.reviewHorizonWeeks.takeUnless { input.objective == PlanObjective.EventPreparation },
                    successSignal = input.successSignal.takeIf(String::isNotBlank),
                    goalDescription = input.goalDescription.takeIf(String::isNotBlank),
                    intakeContextVersion = input.intakeContextVersion,
                    priority = if (input.objective == PlanObjective.EventPreparation) "finish" else "generalHealth",
                    preferredDays = input.preferredDays,
                    daysPerWeekTarget = input.sessionsPerWeek,
                    maxSessionMinutes = input.availableMinutes,
                    riskTolerance = if (input.baselineContext == PlanBaselineContext.ReturningAfterBreak) "conservative" else "balanced",
                    constraints = buildMap {
                        input.constraints.takeIf(String::isNotBlank)?.let { put("notes", it) }
                    },
                ),
            )
        }.valueOrThrow()
    }

    override suspend fun planIntakeContext(objective: PlanObjective?): Result<PlanIntakeContext> = runCatching {
        apiCall { personalization.planIntakeContext(authorization(), objective?.wireValue) }.valueOrThrow()
    }

    override suspend fun interpretPlanIntake(input: PlanIntakeInterpretRequest): Result<PlanIntakeInterpretation> = runCatching {
        apiCall { personalization.interpretPlanIntake(authorization(), input) }.valueOrThrow()
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

private fun com.plainstride.outbound.core.network.AccountDto.resolvedOnboardingStatus() =
    onboardingStatus?.toStatus() ?: if (onboardingCompleted == true) OnboardingStatus.completed else OnboardingStatus.pending

private fun String.toStatus() = runCatching { OnboardingStatus.valueOf(this) }.getOrDefault(OnboardingStatus.pending)

private val PlanObjective.wireValue: String get() = when (this) {
    PlanObjective.EventPreparation -> "eventPreparation"
    PlanObjective.Endurance -> "endurance"
    PlanObjective.Speed -> "speed"
    PlanObjective.WeightLoss -> "weightLoss"
    PlanObjective.HealthEnergy -> "healthEnergy"
}

private val PlanBaselineContext.wireValue: String get() = when (this) {
    PlanBaselineContext.StartingOut -> "startingOut"
    PlanBaselineContext.CurrentlyActive -> "currentlyActive"
    PlanBaselineContext.ReturningAfterBreak -> "returningAfterBreak"
}

private val PlanObjective.primaryMotivation: PrimaryMotivation get() = when (this) {
    PlanObjective.EventPreparation, PlanObjective.Endurance, PlanObjective.Speed -> PrimaryMotivation.performance
    PlanObjective.WeightLoss -> PrimaryMotivation.weightLoss
    PlanObjective.HealthEnergy -> PrimaryMotivation.generalFitness
}

private val PlanObjective.preferredRunGoalType: RunGoalType get() = when (this) {
    PlanObjective.EventPreparation, PlanObjective.Endurance -> RunGoalType.distance
    PlanObjective.WeightLoss -> RunGoalType.calories
    PlanObjective.Speed, PlanObjective.HealthEnergy -> RunGoalType.time
}
