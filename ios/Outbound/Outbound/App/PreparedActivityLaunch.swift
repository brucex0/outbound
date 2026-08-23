import Foundation

struct PreparedActivityLaunch: Codable, Equatable {
    let sport: SportType
    let goal: ActivityGoal

    func sessionIntent(unitSystem: MeasurementUnitSystem) -> SessionIntent {
        baseIntent.replacingGoal(goal, unitSystem: unitSystem)
    }

    private var baseIntent: SessionIntent {
        switch sport {
        case .run:
            return .freestyleRun
        case .bike:
            return SessionIntent(
                id: "freestyle-bike",
                sport: .bike,
                title: "Freestyle bike",
                detail: "Bike • no preset target",
                guideLine: "Keep it easy at the start, then build into the ride.",
                startLabel: "Start Bike"
            )
        case .walk, .hike, .swim:
            return SessionIntent(
                id: "freestyle-\(sport.rawValue)",
                sport: sport,
                title: String(format: String(localized: "activity.freestyle.title.format", defaultValue: "Freestyle %@"), locale: .autoupdatingCurrent, sport.displayName.lowercased()),
                detail: String(format: String(localized: "activity.freestyle.detail.format", defaultValue: "%@ • no preset target"), locale: .autoupdatingCurrent, sport.displayName),
                guideLine: String(localized: "activity.freestyle.companion", defaultValue: "Start easy and settle into a comfortable rhythm."),
                startLabel: String(format: String(localized: "activity.goal.start.freestyle.format", defaultValue: "Start %@"), locale: .autoupdatingCurrent, sport.displayName)
            )
        }
    }
}

enum PreparedActivityLaunchStore {
    private static let pendingLaunchKey = "prepared_activity_launch_v1"

    static func save(_ launch: PreparedActivityLaunch, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(launch) else { return }
        defaults.set(data, forKey: pendingLaunchKey)
    }

    static func consume(defaults: UserDefaults = .standard) -> PreparedActivityLaunch? {
        guard let data = defaults.data(forKey: pendingLaunchKey),
              let launch = try? JSONDecoder().decode(PreparedActivityLaunch.self, from: data)
        else {
            return nil
        }

        defaults.removeObject(forKey: pendingLaunchKey)
        return launch
    }
}
