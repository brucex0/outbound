package com.plainstride.outbound.auth

import android.content.Context
import android.util.Log
import androidx.credentials.ClearCredentialStateRequest
import androidx.credentials.CredentialManager
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialException
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import javax.inject.Inject

class GoogleCredentialProvider @Inject constructor(
    private val credentialManager: CredentialManager,
    @param:GoogleServerClientId
    private val serverClientId: String,
) {
    suspend fun identityToken(context: Context): Result<String> = runCatching {
        check(serverClientId.isNotBlank()) { "google_client_not_configured" }
        val option = GetGoogleIdOption.Builder()
            .setServerClientId(serverClientId)
            .setFilterByAuthorizedAccounts(false)
            .setAutoSelectEnabled(false)
            .build()
        val response = credentialManager.getCredential(
            context,
            GetCredentialRequest.Builder().addCredentialOption(option).build(),
        )
        check(response.credential.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) {
            "unsupported_google_credential"
        }
        GoogleIdTokenCredential.createFrom(response.credential.data).idToken
    }.onFailure { error ->
        val credentialType = (error as? GetCredentialException)?.type ?: "non_credential_exception"
        Log.w(TAG, "Credential Manager failed: type=$credentialType class=${error.javaClass.name}")
    }

    suspend fun clear() {
        runCatching { credentialManager.clearCredentialState(ClearCredentialStateRequest()) }
    }
}

@javax.inject.Qualifier
@Retention(AnnotationRetention.BINARY)
annotation class GoogleServerClientId

private const val TAG = "PlainstrideGoogleAuth"
