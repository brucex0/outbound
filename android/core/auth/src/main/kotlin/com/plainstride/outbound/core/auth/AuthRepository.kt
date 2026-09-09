package com.plainstride.outbound.core.auth

import android.util.Log
import java.time.Instant
import com.plainstride.outbound.core.network.ApiErrorCode
import com.plainstride.outbound.core.network.ApiFailure
import com.plainstride.outbound.core.network.ApiResult
import com.plainstride.outbound.core.network.AuthApiService
import com.plainstride.outbound.core.network.GoogleCredentialRequest
import com.plainstride.outbound.core.network.GoogleDeletionRequest
import com.plainstride.outbound.core.network.GoogleSignInRequest
import com.plainstride.outbound.core.network.GoogleLinkRedemptionRequest
import com.plainstride.outbound.core.network.LogoutRequest
import com.plainstride.outbound.core.network.RefreshRequest
import com.plainstride.outbound.core.network.SessionResponseDto
import com.plainstride.outbound.core.network.apiCall
import com.plainstride.outbound.core.network.map

interface AuthRepository {
    suspend fun signIn(identityToken: String, termsVersion: Int, deviceLabel: String?): ApiResult<Unit>
    suspend fun linkGoogle(identityToken: String): ApiResult<Unit>
    suspend fun redeemGoogleLink(identityToken: String, code: String, termsVersion: Int, deviceLabel: String?): ApiResult<Unit>
    suspend fun deleteAccount(identityToken: String): ApiResult<Unit>
}

class DefaultAuthRepository(
    private val api: AuthApiService,
    private val sessions: SessionCoordinator,
) : AuthRepository {
    override suspend fun signIn(identityToken: String, termsVersion: Int, deviceLabel: String?): ApiResult<Unit> =
        apiCall { api.signIn(GoogleSignInRequest(identityToken, deviceLabel = deviceLabel, termsVersion = termsVersion)) }
            .installSession()

    override suspend fun linkGoogle(identityToken: String): ApiResult<Unit> = authenticated { token ->
        apiCall { api.linkGoogle("Bearer $token", GoogleCredentialRequest(identityToken)) }.map { Unit }
    }

    override suspend fun redeemGoogleLink(identityToken: String, code: String, termsVersion: Int, deviceLabel: String?): ApiResult<Unit> =
        apiCall { api.redeemGoogleLink(GoogleLinkRedemptionRequest(identityToken, code, deviceLabel = deviceLabel, termsVersion = termsVersion)) }
            .installSession()

    override suspend fun deleteAccount(identityToken: String): ApiResult<Unit> = authenticated { token ->
        when (val result = apiCall { api.deleteAccount("Bearer $token", GoogleDeletionRequest(identityToken = identityToken)) }) {
            is ApiResult.Success -> {
                sessions.signOut()
                ApiResult.Success(Unit)
            }
            is ApiResult.Failure -> result
        }
    }

    private suspend fun <T> authenticated(block: suspend (String) -> ApiResult<T>): ApiResult<T> {
        val token = sessions.validAccessToken()
            ?: return ApiResult.Failure(ApiFailure(ApiErrorCode.Unauthenticated, retryable = false))
        return block(token)
    }

    private suspend fun ApiResult<SessionResponseDto>.installSession(): ApiResult<Unit> = when (this) {
        is ApiResult.Success -> {
            Log.i(AUTH_REPOSITORY_TAG, "Auth response decoded; installing session")
            sessions.install(value.credentials())
            Log.i(AUTH_REPOSITORY_TAG, "Session installed")
            ApiResult.Success(Unit)
        }
        is ApiResult.Failure -> {
            Log.w(
                AUTH_REPOSITORY_TAG,
                "Auth request failed: code=${error.code} httpStatus=${error.httpStatus} " +
                    "retryable=${error.retryable} requestId=${error.requestId ?: "none"}",
            )
            this
        }
    }
}

class ApiSessionRefresher(private val api: AuthApiService) : SessionRefresher {
    override suspend fun refresh(refreshToken: String) =
        apiCall { api.refresh(RefreshRequest(refreshToken)) }.map { it.credentials() }

    override suspend fun revoke(refreshToken: String) =
        apiCall { api.logout(null, LogoutRequest(refreshToken)) }.map { Unit }
}

private fun SessionResponseDto.credentials() = SessionCredentials(
    accessToken = accessToken,
    accessTokenExpiresAtEpochMilliseconds = Instant.parse(accessTokenExpiresAt).toEpochMilli(),
    refreshToken = refreshToken,
    refreshTokenExpiresAtEpochMilliseconds = Instant.parse(refreshTokenExpiresAt).toEpochMilli(),
    account = SessionAccount(
        id = user.id,
        onboardingCompleted = user.onboardingCompleted,
    ),
)

private const val AUTH_REPOSITORY_TAG = "PlainstrideAuthRepo"
