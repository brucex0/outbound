package com.plainstride.outbound.feature.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import com.plainstride.outbound.core.model.PlannedWorkout

@Composable
fun OnboardingRoute(
    onComplete: () -> Unit,
    onMessage: (OnboardingEffect) -> Unit,
    source: PlanBuilderSource = PlanBuilderSource.Onboarding,
    usesMetric: Boolean = true,
    forceReplay: Boolean = false,
    viewModel: OnboardingViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    LaunchedEffect(viewModel) {
        viewModel.effects.collect {
            if (it == OnboardingEffect.Completed || it == OnboardingEffect.FailedOpen) onComplete() else onMessage(it)
        }
    }
    LaunchedEffect(viewModel, source, usesMetric, forceReplay) {
        if (forceReplay) viewModel.restartForDebug(usesMetric) else viewModel.start(source, usesMetric)
    }
    OnboardingScreen(
        state = state,
        update = viewModel::update,
        back = viewModel::back,
        next = viewModel::next,
        finishLater = viewModel::finishLater,
        exploreFirst = viewModel::exploreFirst,
        skipProfile = viewModel::skipTrainingProfile,
        importHealth = viewModel::importHealth,
    )
}

@Composable
private fun OnboardingScreen(
    state: OnboardingUiState,
    update: ((OnboardingDraft) -> OnboardingDraft) -> Unit,
    back: () -> Unit,
    next: () -> Unit,
    finishLater: () -> Unit,
    exploreFirst: () -> Unit,
    skipProfile: () -> Unit,
    importHealth: () -> Unit,
) {
    val draft = state.draft
    if (state.loading || draft == null) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        return
    }

    val progressSteps = if (state.firstUse) FIRST_USE_STEPS else BUILDER_STEPS
    val progressIndex = progressSteps.indexOf(draft.step).let { if (it < 0) progressSteps.lastIndex else it }
    val progress = (progressIndex + 1).toFloat() / progressSteps.size
    val canGoBack = draft.step in setOf(
        OnboardingStep.Objective, OnboardingStep.Activities, OnboardingStep.Baseline,
        OnboardingStep.Week, OnboardingStep.Profile, OnboardingStep.Review,
    ) && (draft.step != OnboardingStep.Objective || state.firstUse)
    val canFinishLater = draft.step in setOf(
        OnboardingStep.Objective, OnboardingStep.Activities, OnboardingStep.Baseline,
        OnboardingStep.Week, OnboardingStep.Profile, OnboardingStep.Review,
    )

    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).safeDrawingPadding().imePadding()) {
        LinearProgressIndicator(
            progress = { progress },
            modifier = Modifier.fillMaxWidth().semantics {
                progressBarRangeInfo = androidx.compose.ui.semantics.ProgressBarRangeInfo(progress, 0f..1f)
            },
        )
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (canGoBack) TextButton(onClick = back) { Text(stringResource(R.string.onboarding_back)) }
            else Spacer(Modifier.width(72.dp))
            Text(
                stringResource(R.string.plan_builder_title),
                style = MaterialTheme.typography.titleMedium,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                modifier = Modifier.weight(1f),
            )
            if (canFinishLater) TextButton(onClick = finishLater) { Text(stringResource(R.string.plan_builder_finish_later)) }
            else Spacer(Modifier.width(72.dp))
        }

        if (draft.step == OnboardingStep.Creating) {
            CreatingStep(Modifier.weight(1f))
            return@Column
        }

        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 24.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            when (draft.step) {
                OnboardingStep.Identity -> IdentityStep(draft, state.account?.verifiedEmail.isNullOrBlank(), update)
                OnboardingStep.Welcome -> WelcomeStep()
                OnboardingStep.Objective -> ObjectiveStep(draft, update)
                OnboardingStep.Activities -> ActivitiesStep(draft, update)
                OnboardingStep.Baseline -> BaselineStep(draft, update)
                OnboardingStep.Week -> WeekStep(draft, update)
                OnboardingStep.Profile -> ProfileStep(
                    draft, state.healthImporting, state.healthConnected, state.recentHealthActivityCount, update, importHealth,
                )
                OnboardingStep.Review -> ReviewStep(draft)
                OnboardingStep.Result -> ResultStep(draft, state.plan, update)
                OnboardingStep.Creating -> Unit
            }
        }

        Column(Modifier.padding(horizontal = 24.dp, vertical = 16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Button(
                onClick = next,
                enabled = !state.saving && !state.healthImporting && draft.canContinue(state.account?.verifiedEmail.isNullOrBlank()),
                modifier = Modifier.fillMaxWidth().height(52.dp),
            ) {
                if (state.saving) CircularProgressIndicator(Modifier.height(24.dp), strokeWidth = 2.dp)
                else Text(stringResource(primaryActionLabel(draft.step)))
            }
            if (state.firstUse && draft.step == OnboardingStep.Welcome) {
                TextButton(onClick = exploreFirst, enabled = !state.saving, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.plan_builder_explore))
                }
            } else if (draft.step == OnboardingStep.Profile) {
                TextButton(onClick = skipProfile, enabled = !state.saving && !state.healthImporting, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.onboarding_skip))
                }
            }
        }
    }
}

