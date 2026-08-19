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
    @Published var autoPaused = false
    @Published private(set) var recoveredSession = false

    let locationManager: LocationManager
    private var timer: AnyCancellable?
    private var locationCancellable: AnyCancellable?
    private var autoPauseCandidateStart: Date?
    private var autoResumeCandidateStart: Date?
    private let autoPauseSpeedThresholdMetersPerSecond: Double = 1.0
    private let autoResumeSpeedThresholdMetersPerSecond: Double = 1.5
    private let autoPauseWarmupSeconds: TimeInterval = 10
    private let autoPauseDurationSeconds: TimeInterval = 12
    private let autoResumeDurationSeconds: TimeInterval = 6
    private var startDate: Date?
    private var currentSegmentStartDate: Date?
    private var accumulatedActiveDuration: TimeInterval = 0
    private var heartRateSamples: [HeartRateSample] = []
    private var lastJournalSaveAt: Date?

    init(locationManager: LocationManager) {
        self.locationManager = locationManager
        locationCancellable = locationManager.$location.sink { [weak self] _ in
            self?.handleLocationUpdate()
        }
        restoreJournalIfPresent()
    }

    func start() {
        timer?.cancel()
        ActiveSessionJournal.clear()
        let now = Date()
        state = .active
        autoPaused = false
        autoPauseCandidateStart = nil
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
        persistJournal(force: true)
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    func pause(autoTriggered: Bool = false) {
        guard state == .active else { return }
        updateSessionMetrics(now: Date())
        state = .paused
        autoPaused = autoTriggered
        accumulatedActiveDuration = TimeInterval(elapsedSeconds)
        currentSegmentStartDate = nil
        autoPauseCandidateStart = nil
        autoResumeCandidateStart = nil
        if !autoTriggered {
            timer?.cancel()
            locationManager.pauseTracking()
        }
        liveSnapshot = makeSnapshot()
        persistJournal(force: true)
    }

    func resume() {
        guard state == .paused else { return }
        state = .active
        autoPaused = false
        autoPauseCandidateStart = nil
        autoResumeCandidateStart = nil
        currentSegmentStartDate = Date()
        locationManager.resumeTracking()
        liveSnapshot = makeSnapshot()
        persistJournal(force: true)
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    func finish() -> ActivitySummary {
        updateSessionMetrics(now: Date())
        state = .idle
        autoPaused = false
        autoPauseCandidateStart = nil
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
        recoveredSession = false
        ActiveSessionJournal.clear()
        return summary
    }

#if DEBUG
    func seedLiveRunForUITest(
        elapsedSeconds: Int = 2_753,
        distanceMeters: Double = 7_820,
        elevationGainMeters: Double = 61,
        currentPaceSecsPerKm: Double = 341,
        heartRate: Int = 152
    ) {
        timer?.cancel()
        let now = Date()
        let route = Self.seeded10KRoute(endingAt: now)
        locationManager.seedLiveRunForUITest(
            distanceMeters: distanceMeters,
            elevationGainMeters: elevationGainMeters,
            currentPaceSecsPerKm: currentPaceSecsPerKm,
            trackPoints: route
        )
        state = .active
        autoPaused = false
        autoPauseCandidateStart = nil
        autoResumeCandidateStart = nil
        startDate = now.addingTimeInterval(-TimeInterval(elapsedSeconds))
        accumulatedActiveDuration = TimeInterval(elapsedSeconds)
        currentSegmentStartDate = now
        self.elapsedSeconds = elapsedSeconds
        self.distanceMeters = distanceMeters
        self.elevationGainMeters = elevationGainMeters
        currentPace = currentPaceSecsPerKm
        heartRateSamples.removeAll()
        self.heartRate = heartRate
        liveSnapshot = makeSnapshot()
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    private static func seeded10KRoute(endingAt endDate: Date) -> [CLLocation] {
        let coordinates: [(Double, Double, Double)] = [
            (37.76060, -122.40435, 50),
            (37.76210, -122.40435, 48),
            (37.76360, -122.40435, 45),
            (37.76510, -122.40435, 42),
            (37.76660, -122.40435, 39),
            (37.76660, -122.40710, 40),
            (37.76660, -122.40985, 42),
            (37.76660, -122.41260, 45),
            (37.76660, -122.41535, 48),
            (37.76660, -122.41810, 51),
            (37.76660, -122.42085, 54),
            (37.76660, -122.42360, 57),
            (37.76660, -122.42635, 60),
            (37.76660, -122.42910, 62),
            (37.76660, -122.43185, 64),
            (37.76460, -122.43185, 62),
            (37.76260, -122.43185, 59),
            (37.76060, -122.43185, 55),
            (37.75860, -122.43185, 51),
            (37.75660, -122.43185, 47),
            (37.75460, -122.43185, 43),
            (37.75260, -122.43185, 39),
            (37.75260, -122.42880, 38),
            (37.75260, -122.42575, 37),
            (37.75260, -122.42270, 36),
            (37.75260, -122.41965, 35),
            (37.75260, -122.41660, 34),
            (37.75260, -122.41355, 33),
            (37.75260, -122.41050, 32),
            (37.75260, -122.40745, 31),
            (37.75260, -122.40435, 30),
            (37.75460, -122.40435, 34),
            (37.75660, -122.40435, 39),
            (37.75860, -122.40435, 45),
            (37.76060, -122.40435, 50),
        ]
        let interval = TimeInterval(2_753 / max(1, coordinates.count - 1))
        return coordinates.enumerated().map { index, point in
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: point.0, longitude: point.1),
                altitude: point.2,
                horizontalAccuracy: 5,
                verticalAccuracy: 5,
                course: 180,
                speed: 2.93,
                timestamp: endDate.addingTimeInterval(-interval * Double(coordinates.count - 1 - index))
            )
        }
    }
#endif

    private func tick() {
        switch state {
        case .active:
            evaluateAutoPauseCandidate(now: Date())
        case .paused where autoPaused:
            evaluateAutoResumeCandidate(now: Date())
        default:
            break
        }
        updateSessionMetrics(now: Date())
    }

    private func handleLocationUpdate() {
        switch state {
        case .active:
            evaluateAutoPauseCandidate(now: Date())
        case .paused where autoPaused:
            evaluateAutoResumeCandidate(now: Date())
        default:
            break
        }
        updateSessionMetrics(now: Date())
    }

    private func evaluateAutoPauseCandidate(now: Date) {
        guard Double(currentElapsedSeconds(at: now)) >= autoPauseWarmupSeconds else {
            resetAutoPauseCandidate()
            return
        }

        guard let speed = locationManager.currentSpeedMetersPerSecond else {
            resetAutoPauseCandidate()
            return
        }

        if speed < autoPauseSpeedThresholdMetersPerSecond {
            if autoPauseCandidateStart == nil {
                autoPauseCandidateStart = now
            } else if now.timeIntervalSince(autoPauseCandidateStart!) >= autoPauseDurationSeconds {
                pause(autoTriggered: true)
            }
        } else {
            resetAutoPauseCandidate()
        }
    }

    private func evaluateAutoResumeCandidate(now: Date) {
        guard let speed = locationManager.currentSpeedMetersPerSecond else {
            resetAutoResumeCandidate()
            return
        }

        if speed >= autoResumeSpeedThresholdMetersPerSecond {
            if autoResumeCandidateStart == nil {
                autoResumeCandidateStart = now
            } else if now.timeIntervalSince(autoResumeCandidateStart!) >= autoResumeDurationSeconds {
                resume()
            }
        } else {
            resetAutoResumeCandidate()
        }
    }

    private func resetAutoPauseCandidate() {
        autoPauseCandidateStart = nil
    }

    private func resetAutoResumeCandidate() {
        autoResumeCandidateStart = nil
    }

    private func updateSessionMetrics(now: Date) {
        elapsedSeconds = currentElapsedSeconds(at: now)
        distanceMeters = locationManager.totalDistanceMeters
        elevationGainMeters = locationManager.elevationGainMeters
        currentPace = locationManager.currentPaceSecsPerKm
        liveSnapshot = makeSnapshot()
        persistJournal()
    }

    private func restoreJournalIfPresent() {
        guard let journal = ActiveSessionJournal.load() else { return }
        let points = journal.trackPoints.map(\.location)
        startDate = journal.startedAt
        accumulatedActiveDuration = TimeInterval(journal.elapsedSeconds)
        currentSegmentStartDate = nil
        elapsedSeconds = journal.elapsedSeconds
        locationManager.restoreTracking(from: points)
        distanceMeters = locationManager.totalDistanceMeters
        elevationGainMeters = locationManager.elevationGainMeters
        currentPace = locationManager.currentPaceSecsPerKm
        state = .paused
        recoveredSession = true
        liveSnapshot = makeSnapshot()
    }

    private func persistJournal(force: Bool = false) {
        guard state != .idle, let startDate else { return }
        let now = Date()
        if !force, let lastJournalSaveAt, now.timeIntervalSince(lastJournalSaveAt) < 10 { return }
        lastJournalSaveAt = now
        ActiveSessionJournal(
            startedAt: startDate,
            elapsedSeconds: elapsedSeconds,
            wasPaused: state == .paused,
            trackPoints: locationManager.trackPoints.map(JournalTrackPoint.init)
        ).save()
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
