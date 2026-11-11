package com.plainstride.outbound

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.core.view.WindowCompat
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dagger.hilt.android.AndroidEntryPoint
import com.plainstride.outbound.core.designsystem.PlainstrideTheme
import com.plainstride.outbound.feature.settings.AppearanceMode
import com.plainstride.outbound.feature.settings.SettingsViewModel
import com.plainstride.outbound.di.SpotifyOAuthClient

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    @javax.inject.Inject lateinit var configurationSync: com.plainstride.outbound.preferences.AccountConfigurationSync
    override fun onResume() {
        super.onResume()
        configurationSync.refresh()
    }

    private var transferCode by mutableStateOf<String?>(null)
    private var navigationUri by mutableStateOf<Uri?>(null)
    private var connectionCode by mutableStateOf<String?>(null)
    private var groupInviteToken by mutableStateOf<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        transferCode = intent.transferCode()
        if (intent.action == SpotifyOAuthClient.CALLBACK) SpotifyOAuthClient.complete(intent)
        // Navigation restores its own stack. Replaying a consumed launch link would
        // insert its destination again above whichever nested page was restored.
        navigationUri = if (savedInstanceState == null) intent.navigationUri()
            else savedInstanceState.getString(PENDING_NAVIGATION)?.let(Uri::parse)
        connectionCode = if (savedInstanceState == null) intent.connectionCode()
            else savedInstanceState.getString(PENDING_CONNECTION)
        groupInviteToken = if (savedInstanceState == null) intent.groupInviteToken()
            else savedInstanceState.getString(PENDING_GROUP_INVITE)
        enableEdgeToEdge()
        setContent {
            val settingsViewModel: SettingsViewModel = hiltViewModel()
            val settings by settingsViewModel.state.collectAsStateWithLifecycle()
            val darkTheme = when (settings.preferences.appearance) {
                AppearanceMode.System -> isSystemInDarkTheme()
                AppearanceMode.Light -> false
                AppearanceMode.Dark -> true
            }
            SideEffect {
                val insetsController = WindowCompat.getInsetsController(window, window.decorView)
                insetsController.isAppearanceLightStatusBars = !darkTheme
                insetsController.isAppearanceLightNavigationBars = !darkTheme
            }
            PlainstrideTheme(theme = settings.preferences.theme, darkTheme = darkTheme) {
                if (BuildConfig.DEBUG && intent.getBooleanExtra("debug_activity_repository", false)) DebugActivityRepositoryHarness(settingsViewModel)
                else if (BuildConfig.DEBUG && intent.getBooleanExtra("debug_session_effort", false)) DebugSessionEffortHarness()
                else if (BuildConfig.DEBUG && intent.getBooleanExtra("debug_running_plan", false)) DebugRunningPlanHarness() else PlainstrideApp(
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

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putString(PENDING_NAVIGATION, navigationUri?.toString())
        outState.putString(PENDING_CONNECTION, connectionCode)
        outState.putString(PENDING_GROUP_INVITE, groupInviteToken)
    }

    private companion object {
        const val PENDING_NAVIGATION = "pending_navigation_uri"
        const val PENDING_CONNECTION = "pending_connection_code"
        const val PENDING_GROUP_INVITE = "pending_group_invite"
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

    private fun Intent.navigationUri(): Uri? {
        data?.takeIf { it.scheme == "plainstride" && it.host == "notification" }?.let { return it }
        // Background FCM notification messages launch the activity with data extras.
        val type = getStringExtra("type")?.take(48) ?: return null
        val objectId = getStringExtra("objectId")?.take(160).orEmpty()
        val notificationId = getStringExtra("notificationId")?.take(160).orEmpty()
        val destination = com.plainstride.outbound.feature.safety.NotificationPresentationPolicy.deepLinkDestination(type, objectId)
        return Uri.Builder().scheme("plainstride").authority("notification")
            .appendPath(destination).appendQueryParameter("id", objectId)
            .appendQueryParameter("notification", notificationId).appendQueryParameter("type", type).build()
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
