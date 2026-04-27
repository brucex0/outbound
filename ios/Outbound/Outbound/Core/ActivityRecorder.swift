import Foundation
import Combine
import CoreLocation

enum RecordingState {
    case idle, active, paused
}

@MainActor
final class ActivityRecorder: ObservableObject {
    @Published var state: RecordingState = .idle
    @Published var elapsedSeconds: Int = 0
    @Published var distanceMeters: Double = 0
    @Published var currentPace: Double?   // secs/km
    @Published var heartRate: Int?

    let locationManager: LocationManager
    private var timer: AnyCancellable?
    private var startDate: Date?

    init(locationManager: LocationManager) {
        self.locationManager = locationManager
    }

    func start() {
        state = .active
        startDate = Date()
        elapsedSeconds = 0
        distanceMeters = 0
        currentPace = nil
        heartRate = nil
        locationManager.startTracking()
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    func pause() {
        state = .paused
        timer?.cancel()
    }

    func resume() {
        state = .active
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    func finish() -> ActivitySummary {
        state = .idle
        timer?.cancel()
        let track = locationManager.stopTracking()
        return ActivitySummary(
            startedAt: startDate ?? Date(),
            endedAt: Date(),
            durationSecs: elapsedSeconds,
            distanceM: distanceMeters,
            avgPace: distanceMeters > 0 ? Double(elapsedSeconds) / (distanceMeters / 1000) : nil,
            trackPoints: track
        )
    }

    private func tick() {
        elapsedSeconds += 1
        distanceMeters = locationManager.totalDistanceMeters
        currentPace = locationManager.currentPaceSecsPerKm
    }
}

struct ActivitySummary {
    let startedAt: Date
    let endedAt: Date
    let durationSecs: Int
    let distanceM: Double
    let avgPace: Double?
    let trackPoints: [CLLocation]
}
