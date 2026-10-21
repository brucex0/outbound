import Foundation

/// Stop accounting follows GPS observation time, independently of UI timer delivery.
/// A stationary cluster must persist for 20 seconds; uncertain gaps remain moving.
nonisolated struct MovingTimeTracker: Codable, Sendable {
    private(set) var stoppedSeconds: Double = 0
    private var candidateSeconds: Double = 0
    private var lastActiveSeconds: Double?
    private var anchor: Position?
    private var isEnabled: Bool?

    init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }

    mutating func observe(
        activeSeconds: Double,
        latitude: Double,
        longitude: Double,
        horizontalAccuracy: Double,
        speed: Double?,
        speedAccuracy: Double?,
        stationarySpeedThreshold: Double
    ) {
        guard isEnabled != false, activeSeconds.isFinite, activeSeconds >= 0 else { return }
        // Batched callbacks can contain duplicates or fixes preceding the last one.
        if let previous = lastActiveSeconds, activeSeconds <= previous { return }
        defer { lastActiveSeconds = activeSeconds }
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude),
              (0...20).contains(horizontalAccuracy) else {
            clearCandidate()
            return
        }
        let position = Position(latitude: latitude, longitude: longitude)
        guard let previous = lastActiveSeconds, let anchor,
              activeSeconds - previous <= 30 else {
            clearCandidate()
            self.anchor = position
            return
        }
        let minimumNativeSpeed = speed.flatMap { value -> Double? in
            guard value.isFinite, value >= 0, let speedAccuracy,
                  (0...3).contains(speedAccuracy) else { return nil }
            return max(0, value - speedAccuracy)
        }
        // Keep the anchor fixed throughout a candidate, so small increments on a
        // slow climb accumulate rather than repeatedly looking like a stop.
        if position.distance(from: anchor) >= 3 || minimumNativeSpeed.map({ $0 > stationarySpeedThreshold }) == true {
            clearCandidate()
            self.anchor = position
            return
        }
        let delta = activeSeconds - previous
        let previousCandidate = candidateSeconds
        candidateSeconds += delta
        if candidateSeconds >= 20 {
            stoppedSeconds += previousCandidate < 20 ? candidateSeconds : delta
        }
    }

    private mutating func clearCandidate() {
        candidateSeconds = 0
        anchor = nil
    }

    mutating func suspend() {
        clearCandidate()
        lastActiveSeconds = nil
    }

    func movingSeconds(activeSeconds: Int) -> Int {
        max(0, activeSeconds - Int(stoppedSeconds.rounded(.down)))
    }

    private struct Position: Codable, Sendable {
        let latitude: Double
        let longitude: Double

        func distance(from other: Position) -> Double {
            let radians = Double.pi / 180
            let dLat = (latitude - other.latitude) * radians
            let dLon = (longitude - other.longitude) * radians
            let a = pow(sin(dLat / 2), 2)
                + cos(latitude * radians) * cos(other.latitude * radians) * pow(sin(dLon / 2), 2)
            return 6_371_000 * 2 * asin(sqrt(min(1, max(0, a))))
        }
    }
}
