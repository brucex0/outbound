import CoreLocation
import Foundation

enum ElevationGainCalculator {
    private static let maximumVerticalAccuracyMeters = 20.0
    private static let maximumVerticalSpeedMetersPerSecond = 3.0
    private static let minimumDistanceForGradeCheckMeters = 3.0
    private static let maximumGrade = 0.50
    private static let medianWindowSize = 5

    static func sanitizedElevationRangeMeters(from locations: [CLLocation]) -> Double {
        let altitudes = sanitizedAltitudes(from: locations)
        guard let minimum = altitudes.min(),
              let maximum = altitudes.max(),
              maximum > minimum else {
            return 0
        }

        return maximum - minimum
    }

    static func sanitizedAltitudes(from locations: [CLLocation]) -> [Double] {
        let accepted = acceptedAltitudes(from: locations)
        guard accepted.count >= 2 else { return accepted }
        return rollingMedian(accepted, windowSize: medianWindowSize)
    }

    private static func acceptedAltitudes(from locations: [CLLocation]) -> [Double] {
        var acceptedLocations: [CLLocation] = []

        for location in locations {
            guard isValidAltitude(location.altitude),
                  isValidVerticalAccuracy(location.verticalAccuracy) else {
                continue
            }

            if let previous = acceptedLocations.last,
               !isPlausibleTransition(from: previous, to: location) {
                continue
            }

            acceptedLocations.append(location)
        }

        return acceptedLocations.map(\.altitude)
    }

    private static func isValidAltitude(_ altitude: CLLocationDistance) -> Bool {
        altitude.isFinite
    }

    private static func isValidVerticalAccuracy(_ accuracy: CLLocationAccuracy) -> Bool {
        accuracy >= 0 && accuracy <= maximumVerticalAccuracyMeters
    }

    private static func isPlausibleTransition(from previous: CLLocation, to current: CLLocation) -> Bool {
        let altitudeDelta = abs(current.altitude - previous.altitude)
        let duration = current.timestamp.timeIntervalSince(previous.timestamp)

        if duration > 0,
           altitudeDelta / duration > maximumVerticalSpeedMetersPerSecond {
            return false
        }

        let distance = previous.distance(from: current)
        if distance >= minimumDistanceForGradeCheckMeters,
           altitudeDelta / distance > maximumGrade {
            return false
        }

        return true
    }

    private static func rollingMedian(_ values: [Double], windowSize: Int) -> [Double] {
        guard windowSize > 1, values.count > 2 else { return values }

        let radius = windowSize / 2
        return values.indices.map { index in
            let lowerBound = max(values.startIndex, index - radius)
            let upperBound = min(values.endIndex, index + radius + 1)
            let window = values[lowerBound..<upperBound].sorted()
            return window[window.count / 2]
        }
    }
}
