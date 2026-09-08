package com.plainstride.outbound.core.network

import java.io.IOException
import kotlinx.serialization.Serializable
import retrofit2.Response

@Serializable private data class ErrorEnvelope(val code: String? = null)

suspend fun <T : Any> apiCall(block: suspend () -> Response<T>): ApiResult<T> = try {
    val response = block()
    val body = response.body()
    if (response.isSuccessful && body != null) ApiResult.Success(body)
    else ApiResult.Failure(response.toFailure())
} catch (_: IOException) {
    ApiResult.Failure(ApiFailure(ApiErrorCode.NetworkUnavailable, retryable = true))
} catch (_: Exception) {
    ApiResult.Failure(ApiFailure(ApiErrorCode.InvalidResponse, retryable = false))
}

private fun Response<*>.toFailure(): ApiFailure {
    val wireCode = runCatching {
        errorBody()?.string()?.let { PlainstrideJson.decodeFromString<ErrorEnvelope>(it).code }
    }.getOrNull()
    val code = when (wireCode) {
        "authentication_required", "invalid_refresh_token", "invalid_provider_credential" -> ApiErrorCode.Unauthenticated
        "provider_identity_in_use" -> ApiErrorCode.Conflict
        "terms_version_outdated" -> ApiErrorCode.InvalidRequest
        "provider_unavailable", "authentication_unavailable" -> ApiErrorCode.ServerUnavailable
        else -> when (this.code()) {
            400, 422 -> ApiErrorCode.InvalidRequest
            401 -> ApiErrorCode.Unauthenticated
            403 -> ApiErrorCode.Forbidden
            404 -> ApiErrorCode.NotFound
            409 -> ApiErrorCode.Conflict
            429 -> ApiErrorCode.RateLimited
            in 500..599 -> ApiErrorCode.ServerUnavailable
            else -> ApiErrorCode.Unknown
        }
    }
    return ApiFailure(
        code = code,
        retryable = code == ApiErrorCode.NetworkUnavailable || code == ApiErrorCode.ServerUnavailable || code == ApiErrorCode.RateLimited,
        httpStatus = this.code(),
        requestId = headers()["x-request-id"],
    )
}
