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

struct PlannedCalorieEstimate: Equatable, Sendable {
    let targetCalories: Int
    let distanceMeters: Double
    let durationSeconds: Int
}

struct LearnedRunPace: Equatable, Sendable {
    let secondsPerKilometer: Double?
    let validRunCount: Int
    let isReliable: Bool
}

/// Produces a conservative gross-energy estimate from the workout facts the app
/// can verify. Values are calculated on demand so activity edits and newer body
/// weight measurements cannot leave a stale calorie value behind.
enum WorkoutCalorieEstimator {
    private static let validRunPaceRange = 150.0...1_200.0
    private static let defaultWalkingSpeedKilometersPerHour = 4.8

    static func estimate(
        for activity: SavedActivity,
        weightKilograms: Double?
    ) -> WorkoutCalorieEstimate {
        if let energyKilocalories = activity.energyKilocalories, energyKilocalories > 0 {
            return .available(energyKilocalories)
        }
        return estimate(
            activityType: activity.activityType,
            distanceMeters: activity.distanceM,
            durationSeconds: activity.durationSecs,
            elevationGainMeters: activity.elevationGainM ?? 0,
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
            elevationGainMeters: summary.elevationGainM,
            weightKilograms: weightKilograms
        )
    }

    static func estimate(
        activityType: ActivityType,
        distanceMeters: Double,
        durationSeconds: Int,
        elevationGainMeters: Double = 0,
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

        let levelKilocalories: Double
        if activityType == .running {
            levelKilocalories = weightKilograms * (distanceMeters / 1_000)
        } else {
            levelKilocalories = metabolicEquivalent(
                for: activityType,
                speedKilometersPerHour: speedKilometersPerHour
            ) * weightKilograms * durationHours
        }
        let rawKilocalories = levelKilocalories + uphillEnergyKilocalories(
            activityType: activityType,
            elevationGainMeters: elevationGainMeters,
            distanceMeters: distanceMeters,
            weightKilograms: weightKilograms
        )

        guard rawKilocalories.isFinite, rawKilocalories >= 10, rawKilocalories <= 10_000 else {
            return .unavailable(.implausibleSpeed)
        }

        // Five-calorie increments communicate the estimate without implying
        // precision that the available workout inputs cannot support.
        return .available(max(5, Int((rawKilocalories / 5).rounded()) * 5))
    }

    static func liveEnergyKilocalories(
        activityType: ActivityType,
        distanceMeters: Double,
        durationSeconds: Int,
        elevationGainMeters: Double,
        weightKilograms: Double?
    ) -> Double? {
        guard let weightKilograms,
              weightKilograms.isFinite,
              (25...350).contains(weightKilograms),
              durationSeconds > 0 else { return nil }
        let levelKilocalories: Double
        switch activityType {
        case .running:
            guard distanceMeters > 0 else { return nil }
            levelKilocalories = weightKilograms * (distanceMeters / 1_000)
        case .cycling:
            levelKilocalories = 8 * weightKilograms * (Double(durationSeconds) / 3_600)
        case .walking:
            guard distanceMeters > 0 else { return nil }
            let durationHours = Double(durationSeconds) / 3_600
            let speedKilometersPerHour = (distanceMeters / 1_000) / durationHours
            let walkingMET = plausibleSpeedRange(for: .walking).contains(speedKilometersPerHour)
                ? metabolicEquivalent(for: .walking, speedKilometersPerHour: speedKilometersPerHour)
                : 3.5
            levelKilocalories = walkingMET * weightKilograms * durationHours
        case .hiking, .swimming:
            levelKilocalories = 6 * weightKilograms * (Double(durationSeconds) / 3_600)
        }
        return levelKilocalories + uphillEnergyKilocalories(
            activityType: activityType,
            elevationGainMeters: elevationGainMeters,
            distanceMeters: distanceMeters,
            weightKilograms: weightKilograms
        )
    }

