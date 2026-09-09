package com.plainstride.outbound.feature.today

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import android.Manifest
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import java.text.DateFormat
import java.util.Date
import com.plainstride.outbound.core.model.ActivitySuggestion
import com.plainstride.outbound.core.model.AdjustmentProposal
import com.plainstride.outbound.core.designsystem.PlainstrideRouteMap

@Composable
fun TodayRoute(
    accountId: String,
    localeTag: String,
    viewModel: TodayViewModel,
    activeSession: Boolean,
    completedToday: Boolean,
    onStartWorkout: (WorkoutLaunchIntent) -> Unit,
    onStartFreestyle: () -> Unit,
    onReturnToSession: () -> Unit,
    onSetUpPlan: () -> Unit,
    onMessage: suspend (TodayMessage) -> Unit,
    initialWorkoutId: String? = null,
    guidanceContent: @Composable () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    LaunchedEffect(accountId, localeTag) { viewModel.configure(accountId, localeTag) }
    val state by viewModel.state.collectAsStateWithLifecycle()
    val weather by viewModel.weather.collectAsStateWithLifecycle()
    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        viewModel.refreshWeather()
    }
    LaunchedEffect(activeSession, completedToday) { viewModel.updateSessionState(activeSession, completedToday) }
    LaunchedEffect(viewModel) {
        viewModel.weatherPermissionRequests.collect {
            permissionLauncher.launch(Manifest.permission.ACCESS_COARSE_LOCATION)
        }
    }
    LaunchedEffect(viewModel) { viewModel.messages.collect(onMessage) }
    TodayScreen(
        state = state,
        weather = weather,
        onRefresh = viewModel::refresh,
        onStart = { suggestion, source ->
            viewModel.trackWorkoutStarted(source)
            onStartWorkout(viewModel.launchIntent(suggestion, source))
        },
        onStartFreestyle = onStartFreestyle,
        onReturnToSession = onReturnToSession,
        onSetUpPlan = { viewModel.setUpPlan(); onSetUpPlan() },
        onSubmitConstraint = viewModel::submitConstraint,
        onDecideAdjustment = viewModel::decideAdjustment,
        onCardDisplayChanged = viewModel::trackCardDisplayChanged,
        guidanceContent = guidanceContent,
        initialWorkoutId = initialWorkoutId,
        locationGranted = context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED,
        modifier = modifier,
    )
}

