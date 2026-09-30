package com.plainstride.outbound.feature.onboarding

import androidx.compose.runtime.Immutable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlin.math.roundToInt
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import com.plainstride.outbound.core.analytics.AnalyticsEvent
import com.plainstride.outbound.core.analytics.AnalyticsProperty
import com.plainstride.outbound.core.analytics.ProductAnalytics
import com.plainstride.outbound.core.model.PlanningState
import com.plainstride.outbound.core.network.PlanIntakeContext
import com.plainstride.outbound.core.network.PlanIntakeDraftRequest
import com.plainstride.outbound.core.network.PlanIntakeInterpretRequest

@Immutable
data class OnboardingUiState(
    val loading: Boolean = true,
    val account: OnboardingAccount? = null,
    val draft: OnboardingDraft? = null,
    val source: PlanBuilderSource = PlanBuilderSource.Onboarding,
    val firstUse: Boolean = false,
    val saving: Boolean = false,
    val healthImporting: Boolean = false,
    val healthConnected: Boolean = false,
    val recentHealthActivityCount: Int = 0,
    val plan: PlanningState? = null,
    val intakeContext: PlanIntakeContext? = null,
    val interpretingGoal: Boolean = false,
    val interpretationReply: String? = null,
    val interpretationFailed: Boolean = false,
)

sealed interface OnboardingEffect {
    data object Completed : OnboardingEffect
    data object FailedOpen : OnboardingEffect
    data object IdentityUnavailable : OnboardingEffect
    data object HealthUnavailable : OnboardingEffect
    data object ProfileUnavailable : OnboardingEffect
    data object PlanCreationUnavailable : OnboardingEffect
    data object SkipUnavailable : OnboardingEffect
}

