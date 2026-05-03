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
    @Published var elevationGainMeters: Double = 0
    @Published var currentPace: Double?   // secs/km
    @Published var heartRate: Int?
    @Published var liveSnapshot: ActiveSessionSnapshot = .empty

    let locationManager: LocationManager
    private var timer: AnyCancellable?
    private var locationCancellable: AnyCancellable?
    private var startDate: Date?
    private var currentSegmentStartDate: Date?
    private var accumulatedActiveDuration: TimeInterval = 0

    init(locationManager: LocationManager) {
        self.locationManager = locationManager
        locationCancellable = locationManager.$location.sink { [weak self] _ in
            self?.handleLocationUpdate()
        }
    }

    func start() {
        timer?.cancel()
        let now = Date()
        state = .active
        startDate = now
        currentSegmentStartDate = now
        accumulatedActiveDuration = 0
        elapsedSeconds = 0
        distanceMeters = 0
        elevationGainMeters = 0
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
        updateSessionMetrics(now: Date())
        state = .paused
        accumulatedActiveDuration = TimeInterval(elapsedSeconds)
        currentSegmentStartDate = nil
        timer?.cancel()
        locationManager.pauseTracking()
        liveSnapshot = makeSnapshot()
    }

    func resume() {
        guard state == .paused else { return }
        state = .active
        currentSegmentStartDate = Date()
        locationManager.resumeTracking()
        liveSnapshot = makeSnapshot()
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    func finish() -> ActivitySummary {
        updateSessionMetrics(now: Date())
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
        currentSegmentStartDate = nil
        accumulatedActiveDuration = 0
        return summary
    }

    private func tick() {
        guard state == .active else { return }
        updateSessionMetrics(now: Date())
    }

    private func handleLocationUpdate() {
        guard state == .active else { return }
        updateSessionMetrics(now: Date())
    }

    private func updateSessionMetrics(now: Date) {
        elapsedSeconds = currentElapsedSeconds(at: now)
        distanceMeters = locationManager.totalDistanceMeters
        elevationGainMeters = locationManager.elevationGainMeters
        currentPace = locationManager.currentPaceSecsPerKm
        liveSnapshot = makeSnapshot()
    }

    private func currentElapsedSeconds(at now: Date) -> Int {
        switch state {
        case .idle:
            return 0
        case .paused:
            return Int(accumulatedActiveDuration.rounded(.down))
        case .active:
            let segmentDuration = currentSegmentStartDate.map { now.timeIntervalSince($0) } ?? 0
            return Int((accumulatedActiveDuration + segmentDuration).rounded(.down))
        }
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

    var photoCaptureContext: PhotoCaptureContext {
        switch state {
        case .idle:
            return .preActivity
        case .active:
            return .active
        case .paused:
            return .paused
        }
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
