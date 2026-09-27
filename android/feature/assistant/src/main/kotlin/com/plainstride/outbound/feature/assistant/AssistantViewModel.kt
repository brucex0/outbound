package com.plainstride.outbound.feature.assistant

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.plainstride.outbound.core.analytics.AnalyticsEvent
import com.plainstride.outbound.core.analytics.AnalyticsProperty
import com.plainstride.outbound.core.analytics.ProductAnalytics
import com.plainstride.outbound.core.assistant.*
import com.plainstride.outbound.core.network.ApiResult
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import java.util.TimeZone
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

data class AssistantUiState(
    val conversation: CompanionConversationState = CompanionConversationState(),
    val draft: String = "",
    val speech: SpeechRecognitionState = SpeechRecognitionState.Idle,
    val activityCommand: PreparedActivityCommand? = null,
)

@HiltViewModel
class AssistantViewModel @Inject constructor(
    private val repository: CompanionRepository,
    private val analytics: ProductAnalytics,
    @param:ApplicationContext private val context: Context,
) : ViewModel() {
    private val speech = AndroidSpeechRecognizer(context)
    private val draft = MutableStateFlow("")
    private val activityCommand = MutableStateFlow<PreparedActivityCommand?>(null)
    val state: StateFlow<AssistantUiState> = combine(repository.state, draft, speech.state, activityCommand, ::AssistantUiState)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), AssistantUiState())
    private var accountId: String? = null

    val suggestions = listOf(
        AssistantSuggestion("discover", AssistantCapability.Discover, context.getString(R.string.assistant_suggestion_discover), context.getString(R.string.assistant_prompt_discover)),
        AssistantSuggestion("support", AssistantCapability.Support, context.getString(R.string.assistant_suggestion_support), context.getString(R.string.assistant_prompt_support)),
        AssistantSuggestion("brainstorm", AssistantCapability.Brainstorm, context.getString(R.string.assistant_suggestion_brainstorm), context.getString(R.string.assistant_prompt_brainstorm)),
        AssistantSuggestion("plan", AssistantCapability.Plan, context.getString(R.string.assistant_suggestion_plan), context.getString(R.string.assistant_prompt_plan)),
        AssistantSuggestion("log-workout", AssistantCapability.Plan, context.getString(R.string.assistant_suggestion_log_workout), context.getString(R.string.assistant_prompt_log_workout)),
        AssistantSuggestion("live-status", AssistantCapability.Plan, context.getString(R.string.assistant_live_status), context.getString(R.string.assistant_prompt_live_status)),
        AssistantSuggestion("live-focus", AssistantCapability.Discover, context.getString(R.string.assistant_live_focus), context.getString(R.string.assistant_prompt_live_focus)),
    )

    fun initialize(accountId: String) {
        if (this.accountId == accountId) return
        this.accountId = accountId
        viewModelScope.launch {
            repository.restore(accountId)
            if (repository.state.value.messages.isEmpty()) {
                repository.appendAssistantMessage(accountId, context.getString(R.string.assistant_intro), AssistantCapability.Discover)
            }
        }
    }

    fun draft(value: String) { draft.value = value.take(8_000) }
    fun listen(permission: Boolean) {
        analytics.record(AnalyticsEvent("assistant_voice_started"))
        speech.start(permission)
    }
    fun stopListening() = speech.stop()
    fun consumeActivityCommand() { activityCommand.value = null }
    fun handleSpeechResult(transcript: String, screen: String) {
        draft.value = transcript
        send(screen)
    }
    fun handleStableSpeechCommand(transcript: String, screen: String) {
        if (ActivityVoiceCommandParser.parse(transcript) == null) return
        speech.cancel()
        handleSpeechResult(transcript, screen)
    }
    fun selectSuggestion(suggestion: AssistantSuggestion, screen: String) {
        trackEngagement(screen, "suggestion")
        submit(suggestion.prompt, suggestion.capability, screen)
    }

    fun send(screen: String) {
        val prompt = draft.value.trim()
        if (prompt.isEmpty()) return
        draft.value = ""
        trackEngagement(screen, "message")
        submit(prompt, null, screen)
    }

    private fun submit(prompt: String, requestedCapability: AssistantCapability?, screen: String) {
        val account = accountId ?: return
        val capability = requestedCapability ?: inferCapability(prompt)
        val destination = AssistantDestinationRegistry.infer(prompt)
        if (prompt.containsAny("log a workout", "workout i already completed", "log workout")) {
            viewModelScope.launch {
                repository.recordLocalTurn(account, prompt, context.getString(R.string.assistant_log_workout_reply), AssistantCapability.Plan, "me")
            }
            return
        }
        val command = ActivityVoiceCommandParser.parse(prompt)
        if (command != null) {
            val prepared = when (command) {
                is ActivityVoiceCommand.Distance -> PreparedActivityCommand(command.sport, distanceMeters = command.meters)
                is ActivityVoiceCommand.Duration -> PreparedActivityCommand(command.sport, durationSeconds = command.seconds)
                is ActivityVoiceCommand.Freestyle -> PreparedActivityCommand(command.sport)
            }
            viewModelScope.launch {
                val label = context.getString(R.string.assistant_activity_prepared)
                repository.recordLocalTurn(account, prompt, label, AssistantCapability.Plan)
                activityCommand.value = prepared
            }
            return
        }
        if (destination != null) {
            val title = context.getString(AssistantDestinationRegistry.titleResource(destination))
            viewModelScope.launch { repository.recordLocalTurn(account, prompt, context.getString(R.string.assistant_opening, title), capability, destination.routeId) }
            return
        }

        val task = when {
            screen == "recording" -> CompanionTask.LiveGuidance
            screen == "today" -> CompanionTask.AdaptToday
            prompt.containsAny("today", "tired", "sore", "short on time") -> CompanionTask.AdaptToday
            capability == AssistantCapability.Plan -> CompanionTask.PrepareWeek
            capability == AssistantCapability.Discover || capability == AssistantCapability.Navigate || capability == AssistantCapability.Support -> CompanionTask.ProductHelp
            else -> CompanionTask.AnswerTrainingQuestion
        }
        val surface = when (screen) {
            "recording" -> CompanionSurface.LiveSession
            "today" -> CompanionSurface.Today
            else -> CompanionSurface.Assistant
        }
        viewModelScope.launch {
            val result = repository.send(account, CompanionTurnRequest(
                task = task,
                surface = surface,
                prompt = groundedPrompt(prompt, capability),
                recentMessages = state.value.conversation.messages.takeLast(12),
                clientCapabilities = listOf("action-confirmation", "memory-controls", "context-receipt"),
                timeZoneIdentifier = TimeZone.getDefault().id,
            ))
            if (result is ApiResult.Failure) {
                repository.appendAssistantMessage(account, fallback(capability, screen), capability)
            }
        }
    }

    fun decide(actionId: String, accept: Boolean, onActionApplied: () -> Unit = {}) {
        val account = accountId ?: return
        viewModelScope.launch {
            when (val result = repository.decide(account, actionId, accept)) {
                is ApiResult.Success -> {
                    val executed = accept && result.value.action.status == "executed"
                    if (executed) onActionApplied()
                    val summary = result.value.action.afterState?.summary
                    val reply = if (executed && !summary.isNullOrBlank()) context.getString(R.string.assistant_action_done_summary, summary)
                    else context.getString(if (accept) R.string.assistant_action_done else R.string.assistant_action_kept)
                    repository.appendAssistantMessage(account, reply, AssistantCapability.Plan)
                }
                is ApiResult.Failure -> repository.appendAssistantMessage(account, context.getString(R.string.assistant_action_failed), AssistantCapability.Plan)
            }
        }
    }

    fun reset() {
        val account = accountId ?: return
        viewModelScope.launch {
            repository.reset(account)
            repository.appendAssistantMessage(account, context.getString(R.string.assistant_intro), AssistantCapability.Discover)
        }
    }

    private fun trackEngagement(screen: String, source: String) = analytics.record(AnalyticsEvent(
        "assistant_meaningful_engagement",
        mapOf(AnalyticsProperty.Destination to screen, AnalyticsProperty.EntrySource to source),
    ))

    private fun fallback(capability: AssistantCapability, screen: String): String {
        if (capability == AssistantCapability.Navigate) return context.getString(R.string.assistant_fallback_navigate)
        if (screen == "recording") return context.getString(R.string.assistant_fallback_live)
        if (screen == "today") return context.getString(R.string.assistant_fallback_today)
        return context.getString(when (capability) {
            AssistantCapability.Discover -> R.string.assistant_fallback_discover
            AssistantCapability.Support -> R.string.assistant_fallback_support
            AssistantCapability.Brainstorm -> R.string.assistant_fallback_brainstorm
            AssistantCapability.Plan -> R.string.assistant_fallback_plan
            AssistantCapability.Navigate -> R.string.assistant_fallback_navigate
        })
    }

    private fun groundedPrompt(prompt: String, capability: AssistantCapability): String {
        if (capability != AssistantCapability.Discover && capability != AssistantCapability.Navigate && capability != AssistantCapability.Support) return prompt
        return context.getString(R.string.assistant_product_context, prompt, AssistantDestinationRegistry.productContext(context))
    }

    private fun inferCapability(prompt: String): AssistantCapability = when {
        prompt.containsAny("where", "find", "go to", "navigate", "open", "show me") -> AssistantCapability.Navigate
        prompt.containsAny("help", "issue", "stuck", "support", "setup") -> AssistantCapability.Support
        prompt.containsAny("idea", "brainstorm", "could", "should we") -> AssistantCapability.Brainstorm
        prompt.containsAny("plan", "week", "schedule", "goal") -> AssistantCapability.Plan
        else -> AssistantCapability.Discover
    }

    override fun onCleared() { speech.close(); super.onCleared() }
}

private fun String.containsAny(vararg values: String) = values.any { contains(it, ignoreCase = true) }
