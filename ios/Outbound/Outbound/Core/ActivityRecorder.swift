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
    @Published var liveSnapshot: ActiveSessionSnapshot = .empty

    let locationManager: LocationManager
    private var timer: AnyCancellable?
    private var startDate: Date?

    init(locationManager: LocationManager) {
        self.locationManager = locationManager
    }

    func start() {
        timer?.cancel()
        state = .active
        startDate = Date()
        elapsedSeconds = 0
        distanceMeters = 0
        currentPace = nil
        heartRate = nil
        locationManager.startTracking()
        liveSnapshot = makeSnapshot()
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    func pause() {
        guard state == .active else { return }
        state = .paused
        timer?.cancel()
        locationManager.pauseTracking()
        liveSnapshot = makeSnapshot()
    }

    func resume() {
        guard state == .paused else { return }
        state = .active
        locationManager.resumeTracking()
        liveSnapshot = makeSnapshot()
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    func finish() -> ActivitySummary {
        state = .idle
        timer?.cancel()
        let track = locationManager.stopTracking()
        let summary = ActivitySummary(
            startedAt: startDate ?? Date(),
            endedAt: Date(),
            durationSecs: elapsedSeconds,
            distanceM: distanceMeters,
            avgPace: distanceMeters > 0 ? Double(elapsedSeconds) / (distanceMeters / 1000) : nil,
            trackPoints: track
        )
        liveSnapshot = makeSnapshot(isActive: false)
        startDate = nil
        return summary
    }

    private func tick() {
        guard state == .active else { return }
        elapsedSeconds += 1
        distanceMeters = locationManager.totalDistanceMeters
        currentPace = locationManager.currentPaceSecsPerKm
        liveSnapshot = makeSnapshot()
    }

    private func makeSnapshot(isActive: Bool? = nil) -> ActiveSessionSnapshot {
        ActiveSessionSnapshot(
            recordedAt: Date(),
            startedAt: startDate,
            elapsedSeconds: elapsedSeconds,
            distanceMeters: distanceMeters,
            currentPaceSecsPerKm: currentPace,
            heartRate: heartRate,
            location: locationManager.location.map(SessionLocation.init),
            isActive: isActive ?? (state == .active)
        )
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
