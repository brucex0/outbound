import Foundation
import Combine
import CoreLocation

enum RecordingState: Equatable {
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

enum HeartRateSignalState: String, Codable {
    case waitingForFirstReading
    case available
    case unavailable
}

enum HeartRateIngestionSource: String, Codable {
    case appleWatch
    case debugFixture
}

@MainActor
final class ActivityRecorder: ObservableObject {
    @Published var state: RecordingState = .idle
    @Published var elapsedSeconds: Int = 0
    @Published var distanceMeters: Double = 0
    @Published var elevationGainMeters: Double = 0
    @Published private(set) var walkingStepCount: Int?
    @Published private(set) var companionType: ActivityCompanionType?
    @Published var currentPace: Double?   // secs/km
    @Published private(set) var heartRate: Int?
    @Published private(set) var heartRateSignalState: HeartRateSignalState = .waitingForFirstReading
    @Published private(set) var heartRateZone: Int?
    @Published private(set) var heartRateEffort: PlainstrideHeartRateEffort = .unavailable
    @Published var liveSnapshot: ActiveSessionSnapshot = .empty
    @Published var autoPaused = false
    @Published private(set) var lastAutoPauseRecoveredDurationSeconds = 0
    @Published private(set) var recoveredSession = false
    @Published private(set) var recoveredAwaitingSave = false
    @Published private(set) var recoveredRouteGuidance: ActiveRouteGuidanceJournal?
    @Published private(set) var recoveredActivityType: ActivityType?
    private(set) var recoveredWatchLifecycle: PlainstrideWorkoutLifecycle?
    private(set) var recoveredWatchMessageSequence: UInt64?
    @Published private(set) var routeGuidanceSnapshot: RouteGuidanceSnapshot?
#if DEBUG
    @Published private(set) var runSimulationState: RunSimulationState?
#endif
    let routeGuidanceEvents = PassthroughSubject<RouteGuidanceEvent, Never>()

    let locationManager: LocationManager
    private var timer: AnyCancellable?
    private var locationCancellable: AnyCancellable?
    private var autoPauseCandidateStart: Date?
    private var autoResumeCandidateStart: Date?
    private let autoPauseWarmupSeconds: TimeInterval = 10
    private let autoPauseDurationSeconds: TimeInterval = 12
    private let autoResumeDurationSeconds: TimeInterval = 6
    private var startDate: Date?
    private var currentSegmentStartDate: Date?
    private var accumulatedActiveDuration: TimeInterval = 0
    private var heartRateEngine = HeartRateEffortEngine()
    private var finalWatchHeartRateMetrics: PlainstrideFinalWorkoutMetrics?
    private var sessionMetadata: ActivityRecordingSessionMetadata?
    private let heartRateStaleInterval: TimeInterval = 20
    private var lastJournalSaveAt: Date?
    private var lastJournaledTrackPointCount = 0
    private var activityType: ActivityType = .running
    var averagePace: Double? {
        activityType.plausibleAveragePace(
            durationSeconds: Double(elapsedSeconds),
            distanceMeters: distanceMeters
        )
    }
    var recordingSessionMetadata: ActivityRecordingSessionMetadata? { sessionMetadata }
    private var tracksLocation: Bool {
        activityType != .strengthTraining && activityType != .mobility
    }
    private var routeGuidance: ActiveRouteGuidanceJournal?
    private var routeGuidanceEngine: RouteGuidanceEngine?
#if DEBUG
    private var runSimulationSampler: RunSimulationRouteSampler?
    private var runSimulationClock: AnyCancellable?
#endif

    private var autoPauseSpeedThresholdMetersPerSecond: Double {
        switch activityType {
        case .cycling: 1.5
        case .walking, .hiking: 0.35
        case .swimming: 0.2
        case .strengthTraining, .mobility: 0
        case .running: 1.0
        }
    }

    private var autoResumeSpeedThresholdMetersPerSecond: Double {
        switch activityType {
        case .cycling: 2.5
        case .walking, .hiking: 0.75
        case .swimming: 0.5
        case .strengthTraining, .mobility: 0
        case .running: 1.5
        }
    }

