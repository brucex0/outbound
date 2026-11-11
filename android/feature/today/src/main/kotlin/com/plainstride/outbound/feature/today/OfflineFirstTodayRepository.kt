package com.plainstride.outbound.feature.today

import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.KSerializer
import javax.inject.Inject
import com.plainstride.outbound.core.database.AccountCacheDao
import com.plainstride.outbound.core.database.AccountCacheEntity
import com.plainstride.outbound.core.model.ActivitySuggestionEnvelope
import com.plainstride.outbound.core.model.isCurrent
import com.plainstride.outbound.core.model.PersonalizationSnapshot
import com.plainstride.outbound.core.model.PlanningState
import com.plainstride.outbound.core.model.StandaloneWorkoutCatalog
import com.plainstride.outbound.core.model.TrainingProfile
import com.plainstride.outbound.core.network.AccessTokenProvider
import com.plainstride.outbound.core.network.AdjustmentDecisionRequest
import com.plainstride.outbound.core.network.ApiErrorCode
import com.plainstride.outbound.core.network.ApiFailure
import com.plainstride.outbound.core.network.ApiResult
import com.plainstride.outbound.core.network.CreateTrainingGoalRequest
import com.plainstride.outbound.core.network.PlanRecommendation
import com.plainstride.outbound.core.network.PlanRecommendationsResponse
import com.plainstride.outbound.core.network.PersonalizationMutationResponse
import com.plainstride.outbound.core.network.PlainstrideJson
import com.plainstride.outbound.core.network.PlannedWorkoutCompletionRequest
import com.plainstride.outbound.core.network.PlanningApiService
import com.plainstride.outbound.core.network.PlanningReadinessRequest
import com.plainstride.outbound.core.network.ReadinessCheckInRequest
import com.plainstride.outbound.core.network.RunnerProfileRequest
import com.plainstride.outbound.core.network.TrainingProfileRequest
import com.plainstride.outbound.core.network.WorkoutFeedbackRequest
import com.plainstride.outbound.core.network.apiCall
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.contentOrNull
import java.time.LocalDate

