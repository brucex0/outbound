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
                coachLine: "Keep it easy at the start, then build into the ride.",
                startLabel: "Start Bike"
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
