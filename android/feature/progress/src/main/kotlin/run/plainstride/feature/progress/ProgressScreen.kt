package run.plainstride.feature.progress

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DirectionsRun
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Landscape
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.Card
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlin.math.roundToInt

enum class ProgressUnitSystem { METRIC, IMPERIAL }

data class ProgressScreenState(
    val stats: ProgressStatsSnapshot,
    val gear: List<GearMileageSummary>,
    val unitSystem: ProgressUnitSystem = ProgressUnitSystem.METRIC,
)

data class ProgressAnalyticsEvent(
    val name: String,
    val properties: Map<String, String>,
)

@Composable
fun ProgressScreen(
    state: ProgressScreenState,
    modifier: Modifier = Modifier,
    onAnalyticsEvent: (ProgressAnalyticsEvent) -> Unit = {},
) {
    LaunchedEffect(state.stats.eligibleActivityCount, state.gear.size) {
        onAnalyticsEvent(
            ProgressAnalyticsEvent(
                name = "progress_viewed",
                properties = mapOf(
                    "activity_count_bucket" to countBucket(state.stats.eligibleActivityCount),
                    "gear_count_bucket" to countBucket(state.gear.size),
                ),
            ),
        )
    }
    LazyColumn(
        modifier = modifier.padding(horizontal = 20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item { Text(stringResource(R.string.progress_title), style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold) }
        state.stats.momentumNote?.let { item { MomentumCard(it) } }
        item { WeeklySummary(state.stats.currentWeek, state.unitSystem) }
        item { WeeklyChart(state.stats.weeklyBuckets, state.unitSystem) }
        if (state.stats.personalRecords.isNotEmpty()) {
            item { SectionTitle(stringResource(R.string.progress_personal_records)) }
            items(state.stats.personalRecords, key = { "${it.title}-${it.effort.activityId}" }) { PersonalRecordRow(it, state.unitSystem) }
        }
        if (state.stats.racePredictions.isNotEmpty()) {
            item { SectionTitle(stringResource(R.string.progress_race_predictions)) }
            items(state.stats.racePredictions, key = { it.title }) { PredictionRow(it) }
        }
        if (state.gear.isNotEmpty()) {
            item { SectionTitle(stringResource(R.string.progress_gear)) }
            items(state.gear, key = { it.item.id }) { GearCard(it, state.unitSystem) }
        }
    }
}

@Composable private fun WeeklySummary(totals: ProgressPeriodTotals, units: ProgressUnitSystem) = Card(Modifier.fillMaxWidth()) {
    Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(stringResource(R.string.progress_this_week), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Stat(stringResource(R.string.progress_distance), distance(totals.distanceMeters, units), Icons.AutoMirrored.Filled.DirectionsRun)
            Stat(stringResource(R.string.progress_time), duration(totals.durationSeconds), Icons.Default.Schedule)
            Stat(stringResource(R.string.progress_elevation), elevation(totals.elevationMeters, units), Icons.Default.Landscape)
        }
        Text(pluralStringResource(R.plurals.progress_activities_count, totals.activityCount, totals.activityCount))
    }
}

@Composable private fun Stat(label: String, value: String, icon: ImageVector) = Column {
    androidx.compose.material3.Icon(icon, contentDescription = null)
    Text(value, fontWeight = FontWeight.Bold)
    Text(label, style = MaterialTheme.typography.labelMedium)
}

@Composable private fun WeeklyChart(buckets: List<ProgressWeekBucket>, units: ProgressUnitSystem) {
    val maximum = buckets.maxOfOrNull { it.distanceMeters }?.coerceAtLeast(1.0) ?: 1.0
    val descriptions = mutableListOf<String>()
    for (bucket in buckets) {
        descriptions += stringResource(
            R.string.progress_chart_week_value,
            shortDate(bucket.startDate),
            distance(bucket.distanceMeters, units),
        )
    }
    val description = descriptions.joinToString(stringResource(R.string.progress_chart_separator))
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(18.dp)) {
            Text(stringResource(R.string.progress_four_week_trend), style = MaterialTheme.typography.titleMedium)
            Canvas(
                Modifier.fillMaxWidth().height(140.dp).padding(top = 12.dp).semantics { contentDescription = description },
            ) {
                if (buckets.isEmpty()) return@Canvas
                val slot = size.width / buckets.size
                buckets.forEachIndexed { index, bucket ->
                    val barHeight = (bucket.distanceMeters / maximum).toFloat() * size.height
                    drawLine(
                        color = Color(0xFF2E7D62),
                        start = Offset(slot * index + slot / 2, size.height),
                        end = Offset(slot * index + slot / 2, size.height - barHeight),
                        strokeWidth = slot * 0.48f,
                    )
                }
            }
        }
    }
}

