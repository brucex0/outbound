package com.plainstride.outbound.core.assistant

import java.time.Instant
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import retrofit2.Response
import retrofit2.Retrofit
import retrofit2.converter.kotlinx.serialization.asConverterFactory
import retrofit2.http.Body
import retrofit2.http.Header
import retrofit2.http.POST
import retrofit2.http.Path
import com.plainstride.outbound.core.database.AccountCacheDao
import com.plainstride.outbound.core.database.AccountCacheEntity
import com.plainstride.outbound.core.network.AccessTokenProvider
import com.plainstride.outbound.core.network.ApiResult
import com.plainstride.outbound.core.network.PlainstrideJson
import com.plainstride.outbound.core.network.apiCall

interface CompanionApi {
    @POST("v1/companion/turns") suspend fun turn(@Header("Authorization") authorization: String, @Body body: CompanionTurnRequest): Response<CompanionTurnResponse>
    @POST("v1/companion/actions/{id}/decision") suspend fun decide(@Header("Authorization") authorization: String, @Path("id") actionId: String, @Body body: CompanionDecisionRequest): Response<CompanionDecisionResponse>
}

fun createCompanionApi(baseUrl: String, client: OkHttpClient): CompanionApi = Retrofit.Builder()
    .baseUrl(if (baseUrl.endsWith('/')) baseUrl else "$baseUrl/")
    .client(client).addConverterFactory(PlainstrideJson.asConverterFactory("application/json".toMediaType()))
    .build().create(CompanionApi::class.java)

interface CompanionRepository {
    val state: StateFlow<CompanionConversationState>
    suspend fun restore(accountId: String, conversationKey: String = "android-assistant")
    suspend fun send(accountId: String, request: CompanionTurnRequest, visibleUserText: String = request.prompt): ApiResult<CompanionTurnResponse>
    suspend fun decide(accountId: String, actionId: String, accept: Boolean): ApiResult<CompanionDecisionResponse>
    suspend fun reset(accountId: String, conversationKey: String = "android-assistant")
    suspend fun appendAssistantMessage(accountId: String, text: String, capability: AssistantCapability? = null)
    suspend fun recordLocalTurn(accountId: String, userText: String, assistantText: String, capability: AssistantCapability, navigationTarget: String? = null)
}

