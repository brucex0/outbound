package com.plainstride.outbound.feature.today

import kotlinx.coroutines.flow.Flow
import com.plainstride.outbound.core.model.ActivitySuggestionEnvelope
import com.plainstride.outbound.core.model.PersonalizationSnapshot
import com.plainstride.outbound.core.model.PlanningState
import com.plainstride.outbound.core.model.StandaloneWorkoutCatalog
import com.plainstride.outbound.core.model.TrainingProfile
import com.plainstride.outbound.core.network.CreateTrainingGoalRequest
import com.plainstride.outbound.core.network.PlannedWorkoutCompletionRequest
import com.plainstride.outbound.core.network.PlanningReadinessRequest
import com.plainstride.outbound.core.network.ReadinessCheckInRequest
import com.plainstride.outbound.core.network.RunnerProfileRequest
import com.plainstride.outbound.core.network.TrainingProfileRequest
import com.plainstride.outbound.core.network.WorkoutFeedbackRequest

sealed interface CachedResource<out T> {
    data object Loading : CachedResource<Nothing>
    data class Available<T>(val value: T, val isStale: Boolean, val updatedAtEpochMs: Long) : CachedResource<T>
    data class Failed<T>(val error: TodayDataError, val cachedValue: T? = null) : CachedResource<T>
}

sealed interface TodayDataError {
    data object SignedOut : TodayDataError
    data object Offline : TodayDataError
    data object InvalidServerResponse : TodayDataError
    data object PermissionDenied : TodayDataError
    data object NotFound : TodayDataError
    data object Conflict : TodayDataError
    data object RateLimited : TodayDataError
    data object ServerUnavailable : TodayDataError
    data class Unexpected(val requestId: String? = null) : TodayDataError
}

interface TodayRepository {
    fun observePlanning(accountId: String, localeTag: String): Flow<CachedResource<PlanningState>>
    fun observeSuggestion(accountId: String, localeTag: String): Flow<CachedResource<ActivitySuggestionEnvelope>>
    fun observePersonalization(accountId: String, localeTag: String): Flow<CachedResource<PersonalizationSnapshot>>
    fun observeStandaloneWorkouts(accountId: String, localeTag: String): Flow<CachedResource<StandaloneWorkoutCatalog>>
    suspend fun refresh(accountId: String, localeTag: String): TodayDataError?
    suspend fun createGoal(accountId: String, localeTag: String, request: CreateTrainingGoalRequest): Result<PlanningState>
    suspend fun submitPlanningReadiness(accountId: String, localeTag: String, request: PlanningReadinessRequest): Result<PlanningState>
    suspend fun skipWorkout(accountId: String, localeTag: String, workoutId: String): Result<PlanningState>
    suspend fun completeWorkout(accountId: String, localeTag: String, workoutId: String, request: PlannedWorkoutCompletionRequest): Result<PlanningState>
    suspend fun clearPlan(accountId: String, localeTag: String): Result<PlanningState>
    suspend fun updateRunnerProfile(accountId: String, localeTag: String, request: RunnerProfileRequest): Result<PersonalizationSnapshot>
    suspend fun submitReadiness(accountId: String, localeTag: String, request: ReadinessCheckInRequest): Result<PersonalizationSnapshot>
    suspend fun decideAdjustment(accountId: String, localeTag: String, adjustmentId: String, accept: Boolean): Result<Unit>
    suspend fun submitFeedback(accountId: String, localeTag: String, request: WorkoutFeedbackRequest): Result<PersonalizationSnapshot>
    suspend fun trainingProfile(): Result<TrainingProfile>
    suspend fun updateTrainingProfile(request: TrainingProfileRequest): Result<TrainingProfile>
}

class TodayRepositoryException(val dataError: TodayDataError) : Exception()