@Composable
fun TodayScreen(
    state: TodayUiState,
    weather: WeatherGuidance?,
    onRefresh: () -> Unit,
    onStart: (ActivitySuggestion, String) -> Unit,
    onStartFreestyle: () -> Unit,
    onReturnToSession: () -> Unit,
    onSetUpPlan: () -> Unit,
    onSubmitConstraint: (TodayConstraint, String, String?) -> Unit,
    onDecideAdjustment: (String, Boolean) -> Unit,
    onCardDisplayChanged: (Boolean) -> Unit = {},
    guidanceContent: @Composable () -> Unit = {},
    initialWorkoutId: String? = null,
    locationGranted: Boolean = false,
    modifier: Modifier = Modifier,
) {
    var showsDetail by rememberSaveable { mutableStateOf(false) }
    var showsChange by rememberSaveable { mutableStateOf(false) }
    val context = LocalContext.current
    val displayPreferences = remember(context) { context.getSharedPreferences("today_display", android.content.Context.MODE_PRIVATE) }
    var cardMinimized by rememberSaveable { mutableStateOf(displayPreferences.getBoolean("planned_workout_minimized", false)) }
    val suggestion = state.primarySuggestion
    LaunchedEffect(initialWorkoutId, suggestion?.id, suggestion?.plannedWorkoutId) {
        if (initialWorkoutId != null && (suggestion?.id == initialWorkoutId || suggestion?.plannedWorkoutId == initialWorkoutId)) showsDetail = true
    }

    Box(modifier.fillMaxSize()) {
        PlainstrideRouteMap(
            points = emptyList(),
            modifier = Modifier.fillMaxSize(),
            showUserLocation = locationGranted,
            preciseLocationGranted = locationGranted,
        )
        Column(
            Modifier.fillMaxSize().padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.SpaceBetween,
        ) {
            Column(
                Modifier.fillMaxWidth().weight(1f).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                when {
                    state.suggestion is CachedResource.Loading && state.refreshError == null -> TodaySkeleton()
                    suggestion != null -> WorkoutRecommendationCard(
                        suggestion = suggestion,
                        stale = state.isStale,
                        updatedAtEpochMs = state.suggestionUpdatedAtEpochMs,
                        completedToday = state.completedToday,
                        weather = weather,
                        minimized = cardMinimized,
                        onToggleMinimized = {
                            cardMinimized = !cardMinimized
                            displayPreferences.edit().putBoolean("planned_workout_minimized", cardMinimized).apply()
                            onCardDisplayChanged(cardMinimized)
                        },
                        onOpen = { showsDetail = true },
                        onChange = { showsChange = true },
                    )
                    state.hasNoCachedSuggestion -> NoSuggestionCard(
                        noPlan = (state.planning as? CachedResource.Available)?.value?.plan == null,
                        onStartFreestyle = onStartFreestyle,
                        onSetUpPlan = onSetUpPlan,
                        onRefresh = onRefresh,
                    )
                }
                guidanceContent()
                if (state.refreshing) Surface(shape = RoundedCornerShape(20.dp), tonalElevation = 3.dp) {
                    Row(Modifier.padding(horizontal = 14.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                        Spacer(Modifier.width(8.dp))
                        Text(stringResource(R.string.today_updating), style = MaterialTheme.typography.labelLarge)
                    }
                }
            }
            LaunchDock(
                suggestion = suggestion,
                activeSession = state.activeSession,
                completedToday = state.completedToday,
                onStart = { suggestion?.let { onStart(it, "today_planned") } ?: onStartFreestyle() },
                onReturnToSession = onReturnToSession,
                onOpenDetails = { showsDetail = true },
            )
        }
    }

    if (showsDetail && suggestion != null) WorkoutDetailSheet(
        suggestion,
        onDismiss = { showsDetail = false },
        onStart = { showsDetail = false; onStart(suggestion, "today_detail") },
    )
    if (showsChange && suggestion != null) ChangeWorkoutSheet(
        original = suggestion,
        pending = state.pendingAdjustment,
        busy = state.mutationInFlight,
        onDismiss = { showsChange = false },
        onSubmit = onSubmitConstraint,
        onDecision = { id, accept -> onDecideAdjustment(id, accept); showsChange = false },
    )
}

@Composable
private fun WorkoutRecommendationCard(
    suggestion: ActivitySuggestion,
    stale: Boolean,
    updatedAtEpochMs: Long?,
    completedToday: Boolean,
    weather: WeatherGuidance?,
    minimized: Boolean,
    onToggleMinimized: () -> Unit,
    onOpen: () -> Unit,
    onChange: () -> Unit,
) {
    val uriHandler = LocalUriHandler.current
    val toggleDescription = stringResource(if (minimized) R.string.today_expand_card else R.string.today_collapse_card)
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface.copy(alpha = .96f))) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f).clickable(role = Role.Button, onClick = onOpen)) {
                    Text(stringResource(if (completedToday) R.string.today_up_next else R.string.today_workout), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                    Text(suggestion.title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
                Text(stringResource(R.string.today_minutes, suggestion.durationMinutes), style = MaterialTheme.typography.titleSmall)
                TextButton(
                    onClick = onToggleMinimized,
                    modifier = Modifier.size(48.dp).semantics {
                        contentDescription = toggleDescription
                    },
                ) {
                    Text(if (minimized) "⌄" else "⌃", style = MaterialTheme.typography.titleLarge)
                }
            }
            if (!minimized) {
                weather?.let {
                    Text("${it.headline} · ${it.detail}", style = MaterialTheme.typography.bodySmall, color = if (it.unsafe) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(it.attribution, modifier = Modifier.clickable(role = Role.Button) { uriHandler.openUri(it.attributionUrl) }, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
                }
                PhasePreview(suggestion.steps)
                if (stale) Text(
                    stringResource(R.string.today_cached_at, updatedAtEpochMs?.let { DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(it)) }.orEmpty()),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.tertiary,
                )
                HorizontalDivider()
                Row(Modifier.fillMaxWidth()) {
                    TextButton(onClick = onOpen, modifier = Modifier.weight(1f).heightIn(min = 48.dp)) { Text(stringResource(R.string.today_details)) }
                    TextButton(onClick = onChange, modifier = Modifier.weight(1f).heightIn(min = 48.dp)) { Text(stringResource(R.string.today_change_workout)) }
                }
            }
        }
    }
}

