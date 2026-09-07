package run.plainstride.feature.progress

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
    val averagePaceSecondsPerKilometer: Double?
        get() = if (distanceMeters > 0 && durationSeconds > 0) durationSeconds / (distanceMeters / 1_000.0) else null
}

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
    val bestEfforts: List<ProgressBestEffort>,
    val personalRecords: List<ProgressPersonalRecord>,
    val racePredictions: List<ProgressRacePrediction>,
    val momentumNote: ProgressMomentumNote?,
    val eligibleActivityCount: Int,
)

interface ProgressRepository {
    suspend fun activities(): List<ProgressActivity>
}
