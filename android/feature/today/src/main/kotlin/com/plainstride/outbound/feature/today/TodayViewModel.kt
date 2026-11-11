package com.plainstride.outbound.feature.today

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import java.time.Instant
import java.util.Locale
import java.util.UUID
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.ensureActive
import com.plainstride.outbound.core.analytics.AnalyticsEvent
import com.plainstride.outbound.core.analytics.AnalyticsProperty
import com.plainstride.outbound.core.analytics.ProductAnalytics
import com.plainstride.outbound.core.model.ActivitySuggestion
import com.plainstride.outbound.core.model.ActivitySuggestionEnvelope
import com.plainstride.outbound.core.model.isCurrent
import com.plainstride.outbound.core.model.AdjustmentProposal
import com.plainstride.outbound.core.model.Modality
import com.plainstride.outbound.core.model.PersonalizationSnapshot
import com.plainstride.outbound.core.model.PlanningState
import com.plainstride.outbound.core.model.StandaloneWorkoutCatalog
import com.plainstride.outbound.core.model.TrainingStimulus
import com.plainstride.outbound.core.network.WorkoutAdjustmentApplyRequest
import com.plainstride.outbound.core.network.PlanRecommendation
import com.plainstride.outbound.core.data.ActivityRepository
import com.plainstride.outbound.core.model.CalibrationStatus
import com.plainstride.outbound.core.model.activity.ActivityFacts
import com.plainstride.outbound.core.model.activity.PlannedCalorieEstimate
import com.plainstride.outbound.core.model.activity.WorkoutCalorieEstimator

enum class TodayConstraint(val wireValue: String) {
    LowEnergy("tired"),
    Soreness("sore"),
    LimitedTime("shortOnTime"),
}

data class TodayUiState(
    val planning: CachedResource<PlanningState> = CachedResource.Loading,
    val suggestion: CachedResource<ActivitySuggestionEnvelope> = CachedResource.Loading,
    val personalization: CachedResource<PersonalizationSnapshot> = CachedResource.Loading,
    val catalog: CachedResource<StandaloneWorkoutCatalog> = CachedResource.Loading,
    val refreshing: Boolean = false,
    val mutationInFlight: Boolean = false,
    val refreshError: TodayDataError? = null,
    val activeSession: Boolean = false,
    val completedToday: Boolean = false,
) {
    val planningSnapshot: PlanningState?
        get() = when (planning) {
            is CachedResource.Available -> planning.value
            is CachedResource.Failed -> planning.cachedValue
            CachedResource.Loading -> null
        }
    val currentRecommendationSnapshot: ActivitySuggestionEnvelope?
        get() {
            val snapshot = when (suggestion) {
                is CachedResource.Available -> suggestion.value
                is CachedResource.Failed -> suggestion.cachedValue
                CachedResource.Loading -> null
            } ?: return null
            return snapshot.takeIf {
                it.primary != null && it.isCurrent()
            }
        }
    val restRecommended: Boolean
        get() = (suggestion as? CachedResource.Available)?.value?.let { it.isCurrent() && it.status == "restRecommended" } == true
    val hasConfirmedNoPlan: Boolean
        get() {
            val snapshot = planning as? CachedResource.Available ?: return false
            val planSuggestion = when (suggestion) {
                is CachedResource.Available -> suggestion.value.takeUnless { suggestion.isStale }
                is CachedResource.Failed -> suggestion.cachedValue
                CachedResource.Loading -> null
            }
            val hasCurrentPlanSuggestion = planSuggestion?.planContext != null &&
                planSuggestion.isCurrent()
            return snapshot.value.plan == null && !snapshot.isStale && !refreshing &&
                refreshError == null && !hasCurrentPlanSuggestion
        }
    val primarySuggestion: ActivitySuggestion?
        get() = (suggestion as? CachedResource.Available)?.value?.primary
    val pendingAdjustment: AdjustmentProposal?
        get() = when (personalization) {
            is CachedResource.Available -> personalization.value.pendingAdjustment
            is CachedResource.Failed -> personalization.cachedValue?.pendingAdjustment
            CachedResource.Loading -> null
        }
    val isStale: Boolean
        get() = (suggestion as? CachedResource.Available)?.isStale == true
    val suggestionUpdatedAtEpochMs: Long?
        get() = (suggestion as? CachedResource.Available)?.updatedAtEpochMs
    val hasNoCachedSuggestion: Boolean
        get() = suggestion is CachedResource.Failed || (suggestion is CachedResource.Loading && refreshError != null) ||
            (suggestion is CachedResource.Available && suggestion.value.primary == null)
}

