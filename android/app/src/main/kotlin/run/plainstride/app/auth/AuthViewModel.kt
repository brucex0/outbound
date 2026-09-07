package run.plainstride.app.auth

import android.os.Build
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
import run.plainstride.core.analytics.AnalyticsEvent
import run.plainstride.core.analytics.AnalyticsProperty
import run.plainstride.core.analytics.ProductAnalytics
import run.plainstride.core.auth.AuthRepository
import run.plainstride.core.auth.SessionCoordinator
import run.plainstride.core.auth.SessionState
import run.plainstride.core.network.ApiErrorCode
import run.plainstride.core.network.ApiResult
import androidx.credentials.exceptions.GetCredentialCancellationException
import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import run.plainstride.app.notifications.PlainstrideMessagingService
import run.plainstride.feature.safety.LiveShareCoordinator
import run.plainstride.core.database.AccountDatabaseOperations

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
    @param:ApplicationContext private val context: Context,
) : ViewModel() {
    private val operation = MutableStateFlow<AuthOperation?>(null)
    private val confirmDeletion = MutableStateFlow(false)
    val state: StateFlow<AuthUiState> = combine(sessions.state, operation, confirmDeletion, ::AuthUiState)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), AuthUiState())
    private val mutableMessages = MutableSharedFlow<AuthMessage>(extraBufferCapacity = 1)
    val messages = mutableMessages.asSharedFlow()

    init { viewModelScope.launch { sessions.restore() } }

    fun signIn() = perform(AuthOperation.SignIn, "auth_sign_in") {
        google.identityToken().fold(
            onSuccess = { repository.signIn(it, CURRENT_TERMS_VERSION, Build.MODEL.take(100)) },
            onFailure = { credentialFailure(it) },
        )
    }

    fun linkGoogle() = perform(AuthOperation.Link, "auth_link_google", AuthMessage.Linked) {
        google.identityToken().fold(
            onSuccess = { repository.linkGoogle(it) },
            onFailure = { credentialFailure(it) },
        )
    }

    fun redeemTransfer(code: String) = perform(AuthOperation.Redeem, "account_transfer_redeemed", AuthMessage.Transferred) {
        val normalized = code.trim().uppercase().replace(Regex("[^2-9A-Z]"), "")
        if (normalized.length != 16) return@perform ApiResult.Failure(
            run.plainstride.core.network.ApiFailure(ApiErrorCode.InvalidRequest, retryable = false)
        )
        google.identityToken().fold(
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
    fun deleteAccount() {
        confirmDeletion.value = false
        perform(AuthOperation.Delete, "auth_delete_account", AuthMessage.Deleted) {
            val accountId = (sessions.state.value as? SessionState.SignedIn)?.accountId
                ?: (sessions.state.value as? SessionState.Refreshing)?.accountId
            unregisterPush()
            google.identityToken().fold(
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
            val result = block()
            val outcome = if (result is ApiResult.Success) "success" else "failure"
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
        return ApiResult.Failure(run.plainstride.core.network.ApiFailure(code, retryable = false))
    }

    private fun ApiResult.Failure.toMessage() = when (error.code) {
        ApiErrorCode.NetworkUnavailable -> AuthMessage.Offline
        ApiErrorCode.ServerUnavailable, ApiErrorCode.RateLimited -> AuthMessage.Unavailable
        ApiErrorCode.Unauthenticated -> if (operation.value == AuthOperation.Redeem) AuthMessage.InvalidTransfer else AuthMessage.InvalidCredential
        ApiErrorCode.Conflict -> AuthMessage.Conflict
        ApiErrorCode.InvalidRequest -> AuthMessage.Configuration
        ApiErrorCode.Cancelled -> AuthMessage.Cancelled
        else -> AuthMessage.Generic
    }

    private companion object { const val CURRENT_TERMS_VERSION = 2 }
}
