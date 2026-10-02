package com.plainstride.outbound.feature.progress

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
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
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Tab
import androidx.compose.material3.TextButton
import androidx.compose.material3.PrimaryScrollableTabRow
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import java.time.ZoneId
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlin.math.roundToInt
import kotlin.math.abs

enum class ProgressUnitSystem { METRIC, IMPERIAL }

data class ProgressScreenState(
    val stats: ProgressStatsSnapshot,
    val unitSystem: ProgressUnitSystem = ProgressUnitSystem.METRIC,
    val activities: List<ProgressActivity> = emptyList(),
)

data class ProgressAnalyticsEvent(
    val name: String,
    val properties: Map<String, String>,
)

private enum class ProgressTab(val wireValue: String, val label: Int) {
    NOW("now", R.string.progress_tab_now), TRENDS("trends", R.string.progress_tab_trends),
    INSIGHTS("insights", R.string.progress_tab_insights), RECORDS("records", R.string.progress_tab_records),
}
private val ProgressTrendRange.wireValue: String get() = when (this) {
    ProgressTrendRange.FOUR_WEEKS -> "fourWeeks"; ProgressTrendRange.THREE_MONTHS -> "threeMonths"
    ProgressTrendRange.SIX_MONTHS -> "sixMonths"; ProgressTrendRange.ONE_YEAR -> "oneYear"
}
private val ProgressMetric.wireValue: String get() = when (this) {
    ProgressMetric.DISTANCE -> "distance"; ProgressMetric.DURATION -> "duration"; ProgressMetric.ACTIVITIES -> "activities"
    ProgressMetric.ELEVATION -> "elevation"; ProgressMetric.AVERAGE_PACE -> "averagePace"
}
private val ProgressInsightCategory.wireValue: String get() = when (this) {
    ProgressInsightCategory.VOLUME -> "volume"; ProgressInsightCategory.CONSISTENCY -> "consistency"
    ProgressInsightCategory.ENDURANCE -> "endurance"; ProgressInsightCategory.EFFICIENCY -> "efficiency"
    ProgressInsightCategory.TRAINING_LOAD -> "trainingLoad"; ProgressInsightCategory.TRAINING_BALANCE -> "trainingBalance"
    ProgressInsightCategory.GOALS -> "goals"; ProgressInsightCategory.PATTERN -> "pattern"
}

