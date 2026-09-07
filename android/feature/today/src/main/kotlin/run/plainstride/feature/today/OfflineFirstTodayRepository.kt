package run.plainstride.feature.today

import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.KSerializer
import run.plainstride.core.database.AccountCacheDao
import run.plainstride.core.database.AccountCacheEntity
import run.plainstride.core.model.ActivitySuggestionEnvelope
import run.plainstride.core.model.PersonalizationSnapshot
import run.plainstride.core.model.PlanningState
import run.plainstride.core.model.StandaloneWorkoutCatalog
import run.plainstride.core.model.TrainingProfile
import run.plainstride.core.network.AccessTokenProvider
import run.plainstride.core.network.ApiErrorCode
import run.plainstride.core.network.ApiFailure
import run.plainstride.core.network.ApiResult
import run.plainstride.core.network.CreateTrainingGoalRequest
import run.plainstride.core.network.PersonalizationMutationResponse
import run.plainstride.core.network.PlainstrideJson
import run.plainstride.core.network.PlannedWorkoutCompletionRequest
import run.plainstride.core.network.PlanningApiService
import run.plainstride.core.network.PlanningReadinessRequest
import run.plainstride.core.network.ReadinessCheckInRequest
import run.plainstride.core.network.RunnerProfileRequest
import run.plainstride.core.network.TrainingProfileRequest
import run.plainstride.core.network.WorkoutFeedbackRequest
import run.plainstride.core.network.apiCall