@HiltViewModel
class OnboardingViewModel @Inject constructor(
    private val repository: OnboardingRepository,
    private val drafts: OnboardingDraftStore,
    private val analytics: ProductAnalytics,
) : ViewModel() {
    private val mutableState = MutableStateFlow(OnboardingUiState())
    val state: StateFlow<OnboardingUiState> = mutableState
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), OnboardingUiState())
    private val mutableEffects = MutableSharedFlow<OnboardingEffect>(extraBufferCapacity = 1)
    val effects = mutableEffects.asSharedFlow()
    fun start(source: PlanBuilderSource, usesMetric: Boolean, forceRestart: Boolean = false) {
        viewModelScope.launch { restore(source, usesMetric, forceRestart) }
    }

    fun update(transform: (OnboardingDraft) -> OnboardingDraft) {
        val draft = mutableState.value.draft ?: return
        val updated = transform(draft).normalized()
        mutableState.value = mutableState.value.copy(draft = updated)
        viewModelScope.launch { drafts.save(updated) }
    }

    fun next() {
        val draft = mutableState.value.draft ?: return
        when (draft.step) {
            OnboardingStep.Identity -> saveIdentity(draft)
            OnboardingStep.Welcome -> moveTo(OnboardingStep.Objective)
            OnboardingStep.Objective -> moveTo(OnboardingStep.Activities)
            OnboardingStep.Activities -> {
                val setup = mutableState.value.intakeContext?.suggestedSetup
                if (setup?.confidence == "high" && draft.observedBaselineConfirmed == true) {
                    moveTo(if (mutableState.value.hasPlanningBodyProfile()) OnboardingStep.Review else OnboardingStep.Profile)
                } else moveTo(OnboardingStep.Baseline)
            }
            OnboardingStep.Baseline -> moveTo(OnboardingStep.Week)
            OnboardingStep.Week -> moveTo(if (mutableState.value.hasPlanningBodyProfile()) OnboardingStep.Review else OnboardingStep.Profile)
            OnboardingStep.Profile -> saveTrainingProfileAndContinue()
            OnboardingStep.Review -> createPlan()
            OnboardingStep.Result -> {
                mutableEffects.tryEmit(OnboardingEffect.Completed)
            }
            OnboardingStep.Creating -> Unit
        }
    }

    fun back() {
        val previous = when (mutableState.value.draft?.step) {
            OnboardingStep.Objective -> if (mutableState.value.firstUse) OnboardingStep.Welcome else return
            OnboardingStep.Activities -> OnboardingStep.Objective
            OnboardingStep.Baseline -> OnboardingStep.Activities
            OnboardingStep.Week -> OnboardingStep.Baseline
            OnboardingStep.Profile -> if (mutableState.value.usesSuggestedSetup()) OnboardingStep.Activities else OnboardingStep.Week
            OnboardingStep.Review -> when {
                !mutableState.value.hasPlanningBodyProfile() -> OnboardingStep.Profile
                mutableState.value.usesSuggestedSetup() -> OnboardingStep.Activities
                else -> OnboardingStep.Week
            }
            else -> return
        }
        moveTo(previous)
    }

    fun exploreFirst() = resolveSkip()

    fun chooseObjective(objective: PlanObjective) {
        update { draft ->
            val activities = if (objective == PlanObjective.EventPreparation && PlanActivity.Run !in draft.activities) listOf(PlanActivity.Run) + draft.activities else draft.activities
            draft.copy(
                objective = objective,
                objectiveConfirmed = true,
                goalInputText = null,
                eventDistanceConfirmed = false,
                eventDateConfirmed = false,
                eventIntentConfirmed = false,
                targetTimeConfirmed = false,
                reviewHorizonConfirmed = false,
                activities = activities,
            )
        }
        mutableState.value = mutableState.value.copy(interpretationReply = null, interpretationFailed = false)
        analytics.record(AnalyticsEvent("plan_intake_goal_interpreted", mapOf(AnalyticsProperty.Result to "success", AnalyticsProperty.SourceType to "quick_reply")))
    }

    fun reviseObjective() {
        update { it.copy(
            objectiveConfirmed = false,
            goalInputText = null,
            eventDistanceConfirmed = false,
            eventDateConfirmed = false,
            eventIntentConfirmed = false,
            targetTimeConfirmed = false,
            reviewHorizonConfirmed = false,
            successSignal = "",
        ) }
        mutableState.value = mutableState.value.copy(interpretationReply = null, interpretationFailed = false)
        analytics.record(AnalyticsEvent("plan_intake_answer_edited", mapOf(AnalyticsProperty.SelectionType to "goal", AnalyticsProperty.SourceType to "conversation")))
    }

    fun acceptSuggestedSetup() {
        update { it.copy(observedBaselineConfirmed = true) }
        analytics.record(AnalyticsEvent("plan_intake_baseline_confirmed", mapOf(AnalyticsProperty.Result to "accepted", AnalyticsProperty.SourceType to "recent_activity_setup")))
        next()
    }

    fun adjustSuggestedSetup() {
        update { it.copy(observedBaselineConfirmed = false) }
        analytics.record(AnalyticsEvent("plan_intake_baseline_confirmed", mapOf(AnalyticsProperty.Result to "corrected", AnalyticsProperty.SourceType to "recent_activity_setup")))
    }

    fun trackAnswerEdited(field: String) {
        if (field !in setOf("goal", "event_distance", "event_date", "event_intent", "target_time", "review_horizon", "activities", "baseline", "schedule")) return
        analytics.record(AnalyticsEvent("plan_intake_answer_edited", mapOf(AnalyticsProperty.SelectionType to field, AnalyticsProperty.SourceType to "conversation")))
    }

    fun confirmObservedBaseline(accepted: Boolean) {
        update { it.copy(observedBaselineConfirmed = accepted) }
        analytics.record(AnalyticsEvent("plan_intake_baseline_confirmed", mapOf(
            AnalyticsProperty.Result to if (accepted) "accepted" else "corrected",
            AnalyticsProperty.SourceType to "recent_activities",
        )))
    }

    fun interpretGoal(message: String) {
        val state = mutableState.value
        val draft = state.draft ?: return
        val context = state.intakeContext ?: return
        if (message.isBlank() || state.interpretingGoal) return
        viewModelScope.launch {
            mutableState.value = mutableState.value.copy(interpretingGoal = true, interpretationReply = null, interpretationFailed = false)
            val request = PlanIntakeInterpretRequest(
                message.trim(),
                context.contextVersion,
                PlanIntakeDraftRequest(
                    objective = draft.objective.apiValue.takeIf { draft.objectiveConfirmed },
                    activities = emptyList(),
                    eventDate = draft.eventDate.takeIf { draft.eventDateConfirmed },
                    eventDistanceMeters = draft.eventDistanceMeters.takeIf { draft.eventDistanceConfirmed },
                    eventIntent = draft.eventIntent.takeIf { draft.eventIntentConfirmed },
                    targetTimeSeconds = draft.targetTimeSeconds.takeIf { draft.targetTimeConfirmed },
                    reviewHorizonWeeks = draft.reviewHorizonWeeks.takeIf { draft.reviewHorizonConfirmed },
                    sessionsPerWeek = draft.sessionsPerWeek,
                    maxSessionMinutes = draft.availableMinutes,
                ),
            )
            repository.interpretPlanIntake(request).fold(
                onSuccess = { result ->
                    val objective = result.objective?.toPlanObjective()
                    if (objective == null) {
                        mutableState.value = mutableState.value.copy(interpretingGoal = false, interpretationReply = result.assistantReply)
                        analytics.record(AnalyticsEvent("plan_intake_goal_interpreted", mapOf(
                            AnalyticsProperty.Result to "failure",
                            AnalyticsProperty.SourceType to "conversation_text",
                            AnalyticsProperty.ErrorCategory to "unsupported_goal",
                        )))
                        return@fold
                    }
                    val recognized = result.recognizedFields.toSet()
                    val current = mutableState.value.draft ?: draft
                    val updated = current.copy(
                        objective = objective,
                        objectiveConfirmed = true,
                        goalInputText = message.trim(),
                        eventDistanceConfirmed = "eventDistanceMeters" in recognized && result.eventDistanceMeters != null,
                        eventDateConfirmed = "eventDate" in recognized && result.eventDate != null,
                        eventIntentConfirmed = ("eventIntent" in recognized && result.eventIntent != null) || ("targetTimeSeconds" in recognized && result.targetTimeSeconds != null),
                        targetTimeConfirmed = "targetTimeSeconds" in recognized && result.targetTimeSeconds != null,
                        reviewHorizonConfirmed = "reviewHorizonWeeks" in recognized && result.reviewHorizonWeeks != null,
                        eventDate = if ("eventDate" in recognized) result.eventDate ?: current.eventDate else current.eventDate,
                        eventDistanceMeters = if ("eventDistanceMeters" in recognized) result.eventDistanceMeters ?: current.eventDistanceMeters else current.eventDistanceMeters,
                        eventIntent = if ("eventIntent" in recognized) result.eventIntent ?: current.eventIntent else if ("targetTimeSeconds" in recognized && result.targetTimeSeconds != null) "targetTime" else current.eventIntent,
                        targetTimeSeconds = if ("targetTimeSeconds" in recognized) result.targetTimeSeconds ?: current.targetTimeSeconds else current.targetTimeSeconds,
                        reviewHorizonWeeks = if ("reviewHorizonWeeks" in recognized) result.reviewHorizonWeeks ?: current.reviewHorizonWeeks else current.reviewHorizonWeeks,
                        goalDescription = result.goalDescription ?: message.trim(),
                    ).normalized()
                    drafts.save(updated)
                    mutableState.value = mutableState.value.copy(draft = updated, interpretingGoal = false, interpretationReply = result.assistantReply)
                    analytics.record(AnalyticsEvent("plan_intake_goal_interpreted", mapOf(AnalyticsProperty.Result to "success", AnalyticsProperty.SourceType to "conversation_text")))
                },
                onFailure = {
                    mutableState.value = mutableState.value.copy(interpretingGoal = false, interpretationFailed = true)
                    analytics.record(AnalyticsEvent("plan_intake_goal_interpreted", mapOf(AnalyticsProperty.Result to "failure", AnalyticsProperty.SourceType to "conversation_text", AnalyticsProperty.ErrorCategory to "unavailable")))
                },
            )
        }
    }

    fun finishLater() {
        val state = mutableState.value
        val draft = state.draft ?: return
        analytics.record(AnalyticsEvent("plan_builder_exited", mapOf(AnalyticsProperty.Source to draft.step.analyticsName())))
        if (state.firstUse) resolveSkip() else mutableEffects.tryEmit(OnboardingEffect.Completed)
    }

    fun skipTrainingProfile() {
        analytics.record(AnalyticsEvent(
            "onboarding_training_profile_completed",
            mapOf(
                AnalyticsProperty.Result to "skipped",
                AnalyticsProperty.SourceType to if (mutableState.value.healthConnected) "health" else "manual",
            ),
        ))
        moveTo(OnboardingStep.Review)
    }

    fun importHealth() {
        if (mutableState.value.healthImporting) return
        viewModelScope.launch {
            mutableState.value = mutableState.value.copy(healthImporting = true)
            analytics.record(AnalyticsEvent("health_connection_requested", mapOf(AnalyticsProperty.Source to "onboarding")))
            repository.importHealthProfile().fold(
                onSuccess = { imported ->
                    val old = mutableState.value.draft ?: return@fold
                    val profile = imported.trainingProfile
                    val metric = old.measurementSystem == MeasurementSystem.Metric
                    val updated = old.copy(
                        birthDate = profile.birthDate.orEmpty(),
                        height = profile.heightCentimeters?.let { if (metric) it else it / 2.54 }?.displayValue().orEmpty(),
                        weight = profile.weightKilograms?.let { if (metric) it else it / 0.45359237 }?.displayValue().orEmpty(),
                        sexAtBirth = profile.sexAtBirth ?: SexAtBirth.NotProvided,
                        recentSessionsPerWeek = imported.recentSessionsPerWeek?.coerceIn(0, 6) ?: old.recentSessionsPerWeek,
                        comfortableMinutes = imported.comfortableMinutes?.coerceIn(10, 120) ?: old.comfortableMinutes,
                    )
                    drafts.save(updated)
                    mutableState.value = mutableState.value.copy(
                        draft = updated,
                        healthImporting = false,
                        healthConnected = true,
                        recentHealthActivityCount = imported.recentActivityCount,
                    )
                    analytics.record(AnalyticsEvent("health_connection_completed", mapOf(AnalyticsProperty.Result to "connected")))
                },
                onFailure = {
                    mutableState.value = mutableState.value.copy(healthImporting = false)
                    analytics.record(AnalyticsEvent("health_connection_completed", mapOf(AnalyticsProperty.Result to "failed")))
                    mutableEffects.emit(OnboardingEffect.HealthUnavailable)
                },
            )
        }
    }

    /** Debug-only caller control. Production never exposes the entry point. */
    fun restartForDebug(usesMetric: Boolean) = start(PlanBuilderSource.Settings, usesMetric, forceRestart = true)

    private suspend fun restore(source: PlanBuilderSource, usesMetric: Boolean, forceRestart: Boolean) {
        mutableState.value = OnboardingUiState(loading = true, source = source)
        val account = runCatching { repository.currentAccount() }.getOrElse {
            analytics.record(AnalyticsEvent("onboarding_resolution_failed", mapOf(AnalyticsProperty.Result to "fail_open")))
            mutableState.value = OnboardingUiState(loading = false, source = source)
            mutableEffects.emit(OnboardingEffect.FailedOpen)
            return
        }
        val firstUse = source == PlanBuilderSource.Onboarding && account.onboardingStatus == OnboardingStatus.pending
        if (source == PlanBuilderSource.Onboarding && !firstUse && !forceRestart) {
            mutableState.value = OnboardingUiState(loading = false, account = account, source = source)
            mutableEffects.emit(OnboardingEffect.Completed)
            return
        }

        val targetSystem = if (usesMetric) MeasurementSystem.Metric else MeasurementSystem.Imperial
        val restored = if (forceRestart) null else drafts.load(account.id)
        var initial = (restored ?: newDraft(account, firstUse, targetSystem)).withMeasurementSystem(targetSystem)
        if (initial.step == OnboardingStep.Creating || initial.step == OnboardingStep.Result) {
            initial = initial.copy(step = OnboardingStep.Review)
        }
        if (!firstUse && initial.step == OnboardingStep.Welcome) initial = initial.copy(step = OnboardingStep.Objective)
        if (firstUse && account.needsIdentity) initial = initial.copy(step = OnboardingStep.Identity)

        val context = repository.planIntakeContext().getOrNull()
        initial = if (context != null) initial.withIntakeContext(context)
            else initial.copy(intakeContextVersion = null)
        drafts.save(initial)
        mutableState.value = OnboardingUiState(
            loading = false,
            account = account,
            draft = initial,
            source = source,
            firstUse = firstUse,
            intakeContext = context,
        )
        analytics.record(AnalyticsEvent("plan_builder_opened", mapOf(AnalyticsProperty.EntrySource to source.analyticsValue)))
        analytics.record(AnalyticsEvent("onboarding_step_viewed", mapOf(AnalyticsProperty.Source to initial.step.analyticsName())))
        context?.let { analytics.record(AnalyticsEvent("plan_intake_context_loaded", mapOf(AnalyticsProperty.SourceType to it.dataTier))) }
    }

    private fun newDraft(account: OnboardingAccount, firstUse: Boolean, measurementSystem: MeasurementSystem) = OnboardingDraft(
        accountId = account.id,
        step = when {
            firstUse && account.needsIdentity -> OnboardingStep.Identity
            firstUse -> OnboardingStep.Welcome
            else -> OnboardingStep.Objective
        },
        displayName = account.displayName.orEmpty().takeUnless { it.equals("runner", ignoreCase = true) }.orEmpty(),
        username = account.username.orEmpty().takeUnless { it.equals("runner", ignoreCase = true) }.orEmpty(),
        email = account.verifiedEmail.orEmpty(),
        measurementSystem = measurementSystem,
    )

    private fun saveIdentity(draft: OnboardingDraft) = viewModelScope.launch {
        if (!draft.identityValid(mutableState.value.account?.verifiedEmail.isNullOrBlank())) return@launch
        mutableState.value = mutableState.value.copy(saving = true)
        repository.updateIdentity(
            draft.displayName.trim(),
            draft.username.trim().lowercase(),
            draft.email.trim().lowercase().takeIf { mutableState.value.account?.verifiedEmail.isNullOrBlank() },
        ).fold(
            onSuccess = { account ->
                mutableState.value = mutableState.value.copy(account = account, saving = false)
                analytics.record(AnalyticsEvent("onboarding_identity_completed"))
                moveTo(if (mutableState.value.firstUse) OnboardingStep.Welcome else OnboardingStep.Objective)
            },
            onFailure = {
                mutableState.value = mutableState.value.copy(saving = false)
                mutableEffects.emit(OnboardingEffect.IdentityUnavailable)
            },
        )
    }

    private fun saveTrainingProfileAndContinue() = viewModelScope.launch {
        val draft = mutableState.value.draft ?: return@launch
        if (!draft.measurementsValid() || !draft.requiredBodyProfileComplete()) return@launch
        val metric = draft.measurementSystem == MeasurementSystem.Metric
        val training = TrainingProfileInput(
            birthDate = draft.birthDate.ifBlank { null },
            heightCentimeters = draft.height.parseMeasurement()?.let { if (metric) it else it * 2.54 },
            weightKilograms = draft.weight.parseMeasurement()?.let { if (metric) it else it * 0.45359237 },
            sexAtBirth = draft.sexAtBirth.takeUnless { it == SexAtBirth.NotProvided },
            objective = draft.objective,
        )
        mutableState.value = mutableState.value.copy(saving = true)
        repository.updateTrainingProfile(training).fold(
            onSuccess = {
                val refreshedContext = repository.planIntakeContext(draft.objective).getOrNull()
                // Updating the profile changes the server's intake version. If its refresh is
                // unavailable, omit the old version instead of submitting a guaranteed stale one.
                val refreshedDraft = refreshedContext?.let { draft.withIntakeContext(it) }
                    ?: draft.copy(intakeContextVersion = null)
                drafts.save(refreshedDraft)
                mutableState.value = mutableState.value.copy(saving = false, draft = refreshedDraft, intakeContext = refreshedContext ?: mutableState.value.intakeContext)
                analytics.record(AnalyticsEvent(
                    "onboarding_training_profile_completed",
                    mapOf(
                        AnalyticsProperty.Result to "saved",
                        AnalyticsProperty.SourceType to if (mutableState.value.healthConnected) "health" else "manual",
                    ),
                ))
                moveTo(OnboardingStep.Review)
            },
            onFailure = {
                mutableState.value = mutableState.value.copy(saving = false)
                mutableEffects.emit(OnboardingEffect.ProfileUnavailable)
            },
        )
    }

    private fun createPlan() = viewModelScope.launch {
        val draft = mutableState.value.draft ?: return@launch
        val startedAt = System.nanoTime()
        mutableState.value = mutableState.value.copy(saving = true, draft = draft.copy(step = OnboardingStep.Creating))
        repository.createPlan(draft.planInput()).fold(
            onSuccess = { plan ->
                drafts.clear(draft.accountId)
                mutableState.value = mutableState.value.copy(
                    saving = false,
                    draft = draft.copy(step = OnboardingStep.Result),
                    plan = plan,
                )
                trackCreation(draft, "success", startedAt)
                if (mutableState.value.firstUse) {
                    analytics.record(AnalyticsEvent("onboarding_resolved", mapOf(AnalyticsProperty.Result to "completed")))
                }
            },
            onFailure = {
                val reviewDraft = draft.copy(step = OnboardingStep.Review)
                drafts.save(reviewDraft)
                mutableState.value = mutableState.value.copy(saving = false, draft = reviewDraft)
                trackCreation(draft, "failure", startedAt, it)
                mutableEffects.emit(OnboardingEffect.PlanCreationUnavailable)
            },
        )
    }

    private fun resolveSkip() {
        if (mutableState.value.saving) return
        viewModelScope.launch {
            mutableState.value = mutableState.value.copy(saving = true)
            repository.skipOnboarding().fold(
                onSuccess = {
                    mutableState.value = mutableState.value.copy(saving = false)
                    analytics.record(AnalyticsEvent("onboarding_resolved", mapOf(AnalyticsProperty.Result to "skipped")))
                    mutableEffects.emit(OnboardingEffect.Completed)
                },
                onFailure = {
                    mutableState.value = mutableState.value.copy(saving = false)
                    mutableEffects.emit(OnboardingEffect.SkipUnavailable)
                },
            )
        }
    }

    private fun moveTo(step: OnboardingStep) {
        update { it.copy(step = step) }
        analytics.record(AnalyticsEvent("onboarding_step_viewed", mapOf(AnalyticsProperty.Source to step.analyticsName())))
        if (step == OnboardingStep.Profile) analytics.record(AnalyticsEvent("onboarding_training_profile_viewed"))
    }

    private fun trackCreation(draft: OnboardingDraft, result: String, startedAt: Long, error: Throwable? = null) {
        val seconds = (System.nanoTime() - startedAt) / 1_000_000_000.0
        val latency = when {
            seconds < 2 -> "under_2s"
            seconds < 5 -> "2s_5s"
            seconds < 10 -> "5s_10s"
            else -> "10s_plus"
        }
        val properties = mutableMapOf(
            AnalyticsProperty.Result to result,
            AnalyticsProperty.LatencyBucket to latency,
            AnalyticsProperty.GoalType to draft.objective.analyticsValue,
            AnalyticsProperty.CountBucket to "activities_${draft.activities.size}",
        )
        if (error != null) properties[AnalyticsProperty.ErrorCategory] = when (error) {
            is OnboardingDataException.Api -> when (error.failure.httpStatus) {
                400 -> "http_400"
                409 -> "http_409"
                in 400..499 -> "http_4xx"
                in 500..599 -> "http_5xx"
                else -> "http_other"
            }
            else -> "unknown"
        }
        analytics.record(AnalyticsEvent("plan_creation_completed", properties))
    }

    private fun OnboardingDraft.planInput() = PlanBuilderInput(
        objective, activities, eventDistanceMeters,
        eventDate ?: defaultEventDate(), eventIntent, targetTimeSeconds, reviewHorizonWeeks,
        successSignal, goalDescription, intakeContextVersion, baselineContext, recentSessionsPerWeek,
        comfortableMinutes, sessionsPerWeek, availableMinutes, preferredDays, constraints,
    )

    private fun OnboardingDraft.identityValid(needsEmail: Boolean): Boolean = displayName.isNotBlank() &&
        username.trim().matches(Regex("[A-Za-z0-9_-]{3,30}")) &&
        (!needsEmail || email.matches(Regex("[^@\\s]+@[^@\\s]+\\.[^@\\s]+")))

    private fun OnboardingDraft.normalized() = copy(
        activities = activities.distinct().ifEmpty { listOf(PlanActivity.Run) },
        recentSessionsPerWeek = recentSessionsPerWeek.coerceIn(0, 6),
        comfortableMinutes = comfortableMinutes.coerceIn(10, 120),
        sessionsPerWeek = sessionsPerWeek.coerceIn(1, 6),
        availableMinutes = availableMinutes.coerceIn(10, 120),
        preferredDays = preferredDays.distinct().take(sessionsPerWeek.coerceIn(1, 6)),
    )

    private fun OnboardingDraft.withMeasurementSystem(target: MeasurementSystem): OnboardingDraft {
        if (measurementSystem == target) return normalized()
        val heightValue = height.parseMeasurement()
        val weightValue = weight.parseMeasurement()
        val toMetric = target == MeasurementSystem.Metric
        return copy(
            height = heightValue?.let { if (toMetric) it * 2.54 else it / 2.54 }?.displayValue().orEmpty(),
            weight = weightValue?.let { if (toMetric) it * 0.45359237 else it / 0.45359237 }?.displayValue().orEmpty(),
            measurementSystem = target,
        ).normalized()
    }

    private fun OnboardingDraft.measurementsValid(): Boolean {
        val heightValue = height.parseMeasurement()
        val weightValue = weight.parseMeasurement()
        val metric = measurementSystem == MeasurementSystem.Metric
        return (height.isBlank() || heightValue != null && heightValue in if (metric) 90.0..250.0 else 35.0..98.5) &&
            (weight.isBlank() || weightValue != null && weightValue in if (metric) 25.0..350.0 else 55.0..772.0)
    }

    private fun TrainingProfileInput.hasValues() = birthDate != null || heightCentimeters != null || weightKilograms != null || sexAtBirth != null
    private fun Double.displayValue() = if (this % 1.0 == 0.0) roundToInt().toString() else "%.1f".format(this)
    private fun String.parseMeasurement() = trim().replace(',', '.').toDoubleOrNull()
    private fun OnboardingStep.analyticsName() = when (this) {
        OnboardingStep.Profile -> "private_details"
        else -> name.lowercase()
    }
    private val PlanObjective.analyticsValue: String get() = when (this) {
        PlanObjective.EventPreparation -> "event_preparation"
        PlanObjective.HealthEnergy -> "health_energy"
        PlanObjective.WeightLoss -> "weight_loss"
        else -> name.lowercase()
    }
}