@Composable
private fun WelcomeStep() {
    Heading(R.string.plan_builder_welcome_title, R.string.plan_builder_welcome_subtitle)
    PromiseCard(R.string.plan_builder_welcome_today)
    PromiseCard(R.string.plan_builder_welcome_week)
    PromiseCard(R.string.plan_builder_welcome_adapts)
}

@Composable
private fun IdentityStep(
    draft: OnboardingDraft,
    needsEmail: Boolean,
    update: ((OnboardingDraft) -> OnboardingDraft) -> Unit,
) {
    Heading(R.string.onboarding_identity_title, R.string.onboarding_identity_subtitle)
    OutlinedTextField(
        draft.displayName, { value -> update { it.copy(displayName = value) } }, Modifier.fillMaxWidth(),
        label = { Text(stringResource(R.string.onboarding_display_name)) }, singleLine = true,
    )
    OutlinedTextField(
        draft.username, { value -> update { it.copy(username = value) } }, Modifier.fillMaxWidth(),
        label = { Text(stringResource(R.string.onboarding_username)) }, singleLine = true,
    )
    if (needsEmail) OutlinedTextField(
        draft.email, { value -> update { it.copy(email = value) } }, Modifier.fillMaxWidth(),
        label = { Text(stringResource(R.string.onboarding_email)) },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email), singleLine = true,
    )
}

@Composable
private fun ObjectiveStep(draft: OnboardingDraft, update: ((OnboardingDraft) -> OnboardingDraft) -> Unit) {
    Heading(R.string.plan_builder_objective_title, R.string.plan_builder_objective_subtitle)
    ChoiceGrid(PlanObjective.entries, { stringResource(it.label) }, { draft.objective == it }) { selected ->
        update { it.copy(objective = selected) }
    }
    if (draft.objective == PlanObjective.Other) {
        OutlinedTextField(
            draft.otherObjective, { value -> update { it.copy(otherObjective = value) } }, Modifier.fillMaxWidth(),
            label = { Text(stringResource(R.string.plan_builder_objective_other_prompt)) }, minLines = 2,
        )
    }
    if (draft.objective == PlanObjective.EventPreparation) EventFields(draft, update)
}

@Composable
private fun ActivitiesStep(draft: OnboardingDraft, update: ((OnboardingDraft) -> OnboardingDraft) -> Unit) {
    Heading(R.string.plan_builder_activities_title, R.string.plan_builder_activities_subtitle)
    ChoiceGrid(PlanActivity.entries, { stringResource(it.label) }, { draft.activities.contains(it) }) { activity ->
        update { current ->
            val selected = current.activities.toMutableList()
            if (activity in selected && selected.size > 1) selected.remove(activity) else if (activity !in selected) selected.add(activity)
            current.copy(activities = selected)
        }
    }
}