    static func resolveLearnedRunPace(
        activities: [SavedActivity],
        calibrationCompleted: Bool
    ) -> LearnedRunPace {
        let values = activities
            .filter { $0.activityType == .running }
            .filter { $0.distanceM >= 500 && (5 * 60...12 * 60 * 60).contains($0.durationSecs) }
            .compactMap { activity -> Double? in
                let pace = activity.avgPace ?? Double(activity.durationSecs) / (activity.distanceM / 1_000)
                return pace.isFinite && validRunPaceRange.contains(pace) ? pace : nil
            }
            .prefix(10)
            .sorted()
        let reliable = values.count >= 3 || (calibrationCompleted && !values.isEmpty)
        guard reliable else {
            return LearnedRunPace(secondsPerKilometer: nil, validRunCount: values.count, isReliable: false)
        }
        let middle = values.count / 2
        let pace = values.count.isMultiple(of: 2)
            ? (values[middle - 1] + values[middle]) / 2
            : values[middle]
        return LearnedRunPace(secondsPerKilometer: pace, validRunCount: values.count, isReliable: true)
    }

    static func plannedRun(
        targetCalories: Int,
        weightKilograms: Double?,
        paceSecondsPerKilometer: Double?
    ) -> PlannedCalorieEstimate? {
        guard let weightKilograms,
              (25...350).contains(weightKilograms),
              let paceSecondsPerKilometer,
              validRunPaceRange.contains(paceSecondsPerKilometer),
              targetCalories > 0 else { return nil }
        let roundedCalories = max(50, Int((Double(targetCalories) / 25).rounded()) * 25)
        let distanceKilometers = Double(roundedCalories) / weightKilograms
        return PlannedCalorieEstimate(
            targetCalories: roundedCalories,
            distanceMeters: distanceKilometers * 1_000,
            durationSeconds: max(60, Int((distanceKilometers * paceSecondsPerKilometer).rounded()))
        )
    }

    static func plannedRun(
        durationSeconds: Int,
        weightKilograms: Double?,
        paceSecondsPerKilometer: Double?
    ) -> PlannedCalorieEstimate? {
        guard let weightKilograms,
              let paceSecondsPerKilometer,
              durationSeconds > 0,
              validRunPaceRange.contains(paceSecondsPerKilometer) else { return nil }
        let distanceKilometers = Double(durationSeconds) / paceSecondsPerKilometer
        return plannedRun(
            targetCalories: Int((weightKilograms * distanceKilometers).rounded()),
            weightKilograms: weightKilograms,
            paceSecondsPerKilometer: paceSecondsPerKilometer
        )
    }

    static func plannedWalk(
        targetCalories: Int,
        weightKilograms: Double?,
        speedKilometersPerHour: Double = defaultWalkingSpeedKilometersPerHour
    ) -> PlannedCalorieEstimate? {
        guard let weightKilograms,
              (25...350).contains(weightKilograms),
              targetCalories > 0,
              plausibleSpeedRange(for: .walking).contains(speedKilometersPerHour)
        else { return nil }

        let roundedCalories = max(50, Int((Double(targetCalories) / 25).rounded()) * 25)
        let metabolicEquivalent = metabolicEquivalent(
            for: .walking,
            speedKilometersPerHour: speedKilometersPerHour
        )
        let durationHours = Double(roundedCalories) / (metabolicEquivalent * weightKilograms)
        return PlannedCalorieEstimate(
            targetCalories: roundedCalories,
            distanceMeters: speedKilometersPerHour * durationHours * 1_000,
            durationSeconds: max(60, Int((durationHours * 3_600).rounded()))
        )
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

    private static func uphillEnergyKilocalories(
        activityType: ActivityType,
        elevationGainMeters: Double,
        distanceMeters: Double,
        weightKilograms: Double
    ) -> Double {
        guard elevationGainMeters.isFinite,
              elevationGainMeters > 0,
              distanceMeters.isFinite,
              distanceMeters > 0
        else { return 0 }

        // The level-work formulas do not account for climbing. These coefficients
        // integrate the uphill term in the ACSM walking/running metabolic equations;
        // cycling uses gravitational work at 25% mechanical efficiency. Elevation is
        // capped by traveled distance as a final guard against bad altitude samples.
        let kilocaloriesPerKilogramMeter: Double
        switch activityType {
        case .running:
            kilocaloriesPerKilogramMeter = 0.0045
        case .walking, .hiking:
            kilocaloriesPerKilogramMeter = 0.009
        case .cycling:
            kilocaloriesPerKilogramMeter = 9.80665 / (4_184 * 0.25)
        case .swimming:
            return 0
        }
        return weightKilograms
            * min(elevationGainMeters, distanceMeters)
            * kilocaloriesPerKilogramMeter
    }
}
