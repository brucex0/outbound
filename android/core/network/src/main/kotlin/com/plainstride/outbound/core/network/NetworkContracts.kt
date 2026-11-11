package com.plainstride.outbound.core.network

import kotlinx.serialization.json.Json

enum class ApiErrorCode {
    RunningScheduleConflict, ProgrammeTimelineConflict, ProgrammeConstraintsConflict, GoalTimelineUnrealistic, RunningBenchmarkInvalid, InvalidRequest, Unauthenticated, Forbidden, NotFound, Conflict, RateLimited,
    ServerUnavailable, NetworkUnavailable, InvalidResponse, Cancelled, Unknown,
}

data class ApiFailure(
    val code: ApiErrorCode,
    val retryable: Boolean,
    val httpStatus: Int? = null,
    val requestId: String? = null,
    val wireCode: String? = null,
)

sealed interface ApiResult<out T> {
    data class Success<T>(val value: T) : ApiResult<T>
    data class Failure(val error: ApiFailure) : ApiResult<Nothing>
}

inline fun <T, R> ApiResult<T>.map(transform: (T) -> R): ApiResult<R> = when (this) {
    is ApiResult.Success -> ApiResult.Success(transform(value))
    is ApiResult.Failure -> this
}

interface AccessTokenProvider {
    suspend fun validAccessToken(): String?
    fun currentContext(): AccountRequestContext? = null
    fun captureAccount(accountId: String): AccountRequestContext? = AccountRequestContext(accountId, 0)
    fun isCurrent(context: AccountRequestContext): Boolean = true
    suspend fun validAccessToken(context: AccountRequestContext): String? {
        if (!isCurrent(context)) return null
        val token = validAccessToken()
        return token.takeIf { isCurrent(context) }
    }
}

interface PlainstrideApi { suspend fun health(): ApiResult<Unit> }

val PlainstrideJson = Json {
    ignoreUnknownKeys = true
    explicitNulls = true
    encodeDefaults = true
}