class OfflineFirstCompanionRepository(
    private val api: CompanionApi,
    private val tokens: AccessTokenProvider,
    private val cache: AccountCacheDao,
) : CompanionRepository {
    private val mutex = Mutex()
    private val mutableState = MutableStateFlow(CompanionConversationState())
    override val state = mutableState.asStateFlow()

    override suspend fun restore(accountId: String, conversationKey: String) = mutex.withLock {
        val saved = cache.get(accountId, NAMESPACE, conversationKey, LOCALE)?.payloadJson
            ?.let { runCatching { PlainstrideJson.decodeFromString<PersistedConversation>(it) }.getOrNull() }
        mutableState.value = CompanionConversationState(messages = saved?.messages.orEmpty().takeLast(MAX_MESSAGES).map(::visibleMessage))
    }

    override suspend fun send(accountId: String, request: CompanionTurnRequest, visibleUserText: String): ApiResult<CompanionTurnResponse> = mutex.withLock {
        val prompt = request.prompt.trim().take(MAX_PROMPT)
        require(prompt.isNotEmpty())
        val user = CompanionMessage("user", visibleUserText.trim().take(MAX_PROMPT), Instant.now().toString())
        val history = (mutableState.value.messages + user).takeLast(MAX_MESSAGES)
        mutableState.value = mutableState.value.copy(messages = history, sending = true, lastFailure = null)
        persist(accountId, request.conversationKey, history)
        val token = tokens.validAccessToken()
        if (token == null) {
            mutableState.value = mutableState.value.copy(sending = false, lastFailure = "authentication_required")
            return@withLock ApiResult.Failure(com.plainstride.outbound.core.network.ApiFailure(com.plainstride.outbound.core.network.ApiErrorCode.Unauthenticated, false))
        }
        val result = apiCall {
            api.turn(
                "Bearer $token",
                request.copy(prompt = prompt, recentMessages = history.dropLast(1).takeLast(12).map { CompanionMessage(it.role, it.text) }),
            )
        }
        if (result is ApiResult.Success) {
            if (result.value.message.isGenericFailureReply()) {
                mutableState.value = mutableState.value.copy(sending = false, lastFailure = "unusable_response")
                return@withLock ApiResult.Failure(com.plainstride.outbound.core.network.ApiFailure(com.plainstride.outbound.core.network.ApiErrorCode.InvalidResponse, false))
            }
            val updated = (history + CompanionMessage("assistant", result.value.message, Instant.now().toString())).takeLast(MAX_MESSAGES)
            mutableState.value = CompanionConversationState(updated, confirmation = result.value.confirmationRequest, suggestedReplies = result.value.suggestedReplies)
            persist(accountId, request.conversationKey, updated)
        } else mutableState.value = mutableState.value.copy(sending = false, lastFailure = (result as ApiResult.Failure).error.code.name)
        result
    }

    override suspend fun decide(accountId: String, actionId: String, accept: Boolean): ApiResult<CompanionDecisionResponse> = mutex.withLock {
        val token = tokens.validAccessToken() ?: return@withLock ApiResult.Failure(com.plainstride.outbound.core.network.ApiFailure(com.plainstride.outbound.core.network.ApiErrorCode.Unauthenticated, false))
        val result = apiCall { api.decide("Bearer $token", actionId, CompanionDecisionRequest(if (accept) "accept" else "reject")) }
        if (result is ApiResult.Success) mutableState.value = mutableState.value.copy(confirmation = null)
        result
    }

    override suspend fun reset(accountId: String, conversationKey: String) = mutex.withLock {
        cache.upsert(AccountCacheEntity(accountId, NAMESPACE, conversationKey, LOCALE, PlainstrideJson.encodeToString(PersistedConversation()), null, System.currentTimeMillis(), null))
        mutableState.value = CompanionConversationState()
    }

    override suspend fun appendAssistantMessage(accountId: String, text: String, capability: AssistantCapability?) = mutex.withLock {
        val key = "android-assistant"
        val messages = (mutableState.value.messages + CompanionMessage("assistant", text, Instant.now().toString(), capability)).takeLast(MAX_MESSAGES)
        mutableState.value = mutableState.value.copy(messages = messages, sending = false, lastFailure = null)
        persist(accountId, key, messages)
    }

    override suspend fun recordLocalTurn(accountId: String, userText: String, assistantText: String, capability: AssistantCapability, navigationTarget: String?) = mutex.withLock {
        val key = "android-assistant"
        val messages = (mutableState.value.messages + listOf(
            CompanionMessage("user", userText, Instant.now().toString(), capability),
            CompanionMessage("assistant", assistantText, Instant.now().toString(), capability, navigationTarget),
        )).takeLast(MAX_MESSAGES)
        mutableState.value = mutableState.value.copy(messages = messages, sending = false, lastFailure = null)
        persist(accountId, key, messages)
    }

    private suspend fun persist(accountId: String, key: String, messages: List<CompanionMessage>) = cache.upsert(
        AccountCacheEntity(accountId, NAMESPACE, key, LOCALE, PlainstrideJson.encodeToString(PersistedConversation(messages)), null, System.currentTimeMillis(), null),
    )

    private fun String.isGenericFailureReply(): Boolean = trim().lowercase() in setOf(
        "sorry, something went wrong. please try again.",
        "something went wrong. please try again.",
        "sorry, something went wrong.",
    )

    private fun visibleMessage(message: CompanionMessage): CompanionMessage {
        if (message.role != "user") return message
        val catalogMarkers = listOf(
            "\n\nUse this current Plainstride feature catalog as the source of truth.",
            "\n\nUsa este catálogo actual de Plainstride como fuente de verdad.",
            "\n\n请以这份最新的 Plainstride 功能目录为准，",
        )
        val marker = catalogMarkers.firstOrNull { message.text.contains(it) } ?: return message
        val rawRequest = message.text.substringBefore(marker)
        val request = if (rawRequest.startsWith("用户请求：")) {
            rawRequest.substringAfter("用户请求：")
        } else {
            rawRequest.substringAfter(":")
        }.trim()
        return message.copy(text = request)
    }

    private companion object { const val NAMESPACE = "companion"; const val LOCALE = "all"; const val MAX_MESSAGES = 40; const val MAX_PROMPT = 8_000 }
}

@Serializable private data class PersistedConversation(val messages: List<CompanionMessage> = emptyList())
