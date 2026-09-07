package run.plainstride.core.model.activity

import kotlin.math.min
import kotlin.math.roundToInt

enum class CalorieUnavailableReason(val wireValue: String) {
    missingWeight("missing_weight"),
    insufficientDuration("insufficient_duration"),
    missingDistance("missing_distance"),
    implausibleSpeed("implausible_speed"),
}

data class WorkoutCalorieEstimate(
    val kilocalories: Int? = null,
    val unavailableReason: CalorieUnavailableReason? = null,
)

data class PlannedCalorieEstimate(
    val targetCalories: Int,
    val distanceMeters: Double,
    val durationSeconds: Int,
)

data class LearnedRunPace(
    val secondsPerKilometer: Double?,
    val validRunCount: Int,
    val isReliable: Boolean,
)

object WorkoutCalorieEstimator {
    private val validRunPaceRange = 150.0..1_200.0
    private const val DEFAULT_WALKING_SPEED_KILOMETERS_PER_HOUR = 4.8

    fun estimate(activity: ActivityFacts, weightKilograms: Double?): WorkoutCalorieEstimate {
        activity.energyKilocalories?.takeIf { it > 0 }?.let {
            return WorkoutCalorieEstimate(kilocalories = it)
        }
        return estimate(
            activityType = activity.activityType,
            distanceMeters = activity.distanceMeters,
            durationSeconds = activity.durationSeconds,
            elevationGainMeters = activity.elevationGainMeters,
            weightKilograms = weightKilograms,
        )
    }

    fun estimate(
        activityType: ActivityType,
        distanceMeters: Double,
        durationSeconds: Int,
        elevationGainMeters: Double = 0.0,
        weightKilograms: Double?,
    ): WorkoutCalorieEstimate {
        if (weightKilograms == null || !weightKilograms.isFinite() || weightKilograms !in 25.0..350.0) {
            return WorkoutCalorieEstimate(unavailableReason = CalorieUnavailableReason.missingWeight)
        }
        if (durationSeconds !in 300..86_400) {
            return WorkoutCalorieEstimate(unavailableReason = CalorieUnavailableReason.insufficientDuration)
        }
        val minimumDistance = if (activityType == ActivityType.swimming) 50.0 else 100.0
        if (!distanceMeters.isFinite() || distanceMeters < minimumDistance) {
            return WorkoutCalorieEstimate(unavailableReason = CalorieUnavailableReason.missingDistance)
        }
        val durationHours = durationSeconds / 3_600.0
        val speedKilometersPerHour = distanceMeters / 1_000.0 / durationHours
        if (speedKilometersPerHour !in plausibleSpeedRange(activityType)) {
            return WorkoutCalorieEstimate(unavailableReason = CalorieUnavailableReason.implausibleSpeed)
        }
        val levelKilocalories = if (activityType == ActivityType.running) {
            weightKilograms * (distanceMeters / 1_000.0)
        } else {
            metabolicEquivalent(activityType, speedKilometersPerHour) * weightKilograms * durationHours
        }
        val rawKilocalories = levelKilocalories + uphillEnergyKilocalories(
            activityType,
            elevationGainMeters,
            distanceMeters,
            weightKilograms,
        )
        if (!rawKilocalories.isFinite() || rawKilocalories !in 10.0..10_000.0) {
            return WorkoutCalorieEstimate(unavailableReason = CalorieUnavailableReason.implausibleSpeed)
        }
        return WorkoutCalorieEstimate(kilocalories = maxOf(5, (rawKilocalories / 5.0).roundToInt() * 5))
    }

    fun liveEnergyKilocalories(
        activityType: ActivityType,
        distanceMeters: Double,
        durationSeconds: Int,
        elevationGainMeters: Double,
        weightKilograms: Double?,
    ): Double? {
        if (weightKilograms == null || !weightKilograms.isFinite() || weightKilograms !in 25.0..350.0 || durationSeconds <= 0) return null
        val durationHours = durationSeconds / 3_600.0
        val levelKilocalories = when (activityType) {
            ActivityType.running -> if (distanceMeters > 0) weightKilograms * distanceMeters / 1_000.0 else return null
            ActivityType.cycling -> 8.0 * weightKilograms * durationHours
            ActivityType.walking -> {
                if (distanceMeters <= 0) return null
                val speed = distanceMeters / 1_000.0 / durationHours
                val walkingMet = if (speed in plausibleSpeedRange(ActivityType.walking)) metabolicEquivalent(ActivityType.walking, speed) else 3.5
                walkingMet * weightKilograms * durationHours
            }
            ActivityType.hiking, ActivityType.swimming -> 6.0 * weightKilograms * durationHours
        }
        return levelKilocalories + uphillEnergyKilocalories(activityType, elevationGainMeters, distanceMeters, weightKilograms)
    }

    fun resolveLearnedRunPace(activities: List<ActivityFacts>, calibrationCompleted: Boolean): LearnedRunPace {
        val values = activities.asSequence()
            .filter { it.activityType == ActivityType.running }
            .filter { it.distanceMeters >= 500.0 && it.durationSeconds in 300..43_200 }
            .mapNotNull { activity ->
                val pace = activity.averagePaceSecondsPerKilometer
                    ?: (activity.durationSeconds / (activity.distanceMeters / 1_000.0))
                pace.takeIf { it.isFinite() && it in validRunPaceRange }
            }
            .take(10)
            .sorted()
            .toList()
        val reliable = values.size >= 3 || (calibrationCompleted && values.isNotEmpty())
        if (!reliable) return LearnedRunPace(null, values.size, false)
        val middle = values.size / 2
        val pace = if (values.size % 2 == 0) (values[middle - 1] + values[middle]) / 2.0 else values[middle]
        return LearnedRunPace(pace, values.size, true)
    }