@Composable
private fun BaselineStep(draft: OnboardingDraft, update: ((OnboardingDraft) -> OnboardingDraft) -> Unit) {
    Heading(R.string.plan_builder_baseline_title, R.string.plan_builder_baseline_subtitle)
    PlanBaselineContext.entries.forEach { value ->
        SelectionRow(stringResource(value.label), draft.baselineContext == value) { update { it.copy(baselineContext = value) } }
    }
    NumberControl(R.string.plan_builder_baseline_frequency, draft.recentSessionsPerWeek, 0, 6, 1) { value ->
        update { it.copy(recentSessionsPerWeek = value) }
    }
    NumberControl(R.string.plan_builder_baseline_duration, draft.comfortableMinutes, 10, 120, 5) { value ->
        update { it.copy(comfortableMinutes = value) }
    }
}

@Composable
private fun WeekStep(draft: OnboardingDraft, update: ((OnboardingDraft) -> OnboardingDraft) -> Unit) {
    Heading(R.string.plan_builder_week_title, R.string.plan_builder_week_subtitle)
    NumberControl(R.string.plan_builder_week_sessions, draft.sessionsPerWeek, 1, 6, 1) { value ->
        update { it.copy(sessionsPerWeek = value, preferredDays = it.preferredDays.take(value)) }
    }
    NumberControl(R.string.plan_builder_week_duration, draft.availableMinutes, 10, 120, 5) { value ->
        update { it.copy(availableMinutes = value) }
    }
    Text(stringResource(R.string.plan_builder_week_preferred_days), style = MaterialTheme.typography.titleSmall)
    WEEKDAYS.chunked(4).forEach { row ->
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            row.forEach { day ->
                FilterChip(
                    selected = day.code in draft.preferredDays,
                    onClick = {
                        update { current ->
                            val days = current.preferredDays.toMutableList()
                            if (day.code in days) days.remove(day.code)
                            else if (days.size < current.sessionsPerWeek) days.add(day.code)
                            current.copy(preferredDays = days)
                        }
                    },
                    label = { Text(stringResource(day.label)) },
                    modifier = Modifier.weight(1f),
                )
            }
            repeat(4 - row.size) { Spacer(Modifier.weight(1f)) }
        }
    }
    OutlinedTextField(
        draft.constraints, { value -> update { it.copy(constraints = value) } }, Modifier.fillMaxWidth(),
        label = { Text(stringResource(R.string.plan_builder_week_constraints)) }, minLines = 2,
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ProfileStep(
    draft: OnboardingDraft,
    importing: Boolean,
    connected: Boolean,
    recentActivityCount: Int,
    update: ((OnboardingDraft) -> OnboardingDraft) -> Unit,
    importHealth: () -> Unit,
) {
    Heading(R.string.onboarding_profile_title, R.string.onboarding_profile_subtitle)
    OutlinedButton(onClick = importHealth, enabled = !importing && !connected, modifier = Modifier.fillMaxWidth().height(52.dp)) {
        Text(
            if (connected) stringResource(R.string.plan_builder_health_connected, recentActivityCount)
            else stringResource(if (importing) R.string.onboarding_health_connecting else R.string.onboarding_health_connect),
        )
    }
    Text(stringResource(R.string.onboarding_profile_manual), style = MaterialTheme.typography.labelMedium)
    BirthdayField(draft.birthDate) { value -> update { it.copy(birthDate = value) } }
    val metric = draft.measurementSystem == MeasurementSystem.Metric
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        OutlinedTextField(
            draft.height, { value -> update { it.copy(height = value) } }, Modifier.weight(1f),
            label = { Text(stringResource(if (metric) R.string.onboarding_height_cm else R.string.onboarding_height_in)) },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), singleLine = true,
        )
        OutlinedTextField(
            draft.weight, { value -> update { it.copy(weight = value) } }, Modifier.weight(1f),
            label = { Text(stringResource(if (metric) R.string.onboarding_weight_kg else R.string.onboarding_weight_lb)) },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), singleLine = true,
        )
    }
    SexAtBirth.entries.forEach { value ->
        SelectionRow(stringResource(value.label), draft.sexAtBirth == value) { update { it.copy(sexAtBirth = value) } }
    }
    if (!draft.measurementsValid()) {
        Text(
            stringResource(if (metric) R.string.onboarding_measurement_error else R.string.onboarding_profile_measurement_error_imperial),
            color = MaterialTheme.colorScheme.error,
        )
    }
    Text(stringResource(R.string.onboarding_profile_private), color = MaterialTheme.colorScheme.onSurfaceVariant)
}

