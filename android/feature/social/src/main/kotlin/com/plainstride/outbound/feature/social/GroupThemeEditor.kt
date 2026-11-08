package com.plainstride.outbound.feature.social

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.selection.selectable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties

internal data class GroupThemeDefinition(val key: String, val icon: ImageVector, val title: Int, val detail: Int)

internal object GroupThemeCatalog {
    val all = listOf(
        GroupThemeDefinition("build_consistency", Icons.Outlined.Repeat, R.string.group_theme_build_consistency_title, R.string.group_theme_build_consistency_detail),
        GroupThemeDefinition("one_small_step", Icons.Outlined.DirectionsWalk, R.string.group_theme_one_small_step_title, R.string.group_theme_one_small_step_detail),
        GroupThemeDefinition("keep_the_rhythm", Icons.Outlined.ShowChart, R.string.group_theme_keep_the_rhythm_title, R.string.group_theme_keep_the_rhythm_detail),
        GroupThemeDefinition("move_for_your_mood", Icons.Outlined.WbSunny, R.string.group_theme_move_for_your_mood_title, R.string.group_theme_move_for_your_mood_detail),
        GroupThemeDefinition("recover_and_recharge", Icons.Outlined.Eco, R.string.group_theme_recover_and_recharge_title, R.string.group_theme_recover_and_recharge_detail),
        GroupThemeDefinition("do_something_together", Icons.Outlined.People, R.string.group_theme_do_something_together_title, R.string.group_theme_do_something_together_detail),
        GroupThemeDefinition("explore_somewhere_new", Icons.Outlined.Map, R.string.group_theme_explore_somewhere_new_title, R.string.group_theme_explore_somewhere_new_detail),
        GroupThemeDefinition("try_something_different", Icons.Outlined.AutoAwesome, R.string.group_theme_try_something_different_title, R.string.group_theme_try_something_different_detail),
        GroupThemeDefinition("celebrate_every_effort", Icons.Outlined.Favorite, R.string.group_theme_celebrate_every_effort_title, R.string.group_theme_celebrate_every_effort_detail),
    )
    fun definition(key: String?) = all.firstOrNull { it.key == key }
    fun recommendations(group: GroupSummary): List<GroupThemeDefinition> {
        val keys = buildList {
            if (group.upcomingActivities.isNotEmpty()) add("do_something_together")
            add(when {
                group.week.state == "completed" -> "celebrate_every_effort"
                group.week.contributedCount == 0 -> "one_small_step"
                else -> "keep_the_rhythm"
            })
            addAll(listOf("build_consistency", "move_for_your_mood", "recover_and_recharge"))
        }
        return keys.distinct().mapNotNull(::definition).take(3)
    }
}

@Composable internal fun groupThemeTitle(key: String?, customTitle: String?): String? =
    if (key == "custom") customTitle else GroupThemeCatalog.definition(key)?.let { stringResource(it.title) }

@Composable internal fun groupThemeDetail(key: String?, customNote: String?): String? =
    if (key == "custom") customNote else GroupThemeCatalog.definition(key)?.let { stringResource(it.detail) }

data class GroupThemeDraft(
    val themeKey: String,
    val customTitle: String?,
    val customNote: String?,
    val apply: String,
    val hasCommitment: Boolean,
    val target: Int,
    val focusChanged: Boolean,
    val commitmentChanged: Boolean,
)