// Local or Health Connect values still need to be saved before the server can build a plan.
private fun OnboardingUiState.hasPlanningBodyProfile() = intakeContext?.bodyProfile?.completeForPlanning == true
private fun OnboardingUiState.usesSuggestedSetup() =
    intakeContext?.suggestedSetup?.confidence == "high" && draft?.observedBaselineConfirmed == true

private fun OnboardingDraft.withIntakeContext(context: PlanIntakeContext): OnboardingDraft {
    val metric = measurementSystem == MeasurementSystem.Metric
    val body = context.bodyProfile
    val baseline = context.observedBaseline
    val inferredActivities = baseline?.activityMix.orEmpty().mapNotNull(String::toPlanActivity).takeIf { observedBaselineConfirmed != false }.orEmpty()
    val suggested = context.suggestedSetup?.takeIf { it.confidence == "high" && observedBaselineConfirmed != false }
    val suggestedActivities = suggested?.activities.orEmpty().mapNotNull(String::toPlanActivity)
    return copy(
        intakeContextVersion = context.contextVersion,
        birthDate = body.birthDate ?: birthDate,
        height = body.heightCentimeters?.let { if (metric) it else it / 2.54 }?.formatInputValue() ?: height,
        weight = body.weightKilograms?.let { if (metric) it else it / 0.45359237 }?.formatInputValue() ?: weight,
        sexAtBirth = body.sexAtBirth?.let { runCatching { SexAtBirth.valueOf(it.replaceFirstChar(Char::uppercase)) }.getOrNull() } ?: sexAtBirth,
        recentSessionsPerWeek = if (observedBaselineConfirmed != false && baseline?.confidence == "high") baseline.sessionsPerWeek.coerceIn(0, 6) else recentSessionsPerWeek,
        comfortableMinutes = if (observedBaselineConfirmed != false && baseline?.confidence == "high") baseline.comfortableMinutes?.coerceIn(10, 120) ?: comfortableMinutes else comfortableMinutes,
        activities = suggestedActivities.ifEmpty { inferredActivities.ifEmpty { activities } },
        baselineContext = suggested?.baselineContext?.toPlanBaselineContext() ?: baselineContext,
        sessionsPerWeek = suggested?.sessionsPerWeek?.coerceIn(1, 6) ?: context.previousSchedule?.sessionsPerWeek ?: sessionsPerWeek,
        availableMinutes = suggested?.maxSessionMinutes?.coerceIn(10, 120) ?: context.previousSchedule?.maxSessionMinutes ?: availableMinutes,
        preferredDays = suggested?.preferredDays ?: context.previousSchedule?.preferredDays ?: preferredDays,
    )
}

private fun String.toPlanBaselineContext() = when (this) {
    "startingOut" -> PlanBaselineContext.StartingOut
    "returningAfterBreak" -> PlanBaselineContext.ReturningAfterBreak
    else -> PlanBaselineContext.CurrentlyActive
}

private val PlanObjective.apiValue: String get() = when (this) {
    PlanObjective.EventPreparation -> "eventPreparation"
    PlanObjective.Endurance -> "endurance"
    PlanObjective.Speed -> "speed"
    PlanObjective.WeightLoss -> "weightLoss"
    PlanObjective.HealthEnergy -> "healthEnergy"
}

private fun String.toPlanObjective() = PlanObjective.entries.firstOrNull { it.apiValue == this }
private fun String.toPlanActivity() = when (this) { "run" -> PlanActivity.Run; "walk" -> PlanActivity.Walk; "bike" -> PlanActivity.Bike; else -> null }
private fun Double.formatInputValue() = if (this % 1.0 == 0.0) roundToInt().toString() else "%.1f".format(this)
