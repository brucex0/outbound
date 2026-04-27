import CoreLocation
import Foundation

struct ActiveSessionSnapshot: Equatable {
    let recordedAt: Date
    let startedAt: Date?
    let elapsedSeconds: Int
    let distanceMeters: Double
    let currentPaceSecsPerKm: Double?
    let heartRate: Int?
    let location: SessionLocation?
    let isActive: Bool

    static var empty: ActiveSessionSnapshot {
        ActiveSessionSnapshot(
            recordedAt: Date(),
            startedAt: nil,
            elapsedSeconds: 0,
            distanceMeters: 0,
            currentPaceSecsPerKm: nil,
            heartRate: nil,
            location: nil,
            isActive: false
        )
    }

    var distanceKilometers: Double {
        distanceMeters / 1000
    }
}

struct SessionLocation: Equatable {
    let latitude: Double
    let longitude: Double
    let altitudeMeters: Double
    let horizontalAccuracyMeters: Double
    let speedMetersPerSecond: Double?
    let courseDegrees: Double?

    init(_ location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        altitudeMeters = location.altitude
        horizontalAccuracyMeters = location.horizontalAccuracy
        speedMetersPerSecond = location.speed >= 0 ? location.speed : nil
        courseDegrees = location.course >= 0 ? location.course : nil
    }
}
