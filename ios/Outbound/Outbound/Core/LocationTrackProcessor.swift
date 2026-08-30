import CoreLocation
import MapKit

enum LocationSignalQuality: String, Equatable {
    case unavailable
    case reduced
    case poor
    case fair
    case good
    case excellent

    static func classify(
        _ location: CLLocation?,
        accuracyAuthorization: CLAccuracyAuthorization
    ) -> LocationSignalQuality {
        guard accuracyAuthorization == .fullAccuracy else { return .reduced }
        guard let location,
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy.isFinite
        else { return .unavailable }

        return switch location.horizontalAccuracy {
        case ...8: .excellent
        case ...15: .good
        case ...30: .fair
        default: .poor
        }
    }
}

struct LocationFilterConfiguration {
    let maximumSpeedMetersPerSecond: Double
    let maximumHorizontalAccuracyMeters: Double
    let stationarySpeedMetersPerSecond: Double

    init(activityType: ActivityType) {
        switch activityType {
        case .cycling:
            maximumSpeedMetersPerSecond = 25
            stationarySpeedMetersPerSecond = 1.0
        case .walking, .hiking:
            maximumSpeedMetersPerSecond = 7
            stationarySpeedMetersPerSecond = 0.45
        case .running:
            maximumSpeedMetersPerSecond = 10
            stationarySpeedMetersPerSecond = 0.65
        case .swimming:
            maximumSpeedMetersPerSecond = 5
            stationarySpeedMetersPerSecond = 0.35
        }
        maximumHorizontalAccuracyMeters = 50
    }
}

struct LocationFilterOutput {
    enum Decision {
        case recorded
        case stationary
        case rejected
    }

    let decision: Decision
    let filteredLocation: CLLocation?
    let distanceIncrementMeters: Double
    let estimatedSpeedMetersPerSecond: Double?
}

/// A lightweight constant-velocity filter for workout fixes. Core Location has
/// already fused device sensors; this layer uses the reported uncertainty to
/// prevent residual GPS jitter from becoming workout distance.
struct LocationTrackFilter {
    private let configuration: LocationFilterConfiguration
    private var anchorLocation: CLLocation?
    private var filteredLocation: CLLocation?
    private var velocityMapPointsPerSecond = MKMapPoint(x: 0, y: 0)

    init(activityType: ActivityType) {
        configuration = LocationFilterConfiguration(activityType: activityType)
    }

    mutating func reset(with baseline: CLLocation? = nil) {
        anchorLocation = baseline
        filteredLocation = baseline
        velocityMapPointsPerSecond = MKMapPoint(x: 0, y: 0)
    }

    mutating func ingest(_ raw: CLLocation) -> LocationFilterOutput {
        guard raw.coordinate.latitude.isFinite,
              raw.coordinate.longitude.isFinite,
              abs(raw.coordinate.latitude) <= 90,
              abs(raw.coordinate.longitude) <= 180,
              raw.horizontalAccuracy >= 0,
              raw.horizontalAccuracy <= configuration.maximumHorizontalAccuracyMeters
        else {
            return LocationFilterOutput(
                decision: .rejected,
                filteredLocation: nil,
                distanceIncrementMeters: 0,
                estimatedSpeedMetersPerSecond: nil
            )
        }

        guard let anchorLocation, let filteredLocation else {
            reset(with: raw)
            return LocationFilterOutput(
                decision: .recorded,
                filteredLocation: raw,
                distanceIncrementMeters: 0,
                estimatedSpeedMetersPerSecond: reliableReportedSpeed(for: raw)
            )
        }

        let interval = raw.timestamp.timeIntervalSince(anchorLocation.timestamp)
        guard interval > 0 else {
            return LocationFilterOutput(
                decision: .rejected,
                filteredLocation: nil,
                distanceIncrementMeters: 0,
                estimatedSpeedMetersPerSecond: nil
            )
        }

        if let speed = reliableReportedSpeed(for: raw),
           speed - max(0, raw.speedAccuracy) > configuration.maximumSpeedMetersPerSecond {
            return LocationFilterOutput(
                decision: .rejected,
                filteredLocation: nil,
                distanceIncrementMeters: 0,
                estimatedSpeedMetersPerSecond: nil
            )
        }

        let rawDistance = anchorLocation.distance(from: raw)
        let combinedUncertainty = hypot(
            max(0, anchorLocation.horizontalAccuracy),
            max(0, raw.horizontalAccuracy)
        )
        let plausibleMinimumDistance = max(0, rawDistance - min(30, combinedUncertainty * 0.7))
        guard plausibleMinimumDistance / interval <= configuration.maximumSpeedMetersPerSecond * 1.2 else {
            return LocationFilterOutput(
                decision: .rejected,
                filteredLocation: nil,
                distanceIncrementMeters: 0,
                estimatedSpeedMetersPerSecond: nil
            )
        }

        let movementThreshold = max(1.5, min(9, combinedUncertainty * 0.2))
        let reportedSpeed = reliableReportedSpeed(for: raw)
        let speedCouldBeStationary = reportedSpeed.map {
            $0 <= configuration.stationarySpeedMetersPerSecond + max(0, raw.speedAccuracy)
        } ?? true
        if rawDistance < movementThreshold, speedCouldBeStationary {
            return LocationFilterOutput(
                decision: .stationary,
                filteredLocation: nil,
                distanceIncrementMeters: 0,
                estimatedSpeedMetersPerSecond: reportedSpeed ?? 0
            )
        }

        let previousMapPoint = MKMapPoint(filteredLocation.coordinate)
        let measurement = MKMapPoint(raw.coordinate)
        let predictionInterval = min(interval, 10)
        let predicted = MKMapPoint(
            x: previousMapPoint.x + velocityMapPointsPerSecond.x * predictionInterval,
            y: previousMapPoint.y + velocityMapPointsPerSecond.y * predictionInterval
        )
        let alpha = measurementWeight(horizontalAccuracy: raw.horizontalAccuracy)
        let nextMapPoint = MKMapPoint(
            x: predicted.x + (measurement.x - predicted.x) * alpha,
            y: predicted.y + (measurement.y - predicted.y) * alpha
        )
        let beta = min(0.22, alpha * 0.24)
        velocityMapPointsPerSecond = MKMapPoint(
            x: velocityMapPointsPerSecond.x + (measurement.x - predicted.x) * beta / predictionInterval,
            y: velocityMapPointsPerSecond.y + (measurement.y - predicted.y) * beta / predictionInterval
        )

        let next = raw.replacingCoordinate(nextMapPoint.coordinate)
        let distance = filteredLocation.distance(from: next)
        let inferredSpeed = distance / interval
        self.anchorLocation = raw
        self.filteredLocation = next
        return LocationFilterOutput(
            decision: .recorded,
            filteredLocation: next,
            distanceIncrementMeters: distance,
            estimatedSpeedMetersPerSecond: reportedSpeed ?? inferredSpeed
        )
    }

