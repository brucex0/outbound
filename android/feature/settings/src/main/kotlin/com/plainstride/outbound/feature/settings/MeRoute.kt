package com.plainstride.outbound.feature.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.ExitToApp
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.DeleteForever
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.HelpOutline
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Link
import androidx.compose.material.icons.outlined.Palette
import androidx.compose.material.icons.outlined.Policy
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Straighten
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.plainstride.outbound.core.designsystem.PlainstrideThemeId
import com.plainstride.outbound.core.designsystem.plainstrideThemeColors

private enum class MePage { Overview, Settings }

@Composable
fun MeRoute(
    viewModel: SettingsViewModel,
    appVersion: String,
    debugToolsEnabled: Boolean,
    onLinkGoogle: () -> Unit,
    onSignOut: () -> Unit,
    onDeleteAccount: () -> Unit,
    onReplayOnboarding: () -> Unit,
    onActivityHistory: () -> Unit,
    activityContent: @Composable () -> Unit = {},
    settingsContent: @Composable () -> Unit = {},
    onMessage: suspend (SettingsMessage) -> Unit,
    modifier: Modifier = Modifier,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    var page by rememberSaveable { mutableStateOf(MePage.Overview) }
    LaunchedEffect(viewModel) { viewModel.messages.collect(onMessage) }
    when (page) {
        MePage.Overview -> MeOverview(state, onSettings = { page = MePage.Settings }, onRefresh = viewModel::refresh, onActivityHistory, activityContent, modifier)
        MePage.Settings -> SettingsScreen(
            state = state,
            appVersion = appVersion,
            debugToolsEnabled = debugToolsEnabled,
            onBack = { page = MePage.Overview },
            onUpdateProfile = viewModel::updateProfile,
            onMeasurement = viewModel::setMeasurement,
            onTemperature = viewModel::setTemperature,
            onAppearance = viewModel::setAppearance,
            onTheme = viewModel::setTheme,
            onLinkGoogle = onLinkGoogle,
            onSignOut = onSignOut,
            onDeleteAccount = onDeleteAccount,
            onReplayOnboarding = { viewModel.trackOnboardingReplay(); onReplayOnboarding() },
            onLegal = viewModel::trackLegal,
            settingsContent = settingsContent,
            modifier = modifier,
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MeOverview(state: SettingsUiState, onSettings: () -> Unit, onRefresh: () -> Unit, onActivityHistory: () -> Unit, activityContent: @Composable () -> Unit, modifier: Modifier) {
    Scaffold(
        modifier = modifier,
        topBar = { TopAppBar(title = { Text(stringResource(R.string.me_title)) }, actions = {
            IconButton(onClick = onRefresh) { Icon(Icons.Outlined.Refresh, stringResource(R.string.refresh)) }
            IconButton(onClick = onSettings) { Icon(Icons.Outlined.Settings, stringResource(R.string.settings_title)) }
        }) },
    ) { padding ->
        LazyColumn(Modifier.fillMaxSize().padding(padding).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            item { OutlinedCard(Modifier.fillMaxWidth().clickable(role = Role.Button, onClick = onSettings)) {
                Row(Modifier.padding(18.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    Icon(Icons.Outlined.AccountCircle, null, Modifier.size(58.dp), tint = MaterialTheme.colorScheme.primary)
                    Column(Modifier.weight(1f)) {
                        Text(state.account?.displayName ?: stringResource(R.string.runner), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                        state.account?.username?.let { Text("@$it", color = MaterialTheme.colorScheme.onSurfaceVariant) }
                    }
                    Icon(Icons.Outlined.Edit, stringResource(R.string.edit_profile))
                }
            } }
            item { SectionTitle(stringResource(R.string.current_focus)) }
            item {
                OutlinedCard(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(state.summary?.phase ?: stringResource(R.string.no_active_plan), style = MaterialTheme.typography.titleMedium)
                        Text(stringResource(if (state.summary?.phase == null) R.string.no_active_plan_body else R.string.plan_synced), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            item { SectionTitle(stringResource(R.string.this_week)) }
            item {
                OutlinedCard(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                        LinearProgressIndicator(
                            progress = { (state.summary?.consistencyPercent ?: 0).coerceIn(0, 100) / 100f },
                            modifier = Modifier.fillMaxWidth(),
                        )
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            SummaryStat(state.summary?.weeklyMinutes?.toString() ?: "—", stringResource(R.string.minutes))
                            SummaryStat(formatWeeklyDistance(state), stringResource(if (state.preferences.measurement == MeasurementSystem.Metric) R.string.kilometers else R.string.miles))
                            SummaryStat(state.summary?.consistencyPercent?.let { "$it%" } ?: "—", stringResource(R.string.consistency))
                        }
                    }
                }
            }
            item { SectionTitle(stringResource(R.string.recent)) }
            item { activityContent() }
            item { OutlinedCard(Modifier.fillMaxWidth().clickable(role = Role.Button, onClick = onActivityHistory)) {
                ListItem(
                    headlineContent = { Text(stringResource(R.string.activity_history_title)) },
                    supportingContent = { Text(stringResource(R.string.activity_history_body)) },
                    leadingContent = { Icon(Icons.Outlined.History, null) },
                )
            } }
            item { Button(onClick = onSettings, Modifier.fillMaxWidth().heightIn(min = 52.dp)) { Icon(Icons.Outlined.Settings, null); Text(stringResource(R.string.open_settings), Modifier.padding(start = 8.dp)) } }
            if (state.loading) item { Box(Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() } }
        }
    }
}

private fun formatWeeklyDistance(state: SettingsUiState): String = state.summary?.weeklyDistanceMeters?.let { meters ->
    if (state.preferences.measurement == MeasurementSystem.Metric) "%.1f".format(meters / 1_000)
    else "%.1f".format(meters / 1_609.344)
} ?: "—"

@Composable private fun SummaryStat(value: String, label: String) = Column(horizontalAlignment = Alignment.CenterHorizontally) {
    Text(value, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
    Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SettingsScreen(
    state: SettingsUiState,
    appVersion: String,
    debugToolsEnabled: Boolean,
    onBack: () -> Unit,
    onUpdateProfile: (String, String?, String?) -> Unit,
    onMeasurement: (MeasurementSystem) -> Unit,
    onTemperature: (TemperatureUnit) -> Unit,
    onAppearance: (AppearanceMode) -> Unit,
    onTheme: (PlainstrideThemeId) -> Unit,
    onLinkGoogle: () -> Unit,
    onSignOut: () -> Unit,
    onDeleteAccount: () -> Unit,
    onReplayOnboarding: () -> Unit,
    onLegal: (String) -> Unit,
    settingsContent: @Composable () -> Unit,
    modifier: Modifier,
) {
    var editProfile by rememberSaveable { mutableStateOf(false) }
    var confirmSignOut by rememberSaveable { mutableStateOf(false) }
    val uriHandler = LocalUriHandler.current
    Scaffold(modifier, topBar = { TopAppBar(
        title = { Text(stringResource(R.string.settings_title)) },
        navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.back)) } },
    ) }) { padding ->
        LazyColumn(Modifier.fillMaxSize().padding(padding), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            item { SectionTitle(stringResource(R.string.account)) }
            item { ListItem(
                headlineContent = { Text(state.account?.displayName ?: stringResource(R.string.runner)) },
                supportingContent = { Text(state.account?.contactEmail ?: state.account?.normalizedEmail ?: stringResource(R.string.account_connected)) },
                leadingContent = { Icon(Icons.Outlined.AccountCircle, null) },
                trailingContent = { Icon(Icons.Outlined.Edit, null) },
                modifier = Modifier.clickable(role = Role.Button) { editProfile = true },
            ) }
            item { SettingsAction(R.string.link_google, Icons.Outlined.Link, onLinkGoogle) }
            item { SettingsAction(R.string.sign_out, Icons.AutoMirrored.Outlined.ExitToApp) { confirmSignOut = true } }
            item { HorizontalDivider() }
            item { SectionTitle(stringResource(R.string.units)) }
            item { ChoiceRow(stringResource(R.string.measurement), MeasurementSystem.entries, state.preferences.measurement, { stringResource(if (it == MeasurementSystem.Metric) R.string.metric else R.string.imperial) }, onMeasurement) }
            item { ChoiceRow(stringResource(R.string.temperature), TemperatureUnit.entries, state.preferences.temperature, { stringResource(if (it == TemperatureUnit.Celsius) R.string.celsius else R.string.fahrenheit) }, onTemperature) }
            item { HorizontalDivider() }
            item { SectionTitle(stringResource(R.string.appearance)) }
            item { ChoiceRow(stringResource(R.string.mode), AppearanceMode.entries, state.preferences.appearance, { stringResource(when (it) { AppearanceMode.System -> R.string.system_mode; AppearanceMode.Light -> R.string.light_mode; AppearanceMode.Dark -> R.string.dark_mode }) }, onAppearance) }
            item { Text(stringResource(R.string.theme), Modifier.padding(horizontal = 20.dp, vertical = 10.dp), style = MaterialTheme.typography.titleSmall) }
            items(PlainstrideThemeId.entries.chunked(2)) { row ->
                Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    row.forEach { theme -> ThemeChoice(theme, theme == state.preferences.theme, { onTheme(theme) }, Modifier.weight(1f)) }
                    if (row.size == 1) Box(Modifier.weight(1f))
                }
            }
            item { HorizontalDivider() }
            item { settingsContent() }
            item { HorizontalDivider() }
            item { SectionTitle(stringResource(R.string.help_and_legal)) }
            item { LegalAction(R.string.terms, "terms", "https://run.plainstride.com/terms", onLegal, uriHandler::openUri) }
            item { LegalAction(R.string.privacy, "privacy", "https://run.plainstride.com/privacy", onLegal, uriHandler::openUri) }
            item { LegalAction(R.string.support, "support", "https://run.plainstride.com/support", onLegal, uriHandler::openUri) }
            if (debugToolsEnabled) item { SettingsAction(R.string.replay_onboarding, Icons.Outlined.Refresh, onReplayOnboarding) }
            item { ListItem(headlineContent = { Text(stringResource(R.string.version)) }, supportingContent = { Text(appVersion) }) }
            item { Text(stringResource(R.string.privacy_note), Modifier.padding(20.dp), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            item { TextButton(onClick = onDeleteAccount, Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Icon(Icons.Outlined.DeleteForever, null); Text(stringResource(R.string.delete_account), Modifier.padding(start = 8.dp), color = MaterialTheme.colorScheme.error) } }
        }
    }
    if (editProfile) ProfileDialog(state.account, { editProfile = false }, { name, username, email -> onUpdateProfile(name, username, email); editProfile = false })
    if (confirmSignOut) AlertDialog(
        onDismissRequest = { confirmSignOut = false },
        title = { Text(stringResource(R.string.sign_out_question)) },
        confirmButton = { TextButton(onClick = { confirmSignOut = false; onSignOut() }) { Text(stringResource(R.string.sign_out)) } },
        dismissButton = { TextButton(onClick = { confirmSignOut = false }) { Text(stringResource(R.string.cancel)) } },
    )
}

@Composable private fun SectionTitle(text: String) = Text(text, Modifier.padding(horizontal = 20.dp, vertical = 12.dp).semantics { heading() }, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)

@Composable private fun SettingsAction(label: Int, icon: androidx.compose.ui.graphics.vector.ImageVector, action: () -> Unit) = ListItem(
    headlineContent = { Text(stringResource(label)) }, leadingContent = { Icon(icon, null) },
    modifier = Modifier.clickable(role = Role.Button, onClick = action).heightIn(min = 56.dp),
)

@Composable private fun LegalAction(label: Int, kind: String, url: String, track: (String) -> Unit, open: (String) -> Unit) = ListItem(
    headlineContent = { Text(stringResource(label)) }, leadingContent = { Icon(if (kind == "support") Icons.Outlined.HelpOutline else Icons.Outlined.Policy, null) },
    modifier = Modifier.clickable(role = Role.Button) { track(kind); open(url) }.heightIn(min = 56.dp),
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun <T> ChoiceRow(title: String, choices: List<T>, selected: T, label: @Composable (T) -> String, onSelect: (T) -> Unit) {
    Column(Modifier.padding(horizontal = 20.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, style = MaterialTheme.typography.titleSmall)
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            choices.forEachIndexed { index, choice -> SegmentedButton(
                selected = choice == selected,
                onClick = { onSelect(choice) },
                shape = SegmentedButtonDefaults.itemShape(index, choices.size),
                label = { Text(label(choice), maxLines = 1, overflow = TextOverflow.Ellipsis) },
            ) }
        }
    }
}

@Composable private fun ThemeChoice(theme: PlainstrideThemeId, selected: Boolean, onClick: () -> Unit, modifier: Modifier) {
    val colors = plainstrideThemeColors(theme, false)
    OutlinedButton(onClick = onClick, modifier.heightIn(min = 58.dp)) {
        Box(Modifier.size(22.dp).background(colors.accent, RoundedCornerShape(6.dp)))
        Text(stringResource(themeName(theme)), Modifier.padding(start = 8.dp), maxLines = 1)
        if (selected) Text(" ✓")
    }
}

@Composable private fun ProfileDialog(account: com.plainstride.outbound.core.network.AccountDto?, dismiss: () -> Unit, save: (String, String?, String?) -> Unit) {
    var name by remember(account) { mutableStateOf(account?.displayName.orEmpty()) }
    var username by remember(account) { mutableStateOf(account?.username.orEmpty()) }
    var email by remember(account) { mutableStateOf(account?.contactEmail.orEmpty()) }
    val cleanedUsername = username.trim().lowercase()
    val usernameValid = cleanedUsername.isEmpty() || (cleanedUsername.length in 3..30 && cleanedUsername.all { it.isLetterOrDigit() || it == '_' || it == '-' })
    val usernameChanged = cleanedUsername != account?.username.orEmpty().lowercase()
    AlertDialog(
        onDismissRequest = dismiss,
        title = { Text(stringResource(R.string.edit_profile)) },
        text = { Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            OutlinedTextField(name, { name = it.take(50) }, label = { Text(stringResource(R.string.display_name)) }, singleLine = true)
            OutlinedTextField(username, { username = it.lowercase().filter { character -> character.isLetterOrDigit() || character == '_' || character == '-' }.take(30) }, label = { Text(stringResource(R.string.username)) }, supportingText = { Text(stringResource(if (usernameValid) R.string.username_cooldown else R.string.username_invalid)) }, isError = !usernameValid, singleLine = true)
            OutlinedTextField(email, { email = it.take(254) }, label = { Text(stringResource(R.string.contact_email)) }, singleLine = true)
        } },
        confirmButton = { TextButton(onClick = { save(name.trim(), cleanedUsername.takeIf { it.isNotEmpty() }, email) }, enabled = name.isNotBlank() && usernameValid && (!usernameChanged || cleanedUsername.isNotEmpty())) { Text(stringResource(R.string.save)) } },
        dismissButton = { TextButton(onClick = dismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

private fun themeName(theme: PlainstrideThemeId) = when (theme) {
    PlainstrideThemeId.VictoryGold -> R.string.theme_victory_gold
    PlainstrideThemeId.Indigo -> R.string.theme_indigo
    PlainstrideThemeId.Ocean -> R.string.theme_ocean
    PlainstrideThemeId.Forest -> R.string.theme_forest
    PlainstrideThemeId.Rose -> R.string.theme_rose
    PlainstrideThemeId.Aurora -> R.string.theme_aurora
    PlainstrideThemeId.ElectricLime -> R.string.theme_electric_lime
    PlainstrideThemeId.NeonPulse -> R.string.theme_neon_pulse
}