@Composable
fun ProgressScreen(
    state: ProgressScreenState,
    modifier: Modifier = Modifier,
    onAnalyticsEvent: (ProgressAnalyticsEvent) -> Unit = {},
) {
    var selectedTab by remember { mutableStateOf(ProgressTab.NOW) }
    var selectedRange by remember { mutableStateOf(ProgressTrendRange.FOUR_WEEKS) }
    var selectedMetric by remember { mutableStateOf(ProgressMetric.DISTANCE) }
    var selectedSport by remember(state.activities) { mutableStateOf(state.activities.firstOrNull()?.activityType ?: "running") }
    fun trackControl(control: String, selection: String) = onAnalyticsEvent(
        ProgressAnalyticsEvent("progress_control_changed", mapOf("control" to control, "selection_type" to selection)),
    )
    val trendStats = remember(state.activities, selectedSport) {
        ProgressStatsEngine.snapshot(state.activities.filter { it.activityType == selectedSport })
    }
    LaunchedEffect(Unit) {
        onAnalyticsEvent(
            ProgressAnalyticsEvent(
                name = "progress_surface_opened",
                properties = mapOf(
                    "entry_source" to "me",
                    "count_bucket" to countBucket(state.stats.eligibleActivityCount),
                ),
            ),
        )
        state.stats.insights.firstOrNull()?.let { insight ->
            onAnalyticsEvent(ProgressAnalyticsEvent("progress_insights_exposed", mapOf(
                "count_bucket" to countBucket(state.stats.insights.size), "source_type" to insight.category.wireValue,
            )))
        }
    }
    LazyColumn(
        modifier = modifier.padding(horizontal = 20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item { Text(stringResource(R.string.progress_title), style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold) }
        if (state.stats.eligibleActivityCount == 0) {
            item { EmptyProgressState() }
        } else {
            item {
                PrimaryScrollableTabRow(selectedTabIndex = selectedTab.ordinal) {
                    ProgressTab.entries.forEach { tab ->
                        Tab(
                            selected = selectedTab == tab,
                            onClick = { if (selectedTab != tab) { selectedTab = tab; trackControl("tab", tab.wireValue) } },
                            text = {
                                Text(
                                    stringResource(tab.label),
                                    maxLines = 1,
                                    softWrap = false,
                                    overflow = TextOverflow.Clip,
                                )
                            },
                        )
                    }
                }
            }
            when (selectedTab) {
                ProgressTab.NOW -> {
                    state.stats.momentumNote?.let { item { MomentumCard(it) } }
                    item { WeeklySummary(state.stats.currentWeek, state.stats, state.unitSystem) }
                    state.stats.insights.firstOrNull()?.let { item { InsightCard(it, state.unitSystem, compact = true) } }
                    if (state.activities.isNotEmpty()) {
                        item { SectionTitle(stringResource(R.string.progress_recent_activity_stats)) }
                        items(state.activities.filter { it.durationSeconds > 60 }.take(6), key = { it.id }) { activity -> RecentActivityCard(activity, state.unitSystem) }
                    }
                }
                ProgressTab.TRENDS -> {
                    item { ComparisonSection(state.stats.comparisons, state.unitSystem) }
                    item {
                        val availableSports = state.activities.map { it.activityType }.distinct().sorted()
                        TrendControls(availableSports, selectedSport, selectedRange, selectedMetric,
                            onSport = { if (selectedSport != it) { selectedSport = it; trackControl("activity_type", it) } },
                            onRange = { if (selectedRange != it) { selectedRange = it; trackControl("range", it.wireValue) } },
                            onMetric = { if (selectedMetric != it) { selectedMetric = it; trackControl("metric", it.wireValue) } })
                    }
                    val series = trendStats.trendSeries.firstOrNull { it.range == selectedRange }
                    if (series == null || series.buckets.isEmpty()) item { Text(stringResource(R.string.progress_no_trend_data), color = MaterialTheme.colorScheme.onSurfaceVariant) }
                    else items(series.buckets, key = { it.start }) { bucket -> TrendRow(bucket, selectedRange, selectedMetric, series.buckets, state.unitSystem) }
                }
                ProgressTab.INSIGHTS -> {
                    item { Text(stringResource(R.string.progress_insights_intro), color = MaterialTheme.colorScheme.onSurfaceVariant) }
                    if (state.stats.insights.isEmpty()) item { Text(stringResource(R.string.progress_insights_empty), color = MaterialTheme.colorScheme.onSurfaceVariant) }
                    else items(state.stats.insights, key = { it.id }) { InsightCard(it, state.unitSystem) }
                }
                ProgressTab.RECORDS -> {
                    item { SectionTitle(stringResource(R.string.progress_best_efforts)) }
                    items(state.stats.bestEfforts, key = { it.kind.name }) { BestEffortCard(it, state.unitSystem) }
                    item { SectionTitle(stringResource(R.string.progress_personal_records)) }
                    if (state.stats.personalRecords.isEmpty()) item { Text(stringResource(R.string.progress_pr_empty), color = MaterialTheme.colorScheme.onSurfaceVariant) }
                    else items(state.stats.personalRecords.take(8), key = { it.title }) { PersonalRecordRow(it, state.unitSystem) }
                    if (state.stats.racePredictions.isNotEmpty()) {
                        item { SectionTitle(stringResource(R.string.progress_race_predictions)) }
                        items(state.stats.racePredictions, key = { it.title }) { PredictionRow(it) }
                    }
                }
            }
        }
    }
}

@Composable private fun WeeklySummary(totals: ProgressPeriodTotals, stats: ProgressStatsSnapshot, units: ProgressUnitSystem) = Card(Modifier.fillMaxWidth()) {
    Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(stringResource(R.string.progress_this_week), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Stat(stringResource(R.string.progress_distance), distance(totals.distanceMeters, units), Icons.AutoMirrored.Filled.DirectionsRun)
            Stat(stringResource(R.string.progress_time), duration(totals.durationSeconds), Icons.Default.Schedule)
            Stat(stringResource(R.string.progress_elevation), elevation(totals.elevationMeters, units), Icons.Default.Landscape)
        }
        Text(pluralStringResource(R.plurals.progress_activities_count, totals.activityCount, totals.activityCount))
        val week = stats.comparisons.firstOrNull { it.kind == ProgressComparisonKind.WEEK }
        week?.let {
            val metric = if (it.current.distanceMeters > 0 || it.previous.distanceMeters > 0) ProgressMetric.DISTANCE else ProgressMetric.DURATION
            val delta = it.delta(metric)
            val label = when {
                delta == null -> null
                delta.previous == 0.0 -> if (delta.current > 0) stringResource(R.string.progress_new_this_period) else null
                else -> stringResource(R.string.progress_vs_last_week_format, delta.percent?.roundToInt() ?: 0)
            }
            label?.let { value -> Text(value, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
    }
}

@Composable private fun EmptyProgressState() = Card(Modifier.fillMaxWidth()) {
    Column(Modifier.fillMaxWidth().padding(24.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(stringResource(R.string.progress_empty_title), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        Text(stringResource(R.string.progress_empty_body), color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable private fun ComparisonSection(comparisons: List<ProgressPeriodComparison>, units: ProgressUnitSystem) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(stringResource(R.string.progress_period_comparisons), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            comparisons.forEachIndexed { index, comparison ->
                if (index > 0) androidx.compose.material3.HorizontalDivider()
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    val title = when (comparison.kind) {
                        ProgressComparisonKind.WEEK -> R.string.progress_comparison_week
                        ProgressComparisonKind.MONTH -> R.string.progress_comparison_month
                        ProgressComparisonKind.ROLLING_28_DAYS -> R.string.progress_comparison_rolling
                    }
                    Text(stringResource(title), fontWeight = FontWeight.SemiBold)
                    Text(stringResource(if (comparison.kind == ProgressComparisonKind.ROLLING_28_DAYS) R.string.progress_comparison_previous_window else R.string.progress_comparison_matched), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    val primaryMetric = if (comparison.current.distanceMeters > 0 || comparison.previous.distanceMeters > 0) ProgressMetric.DISTANCE else ProgressMetric.DURATION
                    val delta = comparison.delta(primaryMetric)
                    val change = when {
                        delta == null -> "--"
                        delta.previous == 0.0 -> stringResource(if (delta.current > 0) R.string.progress_new else R.string.progress_steady)
                        else -> stringResource(R.string.progress_percent_signed_format, delta.percent?.roundToInt() ?: 0)
                    }
                    Text(change, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary)
                    Text("${distance(comparison.current.distanceMeters, units)} · ${duration(comparison.current.durationSeconds)} · ${comparison.current.activityCount}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

@Composable private fun TrendControls(
    sports: List<String>, sport: String, range: ProgressTrendRange, metric: ProgressMetric,
    onSport: (String) -> Unit, onRange: (ProgressTrendRange) -> Unit, onMetric: (ProgressMetric) -> Unit,
) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(stringResource(R.string.progress_trend_history), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                ChoiceMenu(sportTitle(sport), sports, { sportTitle(it) }, onSport)
                ChoiceMenu(stringResource(rangeLabel(range)), ProgressTrendRange.entries, { stringResource(rangeLabel(it)) }, onRange)
                ChoiceMenu(stringResource(metricLabel(metric)), ProgressMetric.entries, { stringResource(metricLabel(it)) }, onMetric)
            }
        }
    }
}

@Composable private fun <T> ChoiceMenu(value: String, options: List<T>, title: @Composable (T) -> String, onSelect: (T) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    androidx.compose.foundation.layout.Box {
        OutlinedButton(onClick = { expanded = true }, contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 9.dp, vertical = 4.dp)) { Text(value, maxLines = 1, style = MaterialTheme.typography.labelSmall) }
        DropdownMenu(expanded, onDismissRequest = { expanded = false }) {
            options.forEach { option -> DropdownMenuItem(text = { Text(title(option)) }, onClick = { onSelect(option); expanded = false }) }
        }
    }
}

private fun rangeLabel(value: ProgressTrendRange) = when (value) {
    ProgressTrendRange.FOUR_WEEKS -> R.string.progress_range_4w
    ProgressTrendRange.THREE_MONTHS -> R.string.progress_range_3m
    ProgressTrendRange.SIX_MONTHS -> R.string.progress_range_6m
    ProgressTrendRange.ONE_YEAR -> R.string.progress_range_1y
}
private fun metricLabel(value: ProgressMetric) = when (value) {
    ProgressMetric.DISTANCE -> R.string.progress_distance
    ProgressMetric.DURATION -> R.string.progress_time
    ProgressMetric.ACTIVITIES -> R.string.progress_activities
    ProgressMetric.ELEVATION -> R.string.progress_elevation
    ProgressMetric.AVERAGE_PACE -> R.string.progress_average_pace
}
@Composable private fun sportTitle(value: String) = stringResource(when (value) {
    "running" -> R.string.progress_sport_running; "cycling" -> R.string.progress_sport_cycling; "hiking" -> R.string.progress_sport_hiking
    "walking" -> R.string.progress_sport_walking; "swimming" -> R.string.progress_sport_swimming; "strength" -> R.string.progress_sport_strength
    "mobility" -> R.string.progress_sport_mobility; else -> R.string.progress_sport_activity
})

@Composable private fun TrendRow(bucket: ProgressTrendBucket, range: ProgressTrendRange, metric: ProgressMetric, buckets: List<ProgressTrendBucket>, units: ProgressUnitSystem) {
    val value = bucket.totals.value(metric)
    val max = buckets.mapNotNull { it.totals.value(metric) }.maxOrNull()?.coerceAtLeast(1.0) ?: 1.0
    val fastestReciprocal = buckets.mapNotNull { it.totals.averagePaceSecondsPerKilometer }.filter { it > 0 }.maxOfOrNull { 1 / it } ?: 1.0
    val fraction = value?.let { if (metric == ProgressMetric.AVERAGE_PACE && it > 0) (1 / it) / fastestReciprocal else it / max }?.coerceIn(0.0, 1.0) ?: 0.0
    val local = bucket.start.atZone(ZoneId.systemDefault())
    val label = if (range.months) local.format(DateTimeFormatter.ofPattern("MMM")) else local.format(DateTimeFormatter.ofPattern("MMM d"))
    val display = when (metric) {
        ProgressMetric.DISTANCE -> distance(value ?: 0.0, units)
        ProgressMetric.DURATION -> duration((value ?: 0.0).roundToInt())
        ProgressMetric.ACTIVITIES -> (value ?: 0.0).roundToInt().toString()
        ProgressMetric.ELEVATION -> elevation(value ?: 0.0, units)
        ProgressMetric.AVERAGE_PACE -> value?.let { pace(it, units) } ?: "--"
    }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
        Text(label, modifier = Modifier.width(48.dp), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        LinearProgressIndicator(progress = { fraction.toFloat() }, modifier = Modifier.weight(1f))
        Text(display, modifier = Modifier.width(78.dp), maxLines = 1, style = MaterialTheme.typography.labelSmall)
    }
}

@Composable private fun InsightCard(insight: ProgressInsight, units: ProgressUnitSystem, compact: Boolean = false) {
    val category = when (insight.category) {
        ProgressInsightCategory.VOLUME -> R.string.progress_insight_volume
        ProgressInsightCategory.CONSISTENCY -> R.string.progress_insight_consistency
        ProgressInsightCategory.ENDURANCE -> R.string.progress_insight_endurance
        ProgressInsightCategory.EFFICIENCY -> R.string.progress_insight_efficiency
        ProgressInsightCategory.TRAINING_LOAD -> R.string.progress_insight_load
        ProgressInsightCategory.TRAINING_BALANCE -> R.string.progress_insight_balance
        ProgressInsightCategory.GOALS -> R.string.progress_insight_goals
        ProgressInsightCategory.PATTERN -> R.string.progress_insight_pattern
    }
    val confidence = when (insight.confidence) {
        ProgressInsightConfidence.EMERGING -> R.string.progress_confidence_emerging
        ProgressInsightConfidence.SOLID -> R.string.progress_confidence_solid
        ProgressInsightConfidence.STRONG -> R.string.progress_confidence_strong
    }
    val (body, evidence, action) = insightCopy(insight.evidence, units)
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                androidx.compose.material3.Icon(Icons.Default.CheckCircle, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                Column { Text(stringResource(category), fontWeight = FontWeight.SemiBold); Text(stringResource(confidence), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            }
            Text(stringResource(body.first, *body.second.toTypedArray()), color = if (compact) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface)
            if (!compact) {
                Text(stringResource(evidence.first, *evidence.second.toTypedArray()), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                androidx.compose.material3.HorizontalDivider()
                Text(stringResource(action.first, *action.second.toTypedArray()), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable private fun insightCopy(e: ProgressInsightEvidence, units: ProgressUnitSystem): Triple<Pair<Int, List<Any>>, Pair<Int, List<Any>>, Pair<Int, List<Any>>> = when (e) {
    is ProgressInsightEvidence.RollingDistance -> Triple((if (e.percent >= 0) R.string.progress_insight_volume_up_format else R.string.progress_insight_volume_down_format) to listOf(abs(e.percent)), R.string.progress_evidence_distance_format to listOf(distance(e.currentMeters, units), distance(e.previousMeters, units)), (if (abs(e.percent) >= 25 && e.percent > 0) R.string.progress_action_volume_high else R.string.progress_action_volume) to emptyList())
    is ProgressInsightEvidence.ActiveWeeks -> Triple(R.string.progress_insight_consistency_body_format to listOf(e.count, e.total), R.string.progress_evidence_weeks_format to listOf(e.count, e.total), R.string.progress_action_consistency to emptyList())
    is ProgressInsightEvidence.LongRunShare -> Triple(R.string.progress_insight_endurance_body_format to listOf(e.percent), R.string.progress_evidence_long_run_format to listOf(distance(e.longRunMeters, units), distance(e.weekMeters, units)), (if (e.percent > 50) R.string.progress_action_endurance_high else R.string.progress_action_endurance) to emptyList())
    is ProgressInsightEvidence.HeartRateEfficiency -> Triple((if (e.pacePercent >= 0) R.string.progress_insight_efficiency_up_format else R.string.progress_insight_efficiency_down_format) to listOf(abs(e.pacePercent), e.heartRateDifference), R.string.progress_evidence_efficiency_format to listOf(e.pacePercent, e.heartRateDifference), (if (e.pacePercent >= 0) R.string.progress_action_efficiency_up else R.string.progress_action_efficiency_down) to emptyList())
    is ProgressInsightEvidence.LoadRamp -> Triple((if (e.percent >= 0) R.string.progress_insight_load_up_format else R.string.progress_insight_load_down_format) to listOf(abs(e.percent)), R.string.progress_evidence_load_format to listOf(e.current, e.previous), (if (e.percent > 35) R.string.progress_action_load_high else R.string.progress_action_load) to emptyList())
    is ProgressInsightEvidence.IntensityBalance -> Triple(R.string.progress_insight_balance_body_format to listOf(e.highIntensityPercent), R.string.progress_evidence_intensity_format to listOf(e.highIntensityPercent), (if (e.highIntensityPercent > 30) R.string.progress_action_intensity_high else R.string.progress_action_intensity) to emptyList())
    is ProgressInsightEvidence.GoalCompletion -> Triple(R.string.progress_insight_goals_body_format to listOf(e.completed, e.total), R.string.progress_evidence_goals_format to listOf(e.completed, e.total), R.string.progress_action_goals to emptyList())
    is ProgressInsightEvidence.PreferredTime -> {
        val part = when (e.dayPart) { ProgressDayPart.MORNING -> R.string.progress_day_part_morning; ProgressDayPart.AFTERNOON -> R.string.progress_day_part_afternoon; ProgressDayPart.EVENING -> R.string.progress_day_part_evening }
        val localizedPart = stringResource(part)
        Triple(R.string.progress_insight_pattern_body_format to listOf(e.percent, localizedPart), R.string.progress_evidence_pattern_format to listOf(e.percent, localizedPart, e.total), R.string.progress_action_pattern_format to listOf(localizedPart))
    }
}

@Composable private fun BestEffortCard(item: ProgressBestEffort, units: ProgressUnitSystem) = Card(Modifier.fillMaxWidth()) {
    Row(Modifier.fillMaxWidth().padding(14.dp), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(bestEffortTitle(item.kind), fontWeight = FontWeight.SemiBold)
        Text(item.durationSeconds?.let(::duration) ?: item.distanceMeters?.let { distance(it, units) }.orEmpty(), fontWeight = FontWeight.Bold)
    }
}

@Composable private fun bestEffortTitle(kind: BestEffortKind): String = when (kind) {
    BestEffortKind.FASTEST_KILOMETER -> stringResource(R.string.progress_best_effort_fastest_km)
    BestEffortKind.FASTEST_MILE -> stringResource(R.string.progress_best_effort_fastest_mile)
    BestEffortKind.FASTEST_FIVE_KILOMETER -> stringResource(R.string.progress_best_effort_fastest_5k)
    BestEffortKind.LONGEST_RUN -> stringResource(R.string.progress_best_effort_longest)
    BestEffortKind.MOST_ELEVATION -> stringResource(R.string.progress_best_effort_elevation)
    BestEffortKind.BEST_WEEK -> stringResource(R.string.progress_best_effort_week)
}

@Composable private fun RecentActivityCard(activity: ProgressActivity, units: ProgressUnitSystem) = Card(Modifier.fillMaxWidth()) {
    Row(Modifier.fillMaxWidth().padding(14.dp), horizontalArrangement = Arrangement.SpaceBetween) {
        Column { Text(activity.title, fontWeight = FontWeight.SemiBold); Text(activity.startedAt.atZone(ZoneId.systemDefault()).format(DateTimeFormatter.ofPattern("MMM d")), style = MaterialTheme.typography.labelSmall) }
        Column(horizontalAlignment = androidx.compose.ui.Alignment.End) { Text(distance(activity.distanceMeters, units), fontWeight = FontWeight.Bold); Text(duration(activity.durationSeconds), style = MaterialTheme.typography.labelSmall) }
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
                        color = Color(0xFFFF9500),
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
        Column { Text(recordTitle(record.targetMeters), fontWeight = FontWeight.SemiBold); Text(record.effort.activityTitle.orEmpty(), style = MaterialTheme.typography.bodySmall) }
        Column { Text(duration(record.effort.durationSeconds ?: 0), fontWeight = FontWeight.Bold); Text(distance(record.targetMeters, units), style = MaterialTheme.typography.bodySmall) }
    }
}

@Composable private fun PredictionRow(prediction: ProgressRacePrediction) = Card(Modifier.fillMaxWidth()) {
    Row(Modifier.fillMaxWidth().padding(16.dp), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(predictionTitle(prediction.targetMeters), fontWeight = FontWeight.SemiBold)
        Column { Text(duration(prediction.predictedSeconds), fontWeight = FontWeight.Bold); Text(confidence(prediction.confidence), style = MaterialTheme.typography.labelMedium) }
    }
}

@Composable private fun recordTitle(meters: Double): String = stringResource(when (meters) {
    400.0 -> R.string.progress_pr_400m; 1_000.0 -> R.string.progress_pr_1k; 1_609.344 -> R.string.progress_pr_mile
    5_000.0 -> R.string.progress_pr_5k; 10_000.0 -> R.string.progress_pr_10k; 16_093.44 -> R.string.progress_pr_10mile
    21_097.5 -> R.string.progress_pr_half; else -> R.string.progress_pr_marathon
})

@Composable private fun predictionTitle(meters: Double): String = stringResource(when (meters) {
    5_000.0 -> R.string.progress_race_5k; 10_000.0 -> R.string.progress_race_10k
    21_097.5 -> R.string.progress_race_half; else -> R.string.progress_race_marathon
})

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
private fun pace(secondsPerKilometer: Double, units: ProgressUnitSystem): String {
    val perDistance = if (units == ProgressUnitSystem.METRIC) secondsPerKilometer else secondsPerKilometer * 1.609344
    val seconds = perDistance.roundToInt().coerceAtLeast(0)
    return "%d:%02d".format(seconds / 60, seconds % 60) + if (units == ProgressUnitSystem.METRIC) " / km" else " / mi"
}
private fun shortDate(date: java.time.LocalDate) = date.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.SHORT))
private fun countBucket(count: Int) = when (count) { 0 -> "0"; 1 -> "1"; in 2..4 -> "2_4"; in 5..9 -> "5_9"; else -> "10_plus" }
