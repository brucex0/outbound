package run.plainstride.app

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import dagger.hilt.android.AndroidEntryPoint
import run.plainstride.core.designsystem.PlainstrideTheme

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    private var transferCode by mutableStateOf<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        transferCode = intent.transferCode()
        enableEdgeToEdge()
        setContent {
            PlainstrideTheme {
                PlainstrideApp(transferCode = transferCode, onTransferCodeConsumed = { transferCode = null })
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        transferCode = intent.transferCode()
    }

    private fun Intent.transferCode(): String? {
        val uri: Uri = data ?: return null
        if (uri.scheme != "https" || uri.host != "run.plainstride.com" || uri.path != "/account-link") return null
        return uri.getQueryParameter("code")?.take(32)
    }
}
