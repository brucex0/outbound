import Foundation

/// Defines when a recorded activity is substantial enough to keep as a saved activity.
nonisolated enum ActivitySaveEligibility: Equatable {
    static let minimumDurationSeconds = 300
    static let minimumDistanceMeters = 500.0

    case eligible
    case tooShort

    static func evaluate(durationSecs: Int, distanceM: Double) -> Self {
        guard durationSecs >= minimumDurationSeconds || distanceM >= minimumDistanceMeters else {
            return .tooShort
        }
        return .eligible
    }
}
