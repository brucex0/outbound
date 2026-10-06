package com.plainstride.outbound.feature.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import com.plainstride.outbound.core.analytics.AnalyticsEvent
import com.plainstride.outbound.core.analytics.AnalyticsProperty
import com.plainstride.outbound.core.analytics.ProductAnalytics
import com.plainstride.outbound.core.auth.SessionCoordinator
import com.plainstride.outbound.core.auth.SessionState
import com.plainstride.outbound.core.designsystem.PlainstrideThemeId
import com.plainstride.outbound.core.network.AccountDto

data class SettingsUiState(
    val preferences: SettingsPreferences = SettingsPreferences(MeasurementSystem.Metric, TemperatureUnit.Celsius, AppearanceMode.System, PlainstrideThemeId.VictoryGold),
    val account: AccountDto? = null,
    val summary: MeSummary? = null,
    val loading: Boolean = true,
    val saving: Boolean = false,
)

enum class SettingsMessage { Refreshed, Saved, SaveFailed, RefreshFailed }

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val repository: SettingsRepository,
    private val analytics: ProductAnalytics,
    private val sessions: SessionCoordinator,
) : ViewModel() {
    private val account = MutableStateFlow<AccountDto?>(null)
    private val summary = MutableStateFlow<MeSummary?>(null)
    private val loading = MutableStateFlow(true)
    private val saving = MutableStateFlow(false)
    private var activeAccountId: String? = null
    val messages = MutableSharedFlow<SettingsMessage>(extraBufferCapacity = 2)

    val state = combine(repository.preferences, account, summary, loading, saving, ::SettingsUiState)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), SettingsUiState())

    init {
        viewModelScope.launch {
            sessions.state.collect { session ->
                val accountId = when (session) {
                    is SessionState.SignedIn -> session.accountId
                    is SessionState.Refreshing -> session.accountId
                    SessionState.Loading -> return@collect
                    SessionState.SignedOut -> null
                }
                if (accountId == activeAccountId) return@collect

                activeAccountId = accountId
                account.value = null
                summary.value = null
                if (accountId == null) {
                    loading.value = false
                } else {
                    refresh(accountId, showSuccess = false)
                }
            }
        }
    }

    fun refresh(showSuccess: Boolean = true) {
        activeAccountId?.let { refresh(it, showSuccess) }
    }

    private fun refresh(expectedAccountId: String, showSuccess: Boolean) {
        viewModelScope.launch {
            loading.value = true
            val result = repository.refresh()
            // A request started for the previous session must never repopulate Me
            // after the user has signed out or switched accounts.
            if (activeAccountId != expectedAccountId || sessions.state.value.accountId() != expectedAccountId) {
                return@launch
            }
            result.fold(
                onSuccess = {
                    if (it.first.id != expectedAccountId) return@fold
                    account.value = it.first
                    summary.value = it.second
                    if (showSuccess) messages.emit(SettingsMessage.Refreshed)
                },
                onFailure = { messages.emit(SettingsMessage.RefreshFailed) },
            )
            loading.value = false
        }
    }

    fun updateProfile(displayName: String, username: String?, contactEmail: String?) = save("profile", null) {
        repository.updateProfile(displayName, username, contactEmail).onSuccess { account.value = it }.map { Unit }
    }

    fun setMeasurement(value: MeasurementSystem) = save("measurement_unit_system", value.wireValue) { repository.setMeasurement(value) }
    fun setTemperature(value: TemperatureUnit) = save("temperature_unit", value.wireValue) { repository.setTemperature(value) }
    fun setAppearance(value: AppearanceMode) = save("appearance_mode", value.wireValue) { repository.setAppearance(value) }
    fun setTheme(value: PlainstrideThemeId) = save("theme", value.serializedName) { repository.setTheme(value) }

    fun setSaveActivityPhotosToAlbum(value: Boolean, showMessage: Boolean = true) {
        if (saving.value) return
        viewModelScope.launch {
            saving.value = true
            val result = repository.setSaveActivityPhotosToAlbum(value)
            analytics.record(AnalyticsEvent(
                "preference_changed",
                mapOf(
                    AnalyticsProperty.ChangeType to "save_activity_photos_to_album",
                    AnalyticsProperty.SelectionType to if (value) "enabled" else "disabled",
                ),
            ))
            if (showMessage) messages.emit(if (result.isSuccess) SettingsMessage.Saved else SettingsMessage.SaveFailed)
            saving.value = false
        }
    }

    fun trackLegal(document: String) = analytics.record(
        AnalyticsEvent("legal_document_opened", mapOf(AnalyticsProperty.Source to "settings", AnalyticsProperty.Result to document))
    )

    fun trackOnboardingReplay() = analytics.record(
        AnalyticsEvent("onboarding_replay_requested", mapOf(AnalyticsProperty.Source to "settings"))
    )

    fun trackMeDestination(destination: String) = analytics.record(
        AnalyticsEvent("me_destination_opened", mapOf(AnalyticsProperty.Destination to destination, AnalyticsProperty.EntrySource to "me"))
    )

    private fun save(type: String, selection: String?, block: suspend () -> Result<Unit>) {
        if (saving.value) return
        viewModelScope.launch {
            saving.value = true
            val result = block()
            analytics.record(AnalyticsEvent(
                "preference_changed",
                buildMap {
                    put(AnalyticsProperty.Source, type)
                    selection?.let { put(AnalyticsProperty.Result, it) }
                    put(AnalyticsProperty.Enabled, result.isSuccess)
                },
            ))
            messages.emit(if (result.isSuccess) SettingsMessage.Saved else SettingsMessage.SaveFailed)
            saving.value = false
        }
    }

    private fun SessionState.accountId(): String? = when (this) {
        is SessionState.SignedIn -> accountId
        is SessionState.Refreshing -> accountId
        SessionState.Loading, SessionState.SignedOut -> null
    }
}
