package run.plainstride.core.auth

data class SessionCredentials(
    val accessToken: String,
    val accessTokenExpiresAtEpochMilliseconds: Long,
    val refreshToken: String,
    val refreshTokenExpiresAtEpochMilliseconds: Long,
)

interface SecureSessionStore {
    suspend fun load(): SessionCredentials?
    suspend fun replace(credentials: SessionCredentials)
    suspend fun clear()
}

interface SessionCoordinator {
    suspend fun validAccessToken(): String?
    suspend fun signOut()
}
