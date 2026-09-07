package run.plainstride.feature.onboarding

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
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
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
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

@Composable
fun OnboardingRoute(
    onComplete: () -> Unit,
    onMessage: (OnboardingEffect) -> Unit,
    viewModel: OnboardingViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    LaunchedEffect(viewModel) {
        viewModel.effects.collect {
            if (it == OnboardingEffect.Completed) onComplete() else onMessage(it)
        }
    }
    OnboardingScreen(state, viewModel::update, viewModel::back, viewModel::next,
        viewModel::skipTrainingProfile, viewModel::importHealth)
}

@Composable
private fun OnboardingScreen(
    state: OnboardingUiState,
    update: ((OnboardingDraft) -> OnboardingDraft) -> Unit,
    back: () -> Unit,
    next: () -> Unit,
    skipProfile: () -> Unit,
    importHealth: () -> Unit,
) {
    val draft = state.draft
    if (state.loading || draft == null) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        return
    }
    val visibleSteps = remember(state.account?.needsIdentity) {
        if (state.account?.needsIdentity == true) OnboardingStep.entries else OnboardingStep.entries.drop(1)
    }
    val progress = (visibleSteps.indexOf(draft.step).coerceAtLeast(0) + 1).toFloat() / visibleSteps.size
    Column(Modifier.fillMaxSize().safeDrawingPadding().imePadding()) {
        LinearProgressIndicator(
            progress = { progress },
            modifier = Modifier.fillMaxWidth().semantics { progressBarRangeInfo = androidx.compose.ui.semantics.ProgressBarRangeInfo(progress, 0f..1f) },
        )
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            if (draft.step !in listOf(OnboardingStep.Identity, OnboardingStep.Goal)) {
                TextButton(onClick = back) { Text(stringResource(R.string.onboarding_back)) }
            } else Spacer(Modifier.width(64.dp))
            Spacer(Modifier.weight(1f))
            Text(stringResource(R.string.onboarding_progress, visibleSteps.indexOf(draft.step) + 1, visibleSteps.size), style = MaterialTheme.typography.labelLarge)
        }
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 24.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            when (draft.step) {
                OnboardingStep.Identity -> IdentityStep(draft, state.account?.verifiedEmail.isNullOrBlank(), update)
                OnboardingStep.Goal -> GoalStep(draft, update)
                OnboardingStep.Baseline -> BaselineStep(draft, update)
                OnboardingStep.Week -> WeekStep(draft, update)
                OnboardingStep.Profile -> ProfileStep(draft, state.healthImporting, update, importHealth)
                OnboardingStep.Ready -> ReadyStep(draft)
            }
        }
        Column(Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(
                onClick = next,
                enabled = !state.saving && !state.healthImporting &&
                    (draft.step != OnboardingStep.Identity || identityValid(draft, state.account?.verifiedEmail.isNullOrBlank())) && measurementsValid(draft),
                modifier = Modifier.fillMaxWidth().height(52.dp),
            ) {
                if (state.saving) CircularProgressIndicator(Modifier.height(24.dp), strokeWidth = 2.dp)
                else Text(stringResource(if (draft.step == OnboardingStep.Ready) R.string.onboarding_build_week else R.string.onboarding_continue))
            }
            if (draft.step == OnboardingStep.Profile) {
                TextButton(onClick = skipProfile, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.onboarding_skip)) }
            }
        }
    }
}

