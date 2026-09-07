package run.plainstride.feature.today

import kotlinx.coroutines.flow.Flow
import run.plainstride.core.model.ActivitySuggestionEnvelope
import run.plainstride.core.model.PersonalizationSnapshot
import run.plainstride.core.model.PlanningState
import run.plainstride.core.model.StandaloneWorkoutCatalog
import run.plainstride.core.model.TrainingProfile
import run.plainstride.core.network.CreateTrainingGoalRequest
import run.plainstride.core.network.PlannedWorkoutCompletionRequest
import run.plainstride.core.network.PlanningReadinessRequest
import run.plainstride.core.network.ReadinessCheckInRequest
import run.plainstride.core.network.RunnerProfileRequest
import run.plainstride.core.network.TrainingProfileRequest
import run.plainstride.core.network.WorkoutFeedbackRequest

sealed interface CachedResource<out T> {
    data object Loading : CachedResource<Nothing>
    data class Available<T>(val value: T, val isStale: Boolean) : CachedResource<T>
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
    suspend fun submitFeedback(accountId: String, localeTag: String, request: WorkoutFeedbackRequest): Result<PersonalizationSnapshot>
    suspend fun trainingProfile(): Result<TrainingProfile>
    suspend fun updateTrainingProfile(request: TrainingProfileRequest): Result<TrainingProfile>
}

class TodayRepositoryException(val dataError: TodayDataError) : Exception()