data class PlanPickerUiState(
    val open: Boolean = false,
    val loading: Boolean = false,
    val recommendations: List<PlanRecommendation> = emptyList(),
    val selected: PlanRecommendation? = null,
    val replacing: Boolean = false,
    val error: Boolean = false,
    val loadingError: Boolean = false,
    val constraintError: TodayDataError? = null,
)

sealed interface TodayMessage {
    data object CouldNotRefresh : TodayMessage
    data object ReadinessSavedOffline : TodayMessage
    data object CouldNotAdjust : TodayMessage
    data object AdjustmentApplied : TodayMessage
    data object OriginalKept : TodayMessage
    data object PlanEnded : TodayMessage
    data object CouldNotEndPlan : TodayMessage
}

@HiltViewModel
class TodayViewModel @Inject constructor(
    private val repository: TodayRepository,
    private val analytics: ProductAnalytics,
    private val weatherPolicy: TodayWeatherPolicy,
    private val activities: ActivityRepository,
) : ViewModel() {
    // A single encrypted session is active at a time; account bootstrap can later provide the
    // opaque server account ID without exposing identity details to this feature.
    private val accountScope = MutableStateFlow("authenticated_account" to Locale.getDefault().toLanguageTag())
    private val refreshing = MutableStateFlow(false)
    private val mutationInFlight = MutableStateFlow(false)
    private val refreshError = MutableStateFlow<TodayDataError?>(null)
    private val sessionState = MutableStateFlow(false to false)
    val messages = MutableSharedFlow<TodayMessage>(extraBufferCapacity = 1)
    private val mutableWeather = MutableStateFlow<WeatherGuidance?>(null)
    val weather = mutableWeather
    private val mutablePlanPicker = MutableStateFlow(PlanPickerUiState())
    val planPicker = mutablePlanPicker

    val raceHistory = accountScope.flatMapLatest { activities.observeAll(it.first) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val state = combine(
        accountScope.flatMapLatest { repository.observePlanning(it.first, it.second) },
        accountScope.flatMapLatest { repository.observeSuggestion(it.first, it.second) },
        accountScope.flatMapLatest { repository.observePersonalization(it.first, it.second) },
        accountScope.flatMapLatest { repository.observeStandaloneWorkouts(it.first, it.second) },
        combine(refreshing, mutationInFlight, refreshError, sessionState) { a, b, c, d -> Meta(a, b, c, d) },
    ) { planning, suggestion, personalization, catalog, meta ->
        val plannedCompletion = (planning as? CachedResource.Available)?.value?.today?.status == "completed"
        TodayUiState(planning, suggestion, personalization, catalog, meta.refreshing, meta.mutating, meta.error, meta.session.first, plannedCompletion)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), TodayUiState())

    init { refreshWeather() }

    fun configure(accountId: String, localeTag: String) {
        if (accountScope.value == accountId to localeTag) return
        accountScope.value = accountId to localeTag
        refresh()
    }

    fun refreshWeather() = viewModelScope.launch {
        when (val result = weatherPolicy.guidance()) {
            is TodayWeatherResult.Available -> mutableWeather.value = result.guidance
            TodayWeatherResult.PermissionRequired -> Unit
            TodayWeatherResult.Unavailable -> Unit
        }
    }

    fun updateSessionState(active: Boolean, completedToday: Boolean) {
        sessionState.value = active to completedToday
    }

    fun openPlanPicker(entrySource: String = "today_planned_card_change") {
        mutablePlanPicker.value = PlanPickerUiState(open = true, loading = true)
        analytics.record(AnalyticsEvent("planning_surface_opened", mapOf(
            AnalyticsProperty.SourceType to "plan_picker",
            AnalyticsProperty.EntrySource to entrySource,
        )))
        viewModelScope.launch {
            repository.planRecommendations().fold(
                onSuccess = { response -> mutablePlanPicker.value = mutablePlanPicker.value.copy(loading = false, recommendations = response.recommendations) },
                onFailure = { mutablePlanPicker.value = mutablePlanPicker.value.copy(loading = false, error = true, loadingError = true) },
            )
        }
    }

    fun trackPlanDetailsOpened(workoutCount: Int, entrySource: String) {
        analytics.record(AnalyticsEvent("planning_surface_opened", mapOf(
            AnalyticsProperty.SourceType to "plan_details",
            AnalyticsProperty.EntrySource to entrySource,
            AnalyticsProperty.CountBucket to when (workoutCount) {
                0 -> "0"
                1 -> "1"
                in 2..3 -> "2_3"
                in 4..7 -> "4_7"
                else -> "8_plus"
            },
        )))
        val progress = (state.value.planning as? CachedResource.Available)?.value?.currentVersion?.engineDecision
        if (progress?.programmeDoseStatus == "needs_review" || progress?.programmeTimelineStatus == "needs_review") {
            analytics.record(AnalyticsEvent("feature_exposed", mapOf(AnalyticsProperty.Feature to "running_programme_review")))
        }
    }

    fun trackDailyRecommendationDetailsOpened(entrySource: String) = analytics.record(AnalyticsEvent("planning_surface_opened", mapOf(
        AnalyticsProperty.SourceType to "daily_recommendation_details",
        AnalyticsProperty.EntrySource to entrySource,
    )))

    fun trackEndPlanConfirmation() = analytics.record(AnalyticsEvent("feature_exposed", mapOf(
        AnalyticsProperty.Feature to "plan_end_confirmation",
    )))

    fun endPlan() {
        if (mutationInFlight.value) return
        viewModelScope.launch {
            mutationInFlight.value = true
            val (accountId, localeTag) = accountScope.value
            try {
                val result = try {
                    repository.clearPlan(accountId, localeTag)
                } catch (error: Exception) {
                    if (error is kotlinx.coroutines.CancellationException) throw error
                    Result.failure(error)
                }
                result.fold(
                    onSuccess = {
                        analytics.record(AnalyticsEvent("training_plan_ended", mapOf(AnalyticsProperty.EntrySource to "plan_details")))
                        messages.emit(TodayMessage.PlanEnded)
                        refresh()
                    },
                    onFailure = { error ->
                        if (error is kotlinx.coroutines.CancellationException) throw error
                        kotlinx.coroutines.currentCoroutineContext().ensureActive()
                        val category = (error as? TodayRepositoryException)?.dataError?.javaClass?.simpleName ?: error.javaClass.simpleName
                        android.util.Log.w("PlainstridePlanning", "End plan failed category=$category")
                        analytics.record(AnalyticsEvent("feature_exposed", mapOf(AnalyticsProperty.Feature to "plan_end_failed")))
                        messages.emit(TodayMessage.CouldNotEndPlan)
                    },
                )
            } finally {
                mutationInFlight.value = false
            }
        }
    }

    fun selectPlanRecommendation(recommendation: PlanRecommendation?) {
        mutablePlanPicker.value = mutablePlanPicker.value.copy(selected = recommendation)
    }

    fun confirmPlanRecommendation(recommendation: PlanRecommendation, replacing: Boolean) {
        if (mutablePlanPicker.value.replacing) return
        mutablePlanPicker.value = mutablePlanPicker.value.copy(replacing = true, error = false, loadingError = false, constraintError = null)
        viewModelScope.launch {
            val result = repository.activatePlanRecommendation(accountScope.value.first, accountScope.value.second, recommendation)
            kotlinx.coroutines.currentCoroutineContext().ensureActive()
            result.fold(
                onSuccess = {
                    mutablePlanPicker.value = PlanPickerUiState()
                    refresh()
                    analytics.record(AnalyticsEvent("training_plan_recommendation_selected", mapOf(
                        AnalyticsProperty.Result to "success",
                        AnalyticsProperty.SelectionType to if (replacing) "replace" else "new",
                    )))
                },
                onFailure = { error ->
                    val category = (error as? TodayRepositoryException)?.dataError
                    if (category in setOf(TodayDataError.RunningScheduleConflict, TodayDataError.ProgrammeTimelineConflict, TodayDataError.ProgrammeConstraintsConflict)) {
                        android.util.Log.i("Planning", "catalogue_activation_validation category=${category?.javaClass?.simpleName}")
                    } else android.util.Log.e("Planning", "catalogue_activation_failed category=${category?.javaClass?.simpleName ?: error.javaClass.simpleName}")
                    mutablePlanPicker.value = mutablePlanPicker.value.copy(replacing = false, error = true, constraintError = (error as? TodayRepositoryException)?.dataError)
                    analytics.record(AnalyticsEvent("training_plan_recommendation_selected", mapOf(
                        AnalyticsProperty.Result to "failure",
                        AnalyticsProperty.SelectionType to if (replacing) "replace" else "new",
                    )))
                },
            )
        }
    }

    fun closePlanPicker() { mutablePlanPicker.value = PlanPickerUiState() }

    fun refresh() {
        if (refreshing.value) return
        viewModelScope.launch {
            refreshing.value = true
            val (accountId, localeTag) = accountScope.value
            refreshError.value = repository.refresh(accountId, localeTag)
            refreshing.value = false
            if (refreshError.value != null) messages.emit(TodayMessage.CouldNotRefresh)
        }
    }

    fun launchIntent(suggestion: ActivitySuggestion, source: String): WorkoutLaunchIntent = suggestion.toWorkoutLaunchIntent(source)

    private var pendingWorkoutChange: WorkoutAdjustmentApplyRequest? = null

    fun submitConstraint(constraint: TodayConstraint, suggestion: ActivitySuggestion, note: String?, minutes: Int) {
        val envelope = (state.value.suggestion as? CachedResource.Available)?.value ?: return
        if (!mutationInFlight.compareAndSet(false, true)) return
        val scope = accountScope.value
        val candidate = WorkoutAdjustmentApplyRequest(
            idempotencyKey = pendingWorkoutChange?.idempotencyKey ?: UUID.randomUUID().toString(),
            workoutId = suggestion.plannedWorkoutId ?: suggestion.id, suggestionId = suggestion.id,
            validForDate = envelope.validForDate, choice = constraint.wireValue, minutes = minutes,
            note = note?.trim()?.take(160)?.takeIf(String::isNotEmpty),
        )
        val request = if (candidate == pendingWorkoutChange) candidate else candidate.copy(idempotencyKey = UUID.randomUUID().toString())
        pendingWorkoutChange = request
        val analyticsChoice = if (constraint == TodayConstraint.LimitedTime) "short_on_time" else constraint.wireValue
        analytics.record(AnalyticsEvent("today_adjustment_selected", mapOf(AnalyticsProperty.Result to analyticsChoice, AnalyticsProperty.SourceType to "workout_change")))
        analytics.record(AnalyticsEvent("today_adjustment_decided", mapOf(AnalyticsProperty.Result to "accepted", AnalyticsProperty.SourceType to "workout_change")))
        viewModelScope.launch {
            try {
                val result = repository.applyWorkoutAdjustment(scope.first, scope.second, request)
                if (accountScope.value != scope) return@launch
                if (result.isSuccess) {
                    pendingWorkoutChange = null
                    messages.emit(TodayMessage.AdjustmentApplied)
                } else reportWorkoutAdjustmentFailure("apply", result.exceptionOrNull() ?: IllegalStateException())
            } catch (error: Exception) {
                if (error is kotlinx.coroutines.CancellationException) throw error
                if (accountScope.value == scope) reportWorkoutAdjustmentFailure("apply", error)
            } finally {
                mutationInFlight.value = false
            }
        }
    }

    fun decideAdjustment(adjustmentId: String, accept: Boolean) {
        if (mutationInFlight.value) return
        val scope = accountScope.value
        analytics.record(AnalyticsEvent("today_adjustment_decided", mapOf(AnalyticsProperty.Result to if (accept) "accepted" else "kept_original", AnalyticsProperty.SourceType to "workout_change")))
        viewModelScope.launch {
            mutationInFlight.value = true
            try {
                val result = repository.decideAdjustment(scope.first, scope.second, adjustmentId, accept)
                if (accountScope.value != scope) return@launch
                if (result.isSuccess) {
                    messages.emit(if (accept) TodayMessage.AdjustmentApplied else TodayMessage.OriginalKept)
                } else {
                    reportWorkoutAdjustmentFailure("decision", result.exceptionOrNull() ?: IllegalStateException())
                }
            } catch (error: Exception) {
                if (error is kotlinx.coroutines.CancellationException) throw error
                if (accountScope.value == scope) reportWorkoutAdjustmentFailure("decision", error)
            } finally {
                mutationInFlight.value = false
            }
        }
    }

    private suspend fun reportWorkoutAdjustmentFailure(operation: String, error: Throwable, message: TodayMessage = TodayMessage.CouldNotAdjust) {
        if (error is kotlinx.coroutines.CancellationException) throw error
        val category = (error as? TodayRepositoryException)?.dataError?.javaClass?.simpleName ?: error.javaClass.simpleName
        android.util.Log.w("PlainstridePlanning", "Workout adjustment $operation failed category=$category")
        messages.emit(message)
    }

    suspend fun updateRaceGoal(goalId: String, request: com.plainstride.outbound.core.network.RaceGoalUpdateRequest): Boolean {
        if (mutationInFlight.value) return false
        mutationInFlight.value = true
        val (accountId, localeTag) = accountScope.value
        val result = repository.updateRaceGoal(accountId, localeTag, goalId, request)
        mutationInFlight.value = false
        analytics.record(AnalyticsEvent("race_goal_updated", mapOf(AnalyticsProperty.Result to if (result.isSuccess) "success" else "failure", AnalyticsProperty.SelectionType to if (request.shortRunSessions) "short" else "standard")))
        if ((result.exceptionOrNull() as? TodayRepositoryException)?.dataError in setOf(TodayDataError.GoalTimelineUnrealistic, TodayDataError.RunningScheduleConflict, TodayDataError.ProgrammeTimelineConflict, TodayDataError.ProgrammeConstraintsConflict)) {
            android.util.Log.i("Planning", "race_goal_update_validation category=${(result.exceptionOrNull() as? TodayRepositoryException)?.dataError?.javaClass?.simpleName}")
            throw result.exceptionOrNull()!!
        }
        if (result.isFailure) android.util.Log.e("Planning", "race_goal_update_failed category=${(result.exceptionOrNull() as? TodayRepositoryException)?.dataError?.javaClass?.simpleName ?: "unknown"}")
        if (result.isSuccess) refresh()
        return result.isSuccess
    }

    suspend fun updateRunningBenchmark(goalId: String, report: com.plainstride.outbound.core.model.RunningBenchmarkReport?): Boolean {
        if (mutationInFlight.value) return false
        mutationInFlight.value = true
        try {
            val (accountId, localeTag) = accountScope.value
            val result = repository.updateRunningBenchmark(accountId, localeTag, goalId, com.plainstride.outbound.core.network.RunningBenchmarkUpdateRequest(report))
            kotlinx.coroutines.currentCoroutineContext().ensureActive()
            analytics.record(AnalyticsEvent("feature_exposed", mapOf(AnalyticsProperty.Feature to if (report == null) "running_benchmark_removed" else "running_benchmark_saved", AnalyticsProperty.Result to if (result.isSuccess) "success" else "failure")))
            if ((result.exceptionOrNull() as? TodayRepositoryException)?.dataError == TodayDataError.RunningBenchmarkInvalid) {
                android.util.Log.i("Planning", "running_benchmark_validation category=invalid_input")
                throw result.exceptionOrNull()!!
            }
            if (result.isFailure) {
                val failure = result.exceptionOrNull()
                val category = (failure as? TodayRepositoryException)?.dataError?.javaClass?.simpleName ?: failure?.javaClass?.simpleName ?: "unknown"
                android.util.Log.e("Planning", "running_benchmark_update_failed category=$category")
            }
            if (result.isSuccess) refresh()
            return result.isSuccess
        } finally { mutationInFlight.value = false }
    }

    fun trackRunningBenchmarkOpened() = analytics.record(AnalyticsEvent("planning_surface_opened", mapOf(AnalyticsProperty.SourceType to "running_benchmark", AnalyticsProperty.EntrySource to "plan_details")))

    fun trackRaceGoalOpened() = analytics.record(AnalyticsEvent("planning_surface_opened", mapOf(AnalyticsProperty.SourceType to "race_goal_edit", AnalyticsProperty.EntrySource to "plan_details")))

    fun trackWorkoutStarted(source: String) = analytics.record(
        AnalyticsEvent("workout_started", mapOf(AnalyticsProperty.Source to source)),
    )

    fun trackCardDisplayChanged(minimized: Boolean) = analytics.record(
        AnalyticsEvent(
            "today_card_display_changed",
            mapOf(
                AnalyticsProperty.SourceType to "planned_workout",
                AnalyticsProperty.SelectionType to if (minimized) "minimized" else "expanded",
            ),
        ),
    )

    fun trackWorkoutChangeOpened() {
        analytics.record(
        AnalyticsEvent("planning_surface_opened", mapOf(
            AnalyticsProperty.SourceType to "workout_change",
            AnalyticsProperty.EntrySource to "today_planned_card_change",
        )),
        )
    }

    fun trackPlannedWorkoutDetailsOpened() = analytics.record(
        AnalyticsEvent("planning_surface_opened", mapOf(
            AnalyticsProperty.SourceType to "planned_workout_details",
            AnalyticsProperty.EntrySource to "today_planned_card",
        )),
    )

    fun trackWeatherDetailsOpened() = analytics.record(
        AnalyticsEvent("today_weather_details_opened", mapOf(AnalyticsProperty.Source to "today_weather_pill")),
    )

    fun trackWeatherAttributionOpened() = analytics.record(
        AnalyticsEvent("weather_attribution_opened", mapOf(AnalyticsProperty.Source to "today_weather_details")),
    )

    fun trackRacePlannerOpened() = analytics.record(AnalyticsEvent("planning_surface_opened", mapOf(
        AnalyticsProperty.SourceType to "race", AnalyticsProperty.EntrySource to "manual_mode_row",
    )))

    fun trackRacePlanApplied(plan: TodayRacePlan) = analytics.record(AnalyticsEvent("activity_configuration_changed", mapOf(
        AnalyticsProperty.ChangeType to "race_plan",
        AnalyticsProperty.GoalType to "race",
        AnalyticsProperty.SourceType to plan.recommendationSource,
        AnalyticsProperty.PacingStrategy to plan.pacingStrategy,
        AnalyticsProperty.TargetBucket to when {
            plan.distanceMeters < 10_000 -> "5k_10k"
            plan.distanceMeters < 21_097.5 -> "10k_half"
            else -> "half_plus"
        },
    )))

    fun trackLaunchConfiguration(changeType: String, selection: String) = analytics.record(
        AnalyticsEvent(
            "activity_configuration_changed",
            mapOf(AnalyticsProperty.ChangeType to changeType, AnalyticsProperty.SelectionType to selection),
        ),
    )

    fun trackManualWorkoutStarted(activity: TodayActivityChoice, goal: TodayGoalChoice) = analytics.record(
        AnalyticsEvent(
            "workout_started",
            mapOf(AnalyticsProperty.Source to "today_manual", AnalyticsProperty.ActivityType to activity.name.lowercase(), AnalyticsProperty.GoalType to goal.name.lowercase()),
        ),
    )

    suspend fun calorieEstimate(
        activity: TodayActivityChoice,
        target: Int,
    ): PlannedCalorieEstimate? {
        val profile = repository.trainingProfile().getOrNull() ?: return null
        if (activity == TodayActivityChoice.WALK) {
            return WorkoutCalorieEstimator.plannedWalk(target, profile.weightKilograms)
        }
        if (activity != TodayActivityChoice.RUN) return null

        val accountId = accountScope.value.first
        val saved = activities.observePage(accountId, limit = 30).first().activities.map { item ->
            ActivityFacts(
                activityType = item.type,
                startedAt = Instant.parse(item.startedAt),
                durationSeconds = item.durationSecs,
                distanceMeters = item.distanceM,
                averagePaceSecondsPerKilometer = item.averagePaceSecsPerKm,
                elevationGainMeters = item.elevationGainM ?: 0.0,
                energyKilocalories = item.energyKilocalories,
            )
        }
        val calibrationCompleted =
            (state.value.personalization as? CachedResource.Available)
                ?.value
                ?.calibration
                ?.status == CalibrationStatus.completed
        val pace = WorkoutCalorieEstimator
            .resolveLearnedRunPace(saved, calibrationCompleted)
            .secondsPerKilometer
        return WorkoutCalorieEstimator.plannedRunByCalories(
            target,
            profile.weightKilograms,
            pace,
        )
    }

    private data class Meta(
        val refreshing: Boolean,
        val mutating: Boolean,
        val error: TodayDataError?,
        val session: Pair<Boolean, Boolean>,
    )
}