@Composable private fun Heading(title: Int, subtitle: Int) {
    Text(stringResource(title), style = MaterialTheme.typography.headlineSmall, modifier = Modifier.semantics { heading() })
    Text(stringResource(subtitle), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

@Composable private fun IdentityStep(draft: OnboardingDraft, needsEmail: Boolean, update: ((OnboardingDraft) -> OnboardingDraft) -> Unit) {
    Heading(R.string.onboarding_identity_title, R.string.onboarding_identity_subtitle)
    OutlinedTextField(draft.displayName, { v -> update { it.copy(displayName = v) } }, Modifier.fillMaxWidth(), label = { Text(stringResource(R.string.onboarding_display_name)) }, singleLine = true)
    OutlinedTextField(draft.username, { v -> update { it.copy(username = v) } }, Modifier.fillMaxWidth(), label = { Text(stringResource(R.string.onboarding_username)) }, supportingText = { Text(stringResource(R.string.onboarding_username_help)) }, singleLine = true)
    if (needsEmail) OutlinedTextField(draft.email, { v -> update { it.copy(email = v) } }, Modifier.fillMaxWidth(), label = { Text(stringResource(R.string.onboarding_email)) }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email), singleLine = true)
}

@Composable private fun GoalStep(draft: OnboardingDraft, update: ((OnboardingDraft) -> OnboardingDraft) -> Unit) {
    Heading(R.string.onboarding_goal_title, R.string.onboarding_goal_subtitle)
    RunningGoal.entries.forEach { value -> Choice(stringResource(value.label), draft.goal == value) { update { it.copy(goal = value) } } }
}

@Composable private fun BaselineStep(draft: OnboardingDraft, update: ((OnboardingDraft) -> OnboardingDraft) -> Unit) {
    Heading(R.string.onboarding_baseline_title, R.string.onboarding_baseline_subtitle)
    Text(stringResource(R.string.onboarding_recent_frequency), style = MaterialTheme.typography.labelMedium)
    RunningFrequency.entries.forEach { value -> Choice(stringResource(value.label), draft.frequency == value) { update { it.copy(frequency = value) } } }
    NumberControl(R.string.onboarding_comfortable_minutes, draft.comfortableMinutes, 10, 90, 5) { v -> update { it.copy(comfortableMinutes = v) } }
}

@Composable private fun WeekStep(draft: OnboardingDraft, update: ((OnboardingDraft) -> OnboardingDraft) -> Unit) {
    Heading(R.string.onboarding_week_title, R.string.onboarding_week_subtitle)
    NumberControl(R.string.onboarding_runs_per_week, draft.runsPerWeek, 2, 6, 1) { v -> update { it.copy(runsPerWeek = v) } }
    NumberControl(R.string.onboarding_weekday_minutes, draft.availableMinutes, 15, 90, 5) { v -> update { it.copy(availableMinutes = v) } }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun ProfileStep(
    draft: OnboardingDraft,
    importing: Boolean,
    update: ((OnboardingDraft) -> OnboardingDraft) -> Unit,
    importHealth: () -> Unit,
) {
    Heading(R.string.onboarding_profile_title, R.string.onboarding_profile_subtitle)
    OutlinedButton(onClick = importHealth, enabled = !importing, modifier = Modifier.fillMaxWidth().height(52.dp)) {
        Text(stringResource(if (importing) R.string.onboarding_health_connecting else R.string.onboarding_health_connect))
    }
    Text(stringResource(R.string.onboarding_profile_manual), style = MaterialTheme.typography.labelMedium)
    BirthdayField(draft.birthDate) { update { d -> d.copy(birthDate = it) } }
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        OutlinedTextField(draft.heightCentimeters, { v -> update { it.copy(heightCentimeters = v) } }, Modifier.weight(1f), label = { Text(stringResource(R.string.onboarding_height_cm)) }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), singleLine = true)
        OutlinedTextField(draft.weightKilograms, { v -> update { it.copy(weightKilograms = v) } }, Modifier.weight(1f), label = { Text(stringResource(R.string.onboarding_weight_kg)) }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), singleLine = true)
    }
    SexAtBirth.entries.forEach { value -> Choice(stringResource(value.label), draft.sexAtBirth == value) { update { it.copy(sexAtBirth = value) } } }
    if (!measurementsValid(draft)) Text(stringResource(R.string.onboarding_measurement_error), color = MaterialTheme.colorScheme.error)
    Text(stringResource(R.string.onboarding_profile_private), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun BirthdayField(value: String, onChange: (String) -> Unit) {
    val selectedMillis = runCatching { LocalDate.parse(value).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli() }.getOrNull()
    val picker = rememberDatePickerState(initialSelectedDateMillis = selectedMillis)
    val showDialog = androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf(false) }
    OutlinedButton(onClick = { showDialog.value = true }, modifier = Modifier.fillMaxWidth()) {
        Text(if (value.isBlank()) stringResource(R.string.onboarding_add_birthday) else value)
    }
    if (showDialog.value) DatePickerDialog(onDismissRequest = { showDialog.value = false }, confirmButton = {
        TextButton(onClick = {
            picker.selectedDateMillis?.let { onChange(Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate().toString()) }
            showDialog.value = false
        }) { Text(stringResource(R.string.onboarding_date_confirm)) }
    }, dismissButton = { TextButton(onClick = { showDialog.value = false }) { Text(stringResource(R.string.onboarding_date_clear)) } }) { DatePicker(picker) }
}

