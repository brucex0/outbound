package run.plainstride.feature.onboarding

import androidx.compose.runtime.Immutable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import run.plainstride.core.analytics.AnalyticsEvent
import run.plainstride.core.analytics.AnalyticsProperty
import run.plainstride.core.analytics.ProductAnalytics

@Immutable
data class OnboardingUiState(
    val loading: Boolean = true,
    val account: OnboardingAccount? = null,
    val draft: OnboardingDraft? = null,
    val saving: Boolean = false,
    val healthImporting: Boolean = false,
)

sealed interface OnboardingEffect {
    data object Completed : OnboardingEffect
    data object SavedOffline : OnboardingEffect
    data object IdentityUnavailable : OnboardingEffect
    data object HealthUnavailable : OnboardingEffect
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

    init { viewModelScope.launch { restore() } }

    fun update(transform: (OnboardingDraft) -> OnboardingDraft) {
        val draft = mutableState.value.draft ?: return
        val updated = transform(draft)
        mutableState.value = mutableState.value.copy(draft = updated)
        viewModelScope.launch { drafts.save(updated) }
    }

    fun next() {
        val draft = mutableState.value.draft ?: return
        if (draft.step == OnboardingStep.Identity) {
            saveIdentity(draft)
            return
        }
        val next = when (draft.step) {
            OnboardingStep.Goal -> OnboardingStep.Baseline
            OnboardingStep.Baseline -> OnboardingStep.Week
            OnboardingStep.Week -> OnboardingStep.Profile
            OnboardingStep.Profile -> OnboardingStep.Ready
            OnboardingStep.Ready -> return complete()
            OnboardingStep.Identity -> return
        }
        moveTo(next)
    }

    fun back() {
        val step = when (mutableState.value.draft?.step) {
            OnboardingStep.Baseline -> OnboardingStep.Goal
            OnboardingStep.Week -> OnboardingStep.Baseline
            OnboardingStep.Profile -> OnboardingStep.Week
            OnboardingStep.Ready -> OnboardingStep.Profile
            else -> return
        }
        moveTo(step)
    }

    fun skipTrainingProfile() { moveTo(OnboardingStep.Ready) }

    fun importHealth() {
        if (mutableState.value.healthImporting) return
        viewModelScope.launch {
            mutableState.value = mutableState.value.copy(healthImporting = true)
            analytics.record(AnalyticsEvent("health_connection_requested", mapOf(AnalyticsProperty.Source to "onboarding")))
            repository.importHealthProfile().fold(
                onSuccess = { imported ->
                    val old = mutableState.value.draft ?: return@fold
                    val profile = imported.trainingProfile
                    val updated = old.copy(
                        birthDate = profile.birthDate.orEmpty(),
                        heightCentimeters = profile.heightCentimeters?.displayValue().orEmpty(),
                        weightKilograms = profile.weightKilograms?.displayValue().orEmpty(),
                        sexAtBirth = profile.sexAtBirth ?: SexAtBirth.NotProvided,
                        frequency = imported.recentSessionsPerWeek?.toFrequency() ?: old.frequency,
                        comfortableMinutes = imported.comfortableMinutes?.coerceIn(10, 90) ?: old.comfortableMinutes,
                    )
                    drafts.save(updated)
                    mutableState.value = mutableState.value.copy(draft = updated, healthImporting = false)
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

    private suspend fun restore() {
        val account = repository.currentAccount()
        if (account.onboardingCompleted) {
            mutableState.value = OnboardingUiState(loading = false, account = account)
            mutableEffects.emit(OnboardingEffect.Completed)
            return
        }
        val restored = drafts.load(account.id)
        val initial = restored ?: OnboardingDraft(
            accountId = account.id,
            step = if (account.needsIdentity) OnboardingStep.Identity else OnboardingStep.Goal,
            displayName = account.displayName.orEmpty(),
            username = account.username.orEmpty().takeUnless { it == "runner" }.orEmpty(),
            email = account.verifiedEmail.orEmpty(),
        )
        mutableState.value = OnboardingUiState(loading = false, account = account, draft = initial)
        drafts.save(initial)
        analytics.record(AnalyticsEvent("onboarding_step_viewed", mapOf(AnalyticsProperty.Source to initial.step.analyticsName())))
    }

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
                moveTo(OnboardingStep.Goal)
            },
            onFailure = {
                mutableState.value = mutableState.value.copy(saving = false)
                mutableEffects.emit(OnboardingEffect.IdentityUnavailable)
            },
        )
    }

    private fun complete() {
        viewModelScope.launch {
            val draft = mutableState.value.draft ?: return@launch
            mutableState.value = mutableState.value.copy(saving = true)
            val training = TrainingProfileInput(
                draft.birthDate.ifBlank { null }, draft.heightCentimeters.toDoubleOrNull(),
                draft.weightKilograms.toDoubleOrNull(), draft.sexAtBirth.takeUnless { it == SexAtBirth.NotProvided },
            )
            if (training.hasValues()) repository.updateTrainingProfile(training)
            val result = repository.completeOnboarding(
                RunnerProfileInput(draft.goal, draft.frequency.sessionsPerWeek, draft.comfortableMinutes,
                    draft.runsPerWeek, draft.availableMinutes),
            )
            result.fold(
                onSuccess = {
                    drafts.clear(draft.accountId)
                    analytics.record(AnalyticsEvent("onboarding_completed", mapOf(AnalyticsProperty.Result to "success")))
                    mutableEffects.emit(OnboardingEffect.Completed)
                },
                onFailure = {
                    mutableState.value = mutableState.value.copy(saving = false)
                    mutableEffects.emit(OnboardingEffect.SavedOffline)
                },
            )
        }
    }

    private fun moveTo(step: OnboardingStep) {
        update { it.copy(step = step) }
        analytics.record(AnalyticsEvent("onboarding_step_viewed", mapOf(AnalyticsProperty.Source to step.analyticsName())))
    }

    private fun OnboardingDraft.identityValid(needsEmail: Boolean): Boolean = displayName.isNotBlank() &&
        username.trim().matches(Regex("[A-Za-z0-9_-]{3,30}")) &&
        (!needsEmail || email.matches(Regex("[^@\\s]+@[^@\\s]+\\.[^@\\s]+")))
    private fun TrainingProfileInput.hasValues() = birthDate != null || heightCentimeters != null || weightKilograms != null || sexAtBirth != null
    private fun Double.displayValue() = if (this % 1.0 == 0.0) toInt().toString() else "%.1f".format(this)
    private fun Int.toFrequency() = when { this <= 0 -> RunningFrequency.None; this == 1 -> RunningFrequency.Occasional; this == 2 -> RunningFrequency.OneOrTwo; else -> RunningFrequency.ThreePlus }
    private fun OnboardingStep.analyticsName() = name.lowercase()
}
