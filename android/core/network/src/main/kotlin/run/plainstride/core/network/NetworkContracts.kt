package run.plainstride.core.network

import kotlinx.serialization.json.Json

enum class ApiErrorCode {
    InvalidRequest, Unauthenticated, Forbidden, NotFound, Conflict, RateLimited,
    ServerUnavailable, NetworkUnavailable, InvalidResponse, Unknown,
}

data class ApiFailure(val code: ApiErrorCode, val retryable: Boolean)

interface AccessTokenProvider { suspend fun validAccessToken(): String? }

interface PlainstrideApi { suspend fun health(): Result<Unit> }

val PlainstrideJson = Json {
    ignoreUnknownKeys = true
    explicitNulls = true
    encodeDefaults = true
}
