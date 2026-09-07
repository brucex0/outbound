package run.plainstride.core.network

import kotlinx.serialization.json.Json

enum class ApiErrorCode {
    InvalidRequest, Unauthenticated, Forbidden, NotFound, Conflict, RateLimited,
    ServerUnavailable, NetworkUnavailable, InvalidResponse, Unknown,
}

data class ApiFailure(
    val code: ApiErrorCode,
    val retryable: Boolean,
    val httpStatus: Int? = null,
    val requestId: String? = null,
)

sealed interface ApiResult<out T> {
    data class Success<T>(val value: T) : ApiResult<T>
    data class Failure(val error: ApiFailure) : ApiResult<Nothing>
}

inline fun <T, R> ApiResult<T>.map(transform: (T) -> R): ApiResult<R> = when (this) {
    is ApiResult.Success -> ApiResult.Success(transform(value))
    is ApiResult.Failure -> this
}

interface AccessTokenProvider { suspend fun validAccessToken(): String? }

interface PlainstrideApi { suspend fun health(): ApiResult<Unit> }

val PlainstrideJson = Json {
    ignoreUnknownKeys = true
    explicitNulls = true
    encodeDefaults = true
}