@Composable private fun PersonalRecordRow(record: ProgressPersonalRecord, units: ProgressUnitSystem) = Card(Modifier.fillMaxWidth()) {
    Row(Modifier.fillMaxWidth().padding(16.dp), horizontalArrangement = Arrangement.SpaceBetween) {
        Column { Text(record.title, fontWeight = FontWeight.SemiBold); Text(record.effort.activityTitle.orEmpty(), style = MaterialTheme.typography.bodySmall) }
        Column { Text(duration(record.effort.durationSeconds ?: 0), fontWeight = FontWeight.Bold); Text(distance(record.targetMeters, units), style = MaterialTheme.typography.bodySmall) }
    }
}

@Composable private fun PredictionRow(prediction: ProgressRacePrediction) = Card(Modifier.fillMaxWidth()) {
    Row(Modifier.fillMaxWidth().padding(16.dp), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(prediction.title, fontWeight = FontWeight.SemiBold)
        Column { Text(duration(prediction.predictedSeconds), fontWeight = FontWeight.Bold); Text(confidence(prediction.confidence), style = MaterialTheme.typography.labelMedium) }
    }
}

@Composable private fun GearCard(summary: GearMileageSummary, units: ProgressUnitSystem) = Card(Modifier.fillMaxWidth()) {
    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(summary.item.displayName, fontWeight = FontWeight.SemiBold)
            if (summary.item.isRetired) Text(stringResource(R.string.progress_gear_retired))
        }
        LinearProgressIndicator(
            progress = { summary.usageFraction.toFloat() },
            modifier = Modifier.fillMaxWidth().semantics {
                contentDescription = "${distance(summary.distanceMeters, units)} / ${distance(summary.item.distanceLimitMeters, units)}"
            },
        )
        Text(stringResource(R.string.progress_gear_mileage, distance(summary.distanceMeters, units), distance(summary.item.distanceLimitMeters, units)))
        if (summary.retirementDue && !summary.item.isRetired) Text(stringResource(R.string.progress_gear_retirement_due), color = MaterialTheme.colorScheme.error)
    }
}

@Composable private fun MomentumCard(note: ProgressMomentumNote) = Card(Modifier.fillMaxWidth()) {
    Row(Modifier.padding(16.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        androidx.compose.material3.Icon(Icons.Default.CheckCircle, contentDescription = null)
        Text(momentumText(note), fontWeight = FontWeight.SemiBold)
    }
}

@Composable private fun momentumText(note: ProgressMomentumNote): String = when (note.kind) {
    MomentumKind.SHOWED_UP_TODAY -> stringResource(R.string.progress_momentum_today)
    MomentumKind.BACK_AFTER_REST -> stringResource(R.string.progress_momentum_return)
    MomentumKind.BUILDING_RHYTHM -> stringResource(R.string.progress_momentum_rhythm)
    MomentumKind.SHORT_COUNTS -> stringResource(R.string.progress_momentum_short)
    MomentumKind.WEEK_COUNT -> pluralStringResource(R.plurals.progress_momentum_week_count, note.activityCount, note.activityCount)
    MomentumKind.KEEP_SIMPLE -> stringResource(R.string.progress_momentum_simple)
}

@Composable private fun confidence(value: PredictionConfidence) = when (value) {
    PredictionConfidence.LOW -> stringResource(R.string.progress_confidence_low)
    PredictionConfidence.MEDIUM -> stringResource(R.string.progress_confidence_medium)
    PredictionConfidence.HIGH -> stringResource(R.string.progress_confidence_high)
}

@Composable private fun SectionTitle(text: String) = Text(text, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
private fun distance(meters: Double, units: ProgressUnitSystem) = if (units == ProgressUnitSystem.METRIC) "%.1f km".format(meters / 1_000) else "%.1f mi".format(meters / 1_609.344)
private fun elevation(meters: Double, units: ProgressUnitSystem) = if (units == ProgressUnitSystem.METRIC) "${meters.roundToInt()} m" else "${(meters * 3.28084).roundToInt()} ft"
private fun duration(seconds: Int): String { val hours = seconds / 3_600; val minutes = seconds % 3_600 / 60; val secs = seconds % 60; return if (hours > 0) "%d:%02d:%02d".format(hours, minutes, secs) else "%d:%02d".format(minutes, secs) }
private fun shortDate(date: java.time.LocalDate) = date.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.SHORT))
private fun countBucket(count: Int) = when (count) { 0 -> "0"; 1 -> "1"; in 2..4 -> "2_4"; in 5..9 -> "5_9"; else -> "10_plus" }
