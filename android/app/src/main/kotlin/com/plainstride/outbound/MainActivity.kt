package com.plainstride.outbound

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dagger.hilt.android.AndroidEntryPoint
import com.plainstride.outbound.core.designsystem.PlainstrideTheme
import com.plainstride.outbound.feature.settings.AppearanceMode
import com.plainstride.outbound.feature.settings.SettingsViewModel
import com.plainstride.outbound.di.SpotifyOAuthClient

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    private var transferCode by mutableStateOf<String?>(null)
    private var navigationUri by mutableStateOf<Uri?>(null)
    private var connectionCode by mutableStateOf<String?>(null)
    private var groupInviteToken by mutableStateOf<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        transferCode = intent.transferCode()
        if (intent.action == SpotifyOAuthClient.CALLBACK) SpotifyOAuthClient.complete(intent)
        navigationUri = intent.navigationUri()
        connectionCode = intent.connectionCode()
        groupInviteToken = intent.groupInviteToken()
        enableEdgeToEdge()
        setContent {
            val settingsViewModel: SettingsViewModel = hiltViewModel()
            val settings by settingsViewModel.state.collectAsStateWithLifecycle()
            val darkTheme = when (settings.preferences.appearance) {
                AppearanceMode.System -> isSystemInDarkTheme()
                AppearanceMode.Light -> false
                AppearanceMode.Dark -> true
            }
            PlainstrideTheme(theme = settings.preferences.theme, darkTheme = darkTheme) {
                PlainstrideApp(
                    settingsViewModel = settingsViewModel,
                    transferCode = transferCode,
                    onTransferCodeConsumed = { transferCode = null },
                    navigationUri = navigationUri,
                    onNavigationUriConsumed = { navigationUri = null },
                    connectionCode = connectionCode,
                    onConnectionCodeConsumed = { connectionCode = null },
                    groupInviteToken = groupInviteToken,
                    onGroupInviteConsumed = { groupInviteToken = null },
                )
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        transferCode = intent.transferCode()
        if (intent.action == SpotifyOAuthClient.CALLBACK) SpotifyOAuthClient.complete(intent)
        navigationUri = intent.navigationUri()
        connectionCode = intent.connectionCode()
        groupInviteToken = intent.groupInviteToken()
    }

    private fun Intent.transferCode(): String? {
        val uri: Uri = data ?: return null
        if (uri.scheme != "https" || uri.host != "plainstride.ai" || uri.path != "/account-link") return null
        return uri.getQueryParameter("code")?.take(32)
    }

    private fun Intent.navigationUri(): Uri? = data?.takeIf { uri ->
        uri.scheme == "plainstride" && uri.host == "notification"
    }

    private fun Intent.connectionCode(): String? {
        val uri = data ?: return null
        val segments = uri.pathSegments
        if (uri.scheme != "https" || uri.host != "plainstride.ai") return null
        val code = when {
            segments.size == 2 && segments[0] == "connect" -> segments[1]
            segments.size == 3 && segments[0] == "invite" && segments[1] == "r" -> segments[2]
            else -> return null
        }
        return code.lowercase().takeIf { it.matches(Regex("[a-z0-9]{8}")) }
    }

    private fun Intent.groupInviteToken(): String? {
        val uri = data ?: return null
        val segments = uri.pathSegments
        if (uri.scheme != "https" || uri.host != "plainstride.ai" || segments.size != 3 || segments[0] != "invite" || segments[1] != "group") return null
        return segments[2].takeIf { it.isNotBlank() }
    }
}
