package com.plainstride.outbound.auth

import android.os.Build
import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import com.plainstride.outbound.core.analytics.AnalyticsEvent
import com.plainstride.outbound.core.analytics.AnalyticsProperty
import com.plainstride.outbound.core.analytics.ProductAnalytics
import com.plainstride.outbound.core.auth.AuthRepository
import com.plainstride.outbound.core.auth.SessionCoordinator
import com.plainstride.outbound.core.auth.SessionState
import com.plainstride.outbound.core.network.ApiErrorCode
import com.plainstride.outbound.core.network.ApiResult
import androidx.credentials.exceptions.GetCredentialCancellationException
import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import com.plainstride.outbound.notifications.PlainstrideMessagingService
import com.plainstride.outbound.feature.safety.LiveShareCoordinator
import com.plainstride.outbound.core.database.AccountDatabaseOperations
import com.plainstride.outbound.subscriptions.RevenueCatCoordinator

data class AuthUiState(
    val session: SessionState = SessionState.Loading,
    val operation: AuthOperation? = null,
    val confirmDeletion: Boolean = false,
)

enum class AuthOperation { SignIn, SignOut, Link, Redeem, Delete }
enum class AuthMessage { Cancelled, Configuration, InvalidCredential, InvalidTransfer, Conflict, Offline, Unavailable, Generic, Linked, Transferred, SignedOut, Deleted }

