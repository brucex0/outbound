import CoreLocation
import Combine

struct LocationRecordingDiagnostics: Equatable {
    let receivedBatchCount: Int
    let maximumBatchSize: Int
    let acceptedTrackPointCount: Int
    let rejectedLocationCount: Int

    var deliveryMode: String {
        if receivedBatchCount == 0 { return "no_updates" }
        return maximumBatchSize > 1 ? "batched_updates" : "single_updates"
    }

    var result: String {
        if acceptedTrackPointCount == 0 { return "no_usable_points" }
        return rejectedLocationCount == 0 ? "all_accepted" : "some_filtered"
    }
}

@MainActor
final class LocationManager: NSObject, ObservableObject {
    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var trackPoints: [CLLocation] = []
    @Published private(set) var trackCoordinates: [CLLocationCoordinate2D] = []

    private var maximumValidSpeedMetersPerSecond: Double = 10
    private let maximumValidLocationAccuracyMeters: Double = 40
    private let minimumValidPaceDistanceMeters: Double = 20
    private let minimumValidPaceDurationSeconds: TimeInterval = 5
    private let minimumValidPaceSecsPerKm: Double = 150
    private let maximumValidPaceSecsPerKm: Double = 1500
    private let maximumPreStartLocationAgeSeconds: TimeInterval = 3

    var currentSpeedMetersPerSecond: Double? {
        guard let location = location else { return nil }
        if location.speed >= 0 {
            return location.speed <= maximumValidSpeedMetersPerSecond ? location.speed : nil
        }

        guard let previous = trackPoints.last else { return nil }
        let duration = location.timestamp.timeIntervalSince(previous.timestamp)
        if duration == 0 {
            let age = Date().timeIntervalSince(location.timestamp)
            return age >= 10 ? 0 : nil
        }

        let distance = previous.distance(from: location)
        let impliedSpeed = distance / duration
        return impliedSpeed <= maximumValidSpeedMetersPerSecond ? impliedSpeed : nil
    }

    private let manager = CLLocationManager()
    private var wantsTracking = false
    private var wantsOneShotLocation = false
    private var trackingStartedAt: Date?
    private var accumulatedDistanceMeters: Double = 0
    private var elevationAccumulator = ElevationGainCalculator.StreamingRangeAccumulator()
    private var receivedBatchCount = 0
    private var maximumBatchSize = 0
    private var acceptedTrackPointCount = 0
    private var rejectedLocationCount = 0
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
        manager.distanceFilter = 1  // meters
        manager.activityType = .fitness
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
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

