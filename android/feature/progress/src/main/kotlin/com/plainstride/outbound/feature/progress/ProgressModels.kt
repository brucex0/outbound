package com.plainstride.outbound.feature.progress

import java.time.Instant
import java.time.LocalDate

data class ProgressActivity(
    val id: String,
    val title: String,
    val startedAt: Instant,
    val durationSeconds: Int,
    val distanceMeters: Double,
    val elevationGainMeters: Double? = null,
    val averageHeartRate: Int? = null,
    val routePoints: List<ProgressRoutePoint> = emptyList(),
    val activityType: String = "running",
    val goalCompleted: Boolean? = null,
    val heartRateZoneSeconds: Map<Int, Int> = emptyMap(),
)

data class ProgressRoutePoint(
    val timestamp: Instant,
    val cumulativeDistanceMeters: Double,
)

data class ProgressPeriodTotals(
    val activityCount: Int,
    val distanceMeters: Double,
    val durationSeconds: Int,
    val elevationMeters: Double,
) {
    fun value(metric: ProgressMetric): Double? = when (metric) {
        ProgressMetric.DISTANCE -> distanceMeters
        ProgressMetric.DURATION -> durationSeconds.toDouble()
        ProgressMetric.ACTIVITIES -> activityCount.toDouble()
        ProgressMetric.ELEVATION -> elevationMeters
        ProgressMetric.AVERAGE_PACE -> averagePaceSecondsPerKilometer
    }
    val averagePaceSecondsPerKilometer: Double?
        get() = if (distanceMeters > 0 && durationSeconds > 0) durationSeconds / (distanceMeters / 1_000.0) else null
}

enum class ProgressMetric { DISTANCE, DURATION, ACTIVITIES, ELEVATION, AVERAGE_PACE }
enum class ProgressComparisonKind { WEEK, MONTH, ROLLING_28_DAYS }
enum class ProgressTrendRange(val bucketCount: Int, val months: Boolean) { FOUR_WEEKS(4, false), THREE_MONTHS(13, false), SIX_MONTHS(6, true), ONE_YEAR(12, true) }
data class ProgressMetricDelta(val current: Double, val previous: Double) {
    val percent: Double? get() = if (previous > 0) (current - previous) / previous * 100 else null
}
data class ProgressPeriodComparison(
    val kind: ProgressComparisonKind,
    val currentStart: Instant,
    val currentEnd: Instant,
    val previousStart: Instant,
    val previousEnd: Instant,
    val current: ProgressPeriodTotals,
    val previous: ProgressPeriodTotals,
) {
    fun delta(metric: ProgressMetric) = current.value(metric)?.let { currentValue -> previous.value(metric)?.let { ProgressMetricDelta(currentValue, it) } }
}
data class ProgressTrendBucket(val start: Instant, val end: Instant, val totals: ProgressPeriodTotals)
data class ProgressTrendSeries(val range: ProgressTrendRange, val buckets: List<ProgressTrendBucket>)
data class ProgressTrainingLoadSnapshot(
    val currentSevenDays: Double,
    val previousSevenDays: Double,
    val rampPercent: Double?,
    val highIntensityPercent: Double?,
    val heartRateActivityCount: Int,
)
enum class ProgressInsightConfidence { EMERGING, SOLID, STRONG }
enum class ProgressInsightCategory { VOLUME, CONSISTENCY, ENDURANCE, EFFICIENCY, TRAINING_LOAD, TRAINING_BALANCE, GOALS, PATTERN }
enum class ProgressDayPart { MORNING, AFTERNOON, EVENING }
sealed interface ProgressInsightEvidence {
    data class RollingDistance(val percent: Int, val currentMeters: Double, val previousMeters: Double) : ProgressInsightEvidence
    data class ActiveWeeks(val count: Int, val total: Int) : ProgressInsightEvidence
    data class LongRunShare(val percent: Int, val longRunMeters: Double, val weekMeters: Double) : ProgressInsightEvidence
    data class HeartRateEfficiency(val pacePercent: Int, val heartRateDifference: Int) : ProgressInsightEvidence
    data class LoadRamp(val percent: Int, val current: Double, val previous: Double) : ProgressInsightEvidence
    data class IntensityBalance(val highIntensityPercent: Int) : ProgressInsightEvidence
    data class GoalCompletion(val completed: Int, val total: Int) : ProgressInsightEvidence
    data class PreferredTime(val dayPart: ProgressDayPart, val percent: Int, val total: Int) : ProgressInsightEvidence
}
data class ProgressInsight(
    val id: String,
    val category: ProgressInsightCategory,
    val confidence: ProgressInsightConfidence,
    val symbolName: String,
    val evidence: ProgressInsightEvidence,
)

data class ProgressWeekBucket(
    val startDate: LocalDate,
    val endDateExclusive: LocalDate,
    val activityCount: Int,
    val distanceMeters: Double,
    val durationSeconds: Int,
    val elevationMeters: Double,
)

enum class BestEffortKind { FASTEST_KILOMETER, FASTEST_MILE, FASTEST_FIVE_KILOMETER, LONGEST_RUN, MOST_ELEVATION, BEST_WEEK }
enum class BestEffortSource { ROUTE_WINDOW, WHOLE_ACTIVITY_FALLBACK, ACTIVITY_SUMMARY, WEEKLY_TOTAL }

data class ProgressBestEffort(
    val kind: BestEffortKind,
    val activityId: String?,
    val activityTitle: String?,
    val date: Instant,
    val durationSeconds: Int?,
    val distanceMeters: Double?,
    val elevationMeters: Double?,
    val source: BestEffortSource,
)

data class ProgressPersonalRecord(
    val title: String,
    val targetMeters: Double,
    val effort: ProgressBestEffort,
)

enum class PredictionConfidence { LOW, MEDIUM, HIGH }

data class ProgressRacePrediction(
    val title: String,
    val targetMeters: Double,
    val predictedSeconds: Int,
    val confidence: PredictionConfidence,
)

enum class MomentumKind { SHOWED_UP_TODAY, BACK_AFTER_REST, BUILDING_RHYTHM, SHORT_COUNTS, WEEK_COUNT, KEEP_SIMPLE }
data class ProgressMomentumNote(val kind: MomentumKind, val activityCount: Int = 0)

data class ProgressStatsSnapshot(
    val currentWeek: ProgressPeriodTotals,
    val weeklyBuckets: List<ProgressWeekBucket>,
    val comparisons: List<ProgressPeriodComparison>,
    val trendSeries: List<ProgressTrendSeries>,
    val trainingLoad: ProgressTrainingLoadSnapshot,
    val insights: List<ProgressInsight>,
    val bestEfforts: List<ProgressBestEffort>,
    val personalRecords: List<ProgressPersonalRecord>,
    val racePredictions: List<ProgressRacePrediction>,
    val momentumNote: ProgressMomentumNote?,
    val eligibleActivityCount: Int,
)

interface ProgressRepository {
    suspend fun activities(): List<ProgressActivity>
}
