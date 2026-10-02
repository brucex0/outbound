package com.plainstride.outbound.feature.progress

import java.time.DayOfWeek
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.time.temporal.TemporalAdjusters
import java.time.temporal.WeekFields
import java.util.Locale
import kotlin.math.abs
import kotlin.math.pow
import kotlin.math.roundToInt

object ProgressStatsEngine {
    private const val MINIMUM_DURATION_SECONDS = 60

    fun snapshot(
        activities: List<ProgressActivity>,
        now: Instant = Instant.now(),
        zoneId: ZoneId = ZoneId.systemDefault(),
        firstDayOfWeek: DayOfWeek = WeekFields.of(Locale.getDefault()).firstDayOfWeek,
    ): ProgressStatsSnapshot {
        val eligible = activities.filter { it.durationSeconds > MINIMUM_DURATION_SECONDS }.sortedByDescending { it.startedAt }
        val currentStart = weekStart(now.atZone(zoneId).toLocalDate(), firstDayOfWeek)
        val currentWeek = eligible.filter { it.localDate(zoneId) >= currentStart && it.localDate(zoneId) < currentStart.plusWeeks(1) }
        val weeks = weeklyBuckets(eligible, now, zoneId, firstDayOfWeek)
        val running = eligible.filter { it.activityType == "running" }
        val runningWeeks = weeklyBuckets(running, now, zoneId, firstDayOfWeek)
        val comparisons = periodComparisons(eligible, now, zoneId, firstDayOfWeek)
        val trends = ProgressTrendRange.entries.map { range ->
            ProgressTrendSeries(range, trendBuckets(eligible, range, now, zoneId, firstDayOfWeek))
        }
        val load = trainingLoad(eligible, now, zoneId)
        return ProgressStatsSnapshot(
            currentWeek = totals(currentWeek),
            weeklyBuckets = weeks,
            comparisons = comparisons,
            trendSeries = trends,
            trainingLoad = load,
            insights = insights(eligible, currentWeek, comparisons, load, now, zoneId, firstDayOfWeek),
            bestEfforts = bestEfforts(running, runningWeeks, zoneId),
            personalRecords = personalRecords(running),
            racePredictions = racePredictions(running, now, zoneId),
            momentumNote = momentum(eligible, currentWeek, now.atZone(zoneId).toLocalDate(), zoneId),
            eligibleActivityCount = eligible.size,
        )
    }

    private fun totals(items: List<ProgressActivity>) = ProgressPeriodTotals(
        items.size,
        items.sumOf { it.distanceMeters.coerceAtLeast(0.0) },
        items.sumOf { it.durationSeconds.coerceAtLeast(0) },
        items.sumOf { (it.elevationGainMeters ?: 0.0).coerceAtLeast(0.0) },
    )

    private fun interval(items: List<ProgressActivity>, start: Instant, end: Instant) = items.filter { it.startedAt >= start && it.startedAt < end }

    private fun periodComparisons(items: List<ProgressActivity>, now: Instant, zone: ZoneId, firstDay: DayOfWeek): List<ProgressPeriodComparison> {
        val localNow = now.atZone(zone)
        val weekStart = weekStart(localNow.toLocalDate(), firstDay).atStartOfDay(zone)
        val monthStart = localNow.toLocalDate().withDayOfMonth(1).atStartOfDay(zone)
        fun matched(kind: ProgressComparisonKind, start: java.time.ZonedDateTime, previousStart: java.time.ZonedDateTime, previousEnd: java.time.ZonedDateTime): ProgressPeriodComparison {
            val end = now.plusSeconds(1).coerceAtMost(start.plus(if (kind == ProgressComparisonKind.WEEK) 1 else 1, if (kind == ProgressComparisonKind.WEEK) ChronoUnit.WEEKS else ChronoUnit.MONTHS).toInstant())
            val elapsed = Duration.between(start.toInstant(), end).coerceAtLeast(Duration.ZERO)
            val priorEnd = previousStart.plus(elapsed).toInstant().coerceAtMost(previousEnd.toInstant())
            return ProgressPeriodComparison(kind, start.toInstant(), end, previousStart.toInstant(), priorEnd,
                totals(interval(items, start.toInstant(), end)), totals(interval(items, previousStart.toInstant(), priorEnd)))
        }
        val weekPrevious = weekStart.minusWeeks(1)
        val monthPrevious = monthStart.minusMonths(1)
        val rollingEnd = now.plusSeconds(1)
        val rollingStart = rollingEnd.minus(28, ChronoUnit.DAYS)
        val previousRollingStart = rollingStart.minus(28, ChronoUnit.DAYS)
        return listOf(
            matched(ProgressComparisonKind.WEEK, weekStart, weekPrevious, weekStart),
            matched(ProgressComparisonKind.MONTH, monthStart, monthPrevious, monthStart),
            ProgressPeriodComparison(ProgressComparisonKind.ROLLING_28_DAYS, rollingStart, rollingEnd, previousRollingStart, rollingStart,
                totals(interval(items, rollingStart, rollingEnd)), totals(interval(items, previousRollingStart, rollingStart))),
        )
    }