    func startTracking(activityType: ActivityType = .running) {
#if DEBUG
        clearTestOverrides()
        isSimulatingLocations = false
        simulatedSpeedMetersPerSecond = nil
#endif
        trackPoints = []
        trackCoordinates = []
        accumulatedDistanceMeters = 0
        elevationAccumulator.reset()
        receivedBatchCount = 0
        maximumBatchSize = 0
        acceptedTrackPointCount = 0
        rejectedLocationCount = 0
        location = nil
        trackingStartedAt = Date()
        wantsTracking = true
        configureValidation(for: activityType)

        switch manager.authorizationStatus {
        case .notDetermined:
            requestPermission()
        case .authorizedAlways, .authorizedWhenInUse:
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
        guard wantsTracking else { return }
        manager.startUpdatingLocation()
    }

    func pauseTracking() {
        guard wantsTracking else { return }
        manager.stopUpdatingLocation()
    }

    func resumeTracking() {
        startTrackingIfPermitted()
    }

    func stopTracking() -> [CLLocation] {
        wantsTracking = false
        trackingStartedAt = nil
        manager.stopUpdatingLocation()
#if DEBUG
        isSimulatingLocations = false
        simulatedSpeedMetersPerSecond = nil
#endif
        return trackPoints
    }

    func restoreTracking(from points: [CLLocation], activityType: ActivityType = .running) {
#if DEBUG
        isSimulatingLocations = false
        simulatedSpeedMetersPerSecond = nil
#endif
        configureValidation(for: activityType)
        trackPoints = points
        trackCoordinates = points.map(\.coordinate)
        accumulatedDistanceMeters = zip(points, points.dropFirst())
            .reduce(0) { $0 + $1.0.distance(from: $1.1) }
        elevationAccumulator.reset()
        for point in points { elevationAccumulator.ingest(point) }
        location = points.last
        trackingStartedAt = Date()
        wantsTracking = true
        manager.stopUpdatingLocation()
    }

    var totalDistanceMeters: Double {
#if DEBUG
        if let testDistanceMeters { return testDistanceMeters }
#endif
        return accumulatedDistanceMeters
    }

    var elevationGainMeters: Double {
#if DEBUG
        if let testElevationGainMeters { return testElevationGainMeters }
#endif
        return elevationAccumulator.rangeMeters
    }

    var recordingDiagnostics: LocationRecordingDiagnostics {
        LocationRecordingDiagnostics(
            receivedBatchCount: receivedBatchCount,
            maximumBatchSize: maximumBatchSize,
            acceptedTrackPointCount: acceptedTrackPointCount,
            rejectedLocationCount: rejectedLocationCount
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
        guard trackPoints.count > 5 else { return nil }
        let recent = Array(trackPoints.suffix(10))
        let dist = zip(recent, recent.dropFirst()).reduce(0.0) { $0 + $1.0.distance(from: $1.1) }
        guard dist >= minimumValidPaceDistanceMeters else { return nil }
        let time = recent.last!.timestamp.timeIntervalSince(recent.first!.timestamp)
        guard time >= minimumValidPaceDurationSeconds else { return nil }

        let pace = (time / dist) * 1000
        let minimumPace = maximumValidSpeedMetersPerSecond > 10 ? 35 : minimumValidPaceSecsPerKm
        let maximumPace = maximumValidSpeedMetersPerSecond < 10 ? 3_600 : maximumValidPaceSecsPerKm
        guard pace >= minimumPace, pace <= maximumPace else { return nil }
        return pace
    }

    private func configureValidation(for activityType: ActivityType) {
        maximumValidSpeedMetersPerSecond = switch activityType {
        case .cycling: 25
        case .walking, .hiking: 7
        case .running: 10
        case .swimming: 5
        }
    }

#if DEBUG
    func startSimulatedTracking(activityType: ActivityType = .running) {
        manager.stopUpdatingLocation()
        clearTestOverrides()
        isSimulatingLocations = true
        simulatedSpeedMetersPerSecond = nil
        trackPoints = []
        trackCoordinates = []
        accumulatedDistanceMeters = 0
        elevationAccumulator.reset()
        receivedBatchCount = 0
        maximumBatchSize = 0
        acceptedTrackPointCount = 0
        rejectedLocationCount = 0
        location = nil
        trackingStartedAt = Date()
        wantsTracking = true
        configureValidation(for: activityType)
    }

    func ingestSimulatedLocation(_ newLocation: CLLocation) {
        guard wantsTracking, isSimulatingLocations else { return }
        guard trackPoints.last.map({ newLocation.timestamp > $0.timestamp }) ?? true else {
            rejectedLocationCount += 1
            return
        }

        receivedBatchCount += 1
        maximumBatchSize = max(maximumBatchSize, 1)
        if let previous = trackPoints.last {
            accumulatedDistanceMeters += previous.distance(from: newLocation)
        }
        trackPoints.append(newLocation)
        trackCoordinates.append(newLocation.coordinate)
        elevationAccumulator.ingest(newLocation)
        acceptedTrackPointCount += 1
        simulatedSpeedMetersPerSecond = newLocation.speed > 0 ? newLocation.speed : nil
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
        location = trackPoints.last
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

            var latestAcceptedLocation: CLLocation?
            for location in locations {
                guard self.shouldAcceptLocationUpdate(location) else {
                    if self.wantsTracking { self.rejectedLocationCount += 1 }
                    continue
                }
                if self.wantsTracking {
                    guard self.shouldAppendTrackPoint(location) else {
                        self.rejectedLocationCount += 1
                        continue
                    }
                    if let previous = self.trackPoints.last {
                        self.accumulatedDistanceMeters += previous.distance(from: location)
                    }
                    self.trackPoints.append(location)
                    self.trackCoordinates.append(location.coordinate)
                    self.elevationAccumulator.ingest(location)
                    self.acceptedTrackPointCount += 1
                }
                latestAcceptedLocation = location
            }

            // Publishing once after the chronological batch is fully ingested keeps
            // downstream metrics consistent while retaining every background fix.
            if let latestAcceptedLocation {
                self.location = latestAcceptedLocation
            }
        }
    }

    private func shouldAcceptLocationUpdate(_ location: CLLocation) -> Bool {
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= maximumValidLocationAccuracyMeters else {
            return false
        }

        guard wantsTracking, let trackingStartedAt else {
            return true
        }

        return location.timestamp >= trackingStartedAt.addingTimeInterval(-maximumPreStartLocationAgeSeconds)
    }

    private func shouldAppendTrackPoint(_ location: CLLocation) -> Bool {
        if location.speed >= 0,
           location.speed > maximumValidSpeedMetersPerSecond {
            return false
        }

        if let previous = trackPoints.last {
            let interval = location.timestamp.timeIntervalSince(previous.timestamp)
            guard interval > 0 else { return false }
            let distance = previous.distance(from: location)
            let impliedSpeed = distance / interval
            return impliedSpeed <= maximumValidSpeedMetersPerSecond
        }

        return true
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                self.startTrackingIfPermitted()
                if self.wantsOneShotLocation && !self.wantsTracking {
                    manager.requestLocation()
                }
            case .denied, .restricted:
                self.wantsTracking = false
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
        }
    }
}