@Composable
internal fun GroupThemeEditor(group: GroupSummary, close: () -> Unit, save: (GroupThemeDraft, (Boolean) -> Unit) -> Unit) {
    // Keep the opening snapshot stable while a successful first mutation refreshes the Group.
    val original = remember(group.id) { group }
    val ownCommitment = original.members.firstOrNull { it.isCurrentUser }?.commitment
    val originalHasCommitment = ownCommitment?.targetCount != null && !ownCommitment.skipped
    val isOwner = original.currentUserRole == "owner"
    var selectedKey by rememberSaveable(group.id) { mutableStateOf(original.week.themeKey.orEmpty()) }
    var customTitle by rememberSaveable(group.id) { mutableStateOf(original.week.themeTitle.orEmpty()) }
    var customNote by rememberSaveable(group.id) { mutableStateOf(original.week.themeNote.orEmpty()) }
    var target by rememberSaveable(group.id) { mutableIntStateOf(ownCommitment?.targetCount ?: 3) }
    var hasCommitment by rememberSaveable(group.id) { mutableStateOf(originalHasCommitment) }
    var apply by rememberSaveable(group.id) { mutableStateOf("now") }
    var saving by remember { mutableStateOf(false) }
    var confirmDiscard by remember { mutableStateOf(false) }
    val normalizedTitle = customTitle.trim().takeIf { selectedKey == "custom" }
    val normalizedNote = customNote.trim().takeIf { selectedKey == "custom" && it.isNotEmpty() }
    val validTheme = selectedKey.isNotEmpty() && (selectedKey != "custom" || !normalizedTitle.isNullOrEmpty())
    val canEditCommitment = (isOwner && apply == "now" && selectedKey.isNotEmpty()) ||
        (group.week.focusConfigured && group.week.focusMode in setOf("theme", "personal_targets"))
    val focusChanged = isOwner && validTheme && (selectedKey != original.week.themeKey ||
        normalizedTitle != original.week.themeTitle || normalizedNote != original.week.themeNote || apply != "now")
    val commitmentChanged = canEditCommitment && (hasCommitment != originalHasCommitment ||
        (hasCommitment && target != ownCommitment?.targetCount))
    val dirty = focusChanged || commitmentChanged || (isOwner && selectedKey == "custom" &&
        (customTitle != original.week.themeTitle.orEmpty() || customNote != original.week.themeNote.orEmpty()))
    val recommendations = GroupThemeCatalog.recommendations(group)
    fun requestClose() { if (!saving) { if (dirty) confirmDiscard = true else close() } }

    Dialog(onDismissRequest = ::requestClose, properties = DialogProperties(usePlatformDefaultWidth = false, dismissOnClickOutside = false)) {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            Column(Modifier.imePadding()) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                    IconButton(::requestClose, enabled = !saving) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.group_theme_back)) }
                    Text(stringResource(if (isOwner) R.string.group_weekly_theme else R.string.group_my_commitment), Modifier.weight(1f), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                    TextButton(onClick = {
                        saving = true
                        save(GroupThemeDraft(selectedKey, normalizedTitle, normalizedNote, apply, hasCommitment, target, focusChanged, commitmentChanged)) { success ->
                            saving = false
                            if (success) close()
                        }
                    }, enabled = !saving && (!isOwner || selectedKey != "custom" || validTheme)) {
                        Text(stringResource(R.string.group_settings_save))
                    }
                }
                if (saving) LinearProgressIndicator(Modifier.fillMaxWidth())
                LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    if (isOwner) {
                        item { ThemeSectionTitle(R.string.group_theme_recommended) }
                        item {
                            ElevatedCard {
                                Column {
                                    recommendations.forEachIndexed { index, theme ->
                                        if (index > 0) HorizontalDivider(Modifier.padding(start = 56.dp))
                                        ThemeOption(theme.icon, theme.title, theme.detail, selectedKey == theme.key, !saving) { selectedKey = theme.key }
                                    }
                                }
                            }
                        }
                        item { ThemeSectionTitle(R.string.group_theme_browse) }
                        item {
                            ElevatedCard {
                                Column {
                                    GroupThemeCatalog.all.filterNot { it in recommendations }.forEachIndexed { index, theme ->
                                        if (index > 0) HorizontalDivider(Modifier.padding(start = 56.dp))
                                        ThemeOption(theme.icon, theme.title, theme.detail, selectedKey == theme.key, !saving) { selectedKey = theme.key }
                                    }
                                    HorizontalDivider(Modifier.padding(start = 56.dp))
                                    ThemeOption(Icons.Outlined.Edit, R.string.group_theme_custom_action, null, selectedKey == "custom", !saving) { selectedKey = "custom" }
                                }
                            }
                        }
                        if (selectedKey == "custom") item {
                            ThemeSection(R.string.group_theme_custom_section) {
                                OutlinedTextField(customTitle, { customTitle = it.take(50) }, Modifier.fillMaxWidth(), enabled = !saving, label = { Text(stringResource(R.string.group_theme_custom_title)) }, singleLine = true)
                                OutlinedTextField(customNote, { customNote = it.take(120) }, Modifier.fillMaxWidth(), enabled = !saving, label = { Text(stringResource(R.string.group_theme_custom_note)) }, minLines = 2, maxLines = 4)
                                if (!validTheme) Text(stringResource(R.string.group_theme_custom_required), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                        item {
                            ThemeSection(R.string.group_focus_apply) {
                                listOf("now" to R.string.group_apply_now, "next_week" to R.string.group_apply_next).forEach { (value, label) ->
                                    Row(Modifier.fillMaxWidth().selectable(apply == value, enabled = !saving, role = Role.RadioButton, onClick = { apply = value }).heightIn(min = 48.dp).padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                                        RadioButton(apply == value, onClick = null, enabled = !saving)
                                        Text(stringResource(label), Modifier.padding(start = 12.dp))
                                    }
                                }
                            }
                        }
                    }
                    if (canEditCommitment) item {
                        ThemeSection(R.string.group_my_commitment) {
                            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                                Text(stringResource(R.string.group_commitment_enable), Modifier.weight(1f))
                                val commitmentLabel = stringResource(R.string.group_commitment_enable)
                                Switch(hasCommitment, { hasCommitment = it }, enabled = !saving, modifier = Modifier.semantics { contentDescription = commitmentLabel })
                            }
                            if (hasCommitment) {
                                Text(stringResource(R.string.group_focus_suggestions), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    listOf(2, 3, 4, 5).forEach { value ->
                                        val label = stringResource(R.string.group_commitment_count, value)
                                        OutlinedButton({ target = value }, Modifier.weight(1f).heightIn(min = 48.dp).semantics { contentDescription = label; selected = target == value }, enabled = !saving, contentPadding = PaddingValues(0.dp), colors = ButtonDefaults.outlinedButtonColors(contentColor = if (target == value) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)) { Text(value.toString()) }
                                    }
                                }
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Text(stringResource(R.string.group_commitment_count, target), Modifier.weight(1f))
                                    IconButton({ target-- }, enabled = !saving && target > 1) { Icon(Icons.Outlined.Remove, stringResource(R.string.group_commitment_decrease)) }
                                    IconButton({ target++ }, enabled = !saving && target < 100) { Icon(Icons.Outlined.Add, stringResource(R.string.group_commitment_increase)) }
                                }
                            }
                            Text(stringResource(R.string.group_commitment_optional), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
        }
        if (confirmDiscard) AlertDialog(
            onDismissRequest = { confirmDiscard = false },
            title = { Text(stringResource(R.string.group_theme_discard_title)) },
            confirmButton = { TextButton({ confirmDiscard = false; close() }) { Text(stringResource(R.string.group_theme_discard)) } },
            dismissButton = { TextButton({ confirmDiscard = false }) { Text(stringResource(R.string.group_theme_keep_editing)) } },
        )
    }
}

@Composable private fun ThemeSectionTitle(title: Int) {
    Text(stringResource(title), Modifier.semantics { heading() }, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

@Composable private fun ThemeSection(title: Int, content: @Composable ColumnScope.() -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        ThemeSectionTitle(title)
        ElevatedCard { Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp), content = content) }
    }
}

@Composable private fun ThemeOption(icon: ImageVector, title: Int, detail: Int?, selected: Boolean, enabled: Boolean, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().selectable(selected, enabled = enabled, role = Role.RadioButton, onClick = onClick).heightIn(min = 76.dp).padding(16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(icon, null, Modifier.size(28.dp), tint = MaterialTheme.colorScheme.primary)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(stringResource(title), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
                detail?.let { Text(stringResource(it), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            }
            if (selected) Icon(Icons.Outlined.CheckCircle, null, tint = MaterialTheme.colorScheme.primary)
    }
}