@Composable
private fun PhasePreview(steps: List<String>) {
    if (steps.isEmpty()) return
    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        steps.forEachIndexed { index, step ->
            Box(
                Modifier.width(92.dp).height(38.dp).clip(RoundedCornerShape(9.dp))
                    .background(if (index % 2 == 0) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.secondaryContainer)
                    .semantics { contentDescription = step },
                contentAlignment = Alignment.Center,
            ) { Text(step, Modifier.padding(horizontal = 6.dp), style = MaterialTheme.typography.labelSmall, maxLines = 2, overflow = TextOverflow.Ellipsis) }
        }
    }
}

@Composable
private fun LaunchDock(
    suggestion: ActivitySuggestion?,
    activeSession: Boolean,
    completedToday: Boolean,
    onStart: () -> Unit,
    onReturnToSession: () -> Unit,
    onOpenDetails: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Card(modifier, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface.copy(alpha = .97f))) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            when {
                activeSession -> Button(onClick = onReturnToSession, modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp)) { Text(stringResource(R.string.today_return_run)) }
                completedToday -> {
                    Text(stringResource(R.string.today_completed_reflection), style = MaterialTheme.typography.titleMedium)
                    OutlinedButton(onClick = onOpenDetails, enabled = suggestion != null, modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp)) { Text(stringResource(R.string.today_view_next)) }
                }
                else -> Button(onClick = onStart, modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp)) {
                    Text(if (suggestion == null) stringResource(R.string.today_freestyle) else stringResource(R.string.today_start_workout, suggestion.title))
                }
            }
        }
    }
}

@Composable
private fun NoSuggestionCard(noPlan: Boolean, onStartFreestyle: () -> Unit, onSetUpPlan: () -> Unit, onRefresh: () -> Unit) {
    OutlinedCard {
        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(stringResource(if (noPlan) R.string.today_no_plan else R.string.today_offline_title), style = MaterialTheme.typography.titleLarge)
            Text(stringResource(if (noPlan) R.string.today_no_plan_body else R.string.today_offline_body), color = MaterialTheme.colorScheme.onSurfaceVariant)
            Button(onClick = onStartFreestyle, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text(stringResource(R.string.today_freestyle)) }
            if (noPlan) TextButton(onClick = onSetUpPlan) { Text(stringResource(R.string.today_set_up_plan)) }
            else TextButton(onClick = onRefresh) { Text(stringResource(R.string.today_retry)) }
        }
    }
}

@Composable
private fun TodaySkeleton() {
    Card {
        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            repeat(3) { index -> Spacer(Modifier.fillMaxWidth(if (index == 1) .72f else 1f).height(if (index == 0) 24.dp else 18.dp).clip(RoundedCornerShape(8.dp)).background(MaterialTheme.colorScheme.surfaceVariant)) }
        }
    }
}

