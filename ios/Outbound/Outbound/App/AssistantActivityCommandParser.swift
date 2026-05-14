import Foundation

enum AssistantActivityCommandParser {
    static func parse(_ transcript: String, unitSystem: MeasurementUnitSystem) -> SessionIntent? {
        let lowercased = transcript.lowercased()
        let hasLaunchVerb = lowercased.contains("start")
            || lowercased.contains("begin")
            || lowercased.contains("launch")
            || lowercased.contains("go for")
            || lowercased.contains(" for ")

        let sport: SportType
        if lowercased.contains("bike") || lowercased.contains("cycle") || lowercased.contains("ride") {
            sport = .bike
        } else if lowercased.contains("run") || lowercased.contains("jog") {
            sport = .run
        } else {
            return nil
        }

        let goal: ActivityGoal
        if let distanceMeters = SessionIntentGoalParser.distanceMeters(from: lowercased) {
            goal = .distanceMeters(distanceMeters)
        } else if let durationSeconds = SessionIntentGoalParser.durationSeconds(from: lowercased) {
            goal = .timeSeconds(durationSeconds)
        } else {
            goal = .freestyle
        }

        guard hasLaunchVerb || !goal.isFreestyle else { return nil }
        return freestyleIntent(for: sport).replacingGoal(goal, unitSystem: unitSystem)
    }

    private static func freestyleIntent(for sport: SportType) -> SessionIntent {
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
