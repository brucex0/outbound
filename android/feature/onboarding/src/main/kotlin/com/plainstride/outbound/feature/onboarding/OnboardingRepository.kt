package com.plainstride.outbound.feature.onboarding

import com.plainstride.outbound.core.model.PlanningState
import com.plainstride.outbound.core.network.PlanIntakeContext
import com.plainstride.outbound.core.network.PlanIntakeInterpretRequest
import com.plainstride.outbound.core.network.PlanIntakeInterpretation

/** Network/data boundary. Implementations must scope all reads and writes to [OnboardingAccount.id]. */
interface OnboardingRepository {
    suspend fun currentAccount(): OnboardingAccount
    suspend fun updateIdentity(displayName: String, username: String, contactEmail: String?): Result<OnboardingAccount>
    suspend fun updateTrainingProfile(input: TrainingProfileInput): Result<Unit>
    suspend fun importHealthProfile(): Result<ImportedHealthProfile>
    suspend fun skipOnboarding(): Result<OnboardingStatus>
    suspend fun createPlan(input: PlanBuilderInput): Result<PlanningState>
    suspend fun planIntakeContext(objective: PlanObjective? = null): Result<PlanIntakeContext>
    suspend fun interpretPlanIntake(input: PlanIntakeInterpretRequest): Result<PlanIntakeInterpretation>
}