    private fun trendBuckets(items: List<ProgressActivity>, range: ProgressTrendRange, now: Instant, zone: ZoneId, firstDay: DayOfWeek): List<ProgressTrendBucket> {
        val local = now.atZone(zone)
        val currentStart = if (range.months) local.toLocalDate().withDayOfMonth(1).atStartOfDay(zone)
            else weekStart(local.toLocalDate(), firstDay).atStartOfDay(zone)
        return (range.bucketCount - 1 downTo 0).map { offset ->
            val start = if (range.months) currentStart.minusMonths(offset.toLong()) else currentStart.minusWeeks(offset.toLong())
            val end = if (range.months) start.plusMonths(1) else start.plusWeeks(1)
            ProgressTrendBucket(start.toInstant(), end.toInstant(), totals(interval(items, start.toInstant(), end.toInstant())))
        }
    }

    private fun weeklyBuckets(items: List<ProgressActivity>, now: Instant, zone: ZoneId, firstDay: DayOfWeek): List<ProgressWeekBucket> {
        val currentStart = weekStart(now.atZone(zone).toLocalDate(), firstDay)
        return (3 downTo 0).map { offset ->
            val start = currentStart.minusWeeks(offset.toLong())
            val values = totals(items.filter { it.localDate(zone) >= start && it.localDate(zone) < start.plusWeeks(1) })
            ProgressWeekBucket(start, start.plusWeeks(1), values.activityCount, values.distanceMeters, values.durationSeconds, values.elevationMeters)
        }
    }

    private fun trainingLoad(items: List<ProgressActivity>, now: Instant, zone: ZoneId): ProgressTrainingLoadSnapshot {
        val end = now.plusSeconds(1)
        val currentStart = end.minus(7, ChronoUnit.DAYS)
        val previousStart = currentStart.minus(7, ChronoUnit.DAYS)
        val current = interval(items, currentStart, end).sumOf(::heartRateLoad)
        val previous = interval(items, previousStart, currentStart).sumOf(::heartRateLoad)
        val recent = interval(items.filter { it.heartRateZoneSeconds.isNotEmpty() }, end.minus(28, ChronoUnit.DAYS), end)
        val total = recent.sumOf { it.heartRateZoneSeconds.values.sumOf { seconds -> seconds.coerceAtLeast(0) } }
        val high = recent.sumOf { a -> a.heartRateZoneSeconds.filterKeys { it >= 4 }.values.sumOf { it.coerceAtLeast(0) } }
        return ProgressTrainingLoadSnapshot(current, previous, if (previous > 0) (current - previous) / previous * 100 else null,
            if (total > 0) high.toDouble() / total * 100 else null, recent.size)
    }

    private fun heartRateLoad(activity: ProgressActivity) = activity.heartRateZoneSeconds.entries.sumOf { (zone, seconds) ->
        seconds.coerceAtLeast(0) / 60.0 * zone.coerceIn(1, 5)
    }

