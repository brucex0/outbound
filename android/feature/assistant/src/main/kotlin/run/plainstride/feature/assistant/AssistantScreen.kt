package run.plainstride.feature.assistant

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Send
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import run.plainstride.core.assistant.SpeechRecognitionState

@OptIn(ExperimentalMaterial3Api::class)
@Composable fun AssistantRoute(accountId: String, onClose: () -> Unit, viewModel: AssistantViewModel = hiltViewModel()) {
    val state by viewModel.state.collectAsStateWithLifecycle(); val context = LocalContext.current
    LaunchedEffect(accountId) { viewModel.initialize(accountId) }
    LaunchedEffect(state.speech) { val speech = state.speech; if (speech is SpeechRecognitionState.Result) { viewModel.draft(speech.transcript) } }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { viewModel.listen(it) }
    Scaffold(topBar = { TopAppBar(title = { Text(stringResource(R.string.assistant_title)) }, navigationIcon = { TextButton(onClick = onClose) { Text(stringResource(R.string.close)) } }, actions = { TextButton(onClick = viewModel::reset) { Text(stringResource(R.string.reset)) } }) }) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).padding(16.dp)) {
            LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                items(state.conversation.messages) { message -> Surface(color = if (message.role == "user") MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceVariant, shape = MaterialTheme.shapes.medium) { Text(message.text, Modifier.padding(12.dp)) } }
                state.conversation.confirmation?.let { confirmation -> item { Card { Column(Modifier.padding(16.dp)) { Text(confirmation.title, style = MaterialTheme.typography.titleMedium); Text(confirmation.explanation); Row { TextButton({ viewModel.decide(confirmation.actionId, false) }) { Text(confirmation.rejectLabel) }; Button({ viewModel.decide(confirmation.actionId, true) }) { Text(confirmation.acceptLabel) } } } } } }
            }
            state.conversation.lastFailure?.let { Text(stringResource(R.string.assistant_offline_fallback), color = MaterialTheme.colorScheme.error) }
            Row { OutlinedTextField(state.draft, viewModel::draft, Modifier.weight(1f), placeholder = { Text(stringResource(R.string.assistant_prompt)) }); IconButton(onClick = { if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) viewModel.listen(true) else permission.launch(Manifest.permission.RECORD_AUDIO) }) { Icon(Icons.Default.Mic, stringResource(R.string.listen)) }; IconButton(onClick = viewModel::send, enabled = !state.conversation.sending) { Icon(Icons.Default.Send, stringResource(R.string.send)) } }
        }
    }
}
