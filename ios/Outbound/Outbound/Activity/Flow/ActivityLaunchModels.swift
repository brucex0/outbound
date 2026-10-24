import SwiftUI

enum SessionPage: String {
    case camera
    case map
}

enum ActivitySetupSheet: String, Identifiable {
    case goal
    case music
    case more
    case groupRun

    var id: String { rawValue }

    var title: String {
        switch self {
        case .goal: String(localized: "record.goal.edit", defaultValue: "Edit Goal")
        case .music: String(localized: "record.setup.music", defaultValue: "Music")
        case .more: String(localized: "record.setup.more", defaultValue: "More")
        case .groupRun: String(localized: "record.group.title", defaultValue: "Group run")
        }
    }
}

enum PendingCaloriesWeightAction {
    case selectMode(reopenGoalEditor: Bool)
}

enum ActivityLaunchLayout {
    static let dockHeight: CGFloat = 148
    static let peerCardGap: CGFloat = 12
    static let goalPillRowHeight: CGFloat = 64
    static let controlWidth: CGFloat = 112
    static let controlHeight: CGFloat = 64
}

enum LaunchWorkoutChoice: Hashable, Identifiable {
    case planned
    case sport(SportType)

    static let supportedManualSports: [SportType] = [.run, .walk, .hike, .bike]
    static var allCases: [LaunchWorkoutChoice] {
        [.planned] + supportedManualSports.map(LaunchWorkoutChoice.sport)
    }

    var id: String { analyticsValue }

    var title: String {
        switch self {
        case .planned:
            String(localized: "record.goal.planned", defaultValue: "Planned")
        case .sport(let sport):
            sport.displayName
        }
    }

    var systemImage: String {
        switch self {
        case .planned: "list.bullet.clipboard.fill"
        case .sport(let sport): sport.systemImage
        }
    }

    var analyticsValue: String {
        switch self {
        case .planned: "planned"
        case .sport(let sport): sport.rawValue
        }
    }

    func accessibilityValue(
        plannedIntent: SessionIntent?,
        curatedIntent: SessionIntent?,
        selectedMode: SessionGoalMode,
        manualGoal: ActivityGoal,
        unitSystem: MeasurementUnitSystem
    ) -> String {
        switch self {
        case .planned:
            plannedIntent?.title ?? String(localized: "record.goal.choose_workout", defaultValue: "Choose a workout")
        case .sport(let sport) where selectedMode == .curated && curatedIntent?.sport == sport:
            curatedIntent?.title ?? String(localized: "Curated")
        case .sport:
            manualGoal.label(unitSystem: unitSystem)
        }
    }
}

enum SessionGoalMode: String, CaseIterable, Equatable {
    case planned
    case curated
    case freestyle
    case distance
    case time
    case calories
    case race

    init(goal: ActivityGoal) {
        switch goal {
        case .freestyle:
            self = .freestyle
        case .distanceMeters:
            self = .distance
        case .timeSeconds:
            self = .time
        case .calories:
            self = .calories
        }
    }

    var title: String {
        switch self {
        case .planned:
            return String(localized: "record.goal.planned", defaultValue: "Planned")
        case .curated:
            return String(localized: "Curated")
        case .freestyle:
            return String(localized: "activity.goal.freestyle", defaultValue: "Freestyle")
        case .distance:
            return String(localized: "record.goal.distance", defaultValue: "Distance")
        case .time:
            return String(localized: "record.goal.time", defaultValue: "Time")
        case .calories:
            return String(localized: "record.goal.calories", defaultValue: "Calories")
        case .race:
            return String(localized: "race.planner.mode", defaultValue: "Race")
        }
    }

    static let manualCases: [SessionGoalMode] = [.curated, .race, .freestyle, .distance, .time, .calories]

    var pillTitle: String {
        switch self {
        case .freestyle:
            String(localized: "record.goal.free", defaultValue: "Free")
        case .planned, .curated, .distance, .time, .calories, .race:
            title
        }
    }

    var systemImage: String {
        switch self {
        case .planned: return "list.bullet.clipboard.fill"
        case .curated: return "sparkles.rectangle.stack"
        case .freestyle: return "figure.run"
        case .distance: return "point.topleft.down.to.point.bottomright.curvepath.fill"
        case .time: return "clock.fill"
        case .calories: return "flame.fill"
        case .race: return "flag.checkered"
        }
    }

    var editorTitle: String {
        switch self {
        case .distance:
            return String(localized: "record.goal.distance_picker", defaultValue: "Choose distance")
        case .time:
            return String(localized: "record.goal.time_picker", defaultValue: "Choose time")
        case .calories:
            return String(localized: "record.goal.calories_picker", defaultValue: "Choose calories")
        case .planned:
            return String(localized: "record.goal.choose_workout", defaultValue: "Choose a workout")
        case .curated:
            return String(localized: "record.goal.choose_workout", defaultValue: "Choose a workout")
        case .freestyle:
            return String(localized: "activity.goal.freestyle", defaultValue: "Freestyle")
        case .race:
            return String(localized: "race.planner.title", defaultValue: "Plan this race")
        }
    }

    var customGoalKind: CustomGoalKind? {
        switch self {
        case .distance: return .distance
        case .time: return .time
        case .calories: return .calories
        case .planned, .curated, .freestyle, .race: return nil
        }
    }

    var analyticsValue: String { rawValue }

    func compactValue(goal: ActivityGoal?) -> String {
        switch self {
        case .planned:
            return String(localized: "record.goal.today", defaultValue: "Today")
        case .curated:
            return String(localized: "record.goal.choose_workout", defaultValue: "Choose a workout")
        case .freestyle:
            return String(localized: "record.goal.just_run", defaultValue: "Just run")
        case .distance:
            return goal?.targetDistanceMeters.map { ActivityGoal.distanceMeters($0).label(unitSystem: .metric) }
                ?? String(localized: "record.goal.default_distance", defaultValue: "5 km")
        case .time:
            return goal?.targetDurationSeconds.map { ActivityGoal.timeSeconds($0).label(unitSystem: .metric) }
                ?? String(localized: "record.goal.default_time", defaultValue: "30 min")
        case .calories:
            return goal?.targetCalories.map { ActivityGoal.calories($0).label(unitSystem: .metric) }
                ?? String(localized: "record.goal.default_calories", defaultValue: "300 kcal")
        case .race:
            return String(localized: "race.planner.start", defaultValue: "Plan a race effort")
        }
    }
}

enum CustomGoalKind: Hashable {
    case distance
    case time
    case calories
}
