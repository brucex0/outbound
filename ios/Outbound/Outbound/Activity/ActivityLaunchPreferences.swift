import Combine
import Foundation

struct ActivityManualSetupDraft: Equatable {
    var selectedMode: SessionGoalMode
    var distanceMeters: Double?
    var timeSeconds: Int?
    var calories: Int?

    init(preference: ActivitySportLaunchPreference = .init()) {
        selectedMode = preference.preferredGoalMode ?? .freestyle
        distanceMeters = preference.distanceMeters
        timeSeconds = preference.timeSeconds
        calories = preference.calories
    }

    mutating func remember(_ goal: ActivityGoal) {
        selectedMode = SessionGoalMode(goal: goal)
        switch goal {
        case .freestyle:
            break
        case .distanceMeters(let meters):
            distanceMeters = meters
        case .timeSeconds(let seconds):
            timeSeconds = seconds
        case .calories(let calories):
            self.calories = calories
        }
    }

    func goal(
        for mode: SessionGoalMode,
        defaultDistanceMeters: Double,
        defaultTimeSeconds: Int,
        defaultCalories: Int
    ) -> ActivityGoal {
        switch mode {
        case .freestyle, .planned, .curated, .race:
            return .freestyle
        case .distance:
            return .distanceMeters(distanceMeters ?? defaultDistanceMeters)
        case .time:
            return .timeSeconds(timeSeconds ?? defaultTimeSeconds)
        case .calories:
            return .calories(calories ?? defaultCalories)
        }
    }
}

struct ActivitySportLaunchPreference: Codable, Equatable {
    var preferredGoalModeRawValue: String?
    var goalModeStartHistory: [String] = []
    var distanceMeters: Double?
    var timeSeconds: Int?
    var calories: Int?

    var preferredGoalMode: SessionGoalMode? {
        guard let preferredGoalModeRawValue,
              let mode = SessionGoalMode(rawValue: preferredGoalModeRawValue),
              mode.isLearnableManualMode else {
            return nil
        }
        return mode
    }

    func goal(for mode: SessionGoalMode) -> ActivityGoal? {
        switch mode {
        case .distance:
            return distanceMeters.map(ActivityGoal.distanceMeters)
        case .time:
            return timeSeconds.map(ActivityGoal.timeSeconds)
        case .calories:
            return calories.map(ActivityGoal.calories)
        case .freestyle:
            return .freestyle
        case .planned, .curated, .race:
            return nil
        }
    }

    mutating func rememberTarget(_ goal: ActivityGoal) {
        switch goal {
        case .freestyle:
            break
        case .distanceMeters(let meters) where meters.isFinite && meters > 0:
            distanceMeters = meters
        case .timeSeconds(let seconds) where seconds > 0:
            timeSeconds = seconds
        case .calories(let calories) where calories > 0:
            self.calories = calories
        case .distanceMeters, .timeSeconds, .calories:
            break
        }
    }
}

private struct ActivityLaunchPreferenceSnapshot: Codable {
    var version = 1
    var lastManualSportRawValue: String?
    var sports: [String: ActivitySportLaunchPreference] = [:]
}

struct ActivityLaunchPreferenceChanges: Equatable {
    var didChangeSport = false
    var didChangeTarget = false
    var didLearnGoalMode = false
}

@MainActor
final class ActivityLaunchPreferenceStore: ObservableObject {
    private var snapshot: ActivityLaunchPreferenceSnapshot
    private let defaults: UserDefaults
    private let storageKey: String

    init(
        userID: String?,
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        self.storageKey = userID.map { "activity_launch_preferences_v1_account_\($0)" }
            ?? "activity_launch_preferences_v1"
        self.snapshot = defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode(ActivityLaunchPreferenceSnapshot.self, from: $0) }
            ?? ActivityLaunchPreferenceSnapshot()
    }

    var lastManualSport: SportType? {
        snapshot.lastManualSportRawValue.flatMap(SportType.init(rawValue:))
    }

    func draft(for sport: SportType) -> ActivityManualSetupDraft {
        ActivityManualSetupDraft(preference: preference(for: sport))
    }

    func preferredGoalMode(for sport: SportType) -> SessionGoalMode? {
        preference(for: sport).preferredGoalMode
    }

    func recordStarted(
        sport: SportType,
        mode: SessionGoalMode,
        goal: ActivityGoal
    ) -> ActivityLaunchPreferenceChanges {
        guard mode.isLearnableManualMode else { return .init() }

        var changes = ActivityLaunchPreferenceChanges()
        if snapshot.lastManualSportRawValue != sport.rawValue {
            snapshot.lastManualSportRawValue = sport.rawValue
            changes.didChangeSport = true
        }

        var sportPreference = preference(for: sport)
        let previousGoal = sportPreference.goal(for: mode)
        sportPreference.rememberTarget(goal)
        changes.didChangeTarget = previousGoal != sportPreference.goal(for: mode)

        sportPreference.goalModeStartHistory.append(mode.rawValue)
        sportPreference.goalModeStartHistory = Array(sportPreference.goalModeStartHistory.suffix(3))
        if sportPreference.goalModeStartHistory.count == 3,
           sportPreference.goalModeStartHistory.allSatisfy({ $0 == mode.rawValue }),
           sportPreference.preferredGoalModeRawValue != mode.rawValue {
            sportPreference.preferredGoalModeRawValue = mode.rawValue
            changes.didLearnGoalMode = true
        }

        snapshot.sports[sport.rawValue] = sportPreference
        persist()
        return changes
    }

    private func preference(for sport: SportType) -> ActivitySportLaunchPreference {
        snapshot.sports[sport.rawValue] ?? ActivitySportLaunchPreference()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

extension SessionGoalMode {
    var isLearnableManualMode: Bool {
        switch self {
        case .freestyle, .distance, .time, .calories:
            return true
        case .planned, .curated, .race:
            return false
        }
    }
}
