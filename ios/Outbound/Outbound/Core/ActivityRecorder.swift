import Foundation
import Combine
import CoreLocation

enum RecordingState {
    case idle, active, paused
}

struct ActivityHealthMetrics: Codable, Hashable {
    let averageHeartRateBPM: Int?
    let maxHeartRateBPM: Int?
    let heartRateSampleCount: Int

    var hasHeartRateData: Bool {
        averageHeartRateBPM != nil || maxHeartRateBPM != nil
    }
}

private struct HeartRateSample {
    let recordedAt: Date
    let beatsPerMinute: Int
}

@MainActor
final class ActivityRecorder: ObservableObject {
    @Published var state: RecordingState = .idle
    @Published var elapsedSeconds: Int = 0
    @Published var distanceMeters: Double = 0
    @Published var elevationGainMeters: Double = 0
    @Published var currentPace: Double?   // secs/km
    @Published var heartRate: Int? {
        didSet {
            recordHeartRateSample(heartRate)
        }
    }
    @Published var liveSnapshot: ActiveSessionSnapshot = .empty

    let locationManager: LocationManager
    private var timer: AnyCancellable?
    private var locationCancellable: AnyCancellable?
    private var startDate: Date?
    private var currentSegmentStartDate: Date?
    private var accumulatedActiveDuration: TimeInterval = 0
    private var heartRateSamples: [HeartRateSample] = []

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
        heartRateSamples.removeAll()
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
            elevationGainM: elevationGainMeters,
            healthMetrics: healthMetricsSummary(),
            trackPoints: track
        )
        liveSnapshot = makeSnapshot(isActive: false)
        startDate = nil
        currentSegmentStartDate = nil
        accumulatedActiveDuration = 0
        heartRateSamples.removeAll()
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

    private func recordHeartRateSample(_ heartRate: Int?) {
        guard state != .idle, let heartRate, (30...240).contains(heartRate) else { return }

        let now = Date()
        if let lastSample = heartRateSamples.last,
           lastSample.beatsPerMinute == heartRate,
           now.timeIntervalSince(lastSample.recordedAt) < 15 {
            return
        }

        heartRateSamples.append(HeartRateSample(recordedAt: now, beatsPerMinute: heartRate))
    }

    private func healthMetricsSummary() -> ActivityHealthMetrics? {
        let values = heartRateSamples.map(\.beatsPerMinute)
        guard !values.isEmpty else { return nil }

        let average = Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
        return ActivityHealthMetrics(
            averageHeartRateBPM: average,
            maxHeartRateBPM: values.max(),
            heartRateSampleCount: values.count
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
    let elevationGainM: Double
    let healthMetrics: ActivityHealthMetrics?
    let trackPoints: [CLLocation]

    init(
        startedAt: Date,
        endedAt: Date,
        durationSecs: Int,
        distanceM: Double,
        avgPace: Double?,
        elevationGainM: Double = 0,
        healthMetrics: ActivityHealthMetrics? = nil,
        trackPoints: [CLLocation]
    ) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSecs = durationSecs
        self.distanceM = distanceM
        self.avgPace = avgPace
        self.elevationGainM = elevationGainM
        self.healthMetrics = healthMetrics
        self.trackPoints = trackPoints
    }
}