@HiltViewModel
class AuthViewModel @Inject constructor(
    private val repository: AuthRepository,
    private val sessions: SessionCoordinator,
    private val google: GoogleCredentialProvider,
    private val analytics: ProductAnalytics,
    private val push: LiveShareCoordinator,
    private val accountData: AccountDatabaseOperations,
    private val revenueCat: RevenueCatCoordinator,
    @param:ApplicationContext private val context: Context,
) : ViewModel() {
    private val operation = MutableStateFlow<AuthOperation?>(null)
    private val confirmDeletion = MutableStateFlow(false)
    val state: StateFlow<AuthUiState> = combine(sessions.state, operation, confirmDeletion, ::AuthUiState)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), AuthUiState())
    private val mutableMessages = MutableSharedFlow<AuthMessage>(extraBufferCapacity = 1)
    val messages = mutableMessages.asSharedFlow()

    init {
        viewModelScope.launch {
            sessions.state.collect { session ->
                val accountId = when (session) {
                    is SessionState.SignedIn -> session.accountId
                    is SessionState.Refreshing -> session.accountId
                    SessionState.Loading, SessionState.SignedOut -> null
                }
                analytics.setUserId(accountId)
                revenueCat.activate(accountId)
            }
        }
        viewModelScope.launch { sessions.restore() }
    }

    fun signIn(activityContext: Context) = perform(AuthOperation.SignIn, "auth_sign_in") {
        google.identityToken(activityContext).fold(
            onSuccess = { repository.signIn(it, CURRENT_TERMS_VERSION, Build.MODEL.take(100)) },
            onFailure = { credentialFailure(it) },
        )
    }

    fun linkGoogle(activityContext: Context) = perform(AuthOperation.Link, "auth_link_google", AuthMessage.Linked) {
        google.identityToken(activityContext).fold(
            onSuccess = { repository.linkGoogle(it) },
            onFailure = { credentialFailure(it) },
        )
    }

    fun trackLegal(document: String) = analytics.record(
        AnalyticsEvent(
            "legal_document_opened",
            mapOf(
                AnalyticsProperty.EntrySource to "authentication",
                AnalyticsProperty.Result to document,
            ),
        ),
    )

    fun redeemTransfer(activityContext: Context, code: String) = perform(AuthOperation.Redeem, "account_transfer_redeemed", AuthMessage.Transferred) {
        val normalized = code.trim().uppercase().replace(Regex("[^2-9A-Z]"), "")
        Log.i(TAG, "Transfer redemption requested: normalizedCodeLength=${normalized.length}")
        if (normalized.length != 16) return@perform ApiResult.Failure(
            com.plainstride.outbound.core.network.ApiFailure(ApiErrorCode.InvalidRequest, retryable = false)
        )
        google.identityToken(activityContext).fold(
            onSuccess = { repository.redeemGoogleLink(it, normalized, CURRENT_TERMS_VERSION, Build.MODEL.take(100)) },
            onFailure = { credentialFailure(it) },
        )
    }

    fun signOut() = perform(AuthOperation.SignOut, "auth_sign_out", AuthMessage.SignedOut) {
        unregisterPush()
        sessions.signOut()
        google.clear()
        ApiResult.Success(Unit)
    }

    fun requestDeletion() { confirmDeletion.value = true }
    fun cancelDeletion() { confirmDeletion.value = false }
    fun deleteAccount(activityContext: Context) {
        confirmDeletion.value = false
        perform(AuthOperation.Delete, "auth_delete_account", AuthMessage.Deleted) {
            val accountId = (sessions.state.value as? SessionState.SignedIn)?.accountId
                ?: (sessions.state.value as? SessionState.Refreshing)?.accountId
            unregisterPush()
            google.identityToken(activityContext).fold(
                onSuccess = { token -> repository.deleteAccount(token).also { result -> if (result is ApiResult.Success && accountId != null) accountData.clearAccount(accountId) } },
                onFailure = { credentialFailure(it) },
            )
        }
    }

    private suspend fun unregisterPush() {
        val preferences = context.getSharedPreferences(PlainstrideMessagingService.PREFERENCES, Context.MODE_PRIVATE)
        preferences.getString(PlainstrideMessagingService.TOKEN, null)?.let { push.unregisterToken(it) }
        preferences.edit().clear().apply()
    }

    private fun perform(operationValue: AuthOperation, event: String, successMessage: AuthMessage? = null, block: suspend () -> ApiResult<Unit>) {
        if (operation.value != null) return
        viewModelScope.launch {
            operation.value = operationValue
            Log.i(TAG, "Auth operation started: operation=$operationValue")
            val result = block()
            val outcome = if (result is ApiResult.Success) "success" else "failure"
            when (result) {
                is ApiResult.Success -> Log.i(TAG, "Auth operation succeeded: operation=$operationValue")
                is ApiResult.Failure -> Log.w(
                    TAG,
                    "Auth operation failed: operation=$operationValue code=${result.error.code} " +
                        "httpStatus=${result.error.httpStatus} retryable=${result.error.retryable} " +
                        "requestId=${result.error.requestId ?: "none"}",
                )
            }
            analytics.record(AnalyticsEvent(event, mapOf(AnalyticsProperty.Result to outcome)))
            if (result is ApiResult.Success) successMessage?.let { mutableMessages.emit(it) }
            if (result is ApiResult.Failure) mutableMessages.emit(result.toMessage())
            operation.value = null
        }
    }

    private fun credentialFailure(error: Throwable): ApiResult.Failure {
        val code = when {
            error is GetCredentialCancellationException -> ApiErrorCode.Cancelled
            error.message == "google_client_not_configured" -> ApiErrorCode.InvalidRequest
            else -> ApiErrorCode.Unauthenticated
        }
        return ApiResult.Failure(com.plainstride.outbound.core.network.ApiFailure(code, retryable = false))
    }

    private fun ApiResult.Failure.toMessage() = when (error.code) {
        ApiErrorCode.NetworkUnavailable -> AuthMessage.Offline
        ApiErrorCode.ServerUnavailable, ApiErrorCode.RateLimited -> AuthMessage.Unavailable
        ApiErrorCode.Unauthenticated -> if (operation.value == AuthOperation.Redeem) AuthMessage.InvalidTransfer else AuthMessage.InvalidCredential
        ApiErrorCode.Conflict -> AuthMessage.Conflict
        ApiErrorCode.InvalidRequest -> if (error.httpStatus == null) {
            AuthMessage.Configuration
        } else {
            AuthMessage.InvalidCredential
        }
        ApiErrorCode.Cancelled -> AuthMessage.Cancelled
        else -> AuthMessage.Generic
    }

    private companion object {
        const val CURRENT_TERMS_VERSION = 2
        const val TAG = "PlainstrideAuth"
    }
}