    private fun insights(
        items: List<ProgressActivity>, currentWeek: List<ProgressActivity>, comparisons: List<ProgressPeriodComparison>,
        load: ProgressTrainingLoadSnapshot, now: Instant, zone: ZoneId, firstDay: DayOfWeek,
    ): List<ProgressInsight> {
        val out = mutableListOf<Pair<Int, ProgressInsight>>()
        val rolling = comparisons.firstOrNull { it.kind == ProgressComparisonKind.ROLLING_28_DAYS }
        val change = rolling?.delta(ProgressMetric.DISTANCE)?.percent
        if (rolling != null && rolling.current.activityCount >= 2 && rolling.previous.distanceMeters > 0 && change != null && abs(change) >= 8) {
            out += 90 to ProgressInsight("rolling-distance", ProgressInsightCategory.VOLUME,
                if (minOf(rolling.current.activityCount, rolling.previous.activityCount) >= 5) ProgressInsightConfidence.STRONG else ProgressInsightConfidence.SOLID,
                if (change >= 0) "trending_up" else "trending_down",
                ProgressInsightEvidence.RollingDistance(change.roundToInt(), rolling.current.distanceMeters, rolling.previous.distanceMeters))
        }
        val activeWeeks = (0..7).count { offset ->
            val start = weekStart(now.atZone(zone).toLocalDate(), firstDay).minusWeeks(offset.toLong())
            items.any { it.localDate(zone) >= start && it.localDate(zone) < start.plusWeeks(1) }
        }
        if (activeWeeks >= 3) out += (if (activeWeeks >= 6) 88 else 72) to ProgressInsight("active-weeks", ProgressInsightCategory.CONSISTENCY,
            if (activeWeeks >= 6) ProgressInsightConfidence.STRONG else ProgressInsightConfidence.SOLID, "calendar", ProgressInsightEvidence.ActiveWeeks(activeWeeks, 8))

        val weekDistance = currentWeek.sumOf { it.distanceMeters.coerceAtLeast(0.0) }
        val longest = currentWeek.maxByOrNull { it.distanceMeters }
        if (currentWeek.size >= 2 && weekDistance > 0 && longest != null) {
            val share = longest.distanceMeters / weekDistance * 100
            if (share >= 25) out += (if (share > 50) 92 else 68) to ProgressInsight("long-run-share", ProgressInsightCategory.ENDURANCE,
                if (currentWeek.size >= 3) ProgressInsightConfidence.SOLID else ProgressInsightConfidence.EMERGING, "compare_arrows",
                ProgressInsightEvidence.LongRunShare(share.roundToInt(), longest.distanceMeters, weekDistance))
        }
        heartRateEfficiency(items, now)?.let { efficiency ->
            out += 86 to ProgressInsight("heart-rate-efficiency", ProgressInsightCategory.EFFICIENCY,
                if (efficiency.third >= 8) ProgressInsightConfidence.STRONG else ProgressInsightConfidence.SOLID, "favorite",
                ProgressInsightEvidence.HeartRateEfficiency(efficiency.first, efficiency.second))
        }
        val ramp = load.rampPercent
        if (load.heartRateActivityCount >= 4 && load.currentSevenDays > 0 && load.previousSevenDays > 0 && ramp != null && abs(ramp) >= 20) {
            out += (if (abs(ramp) >= 40) 96 else 82) to ProgressInsight("training-load", ProgressInsightCategory.TRAINING_LOAD,
                if (load.heartRateActivityCount >= 7) ProgressInsightConfidence.STRONG else ProgressInsightConfidence.SOLID, "speed",
                ProgressInsightEvidence.LoadRamp(ramp.roundToInt(), load.currentSevenDays, load.previousSevenDays))
        }
        load.highIntensityPercent?.takeIf { load.heartRateActivityCount >= 3 }?.let { high ->
            out += (if (high > 30) 94 else 64) to ProgressInsight("intensity-balance", ProgressInsightCategory.TRAINING_BALANCE,
                if (load.heartRateActivityCount >= 6) ProgressInsightConfidence.STRONG else ProgressInsightConfidence.SOLID, "bar_chart",
                ProgressInsightEvidence.IntensityBalance(high.roundToInt()))
        }
        val goals = items.filter { ChronoUnit.DAYS.between(it.localDate(zone), now.atZone(zone).toLocalDate()) in 0..28 && it.goalCompleted != null }
        if (goals.size >= 3) out += 74 to ProgressInsight("goal-completion", ProgressInsightCategory.GOALS,
            if (goals.size >= 6) ProgressInsightConfidence.STRONG else ProgressInsightConfidence.SOLID, "track_changes",
            ProgressInsightEvidence.GoalCompletion(goals.count { it.goalCompleted == true }, goals.size))
        val pattern = items.filter { ChronoUnit.DAYS.between(it.localDate(zone), now.atZone(zone).toLocalDate()) in 0..42 }
        preferredDayPart(pattern, zone)?.let { (part, percent) ->
            out += 56 to ProgressInsight("preferred-time", ProgressInsightCategory.PATTERN,
                if (pattern.size >= 10) ProgressInsightConfidence.STRONG else ProgressInsightConfidence.SOLID, "schedule",
                ProgressInsightEvidence.PreferredTime(part, percent, pattern.size))
        }
        return out.sortedWith(compareByDescending<Pair<Int, ProgressInsight>> { it.first }.thenBy { it.second.id }).map { it.second }
    }

