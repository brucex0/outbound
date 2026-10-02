package com.plainstride.outbound.feature.progress

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DirectionsRun
import androidx.compose.material.icons.filled.Archive
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.unit.dp
import java.text.NumberFormat
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlin.math.roundToInt

data class NewShoe(
    val name: String,
    val brand: String,
    val model: String,
    val purpose: GearPurpose,
    val distanceLimitMeters: Double,
)

@Composable
fun GearSettingsSection(
    summaries: List<GearMileageSummary>,
    defaultShoeId: String?,
    units: ProgressUnitSystem,
    onAdd: () -> Unit,
    onMakeDefault: (GearItem) -> Unit,
    onRetire: (GearItem) -> Unit,
    modifier: Modifier = Modifier,
) {
    var expanded by rememberSaveable { mutableStateOf(false) }
    val activeCount = summaries.count { !it.item.isRetired }
    val defaultShoe = summaries.firstOrNull { it.item.id.toString() == defaultShoeId && !it.item.isRetired }?.item
        ?: summaries.firstOrNull { !it.item.isRetired }?.item
    val summaryText = when {
        defaultShoe != null -> stringResource(R.string.progress_gear_selected, defaultShoe.displayName)
        summaries.isEmpty() -> stringResource(R.string.progress_gear_none_selected)
        else -> stringResource(R.string.progress_gear_active_count, activeCount)
    }
    val gearTitleText = stringResource(R.string.progress_gear_shoes_title)
    val expandHintText = stringResource(R.string.progress_gear_expand_hint)
    val collapseHintText = stringResource(R.string.progress_gear_collapse_hint)
    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = Color(0xFFFF9500).copy(alpha = 0.07f)),
        shape = MaterialTheme.shapes.extraLarge,
    ) {
        Column(Modifier.animateContentSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(
                Modifier.fillMaxWidth()
                    .clickable(role = Role.Button) { expanded = !expanded }
                    .semantics(mergeDescendants = true) {
                        contentDescription = "$summaryText — $gearTitleText"
                        stateDescription = if (expanded) collapseHintText else expandHintText
                    }
                    .heightIn(min = 52.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Icon(Icons.AutoMirrored.Filled.DirectionsRun, null, tint = MaterialTheme.colorScheme.primary)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(gearTitleText, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    Text(summaryText, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Icon(
                    Icons.Default.ExpandMore,
                    null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.graphicsLayer { rotationZ = if (expanded) 180f else 0f },
                )
            }
            if (expanded) {
                OutlinedButton(onClick = onAdd, modifier = Modifier.fillMaxWidth()) {
                    Icon(Icons.Default.Add, null, tint = Color(0xFFFF9500))
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(R.string.progress_add_gear))
                }
                if (summaries.isEmpty()) {
                    Text(stringResource(R.string.progress_gear_empty_body), color = MaterialTheme.colorScheme.onSurfaceVariant)
                } else {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        summaries.forEach { summary ->
                            GearSettingsShoeCard(summary, defaultShoeId, units, onMakeDefault, onRetire)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun GearSettingsShoeCard(
    summary: GearMileageSummary,
    defaultShoeId: String?,
    units: ProgressUnitSystem,
    onMakeDefault: (GearItem) -> Unit,
    onRetire: (GearItem) -> Unit,
) {
    val shoe = summary.item
    val isDefault = defaultShoeId == shoe.id.toString() && !shoe.isRetired
    val status = when {
        shoe.retiredAt != null -> stringResource(R.string.progress_gear_status_retired, formatLocalDate(shoe.retiredAt))
        summary.lastUsedAt != null -> stringResource(R.string.progress_gear_status_last_used, formatLocalDate(summary.lastUsedAt))
        else -> stringResource(R.string.progress_gear_status_unused)
    }
    val mileage = gearDistance(summary.distanceMeters, units)
    val target = gearDistance(shoe.distanceLimitMeters, units)
    val mileageDescription = stringResource(R.string.progress_gear_mileage_accessibility, mileage, target)
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Icon(Icons.AutoMirrored.Filled.DirectionsRun, null, tint = if (shoe.isRetired) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.primary)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(shoe.displayName, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
                    Text(status, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                if (isDefault) {
                    Text(stringResource(R.string.progress_gear_default), style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
                } else if (!shoe.isRetired) {
                    TextButton(onClick = { onMakeDefault(shoe) }) { Text(stringResource(R.string.progress_make_default)) }
                }
                if (!shoe.isRetired) {
                    IconButton(onClick = { onRetire(shoe) }) {
                        Icon(Icons.Default.Archive, contentDescription = stringResource(R.string.progress_retire), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.progress_gear_mileage, mileage, target), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold)
                Text("${(summary.usageFraction * 100).roundToInt()}%", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            LinearProgressIndicator(
                progress = { summary.usageFraction.toFloat() },
                modifier = Modifier.fillMaxWidth().semantics {
                    contentDescription = mileageDescription
                },
                color = if (shoe.isRetired) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.primary,
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddShoeSheet(
    units: ProgressUnitSystem,
    onDismiss: () -> Unit,
    onAdd: (NewShoe) -> Unit,
) {
    var purpose by rememberSaveable { mutableStateOf(GearPurpose.DAILY_TRAINER) }
    var query by rememberSaveable { mutableStateOf("") }
    var limitText by rememberSaveable { mutableStateOf("") }
    var selectedCatalogEntry by remember { mutableStateOf<GearShoeCatalogEntry?>(null) }
    var purposeMenuExpanded by remember { mutableStateOf(false) }
    val configuration = LocalConfiguration.current
    val locale = remember(configuration) { configuration.locales[0] ?: Locale.getDefault() }
    val bestMatch = remember(query, purpose, selectedCatalogEntry) {
        if (selectedCatalogEntry == null) GearShoeCatalog.bestMatch(query, purpose) else null
    }
    val catalogEntry = selectedCatalogEntry ?: bestMatch
    val rangeStart = formatGearDistance(purpose.suggestedRangeMeters.start, units, locale)
    val rangeEnd = formatGearDistance(purpose.suggestedRangeMeters.endInclusive, units, locale)
    val unit = if (units == ProgressUnitSystem.METRIC) "km" else "mi"
    val hint = stringResource(purpose.retirementHint, rangeStart, rangeEnd, unit)
    val canAdd = catalogEntry != null || query.trim().isNotEmpty()
    LaunchedEffect(purpose, units, locale) {
        if (limitText.isEmpty()) limitText = formatGearDistance(purpose.suggestedDistanceLimitMeters, units, locale, digits = 0)
    }
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
                TextButton(onClick = onDismiss) { Text(stringResource(R.string.progress_cancel)) }
                Text(stringResource(R.string.progress_add_gear), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                TextButton(
                    onClick = {
                        val resolvedBrand = catalogEntry?.brand.orEmpty()
                        val resolvedModel = catalogEntry?.model ?: query.trim()
                        val limit = catalogEntry?.distanceLimitMeters ?: parseDistance(limitText, locale, units)
                            ?: purpose.suggestedDistanceLimitMeters
                        onAdd(NewShoe(purpose.nickname, resolvedBrand, resolvedModel, purpose, limit))
                    },
                    enabled = canAdd,
                ) { Text(stringResource(R.string.progress_add), fontWeight = FontWeight.SemiBold) }
            }
            HorizontalDivider()
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(stringResource(R.string.progress_gear_purpose), style = MaterialTheme.typography.labelLarge)
                androidx.compose.foundation.layout.Box {
                    OutlinedButton(onClick = { purposeMenuExpanded = true }, modifier = Modifier.fillMaxWidth()) {
                        Text(stringResource(purpose.label), modifier = Modifier.weight(1f))
                        Icon(Icons.Default.ExpandMore, null)
                    }
                    DropdownMenu(expanded = purposeMenuExpanded, onDismissRequest = { purposeMenuExpanded = false }) {
                        GearPurpose.entries.forEach { choice ->
                            DropdownMenuItem(
                                text = { Text(stringResource(choice.label)) },
                                onClick = {
                                    val oldDefault = formatGearDistance(purpose.suggestedDistanceLimitMeters, units, locale, digits = 0)
                                    val shouldUpdateLimit = limitText.isBlank() || limitText == oldDefault
                                    purpose = choice
                                    if (shouldUpdateLimit) limitText = formatGearDistance(choice.suggestedDistanceLimitMeters, units, locale, digits = 0)
                                    selectedCatalogEntry = null
                                    purposeMenuExpanded = false
                                },
                            )
                        }
                    }
                }
            }
            OutlinedTextField(
                value = query,
                onValueChange = { next ->
                    if (selectedCatalogEntry?.displayName != next) selectedCatalogEntry = null
                    query = next
                },
                modifier = Modifier.fillMaxWidth(),
                label = { Text(stringResource(R.string.progress_gear_search)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, autoCorrectEnabled = false),
            )
            bestMatch?.let { entry ->
                OutlinedButton(
                    onClick = {
                        selectedCatalogEntry = entry
                        query = entry.displayName
                        entry.distanceLimitMeters?.let { limitText = formatGearDistance(it, units, locale, digits = 0) }
                    },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Column(Modifier.weight(1f), horizontalAlignment = Alignment.Start) {
                        Text(entry.displayName, fontWeight = FontWeight.SemiBold)
                        Text(stringResource(entry.purpose.label), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Text(stringResource(R.string.progress_gear_suggestion_use), color = MaterialTheme.colorScheme.primary)
                }
            }
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(stringResource(R.string.progress_gear_retire_around))
                Spacer(Modifier.weight(1f))
                OutlinedTextField(
                    value = limitText.ifEmpty { formatGearDistance(purpose.suggestedDistanceLimitMeters, units, locale, digits = 0) },
                    onValueChange = { limitText = it.filter { char -> char.isDigit() || char == '.' || char == ',' }.take(8) },
                    modifier = Modifier.width(88.dp),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    singleLine = true,
                    textStyle = MaterialTheme.typography.bodyMedium,
                )
                Text(unit, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text(hint, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

private fun formatLocalDate(instant: Instant): String = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)
    .withLocale(Locale.getDefault())
    .withZone(ZoneId.systemDefault())
    .format(instant)

private fun gearDistance(meters: Double, units: ProgressUnitSystem): String =
    if (units == ProgressUnitSystem.METRIC) "%.1f km".format(Locale.getDefault(), meters / 1_000.0)
    else "%.1f mi".format(Locale.getDefault(), meters / 1_609.344)

private fun formatGearDistance(meters: Double, units: ProgressUnitSystem, locale: Locale, digits: Int = 0): String {
    val value = if (units == ProgressUnitSystem.METRIC) meters / 1_000.0 else meters / 1_609.344
    return NumberFormat.getNumberInstance(locale).apply { maximumFractionDigits = digits; minimumFractionDigits = digits }.format(value)
}

private fun parseDistance(value: String, locale: Locale, units: ProgressUnitSystem): Double? {
    val parsed = runCatching { NumberFormat.getNumberInstance(locale).parse(value)?.toDouble() }.getOrNull() ?: return null
    return if (units == ProgressUnitSystem.METRIC) parsed * 1_000.0 else parsed * 1_609.344
}
