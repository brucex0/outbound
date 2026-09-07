package run.plainstride.app.auth

import android.content.Context
import androidx.credentials.ClearCredentialStateRequest
import androidx.credentials.CredentialManager
import androidx.credentials.GetCredentialRequest
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject

class GoogleCredentialProvider @Inject constructor(
    @param:ApplicationContext private val context: Context,
    private val credentialManager: CredentialManager,
    @param:GoogleServerClientId
    private val serverClientId: String,
) {
    suspend fun identityToken(): Result<String> = runCatching {
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
    }

    suspend fun clear() {
        runCatching { credentialManager.clearCredentialState(ClearCredentialStateRequest()) }
    }
}

@javax.inject.Qualifier
@Retention(AnnotationRetention.BINARY)
annotation class GoogleServerClientId
