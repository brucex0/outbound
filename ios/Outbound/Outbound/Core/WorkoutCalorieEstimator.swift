import Foundation

struct WorkoutCalorieEstimate: Equatable, Sendable {
    enum UnavailableReason: String, Sendable {
        case missingWeight = "missing_weight"
        case insufficientDuration = "insufficient_duration"
        case missingDistance = "missing_distance"
        case implausibleSpeed = "implausible_speed"
    }

    let kilocalories: Int?
    let unavailableReason: UnavailableReason?

    static func available(_ kilocalories: Int) -> WorkoutCalorieEstimate {
        WorkoutCalorieEstimate(kilocalories: kilocalories, unavailableReason: nil)
    }

    static func unavailable(_ reason: UnavailableReason) -> WorkoutCalorieEstimate {
        WorkoutCalorieEstimate(kilocalories: nil, unavailableReason: reason)
    }
}

/// Produces a conservative gross-energy estimate from the workout facts the app
/// can verify. Values are calculated on demand so activity edits and newer body
/// weight measurements cannot leave a stale calorie value behind.
enum WorkoutCalorieEstimator {
    static func estimate(
        for activity: SavedActivity,
        weightKilograms: Double?
    ) -> WorkoutCalorieEstimate {
        estimate(
            activityType: activity.activityType,
            distanceMeters: activity.distanceM,
            durationSeconds: activity.durationSecs,
            weightKilograms: weightKilograms
        )
    }

    static func estimate(
        for summary: ActivitySummary,
        activityType: ActivityType,
        weightKilograms: Double?
    ) -> WorkoutCalorieEstimate {
        estimate(
            activityType: activityType,
            distanceMeters: summary.distanceM,
            durationSeconds: summary.durationSecs,
            weightKilograms: weightKilograms
        )
    }

    static func estimate(
        activityType: ActivityType,
        distanceMeters: Double,
        durationSeconds: Int,
        weightKilograms: Double?
    ) -> WorkoutCalorieEstimate {
        guard let weightKilograms,
              weightKilograms.isFinite,
              (25...350).contains(weightKilograms)
        else {
            return .unavailable(.missingWeight)
        }

        // Short samples are too sensitive to GPS warm-up and rounding to present
        // as a completed-workout estimate.
        guard (5 * 60...24 * 60 * 60).contains(durationSeconds) else {
            return .unavailable(.insufficientDuration)
        }

        let minimumDistance = activityType == .swimming ? 50.0 : 100.0
        guard distanceMeters.isFinite, distanceMeters >= minimumDistance else {
            return .unavailable(.missingDistance)
        }

        let durationHours = Double(durationSeconds) / 3_600
        let speedKilometersPerHour = (distanceMeters / 1_000) / durationHours
        guard plausibleSpeedRange(for: activityType).contains(speedKilometersPerHour) else {
            return .unavailable(.implausibleSpeed)
        }

        let rawKilocalories = metabolicEquivalent(
            for: activityType,
            speedKilometersPerHour: speedKilometersPerHour
        ) * weightKilograms * durationHours

        guard rawKilocalories.isFinite, rawKilocalories >= 10, rawKilocalories <= 10_000 else {
            return .unavailable(.implausibleSpeed)
        }

        // Five-calorie increments communicate the estimate without implying
        // precision that the available workout inputs cannot support.
        return .available(max(5, Int((rawKilocalories / 5).rounded()) * 5))
    }

    static func calorieValue(_ kilocalories: Int) -> String {
        String(
            format: String(localized: "activity.calories.value.format", defaultValue: "%d cal"),
            locale: .autoupdatingCurrent,
            kilocalories
        )
    }

    static func durationAndCalorieLine(
        durationSeconds: Int,
        kilocalories: Int?
    ) -> String {
        let minutes = max(1, Int((Double(durationSeconds) / 60).rounded()))
        if let kilocalories {
            return String(
                format: String(
                    localized: "activity.completed.duration_calories.format",
                    defaultValue: "%d min · %d cal"
                ),
                locale: .autoupdatingCurrent,
                minutes,
                kilocalories
            )
        }
        return String(
            format: String(localized: "activity.completed.duration.format", defaultValue: "%d min"),
            locale: .autoupdatingCurrent,
            minutes
        )
    }

    private static func plausibleSpeedRange(for activityType: ActivityType) -> ClosedRange<Double> {
        switch activityType {
        case .running: 4.2...26
        case .cycling: 5...60
        case .walking: 1.5...9
        case .hiking: 1...10
        case .swimming: 0.5...8
        }
    }

    private static func metabolicEquivalent(
        for activityType: ActivityType,
        speedKilometersPerHour: Double
    ) -> Double {
        // Speed bands use the 2024 Adult Compendium of Physical Activities.
        // One MET is approximately one kilocalorie per kilogram per hour.
        switch activityType {
        case .running:
            switch speedKilometersPerHour {
            case ..<6.4: 3.3
            case ..<6.9: 6.5
            case ..<8.0: 7.8
            case ..<8.9: 8.5
            case ..<9.7: 9.0
            case ..<10.8: 9.3
            case ..<11.3: 10.5
            case ..<12.1: 11.0
            case ..<12.9: 11.8
            case ..<13.8: 12.0
            case ..<14.5: 12.5
            case ..<15.0: 13.0
            case ..<17.7: 14.8
            case ..<19.3: 16.8
            case ..<20.9: 18.5
            case ..<22.5: 19.8
            default: 23.0
            }
        case .cycling:
            switch speedKilometersPerHour {
            case ..<16: 4.0
            case ..<19.2: 6.8
            case ..<22.5: 8.0
            case ..<25.7: 10.0
            case ..<32.2: 12.0
            default: 16.8
            }
        case .walking:
            switch speedKilometersPerHour {
            case ..<1.9: 2.3
            case ..<3.2: 2.8
            case ..<4.0: 3.0
            case ..<4.8: 3.5
            case ..<5.6: 3.8
            case ..<6.4: 4.8
            case ..<7.2: 5.8
            case ..<8.0: 6.8
            default: 8.3
            }
        case .hiking:
            switch speedKilometersPerHour {
            case ..<3.2: 3.8
            case ..<5.6: 5.3
            default: 6.0
            }
        case .swimming:
            switch speedKilometersPerHour {
            case ..<2.5: 5.8
            case ..<4.1: 8.0
            default: 10.5
            }
        }
    }
}
