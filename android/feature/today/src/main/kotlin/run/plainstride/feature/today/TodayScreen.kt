package run.plainstride.feature.today

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
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
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
import run.plainstride.core.model.ActivitySuggestion
import run.plainstride.core.model.AdjustmentProposal

interface TodayWeatherPolicy {
    /** Must return guidance only; missing permission/provider never changes the workout. */
    suspend fun guidance(): WeatherGuidance?
}

data class WeatherGuidance(val headline: String, val detail: String)

object NoOpTodayWeatherPolicy : TodayWeatherPolicy {
    override suspend fun guidance(): WeatherGuidance? = null
}

@Composable
fun TodayRoute(
    viewModel: TodayViewModel,
    activeSession: Boolean,
    completedToday: Boolean,
    onStartWorkout: (WorkoutLaunchIntent) -> Unit,
    onStartFreestyle: () -> Unit,
    onReturnToSession: () -> Unit,
    onSetUpPlan: () -> Unit,
    onMessage: suspend (TodayMessage) -> Unit,
    weatherPolicy: TodayWeatherPolicy = NoOpTodayWeatherPolicy,
    modifier: Modifier = Modifier,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    var weather by remember { mutableStateOf<WeatherGuidance?>(null) }
    LaunchedEffect(activeSession, completedToday) { viewModel.updateSessionState(activeSession, completedToday) }
    LaunchedEffect(weatherPolicy) { weather = weatherPolicy.guidance() }
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
        onSetUpPlan = onSetUpPlan,
        onSubmitConstraint = viewModel::submitConstraint,
        onDecideAdjustment = viewModel::decideAdjustment,
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
    modifier: Modifier = Modifier,
) {
    var showsDetail by rememberSaveable { mutableStateOf(false) }
    var showsChange by rememberSaveable { mutableStateOf(false) }
    val suggestion = state.primarySuggestion

    Column(
        modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(stringResource(R.string.today_quote), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        Text(stringResource(R.string.today_companion_line), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)

        when {
            state.suggestion is CachedResource.Loading && state.refreshError == null -> TodaySkeleton()
            suggestion != null -> WorkoutRecommendationCard(
                suggestion = suggestion,
                stale = state.isStale,
                updatedAtEpochMs = state.suggestionUpdatedAtEpochMs,
                completedToday = state.completedToday,
                weather = weather,
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

        if (state.refreshing) Row(verticalAlignment = Alignment.CenterVertically) {
            CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
            Spacer(Modifier.width(8.dp))
            Text(stringResource(R.string.today_updating), style = MaterialTheme.typography.labelLarge)
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
    onOpen: () -> Unit,
    onChange: () -> Unit,
) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerHigh)) {
        Column(Modifier.clickable(role = Role.Button, onClick = onOpen).padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(stringResource(if (completedToday) R.string.today_up_next else R.string.today_workout), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                    Text(suggestion.title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
                Text(stringResource(R.string.today_minutes, suggestion.durationMinutes), style = MaterialTheme.typography.titleSmall)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TextButton(onClick = onChange, modifier = Modifier.heightIn(min = 48.dp)) { Text(stringResource(R.string.today_change)) }
                TextButton(onClick = onOpen, modifier = Modifier.heightIn(min = 48.dp)) { Text(stringResource(R.string.today_why)) }
            }
            PhasePreview(suggestion.steps)
            weather?.let { Text("${it.headline} · ${it.detail}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            if (stale) Text(
                stringResource(
                    R.string.today_cached_at,
                    updatedAtEpochMs?.let { DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(it)) }.orEmpty(),
                ),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.tertiary,
            )
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
) {
    OutlinedCard {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(stringResource(R.string.today_launch_dock), style = MaterialTheme.typography.labelLarge)
            if (suggestion != null) Text(suggestion.title, style = MaterialTheme.typography.bodyMedium)
            when {
                activeSession -> Button(onClick = onReturnToSession, modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp)) { Text(stringResource(R.string.today_return_run)) }
                completedToday -> {
                    Text(stringResource(R.string.today_completed_reflection), style = MaterialTheme.typography.titleMedium)
                    OutlinedButton(onClick = onOpenDetails, enabled = suggestion != null, modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp)) { Text(stringResource(R.string.today_view_next)) }
                }
                else -> Button(onClick = onStart, modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp)) { Text(stringResource(R.string.today_start)) }
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
