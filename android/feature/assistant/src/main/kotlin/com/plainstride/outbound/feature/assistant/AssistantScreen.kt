package com.plainstride.outbound.feature.assistant

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.plainstride.outbound.core.assistant.ActivityVoiceCommandParser
import com.plainstride.outbound.core.assistant.AssistantCapability
import com.plainstride.outbound.core.assistant.AssistantSuggestion
import com.plainstride.outbound.core.assistant.SpeechRecognitionState
import com.plainstride.outbound.core.assistant.VoiceSport
import kotlinx.coroutines.delay

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AssistantRoute(
    accountId: String,
    screen: String,
    onClose: () -> Unit,
    onNavigate: (String) -> Unit,
    onPrepareActivity: (VoiceSport, Double?, Int?) -> Unit,
    onActionApplied: () -> Unit = {},
    viewModel: AssistantViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val listState = rememberLazyListState()
    val suggestions = if (screen == "recording") listOf(
        viewModel.suggestions.first { it.id == "live-status" },
        viewModel.suggestions.first { it.id == "live-focus" },
    ) else if (screen == "today") listOf(
        AssistantSuggestion("today-easier", AssistantCapability.Plan, stringResource(R.string.assistant_today_easier), stringResource(R.string.assistant_prompt_today_easier)),
        AssistantSuggestion("today-why", AssistantCapability.Discover, stringResource(R.string.assistant_today_why), stringResource(R.string.assistant_prompt_today_why)),
        viewModel.suggestions.first { it.capability == AssistantCapability.Navigate },
    ) else viewModel.suggestions
    LaunchedEffect(accountId) { viewModel.initialize(accountId) }
    LaunchedEffect(state.speech) {
        when (val speech = state.speech) {
            is SpeechRecognitionState.Listening -> if (speech.partialTranscript.isNotBlank()) {
                viewModel.draft(speech.partialTranscript)
                if (ActivityVoiceCommandParser.parse(speech.partialTranscript) != null) {
                    delay(900)
                    if (state.speech == speech) viewModel.handleStableSpeechCommand(speech.partialTranscript, screen)
                }
            }
            is SpeechRecognitionState.Result -> viewModel.handleSpeechResult(speech.transcript, screen)
            else -> Unit
        }
    }
    LaunchedEffect(state.conversation.messages.size, state.conversation.sending) {
        val count = state.conversation.messages.size + if (state.conversation.sending) 1 else 0
        if (count > 0) listState.animateScrollToItem(count + 2)
    }
    LaunchedEffect(state.activityCommand) {
        state.activityCommand?.let { command ->
            viewModel.consumeActivityCommand()
            onClose()
            onPrepareActivity(command.sport, command.distanceMeters, command.durationSeconds)
        }
    }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { viewModel.listen(it) }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.assistant_title)) },
                navigationIcon = { TextButton(onClick = onClose) { Text(stringResource(R.string.close)) } },
                actions = { TextButton(onClick = viewModel::reset) { Text(stringResource(R.string.reset)) } },
            )
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            LazyColumn(
                state = listState,
                modifier = Modifier.weight(1f).fillMaxWidth(),
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 14.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                item {
                    Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Icon(Icons.Default.AutoAwesome, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(stringResource(R.string.assistant_context_title), style = MaterialTheme.typography.titleSmall)
                            Text(
                                if (screen == "recording") stringResource(R.string.assistant_context_recording)
                                else if (screen == "today") stringResource(R.string.assistant_context_today)
                                else stringResource(R.string.assistant_context_screen, screenLabel(screen)),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
                item { Text(stringResource(R.string.assistant_try), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                items(suggestions, key = { it.id }) { suggestion ->
                    OutlinedButton(
                        onClick = { viewModel.selectSuggestion(suggestion, screen) },
                        modifier = Modifier.fillMaxWidth(),
                        contentPadding = PaddingValues(horizontal = 14.dp, vertical = 10.dp),
                    ) {
                        Text(capabilityTitle(suggestion.capability), color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.labelMedium)
                        Spacer(Modifier.width(10.dp))
                        Text(suggestion.title, modifier = Modifier.weight(1f), color = MaterialTheme.colorScheme.onSurface)
                    }
                }
                items(state.conversation.messages) { message ->
                    val isUser = message.role == "user"
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = if (isUser) Arrangement.End else Arrangement.Start) {
                        Card(
                            modifier = Modifier.widthIn(max = 340.dp),
                            colors = CardDefaults.cardColors(containerColor = if (isUser) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant),
                        ) {
                            Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                                val capability = message.capability
                                if (!isUser && capability != null) {
                                    Text(capabilityTitle(capability), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
                                }
                                Text(message.text, color = if (isUser) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurfaceVariant)
                                message.navigationTarget?.let { target ->
                                        TextButton(onClick = { onClose(); onNavigate(target) }) {
                                        Text(stringResource(R.string.assistant_accessibility_open_destination, destinationLabel(target)))
                                    }
                                }
                            }
                        }
                    }
                }
                state.conversation.confirmation?.let { confirmation ->
                    item {
                        Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.secondaryContainer)) {
                            Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text(confirmation.title, style = MaterialTheme.typography.titleSmall)
                                Text(confirmation.explanation, style = MaterialTheme.typography.bodySmall)
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    OutlinedButton(onClick = { viewModel.decide(confirmation.actionId, false) }) { Text(confirmation.rejectLabel) }
                                    Button(onClick = { viewModel.decide(confirmation.actionId, true, onActionApplied) }) { Text(confirmation.acceptLabel) }
                                }
                            }
                        }
                    }
                }
                if (state.conversation.sending) item {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                        Text(stringResource(R.string.assistant_thinking), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                if (state.speech is SpeechRecognitionState.Failure) item {
                    Text(stringResource(R.string.assistant_speech_error), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                }
            }
            if (state.speech is SpeechRecognitionState.Listening) {
                Text(stringResource(R.string.assistant_listening), Modifier.padding(start = 18.dp, bottom = 4.dp), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
            }
            Row(
                Modifier.fillMaxWidth().imePadding().navigationBarsPadding().padding(horizontal = 12.dp, vertical = 8.dp),
                verticalAlignment = Alignment.Bottom,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                OutlinedTextField(
                    value = state.draft,
                    onValueChange = viewModel::draft,
                    modifier = Modifier.weight(1f),
                    placeholder = { Text(stringResource(R.string.assistant_prompt)) },
                    maxLines = 4,
                )
                IconButton(
                    onClick = {
                        if (state.speech is SpeechRecognitionState.Listening) viewModel.stopListening()
                        else if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) viewModel.listen(true)
                        else permission.launch(Manifest.permission.RECORD_AUDIO)
                    },
                    modifier = Modifier.semantics { contentDescription = context.getString(R.string.listen) },
                ) {
                    Icon(if (state.speech is SpeechRecognitionState.Listening) Icons.Default.Stop else Icons.Default.Mic, contentDescription = null)
                }
                IconButton(onClick = { viewModel.send(screen) }, enabled = state.draft.isNotBlank() && !state.conversation.sending) {
                    Icon(Icons.AutoMirrored.Filled.Send, contentDescription = stringResource(R.string.send))
                }
            }
        }
    }
}

@Composable private fun capabilityTitle(capability: AssistantCapability): String = stringResource(when (capability) {
    AssistantCapability.Discover -> R.string.assistant_capability_discover
    AssistantCapability.Navigate -> R.string.assistant_capability_navigate
    AssistantCapability.Support -> R.string.assistant_capability_support
    AssistantCapability.Brainstorm -> R.string.assistant_capability_brainstorm
    AssistantCapability.Plan -> R.string.assistant_capability_plan
})

@Composable private fun screenLabel(screen: String): String = stringResource(when (screen) {
    "social" -> R.string.assistant_destination_social
    "me" -> R.string.assistant_destination_me
    "today" -> R.string.assistant_destination_today
    else -> R.string.assistant_destination_settings
})

@Composable private fun destinationLabel(route: String): String = stringResource(when (route) {
    "today" -> R.string.assistant_destination_today
    "social" -> R.string.assistant_destination_social
    "me" -> R.string.assistant_destination_me
    "activity_history" -> R.string.assistant_destination_history
    "health" -> R.string.assistant_destination_health
    "music" -> R.string.assistant_destination_music
    else -> R.string.assistant_destination_settings
})