/** Account- and locale-scoped cache; workout IDs and launch prescriptions remain server-authored. */
class OfflineFirstTodayRepository(
    private val api: PlanningApiService,
    private val tokens: AccessTokenProvider,
    private val cache: AccountCacheDao,
    private val nowEpochMs: () -> Long = System::currentTimeMillis,
) : TodayRepository {
    private val refreshMutex = Mutex()

    override fun observePlanning(accountId: String, localeTag: String) = observe(accountId, localeTag, PLANNING, PlanningState.serializer())
    override fun observeSuggestion(accountId: String, localeTag: String) = observe(accountId, localeTag, SUGGESTION, ActivitySuggestionEnvelope.serializer())
    override fun observePersonalization(accountId: String, localeTag: String) = observe(accountId, localeTag, PERSONALIZATION, PersonalizationSnapshot.serializer())
    override fun observeStandaloneWorkouts(accountId: String, localeTag: String) = observe(accountId, localeTag, CATALOG, StandaloneWorkoutCatalog.serializer())

    override suspend fun refresh(accountId: String, localeTag: String): TodayDataError? = refreshMutex.withLock {
        val authorization = authorization() ?: return@withLock TodayDataError.SignedOut
        coroutineScope {
            val planning = async { apiCall { api.state(authorization) } }
            val suggestion = async { apiCall { api.activitySuggestion(authorization) } }
            val personalization = async { apiCall { api.personalization(authorization) } }
            val catalog = async { apiCall { api.standaloneWorkouts(authorization) } }
            listOf(
                persistResult(accountId, localeTag, PLANNING, planning.await(), PlanningState.serializer(), FIVE_MINUTES),
                persistResult(accountId, localeTag, SUGGESTION, suggestion.await(), ActivitySuggestionEnvelope.serializer(), FIVE_MINUTES),
                persistResult(accountId, localeTag, PERSONALIZATION, personalization.await(), PersonalizationSnapshot.serializer(), FIVE_MINUTES),
                persistResult(accountId, localeTag, CATALOG, catalog.await(), StandaloneWorkoutCatalog.serializer(), ONE_DAY),
            ).firstOrNull { it != null }
        }
    }

    override suspend fun createGoal(accountId: String, localeTag: String, request: CreateTrainingGoalRequest) = planningMutation(accountId, localeTag) { apiCall { api.createGoal(it, request) } }
    override suspend fun submitPlanningReadiness(accountId: String, localeTag: String, request: PlanningReadinessRequest) = planningMutation(accountId, localeTag) { apiCall { api.submitPlanningReadiness(it, request) } }
    override suspend fun skipWorkout(accountId: String, localeTag: String, workoutId: String) = planningMutation(accountId, localeTag) { apiCall { api.skipWorkout(it, workoutId) } }
    override suspend fun completeWorkout(accountId: String, localeTag: String, workoutId: String, request: PlannedWorkoutCompletionRequest) = planningMutation(accountId, localeTag) { apiCall { api.completeWorkout(it, workoutId, request) } }
    override suspend fun clearPlan(accountId: String, localeTag: String) = planningMutation(accountId, localeTag) { apiCall { api.clearPlan(it) } }
    override suspend fun updateRunnerProfile(accountId: String, localeTag: String, request: RunnerProfileRequest) = personalizationMutation(accountId, localeTag) { apiCall { api.updateProfile(it, request) } }
    override suspend fun submitReadiness(accountId: String, localeTag: String, request: ReadinessCheckInRequest) = personalizationMutation(accountId, localeTag) { apiCall { api.submitReadiness(it, request) } }
    override suspend fun submitFeedback(accountId: String, localeTag: String, request: WorkoutFeedbackRequest) = personalizationMutation(accountId, localeTag) { apiCall { api.feedback(it, request.workoutId, request) } }
    override suspend fun trainingProfile() = authenticated { apiCall { api.trainingProfile(it) } }
    override suspend fun updateTrainingProfile(request: TrainingProfileRequest) = authenticated { apiCall { api.updateTrainingProfile(it, request) } }

    private suspend fun planningMutation(accountId: String, localeTag: String, call: suspend (String) -> ApiResult<PlanningState>): Result<PlanningState> = authenticated(call).onSuccess {
        persist(accountId, localeTag, PLANNING, it, PlanningState.serializer(), FIVE_MINUTES)
    }

    private suspend fun personalizationMutation(accountId: String, localeTag: String, call: suspend (String) -> ApiResult<PersonalizationMutationResponse>): Result<PersonalizationSnapshot> {
        val result = authenticated(call).map { it.personalization }
        result.onSuccess { persist(accountId, localeTag, PERSONALIZATION, it, PersonalizationSnapshot.serializer(), FIVE_MINUTES) }
        return result
    }

    private suspend fun <T : Any> authenticated(call: suspend (String) -> ApiResult<T>): Result<T> {
        val auth = authorization() ?: return Result.failure(TodayRepositoryException(TodayDataError.SignedOut))
        return when (val result = call(auth)) {
            is ApiResult.Success -> Result.success(result.value)
            is ApiResult.Failure -> Result.failure(TodayRepositoryException(result.error.toTodayError()))
        }
    }

    private suspend fun authorization() = tokens.validAccessToken()?.let { "Bearer $it" }

    private fun <T : Any> observe(accountId: String, localeTag: String, namespace: String, serializer: KSerializer<T>): Flow<CachedResource<T>> =
        cache.observe(accountId, namespace, DEFAULT_KEY, localeTag).map { entity ->
            if (entity == null) return@map CachedResource.Loading
            val value = runCatching { PlainstrideJson.decodeFromString(serializer, entity.payloadJson) }.getOrNull()
                ?: return@map CachedResource.Failed(TodayDataError.InvalidServerResponse)
            CachedResource.Available(value, entity.expiresAtEpochMs?.let { it <= nowEpochMs() } == true)
        }

    private suspend fun <T : Any> persistResult(accountId: String, localeTag: String, namespace: String, result: ApiResult<T>, serializer: KSerializer<T>, ttlMs: Long): TodayDataError? = when (result) {
        is ApiResult.Success -> { persist(accountId, localeTag, namespace, result.value, serializer, ttlMs); null }
        is ApiResult.Failure -> result.error.toTodayError()
    }

    private suspend fun <T : Any> persist(accountId: String, localeTag: String, namespace: String, value: T, serializer: KSerializer<T>, ttlMs: Long) {
        val now = nowEpochMs()
        cache.upsert(AccountCacheEntity(accountId, namespace, DEFAULT_KEY, localeTag, PlainstrideJson.encodeToString(serializer, value), null, now, now + ttlMs))
    }

    private companion object {
        const val DEFAULT_KEY = "current"
        const val PLANNING = "planning.state"
        const val SUGGESTION = "planning.suggestion"
        const val PERSONALIZATION = "personalization.snapshot"
        const val CATALOG = "planning.standalone_catalog"
        const val FIVE_MINUTES = 5 * 60 * 1_000L
        const val ONE_DAY = 24 * 60 * 60 * 1_000L
    }
}

private fun ApiFailure.toTodayError(): TodayDataError = when (code) {
    ApiErrorCode.Unauthenticated -> TodayDataError.SignedOut
    ApiErrorCode.NetworkUnavailable -> TodayDataError.Offline
    ApiErrorCode.InvalidResponse, ApiErrorCode.InvalidRequest -> TodayDataError.InvalidServerResponse
    ApiErrorCode.Forbidden -> TodayDataError.PermissionDenied
    ApiErrorCode.NotFound -> TodayDataError.NotFound
    ApiErrorCode.Conflict -> TodayDataError.Conflict
    ApiErrorCode.RateLimited -> TodayDataError.RateLimited
    ApiErrorCode.ServerUnavailable -> TodayDataError.ServerUnavailable
    ApiErrorCode.Cancelled, ApiErrorCode.Unknown -> TodayDataError.Unexpected(requestId)
}
