package com.plainstride.outbound.core.auth

import kotlinx.coroutines.flow.StateFlow
import com.plainstride.outbound.core.network.ApiResult

data class SessionCredentials(
    val accessToken: String,
    val accessTokenExpiresAtEpochMilliseconds: Long,
    val refreshToken: String,
    val refreshTokenExpiresAtEpochMilliseconds: Long,
    val account: SessionAccount? = null,
)

data class SessionAccount(
    val id: String,
    val onboardingCompleted: Boolean?,
)

interface SecureSessionStore {
    suspend fun load(): SessionCredentials?
    suspend fun replace(credentials: SessionCredentials)
    suspend fun clear()
}

sealed interface SessionState {
    data object Loading : SessionState
    data object SignedOut : SessionState
    data class SignedIn(val accessTokenExpiresAtEpochMilliseconds: Long, val accountId: String?) : SessionState
    data class Refreshing(val accessTokenExpiresAtEpochMilliseconds: Long, val accountId: String?) : SessionState
}

interface SessionRefresher {
    suspend fun refresh(refreshToken: String): ApiResult<SessionCredentials>
    suspend fun revoke(refreshToken: String): ApiResult<Unit>
}

interface SessionCoordinator {
    val state: StateFlow<SessionState>
    suspend fun restore()
    suspend fun install(credentials: SessionCredentials)
    suspend fun validAccessToken(): String?
    suspend fun signOut()
}
