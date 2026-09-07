package run.plainstride.core.auth

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import run.plainstride.core.model.EpochClock
import run.plainstride.core.network.ApiResult

class DefaultSessionCoordinator(
    private val store: SecureSessionStore,
    private val refresher: SessionRefresher,
    private val clock: EpochClock,
) : SessionCoordinator {
    private val sessionMutex = Mutex()
    private val mutableState = MutableStateFlow<SessionState>(SessionState.Loading)
    override val state: StateFlow<SessionState> = mutableState.asStateFlow()

    override suspend fun install(credentials: SessionCredentials) = sessionMutex.withLock {
        store.replace(credentials)
        mutableState.value = credentials.signedInState()
    }

    override suspend fun validAccessToken(): String? = sessionMutex.withLock {
        val credentials = store.load()
        if (credentials == null || credentials.refreshTokenExpiresAtEpochMilliseconds <= clock.nowEpochMilliseconds()) {
            store.clear()
            mutableState.value = SessionState.SignedOut
            return@withLock null
        }

        if (credentials.accessTokenExpiresAtEpochMilliseconds - EXPIRY_SKEW_MILLISECONDS > clock.nowEpochMilliseconds()) {
            mutableState.value = credentials.signedInState()
            return@withLock credentials.accessToken
        }

        mutableState.value = SessionState.Refreshing(credentials.accessTokenExpiresAtEpochMilliseconds)
        when (val result = refresher.refresh(credentials.refreshToken)) {
            is ApiResult.Success -> {
                store.replace(result.value)
                mutableState.value = result.value.signedInState()
                result.value.accessToken
            }
            is ApiResult.Failure -> {
                if (!result.error.retryable) {
                    store.clear()
                    mutableState.value = SessionState.SignedOut
                } else {
                    mutableState.value = credentials.signedInState()
                }
                null
            }
        }
    }

    override suspend fun signOut() = sessionMutex.withLock {
        val refreshToken = store.load()?.refreshToken
        store.clear()
        mutableState.value = SessionState.SignedOut
        if (refreshToken != null) refresher.revoke(refreshToken)
        Unit
    }

    private fun SessionCredentials.signedInState() =
        SessionState.SignedIn(accessTokenExpiresAtEpochMilliseconds)

    private companion object {
        const val EXPIRY_SKEW_MILLISECONDS = 60_000L
    }
}
