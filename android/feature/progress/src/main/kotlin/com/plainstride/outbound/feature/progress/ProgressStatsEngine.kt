package com.plainstride.outbound.feature.progress

import java.time.DayOfWeek
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.TemporalAdjusters
import kotlin.math.pow
import kotlin.math.roundToInt

object ProgressStatsEngine {
    private const val MINIMUM_DURATION_SECONDS = 60

    fun snapshot(
        activities: List<ProgressActivity>,
        now: Instant = Instant.now(),
        zoneId: ZoneId = ZoneId.systemDefault(),
        firstDayOfWeek: DayOfWeek = DayOfWeek.MONDAY,
    ): ProgressStatsSnapshot {
        val eligible = activities.filter { it.durationSeconds > MINIMUM_DURATION_SECONDS }.sortedByDescending { it.startedAt }
        val today = now.atZone(zoneId).toLocalDate()
        val currentStart = today.with(TemporalAdjusters.previousOrSame(firstDayOfWeek))
        val current = eligible.filter { it.localDate(zoneId) >= currentStart && it.localDate(zoneId) < currentStart.plusWeeks(1) }
        val buckets = (3 downTo 0).map { offset ->
            val start = currentStart.minusWeeks(offset.toLong())
            val week = eligible.filter { it.localDate(zoneId) >= start && it.localDate(zoneId) < start.plusWeeks(1) }
            totals(week).let { ProgressWeekBucket(start, start.plusWeeks(1), it.activityCount, it.distanceMeters, it.durationSeconds, it.elevationMeters) }
        }
        return ProgressStatsSnapshot(
            currentWeek = totals(current),
            weeklyBuckets = buckets,
            bestEfforts = bestEfforts(eligible, buckets, zoneId),
            personalRecords = personalRecords(eligible),
            racePredictions = racePredictions(eligible, now, zoneId),
            momentumNote = momentum(eligible, current, today, zoneId),
            eligibleActivityCount = eligible.size,
        )
    }

    private fun totals(items: List<ProgressActivity>) = ProgressPeriodTotals(
        activityCount = items.size,
        distanceMeters = items.sumOf { it.distanceMeters.coerceAtLeast(0.0) },
        durationSeconds = items.sumOf { it.durationSeconds.coerceAtLeast(0) },
        elevationMeters = items.sumOf { (it.elevationGainMeters ?: 0.0).coerceAtLeast(0.0) },
    )

    private fun bestEfforts(items: List<ProgressActivity>, weeks: List<ProgressWeekBucket>, zoneId: ZoneId): List<ProgressBestEffort> = buildList {
        fastest(BestEffortKind.FASTEST_KILOMETER, 1_000.0, items)?.let(::add)
        fastest(BestEffortKind.FASTEST_MILE, 1_609.344, items)?.let(::add)
        fastest(BestEffortKind.FASTEST_FIVE_KILOMETER, 5_000.0, items)?.let(::add)
        items.maxByOrNull { it.distanceMeters }?.let {
            add(ProgressBestEffort(BestEffortKind.LONGEST_RUN, it.id, it.title, it.startedAt, it.durationSeconds, it.distanceMeters, it.elevationGainMeters, BestEffortSource.ACTIVITY_SUMMARY))
        }
        items.maxByOrNull { it.elevationGainMeters ?: 0.0 }?.takeIf { (it.elevationGainMeters ?: 0.0) > 0 }?.let {
            add(ProgressBestEffort(BestEffortKind.MOST_ELEVATION, it.id, it.title, it.startedAt, it.durationSeconds, it.distanceMeters, it.elevationGainMeters, BestEffortSource.ACTIVITY_SUMMARY))
        }
        weeks.maxByOrNull { it.distanceMeters }?.takeIf { it.distanceMeters > 0 }?.let {
            add(ProgressBestEffort(BestEffortKind.BEST_WEEK, null, null, it.startDate.atStartOfDay(zoneId).toInstant(), it.durationSeconds, it.distanceMeters, it.elevationMeters, BestEffortSource.WEEKLY_TOTAL))
        }
    }

    private val recordTargets = listOf(
        "400m" to 400.0, "1K" to 1_000.0, "1 mile" to 1_609.344, "5K" to 5_000.0,
        "10K" to 10_000.0, "10 mile" to 16_093.44, "Half marathon" to 21_097.5, "Marathon" to 42_195.0,
    )

    private fun personalRecords(items: List<ProgressActivity>) = recordTargets.mapNotNull { (title, meters) ->
        fastest(BestEffortKind.FASTEST_KILOMETER, meters, items)?.let { ProgressPersonalRecord(title, meters, it) }
    }

