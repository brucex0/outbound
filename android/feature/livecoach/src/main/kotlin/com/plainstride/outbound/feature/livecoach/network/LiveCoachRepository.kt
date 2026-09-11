package com.plainstride.outbound.feature.livecoach.network

import javax.inject.Inject
import com.plainstride.outbound.core.network.ApiResult
import com.plainstride.outbound.core.network.apiCall
import okhttp3.ResponseBody

interface LiveCoachRepository {
    suspend fun config(token: String): ApiResult<LiveCoachConfig>
    suspend fun catalog(token: String, locale: String): ApiResult<LiveCoachCatalog>
    suspend fun createSession(token: String, request: CreateSessionRequest): ApiResult<CreateSessionResponse>
    suspend fun requestCue(token: String, sessionId: String, request: CueRequest): ApiResult<CueEnvelope>
    suspend fun streamCue(token: String, sessionId: String, request: CueRequest): Result<ResponseBody>
    suspend fun phraseAudio(token: String, sessionId: String, phraseId: String): Result<ByteArray>
    suspend fun recordCachedUse(token: String, sessionId: String, request: CueRequest): ApiResult<Ack>
    suspend fun endSession(token: String, sessionId: String, request: EndSessionRequest): ApiResult<Ack>
}

class DefaultLiveCoachRepository @Inject constructor(private val api: LiveCoachApi) : LiveCoachRepository {
    private fun auth(token: String) = "Bearer $token"
    override suspend fun config(token: String) = apiCall { api.config(auth(token)) }
    override suspend fun catalog(token: String, locale: String) = apiCall { api.catalog(auth(token), locale) }
    override suspend fun createSession(token: String, request: CreateSessionRequest) = apiCall { api.create(auth(token), request) }
    override suspend fun requestCue(token: String, sessionId: String, request: CueRequest) = apiCall { api.cue(auth(token), sessionId, request) }
    override suspend fun streamCue(token: String, sessionId: String, request: CueRequest): Result<ResponseBody> = runCatching {
        val response = api.stream(auth(token), sessionId, request)
        check(response.isSuccessful) { "Live-coach stream failed (${response.code()})" }
        response.body() ?: error("Live-coach stream was empty")
    }
    override suspend fun phraseAudio(token: String, sessionId: String, phraseId: String): Result<ByteArray> = runCatching {
        val response = api.phraseAudio(auth(token), sessionId, phraseId)
        check(response.isSuccessful) { "Live-coach phrase audio failed (${response.code()})" }
        val body = response.body() ?: error("Live-coach phrase audio was empty")
        body.use {
            check(it.contentType()?.toString()?.startsWith("audio/wav") == true)
            check(it.contentLength() in -1..MAX_AUDIO_BYTES.toLong())
            it.bytes().also { bytes -> check(bytes.size in 44..MAX_AUDIO_BYTES) }
        }
    }
    override suspend fun recordCachedUse(token: String, sessionId: String, request: CueRequest) = apiCall { api.recordCached(auth(token), sessionId, request) }
    override suspend fun endSession(token: String, sessionId: String, request: EndSessionRequest) = apiCall { api.end(auth(token), sessionId, request) }

    private companion object { const val MAX_AUDIO_BYTES = 512 * 1024 }
}