    private func reliableReportedSpeed(for location: CLLocation) -> Double? {
        guard location.speed >= 0,
              location.speed.isFinite,
              location.speedAccuracy >= 0,
              location.speedAccuracy.isFinite,
              location.speedAccuracy <= 3
        else { return nil }
        return location.speed
    }

    private func measurementWeight(horizontalAccuracy: Double) -> Double {
        switch horizontalAccuracy {
        case ...5: 0.88
        case ...10: 0.76
        case ...20: 0.58
        case ...35: 0.40
        default: 0.28
        }
    }
}

struct ReconciledLocationTrack {
    let segments: [[CLLocation]]
    let distanceMeters: Double
    let elevationGainMeters: Double
    let routeMatchResult: String

    var points: [CLLocation] { segments.flatMap { $0 } }

    var segmentStartIndices: Set<Int> {
        var starts = Set<Int>()
        var index = 0
        for segment in segments where !segment.isEmpty {
            starts.insert(index)
            index += segment.count
        }
        return starts
    }
}

enum LocationTrackPostProcessor {
    static func reconcile(
        segments: [[CLLocation]],
        plannedRoute: PreparedRoute?
    ) -> ReconciledLocationTrack {
        let cleaned = segments
            .map { symmetricCleanup($0) }
            .filter { !$0.isEmpty }
        let matched = conditionallyMatch(cleaned, to: plannedRoute)
        let distance = matched.segments.reduce(0.0) { total, segment in
            total + zip(segment, segment.dropFirst()).reduce(0.0) {
                $0 + $1.0.distance(from: $1.1)
            }
        }
        let elevation = matched.segments.reduce(0.0) {
            $0 + ElevationGainCalculator.sanitizedElevationGainMeters(from: $1)
        }
        return ReconciledLocationTrack(
            segments: matched.segments,
            distanceMeters: distance,
            elevationGainMeters: elevation,
            routeMatchResult: matched.result
        )
    }

    private static func symmetricCleanup(_ points: [CLLocation]) -> [CLLocation] {
        guard points.count > 2 else { return points }
        var cleaned = points
        for index in 1..<(points.count - 1) {
            let previous = points[index - 1]
            let current = points[index]
            let next = points[index + 1]
            let direct = previous.distance(from: next)
            let incoming = previous.distance(from: current)
            let outgoing = current.distance(from: next)
            let detour = incoming + outgoing - direct
            let tolerance = max(6, min(20, current.horizontalAccuracy * 0.8))
            let neighborAccuracy = max(previous.horizontalAccuracy, next.horizontalAccuracy)
            let poorRelativeAccuracy = current.horizontalAccuracy > max(12, neighborAccuracy * 1.8)
            let doublesBack = direct < min(incoming, outgoing) * 0.7
            guard detour > tolerance, poorRelativeAccuracy || doublesBack else { continue }

            let previousPoint = MKMapPoint(previous.coordinate)
            let nextPoint = MKMapPoint(next.coordinate)
            let replacement = MKMapPoint(
                x: (previousPoint.x + nextPoint.x) / 2,
                y: (previousPoint.y + nextPoint.y) / 2
            )
            cleaned[index] = current.replacingCoordinate(replacement.coordinate)
        }
        return cleaned
    }

