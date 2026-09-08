package com.plainstride.outbound.core.assistant

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable enum class CompanionTask {
    @SerialName("answer_training_question") AnswerTrainingQuestion,
    @SerialName("adapt_today") AdaptToday,
    @SerialName("prepare_week") PrepareWeek,
    @SerialName("post_run_reflection") PostRunReflection,
    @SerialName("live_guidance") LiveGuidance,
    @SerialName("inspect_memory") InspectMemory,
    @SerialName("product_help") ProductHelp,
}

@Serializable enum class CompanionSurface {
    @SerialName("assistant") Assistant,
    @SerialName("today") Today,
    @SerialName("post_run") PostRun,
    @SerialName("weekly_review") WeeklyReview,
    @SerialName("live_session") LiveSession,
    @SerialName("memory") Memory,
}

@Serializable data class CompanionMessage(val role: String, val text: String, val createdAt: String? = null)
@Serializable data class CompanionTurnRequest(
    val task: CompanionTask = CompanionTask.AnswerTrainingQuestion,
    val surface: CompanionSurface = CompanionSurface.Assistant,
    val prompt: String,
    val conversationKey: String = "android-assistant",
    val recentMessages: List<CompanionMessage> = emptyList(),
    val currentEntityIds: List<String> = emptyList(),
    val clientCapabilities: List<String> = listOf("typed-action", "confirmation"),
    val isOffline: Boolean = false,
    val timeZoneIdentifier: String? = null,
    val signals: List<CompanionSignal> = emptyList(),
)
@Serializable data class CompanionSignal(val idempotencyKey: String, val type: String, val value: kotlinx.serialization.json.JsonElement, val source: String, val confidence: Double = 1.0, val privacy: String = "standard", val consequenceLevel: String = "low", val possibleEffects: List<String> = emptyList(), val scope: Map<String, String> = emptyMap(), val observedAt: String, val freshUntil: String)
@Serializable data class CompanionAction(val id: String, val actionType: String, val permissionTier: Int, val requiresConfirmation: Boolean, val status: String, val explanation: String)
@Serializable data class CompanionConfirmation(val actionId: String, val title: String, val explanation: String, val acceptLabel: String, val rejectLabel: String)
@Serializable data class CompanionContextReceipt(val manifestId: String, val task: CompanionTask, val tokenBudget: Int, val estimatedTokens: Int, val includedReferenceCount: Int)
@Serializable data class CompanionTurnResponse(val message: String, val locale: String? = null, val action: CompanionAction? = null, val confirmationRequest: CompanionConfirmation? = null, val suggestedReplies: List<String> = emptyList(), val runnerModelVersion: String, val contextReceipt: CompanionContextReceipt)
@Serializable data class CompanionDecisionRequest(val decision: String)
@Serializable data class CompanionDecidedAction(val id: String, val status: String, val explanation: String)
@Serializable data class CompanionDecisionResponse(val action: CompanionDecidedAction)

data class CompanionConversationState(
    val messages: List<CompanionMessage> = emptyList(),
    val sending: Boolean = false,
    val confirmation: CompanionConfirmation? = null,
    val suggestedReplies: List<String> = emptyList(),
    val lastFailure: String? = null,
)
