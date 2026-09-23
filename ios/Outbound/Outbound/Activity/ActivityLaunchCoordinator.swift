import Combine

enum ActivityLaunchDecision: Equatable {
    case startImmediately
    case requestPermission
    case waitForLocation
}

enum ActivityLaunchPreflight {
    static func decision(
        isIndoor: Bool,
        permissionGranted: Bool,
        hasRecentValidLocation: Bool
    ) -> ActivityLaunchDecision {
        guard !isIndoor else { return .startImmediately }
        guard permissionGranted else { return .requestPermission }
        return hasRecentValidLocation ? .startImmediately : .waitForLocation
    }
}

/// Owns launch intent and preflight phase without owning the recorder. This
/// keeps permission/GPS decisions testable and reusable by Today and event
/// launches while the session controller owns recording lifecycle.
@MainActor
final class ActivityLaunchCoordinator: ObservableObject {
    enum Phase: Equatable {
        case idle
        case preflighting
        case countdown
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var intent: SessionIntent?

    func prepare(intent: SessionIntent?) {
        self.intent = intent
        if phase != .countdown { phase = .idle }
    }

    func beginPreflight() { phase = .preflighting }
    func beginCountdown() { phase = .countdown }
    func cancel() { phase = .idle }
}