    private static func conditionallyMatch(
        _ segments: [[CLLocation]],
        to route: PreparedRoute?
    ) -> (segments: [[CLLocation]], result: String) {
        guard let route,
              let working = RouteWorkingGeometry.navigationPoints(
                route.directedPoints,
                maximumCount: RouteGuidanceEngine.maximumWorkingPointCount
              ),
              working.count > 1
        else { return (segments, "not_available") }

        var matcher = PlannedRouteMatcher(coordinates: working.map(\.locationCoordinate))
        var proposed: [[CLLocation]] = []
        var eligibleCount = 0
        var matchedCount = 0
        for segment in segments {
            matcher.beginSegment()
            var proposedSegment: [CLLocation] = []
            for location in segment {
                guard location.horizontalAccuracy <= 20 else {
                    proposedSegment.append(location)
                    continue
                }
                eligibleCount += 1
                if let coordinate = matcher.matchedCoordinate(for: location) {
                    matchedCount += 1
                    proposedSegment.append(location.replacingCoordinate(coordinate))
                } else {
                    proposedSegment.append(location)
                }
            }
            proposed.append(proposedSegment)
        }

        guard eligibleCount >= 5,
              Double(matchedCount) / Double(eligibleCount) >= 0.7
        else { return (segments, "low_confidence") }
        return (proposed, "matched")
    }
}

private struct PlannedRouteMatcher {
    private let points: [MKMapPoint]
    private var lastSegmentIndex: Int?

    init(coordinates: [CLLocationCoordinate2D]) {
        points = coordinates.map(MKMapPoint.init)
    }

    mutating func beginSegment() {
        lastSegmentIndex = nil
    }

    mutating func matchedCoordinate(for location: CLLocation) -> CLLocationCoordinate2D? {
        guard points.count > 1 else { return nil }
        let candidateIndices: ClosedRange<Int>
        if let lastSegmentIndex {
            candidateIndices = max(0, lastSegmentIndex - 80)...min(points.count - 2, lastSegmentIndex + 160)
        } else {
            candidateIndices = 0...(points.count - 2)
        }

        let locationPoint = MKMapPoint(location.coordinate)
        var best: (index: Int, point: MKMapPoint, distance: Double, bearing: Double)?
        for index in candidateIndices {
            let start = points[index]
            let end = points[index + 1]
            let dx = end.x - start.x
            let dy = end.y - start.y
            let squaredLength = dx * dx + dy * dy
            guard squaredLength > 0 else { continue }
            let fraction = min(1, max(0, (
                (locationPoint.x - start.x) * dx + (locationPoint.y - start.y) * dy
            ) / squaredLength))
            let projected = MKMapPoint(x: start.x + dx * fraction, y: start.y + dy * fraction)
            let distance = locationPoint.distance(to: projected)
            let bearing = Self.bearing(from: start.coordinate, to: end.coordinate)
            if best == nil || distance < best!.distance {
                best = (index, projected, distance, bearing)
            }
        }

        guard let best,
              best.distance <= max(4, min(12, location.horizontalAccuracy * 0.75))
        else { return nil }
        if location.speed >= 1,
           location.course >= 0,
           location.courseAccuracy >= 0,
           location.courseAccuracy <= 45,
           Self.angularDifference(location.course, best.bearing) > 75 {
            return nil
        }
        lastSegmentIndex = best.index
        return best.point.coordinate
    }

    private static func bearing(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> Double {
        let startLat = start.latitude * .pi / 180
        let endLat = end.latitude * .pi / 180
        let deltaLongitude = (end.longitude - start.longitude) * .pi / 180
        let y = sin(deltaLongitude) * cos(endLat)
        let x = cos(startLat) * sin(endLat) - sin(startLat) * cos(endLat) * cos(deltaLongitude)
        let degrees = atan2(y, x) * 180 / .pi
        return degrees >= 0 ? degrees : degrees + 360
    }

    private static func angularDifference(_ lhs: Double, _ rhs: Double) -> Double {
        let raw = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return raw > 180 ? 360 - raw : raw
    }
}

private extension CLLocation {
    func replacingCoordinate(_ coordinate: CLLocationCoordinate2D) -> CLLocation {
        CLLocation(
            coordinate: coordinate,
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            course: course,
            courseAccuracy: courseAccuracy,
            speed: speed,
            speedAccuracy: speedAccuracy,
            timestamp: timestamp
        )
    }
}