    init(locationManager: LocationManager) {
        self.locationManager = locationManager
        locationCancellable = locationManager.$location.sink { [weak self] location in
            self?.handleLocationUpdate(location)
        }
        restoreJournalIfPresent()
    }

    func start(
        activityType: ActivityType = .running,
        routeGuidance: ActiveRouteGuidanceJournal? = nil,
        canonicalStartDate: Date? = nil,
        sessionMetadata: ActivityRecordingSessionMetadata? = nil,
        companionType: ActivityCompanionType? = nil
    ) {
#if DEBUG
        resetRunSimulation()
#endif
        timer?.cancel()
        ActiveSessionJournal.clear(reason: .newRecording)
        lastJournaledTrackPointCount = 0
        recoveredAwaitingSave = false
        let now = Date()
        let resolvedStartDate = canonicalStartDate.map { min($0, now) } ?? now
        state = .active
        autoPaused = false
        lastAutoPauseRecoveredDurationSeconds = 0
        autoPauseCandidateStart = nil
        startDate = resolvedStartDate
        currentSegmentStartDate = now
        accumulatedActiveDuration = max(0, now.timeIntervalSince(resolvedStartDate))
        self.activityType = activityType
        self.sessionMetadata = sessionMetadata
        self.companionType = companionType
        recoveredWatchLifecycle = nil
        recoveredWatchMessageSequence = nil
        self.routeGuidance = routeGuidance
        routeGuidance?.saveRouteSnapshot()
        routeGuidanceEngine = routeGuidance.flatMap {
            RouteGuidanceEngine(route: $0.route, recoverySeed: $0.recoverySeed)
        }
        routeGuidanceSnapshot = routeGuidanceEngine?.currentSnapshot
        recoveredRouteGuidance = nil
        recoveredActivityType = nil
        recoveredWatchLifecycle = nil
        recoveredWatchMessageSequence = nil
        elapsedSeconds = 0
        distanceMeters = 0
        elevationGainMeters = 0
        walkingStepCount = nil
        currentPace = nil
        heartRate = nil
        heartRateSignalState = .waitingForFirstReading
        heartRateZone = nil
        heartRateEffort = .unavailable
        heartRateEngine = HeartRateEffortEngine()
        finalWatchHeartRateMetrics = nil
        if tracksLocation {
            locationManager.startTracking(activityType: activityType)
        }
        liveSnapshot = makeSnapshot()
        persistJournal(force: true)
        if tracksLocation, !locationManager.hasRecentValidLocation {
            ActivityDiagnosticLog.notice(
                .lifecycle,
                "Recording started without valid location fix permission_granted=\(locationManager.isLocationPermissionGranted)"
            )
        }
        ActivityDiagnosticLog.notice(
            .lifecycle,
            "Recording started type=\(activityType.rawValue) route_selected=\(routeGuidance != nil)"
        )
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    func pause(autoTriggered: Bool = false) {
        guard state == .active else { return }
#if DEBUG
        stopRunSimulationClock()
#endif
        updateSessionMetrics(now: Date())
        autoPaused = autoTriggered
        state = .paused
        accumulatedActiveDuration = TimeInterval(elapsedSeconds)
        currentSegmentStartDate = nil
        autoPauseCandidateStart = nil
        autoResumeCandidateStart = nil
        if !tracksLocation {
            timer?.cancel()
        } else if !autoTriggered {
            timer?.cancel()
            locationManager.pauseTracking()
        } else {
            locationManager.beginAutoPauseProbing()
        }
        liveSnapshot = makeSnapshot()
        persistJournal(force: true)
        ActivityDiagnosticLog.notice(
            .lifecycle,
            "Recording paused trigger=\(autoTriggered ? "automatic" : "manual") duration=\(ActivityDiagnosticLog.durationBucket(seconds: elapsedSeconds))"
        )
    }

    func resume() {
        guard state == .paused else { return }
        let wasAutoPaused = autoPaused
        let now = Date()
        let recoveredDuration = tracksLocation
            ? locationManager.resumeTracking(fromAutoPause: wasAutoPaused)
            : 0
        lastAutoPauseRecoveredDurationSeconds = Int(recoveredDuration.rounded())
        accumulatedActiveDuration += recoveredDuration
        state = .active
        autoPaused = false
        autoPauseCandidateStart = nil
        autoResumeCandidateStart = nil
        currentSegmentStartDate = now
        updateSessionMetrics(now: now)
        persistJournal(force: true)
        ActivityDiagnosticLog.notice(
            .lifecycle,
            "Recording resumed source=\(wasAutoPaused ? "automatic_pause" : "manual_pause") recovered_duration=\(ActivityDiagnosticLog.durationBucket(seconds: lastAutoPauseRecoveredDurationSeconds))"
        )
#if DEBUG
        guard runSimulationState == nil else { return }
#endif
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    func finish() -> ActivitySummary {
#if DEBUG
        stopRunSimulationClock()
#endif
        updateSessionMetrics(now: Date())
        // Finishing only commits the runner to the post-run review. Keep the
        // recovery journal durable until that review is saved or discarded.
        persistJournal(force: true, recoveryStage: .awaitingSave)
        state = .idle
        autoPaused = false
        autoPauseCandidateStart = nil
        timer?.cancel()
        let stoppedTrack = locationManager.stopTracking()
        let reconciledTrack = LocationTrackPostProcessor.reconcile(
            segments: stoppedTrack.segments,
            plannedRoute: routeGuidance?.route
        )
        let finalDistanceMeters = stoppedTrack.preservesLiveMetrics
            ? stoppedTrack.liveDistanceMeters
            : reconciledTrack.distanceMeters
                + stoppedTrack.motionSupplementDistanceMeters
                + stoppedTrack.motionTailDistanceMeters
        let finalElevationGainMeters = stoppedTrack.preservesLiveMetrics
            ? elevationGainMeters
            : reconciledTrack.elevationGainMeters
        locationManager.recordFinalReconciliation(
            liveDistanceMeters: stoppedTrack.liveDistanceMeters,
            finalDistanceMeters: finalDistanceMeters,
            routeMatchResult: reconciledTrack.routeMatchResult
        )
        distanceMeters = finalDistanceMeters
        elevationGainMeters = finalElevationGainMeters
        walkingStepCount = stoppedTrack.walkingStepCount
        let finishedRouteGuidance = routeGuidanceSnapshot
        let summary = ActivitySummary(
            startedAt: startDate ?? Date(),
            endedAt: Date(),
            durationSecs: elapsedSeconds,
            distanceM: finalDistanceMeters,
            avgPace: activityType.plausibleAveragePace(
                durationSeconds: Double(elapsedSeconds),
                distanceMeters: finalDistanceMeters
            ),
            elevationGainM: finalElevationGainMeters,
            walkingStepCount: stoppedTrack.walkingStepCount,
            healthMetrics: healthMetricsSummary(),
            heartRateZones: heartRateZoneSummary(),
            sessionMetadata: sessionMetadata,
            routeGuidance: finishedRouteGuidance,
            trackPoints: reconciledTrack.points,
            trackSegmentStartIndices: reconciledTrack.segmentStartIndices
        )
        ActivityDiagnosticLog.notice(
            .lifecycle,
            "Recording finished duration=\(ActivityDiagnosticLog.durationBucket(seconds: summary.durationSecs)) distance=\(ActivityDiagnosticLog.distanceBucket(meters: summary.distanceM)) track_points=\(ActivityDiagnosticLog.countBucket(summary.trackPoints.count)) segments=\(ActivityDiagnosticLog.countBucket(summary.trackSegmentStartIndices.count)) recovery_stage=awaiting_save"
        )
        liveSnapshot = makeSnapshot(isActive: false)
        startDate = nil
        currentSegmentStartDate = nil
        accumulatedActiveDuration = 0
        heartRateEngine = HeartRateEffortEngine()
        finalWatchHeartRateMetrics = nil
        recoveredSession = false
        recoveredAwaitingSave = false
        recoveredRouteGuidance = nil
        recoveredActivityType = nil
        routeGuidance = nil
        routeGuidanceEngine = nil
        routeGuidanceSnapshot = nil
#if DEBUG
        resetRunSimulation()
#endif
        return summary
    }

#if DEBUG
    var isSimulatingRun: Bool {
        runSimulationState != nil
    }

    var runSimulationSpeedBucket: String {
        guard let speed = runSimulationState?.speedKilometersPerHour else { return "unavailable" }
        return switch speed {
        case ..<8: "under_8kph"
        case ..<12: "8_12kph"
        default: "12kph_plus"
        }
    }

    func startRunSimulation(
        activityType: ActivityType = .running,
        routeGuidance: ActiveRouteGuidanceJournal,
        route: PreparedRoute,
        speedKilometersPerHour: Double = 10
    ) {
        guard let sampler = RunSimulationRouteSampler(route: route) else { return }

        timer?.cancel()
        resetRunSimulation()
        ActiveSessionJournal.clear(reason: .newRecording)
        lastJournaledTrackPointCount = 0
        let now = Date()
        state = .active
        autoPaused = false
        autoPauseCandidateStart = nil
        autoResumeCandidateStart = nil
        startDate = now
        currentSegmentStartDate = nil
        accumulatedActiveDuration = 0
        self.activityType = activityType
        self.routeGuidance = routeGuidance
        routeGuidanceEngine = RouteGuidanceEngine(
            route: routeGuidance.route,
            recoverySeed: routeGuidance.recoverySeed
        )
        routeGuidanceSnapshot = routeGuidanceEngine?.currentSnapshot
        recoveredRouteGuidance = nil
        recoveredActivityType = nil
        elapsedSeconds = 0
        distanceMeters = 0
        elevationGainMeters = 0
        currentPace = nil
        companionType = nil
        heartRate = nil
        heartRateSignalState = .waitingForFirstReading
        heartRateZone = nil
        heartRateEffort = .unavailable
        heartRateEngine = HeartRateEffortEngine()
        finalWatchHeartRateMetrics = nil
        sessionMetadata = nil
        runSimulationSampler = sampler
        runSimulationState = RunSimulationState(
            speedKilometersPerHour: max(4, min(24, speedKilometersPerHour)),
            timeRate: 10,
            isClockRunning: false,
            elapsedSeconds: 0,
            distanceMeters: 0,
            routeDistanceMeters: sampler.totalDistanceMeters
        )
        locationManager.startSimulatedTracking(activityType: activityType)
        if let initialLocation = sampler.location(
            at: 0,
            speedMetersPerSecond: runSimulationState?.speedMetersPerSecond ?? 0,
            timestamp: now
        ) {
            locationManager.ingestSimulatedLocation(initialLocation)
        } else {
            liveSnapshot = makeSnapshot()
        }
    }

    func toggleRunSimulationClock() {
        guard let simulation = runSimulationState,
              state == .active,
              !simulation.isComplete
        else { return }

        if simulation.isClockRunning {
            stopRunSimulationClock()
            return
        }

        var updated = simulation
        updated.isClockRunning = true
        runSimulationState = updated
        startRunSimulationClock(rate: updated.timeRate)
    }

    func setRunSimulationTimeRate(_ rate: Int) {
        guard [1, 10, 60].contains(rate), var simulation = runSimulationState else { return }
        let wasRunning = simulation.isClockRunning
        simulation.timeRate = rate
        runSimulationState = simulation
        if wasRunning {
            startRunSimulationClock(rate: rate)
        }
    }

    func adjustRunSimulationSpeed(byKilometersPerHour delta: Double) {
        guard var simulation = runSimulationState else { return }
        simulation.speedKilometersPerHour = max(
            4,
            min(24, simulation.speedKilometersPerHour + delta)
        )
        runSimulationState = simulation
    }

    func advanceRunSimulation(by seconds: Int) {
        guard seconds > 0,
              state == .active,
              let sampler = runSimulationSampler,
              var simulation = runSimulationState,
              !simulation.isComplete,
              let startDate
        else { return }

        var remainingSeconds = seconds
        while remainingSeconds > 0, !simulation.isComplete {
            let stepSeconds = 1
            simulation.elapsedSeconds += stepSeconds
            simulation.distanceMeters = min(
                simulation.routeDistanceMeters,
                simulation.distanceMeters
                    + (simulation.speedMetersPerSecond * Double(stepSeconds))
            )
            runSimulationState = simulation

            if let location = sampler.location(
                at: simulation.distanceMeters,
                speedMetersPerSecond: simulation.speedMetersPerSecond,
                timestamp: startDate.addingTimeInterval(TimeInterval(simulation.elapsedSeconds))
            ) {
                locationManager.ingestSimulatedLocation(location)
            }
            remainingSeconds -= stepSeconds
        }

        if simulation.isComplete {
            stopRunSimulationClock()
        }
    }

    private func startRunSimulationClock(rate: Int) {
        runSimulationClock?.cancel()
        runSimulationClock = Timer.publish(
            every: 1.0 / Double(rate),
            on: .main,
            in: .common
        )
        .autoconnect()
        .sink { [weak self] _ in
            self?.advanceRunSimulation(by: 1)
        }
    }

    private func stopRunSimulationClock() {
        runSimulationClock?.cancel()
        runSimulationClock = nil
        guard var simulation = runSimulationState, simulation.isClockRunning else { return }
        simulation.isClockRunning = false
        runSimulationState = simulation
    }

    private func resetRunSimulation() {
        runSimulationClock?.cancel()
        runSimulationClock = nil
        runSimulationSampler = nil
        runSimulationState = nil
    }

    func seedLiveRunForUITest(
        elapsedSeconds: Int = 2_753,
        distanceMeters: Double = 7_820,
        elevationGainMeters: Double = 61,
        currentPaceSecsPerKm: Double = 341,
        heartRate: Int = 152
    ) {
        timer?.cancel()
        resetRunSimulation()
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
        heartRateEngine = HeartRateEffortEngine()
        _ = ingestHeartRate(bpm: heartRate, sampledAt: now, source: .debugFixture)
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

    private func handleLocationUpdate(_ location: CLLocation?) {
        if state == .active, let location {
            updateRouteGuidance(with: location)
        }
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
#if DEBUG
        guard runSimulationState == nil else { return }
#endif
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
#if DEBUG
        guard runSimulationState == nil else { return }
#endif
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
        walkingStepCount = locationManager.walkingStepCount
        currentPace = locationManager.currentPaceSecsPerKm
        if let lastSample = heartRateEngine.snapshot.lastSampleDate,
           now.timeIntervalSince(lastSample) > heartRateStaleInterval {
            heartRate = nil
            heartRateZone = nil
            heartRateEffort = .unavailable
            heartRateSignalState = .unavailable
        }
        liveSnapshot = makeSnapshot()
        persistJournal()
    }

    private func restoreJournalIfPresent() {
        guard let journal = ActiveSessionJournal.load() else { return }
        let points = journal.trackPoints.map(\.location)
        let segmentStarts = Set(journal.trackPoints.indices.filter {
            journal.trackPoints[$0].startsNewSegment
        })
        lastJournaledTrackPointCount = journal.trackPoints.count
        startDate = journal.startedAt
        accumulatedActiveDuration = TimeInterval(journal.elapsedSeconds)
        currentSegmentStartDate = nil
        elapsedSeconds = journal.elapsedSeconds
        activityType = journal.activityType ?? .running
        companionType = journal.companionType
        locationManager.restoreTracking(
            from: points,
            segmentStartIndices: segmentStarts,
            activityType: activityType,
            walkingStepCount: journal.walkingStepCount
        )
        distanceMeters = locationManager.totalDistanceMeters
        elevationGainMeters = locationManager.elevationGainMeters
        walkingStepCount = locationManager.walkingStepCount
        currentPace = locationManager.currentPaceSecsPerKm
        state = .paused
        recoveredSession = true
        recoveredAwaitingSave = journal.recoveryStage == .awaitingSave
        recoveredActivityType = activityType
        routeGuidance = ActiveRouteGuidanceJournal.load(recoverySeed: journal.routeGuidanceRecoverySeed)
        recoveredRouteGuidance = routeGuidance
        routeGuidanceEngine = routeGuidance.flatMap {
            RouteGuidanceEngine(route: $0.route, recoverySeed: $0.recoverySeed)
        }
        routeGuidanceSnapshot = routeGuidanceEngine?.currentSnapshot
        sessionMetadata = journal.sessionMetadata
        recoveredWatchLifecycle = journal.lastWatchLifecycle
        recoveredWatchMessageSequence = journal.lastWatchMessageSequence
        heartRateEngine = journal.heartRateEffortEngine ?? HeartRateEffortEngine()
        let recoveredHeartRate = heartRateEngine.snapshot
        heartRate = recoveredHeartRate.currentBPM
        heartRateZone = recoveredHeartRate.currentZone
        heartRateEffort = recoveredHeartRate.effort
        heartRateSignalState = recoveredHeartRate.currentBPM == nil ? .waitingForFirstReading : .available
        liveSnapshot = makeSnapshot()
        ActivityDiagnosticLog.notice(
            .recovery,
            "Session recovered stage=\(journal.recoveryStage.rawValue) type=\(activityType.rawValue) duration=\(ActivityDiagnosticLog.durationBucket(seconds: elapsedSeconds)) track_points=\(ActivityDiagnosticLog.countBucket(points.count)) route_selected=\(routeGuidance != nil)"
        )
    }

    private func updateRouteGuidance(with location: CLLocation) {
        guard var engine = routeGuidanceEngine,
              let snapshot = engine.ingest(location)
        else { return }
        routeGuidanceEngine = engine
        routeGuidanceSnapshot = snapshot.withoutEvents
        if let route = routeGuidance?.route {
            routeGuidance = ActiveRouteGuidanceJournal(
                route: route,
                recoverySeed: engine.makeRecoverySeed()
            )
        }
        if !snapshot.events.isEmpty {
            persistJournal(force: true)
        }
        for event in snapshot.events {
            routeGuidanceEvents.send(event)
        }
    }

    private func persistJournal(
        force: Bool = false,
        recoveryStage: ActiveSessionRecoveryStage = .recording
    ) {
#if DEBUG
        guard runSimulationState == nil else { return }
#endif
        guard state != .idle, let startDate else { return }
        let now = Date()
        if !force, let lastJournalSaveAt, now.timeIntervalSince(lastJournalSaveAt) < 10 { return }
        lastJournalSaveAt = now
        let trackPoints = locationManager.trackPoints
        if trackPoints.count < lastJournaledTrackPointCount {
            lastJournaledTrackPointCount = 0
        }
        let newTrackPoints = locationManager.journalTrackPoints(
            startingAt: lastJournaledTrackPointCount
        )
        let trackAppendSucceeded = ActiveSessionTrackJournal.append(newTrackPoints)
        if trackAppendSucceeded {
            lastJournaledTrackPointCount = trackPoints.count
        }
        let metadataSaved = ActiveSessionJournal(
            startedAt: startDate,
            elapsedSeconds: elapsedSeconds,
            wasPaused: state == .paused,
            activityType: activityType,
            walkingStepCount: walkingStepCount,
            companionType: companionType,
            routeGuidanceRecoverySeed: routeGuidance?.recoverySeed,
            sessionMetadata: sessionMetadata,
            heartRateEffortEngine: heartRateEngine,
            lastWatchLifecycle: recoveredWatchLifecycle,
            lastWatchMessageSequence: recoveredWatchMessageSequence,
            recoveryStage: recoveryStage
        ).save()
        if force {
            let stateName = switch state {
            case .idle: "idle"
            case .active: "active"
            case .paused: "paused"
            }
            ActivityDiagnosticLog.notice(
                .recovery,
                "Recovery checkpoint stage=\(recoveryStage.rawValue) state=\(stateName) new_points=\(ActivityDiagnosticLog.countBucket(newTrackPoints.count)) track_write=\(trackAppendSucceeded ? "success" : "failure") metadata_write=\(metadataSaved ? "success" : "failure")"
            )
        } else if !trackAppendSucceeded || !metadataSaved {
            ActivityDiagnosticLog.error(
                .recovery,
                "Recovery checkpoint failed track_write=\(trackAppendSucceeded ? "success" : "failure") metadata_write=\(metadataSaved ? "success" : "failure")"
            )
        }
    }

    private func currentElapsedSeconds(at now: Date) -> Int {
#if DEBUG
        if let runSimulationState {
            return runSimulationState.elapsedSeconds
        }
#endif
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
            activityType: activityType,
            heartRate: heartRate,
            location: locationManager.location.map(SessionLocation.init),
            isActive: isActive ?? (state == .active)
        )
    }

    @discardableResult
    func ingestHeartRate(
        bpm: Int,
        sampledAt: Date,
        source: HeartRateIngestionSource
    ) -> Bool {
        guard state != .idle,
              sampledAt <= Date().addingTimeInterval(5),
              heartRateEngine.ingest(bpm: bpm, sampledAt: sampledAt) else { return false }
        let snapshot = heartRateEngine.snapshot
        heartRate = snapshot.currentBPM
        heartRateZone = snapshot.currentZone
        heartRateEffort = snapshot.effort
        heartRateSignalState = .available
        liveSnapshot = makeSnapshot()
        persistJournal()
        return true
    }

    func applyFinalHeartRateMetrics(_ metrics: PlainstrideFinalWorkoutMetrics) {
        finalWatchHeartRateMetrics = metrics
    }

    func updateRecordingSessionMetadata(_ metadata: ActivityRecordingSessionMetadata) {
        guard state != .idle else { return }
        sessionMetadata = metadata
        persistJournal(force: true)
    }

    func reconcilingFinalHeartRateMetrics(
        _ metrics: PlainstrideFinalWorkoutMetrics,
        into summary: ActivitySummary
    ) -> ActivitySummary {
        let fallbackEngine = HeartRateEffortEngine()
        let existingZones = summary.heartRateZones?.zones ?? (1...5).map { zone in
            let bounds = fallbackEngine.bounds(for: zone)
            return ActivityHeartRateZone(
                index: zone,
                lowerBoundBPM: bounds.lower,
                upperBoundBPM: bounds.upper,
                seconds: 0
            )
        }
        let zones = existingZones.map { zone in
            ActivityHeartRateZone(
                index: zone.index,
                lowerBoundBPM: zone.lowerBoundBPM,
                upperBoundBPM: zone.upperBoundBPM,
                seconds: Int((metrics.timeInZones.first(where: { $0.zone == zone.index })?.seconds ?? 0).rounded())
            )
        }
        let reconciledDistance = summary.trackPoints.isEmpty
            ? (metrics.distanceMeters ?? summary.distanceM)
            : summary.distanceM
        return ActivitySummary(
            startedAt: summary.startedAt,
            endedAt: summary.endedAt,
            durationSecs: max(summary.durationSecs, Int(metrics.elapsedTime.rounded())),
            distanceM: reconciledDistance,
            avgPace: activityType.plausibleAveragePace(
                durationSeconds: Double(max(summary.durationSecs, Int(metrics.elapsedTime.rounded()))),
                distanceMeters: reconciledDistance
            ),
            elevationGainM: summary.elevationGainM,
            elevationMetadata: summary.elevationMetadata,
            walkingStepCount: summary.walkingStepCount,
            healthMetrics: ActivityHealthMetrics(
                averageHeartRateBPM: metrics.averageBPM,
                maxHeartRateBPM: metrics.maximumBPM,
                heartRateSampleCount: summary.healthMetrics?.heartRateSampleCount ?? 0
            ),
            heartRateZones: ActivityHeartRateZoneSummary(
                estimatedMaxHeartRate: summary.heartRateZones?.estimatedMaxHeartRate
                    ?? fallbackEngine.configuration.maximumHeartRate,
                zones: zones
            ),
            sessionMetadata: summary.sessionMetadata,
            routeGuidance: summary.routeGuidance,
            trackPoints: summary.trackPoints,
            trackSegmentStartIndices: summary.trackSegmentStartIndices
        )
    }

    func updateWatchRecoveryState(
        lifecycle: PlainstrideWorkoutLifecycle,
        lastReceivedSequence: UInt64
    ) {
        recoveredWatchLifecycle = lifecycle
        recoveredWatchMessageSequence = max(recoveredWatchMessageSequence ?? 0, lastReceivedSequence)
        persistJournal()
    }

    private func healthMetricsSummary() -> ActivityHealthMetrics? {
        let snapshot = heartRateEngine.snapshot
        let average = finalWatchHeartRateMetrics?.averageBPM ?? snapshot.averageBPM
        let maximum = finalWatchHeartRateMetrics?.maximumBPM ?? snapshot.maximumBPM
        guard average != nil || maximum != nil else { return nil }
        return ActivityHealthMetrics(
            averageHeartRateBPM: average,
            maxHeartRateBPM: maximum,
            heartRateSampleCount: snapshot.sampleCount
        )
    }

    private func heartRateZoneSummary() -> ActivityHeartRateZoneSummary? {
        let snapshot = heartRateEngine.snapshot
        let durations = finalWatchHeartRateMetrics?.timeInZones ?? snapshot.timeInZones
        guard snapshot.sampleCount > 0 || durations.contains(where: { $0.seconds > 0 }) else { return nil }
        let zones = (1...5).map { zone -> ActivityHeartRateZone in
            let bounds = heartRateEngine.bounds(for: zone)
            return ActivityHeartRateZone(
                index: zone,
                lowerBoundBPM: bounds.lower,
                upperBoundBPM: bounds.upper,
                seconds: Int((durations.first(where: { $0.zone == zone })?.seconds ?? 0).rounded())
            )
        }
        return ActivityHeartRateZoneSummary(
            estimatedMaxHeartRate: heartRateEngine.configuration.maximumHeartRate,
            zones: zones
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

    var routeGuidanceCoordinates: [CLLocationCoordinate2D] {
        routeGuidanceEngine?.displayCoordinates ?? []
    }
}

private extension RouteGuidanceSnapshot {
    var withoutEvents: RouteGuidanceSnapshot {
        RouteGuidanceSnapshot(
            state: state,
            progressMeters: progressMeters,
            totalDistanceMeters: totalDistanceMeters,
            remainingDistanceMeters: remainingDistanceMeters,
            distanceFromRouteMeters: distanceFromRouteMeters,
            progressFraction: progressFraction,
            nearestSegmentIndex: nearestSegmentIndex,
            events: []
        )
    }
}

struct ActivitySummary {
    let startedAt: Date
    let endedAt: Date
    let durationSecs: Int
    let distanceM: Double
    let avgPace: Double?
    let elevationGainM: Double
    let elevationMetadata: ActivityElevationMetadata?
    let walkingStepCount: Int?
    let healthMetrics: ActivityHealthMetrics?
    let heartRateZones: ActivityHeartRateZoneSummary?
    let sessionMetadata: ActivityRecordingSessionMetadata?
    let routeGuidance: RouteGuidanceSnapshot?
    let trackPoints: [CLLocation]
    let trackSegmentStartIndices: Set<Int>

    nonisolated var trackSegments: [[CLLocation]] {
        guard !trackPoints.isEmpty else { return [] }
        var result: [[CLLocation]] = []
        var current: [CLLocation] = []
        let starts = trackSegmentStartIndices.isEmpty ? Set([0]) : trackSegmentStartIndices
        for index in trackPoints.indices {
            if starts.contains(index), !current.isEmpty {
                result.append(current)
                current = []
            }
            current.append(trackPoints[index])
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    init(
        startedAt: Date,
        endedAt: Date,
        durationSecs: Int,
        distanceM: Double,
        avgPace: Double?,
        elevationGainM: Double = 0,
        elevationMetadata: ActivityElevationMetadata? = nil,
        walkingStepCount: Int? = nil,
        healthMetrics: ActivityHealthMetrics? = nil,
        heartRateZones: ActivityHeartRateZoneSummary? = nil,
        sessionMetadata: ActivityRecordingSessionMetadata? = nil,
        routeGuidance: RouteGuidanceSnapshot? = nil,
        trackPoints: [CLLocation],
        trackSegmentStartIndices: Set<Int> = []
    ) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSecs = durationSecs
        self.distanceM = distanceM
        self.avgPace = avgPace
        self.elevationGainM = elevationGainM
        self.elevationMetadata = elevationMetadata
        self.walkingStepCount = walkingStepCount
        self.healthMetrics = healthMetrics
        self.heartRateZones = heartRateZones
        self.sessionMetadata = sessionMetadata
        self.routeGuidance = routeGuidance
        self.trackPoints = trackPoints
        self.trackSegmentStartIndices = trackSegmentStartIndices
    }
}
