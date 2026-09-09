package com.plainstride.outbound.feature.livecoach

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.heightIn
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.plainstride.outbound.feature.livecoach.network.CoachingContract
import com.plainstride.outbound.feature.recording.RecordingLaunchConfiguration

@Composable fun LiveCoachRecordingEffect(launch: RecordingLaunchConfiguration, viewModel: LiveCoachViewModel = hiltViewModel()) {
    if (launch.voiceGuideEnabled) LaunchedEffect(viewModel, launch) { viewModel.attachRecording(launch) }
}

@Composable fun LiveCoachSettingsSection(viewModel: LiveCoachViewModel = hiltViewModel()) {
    val state by viewModel.ui.collectAsStateWithLifecycle()
    LaunchedEffect(viewModel) { viewModel.loadCatalog() }
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        HorizontalDivider()
        Text(stringResource(R.string.live_coach_settings_title), Modifier.padding(horizontal = 20.dp, vertical = 12.dp).semantics { heading() }, style = MaterialTheme.typography.titleMedium)
        ListItem(
            headlineContent = { Text(stringResource(R.string.live_coach_enable)) },
            supportingContent = { Text(stringResource(R.string.live_coach_enable_detail)) },
            trailingContent = { Switch(state.preferences.enabled, { viewModel.savePreferences(state.preferences.copy(enabled = it)) }) },
            modifier = Modifier.clickable(role = Role.Switch) { viewModel.savePreferences(state.preferences.copy(enabled = !state.preferences.enabled)) }.heightIn(min = 64.dp),
        )
        if (state.loading) CircularProgressIndicator(Modifier.padding(20.dp))
        if (state.error) Text(stringResource(R.string.live_coach_catalog_error), Modifier.padding(20.dp), color = MaterialTheme.colorScheme.error)
        if (state.preferences.enabled) {
            Text(stringResource(R.string.live_coach_frequency), Modifier.padding(horizontal = 20.dp, vertical = 8.dp), style = MaterialTheme.typography.titleSmall)
            CoachingContract.entries.forEach { contract -> Choice(contract.name, contract == state.preferences.contract, contractLabel(contract)) { viewModel.savePreferences(state.preferences.copy(contract = contract)) } }
            state.catalog?.let { catalog ->
                Text(stringResource(R.string.live_coach_persona), Modifier.padding(horizontal = 20.dp, vertical = 8.dp), style = MaterialTheme.typography.titleSmall)
                catalog.coachPersonas.forEach { persona -> Choice(persona.displayName, persona.id == state.preferences.personaId, persona.description) { viewModel.savePreferences(state.preferences.copy(personaId = persona.id, voiceProfileId = persona.defaultVoiceProfileId, scriptStyleId = persona.fixedScriptStyleId)) } }
                Text(stringResource(R.string.live_coach_voice), Modifier.padding(horizontal = 20.dp, vertical = 8.dp), style = MaterialTheme.typography.titleSmall)
                catalog.voices.filter { it.id in (catalog.coachPersonas.firstOrNull { p -> p.id == state.preferences.personaId }?.allowedVoiceProfileIds ?: emptyList()) }.forEach { voice -> Choice(voice.displayName, voice.id == state.preferences.voiceProfileId, voice.description) { viewModel.savePreferences(state.preferences.copy(voiceProfileId = voice.id)) } }
            }
            Text(stringResource(R.string.live_coach_privacy), Modifier.padding(20.dp), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable private fun Choice(title: String, selected: Boolean, detail: String, select: () -> Unit) = ListItem(
    headlineContent = { Text(title) }, supportingContent = { Text(detail) }, leadingContent = { RadioButton(selected, select) },
    modifier = Modifier.clickable(role = Role.RadioButton, onClick = select).heightIn(min = 56.dp),
)
@Composable private fun contractLabel(value: CoachingContract) = stringResource(when (value) { CoachingContract.Quiet -> R.string.live_coach_quiet; CoachingContract.Responsive -> R.string.live_coach_responsive; CoachingContract.CoachMe -> R.string.live_coach_coach_me })
