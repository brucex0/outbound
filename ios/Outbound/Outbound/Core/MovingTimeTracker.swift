import Foundation

/// Conservative stop accounting, independent of the recording pause controls.
/// Unknown/stale observations and background gaps count as moving time.
nonisolated struct MovingTimeTracker: Codable, Sendable {
    private(set) var stoppedSeconds: Double = 0
    private var candidateSeconds: Double = 0
    private var lastActiveSeconds: Double?

    mutating func update(activeSeconds: Double, stationary: Bool?) {
        defer { lastActiveSeconds = activeSeconds }
        guard let previous = lastActiveSeconds else { return }
        let delta = activeSeconds - previous
        guard delta >= 0, delta <= 5, stationary == true else {
            candidateSeconds = 0
            return
        }
        let previousCandidate = candidateSeconds
        candidateSeconds += delta
        if candidateSeconds >= 10 {
            stoppedSeconds += previousCandidate < 10 ? candidateSeconds : delta
        }
    }

    mutating func suspend() {
        candidateSeconds = 0
        lastActiveSeconds = nil
    }

    func movingSeconds(activeSeconds: Int) -> Int {
        max(0, activeSeconds - Int(stoppedSeconds.rounded(.down)))
    }
}
