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
import com.plainstride.outbound.core.analytics.AnalyticsEvent
import com.plainstride.outbound.core.analytics.AnalyticsProperty
import com.plainstride.outbound.core.analytics.ProductAnalytics
import com.plainstride.outbound.core.model.ActivitySuggestion
import com.plainstride.outbound.core.model.ActivitySuggestionEnvelope
import com.plainstride.outbound.core.model.AdjustmentProposal
import com.plainstride.outbound.core.model.Modality
import com.plainstride.outbound.core.model.PersonalizationSnapshot
import com.plainstride.outbound.core.model.PlanningState
import com.plainstride.outbound.core.model.StandaloneWorkoutCatalog
import com.plainstride.outbound.core.model.TrainingStimulus
import com.plainstride.outbound.core.network.ReadinessCheckInRequest
import com.plainstride.outbound.core.data.ActivityRepository
import com.plainstride.outbound.core.model.CalibrationStatus
import com.plainstride.outbound.core.model.activity.ActivityFacts
import com.plainstride.outbound.core.model.activity.PlannedCalorieEstimate
import com.plainstride.outbound.core.model.activity.WorkoutCalorieEstimator

data class WorkoutLaunchIntent(
    val suggestionId: String,
    val plannedWorkoutId: String?,
    val title: String,
    val modality: Modality,
    val stimulus: TrainingStimulus,
    val durationSeconds: Int,
    val distanceMeters: Double?,
    val targetCalories: Int?,
    val effortLabel: String,
    val intensityModel: String,
    val steps: List<String>,
    val source: String,
)

enum class TodayConstraint(val wireValue: String) {
    LowEnergy("tired"),
    Soreness("sore"),
    LimitedTime("short_on_time"),
    FeelingGood("good"),
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
    val primarySuggestion: ActivitySuggestion?
        get() = (suggestion as? CachedResource.Available)?.value?.primary
    val pendingAdjustment: AdjustmentProposal?
        get() = (personalization as? CachedResource.Available)?.value?.pendingAdjustment
    val isStale: Boolean
        get() = (suggestion as? CachedResource.Available)?.isStale == true
    val suggestionUpdatedAtEpochMs: Long?
        get() = (suggestion as? CachedResource.Available)?.updatedAtEpochMs
    val hasNoCachedSuggestion: Boolean
        get() = suggestion is CachedResource.Failed || (suggestion is CachedResource.Loading && refreshError != null) ||
            (suggestion is CachedResource.Available && suggestion.value.primary == null)
}

sealed interface TodayMessage {
    data object CouldNotRefresh : TodayMessage
    data object CouldNotAdjust : TodayMessage
    data object AdjustmentApplied : TodayMessage
    data object OriginalKept : TodayMessage
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
    val weatherPermissionRequests = MutableSharedFlow<Unit>(extraBufferCapacity = 1)

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
            TodayWeatherResult.PermissionRequired -> weatherPermissionRequests.emit(Unit)
            TodayWeatherResult.Unavailable -> Unit
        }
    }

    fun updateSessionState(active: Boolean, completedToday: Boolean) {
        sessionState.value = active to completedToday
    }

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

    fun launchIntent(suggestion: ActivitySuggestion, source: String): WorkoutLaunchIntent = WorkoutLaunchIntent(
        suggestionId = suggestion.id,
        plannedWorkoutId = suggestion.plannedWorkoutId,
        title = suggestion.title,
        modality = suggestion.modality,
        stimulus = suggestion.stimulus,
        durationSeconds = suggestion.durationMinutes * 60,
        distanceMeters = suggestion.distanceMeters,
        targetCalories = suggestion.targetCalories,
        effortLabel = suggestion.effortLabel,
        intensityModel = suggestion.intensityModel,
        steps = suggestion.steps.toList(),
        source = source,
    )

    fun submitConstraint(constraint: TodayConstraint, workoutId: String, note: String?) {
        if (mutationInFlight.value) return
        viewModelScope.launch {
            mutationInFlight.value = true
            analytics.record(AnalyticsEvent("today_adjustment_selected", mapOf(AnalyticsProperty.Result to constraint.wireValue)))
            val (accountId, localeTag) = accountScope.value
            val result = repository.submitReadiness(
                accountId,
                localeTag,
                ReadinessCheckInRequest(UUID.randomUUID().toString(), workoutId, Instant.now().toString(), constraint.wireValue, note?.take(160)),
            )
            mutationInFlight.value = false
            if (result.isFailure) messages.emit(TodayMessage.CouldNotAdjust)
        }
    }

    fun decideAdjustment(adjustmentId: String, accept: Boolean) {
        if (mutationInFlight.value) return
        viewModelScope.launch {
            mutationInFlight.value = true
            val (accountId, localeTag) = accountScope.value
            val result = repository.decideAdjustment(accountId, localeTag, adjustmentId, accept)
            mutationInFlight.value = false
            if (result.isSuccess) {
                analytics.record(AnalyticsEvent("today_adjustment_decided", mapOf(AnalyticsProperty.Result to if (accept) "accepted" else "kept_original")))
                messages.emit(if (accept) TodayMessage.AdjustmentApplied else TodayMessage.OriginalKept)
            } else {
                messages.emit(TodayMessage.CouldNotAdjust)
            }
        }
    }

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
