package run.plainstride.feature.livecoach.network

import java.io.InputStream
import javax.inject.Inject
import run.plainstride.core.network.ApiResult
import run.plainstride.core.network.apiCall

interface LiveCoachRepository {
    suspend fun config(token: String): ApiResult<LiveCoachConfig>
    suspend fun catalog(token: String, locale: String): ApiResult<LiveCoachCatalog>
    suspend fun createSession(token: String, request: CreateSessionRequest): ApiResult<CreateSessionResponse>
    suspend fun requestCue(token: String, sessionId: String, request: CueRequest): ApiResult<CueEnvelope>
    suspend fun streamCue(token: String, sessionId: String, request: CueRequest): Result<InputStream>
    suspend fun recordCachedUse(token: String, sessionId: String, request: CueRequest): ApiResult<Ack>
    suspend fun endSession(token: String, sessionId: String, request: EndSessionRequest): ApiResult<Ack>
}

class DefaultLiveCoachRepository @Inject constructor(private val api: LiveCoachApi) : LiveCoachRepository {
    private fun auth(token: String) = "Bearer $token"
    override suspend fun config(token: String) = apiCall { api.config(auth(token)) }
    override suspend fun catalog(token: String, locale: String) = apiCall { api.catalog(auth(token), locale) }
    override suspend fun createSession(token: String, request: CreateSessionRequest) = apiCall { api.create(auth(token), request) }
    override suspend fun requestCue(token: String, sessionId: String, request: CueRequest) = apiCall { api.cue(auth(token), sessionId, request) }
    override suspend fun streamCue(token: String, sessionId: String, request: CueRequest): Result<InputStream> = runCatching {
        val response = api.stream(auth(token), sessionId, request)
        check(response.isSuccessful) { "Live-coach stream failed (${response.code()})" }
        response.body()?.byteStream() ?: error("Live-coach stream was empty")
    }
    override suspend fun recordCachedUse(token: String, sessionId: String, request: CueRequest) = apiCall { api.recordCached(auth(token), sessionId, request) }
    override suspend fun endSession(token: String, sessionId: String, request: EndSessionRequest) = apiCall { api.end(auth(token), sessionId, request) }
}
