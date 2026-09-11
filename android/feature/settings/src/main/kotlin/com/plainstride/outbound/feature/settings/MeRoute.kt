package com.plainstride.outbound.feature.settings

import androidx.annotation.StringRes
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DirectionsWalk
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.ExitToApp
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.EventAvailable
import androidx.compose.material.icons.filled.MilitaryTech
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material.icons.filled.TrackChanges
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.DeleteForever
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.HelpOutline
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Link
import androidx.compose.material.icons.outlined.Map
import androidx.compose.material.icons.outlined.Policy
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Settings
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
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.plainstride.outbound.core.designsystem.PlainstrideThemeId
import com.plainstride.outbound.core.designsystem.plainstrideThemeColors
import com.plainstride.outbound.feature.social.SocialAvatar
import com.plainstride.outbound.feature.social.SocialConnectionsPreview
import com.plainstride.outbound.feature.social.SocialPerson
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

private enum class MePage { Overview, Settings, Milestones }

data class MeInsight(val id: String, val label: String, val value: String, val confidence: String)
data class MeMilestone(val id: String, val label: String)

private enum class PersonalMilestoneFamily(@param:StringRes val title: Int) {
    Beginnings(R.string.recognition_family_beginnings),
    Progress(R.string.recognition_family_progress),
}

private enum class PersonalMilestoneBadge(
    val wireValue: String,
    val family: PersonalMilestoneFamily,
    @param:StringRes val title: Int,
    @param:StringRes val detail: Int,
    val priority: Int,
    val icon: ImageVector? = null,
    val iconText: String? = null,
) {
    FirstStep("firstStep", PersonalMilestoneFamily.Beginnings, R.string.recognition_first_step_title, R.string.recognition_first_step_detail, 70, Icons.AutoMirrored.Filled.DirectionsWalk),
    BackInMotion("backInMotion", PersonalMilestoneFamily.Beginnings, R.string.recognition_back_in_motion_title, R.string.recognition_back_in_motion_detail, 100, Icons.Default.Replay),
    WeeklyFocusComplete("weeklyFocusComplete", PersonalMilestoneFamily.Progress, R.string.recognition_weekly_focus_complete_title, R.string.recognition_weekly_focus_complete_detail, 90, Icons.Default.TrackChanges),
    FourWeekRhythm("fourWeekRhythm", PersonalMilestoneFamily.Progress, R.string.recognition_four_week_rhythm_title, R.string.recognition_four_week_rhythm_detail, 85, Icons.Default.EventAvailable),
    First5K("first5K", PersonalMilestoneFamily.Progress, R.string.recognition_first_5k_title, R.string.recognition_first_5k_detail, 82, iconText = "5"),
    First10K("first10K", PersonalMilestoneFamily.Progress, R.string.recognition_first_10k_title, R.string.recognition_first_10k_detail, 84, iconText = "10"),
    FirstHalfMarathon("firstHalfMarathon", PersonalMilestoneFamily.Progress, R.string.recognition_first_half_marathon_title, R.string.recognition_first_half_marathon_detail, 92, Icons.Default.MilitaryTech),
    FirstMarathon("firstMarathon", PersonalMilestoneFamily.Progress, R.string.recognition_first_marathon_title, R.string.recognition_first_marathon_detail, 95, Icons.Default.EmojiEvents);

    companion object {
        fun fromWireValue(value: String): PersonalMilestoneBadge? = entries.firstOrNull { it.wireValue == value }
    }
}

private data class PersonalMilestone(
    val id: String,
    val badge: PersonalMilestoneBadge,
    val earnedAt: Instant?,
)

