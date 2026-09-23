import Combine
import SwiftUI

/// The lifecycle boundary between launch UI and the existing recording,
/// guidance, sharing, and persistence services. It intentionally does not
/// replace those domain owners; it coordinates their phase and immutable
/// session intent for host views.
@MainActor
final class ActivitySessionController: ObservableObject {
    enum Phase: Equatable {
        case setup
        case preflighting
        case countdown
        case recording(RecordingState)
        case review
        case saving
        case postSave

        var isLive: Bool {
            switch self {
            case .recording(.active), .recording(.paused): true
            default: false
            }
        }

        var portalState: ActivitySessionPortalState {
            switch self {
            case .recording(.active): .active
            case .recording(.paused): .paused
            default: .idle
            }
        }
    }

    @Published private(set) var phase: Phase = .setup
    @Published private(set) var preparedIntent: SessionIntent?
    @Published var mapSafeZone = ActivityMapSafeZone.zero

    var isIdle: Bool {
        switch phase {
        case .setup, .preflighting, .countdown: true
        default: false
        }
    }

    func prepare(intent: SessionIntent?) {
        preparedIntent = intent
        if !phase.isLive { phase = .setup }
    }

    func beginPreflight() {
        guard phase == .setup else { return }
        phase = .preflighting
    }

    func beginCountdown() {
        guard phase == .preflighting || phase == .setup else { return }
        phase = .countdown
    }

    func beginRecording() {
        phase = .recording(.active)
    }

    func pause() {
        guard case .recording(.active) = phase else { return }
        phase = .recording(.paused)
    }

    func resume() {
        guard case .recording(.paused) = phase else { return }
        phase = .recording(.active)
    }

    func beginReview() {
        phase = .review
    }

    func beginSaving() {
        guard phase == .review else { return }
        phase = .saving
    }

    func completeSave(withPostSaveFlow: Bool) {
        phase = withPostSaveFlow ? .postSave : .setup
        if !withPostSaveFlow { preparedIntent = nil }
    }

    func saveFailed() {
        phase = .review
    }

    func reset() {
        phase = .setup
        preparedIntent = nil
        mapSafeZone = .zero
    }
}
