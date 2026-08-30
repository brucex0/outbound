import Combine
import CoreLocation
import CoreMotion

struct LocationRecordingDiagnostics: Equatable {
    let receivedBatchCount: Int
    let maximumBatchSize: Int
    let acceptedTrackPointCount: Int
    let rejectedLocationCount: Int
    let stationaryLocationCount: Int
    let segmentCount: Int
    let motionAssistedDistanceMeters: Double
    let finalDistanceCorrectionPercent: Double
    let routeMatchResult: String
    let signalQuality: LocationSignalQuality
    let accuracyAuthorization: CLAccuracyAuthorization

    var deliveryMode: String {
        if receivedBatchCount == 0 { return "no_updates" }
        return maximumBatchSize > 1 ? "batched_updates" : "single_updates"
    }

    var result: String {
        if acceptedTrackPointCount == 0 { return "no_usable_points" }
        return rejectedLocationCount == 0 && stationaryLocationCount == 0
            ? "all_accepted"
            : "some_filtered"
    }

    var precisionMode: String {
        accuracyAuthorization == .fullAccuracy ? "full" : "reduced"
    }
}

struct StoppedLocationTrack {
    let segments: [[CLLocation]]
    let liveDistanceMeters: Double
    let motionSupplementDistanceMeters: Double
    let motionTailDistanceMeters: Double
    let preservesLiveMetrics: Bool
}

@MainActor
final class LocationManager: NSObject, ObservableObject {
    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy
    @Published private(set) var signalQuality: LocationSignalQuality = .unavailable
    @Published var trackPoints: [CLLocation] = []
    @Published private(set) var trackCoordinates: [CLLocationCoordinate2D] = []

    private let maximumPublishedLocationAccuracyMeters: Double = 80
    private let minimumValidPaceDistanceMeters: Double = 25
    private let minimumValidPaceDurationSeconds: TimeInterval = 8
    private let paceWindowSeconds: TimeInterval = 30
    private let maximumPreStartLocationAgeSeconds: TimeInterval = 3
    private let maximumFutureLocationSeconds: TimeInterval = 5
    private let maximumPreparationLocationAgeSeconds: TimeInterval = 8
    private let motionGapThresholdSeconds: TimeInterval = 8