    private fun heartRateEfficiency(items: List<ProgressActivity>, now: Instant): Triple<Int, Int, Int>? {
        val currentStart = now.plusSeconds(1).minus(28, ChronoUnit.DAYS)
        val previousStart = currentStart.minus(28, ChronoUnit.DAYS)
        val comparable = items.filter { it.activityType == "running" && it.averageHeartRate != null && it.distanceMeters >= 1_000 && it.durationSeconds >= 600 }
        val current = interval(comparable, currentStart, now.plusSeconds(1))
        val previous = interval(comparable, previousStart, currentStart)
        if (current.size < 2 || previous.size < 2) return null
        fun summary(group: List<ProgressActivity>): Pair<Double, Double>? {
            val distance = group.sumOf { it.distanceMeters }; val duration = group.sumOf { it.durationSeconds }
            if (distance <= 0 || duration <= 0) return null
            return duration / (distance / 1_000.0) to group.sumOf { it.averageHeartRate!! * it.durationSeconds.toDouble() } / duration
        }
        val a = summary(current) ?: return null; val b = summary(previous) ?: return null
        val hrDiff = (a.second - b.second).roundToInt()
        val paceChange = ((b.first - a.first) / b.first * 100).roundToInt()
        return if (abs(hrDiff) <= 5 && abs(paceChange) >= 2) Triple(paceChange, hrDiff, current.size + previous.size) else null
    }

    private fun preferredDayPart(items: List<ProgressActivity>, zone: ZoneId): Pair<ProgressDayPart, Int>? {
        if (items.size < 5) return null
        val counts = ProgressDayPart.entries.associateWith { 0 }.toMutableMap()
        items.forEach { activity ->
            val hour = activity.startedAt.atZone(zone).hour
            val part = when (hour) { in 5..11 -> ProgressDayPart.MORNING; in 12..17 -> ProgressDayPart.AFTERNOON; else -> ProgressDayPart.EVENING }
            counts[part] = counts.getValue(part) + 1
        }
        val dominant = counts.maxByOrNull { it.value } ?: return null
        val percent = (dominant.value * 100.0 / items.size).roundToInt()
        return if (percent >= 60) dominant.key to percent else null
    }

    private fun weekStart(date: LocalDate, first: DayOfWeek) = date.with(TemporalAdjusters.previousOrSame(first))
    private fun ProgressActivity.localDate(zone: ZoneId) = startedAt.atZone(zone).toLocalDate()

    private fun bestEfforts(items: List<ProgressActivity>, weeks: List<ProgressWeekBucket>, zone: ZoneId): List<ProgressBestEffort> = buildList {
        fastest(BestEffortKind.FASTEST_KILOMETER, 1_000.0, items)?.let(::add)
        fastest(BestEffortKind.FASTEST_MILE, 1_609.344, items)?.let(::add)
        fastest(BestEffortKind.FASTEST_FIVE_KILOMETER, 5_000.0, items)?.let(::add)
        items.maxByOrNull { it.distanceMeters }?.let { add(ProgressBestEffort(BestEffortKind.LONGEST_RUN, it.id, it.title, it.startedAt, it.durationSeconds, it.distanceMeters, it.elevationGainMeters, BestEffortSource.ACTIVITY_SUMMARY)) }
        items.maxByOrNull { it.elevationGainMeters ?: 0.0 }?.takeIf { (it.elevationGainMeters ?: 0.0) > 0 }?.let { add(ProgressBestEffort(BestEffortKind.MOST_ELEVATION, it.id, it.title, it.startedAt, it.durationSeconds, it.distanceMeters, it.elevationGainMeters, BestEffortSource.ACTIVITY_SUMMARY)) }
        weeks.maxByOrNull { it.distanceMeters }?.takeIf { it.distanceMeters > 0 }?.let { add(ProgressBestEffort(BestEffortKind.BEST_WEEK, null, null, it.startDate.atStartOfDay(zone).toInstant(), it.durationSeconds, it.distanceMeters, it.elevationMeters, BestEffortSource.WEEKLY_TOTAL)) }
    }

