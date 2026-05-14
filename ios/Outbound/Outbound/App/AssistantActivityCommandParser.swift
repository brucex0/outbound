import Foundation

enum AssistantActivityCommandParser {
    static func parse(_ transcript: String, unitSystem: MeasurementUnitSystem) -> SessionIntent? {
        let lowercased = normalized(transcript)
        let hasLaunchVerb = lowercased.contains("start")
            || lowercased.contains("begin")
            || lowercased.contains("launch")
            || lowercased.contains("go for")
            || lowercased.contains(" for ")
            || lowercased.contains("do a")
            || lowercased.contains("set up")

        let sport: SportType
        if lowercased.contains("bike")
            || lowercased.contains("biking")
            || lowercased.contains("cycle")
            || lowercased.contains("cycling")
            || lowercased.contains("ride") {
            sport = .bike
        } else if lowercased.contains("run")
            || lowercased.contains("running")
            || lowercased.contains("jog") {
            sport = .run
        } else if hasLaunchVerb,
                  SessionIntentGoalParser.distanceMeters(from: lowercased) != nil {
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

    static let recognitionHints: [String] = [
        "start a run",
        "start a bike",
        "start a 5K run",
        "start a 10K run",
        "start a 3K run",
        "start a 20 minute run",
        "start a 30 minute run",
        "start a 45 minute run",
        "bike for 30 minutes",
        "bike for 45 minutes",
        "ride for 30 minutes",
        "go for a run",
        "go for a bike ride",
        "5K",
        "10K",
        "kilometers",
        "minutes"
    ]

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

    private static func normalized(_ transcript: String) -> String {
        var text = transcript
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "kay", with: " k")
            .replacingOccurrences(of: "okay", with: " k")
            .replacingOccurrences(of: "kays", with: " k")
            .replacingOccurrences(of: "case", with: " k")
            .replacingOccurrences(of: "can run", with: "k run")
            .replacingOccurrences(of: "came run", with: "k run")
            .replacingOccurrences(of: "come run", with: "k run")
            .replacingOccurrences(of: "half an hour", with: "30 minutes")
            .replacingOccurrences(of: "half hour", with: "30 minutes")
            .replacingOccurrences(of: "an hour", with: "1 hour")
            .replacingOccurrences(of: "one hour", with: "1 hour")

        let wordNumbers: [(String, String)] = [
            ("forty five", "45"),
            ("fourty five", "45"),
            ("thirty five", "35"),
            ("twenty five", "25"),
            ("twenty", "20"),
            ("thirty", "30"),
            ("forty", "40"),
            ("fourty", "40"),
            ("fifty", "50"),
            ("sixty", "60"),
            ("fifteen", "15"),
            ("ten", "10"),
            ("eleven", "11"),
            ("twelve", "12"),
            ("thirteen", "13"),
            ("fourteen", "14"),
            ("sixteen", "16"),
            ("seventeen", "17"),
            ("eighteen", "18"),
            ("nineteen", "19"),
            ("one", "1"),
            ("two", "2"),
            ("three", "3"),
            ("four", "4"),
            ("five", "5"),
            ("six", "6"),
            ("seven", "7"),
            ("eight", "8"),
            ("nine", "9")
        ]

        for (word, number) in wordNumbers {
            text = text.replacingOccurrences(
                of: #"(?<![a-z])\#(word)(?![a-z])"#,
                with: number,
                options: .regularExpression
            )
        }

        return text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