private fun MeMilestone.asPersonalMilestone(): PersonalMilestone? {
    val separator = id.indexOf(':')
    if (separator <= 0) return null
    val badge = PersonalMilestoneBadge.fromWireValue(id.substring(0, separator)) ?: return null
    val earnedAt = runCatching { Instant.parse(id.substring(separator + 1)) }.getOrNull()
    return PersonalMilestone(id, badge, earnedAt)
}

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
    connections: List<SocialPerson> = emptyList(),
    insights: List<MeInsight> = emptyList(),
    milestones: List<MeMilestone> = emptyList(),
    localWeeklyMinutes: Int = 0,
    localWeeklyDistanceMeters: Double = 0.0,
    localWeeklyActivityCount: Int = 0,
    onConnections: () -> Unit = {},
    onMyRoutes: () -> Unit = {},
    onMeDestination: (String) -> Unit = {},
    activityContent: @Composable () -> Unit = {},
    settingsContent: @Composable () -> Unit = {},
    onMessage: suspend (SettingsMessage) -> Unit,
    modifier: Modifier = Modifier,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val personalMilestones = remember(milestones) {
        milestones
            .mapNotNull(MeMilestone::asPersonalMilestone)
            .distinctBy(PersonalMilestone::badge)
            .sortedByDescending { it.earnedAt ?: Instant.EPOCH }
    }
    var page by rememberSaveable { mutableStateOf(MePage.Overview) }
    LaunchedEffect(viewModel) { viewModel.messages.collect(onMessage) }
    when (page) {
        MePage.Overview -> MeOverview(
            state, onSettings = { page = MePage.Settings }, onRefresh = viewModel::refresh,
            onActivityHistory, connections, insights, personalMilestones,
            localWeeklyMinutes, localWeeklyDistanceMeters, localWeeklyActivityCount,
            onConnections = { onMeDestination("connections"); onConnections() },
            onMyRoutes = { onMeDestination("my_routes"); onMyRoutes() },
            onMilestones = { onMeDestination("milestones"); page = MePage.Milestones },
            activityContent, modifier,
        )
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
        MePage.Milestones -> MilestonesScreen(personalMilestones, onBack = { page = MePage.Overview }, modifier)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MeOverview(
    state: SettingsUiState,
    onSettings: () -> Unit,
    onRefresh: () -> Unit,
    onActivityHistory: () -> Unit,
    connections: List<SocialPerson>,
    insights: List<MeInsight>,
    milestones: List<PersonalMilestone>,
    localWeeklyMinutes: Int,
    localWeeklyDistanceMeters: Double,
    localWeeklyActivityCount: Int,
    onConnections: () -> Unit,
    onMyRoutes: () -> Unit,
    onMilestones: () -> Unit,
    activityContent: @Composable () -> Unit,
    modifier: Modifier,
) {
    Scaffold(
        modifier = modifier,
        topBar = { TopAppBar(title = { Text(stringResource(R.string.me_title)) }, actions = {
            IconButton(onClick = onRefresh) { Icon(Icons.Outlined.Refresh, stringResource(R.string.refresh)) }
            IconButton(onClick = onSettings) { Icon(Icons.Outlined.Settings, stringResource(R.string.settings_title)) }
        }) },
    ) { padding ->
        LazyColumn(Modifier.fillMaxSize().padding(padding).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            item { OutlinedCard(Modifier.fillMaxWidth().clickable(role = Role.Button, onClick = onSettings)) {
                Row(Modifier.padding(18.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    SocialAvatar(
                        person = SocialPerson(
                            id = state.account?.id.orEmpty(),
                            displayName = state.account?.displayName ?: stringResource(R.string.runner),
                            avatarUrl = state.account?.avatarUrl,
                        ),
                        size = 58.dp,
                    )
                    Column(Modifier.weight(1f)) {
                        Text(state.account?.displayName ?: stringResource(R.string.runner), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                        state.account?.username?.let { Text("@$it", color = MaterialTheme.colorScheme.onSurfaceVariant) }
                    }
                    Icon(Icons.Outlined.Edit, stringResource(R.string.edit_profile))
                }
            } }
            item { SectionTitle(stringResource(R.string.me_connections)) }
            item { SocialConnectionsPreview(connections, onOpenAll = onConnections) }
            item { SectionTitle(stringResource(R.string.current_focus)) }
            item {
                OutlinedCard(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(state.summary?.phase ?: stringResource(R.string.no_active_plan), style = MaterialTheme.typography.titleMedium)
                        Text(stringResource(if (state.summary?.phase == null) R.string.no_active_plan_body else R.string.plan_synced), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            item { NavigationCard(R.string.me_my_routes, R.string.me_my_routes_body, Icons.Outlined.Map, onMyRoutes) }
            if (insights.isNotEmpty()) item {
                OutlinedCard(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text(stringResource(R.string.me_learned), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        insights.take(3).forEach { insight ->
                            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                Text(insight.label, fontWeight = FontWeight.SemiBold)
                                Text(insight.confidence, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            Text(insight.value, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
            item { SectionTitle(stringResource(R.string.this_week)) }
            item {
                OutlinedCard(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                        LinearProgressIndicator(
                            progress = { (state.summary?.consistencyPercent ?: if (localWeeklyActivityCount > 0) (localWeeklyActivityCount * 34).coerceAtMost(100) else 0).coerceIn(0, 100) / 100f },
                            modifier = Modifier.fillMaxWidth(),
                        )
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            SummaryStat((state.summary?.weeklyMinutes ?: localWeeklyMinutes).toString(), stringResource(R.string.minutes))
                            SummaryStat(formatWeeklyDistance(state, localWeeklyDistanceMeters), stringResource(if (state.preferences.measurement == MeasurementSystem.Metric) R.string.kilometers else R.string.miles))
                            SummaryStat("${state.summary?.consistencyPercent ?: (localWeeklyActivityCount * 34).coerceAtMost(100)}%", stringResource(R.string.consistency))
                        }
                    }
                }
            }
            item { MilestonesOverviewCard(milestones, onMilestones) }
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

@Composable
private fun NavigationCard(label: Int, body: Int, icon: androidx.compose.ui.graphics.vector.ImageVector, onClick: () -> Unit, extra: @Composable (() -> Unit)? = null) {
    OutlinedCard(Modifier.fillMaxWidth().clickable(role = Role.Button, onClick = onClick)) {
        ListItem(
            headlineContent = { Text(stringResource(label), fontWeight = FontWeight.SemiBold) },
            supportingContent = { Column { Text(stringResource(body)); extra?.invoke() } },
            leadingContent = { Icon(icon, null, tint = MaterialTheme.colorScheme.primary) },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MilestonesScreen(milestones: List<PersonalMilestone>, onBack: () -> Unit, modifier: Modifier) {
    Scaffold(modifier, topBar = { TopAppBar(
        title = { Text(stringResource(R.string.me_milestones)) },
        navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.back)) } },
    ) }) { padding ->
        LazyColumn(Modifier.fillMaxSize().padding(padding).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            item {
                Text(
                    stringResource(R.string.recognition_history_intro),
                    Modifier.padding(horizontal = 4.dp),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (milestones.isEmpty()) {
                item { MilestoneEmptyCard() }
            } else {
                PersonalMilestoneFamily.entries.forEach { family ->
                    val familyMilestones = milestones
                        .filter { it.badge.family == family }
                        .sortedWith(
                            compareByDescending<PersonalMilestone> { it.earnedAt ?: Instant.EPOCH }
                                .thenBy { it.badge.priority },
                        )
                    if (familyMilestones.isNotEmpty()) {
                        item(key = family.name) { MilestoneFamilyCard(family, familyMilestones) }
                    }
                }
            }
        }
    }
}

@Composable
private fun MilestonesOverviewCard(milestones: List<PersonalMilestone>, onClick: () -> Unit) {
    OutlinedCard(Modifier.fillMaxWidth().clickable(role = Role.Button, onClick = onClick)) {
        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text(stringResource(R.string.me_milestones), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                if (milestones.isEmpty()) {
                    Box(
                        Modifier.size(40.dp).background(RecognitionOrange.copy(alpha = 0.12f), CircleShape),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(Icons.Default.AutoAwesome, stringResource(R.string.me_milestones_empty), tint = RecognitionOrange)
                    }
                } else {
                    milestones.take(4).forEach { milestone -> MilestoneOrb(milestone, 40.dp) }
                }
                Box(Modifier.weight(1f))
                Box(
                    Modifier.size(40.dp).background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.06f), CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Default.ChevronRight, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

@Composable
private fun MilestoneFamilyCard(family: PersonalMilestoneFamily, milestones: List<PersonalMilestone>) {
    OutlinedCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text(
                stringResource(family.title).uppercase(),
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            milestones.forEachIndexed { index, milestone ->
                if (index > 0) HorizontalDivider()
                MilestoneAwardRow(milestone)
            }
        }
    }
}

@Composable
private fun MilestoneAwardRow(milestone: PersonalMilestone) {
    val locale = LocalConfiguration.current.locales[0]
    val formatter = remember(locale) { DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale) }
    val earnedDate = milestone.earnedAt?.atZone(ZoneId.systemDefault())?.toLocalDate()?.format(formatter)
    Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        MilestoneOrb(milestone, 42.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(stringResource(milestone.badge.title), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
            earnedDate?.let {
                Text(stringResource(R.string.recognition_earned_on, it), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text(stringResource(milestone.badge.detail), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun MilestoneOrb(milestone: PersonalMilestone, size: androidx.compose.ui.unit.Dp) {
    Box(
        Modifier
            .size(size)
            .shadow(6.dp, CircleShape)
            .background(Brush.linearGradient(listOf(RecognitionOrange, RecognitionYellow)), CircleShape)
            .border(2.dp, Color.White.copy(alpha = 0.95f), CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        milestone.badge.icon?.let {
            Icon(it, stringResource(milestone.badge.title), Modifier.size(size * 0.46f), tint = Color.White)
        } ?: Text(
            milestone.badge.iconText.orEmpty(),
            color = Color.White,
            fontSize = (size.value * 0.31f).sp,
            fontWeight = FontWeight.Bold,
        )
    }
}

@Composable
private fun MilestoneEmptyCard() {
    OutlinedCard(Modifier.fillMaxWidth()) {
        Row(Modifier.padding(18.dp), verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Box(
                Modifier.size(46.dp).background(RecognitionOrange.copy(alpha = 0.12f), CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Default.AutoAwesome, null, tint = RecognitionOrange)
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(stringResource(R.string.recognition_empty_title), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                Text(stringResource(R.string.recognition_empty_detail), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

private val RecognitionOrange = Color(0xFFFF9500)
private val RecognitionYellow = Color(0xFFFFCC00)

private fun formatWeeklyDistance(state: SettingsUiState, localMeters: Double): String = (state.summary?.weeklyDistanceMeters ?: localMeters).let { meters ->
    if (state.preferences.measurement == MeasurementSystem.Metric) "%.1f".format(meters / 1_000)
    else "%.1f".format(meters / 1_609.344)
}

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

@Composable private fun SectionTitle(text: String) = Text(text, Modifier.padding(start = 20.dp, end = 20.dp, top = 10.dp, bottom = 2.dp).semantics { heading() }, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)

@Composable fun SettingsGroupTitle(text: String) = SectionTitle(text)

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