    private val recordTargets = listOf("400m" to 400.0, "1K" to 1_000.0, "1 mile" to 1_609.344, "5K" to 5_000.0, "10K" to 10_000.0, "10 mile" to 16_093.44, "Half marathon" to 21_097.5, "Marathon" to 42_195.0)
    private fun personalRecords(items: List<ProgressActivity>) = recordTargets.mapNotNull { (title, meters) -> fastest(BestEffortKind.FASTEST_KILOMETER, meters, items)?.let { ProgressPersonalRecord(title, meters, it) } }
    private fun racePredictions(items: List<ProgressActivity>, now: Instant, zone: ZoneId): List<ProgressRacePrediction> {
        val ref = personalRecords(items).filter { it.targetMeters in 1_000.0..21_097.5 && it.effort.durationSeconds != null }
            .maxByOrNull { it.targetMeters * if (ChronoUnit.DAYS.between(it.effort.date.atZone(zone).toLocalDate(), now.atZone(zone).toLocalDate()) <= 90) 1.0 else .75 } ?: return emptyList()
        val recent = items.count { ChronoUnit.DAYS.between(it.localDate(zone), now.atZone(zone).toLocalDate()) <= 42 }
        val confidence = when { items.size >= 12 && recent >= 6 -> PredictionConfidence.HIGH; items.size >= 5 && recent >= 3 -> PredictionConfidence.MEDIUM; else -> PredictionConfidence.LOW }
        return listOf("5K" to 5_000.0, "10K" to 10_000.0, "Half" to 21_097.5, "Marathon" to 42_195.0).map { (title, meters) -> ProgressRacePrediction(title, meters, (ref.effort.durationSeconds!! * (meters / ref.targetMeters).pow(1.06)).roundToInt(), confidence) }
    }
    private fun fastest(kind: BestEffortKind, target: Double, items: List<ProgressActivity>): ProgressBestEffort? {
        val windows = items.mapNotNull { a -> fastestWindow(a, target)?.let { effort(a, kind, target, it, BestEffortSource.ROUTE_WINDOW) } }
        if (windows.isNotEmpty()) return windows.minWithOrNull(effortComparator)
        return items.filter { it.distanceMeters >= target && it.durationSeconds > 0 }.map { effort(it, kind, target, (it.durationSeconds * target / it.distanceMeters).roundToInt(), BestEffortSource.WHOLE_ACTIVITY_FALLBACK) }.minWithOrNull(effortComparator)
    }
    private fun effort(a: ProgressActivity, kind: BestEffortKind, target: Double, seconds: Int, source: BestEffortSource) = ProgressBestEffort(kind, a.id, a.title, a.startedAt, seconds, target, null, source)
    private val effortComparator = compareBy<ProgressBestEffort> { it.durationSeconds ?: Int.MAX_VALUE }.thenByDescending { it.date }
    private fun fastestWindow(a: ProgressActivity, target: Double): Int? {
        val points = a.routePoints.filter { it.cumulativeDistanceMeters.isFinite() }.sortedBy { it.timestamp }
        if (points.size < 2 || points.last().cumulativeDistanceMeters - points.first().cumulativeDistanceMeters < target) return null
        var end = 0; var best: Long? = null
        points.indices.forEach { start ->
            val targetDistance = points[start].cumulativeDistanceMeters + target
            while (end < points.size && points[end].cumulativeDistanceMeters < targetDistance) end++
            if (end < points.size) {
                val seconds = Duration.between(points[start].timestamp, points[end].timestamp).seconds
                if (seconds > 0 && (best == null || seconds < best!!)) best = seconds
            }
        }
        return best?.toInt()
    }
    private fun momentum(items: List<ProgressActivity>, current: List<ProgressActivity>, today: LocalDate, zone: ZoneId): ProgressMomentumNote? {
        val latest = items.firstOrNull() ?: return null
        val days = ChronoUnit.DAYS.between(latest.localDate(zone), today).toInt()
        return when { days == 0 -> ProgressMomentumNote(MomentumKind.SHOWED_UP_TODAY); days >= 2 -> ProgressMomentumNote(MomentumKind.BACK_AFTER_REST); current.size >= 3 -> ProgressMomentumNote(MomentumKind.BUILDING_RHYTHM); latest.durationSeconds <= 900 -> ProgressMomentumNote(MomentumKind.SHORT_COUNTS); current.isNotEmpty() -> ProgressMomentumNote(MomentumKind.WEEK_COUNT, current.size); else -> ProgressMomentumNote(MomentumKind.KEEP_SIMPLE) }
    }
}