/** Account- and locale-scoped cache; workout IDs and launch prescriptions remain server-authored. */
class OfflineFirstTodayRepository @Inject constructor(
    @dagger.hilt.android.qualifiers.ApplicationContext private val context: android.content.Context,
    private val api: PlanningApiService,
    private val tokens: AccessTokenProvider,
    private val cache: AccountCacheDao,
    private val reads: com.plainstride.outbound.core.data.AccountReadRepository,
) : TodayRepository {
    private val refreshMutex = Mutex()

    override fun observePlanning(accountId: String, localeTag: String): Flow<CachedResource<PlanningState>> = reads.observePlanning(accountId).map { row ->
        if (row == null) CachedResource.Loading else CachedResource.Available(StructuredWorkoutText(context, localeTag).planning(row.value), row.stale, row.updatedAt)
    }
    override fun observeSuggestion(accountId: String, localeTag: String) = kotlinx.coroutines.flow.combine(
        observe(accountId, localeTag, SUGGESTION, ActivitySuggestionEnvelope.serializer()), reads.observePlanning(accountId), reads.observeClock(),
    ) { resource, planning, now ->
        val projected = resource.mapValue { envelope ->
            val belongsToOldPlan = planning != null && envelope.planContext != null && envelope.planContext?.planId != planning.value.plan?.id
            val expired = !envelope.isCurrent(now)
            val savedIds = planning?.value?.workouts.orEmpty().filter { it.status == "pending" || it.status == "completed" }.mapTo(mutableSetOf()) { it.id }
            val filtered = envelope.copy(primary = envelope.primary?.takeUnless { it.plannedWorkoutId in savedIds },
                alternates = envelope.alternates.filterNot { it.plannedWorkoutId in savedIds })
            StructuredWorkoutText(context, localeTag).envelope(if (belongsToOldPlan || expired)
                envelope.copy(primary = null, alternates = emptyList(), planContext = null) else filtered)
        }
        when (projected) {
            is CachedResource.Available -> projected.copy(isStale = projected.isStale || now.toEpochMilli() - projected.updatedAtEpochMs >= FIVE_MINUTES || !projected.value.isCurrent(now))
            else -> projected
        }
    }
    override fun observePersonalization(accountId: String, localeTag: String) = observe(accountId, localeTag, PERSONALIZATION, PersonalizationSnapshot.serializer())
    override fun observeStandaloneWorkouts(accountId: String, localeTag: String) = observe(accountId, localeTag, CATALOG, StandaloneWorkoutCatalog.serializer())

    override suspend fun refresh(accountId: String, localeTag: String): TodayDataError? = refreshMutex.withLock {
        val owner = reads.context(accountId) ?: return@withLock TodayDataError.SignedOut
        val authorization = tokens.validAccessToken(owner)?.let { "Bearer $it" } ?: return@withLock TodayDataError.SignedOut
        coroutineScope {
            val planning = async { apiCall { api.state(authorization) } }
            val suggestion = async { apiCall { api.activitySuggestion(authorization) } }
            val personalization = async { apiCall { api.personalization(authorization) } }
            val catalog = async { apiCall { api.standaloneWorkouts(authorization) } }
            listOf(
                persistResult(owner, accountId, localeTag, PLANNING, planning.await(), PlanningState.serializer(), FIVE_MINUTES),
                persistResult(owner, accountId, localeTag, SUGGESTION, suggestion.await(), ActivitySuggestionEnvelope.serializer(), FIVE_MINUTES),
                persistResult(owner, accountId, localeTag, PERSONALIZATION, personalization.await(), PersonalizationSnapshot.serializer(), FIVE_MINUTES),
                persistResult(owner, accountId, localeTag, CATALOG, catalog.await(), StandaloneWorkoutCatalog.serializer(), ONE_DAY),
            ).firstOrNull { it != null }.also {
                // Like iOS, retry queued check-ins after refreshing personalization.
                flushReadiness(accountId, localeTag)
            }
        }
    }

    override suspend fun createGoal(accountId: String, localeTag: String, request: CreateTrainingGoalRequest) = planningMutation(accountId, localeTag) { apiCall { api.createGoal(it, request) } }
    override suspend fun planRecommendations(): Result<PlanRecommendationsResponse> = authenticated { apiCall { api.recommendations(it) } }
    override suspend fun activatePlanRecommendation(accountId: String, localeTag: String, recommendation: PlanRecommendation): Result<PlanningState> {
        val request = runCatching { recommendation.activationGoalRequest() }.getOrElse { return Result.failure(it) }
        return createGoal(accountId, localeTag, request)
    }
    override suspend fun updateRunningBenchmark(accountId: String, localeTag: String, goalId: String, request: com.plainstride.outbound.core.network.RunningBenchmarkUpdateRequest) = planningMutation(accountId, localeTag) { apiCall { api.updateRunningBenchmark(it, goalId, request) } }
    override suspend fun updateRaceGoal(accountId: String, localeTag: String, goalId: String, request: com.plainstride.outbound.core.network.RaceGoalUpdateRequest) = planningMutation(accountId, localeTag) { apiCall { api.updateRaceGoal(it, goalId, request) } }
    override suspend fun submitPlanningReadiness(accountId: String, localeTag: String, request: PlanningReadinessRequest) = planningMutation(accountId, localeTag) { apiCall { api.submitPlanningReadiness(it, request) } }
    override suspend fun skipWorkout(accountId: String, localeTag: String, workoutId: String) = planningMutation(accountId, localeTag) { apiCall { api.skipWorkout(it, workoutId) } }
    override suspend fun completeWorkout(accountId: String, localeTag: String, workoutId: String, request: PlannedWorkoutCompletionRequest) = planningMutation(accountId, localeTag) { apiCall { api.completeWorkout(it, workoutId, request) } }
    override suspend fun clearPlan(accountId: String, localeTag: String) = refreshMutex.withLock {
        val owner = reads.context(accountId) ?: return@withLock Result.failure(TodayRepositoryException(TodayDataError.SignedOut))
        val endedPlanId = reads.observePlanning(accountId).first()?.value?.plan?.id
        if (!reads.isCurrent(owner)) return@withLock Result.failure(TodayRepositoryException(TodayDataError.SignedOut))
        planningMutation(accountId, localeTag) { apiCall { api.clearPlan(it) } }.onSuccess {
            // Serialize with refresh so an older response cannot resurrect the plan.
            // Clear only this plan across locales; preserve unrelated freestyle suggestions.
            if (endedPlanId != null && reads.isCurrent(owner)) {
                cache.entries(accountId, SUGGESTION).forEach { entity ->
                    val envelope = runCatching { PlainstrideJson.decodeFromString(ActivitySuggestionEnvelope.serializer(), entity.payloadJson) }
                        .onFailure { android.util.Log.w("PlainstridePlanning", "End plan cache lookup failed category=invalid_suggestion_cache") }
                        .getOrNull()
                    if (envelope?.planContext?.planId == endedPlanId) cache.delete(accountId, SUGGESTION, entity.cacheKey, entity.localeTag)
                }
            }
        }
    }
    override suspend fun updateRunnerProfile(accountId: String, localeTag: String, request: RunnerProfileRequest) = personalizationMutation(accountId, localeTag) { apiCall { api.updateProfile(it, request) } }
    override suspend fun submitReadiness(accountId: String, localeTag: String, request: ReadinessCheckInRequest): Result<PersonalizationSnapshot> = refreshMutex.withLock {
        val owner = reads.context(accountId) ?: return@withLock Result.failure(TodayRepositoryException(TodayDataError.SignedOut))
        // Persist before sending so a failed request or process interruption keeps its
        // original idempotency key. Account cache cleanup also removes these on sign-out.
        cache.upsert(AccountCacheEntity(accountId, READINESS_QUEUE, request.idempotencyKey, localeTag,
            PlainstrideJson.encodeToString(ReadinessCheckInRequest.serializer(), request), null, System.currentTimeMillis(), null))
        if (!reads.isCurrent(owner)) return@withLock Result.failure(TodayRepositoryException(TodayDataError.SignedOut))
        sendReadiness(accountId, localeTag, request).onSuccess {
            cache.delete(accountId, READINESS_QUEUE, request.idempotencyKey, localeTag)
        }
    }

    private suspend fun sendReadiness(accountId: String, localeTag: String, request: ReadinessCheckInRequest) =
        personalizationMutation(accountId, localeTag) { apiCall { api.submitReadiness(it, request) } }

    private suspend fun flushReadiness(accountId: String, localeTag: String) {
        for (entry in cache.entries(accountId, READINESS_QUEUE).sortedBy { it.updatedAtEpochMs }) {
            val request = runCatching { PlainstrideJson.decodeFromString(ReadinessCheckInRequest.serializer(), entry.payloadJson) }
                .onFailure { android.util.Log.w("PlainstridePlanning", "Readiness retry failed category=invalid_queue_entry") }
                .getOrNull() ?: break
            val result = sendReadiness(accountId, localeTag, request)
            if (result.isFailure) {
                val category = (result.exceptionOrNull() as? TodayRepositoryException)?.dataError?.javaClass?.simpleName ?: "unknown"
                android.util.Log.w("PlainstridePlanning", "Readiness retry failed category=$category")
                break
            }
            cache.delete(accountId, READINESS_QUEUE, entry.cacheKey, entry.localeTag)
        }
    }
    override suspend fun applyWorkoutAdjustment(accountId: String, localeTag: String, request: com.plainstride.outbound.core.network.WorkoutAdjustmentApplyRequest): Result<Unit> {
        val owner = reads.context(accountId) ?: return Result.failure(TodayRepositoryException(TodayDataError.SignedOut))
        val result = refreshMutex.withLock { authenticatedOwned(owner) { apiCall { api.applyWorkoutAdjustment(it, request) } } }
        if (result.isSuccess) reads.invalidate(owner)
        if (result.isFailure) return Result.failure(result.exceptionOrNull()!!)
        // Keep the same idempotency key if the mutation succeeded but refreshing failed.
        val error = refresh(accountId, localeTag)
        return if (error == null) Result.success(Unit) else Result.failure(TodayRepositoryException(error))
    }
    override suspend fun previewWorkoutAdjustment(request: com.plainstride.outbound.core.network.WorkoutAdjustmentPreviewRequest) =
        authenticated { apiCall { api.previewWorkoutAdjustment(it, request) } }.map { it.adjustment }
    override suspend fun decideAdjustment(accountId: String, localeTag: String, adjustmentId: String, accept: Boolean): Result<Unit> =
        planningSideEffect(accountId) { authorization ->
            apiCall {
                api.adjustmentDecision(
                    authorization,
                    adjustmentId,
                    AdjustmentDecisionRequest(if (accept) "accept" else "reject"),
                )
            }
        }.map { Unit }.onSuccess {
            // Clear the confirmed proposal before refetch, even if that refetch is offline.
            cache.get(accountId, PERSONALIZATION, DEFAULT_KEY, localeTag)?.let { entry ->
                val snapshot = runCatching { PlainstrideJson.decodeFromString(PersonalizationSnapshot.serializer(), entry.payloadJson) }
                    .onFailure { android.util.Log.w("PlainstridePlanning", "Adjustment decision cache update failed category=invalid_personalization_cache") }
                    .getOrNull()
                if (snapshot?.pendingAdjustment?.id == adjustmentId) {
                    persist(accountId, localeTag, PERSONALIZATION, snapshot.copy(pendingAdjustment = null), PersonalizationSnapshot.serializer(), FIVE_MINUTES)
                }
            }
            refresh(accountId, localeTag)
        }
    override suspend fun submitFeedback(accountId: String, localeTag: String, request: WorkoutFeedbackRequest) = personalizationMutation(accountId, localeTag) { apiCall { api.feedback(it, request.workoutId, request) } }
    override suspend fun trainingProfile() = authenticated { apiCall { api.trainingProfile(it) } }
    override suspend fun updateTrainingProfile(request: TrainingProfileRequest) = planningSideEffect(null) { apiCall { api.updateTrainingProfile(it, request) } }

    private suspend fun <T : Any> planningSideEffect(accountId: String?, call: suspend (String) -> ApiResult<T>): Result<T> {
        val owner = if (accountId != null) reads.context(accountId) else tokens.currentContext()
        if (owner == null) return Result.failure(TodayRepositoryException(TodayDataError.SignedOut))
        return authenticatedOwned(owner, call).onSuccess { reads.invalidate(owner) }
    }

    private suspend fun planningMutation(accountId: String, localeTag: String, call: suspend (String) -> ApiResult<PlanningState>): Result<PlanningState> {
        val owner = reads.context(accountId) ?: return Result.failure(TodayRepositoryException(TodayDataError.SignedOut))
        val auth = tokens.validAccessToken(owner)?.let { "Bearer $it" } ?: return Result.failure(TodayRepositoryException(TodayDataError.SignedOut))
        return when (val result = call(auth)) {
            is ApiResult.Success -> if (reads.isCurrent(owner)) {
                reads.acceptPlanning(owner, result.value, command = true)
                Result.success(result.value)
            } else Result.failure(TodayRepositoryException(TodayDataError.SignedOut))
            is ApiResult.Failure -> Result.failure(TodayRepositoryException(result.error.toTodayError()))
        }
    }

    private suspend fun personalizationMutation(accountId: String, localeTag: String, call: suspend (String) -> ApiResult<PersonalizationMutationResponse>): Result<PersonalizationSnapshot> {
        val owner = reads.context(accountId) ?: return Result.failure(TodayRepositoryException(TodayDataError.SignedOut))
        val result = authenticatedOwned(owner, call).map { response ->
            response.personalization.copy(pendingAdjustment = response.adjustment ?: response.personalization.pendingAdjustment)
        }
        result.onSuccess {
            persist(accountId, localeTag, PERSONALIZATION, it, PersonalizationSnapshot.serializer(), FIVE_MINUTES, owner)
            reads.invalidate(owner)
        }
        return result
    }

    private suspend fun <T : Any> authenticated(call: suspend (String) -> ApiResult<T>): Result<T> = authenticatedOwned(tokens.currentContext(), call)

    private suspend fun <T : Any> authenticatedOwned(owner: com.plainstride.outbound.core.network.AccountRequestContext?, call: suspend (String) -> ApiResult<T>): Result<T> {
        val token = if (owner != null) tokens.validAccessToken(owner) else tokens.validAccessToken()
        val auth = token?.let { "Bearer $it" } ?: return Result.failure(TodayRepositoryException(TodayDataError.SignedOut))
        return when (val result = call(auth)) {
            is ApiResult.Success -> if (owner == null || tokens.isCurrent(owner)) Result.success(result.value) else Result.failure(TodayRepositoryException(TodayDataError.SignedOut))
            is ApiResult.Failure -> Result.failure(TodayRepositoryException(result.error.toTodayError()))
        }
    }

    private fun <T : Any> observe(accountId: String, localeTag: String, namespace: String, serializer: KSerializer<T>): Flow<CachedResource<T>> =
        cache.observe(accountId, namespace, DEFAULT_KEY, localeTag).map { entity ->
            if (entity == null) return@map CachedResource.Loading
            val value = runCatching { PlainstrideJson.decodeFromString(serializer, entity.payloadJson) }.getOrNull()
                ?: return@map CachedResource.Failed(TodayDataError.InvalidServerResponse)
            CachedResource.Available(value, entity.expiresAtEpochMs?.let { it <= System.currentTimeMillis() } == true, entity.updatedAtEpochMs)
        }

    private suspend fun <T : Any> persistResult(owner: com.plainstride.outbound.core.network.AccountRequestContext, accountId: String, localeTag: String, namespace: String, result: ApiResult<T>, serializer: KSerializer<T>, ttlMs: Long): TodayDataError? = when (result) {
        is ApiResult.Success -> { persist(accountId, localeTag, namespace, result.value, serializer, ttlMs, owner); null }
        is ApiResult.Failure -> result.error.toTodayError()
    }

    private suspend fun <T : Any> persist(accountId: String, localeTag: String, namespace: String, value: T, serializer: KSerializer<T>, ttlMs: Long, owner: com.plainstride.outbound.core.network.AccountRequestContext? = reads.context(accountId)) {
        if (owner == null || !reads.isCurrent(owner)) return
        if (namespace == PLANNING && value is PlanningState) { reads.acceptPlanning(owner, value); return }
        val now = System.currentTimeMillis()
        cache.upsert(AccountCacheEntity(accountId, namespace, DEFAULT_KEY, localeTag, PlainstrideJson.encodeToString(serializer, value), null, now, now + ttlMs))
    }

    private companion object {
        const val DEFAULT_KEY = "current"
        const val PLANNING = "planning.state.v2"
        const val SUGGESTION = "planning.suggestion"
        const val PERSONALIZATION = "personalization.snapshot"
        const val READINESS_QUEUE = "personalization.readiness_queue"
        const val CATALOG = "planning.standalone_catalog"
        const val FIVE_MINUTES = 5 * 60 * 1_000L
        const val ONE_DAY = 24 * 60 * 60 * 1_000L
    }
}

private fun ApiFailure.toTodayError(): TodayDataError = when (code) {
    ApiErrorCode.RunningScheduleConflict -> TodayDataError.RunningScheduleConflict
    ApiErrorCode.ProgrammeTimelineConflict -> TodayDataError.ProgrammeTimelineConflict
    ApiErrorCode.ProgrammeConstraintsConflict -> TodayDataError.ProgrammeConstraintsConflict
    ApiErrorCode.RunningBenchmarkInvalid -> TodayDataError.RunningBenchmarkInvalid
    ApiErrorCode.GoalTimelineUnrealistic -> TodayDataError.GoalTimelineUnrealistic
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
