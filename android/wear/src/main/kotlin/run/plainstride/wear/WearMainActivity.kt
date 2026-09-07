package run.plainstride.wear

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.wear.compose.material.*
import androidx.compose.foundation.layout.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.res.stringResource
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import kotlinx.coroutines.*
import run.plainstride.core.model.activity.SessionPhase

class WearMainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) { super.onCreate(savedInstanceState); val gateway = WearSessionGatewayImpl(this); setContent { var granted by androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf(false) }; val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { granted = it.values.all { value -> value } }; androidx.compose.runtime.LaunchedEffect(Unit) { permission.launch(arrayOf(android.Manifest.permission.BODY_SENSORS, android.Manifest.permission.ACTIVITY_RECOGNITION, android.Manifest.permission.ACCESS_FINE_LOCATION)) }; val state by WearSessionStateStore.state.collectAsStateWithLifecycle(); MaterialTheme { Screen(state, gateway, granted) } } }
}

@androidx.compose.runtime.Composable private fun Screen(state: run.plainstride.core.model.activity.SessionStateEnvelope?, gateway: WearSessionGateway, granted: Boolean) {
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    Column(Modifier.fillMaxSize().padding(12.dp), verticalArrangement = Arrangement.Center) {
        Text(stringResource(when (state?.phase) { SessionPhase.ACTIVE -> R.string.active; SessionPhase.PAUSED -> R.string.paused; SessionPhase.FINISHED -> R.string.finished; else -> R.string.ready }))
        Text(stringResource(R.string.elapsed_distance, state?.elapsedSeconds ?: 0, (state?.distanceMeters ?: 0.0) / 1000))
        state?.heartRateBpm?.let { Text(stringResource(R.string.heart_rate, it.toInt())) }
        val command = when (state?.phase) { SessionPhase.ACTIVE -> WearSessionCommand.Pause; SessionPhase.PAUSED -> WearSessionCommand.Resume; SessionPhase.FINISHED -> WearSessionCommand.Start; else -> WearSessionCommand.Start }
        if (!granted) Text(stringResource(R.string.permissions_required))
        Button(enabled = granted || command != WearSessionCommand.Start, onClick = { scope.launch { gateway.send(command) } }) { Text(stringResource(when(command) { WearSessionCommand.Start -> R.string.start; WearSessionCommand.Pause -> R.string.pause; WearSessionCommand.Resume -> R.string.resume; WearSessionCommand.Finish -> R.string.finish })) }
        if (state?.phase == SessionPhase.ACTIVE || state?.phase == SessionPhase.PAUSED) Button(onClick = { scope.launch { gateway.send(WearSessionCommand.Finish) } }) { Text(stringResource(R.string.finish)) }
    }
}