    private let manager = CLLocationManager()
    private let pedometer = CMPedometer()
    private var activityType: ActivityType = .running
    private var filter = LocationTrackFilter(activityType: .running)
    private var probeFilter = LocationTrackFilter(activityType: .running)
    private var wantsTracking = false
    private var wantsPreparation = false
    private var wantsOneShotLocation = false
    private var isAutoPauseProbing = false
    private var requiresNewSegment = false
    private var trackingStartedAt: Date?
    private var preparedLocation: CLLocation?
    private var probeLocations: [CLLocation] = []
    private var segmentStartIndices = Set<Int>()
    private var accumulatedDistanceMeters: Double = 0
    private var elevationAccumulator = ElevationGainCalculator.StreamingRangeAccumulator()
    private var currentMotionSpeed: Double?
    private var previousMotionLocation: CLLocation?
    private var receivedBatchCount = 0
    private var maximumBatchSize = 0
    private var acceptedTrackPointCount = 0
    private var rejectedLocationCount = 0
    private var stationaryLocationCount = 0
    private var motionAssistedDistanceMeters: Double = 0
    private var finalDistanceCorrectionPercent: Double = 0
    private var routeMatchResult = "not_available"
    private var pedometerDistanceMeters: Double = 0
    private var pedometerDistanceAtLastTrackPoint: Double = 0
    private var pedometerDistanceAtProbeStart: Double = 0
    private var lastAcceptedDeliveryAt: Date?
#if DEBUG
    private var testDistanceMeters: Double?
    private var testElevationGainMeters: Double?
    private var testCurrentPaceSecsPerKm: Double?
    private var isSimulatingLocations = false
    private var simulatedSpeedMetersPerSecond: Double?
#endif

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 1
        manager.activityType = .fitness
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
        updateSignalQuality(using: nil)
    }

    var trackCoordinateSegments: [[CLLocationCoordinate2D]] {
        locationSegments.map { $0.map(\.coordinate) }
    }

    var locationSegments: [[CLLocation]] {
        Self.segments(from: trackPoints, starts: segmentStartIndices)
    }

    var currentSpeedMetersPerSecond: Double? {
#if DEBUG
        if isSimulatingLocations { return simulatedSpeedMetersPerSecond }
#endif
        return currentMotionSpeed
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func requestCurrentLocation() {
        wantsOneShotLocation = true
        switch manager.authorizationStatus {
        case .notDetermined:
            requestPermission()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            wantsOneShotLocation = false
        @unknown default:
            wantsOneShotLocation = false
        }
    }

    /// Starts high-accuracy acquisition during the visible countdown so the
    /// first recorded point can use a warm, recent fix.
    func prepareForRecording(activityType: ActivityType) {
#if DEBUG
        guard !isSimulatingLocations else { return }
#endif
        self.activityType = activityType
        configureFilters(for: activityType)
        wantsPreparation = true
        switch manager.authorizationStatus {
        case .notDetermined:
            requestPermission()
        case .authorizedAlways, .authorizedWhenInUse:
            requestTemporaryFullAccuracyIfNeeded()
            manager.startUpdatingLocation()
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    func cancelPreparation() {
        wantsPreparation = false
        preparedLocation = nil
        guard !wantsTracking else { return }
        manager.stopUpdatingLocation()
    }

    func startTracking(activityType: ActivityType = .running) {
#if DEBUG
        clearTestOverrides()
        isSimulatingLocations = false
        simulatedSpeedMetersPerSecond = nil
#endif
        let warmLocation = preparedLocation.flatMap { candidate in
            let age = abs(Date().timeIntervalSince(candidate.timestamp))
            return age <= maximumPreparationLocationAgeSeconds && candidate.horizontalAccuracy <= 30
                ? candidate
                : nil
        }
        self.activityType = activityType
        configureFilters(for: activityType)
        resetRecordingState(preserving: warmLocation)
        trackingStartedAt = Date()
        wantsTracking = true
        wantsPreparation = false
        preparedLocation = nil
        startPedometerIfAvailable()

        if let warmLocation {
            beginSegment(with: warmLocation)
            location = warmLocation
            updateSignalQuality(using: warmLocation)
        }

        switch manager.authorizationStatus {
        case .notDetermined:
            requestPermission()
        case .authorizedAlways, .authorizedWhenInUse:
            requestTemporaryFullAccuracyIfNeeded()
            manager.startUpdatingLocation()
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    private func startTrackingIfPermitted() {
#if DEBUG
        guard !isSimulatingLocations else { return }
#endif
        guard wantsTracking || wantsPreparation else { return }
        manager.startUpdatingLocation()
    }

    func pauseTracking() {
        guard wantsTracking else { return }
        manager.stopUpdatingLocation()
        stopPedometer()
        requiresNewSegment = true
        currentMotionSpeed = nil
    }

    func beginAutoPauseProbing() {
        guard wantsTracking, !isAutoPauseProbing else { return }
        isAutoPauseProbing = true
        probeLocations = []
        probeFilter = LocationTrackFilter(activityType: activityType)
        probeFilter.reset()
        pedometerDistanceAtProbeStart = pedometerDistanceMeters
        currentMotionSpeed = 0
    }

    func resumeTracking(fromAutoPause: Bool = false) {
        guard wantsTracking else { return }
        if fromAutoPause {
            promoteAutoPauseProbe()
        } else {
            requiresNewSegment = true
            filter.reset()
            pedometerDistanceAtLastTrackPoint = pedometerDistanceMeters
            startPedometerIfAvailable()
        }
        isAutoPauseProbing = false
        probeLocations = []
        startTrackingIfPermitted()
    }

    func stopTracking() -> StoppedLocationTrack {
        let motionTail = pendingMotionGapDistance
        let liveDistance = totalDistanceMeters
#if DEBUG
        let preservesLiveMetrics = testDistanceMeters != nil
#else
        let preservesLiveMetrics = false
#endif
        let result = StoppedLocationTrack(
            segments: locationSegments,
            liveDistanceMeters: liveDistance,
            motionSupplementDistanceMeters: motionAssistedDistanceMeters,
            motionTailDistanceMeters: motionTail,
            preservesLiveMetrics: preservesLiveMetrics
        )
        motionAssistedDistanceMeters += motionTail
        wantsTracking = false
        wantsPreparation = false
        isAutoPauseProbing = false
        trackingStartedAt = nil
        manager.stopUpdatingLocation()
        stopPedometer()
#if DEBUG
        isSimulatingLocations = false
        simulatedSpeedMetersPerSecond = nil
#endif
        return result
    }

    func restoreTracking(
        from points: [CLLocation],
        segmentStartIndices restoredSegmentStarts: Set<Int> = [],
        activityType: ActivityType = .running
    ) {
#if DEBUG
        isSimulatingLocations = false
        simulatedSpeedMetersPerSecond = nil
#endif
        self.activityType = activityType
        configureFilters(for: activityType)
        trackPoints = points
        trackCoordinates = points.map(\.coordinate)
        segmentStartIndices = restoredSegmentStarts.isEmpty && !points.isEmpty
            ? [0]
            : restoredSegmentStarts
        accumulatedDistanceMeters = locationSegments.reduce(0) { total, segment in
            total + zip(segment, segment.dropFirst()).reduce(0) { $0 + $1.0.distance(from: $1.1) }
        }
        elevationAccumulator.reset()
        for segment in locationSegments {
            elevationAccumulator.startNewSegment()
            for point in segment { elevationAccumulator.ingest(point) }
        }
        location = points.last
        updateSignalQuality(using: points.last)
        trackingStartedAt = Date()
        wantsTracking = true
        requiresNewSegment = true
        filter.reset()
        manager.stopUpdatingLocation()
    }

    var totalDistanceMeters: Double {
#if DEBUG
        if let testDistanceMeters { return testDistanceMeters }
#endif
        return accumulatedDistanceMeters + pendingMotionGapDistance
    }

    var elevationGainMeters: Double {
#if DEBUG
        if let testElevationGainMeters { return testElevationGainMeters }
#endif
        return elevationAccumulator.gainMeters
    }

    var recordingDiagnostics: LocationRecordingDiagnostics {
        LocationRecordingDiagnostics(
            receivedBatchCount: receivedBatchCount,
            maximumBatchSize: maximumBatchSize,
            acceptedTrackPointCount: acceptedTrackPointCount,
            rejectedLocationCount: rejectedLocationCount,
            stationaryLocationCount: stationaryLocationCount,
            segmentCount: locationSegments.count,
            motionAssistedDistanceMeters: motionAssistedDistanceMeters,
            finalDistanceCorrectionPercent: finalDistanceCorrectionPercent,
            routeMatchResult: routeMatchResult,
            signalQuality: signalQuality,
            accuracyAuthorization: accuracyAuthorization
        )
    }

    var currentPaceSecsPerKm: Double? {
#if DEBUG
        if let testCurrentPaceSecsPerKm { return testCurrentPaceSecsPerKm }
        if isSimulatingLocations,
           let simulatedSpeedMetersPerSecond,
           simulatedSpeedMetersPerSecond > 0 {
            return 1_000 / simulatedSpeedMetersPerSecond
        }
#endif
        guard let segment = locationSegments.last, segment.count > 2 else { return nil }
        let latestTimestamp = segment.last!.timestamp
        let recent = segment.drop { latestTimestamp.timeIntervalSince($0.timestamp) > paceWindowSeconds }
        guard recent.count > 2, let first = recent.first, let last = recent.last else { return nil }
        let distance = zip(recent, recent.dropFirst()).reduce(0.0) {
            $0 + $1.0.distance(from: $1.1)
        }
        let duration = last.timestamp.timeIntervalSince(first.timestamp)
        guard distance >= minimumValidPaceDistanceMeters,
              duration >= minimumValidPaceDurationSeconds
        else { return nil }

        let pace = duration / distance * 1_000
        let bounds: ClosedRange<Double> = switch activityType {
        case .cycling: 35...3_600
        case .walking, .hiking: 150...3_600
        case .running: 150...1_500
        case .swimming: 150...3_600
        }
        return bounds.contains(pace) ? pace : nil
    }

    func recordFinalReconciliation(
        liveDistanceMeters: Double,
        finalDistanceMeters: Double,
        routeMatchResult: String
    ) {
        if liveDistanceMeters > 0 {
            finalDistanceCorrectionPercent = min(
                100,
                abs(finalDistanceMeters - liveDistanceMeters) / liveDistanceMeters * 100
            )
        } else {
            finalDistanceCorrectionPercent = 0
        }
        self.routeMatchResult = routeMatchResult
    }

    func journalTrackPoints(startingAt index: Int) -> [JournalTrackPoint] {
        guard trackPoints.indices.contains(index) || index == trackPoints.count else { return [] }
        return trackPoints.indices.dropFirst(index).map { pointIndex in
            JournalTrackPoint(
                trackPoints[pointIndex],
                startsNewSegment: segmentStartIndices.contains(pointIndex)
            )
        }
    }

    private var pendingMotionGapDistance: Double {
        guard wantsTracking,
              !isAutoPauseProbing,
              supportsPedometerDistance,
              let lastAcceptedDeliveryAt,
              Date().timeIntervalSince(lastAcceptedDeliveryAt) >= motionGapThresholdSeconds
        else { return 0 }
        return max(0, pedometerDistanceMeters - pedometerDistanceAtLastTrackPoint)
    }

    private var supportsPedometerDistance: Bool {
        CMPedometer.isDistanceAvailable()
            && [.running, .walking, .hiking].contains(activityType)
    }

    private func resetRecordingState(preserving warmLocation: CLLocation?) {
        trackPoints = []
        trackCoordinates = []
        segmentStartIndices = []
        accumulatedDistanceMeters = 0
        elevationAccumulator.reset()
        receivedBatchCount = 0
        maximumBatchSize = 0
        acceptedTrackPointCount = 0
        rejectedLocationCount = 0
        stationaryLocationCount = 0
        motionAssistedDistanceMeters = 0
        finalDistanceCorrectionPercent = 0
        routeMatchResult = "not_available"
        pedometerDistanceMeters = 0
        pedometerDistanceAtLastTrackPoint = 0
        previousMotionLocation = nil
        currentMotionSpeed = nil
        lastAcceptedDeliveryAt = nil
        isAutoPauseProbing = false
        requiresNewSegment = false
        probeLocations = []
        filter.reset(with: warmLocation)
        location = warmLocation
    }

    private func configureFilters(for activityType: ActivityType) {
        filter = LocationTrackFilter(activityType: activityType)
        probeFilter = LocationTrackFilter(activityType: activityType)
    }

    private func requestTemporaryFullAccuracyIfNeeded() {
        accuracyAuthorization = manager.accuracyAuthorization
        guard wantsTracking || wantsPreparation,
              manager.accuracyAuthorization == .reducedAccuracy
        else { return }
        manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "WorkoutRoute")
    }

    private func startPedometerIfAvailable() {
        guard supportsPedometerDistance else { return }
        pedometer.stopUpdates()
        pedometerDistanceMeters = 0
        pedometerDistanceAtLastTrackPoint = 0
        pedometer.startUpdates(from: Date()) { [weak self] data, _ in
            guard let distance = data?.distance?.doubleValue else { return }
            Task { @MainActor in
                self?.pedometerDistanceMeters = max(0, distance)
            }
        }
    }

    private func stopPedometer() {
        pedometer.stopUpdates()
    }

    private func promoteAutoPauseProbe() {
        guard !probeLocations.isEmpty else {
            requiresNewSegment = true
            filter.reset()
            pedometerDistanceAtLastTrackPoint = pedometerDistanceMeters
            return
        }
        requiresNewSegment = true
        filter.reset()
        let priorSegmentCount = locationSegments.count
        for location in probeLocations {
            appendRecordedLocation(location, distanceIncrement: nil, allowsMotionBridge: false)
        }
        let probeMotionDistance = max(0, pedometerDistanceMeters - pedometerDistanceAtProbeStart)
        let promotedDistance = locationSegments.count > priorSegmentCount
            ? locationSegments.last.map { segment in
                zip(segment, segment.dropFirst()).reduce(0) { $0 + $1.0.distance(from: $1.1) }
            } ?? 0
            : 0
        if probeMotionDistance > promotedDistance {
            let supplement = probeMotionDistance - promotedDistance
            accumulatedDistanceMeters += supplement
            motionAssistedDistanceMeters += supplement
        }
        filter.reset(with: probeLocations.last)
        pedometerDistanceAtLastTrackPoint = pedometerDistanceMeters
    }

    private func beginSegment(with location: CLLocation) {
        requiresNewSegment = true
        filter.reset(with: location)
        appendRecordedLocation(location, distanceIncrement: 0, allowsMotionBridge: false)
    }

    private func handleLocation(_ newLocation: CLLocation, allowsMotionBridge: Bool) {
        updateSignalQuality(using: newLocation)
        guard isPublishable(newLocation) else {
            if wantsTracking { rejectedLocationCount += 1 }
            return
        }

        currentMotionSpeed = motionSpeed(for: newLocation)
        previousMotionLocation = newLocation
        location = newLocation

        if wantsPreparation && !wantsTracking {
            if preparedLocation == nil
                || newLocation.horizontalAccuracy < preparedLocation!.horizontalAccuracy
                || newLocation.timestamp > preparedLocation!.timestamp.addingTimeInterval(2) {
                preparedLocation = newLocation
            }
            return
        }
        guard wantsTracking else { return }

        if isAutoPauseProbing {
            let output = probeFilter.ingest(newLocation)
            currentMotionSpeed = output.estimatedSpeedMetersPerSecond ?? currentMotionSpeed
            if output.decision == .recorded, let filtered = output.filteredLocation {
                probeLocations.append(filtered)
            }
            return
        }

        if requiresNewSegment {
            filter.reset()
        }
        let output = filter.ingest(newLocation)
        currentMotionSpeed = output.estimatedSpeedMetersPerSecond ?? currentMotionSpeed
        switch output.decision {
        case .recorded:
            guard let filtered = output.filteredLocation else { return }
            appendRecordedLocation(
                filtered,
                distanceIncrement: output.distanceIncrementMeters,
                allowsMotionBridge: allowsMotionBridge
            )
        case .stationary:
            stationaryLocationCount += 1
        case .rejected:
            rejectedLocationCount += 1
        }
    }

    private func appendRecordedLocation(
        _ newLocation: CLLocation,
        distanceIncrement: Double?,
        allowsMotionBridge: Bool
    ) {
        var increment = distanceIncrement ?? trackPoints.last.map { $0.distance(from: newLocation) } ?? 0
        if requiresNewSegment || trackPoints.isEmpty {
            if !trackPoints.isEmpty { elevationAccumulator.startNewSegment() }
            segmentStartIndices.insert(trackPoints.count)
            increment = 0
            requiresNewSegment = false
        } else if allowsMotionBridge,
                  let previous = trackPoints.last,
                  newLocation.timestamp.timeIntervalSince(previous.timestamp) >= motionGapThresholdSeconds {
            let pedometerDistance = max(0, pedometerDistanceMeters - pedometerDistanceAtLastTrackPoint)
            if pedometerDistance > increment {
                motionAssistedDistanceMeters += pedometerDistance - increment
                increment = pedometerDistance
            }
        }

        accumulatedDistanceMeters += max(0, increment)
        trackPoints.append(newLocation)
        trackCoordinates.append(newLocation.coordinate)
        elevationAccumulator.ingest(newLocation)
        acceptedTrackPointCount += 1
        pedometerDistanceAtLastTrackPoint = pedometerDistanceMeters
        lastAcceptedDeliveryAt = Date()
    }

    private func motionSpeed(for current: CLLocation) -> Double? {
        let maximum = LocationFilterConfiguration(activityType: activityType).maximumSpeedMetersPerSecond
        if current.speed >= 0,
           current.speedAccuracy >= 0,
           current.speedAccuracy <= 3,
           current.speed <= maximum {
            return current.speed
        }
        guard let previousMotionLocation else { return nil }
        let duration = current.timestamp.timeIntervalSince(previousMotionLocation.timestamp)
        guard duration > 0 else { return nil }
        let uncertainty = hypot(
            max(0, current.horizontalAccuracy),
            max(0, previousMotionLocation.horizontalAccuracy)
        )
        let distance = max(0, previousMotionLocation.distance(from: current) - uncertainty * 0.5)
        let speed = distance / duration
        return speed <= maximum ? speed : nil
    }

    private func isPublishable(_ location: CLLocation) -> Bool {
        guard location.coordinate.latitude.isFinite,
              location.coordinate.longitude.isFinite,
              abs(location.coordinate.latitude) <= 90,
              abs(location.coordinate.longitude) <= 180,
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= maximumPublishedLocationAccuracyMeters,
              location.timestamp.timeIntervalSinceNow <= maximumFutureLocationSeconds
        else { return false }
        guard wantsTracking, let trackingStartedAt else { return true }
        return location.timestamp >= trackingStartedAt.addingTimeInterval(-maximumPreStartLocationAgeSeconds)
    }

    private func updateSignalQuality(using location: CLLocation?) {
        accuracyAuthorization = manager.accuracyAuthorization
        signalQuality = LocationSignalQuality.classify(
            location,
            accuracyAuthorization: accuracyAuthorization
        )
    }

    private static func segments(
        from points: [CLLocation],
        starts: Set<Int>
    ) -> [[CLLocation]] {
        guard !points.isEmpty else { return [] }
        var result: [[CLLocation]] = []
        var current: [CLLocation] = []
        for index in points.indices {
            if starts.contains(index), !current.isEmpty {
                result.append(current)
                current = []
            }
            current.append(points[index])
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

#if DEBUG
    func startSimulatedTracking(activityType: ActivityType = .running) {
        manager.stopUpdatingLocation()
        clearTestOverrides()
        isSimulatingLocations = true
        simulatedSpeedMetersPerSecond = nil
        self.activityType = activityType
        configureFilters(for: activityType)
        resetRecordingState(preserving: nil)
        trackingStartedAt = Date()
        wantsTracking = true
        signalQuality = .excellent
    }

    func ingestSimulatedLocation(_ newLocation: CLLocation) {
        guard wantsTracking, isSimulatingLocations else { return }
        guard trackPoints.last.map({ newLocation.timestamp > $0.timestamp }) ?? true else {
            rejectedLocationCount += 1
            return
        }
        receivedBatchCount += 1
        maximumBatchSize = max(maximumBatchSize, 1)
        simulatedSpeedMetersPerSecond = newLocation.speed > 0 ? newLocation.speed : nil
        let output = filter.ingest(newLocation)
        if output.decision == .recorded, let filtered = output.filteredLocation {
            appendRecordedLocation(
                filtered,
                distanceIncrement: output.distanceIncrementMeters,
                allowsMotionBridge: false
            )
        }
        location = newLocation
    }

    func seedLiveRunForUITest(
        distanceMeters: Double,
        elevationGainMeters: Double,
        currentPaceSecsPerKm: Double,
        trackPoints: [CLLocation]
    ) {
        isSimulatingLocations = false
        simulatedSpeedMetersPerSecond = nil
        testDistanceMeters = distanceMeters
        testElevationGainMeters = elevationGainMeters
        testCurrentPaceSecsPerKm = currentPaceSecsPerKm
        self.trackPoints = trackPoints
        trackCoordinates = trackPoints.map(\.coordinate)
        segmentStartIndices = trackPoints.isEmpty ? [] : [0]
        location = trackPoints.last
        signalQuality = .excellent
    }

    private func clearTestOverrides() {
        testDistanceMeters = nil
        testElevationGainMeters = nil
        testCurrentPaceSecsPerKm = nil
    }
#endif
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !locations.isEmpty else { return }
        Task { @MainActor in
            self.wantsOneShotLocation = false
#if DEBUG
            guard !self.isSimulatingLocations else { return }
#endif
            if self.wantsTracking {
                self.receivedBatchCount += 1
                self.maximumBatchSize = max(self.maximumBatchSize, locations.count)
            }
            for (index, location) in locations.enumerated() {
                self.handleLocation(
                    location,
                    allowsMotionBridge: locations.count == 1 || index == locations.count - 1
                )
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            self.accuracyAuthorization = manager.accuracyAuthorization
            self.updateSignalQuality(using: self.location)
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                self.requestTemporaryFullAccuracyIfNeeded()
                self.startTrackingIfPermitted()
                if self.wantsOneShotLocation && !self.wantsTracking && !self.wantsPreparation {
                    manager.requestLocation()
                }
            case .denied, .restricted:
                self.wantsTracking = false
                self.wantsPreparation = false
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.wantsOneShotLocation = false
            if self.location == nil { self.signalQuality = .unavailable }
        }
    }
}
