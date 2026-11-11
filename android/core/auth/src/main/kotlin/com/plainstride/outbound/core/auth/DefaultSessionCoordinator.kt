package com.plainstride.outbound.core.auth

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import com.plainstride.outbound.core.model.EpochClock
import com.plainstride.outbound.core.network.ApiResult

class DefaultSessionCoordinator(
    private val store: SecureSessionStore,
    private val refresher: SessionRefresher,
    private val clock: EpochClock,
) : SessionCoordinator {
    private val sessionMutex = Mutex()
    private val epoch = java.util.concurrent.atomic.AtomicLong()
    override val generation: Long get() = epoch.get()
    private val mutableState = MutableStateFlow<SessionState>(SessionState.Loading)
    override val state: StateFlow<SessionState> = mutableState.asStateFlow()

    override suspend fun restore() = sessionMutex.withLock {
        val credentials = store.load()
        if (credentials == null || credentials.refreshTokenExpiresAtEpochMilliseconds <= clock.nowEpochMilliseconds()) {
            store.clear()
            mutableState.value = SessionState.SignedOut
        } else {
            // Preserve offline access to local data. Network-bound callers refresh lazily.
            mutableState.value = credentials.signedInState()
        }
    }

    override suspend fun install(credentials: SessionCredentials) {
        val context = epoch.incrementAndGet()
        sessionMutex.withLock {
            if (epoch.get() != context) return@withLock
            store.replace(credentials)
            if (epoch.get() == context) mutableState.value = credentials.signedInState()
        }
    }

    override suspend fun validAccessToken(): String? = sessionMutex.withLock {
        val context = epoch.get()
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

        mutableState.value = SessionState.Refreshing(credentials.accessTokenExpiresAtEpochMilliseconds, credentials.account?.id)
        when (val result = refresher.refresh(credentials.refreshToken)) {
            is ApiResult.Success -> {
                if (epoch.get() != context || result.value.account?.id != credentials.account?.id) return@withLock null
                store.replace(result.value)
                if (epoch.get() != context) return@withLock null
                mutableState.value = result.value.signedInState()
                result.value.accessToken
            }
            is ApiResult.Failure -> {
                if (epoch.get() != context) return@withLock null
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

    override suspend fun signOut() {
        val context = epoch.incrementAndGet() // Fence old requests before waiting for a refresh to finish.
        sessionMutex.withLock {
        if (epoch.get() != context) return@withLock
        val refreshToken = store.load()?.refreshToken
        store.clear()
        mutableState.value = SessionState.SignedOut
        if (refreshToken != null) refresher.revoke(refreshToken)
        Unit
        }
    }

    private fun SessionCredentials.signedInState() =
        SessionState.SignedIn(accessTokenExpiresAtEpochMilliseconds, account?.id)

    private companion object {
        const val EXPIRY_SKEW_MILLISECONDS = 60_000L
    }
}