@Composable
@OptIn(ExperimentalMaterial3Api::class)
private fun WorkoutDetailSheet(suggestion: ActivitySuggestion, onDismiss: () -> Unit, onStart: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text(suggestion.title, Modifier.semantics { heading() }, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            Text(stringResource(R.string.today_detail_summary, suggestion.durationMinutes, suggestion.effortLabel), style = MaterialTheme.typography.titleMedium)
            Text(stringResource(R.string.today_phases), style = MaterialTheme.typography.titleMedium)
            suggestion.steps.forEachIndexed { index, step ->
                Row(verticalAlignment = Alignment.Top) {
                    Text("${index + 1}", Modifier.size(32.dp).clip(RoundedCornerShape(16.dp)).background(MaterialTheme.colorScheme.primaryContainer).padding(7.dp), style = MaterialTheme.typography.labelMedium)
                    Spacer(Modifier.width(12.dp)); Text(step, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
                }
            }
            HorizontalDivider()
            Text(stringResource(R.string.today_purpose), style = MaterialTheme.typography.titleMedium)
            Text(suggestion.why, style = MaterialTheme.typography.bodyLarge)
            Button(onClick = onStart, Modifier.fillMaxWidth().heightIn(min = 52.dp)) { Text(suggestion.startLabel) }
            Spacer(Modifier.height(20.dp))
        }
    }
}

@Composable
@OptIn(ExperimentalMaterial3Api::class)
private fun ChangeWorkoutSheet(
    original: ActivitySuggestion,
    pending: AdjustmentProposal?,
    busy: Boolean,
    onDismiss: () -> Unit,
    onSubmit: (TodayConstraint, String, String?) -> Unit,
    onDecision: (String, Boolean) -> Unit,
) {
    var selected by rememberSaveable { mutableStateOf<TodayConstraint?>(null) }
    var note by rememberSaveable { mutableStateOf("") }
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(24.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text(stringResource(R.string.today_change_title), Modifier.semantics { heading() }, style = MaterialTheme.typography.headlineSmall)
            Text(stringResource(R.string.today_change_body), color = MaterialTheme.colorScheme.onSurfaceVariant)
            TodayConstraint.entries.forEach { choice ->
                OutlinedButton(
                    onClick = { selected = choice },
                    modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                ) { Text(stringResource(choice.labelResource())) }
            }
            OutlinedTextField(note, { note = it.take(160) }, Modifier.fillMaxWidth(), label = { Text(stringResource(R.string.today_optional_note)) }, maxLines = 3)
            if (pending == null) {
                Button(onClick = { selected?.let { onSubmit(it, original.plannedWorkoutId ?: original.id, note.ifBlank { null }) } }, enabled = selected != null && !busy, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.today_show_alternative))
                }
                TextButton(onClick = onDismiss, Modifier.fillMaxWidth()) { Text(stringResource(R.string.today_keep_original)) }
            } else {
                HorizontalDivider()
                Text(stringResource(R.string.today_recommendation), style = MaterialTheme.typography.titleMedium)
                Text(pending.explanation)
                pending.changes.forEach { Text(stringResource(R.string.today_change_comparison, it.beforeTitle, it.afterTitle), style = MaterialTheme.typography.bodyMedium) }
                Button(onClick = { onDecision(pending.id, true) }, enabled = !busy, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.today_apply_change)) }
                OutlinedButton(onClick = { onDecision(pending.id, false) }, enabled = !busy, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.today_keep_original)) }
            }
            Spacer(Modifier.height(20.dp))
        }
    }
}

private fun TodayConstraint.labelResource() = when (this) {
    TodayConstraint.LowEnergy -> R.string.today_low_energy
    TodayConstraint.Soreness -> R.string.today_soreness
    TodayConstraint.LimitedTime -> R.string.today_limited_time
    TodayConstraint.FeelingGood -> R.string.today_feeling_good
}
