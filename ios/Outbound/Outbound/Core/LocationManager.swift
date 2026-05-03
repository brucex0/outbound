import CoreLocation
import Combine

@MainActor
final class LocationManager: NSObject, ObservableObject {
    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var trackPoints: [CLLocation] = []

    private let manager = CLLocationManager()
    private var wantsTracking = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 5  // meters
        manager.activityType = .fitness
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startTracking() {
        trackPoints = []
        wantsTracking = true

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
        manager.stopUpdatingLocation()
        return trackPoints
    }

    var totalDistanceMeters: Double {
        guard trackPoints.count > 1 else { return 0 }
        return zip(trackPoints, trackPoints.dropFirst())
            .reduce(0) { $0 + $1.0.distance(from: $1.1) }
    }

    var elevationGainMeters: Double {
        guard trackPoints.count > 1 else { return 0 }
        return zip(trackPoints, trackPoints.dropFirst()).reduce(0) { total, pair in
            let previous = pair.0
            let current = pair.1
            guard previous.verticalAccuracy >= 0, current.verticalAccuracy >= 0 else {
                return total
            }

            let gain = current.altitude - previous.altitude
            guard gain > 1 else { return total }
            return total + gain
        }
    }

    var currentPaceSecsPerKm: Double? {
        guard trackPoints.count > 5 else { return nil }
        let recent = Array(trackPoints.suffix(10))
        let dist = zip(recent, recent.dropFirst()).reduce(0.0) { $0 + $1.0.distance(from: $1.1) }
        guard dist > 0 else { return nil }
        let time = recent.last!.timestamp.timeIntervalSince(recent.first!.timestamp)
        return (time / dist) * 1000
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.location = loc
            self.trackPoints.append(loc)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                self.startTrackingIfPermitted()
            case .denied, .restricted:
                self.wantsTracking = false
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }
    }
}
