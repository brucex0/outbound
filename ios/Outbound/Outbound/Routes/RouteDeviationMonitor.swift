import CoreLocation
import Foundation
import MapKit

struct RouteDeviationMonitor {
    enum Event: Equatable {
        case leftRoute(distanceMeters: Double)
        case rejoinedRoute
    }

    private(set) var isOffRoute = false
    private var deviationStartedAt: Date?

    private let minimumDeviationMeters: Double
    private let sustainedDeviationSeconds: TimeInterval
    private let rejoinHysteresis: Double

    init(
        minimumDeviationMeters: Double = 60,
        sustainedDeviationSeconds: TimeInterval = 15,
        rejoinHysteresis: Double = 0.7
    ) {
        self.minimumDeviationMeters = minimumDeviationMeters
        self.sustainedDeviationSeconds = sustainedDeviationSeconds
        self.rejoinHysteresis = rejoinHysteresis
    }

    mutating func ingest(
        location: CLLocation,
        route: [CLLocationCoordinate2D],
        now: Date = Date()
    ) -> Event? {
        guard route.count > 1, location.horizontalAccuracy >= 0 else {
            deviationStartedAt = nil
            return nil
        }

        let distance = Self.distanceFromRoute(location.coordinate, route: route)
        let deviationThreshold = max(minimumDeviationMeters, location.horizontalAccuracy * 2)

        if isOffRoute {
            guard distance <= deviationThreshold * rejoinHysteresis else { return nil }
            isOffRoute = false
            deviationStartedAt = nil
            return .rejoinedRoute
        }

        guard distance > deviationThreshold else {
            deviationStartedAt = nil
            return nil
        }

        if let deviationStartedAt {
            guard now.timeIntervalSince(deviationStartedAt) >= sustainedDeviationSeconds else { return nil }
            isOffRoute = true
            return .leftRoute(distanceMeters: distance)
        }

        deviationStartedAt = now
        return nil
    }

    mutating func reset() {
        isOffRoute = false
        deviationStartedAt = nil
    }

    private static func distanceFromRoute(
        _ coordinate: CLLocationCoordinate2D,
        route: [CLLocationCoordinate2D]
    ) -> Double {
        let point = MKMapPoint(coordinate)
        var closestMapPointDistance = Double.greatestFiniteMagnitude

        for (startCoordinate, endCoordinate) in zip(route, route.dropFirst()) {
            let start = MKMapPoint(startCoordinate)
            let end = MKMapPoint(endCoordinate)
            let dx = end.x - start.x
            let dy = end.y - start.y
            let squaredLength = dx * dx + dy * dy
            let projection: Double
            if squaredLength == 0 {
                projection = 0
            } else {
                projection = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / squaredLength))
            }
            let projected = MKMapPoint(x: start.x + projection * dx, y: start.y + projection * dy)
            closestMapPointDistance = min(closestMapPointDistance, point.distance(to: projected))
        }

        return closestMapPointDistance
    }
}