    private fun racePredictions(items: List<ProgressActivity>, now: Instant, zoneId: ZoneId): List<ProgressRacePrediction> {
        val reference = personalRecords(items)
            .filter { it.targetMeters in 1_000.0..21_097.5 && it.effort.durationSeconds != null }
            .maxByOrNull { it.targetMeters * if (daysSince(it.effort.date, now, zoneId) <= 90) 1.0 else 0.75 } ?: return emptyList()
        val recent = items.count { daysSince(it.startedAt, now, zoneId) <= 42 }
        val confidence = when {
            items.size >= 12 && recent >= 6 -> PredictionConfidence.HIGH
            items.size >= 5 && recent >= 3 -> PredictionConfidence.MEDIUM
            else -> PredictionConfidence.LOW
        }
        return listOf("5K" to 5_000.0, "10K" to 10_000.0, "Half" to 21_097.5, "Marathon" to 42_195.0).map { (title, meters) ->
            ProgressRacePrediction(title, meters, (reference.effort.durationSeconds!! * (meters / reference.targetMeters).pow(1.06)).roundToInt(), confidence)
        }
    }

    private fun fastest(kind: BestEffortKind, target: Double, items: List<ProgressActivity>): ProgressBestEffort? {
        val windows = items.mapNotNull { activity -> fastestWindow(activity, target)?.let { effort(activity, kind, target, it, BestEffortSource.ROUTE_WINDOW) } }
        if (windows.isNotEmpty()) return windows.minWithOrNull(effortComparator)
        return items.filter { it.distanceMeters >= target && it.durationSeconds > 0 }.map {
            effort(it, kind, target, (it.durationSeconds * target / it.distanceMeters).roundToInt(), BestEffortSource.WHOLE_ACTIVITY_FALLBACK)
        }.minWithOrNull(effortComparator)
    }

    private fun effort(activity: ProgressActivity, kind: BestEffortKind, target: Double, seconds: Int, source: BestEffortSource) =
        ProgressBestEffort(kind, activity.id, activity.title, activity.startedAt, seconds, target, null, source)

    private val effortComparator = compareBy<ProgressBestEffort> { it.durationSeconds ?: Int.MAX_VALUE }.thenByDescending { it.date }

    private fun fastestWindow(activity: ProgressActivity, target: Double): Int? {
        val points = activity.routePoints.filter { it.cumulativeDistanceMeters.isFinite() }.sortedBy { it.timestamp }
        if (points.size < 2 || points.last().cumulativeDistanceMeters - points.first().cumulativeDistanceMeters < target) return null
        var end = 0
        var best: Long? = null
        points.indices.forEach { start ->
            val targetDistance = points[start].cumulativeDistanceMeters + target
            while (end < points.size && points[end].cumulativeDistanceMeters < targetDistance) end++
            if (end >= points.size) return@forEach
            val seconds = Duration.between(points[start].timestamp, points[end].timestamp).seconds
            if (seconds > 0 && (best?.let { seconds < it } != false)) best = seconds
        }
        return best?.toInt()
    }

    private fun momentum(items: List<ProgressActivity>, current: List<ProgressActivity>, today: LocalDate, zoneId: ZoneId): ProgressMomentumNote? {
        val latest = items.firstOrNull() ?: return null
        val latestDate = latest.localDate(zoneId)
        return when {
            latestDate == today -> ProgressMomentumNote(MomentumKind.SHOWED_UP_TODAY)
            java.time.temporal.ChronoUnit.DAYS.between(latestDate, today) >= 2 -> ProgressMomentumNote(MomentumKind.BACK_AFTER_REST)
            current.size >= 3 -> ProgressMomentumNote(MomentumKind.BUILDING_RHYTHM)
            latest.durationSeconds <= 15 * 60 -> ProgressMomentumNote(MomentumKind.SHORT_COUNTS)
            current.isNotEmpty() -> ProgressMomentumNote(MomentumKind.WEEK_COUNT, current.size)
            else -> ProgressMomentumNote(MomentumKind.KEEP_SIMPLE)
        }
    }

    private fun daysSince(date: Instant, now: Instant, zoneId: ZoneId) =
        java.time.temporal.ChronoUnit.DAYS.between(date.atZone(zoneId).toLocalDate(), now.atZone(zoneId).toLocalDate()).toInt()

    private fun ProgressActivity.localDate(zoneId: ZoneId) = startedAt.atZone(zoneId).toLocalDate()
}
