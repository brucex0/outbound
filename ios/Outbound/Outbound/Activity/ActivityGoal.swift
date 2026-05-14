import Foundation

enum ActivityGoal: Codable, Hashable {
    case freestyle
    case distanceMeters(Double)
    case timeSeconds(Int)

    private enum Kind: String, Codable {
        case freestyle
        case distance
        case time
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .freestyle:
            self = .freestyle
        case .distance:
            self = .distanceMeters(try container.decode(Double.self, forKey: .value))
        case .time:
            self = .timeSeconds(try container.decode(Int.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .freestyle:
            try container.encode(Kind.freestyle, forKey: .kind)
        case .distanceMeters(let meters):
            try container.encode(Kind.distance, forKey: .kind)
            try container.encode(meters, forKey: .value)
        case .timeSeconds(let seconds):
            try container.encode(Kind.time, forKey: .kind)
            try container.encode(seconds, forKey: .value)
        }
    }

    var isFreestyle: Bool {
        if case .freestyle = self { return true }
        return false
    }

    var targetDistanceMeters: Double? {
        if case .distanceMeters(let meters) = self { return meters }
        return nil
    }

    var targetDurationSeconds: Int? {
        if case .timeSeconds(let seconds) = self { return seconds }
        return nil
    }

    func label(unitSystem: MeasurementUnitSystem) -> String {
        switch self {
        case .freestyle:
            return "Freestyle"
        case .distanceMeters(let meters):
            let value = unitSystem.distanceValue(meters: meters)
            return unitSystem.distanceString(
                meters: meters,
                fractionDigits: value.rounded() == value ? 0 : 1
            )
        case .timeSeconds(let seconds):
            return Self.durationLabel(seconds: seconds)
        }
    }

    func startLabel(for sport: SportType) -> String {
        switch self {
        case .freestyle:
            return "Start \(sport.displayName)"
        case .distanceMeters(let meters):
            return "Start \(Self.metricDistanceLabel(meters: meters)) \(sport.displayName)"
        case .timeSeconds(let seconds):
            return "Start \(Self.durationLabel(seconds: seconds)) \(sport.displayName)"
        }
    }

    func title(for sport: SportType) -> String {
        switch self {
        case .freestyle:
            return "Freestyle \(sport.displayName.lowercased())"
        case .distanceMeters(let meters):
            return "\(Self.metricDistanceLabel(meters: meters)) \(sport.displayName.lowercased())"
        case .timeSeconds(let seconds):
            return "\(Self.durationLabel(seconds: seconds)) \(sport.displayName.lowercased())"
        }
    }

    func detail(for sport: SportType, unitSystem: MeasurementUnitSystem) -> String {
        switch self {
        case .freestyle:
            return "\(sport.displayName) • no preset target"
        case .distanceMeters:
            return "\(sport.displayName) • \(label(unitSystem: unitSystem)) goal"
        case .timeSeconds:
            return "\(sport.displayName) • \(label(unitSystem: unitSystem)) goal"
        }
    }

    private static func metricDistanceLabel(meters: Double) -> String {
        let kilometers = meters / 1000
        if kilometers.rounded() == kilometers {
            return "\(Int(kilometers))K"
        }
        return String(format: "%.1fK", kilometers)
            .replacingOccurrences(of: #"\.0K$"#, with: "K", options: .regularExpression)
    }

    private static func durationLabel(seconds: Int) -> String {
        if seconds < 3600 {
            return "\(max(1, seconds / 60)) min"
        }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return minutes == 0 ? "\(hours) hr" : "\(hours) hr \(minutes) min"
    }
}

extension SessionIntent {
    var activityGoal: ActivityGoal {
        if let distance = resolvedTargetDistanceMeters {
            return .distanceMeters(distance)
        }
        if let duration = resolvedTargetDurationSeconds {
            return .timeSeconds(duration)
        }
        return .freestyle
    }

    func replacingGoal(_ goal: ActivityGoal, unitSystem: MeasurementUnitSystem) -> SessionIntent {
        SessionIntent(
            id: "\(sport.rawValue)-\(goalID(for: goal))",
            sport: sport,
            title: goal.title(for: sport),
            detail: goal.detail(for: sport, unitSystem: unitSystem),
            coachLine: coachLine(for: goal),
            startLabel: goal.startLabel(for: sport),
            targetDistanceMeters: goal.targetDistanceMeters,
            targetDurationSeconds: goal.targetDurationSeconds,
            routeName: nil,
            workoutSteps: []
        )
    }

    private func goalID(for goal: ActivityGoal) -> String {
        switch goal {
        case .freestyle:
            return "freestyle"
        case .distanceMeters(let meters):
            return "distance-\(Int(meters.rounded()))"
        case .timeSeconds(let seconds):
            return "time-\(seconds)"
        }
    }

    private func coachLine(for goal: ActivityGoal) -> String {
        switch goal {
        case .freestyle:
            return "No pressure. Just start where you are."
        case .distanceMeters:
            return "You picked the distance. Settle in, then let the rhythm do its work."
        case .timeSeconds:
            return "You picked the window. Keep it simple and stay present."
        }
    }
}
