package run.plainstride.feature.today

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
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import run.plainstride.core.analytics.AnalyticsEvent
import run.plainstride.core.analytics.AnalyticsProperty
import run.plainstride.core.analytics.ProductAnalytics
import run.plainstride.core.model.ActivitySuggestion
import run.plainstride.core.model.ActivitySuggestionEnvelope
import run.plainstride.core.model.AdjustmentProposal
import run.plainstride.core.model.Modality
import run.plainstride.core.model.PersonalizationSnapshot
import run.plainstride.core.model.PlanningState
import run.plainstride.core.model.StandaloneWorkoutCatalog
import run.plainstride.core.model.TrainingStimulus
import run.plainstride.core.network.ReadinessCheckInRequest

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
) : ViewModel() {
    // A single encrypted session is active at a time; account bootstrap can later provide the
    // opaque server account ID without exposing identity details to this feature.
    private val accountScopeKey = "authenticated_account"
    private val localeTag = Locale.getDefault().toLanguageTag()
    private val refreshing = MutableStateFlow(false)
    private val mutationInFlight = MutableStateFlow(false)
    private val refreshError = MutableStateFlow<TodayDataError?>(null)
    private val sessionState = MutableStateFlow(false to false)
    val messages = MutableSharedFlow<TodayMessage>(extraBufferCapacity = 1)
    private val mutableWeather = MutableStateFlow<WeatherGuidance?>(null)
    val weather = mutableWeather
    val weatherPermissionRequests = MutableSharedFlow<Unit>(extraBufferCapacity = 1)

    val state = combine(
        repository.observePlanning(accountScopeKey, localeTag),
        repository.observeSuggestion(accountScopeKey, localeTag),
        repository.observePersonalization(accountScopeKey, localeTag),
        repository.observeStandaloneWorkouts(accountScopeKey, localeTag),
        combine(refreshing, mutationInFlight, refreshError, sessionState) { a, b, c, d -> Meta(a, b, c, d) },
    ) { planning, suggestion, personalization, catalog, meta ->
        TodayUiState(planning, suggestion, personalization, catalog, meta.refreshing, meta.mutating, meta.error, meta.session.first, meta.session.second)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), TodayUiState())

    init {
        refresh()
        refreshWeather()
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
            refreshError.value = repository.refresh(accountScopeKey, localeTag)
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
            val result = repository.submitReadiness(
                accountScopeKey,
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
            val result = repository.decideAdjustment(accountScopeKey, localeTag, adjustmentId, accept)
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

    private data class Meta(
        val refreshing: Boolean,
        val mutating: Boolean,
        val error: TodayDataError?,
        val session: Pair<Boolean, Boolean>,
    )
}