@Composable
private fun ReviewStep(draft: OnboardingDraft) {
    val resources = LocalContext.current.resources
    Heading(R.string.plan_builder_review_title, R.string.plan_builder_review_subtitle)
    SummaryCard(R.string.plan_builder_review_objective, stringResource(draft.objective.label))
    SummaryCard(R.string.plan_builder_review_activities, draft.activities.joinToString(" · ") { resources.getString(it.label) })
    SummaryCard(
        R.string.plan_builder_review_week,
        stringResource(R.string.plan_builder_review_week_value, draft.sessionsPerWeek, draft.availableMinutes),
    )
}

@Composable
private fun CreatingStep(modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        CircularProgressIndicator()
        Text(
            stringResource(R.string.plan_builder_creating),
            style = MaterialTheme.typography.titleMedium,
            modifier = Modifier.padding(top = 20.dp, start = 24.dp, end = 24.dp),
        )
    }
}

@Composable
private fun ResultStep(
    draft: OnboardingDraft,
    plan: com.plainstride.outbound.core.model.PlanningState?,
    update: ((OnboardingDraft) -> OnboardingDraft) -> Unit,
) {
    val resources = LocalContext.current.resources
    Heading(R.string.plan_builder_result_plan, null)
    Text(
        plan?.currentVersion?.summary ?: stringResource(R.string.plan_builder_result_direction),
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    SummaryCard(R.string.plan_builder_review_objective, stringResource(draft.objective.label))
    SummaryCard(R.string.plan_builder_review_activities, draft.activities.joinToString(" · ") { resources.getString(it.label) })
    Text(stringResource(R.string.plan_builder_result_week), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
    val workouts = plan?.upcoming.orEmpty().take(7)
    if (workouts.isNotEmpty()) {
        SummaryCard(
            R.string.plan_builder_result_total_time,
            stringResource(R.string.plan_builder_result_total_time_value, workouts.sumOf { it.durationSeconds } / 60),
        )
        workouts.forEach { WorkoutRow(it) }
    }
    TextButton(onClick = {
        update { it.copy(sessionsPerWeek = (it.sessionsPerWeek - 1).coerceAtLeast(1), availableMinutes = (it.availableMinutes - 5).coerceAtLeast(10), step = OnboardingStep.Week) }
    }) { Text(stringResource(R.string.plan_builder_result_easier)) }
    TextButton(onClick = { update { it.copy(step = OnboardingStep.Week) } }) { Text(stringResource(R.string.plan_builder_result_change_days)) }
    TextButton(onClick = { update { it.copy(step = OnboardingStep.Activities) } }) { Text(stringResource(R.string.plan_builder_result_change_mix)) }
}

@Composable
private fun WorkoutRow(workout: PlannedWorkout) {
    Card {
        Column(Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            val day = runCatching { LocalDate.parse(workout.scheduledDate).format(DateTimeFormatter.ofPattern("EEE", Locale.getDefault())) }
                .getOrDefault(workout.scheduledDate)
            Text("$day · ${workout.title}", style = MaterialTheme.typography.titleSmall)
            Text(
                stringResource(R.string.plan_builder_result_total_time_value, workout.durationSeconds / 60),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun EventFields(draft: OnboardingDraft, update: ((OnboardingDraft) -> OnboardingDraft) -> Unit) {
    Text(stringResource(R.string.plan_builder_event_distance), style = MaterialTheme.typography.titleSmall)
    listOf(
        5_000.0 to "5K",
        10_000.0 to "10K",
        21_097.5 to stringResource(R.string.plan_builder_event_half),
        42_195.0 to stringResource(R.string.plan_builder_event_marathon),
    ).forEach { (distance, label) ->
        SelectionRow(label, draft.eventDistanceMeters == distance) { update { it.copy(eventDistanceMeters = distance) } }
    }
    EventDateField(draft.eventDate ?: defaultEventDate()) { value -> update { it.copy(eventDate = value) } }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun EventDateField(value: String, onChange: (String) -> Unit) {
    val selectedMillis = LocalDate.parse(value).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
    val picker = rememberDatePickerState(initialSelectedDateMillis = selectedMillis)
    val showDialog = remember { mutableStateOf(false) }
    OutlinedButton(onClick = { showDialog.value = true }, modifier = Modifier.fillMaxWidth()) {
        val label = LocalDate.parse(value).format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM))
        Text("${stringResource(R.string.plan_builder_event_date)} · $label")
    }
    if (showDialog.value) DatePickerDialog(
        onDismissRequest = { showDialog.value = false },
        confirmButton = {
            TextButton(onClick = {
                picker.selectedDateMillis?.let { onChange(Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate().toString()) }
                showDialog.value = false
            }) { Text(stringResource(R.string.onboarding_date_confirm)) }
        },
        dismissButton = { TextButton(onClick = { showDialog.value = false }) { Text(stringResource(R.string.onboarding_date_clear)) } },
    ) { DatePicker(picker) }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun BirthdayField(value: String, onChange: (String) -> Unit) {
    val selectedMillis = runCatching { LocalDate.parse(value).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli() }.getOrNull()
    val picker = rememberDatePickerState(initialSelectedDateMillis = selectedMillis)
    val showDialog = remember { mutableStateOf(false) }
    OutlinedButton(onClick = { showDialog.value = true }, modifier = Modifier.fillMaxWidth()) {
        val label = runCatching { LocalDate.parse(value).format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)) }.getOrNull()
        Text(label ?: stringResource(R.string.onboarding_add_birthday))
    }
    if (showDialog.value) DatePickerDialog(
        onDismissRequest = { showDialog.value = false },
        confirmButton = {
            TextButton(onClick = {
                picker.selectedDateMillis?.let { onChange(Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate().toString()) }
                showDialog.value = false
            }) { Text(stringResource(R.string.onboarding_date_confirm)) }
        },
        dismissButton = { TextButton(onClick = { showDialog.value = false }) { Text(stringResource(R.string.onboarding_date_clear)) } },
    ) { DatePicker(picker) }
}

@Composable
private fun Heading(title: Int, subtitle: Int?) {
    Text(stringResource(title), style = MaterialTheme.typography.headlineSmall, modifier = Modifier.semantics { heading() })
    subtitle?.let { Text(stringResource(it), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant) }
}

@Composable
private fun PromiseCard(label: Int) = Card {
    Text(stringResource(label), Modifier.fillMaxWidth().padding(16.dp), style = MaterialTheme.typography.titleMedium)
}

@Composable
private fun <T> ChoiceGrid(
    choices: List<T>,
    label: @Composable (T) -> String,
    selected: (T) -> Boolean,
    onSelect: (T) -> Unit,
) {
    choices.chunked(2).forEach { rowChoices ->
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            rowChoices.forEach { choice ->
                ChoiceTile(label(choice), selected(choice), { onSelect(choice) }, Modifier.weight(1f))
            }
            if (rowChoices.size == 1) Spacer(Modifier.weight(1f))
        }
    }
}

@Composable
private fun ChoiceTile(label: String, selected: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val container = if (selected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceVariant
    Row(
        modifier.height(76.dp).background(container, RoundedCornerShape(14.dp)).clickable(onClick = onClick).padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, Modifier.weight(1f), style = MaterialTheme.typography.labelLarge)
        Checkbox(checked = selected, onCheckedChange = null)
    }
}

@Composable
private fun SelectionRow(label: String, selected: Boolean, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().height(52.dp).selectable(selected, onClick = onClick).padding(horizontal = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RadioButton(selected, onClick = null)
        Text(label, Modifier.padding(start = 8.dp), style = MaterialTheme.typography.bodyLarge)
    }
}

@Composable
private fun NumberControl(label: Int, value: Int, min: Int, max: Int, step: Int, onChange: (Int) -> Unit) {
    Card {
        Row(Modifier.fillMaxWidth().padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(label, value), Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
            TextButton(onClick = { onChange((value - step).coerceAtLeast(min)) }, enabled = value > min) { Text("−") }
            TextButton(onClick = { onChange((value + step).coerceAtMost(max)) }, enabled = value < max) { Text("+") }
        }
    }
}

@Composable
private fun SummaryCard(label: Int, value: String) = Card {
    Column(Modifier.fillMaxWidth().padding(16.dp)) {
        Text(stringResource(label), style = MaterialTheme.typography.labelMedium)
        Text(value, style = MaterialTheme.typography.titleMedium)
    }
}

private fun primaryActionLabel(step: OnboardingStep) = when (step) {
    OnboardingStep.Welcome, OnboardingStep.Review -> R.string.plan_builder_create
    OnboardingStep.Result -> R.string.plan_builder_go_today
    OnboardingStep.Identity -> R.string.onboarding_continue
    else -> R.string.onboarding_continue
}

private fun OnboardingDraft.canContinue(needsEmail: Boolean): Boolean = when (step) {
    OnboardingStep.Identity -> displayName.isNotBlank() && username.trim().matches(Regex("[A-Za-z0-9_-]{3,30}")) &&
        (!needsEmail || email.matches(Regex("[^@\\s]+@[^@\\s]+\\.[^@\\s]+")))
    OnboardingStep.Objective -> objective != PlanObjective.Other || otherObjective.isNotBlank()
    OnboardingStep.Activities -> activities.isNotEmpty()
    OnboardingStep.Profile -> measurementsValid()
    OnboardingStep.Creating -> false
    else -> true
}

private fun OnboardingDraft.measurementsValid(): Boolean {
    val heightValue = height.trim().replace(',', '.').toDoubleOrNull()
    val weightValue = weight.trim().replace(',', '.').toDoubleOrNull()
    val metric = measurementSystem == MeasurementSystem.Metric
    return (height.isBlank() || heightValue != null && heightValue in if (metric) 90.0..250.0 else 35.0..98.5) &&
        (weight.isBlank() || weightValue != null && weightValue in if (metric) 25.0..350.0 else 55.0..772.0)
}

private data class Weekday(val code: String, val label: Int)
private val WEEKDAYS = listOf(
    Weekday("mon", R.string.onboarding_weekday_mon), Weekday("tue", R.string.onboarding_weekday_tue),
    Weekday("wed", R.string.onboarding_weekday_wed), Weekday("thu", R.string.onboarding_weekday_thu),
    Weekday("fri", R.string.onboarding_weekday_fri), Weekday("sat", R.string.onboarding_weekday_sat),
    Weekday("sun", R.string.onboarding_weekday_sun),
)
private val FIRST_USE_STEPS = listOf(
    OnboardingStep.Welcome, OnboardingStep.Objective, OnboardingStep.Activities, OnboardingStep.Baseline,
    OnboardingStep.Week, OnboardingStep.Profile, OnboardingStep.Review,
)
private val BUILDER_STEPS = FIRST_USE_STEPS.drop(1)
