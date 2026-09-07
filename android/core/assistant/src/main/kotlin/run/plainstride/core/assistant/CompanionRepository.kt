package run.plainstride.core.assistant

import java.time.Instant
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
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
import run.plainstride.core.database.AccountCacheDao
import run.plainstride.core.database.AccountCacheEntity
import run.plainstride.core.network.AccessTokenProvider
import run.plainstride.core.network.ApiResult
import run.plainstride.core.network.PlainstrideJson
import run.plainstride.core.network.apiCall

interface CompanionApi {
    @POST("v1/companion/turns") suspend fun turn(@Header("Authorization") authorization: String, @Body body: CompanionTurnRequest): Response<CompanionTurnResponse>
    @POST("v1/companion/actions/{id}/decision") suspend fun decide(@Header("Authorization") authorization: String, @Path("id") actionId: String, @Body body: CompanionDecisionRequest): Response<CompanionDecisionResponse>
}

fun createCompanionApi(baseUrl: String, client: OkHttpClient): CompanionApi = Retrofit.Builder()
    .baseUrl(if (baseUrl.endsWith('/')) baseUrl else "$baseUrl/")
    .client(client).addConverterFactory(PlainstrideJson.asConverterFactory("application/json".toMediaType()))
    .build().create(CompanionApi::class.java)

interface CompanionRepository {
    val state: Flow<CompanionConversationState>
    suspend fun restore(accountId: String, conversationKey: String = "android-assistant")
    suspend fun send(accountId: String, request: CompanionTurnRequest): ApiResult<CompanionTurnResponse>
    suspend fun decide(accountId: String, actionId: String, accept: Boolean): ApiResult<CompanionDecisionResponse>
    suspend fun reset(accountId: String, conversationKey: String = "android-assistant")
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
        mutableState.value = CompanionConversationState(messages = saved?.messages.orEmpty().takeLast(MAX_MESSAGES))
    }

    override suspend fun send(accountId: String, request: CompanionTurnRequest): ApiResult<CompanionTurnResponse> = mutex.withLock {
        val prompt = request.prompt.trim().take(MAX_PROMPT)
        require(prompt.isNotEmpty())
        val user = CompanionMessage("user", prompt, Instant.now().toString())
        val history = (mutableState.value.messages + user).takeLast(MAX_MESSAGES)
        mutableState.value = mutableState.value.copy(messages = history, sending = true, lastFailure = null)
        persist(accountId, request.conversationKey, history)
        val token = tokens.validAccessToken()
        if (token == null) {
            mutableState.value = mutableState.value.copy(sending = false, lastFailure = "authentication_required")
            return@withLock ApiResult.Failure(run.plainstride.core.network.ApiFailure(run.plainstride.core.network.ApiErrorCode.Unauthenticated, false))
        }
        val result = apiCall { api.turn("Bearer $token", request.copy(prompt = prompt, recentMessages = history.dropLast(1).takeLast(12))) }
        if (result is ApiResult.Success) {
            val updated = (history + CompanionMessage("assistant", result.value.message, Instant.now().toString())).takeLast(MAX_MESSAGES)
            mutableState.value = CompanionConversationState(updated, confirmation = result.value.confirmationRequest, suggestedReplies = result.value.suggestedReplies)
            persist(accountId, request.conversationKey, updated)
        } else mutableState.value = mutableState.value.copy(sending = false, lastFailure = (result as ApiResult.Failure).error.code.name)
        result
    }

    override suspend fun decide(accountId: String, actionId: String, accept: Boolean): ApiResult<CompanionDecisionResponse> = mutex.withLock {
        val token = tokens.validAccessToken() ?: return@withLock ApiResult.Failure(run.plainstride.core.network.ApiFailure(run.plainstride.core.network.ApiErrorCode.Unauthenticated, false))
        val result = apiCall { api.decide("Bearer $token", actionId, CompanionDecisionRequest(if (accept) "accept" else "reject")) }
        if (result is ApiResult.Success) mutableState.value = mutableState.value.copy(confirmation = null)
        result
    }

    override suspend fun reset(accountId: String, conversationKey: String) = mutex.withLock {
        cache.upsert(AccountCacheEntity(accountId, NAMESPACE, conversationKey, LOCALE, PlainstrideJson.encodeToString(PersistedConversation()), null, System.currentTimeMillis(), null))
        mutableState.value = CompanionConversationState()
    }

    private suspend fun persist(accountId: String, key: String, messages: List<CompanionMessage>) = cache.upsert(
        AccountCacheEntity(accountId, NAMESPACE, key, LOCALE, PlainstrideJson.encodeToString(PersistedConversation(messages)), null, System.currentTimeMillis(), null),
    )

    private companion object { const val NAMESPACE = "companion"; const val LOCALE = "all"; const val MAX_MESSAGES = 40; const val MAX_PROMPT = 8_000 }
}

@Serializable private data class PersistedConversation(val messages: List<CompanionMessage> = emptyList())
