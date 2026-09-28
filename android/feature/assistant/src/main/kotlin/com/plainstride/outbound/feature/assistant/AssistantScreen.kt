package com.plainstride.outbound.feature.assistant

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.automirrored.filled.HelpOutline
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.filled.NearMe
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.shape.CircleShape
import androidx.core.content.ContextCompat
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.plainstride.outbound.core.assistant.ActivityVoiceCommandParser
import com.plainstride.outbound.core.assistant.AssistantCapability
import com.plainstride.outbound.core.assistant.AssistantSuggestion
import com.plainstride.outbound.core.assistant.SpeechRecognitionState
import com.plainstride.outbound.core.assistant.VoiceSport
import kotlinx.coroutines.delay
import kotlin.math.PI
import kotlin.math.sin

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
    val suggestions = if (screen == "today") listOf(
        AssistantSuggestion("today-easier", AssistantCapability.Plan, stringResource(R.string.assistant_today_easier), stringResource(R.string.assistant_prompt_today_easier)),
        AssistantSuggestion("today-why", AssistantCapability.Discover, stringResource(R.string.assistant_today_why), stringResource(R.string.assistant_prompt_today_why)),
        AssistantSuggestion("today-history", AssistantCapability.Navigate, stringResource(R.string.assistant_today_history), stringResource(R.string.assistant_prompt_today_history)),
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
    val lastItemIndex = 2 + suggestions.size + state.conversation.messages.size +
        (if (state.conversation.confirmation != null) 1 else 0) +
        (if (state.conversation.sending) 1 else 0)
    LaunchedEffect(state.conversation.messages.size, state.conversation.sending, state.conversation.confirmation, suggestions.size) {
        val hasConversationContent = state.conversation.messages.isNotEmpty() || state.conversation.sending || state.conversation.confirmation != null
        if (hasConversationContent && lastItemIndex > 0) listState.animateScrollToItem(lastItemIndex - 1)
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
        Column(Modifier.fillMaxSize().padding(padding).imePadding()) {
            LazyColumn(
                state = listState,
                modifier = Modifier.weight(1f).fillMaxWidth(),
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 14.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                item {
                    Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Surface(
                            modifier = Modifier.size(30.dp),
                            shape = CircleShape,
                            color = MaterialTheme.colorScheme.primary.copy(alpha = 0.12f),
                        ) {
                            Box(contentAlignment = Alignment.Center) {
                                Icon(Icons.Default.AutoAwesome, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                            }
                        }
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
                    Button(
                        onClick = { viewModel.selectSuggestion(suggestion, screen) },
                        modifier = Modifier.fillMaxWidth(),
                        shape = CircleShape,
                        colors = ButtonDefaults.buttonColors(
                            containerColor = MaterialTheme.colorScheme.surfaceVariant,
                            contentColor = MaterialTheme.colorScheme.onSurface,
                        ),
                        contentPadding = PaddingValues(horizontal = 14.dp, vertical = 10.dp),
                    ) {
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            Icon(capabilityIcon(suggestion.capability), contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                            Text(suggestion.title, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurface, textAlign = androidx.compose.ui.text.style.TextAlign.Start, maxLines = 1)
                        }
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
            }
            Column(
                Modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = 12.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                when (state.speech) {
                    is SpeechRecognitionState.Listening -> Row(
                        Modifier.fillMaxWidth().padding(start = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        AssistantListeningWave(MaterialTheme.colorScheme.primary)
                        Text(stringResource(R.string.assistant_listening), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
                    }
                    is SpeechRecognitionState.Failure -> Text(
                        stringResource(R.string.assistant_speech_error),
                        Modifier.fillMaxWidth().padding(start = 6.dp),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                    else -> Unit
                }
                Row(
                    Modifier.fillMaxWidth(),
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
                        modifier = Modifier.semantics {
                            contentDescription = context.getString(if (state.speech is SpeechRecognitionState.Listening) R.string.assistant_stop_listening else R.string.listen)
                        },
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
}

private fun capabilityIcon(capability: AssistantCapability) = when (capability) {
    AssistantCapability.Discover -> Icons.Default.AutoAwesome
    AssistantCapability.Navigate -> Icons.Default.NearMe
    AssistantCapability.Support -> Icons.AutoMirrored.Filled.HelpOutline
    AssistantCapability.Brainstorm -> Icons.Default.Lightbulb
    AssistantCapability.Plan -> Icons.Default.CalendarMonth
}

@Composable
private fun capabilityTitle(capability: AssistantCapability): String = stringResource(when (capability) {
    AssistantCapability.Discover -> R.string.assistant_capability_discover
    AssistantCapability.Navigate -> R.string.assistant_capability_navigate
    AssistantCapability.Support -> R.string.assistant_capability_support
    AssistantCapability.Brainstorm -> R.string.assistant_capability_brainstorm
    AssistantCapability.Plan -> R.string.assistant_capability_plan
})

@Composable
private fun AssistantListeningWave(accentColor: Color) {
    val transition = rememberInfiniteTransition(label = "assistantListeningWave")
    val phase = transition.animateFloat(
        initialValue = 0f,
        targetValue = (2 * PI).toFloat(),
        animationSpec = infiniteRepeatable(animation = tween(900, easing = LinearEasing)),
        label = "assistantListeningWavePhase",
    ).value
    Canvas(Modifier.size(28.dp, 18.dp)) {
        val barWidth = size.width * 0.11f
        val gap = size.width * 0.11f
        repeat(5) { index ->
            val height = size.height * (0.28f + ((sin(phase + index * 0.72f) + 1f) / 2f) * 0.72f)
            val x = index * (barWidth + gap)
            drawRoundRect(
                color = accentColor,
                topLeft = Offset(x, (size.height - height) / 2f),
                size = Size(barWidth, height),
                cornerRadius = CornerRadius(barWidth / 2f),
            )
        }
    }
}

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