    fun plannedRunByCalories(targetCalories: Int, weightKilograms: Double?, paceSecondsPerKilometer: Double?): PlannedCalorieEstimate? {
        if (weightKilograms == null || weightKilograms !in 25.0..350.0 || paceSecondsPerKilometer == null || paceSecondsPerKilometer !in validRunPaceRange || targetCalories <= 0) return null
        val roundedCalories = maxOf(50, (targetCalories / 25.0).roundToInt() * 25)
        val distanceKilometers = roundedCalories / weightKilograms
        return PlannedCalorieEstimate(
            targetCalories = roundedCalories,
            distanceMeters = distanceKilometers * 1_000.0,
            durationSeconds = maxOf(60, (distanceKilometers * paceSecondsPerKilometer).roundToInt()),
        )
    }

    fun plannedRunByDuration(durationSeconds: Int, weightKilograms: Double?, paceSecondsPerKilometer: Double?): PlannedCalorieEstimate? {
        if (weightKilograms == null || paceSecondsPerKilometer == null || durationSeconds <= 0 || paceSecondsPerKilometer !in validRunPaceRange) return null
        val distanceKilometers = durationSeconds / paceSecondsPerKilometer
        return plannedRunByCalories((weightKilograms * distanceKilometers).roundToInt(), weightKilograms, paceSecondsPerKilometer)
    }

    fun plannedWalk(
        targetCalories: Int,
        weightKilograms: Double?,
        speedKilometersPerHour: Double = DEFAULT_WALKING_SPEED_KILOMETERS_PER_HOUR,
    ): PlannedCalorieEstimate? {
        if (weightKilograms == null || weightKilograms !in 25.0..350.0 || targetCalories <= 0 || speedKilometersPerHour !in plausibleSpeedRange(ActivityType.walking)) return null
        val roundedCalories = maxOf(50, (targetCalories / 25.0).roundToInt() * 25)
        val durationHours = roundedCalories / (metabolicEquivalent(ActivityType.walking, speedKilometersPerHour) * weightKilograms)
        return PlannedCalorieEstimate(
            targetCalories = roundedCalories,
            distanceMeters = speedKilometersPerHour * durationHours * 1_000.0,
            durationSeconds = maxOf(60, (durationHours * 3_600.0).roundToInt()),
        )
    }

    private fun plausibleSpeedRange(activityType: ActivityType): ClosedFloatingPointRange<Double> = when (activityType) {
        ActivityType.running -> 4.2..26.0
        ActivityType.cycling -> 5.0..60.0
        ActivityType.walking -> 1.5..9.0
        ActivityType.hiking -> 1.0..10.0
        ActivityType.swimming -> 0.5..8.0
    }

    private fun metabolicEquivalent(activityType: ActivityType, speed: Double): Double = when (activityType) {
        ActivityType.running -> when {
            speed < 6.4 -> 3.3; speed < 6.9 -> 6.5; speed < 8.0 -> 7.8; speed < 8.9 -> 8.5
            speed < 9.7 -> 9.0; speed < 10.8 -> 9.3; speed < 11.3 -> 10.5; speed < 12.1 -> 11.0
            speed < 12.9 -> 11.8; speed < 13.8 -> 12.0; speed < 14.5 -> 12.5; speed < 15.0 -> 13.0
            speed < 17.7 -> 14.8; speed < 19.3 -> 16.8; speed < 20.9 -> 18.5; speed < 22.5 -> 19.8
            else -> 23.0
        }
        ActivityType.cycling -> when { speed < 16.0 -> 4.0; speed < 19.2 -> 6.8; speed < 22.5 -> 8.0; speed < 25.7 -> 10.0; speed < 32.2 -> 12.0; else -> 16.8 }
        ActivityType.walking -> when { speed < 1.9 -> 2.3; speed < 3.2 -> 2.8; speed < 4.0 -> 3.0; speed < 4.8 -> 3.5; speed < 5.6 -> 3.8; speed < 6.4 -> 4.8; speed < 7.2 -> 5.8; speed < 8.0 -> 6.8; else -> 8.3 }
        ActivityType.hiking -> when { speed < 3.2 -> 3.8; speed < 5.6 -> 5.3; else -> 6.0 }
        ActivityType.swimming -> when { speed < 2.5 -> 5.8; speed < 4.1 -> 8.0; else -> 10.5 }
    }

    private fun uphillEnergyKilocalories(
        activityType: ActivityType,
        elevationGainMeters: Double,
        distanceMeters: Double,
        weightKilograms: Double,
    ): Double {
        if (!elevationGainMeters.isFinite() || elevationGainMeters <= 0 || !distanceMeters.isFinite() || distanceMeters <= 0) return 0.0
        val coefficient = when (activityType) {
            ActivityType.running -> 0.0045
            ActivityType.walking, ActivityType.hiking -> 0.009
            ActivityType.cycling -> 9.80665 / (4_184.0 * 0.25)
            ActivityType.swimming -> return 0.0
        }
        return weightKilograms * min(elevationGainMeters, distanceMeters) * coefficient
    }
}
