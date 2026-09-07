package run.plainstride.feature.assistant

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import run.plainstride.core.analytics.AnalyticsEvent
import run.plainstride.core.analytics.AnalyticsProperty
import run.plainstride.core.analytics.ProductAnalytics
import run.plainstride.core.assistant.*

data class AssistantUiState(val conversation: CompanionConversationState = CompanionConversationState(), val draft: String = "", val speech: SpeechRecognitionState = SpeechRecognitionState.Idle)

@HiltViewModel class AssistantViewModel @Inject constructor(
    private val repository: CompanionRepository,
    private val analytics: ProductAnalytics,
    @param:ApplicationContext context: Context,
) : ViewModel() {
    private val speech = AndroidSpeechRecognizer(context)
    private val draft = MutableStateFlow("")
    val state: StateFlow<AssistantUiState> = combine(repository.state, draft, speech.state, ::AssistantUiState).stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), AssistantUiState())
    private var accountId: String? = null
    fun initialize(accountId: String) { if (this.accountId == accountId) return; this.accountId = accountId; viewModelScope.launch { repository.restore(accountId) } }
    fun draft(value: String) { draft.value = value.take(8_000) }
    fun listen(permission: Boolean) { analytics.record(AnalyticsEvent("assistant_voice_started")); speech.start(permission) }
    fun stopListening() = speech.stop()
    fun send(surface: CompanionSurface = CompanionSurface.Assistant) {
        val account = accountId ?: return; val prompt = draft.value.trim(); if (prompt.isEmpty()) return
        draft.value = ""; analytics.record(AnalyticsEvent("assistant_prompt_sent", mapOf(AnalyticsProperty.Source to surface.name.lowercase())))
        viewModelScope.launch { repository.send(account, CompanionTurnRequest(surface = surface, prompt = prompt, isOffline = false, timeZoneIdentifier = java.util.TimeZone.getDefault().id)) }
    }
    fun decide(actionId: String, accept: Boolean) { val account = accountId ?: return; viewModelScope.launch { repository.decide(account, actionId, accept) } }
    fun reset() { val account = accountId ?: return; viewModelScope.launch { repository.reset(account) } }
    override fun onCleared() { speech.close(); super.onCleared() }
}