@Composable private fun ReadyStep(draft: OnboardingDraft) {
    Heading(R.string.onboarding_ready_title, R.string.onboarding_ready_subtitle)
    SummaryCard(R.string.onboarding_summary_goal, stringResource(draft.goal.label))
    SummaryCard(R.string.onboarding_summary_start, stringResource(R.string.onboarding_summary_start_value, stringResource(draft.frequency.label), draft.comfortableMinutes))
    SummaryCard(R.string.onboarding_summary_week, stringResource(R.string.onboarding_summary_week_value, draft.runsPerWeek, draft.availableMinutes))
    HorizontalDivider()
    CalibrationRow(1, R.string.onboarding_calibration_one, R.string.onboarding_calibration_one_detail)
    CalibrationRow(2, R.string.onboarding_calibration_two, R.string.onboarding_calibration_two_detail)
    CalibrationRow(3, R.string.onboarding_calibration_three, R.string.onboarding_calibration_three_detail)
    Card { Text(stringResource(R.string.onboarding_ai_explanation), Modifier.padding(16.dp), style = MaterialTheme.typography.bodyLarge) }
}

@Composable private fun Choice(label: String, selected: Boolean, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().height(52.dp).selectable(selected, onClick = onClick).padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        RadioButton(selected, onClick = null)
        Text(label, Modifier.padding(start = 8.dp), style = MaterialTheme.typography.bodyLarge)
    }
}

@Composable private fun NumberControl(label: Int, value: Int, min: Int, max: Int, step: Int, onChange: (Int) -> Unit) {
    Card {
        Row(Modifier.fillMaxWidth().padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(label, value), Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
            TextButton(onClick = { onChange((value - step).coerceAtLeast(min)) }, enabled = value > min) { Text("−") }
            TextButton(onClick = { onChange((value + step).coerceAtMost(max)) }, enabled = value < max) { Text("+") }
        }
    }
}

@Composable private fun SummaryCard(label: Int, value: String) = Card { Column(Modifier.fillMaxWidth().padding(16.dp)) { Text(stringResource(label), style = MaterialTheme.typography.labelMedium); Text(value, style = MaterialTheme.typography.titleMedium) } }
@Composable private fun CalibrationRow(number: Int, title: Int, detail: Int) = Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) { Text(number.toString(), style = MaterialTheme.typography.titleMedium); Column(Modifier.padding(start = 16.dp)) { Text(stringResource(title), style = MaterialTheme.typography.titleSmall); Text(stringResource(detail), color = MaterialTheme.colorScheme.onSurfaceVariant) } }

private fun identityValid(draft: OnboardingDraft, needsEmail: Boolean) = draft.displayName.isNotBlank() &&
    draft.username.matches(Regex("[A-Za-z0-9_-]{3,30}")) &&
    (!needsEmail || draft.email.matches(Regex("[^@\\s]+@[^@\\s]+\\.[^@\\s]+")))
private fun measurementsValid(draft: OnboardingDraft): Boolean {
    val height = draft.heightCentimeters.toDoubleOrNull()
    val weight = draft.weightKilograms.toDoubleOrNull()
    return (draft.heightCentimeters.isBlank() || (height != null && height in 90.0..250.0)) &&
        (draft.weightKilograms.isBlank() || (weight != null && weight in 25.0..350.0))
}
