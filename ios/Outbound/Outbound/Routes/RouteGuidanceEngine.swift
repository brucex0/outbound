import CoreLocation
import Foundation
import MapKit

enum RouteGuidanceState: String, Codable, Equatable {
    case acquiring
    case onRoute
    case offRoute
    case wrongWay
    case arrived
}

enum RouteGuidanceEvent: Equatable {
    case progressReached(Int)
    case deviated(distanceMeters: Double)
    case rejoined
    case wrongWay
    case arrival
}

struct RouteGuidanceRecoverySeed: Codable, Equatable {
    let progressMeters: Double
    let segmentIndex: Int
    let hasAcquiredStart: Bool
    let isOffRoute: Bool
    let isWrongWay: Bool
    let hasArrived: Bool
    let reachedProgressPercents: [Int]
}

struct RouteGuidanceSnapshot: Equatable {
    let state: RouteGuidanceState
    let progressMeters: Double
    let totalDistanceMeters: Double
    let remainingDistanceMeters: Double
    let distanceFromRouteMeters: Double
    let progressFraction: Double
    let nearestSegmentIndex: Int
    let events: [RouteGuidanceEvent]

    var isOffRoute: Bool { state == .offRoute }
    var isWrongWay: Bool { state == .wrongWay }
    var hasArrived: Bool { state == .arrived }
}

/// A deterministic, on-device exact-polyline progress engine. Canonical route
/// geometry remains on `PreparedRoute`; this type owns only a bounded working
/// copy and immutable lookup structures prepared once at session start.
struct RouteGuidanceEngine {
    private struct Segment {
        let start: MKMapPoint
        let end: MKMapPoint
        let lengthMeters: Double
        let cumulativeStartMeters: Double
        let bearingDegrees: Double
    }

    private struct GridCell: Hashable {
        let x: Int
        let y: Int
    }

    private struct Projection {
        let segmentIndex: Int
        let progressMeters: Double
        let distanceMeters: Double
        let routeBearingDegrees: Double
    }

    static let maximumWorkingPointCount = 16_384
    private static let gridCellMeters = 120.0
    private static let localSegmentRadius = 96
    private static let maximumSegmentsPerGridCell = 192
    private static let maximumCandidatesPerUpdate = 384

    let navigationCoordinates: [CLLocationCoordinate2D]
    let displayCoordinates: [CLLocationCoordinate2D]
    let startCoordinate: CLLocationCoordinate2D
    let destinationCoordinate: CLLocationCoordinate2D
    let totalDistanceMeters: Double
    let isLoop: Bool

    private let segments: [Segment]
    private let spatialIndex: [GridCell: [Int]]
    private let gridCellMapUnits: Double
    private let arrivalDistanceMeters: Double

    private var currentSegmentIndex: Int
    private var currentProgressMeters: Double
    private var offRoute = false
    private var wrongWay = false
    private var arrived = false
    private var reachedProgressPercents: Set<Int>
    private var hasAcquiredStart: Bool
    private var deviationBeganAt: Date?
    private var wrongWayBeganAt: Date?
    private var correctDirectionBeganAt: Date?
    private var arrivalBeganAt: Date?
    private var lastUpdateAt: Date?
    private var lastLocation: CLLocation?
    private var hasAcceptedProjection: Bool

    private(set) var currentSnapshot: RouteGuidanceSnapshot

    init?(route: PreparedRoute, recoverySeed: RouteGuidanceRecoverySeed? = nil) {
        let canonical = route.points
        guard canonical.allSatisfy({
            $0.latitude.isFinite && $0.longitude.isFinite
                && abs($0.latitude) <= 90 && abs($0.longitude) <= 180
        }), canonical.count > 1 else { return nil }

        guard let canonicalWorking = RouteWorkingGeometry.navigationPoints(
            canonical,
            maximumCount: Self.maximumWorkingPointCount
        ), canonicalWorking.count > 1 else { return nil }
        let working = route.direction == .forward
            ? canonicalWorking
            : Array(canonicalWorking.reversed())

        let coordinates = working.map(\.locationCoordinate)
        let mapPoints = coordinates.map(MKMapPoint.init)
        var preparedSegments: [Segment] = []
        preparedSegments.reserveCapacity(mapPoints.count - 1)
        var cumulativeDistance = 0.0
        for index in 0..<(mapPoints.count - 1) {
            let start = mapPoints[index]
            let end = mapPoints[index + 1]
            let length = start.distance(to: end)
            guard length.isFinite,
                  length > RouteWorkingGeometry.minimumUsableSegmentDistanceMeters
            else { continue }
            preparedSegments.append(Segment(
                start: start,
                end: end,
                lengthMeters: length,
                cumulativeStartMeters: cumulativeDistance,
                bearingDegrees: Self.bearing(from: coordinates[index], to: coordinates[index + 1])
            ))
            cumulativeDistance += length
        }
        guard !preparedSegments.isEmpty, cumulativeDistance.isFinite, cumulativeDistance >= 10 else { return nil }

        navigationCoordinates = coordinates
        displayCoordinates = RouteWorkingGeometry.displayPoints(working).map(\.locationCoordinate)
        startCoordinate = coordinates[0]
        destinationCoordinate = coordinates[coordinates.count - 1]
        totalDistanceMeters = cumulativeDistance
        isLoop = route.isLoop || CLLocation(latitude: startCoordinate.latitude, longitude: startCoordinate.longitude)
            .distance(from: CLLocation(latitude: destinationCoordinate.latitude, longitude: destinationCoordinate.longitude))
            <= min(80, cumulativeDistance * 0.04)
        segments = preparedSegments

        let representativeLatitude = (startCoordinate.latitude + destinationCoordinate.latitude) / 2
        gridCellMapUnits = Self.gridCellMeters / max(0.000_001, MKMetersPerMapPointAtLatitude(representativeLatitude))
        spatialIndex = Self.makeSpatialIndex(
            segments: preparedSegments,
            cellMapUnits: gridCellMapUnits
        )
        arrivalDistanceMeters = max(20, min(45, cumulativeDistance * 0.01))

        let restoredArrival = recoverySeed?.hasArrived ?? false
        let seedProgress = restoredArrival
            ? cumulativeDistance
            : min(cumulativeDistance, max(0, recoverySeed?.progressMeters ?? 0))
        currentSegmentIndex = min(preparedSegments.count - 1, max(0, recoverySeed?.segmentIndex ?? 0))
        currentProgressMeters = seedProgress
        arrived = restoredArrival
        hasAcquiredStart = arrived || (recoverySeed?.hasAcquiredStart ?? false)
        offRoute = arrived ? false : (recoverySeed?.isOffRoute ?? false)
        wrongWay = arrived ? false : (recoverySeed?.isWrongWay ?? false)
        reachedProgressPercents = Set(recoverySeed?.reachedProgressPercents ?? [])
        hasAcceptedProjection = recoverySeed != nil && hasAcquiredStart

        let state: RouteGuidanceState = arrived
            ? .arrived
            : (hasAcquiredStart ? (offRoute ? .offRoute : (wrongWay ? .wrongWay : .onRoute)) : .acquiring)
        currentSnapshot = RouteGuidanceSnapshot(
            state: state,
            progressMeters: seedProgress,
            totalDistanceMeters: cumulativeDistance,
            remainingDistanceMeters: max(0, cumulativeDistance - seedProgress),
            distanceFromRouteMeters: 0,
            progressFraction: min(1, max(0, seedProgress / cumulativeDistance)),
            nearestSegmentIndex: currentSegmentIndex,
            events: []
        )
    }

    mutating func ingest(_ location: CLLocation, now: Date = Date()) -> RouteGuidanceSnapshot? {
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 80,
              location.coordinate.latitude.isFinite,
              location.coordinate.longitude.isFinite
        else { return nil }

        if arrived {
            let snapshot = RouteGuidanceSnapshot(
                state: .arrived,
                progressMeters: totalDistanceMeters,
                totalDistanceMeters: totalDistanceMeters,
                remainingDistanceMeters: 0,
                distanceFromRouteMeters: currentSnapshot.distanceFromRouteMeters,
                progressFraction: 1,
                nearestSegmentIndex: currentSegmentIndex,
                events: []
            )
            currentSnapshot = snapshot
            lastUpdateAt = now
            lastLocation = location
            return snapshot
        }

        if !hasAcquiredStart {
            let start = CLLocation(
                latitude: startCoordinate.latitude,
                longitude: startCoordinate.longitude
            )
            let distanceToStart = location.distance(from: start)
            let acquisitionDistance = max(60, location.horizontalAccuracy * 2)
            guard distanceToStart <= acquisitionDistance else {
                let snapshot = RouteGuidanceSnapshot(
                    state: .acquiring,
                    progressMeters: 0,
                    totalDistanceMeters: totalDistanceMeters,
                    remainingDistanceMeters: totalDistanceMeters,
                    distanceFromRouteMeters: distanceToStart,
                    progressFraction: 0,
                    nearestSegmentIndex: 0,
                    events: []
                )
                currentSnapshot = snapshot
                lastUpdateAt = now
                lastLocation = location
                return snapshot
            }
            hasAcquiredStart = true
        }

        let candidates = candidateSegmentIndices(for: MKMapPoint(location.coordinate))
        guard let projection = bestProjection(for: location, candidates: candidates, now: now) else { return nil }

        let priorProgress = currentProgressMeters
        currentSegmentIndex = projection.segmentIndex
        currentProgressMeters = min(totalDistanceMeters, max(0, projection.progressMeters))
        hasAcceptedProjection = true

        var events: [RouteGuidanceEvent] = []
        updateDeviation(
            distanceMeters: projection.distanceMeters,
            accuracyMeters: location.horizontalAccuracy,
            now: now,
            events: &events
        )
        updateWrongWay(
            location: location,
            routeBearingDegrees: projection.routeBearingDegrees,
            priorProgressMeters: priorProgress,
            now: now,
            events: &events
        )
        updateArrival(location: location, now: now, events: &events)
        appendProgressEvents(to: &events)

        let state: RouteGuidanceState
        if arrived { state = .arrived }
        else if offRoute { state = .offRoute }
        else if wrongWay { state = .wrongWay }
        else { state = .onRoute }

        let fraction = min(1, max(0, currentProgressMeters / totalDistanceMeters))
        let snapshot = RouteGuidanceSnapshot(
            state: state,
            progressMeters: currentProgressMeters,
            totalDistanceMeters: totalDistanceMeters,
            remainingDistanceMeters: max(0, totalDistanceMeters - currentProgressMeters),
            distanceFromRouteMeters: projection.distanceMeters,
            progressFraction: fraction,
            nearestSegmentIndex: currentSegmentIndex,
            events: events
        )
        currentSnapshot = snapshot
        lastUpdateAt = now
        lastLocation = location
        return snapshot
    }

    func makeRecoverySeed() -> RouteGuidanceRecoverySeed {
        RouteGuidanceRecoverySeed(
            progressMeters: currentProgressMeters,
            segmentIndex: currentSegmentIndex,
            hasAcquiredStart: hasAcquiredStart,
            isOffRoute: offRoute,
            isWrongWay: wrongWay,
            hasArrived: arrived,
            reachedProgressPercents: reachedProgressPercents.sorted()
        )
    }

    private func candidateSegmentIndices(for point: MKMapPoint) -> [Int] {
        var result: [Int] = []
        result.reserveCapacity(Self.maximumCandidatesPerUpdate)
        var seen = Set<Int>()

        func append(_ index: Int) {
            guard result.count < Self.maximumCandidatesPerUpdate,
                  segments.indices.contains(index),
                  seen.insert(index).inserted
            else { return }
            result.append(index)
        }

        let center = gridCell(for: point)
        for radius in 0...2 {
            for x in (center.x - radius)...(center.x + radius) {
                for y in (center.y - radius)...(center.y + radius) {
                    guard abs(x - center.x) == radius || abs(y - center.y) == radius else { continue }
                    for index in spatialIndex[GridCell(x: x, y: y)] ?? [] { append(index) }
                }
            }
            if result.count >= 12 { break }
        }

        let lower = max(0, currentSegmentIndex - Self.localSegmentRadius)
        let upper = min(segments.count - 1, currentSegmentIndex + Self.localSegmentRadius)
        if lower <= upper {
            for index in lower...upper { append(index) }
        }
        return result
    }

    private func bestProjection(
        for location: CLLocation,
        candidates: [Int],
        now: Date
    ) -> Projection? {
        let point = MKMapPoint(location.coordinate)
        let elapsed = max(0.5, min(60, lastUpdateAt.map { now.timeIntervalSince($0) } ?? 1))
        let measuredSpeed: Double = {
            if location.speed >= 0 { return location.speed }
            guard let lastLocation else { return 0 }
            return lastLocation.distance(from: location) / elapsed
        }()
        let maximumAdvance = max(35, measuredSpeed * elapsed * 2.5 + 25)
        let maximumRegression = max(20, measuredSpeed * elapsed * 1.5 + 15)
        let hasReliableCourse = location.course >= 0 && location.course <= 360 && measuredSpeed >= 0.8

        var best: (projection: Projection, score: Double)?
        for index in candidates {
            let segment = segments[index]
            let dx = segment.end.x - segment.start.x
            let dy = segment.end.y - segment.start.y
            let squaredLength = dx * dx + dy * dy
            let fraction = squaredLength > 0
                ? min(1, max(0, ((point.x - segment.start.x) * dx + (point.y - segment.start.y) * dy) / squaredLength))
                : 0
            let projected = MKMapPoint(
                x: segment.start.x + fraction * dx,
                y: segment.start.y + fraction * dy
            )
            let progress = segment.cumulativeStartMeters + segment.lengthMeters * fraction
            if !hasAcceptedProjection,
               progress > max(120, min(400, totalDistanceMeters * 0.08)) {
                continue
            }
            let distance = point.distance(to: projected)
            var score = distance

            if hasAcceptedProjection {
                let delta = progress - currentProgressMeters
                if delta > maximumAdvance { score += (delta - maximumAdvance) * 6 }
                if delta < -maximumRegression { score += (-delta - maximumRegression) * 7 }
                score += Double(abs(index - currentSegmentIndex)) * 0.2
            }
            if hasReliableCourse {
                score += Self.angularDifference(location.course, segment.bearingDegrees) * 0.22
            }

            let projection = Projection(
                segmentIndex: index,
                progressMeters: progress,
                distanceMeters: distance,
                routeBearingDegrees: segment.bearingDegrees
            )
            if best == nil || score < best!.score {
                best = (projection, score)
            }
        }
        return best?.projection
    }

    private mutating func updateDeviation(
        distanceMeters: Double,
        accuracyMeters: Double,
        now: Date,
        events: inout [RouteGuidanceEvent]
    ) {
        let threshold = max(45, accuracyMeters * 2)
        if offRoute {
            if distanceMeters <= threshold * 0.62 {
                offRoute = false
                deviationBeganAt = nil
                events.append(.rejoined)
            }
            return
        }

        guard distanceMeters > threshold else {
            deviationBeganAt = nil
            return
        }
        if let deviationBeganAt {
            if now.timeIntervalSince(deviationBeganAt) >= 12 {
                offRoute = true
                wrongWay = false
                wrongWayBeganAt = nil
                events.append(.deviated(distanceMeters: distanceMeters))
            }
        } else {
            deviationBeganAt = now
        }
    }

    private mutating func updateWrongWay(
        location: CLLocation,
        routeBearingDegrees: Double,
        priorProgressMeters: Double,
        now: Date,
        events: inout [RouteGuidanceEvent]
    ) {
        guard !offRoute, !arrived else {
            wrongWayBeganAt = nil
            correctDirectionBeganAt = nil
            return
        }
        let reliableCourse = location.course >= 0 && location.course <= 360 && location.speed >= 0.8
        let courseOpposesRoute = reliableCourse
            && Self.angularDifference(location.course, routeBearingDegrees) >= 135
        let meaningfulRegression = currentProgressMeters < priorProgressMeters - 6
        let appearsWrongWay = courseOpposesRoute && (meaningfulRegression || location.speed >= 1.2)

        if appearsWrongWay {
            correctDirectionBeganAt = nil
            if let wrongWayBeganAt {
                if !wrongWay, now.timeIntervalSince(wrongWayBeganAt) >= 8 {
                    wrongWay = true
                    events.append(.wrongWay)
                }
            } else {
                wrongWayBeganAt = now
            }
        } else {
            wrongWayBeganAt = nil
            guard wrongWay else { return }
            if let correctDirectionBeganAt {
                if now.timeIntervalSince(correctDirectionBeganAt) >= 5 {
                    wrongWay = false
                    self.correctDirectionBeganAt = nil
                }
            } else {
                correctDirectionBeganAt = now
            }
        }
    }

    private mutating func updateArrival(
        location: CLLocation,
        now: Date,
        events: inout [RouteGuidanceEvent]
    ) {
        guard !arrived, !offRoute else { return }
        let fraction = currentProgressMeters / totalDistanceMeters
        let destination = CLLocation(latitude: destinationCoordinate.latitude, longitude: destinationCoordinate.longitude)
        let nearDestination = location.distance(from: destination) <= max(arrivalDistanceMeters, location.horizontalAccuracy * 1.25)
        let requiredFraction = isLoop ? 0.94 : 0.90
        let maximumRemainingDistance = min(80, max(30, totalDistanceMeters * 0.01))
        guard fraction >= requiredFraction,
              totalDistanceMeters - currentProgressMeters <= maximumRemainingDistance,
              nearDestination
        else {
            arrivalBeganAt = nil
            return
        }
        if let arrivalBeganAt {
            guard now.timeIntervalSince(arrivalBeganAt) >= 4 else { return }
            arrived = true
            currentProgressMeters = totalDistanceMeters
            offRoute = false
            wrongWay = false
            events.append(.arrival)
        } else {
            arrivalBeganAt = now
        }
    }

    private mutating func appendProgressEvents(to events: inout [RouteGuidanceEvent]) {
        let percent = Int((currentProgressMeters / totalDistanceMeters * 100).rounded(.down))
        for threshold in [25, 50, 75, 100]
        where percent >= threshold && reachedProgressPercents.insert(threshold).inserted {
            events.append(.progressReached(threshold))
        }
    }

    private func gridCell(for point: MKMapPoint) -> GridCell {
        GridCell(
            x: Int(floor(point.x / gridCellMapUnits)),
            y: Int(floor(point.y / gridCellMapUnits))
        )
    }

    private static func makeSpatialIndex(
        segments: [Segment],
        cellMapUnits: Double
    ) -> [GridCell: [Int]] {
        var result: [GridCell: [Int]] = [:]
        for (index, segment) in segments.enumerated() {
            let minX = Int(floor(min(segment.start.x, segment.end.x) / cellMapUnits))
            let maxX = Int(floor(max(segment.start.x, segment.end.x) / cellMapUnits))
            let minY = Int(floor(min(segment.start.y, segment.end.y) / cellMapUnits))
            let maxY = Int(floor(max(segment.start.y, segment.end.y) / cellMapUnits))
            let cellCount = (maxX - minX + 1) * (maxY - minY + 1)
            let cells: [GridCell]
            if cellCount <= 64 {
                cells = (minX...maxX).flatMap { x in (minY...maxY).map { GridCell(x: x, y: $0) } }
            } else {
                let middle = MKMapPoint(
                    x: (segment.start.x + segment.end.x) / 2,
                    y: (segment.start.y + segment.end.y) / 2
                )
                cells = [segment.start, middle, segment.end].map {
                    GridCell(x: Int(floor($0.x / cellMapUnits)), y: Int(floor($0.y / cellMapUnits)))
                }
            }
            for cell in cells {
                if result[cell, default: []].count < maximumSegmentsPerGridCell {
                    result[cell, default: []].append(index)
                }
            }
        }
        return result
    }

    private static func bearing(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> Double {
        let startLat = start.latitude * .pi / 180
        let endLat = end.latitude * .pi / 180
        let deltaLon = (end.longitude - start.longitude) * .pi / 180
        let y = sin(deltaLon) * cos(endLat)
        let x = cos(startLat) * sin(endLat) - sin(startLat) * cos(endLat) * cos(deltaLon)
        let degrees = atan2(y, x) * 180 / .pi
        return degrees >= 0 ? degrees : degrees + 360
    }

    private static func angularDifference(_ lhs: Double, _ rhs: Double) -> Double {
        let raw = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return raw > 180 ? 360 - raw : raw
    }
}

nonisolated enum RouteWorkingGeometry {
    static let minimumUsableSegmentDistanceMeters = 0.05
    private static let maximumNavigationErrorMeters = 10.0
    private static let maximumDisplayErrorMeters = 30.0
    private static let minimumWorkingDistanceMeters = 10.0
    private static let minimumRetainedDistanceRatio = 0.70

    static func navigationPoints(
        _ points: [RouteCoordinate],
        maximumCount: Int
    ) -> [RouteCoordinate]? {
        guard let working = boundedRadialPoints(
            points,
            maximumCount: maximumCount,
            maximumErrorMeters: maximumNavigationErrorMeters
        ), retainsRouteLength(working, comparedTo: points) else { return nil }
        return working
    }

    static func displayPoints(
        _ points: [RouteCoordinate],
        maximumCount: Int = 4_096
    ) -> [RouteCoordinate] {
        if let display = boundedRadialPoints(
            points,
            maximumCount: maximumCount,
            maximumErrorMeters: maximumDisplayErrorMeters
        ), retainsRouteLength(display, comparedTo: points) {
            return display
        }
        if let navigation = navigationPoints(
            points,
            maximumCount: RouteGuidanceEngine.maximumWorkingPointCount
        ) {
            return navigation
        }
        guard points.count > maximumCount, maximumCount > 2 else { return points }
        return Array(points.prefix(maximumCount - 1)) + [points[points.count - 1]]
    }

    static func isRepresentableForNavigation(_ points: [RouteCoordinate]) -> Bool {
        navigationPoints(
            points,
            maximumCount: RouteGuidanceEngine.maximumWorkingPointCount
        ) != nil
    }

    private static func boundedRadialPoints(
        _ points: [RouteCoordinate],
        maximumCount: Int,
        maximumErrorMeters: Double
    ) -> [RouteCoordinate]? {
        guard maximumCount > 2 else { return nil }
        guard points.count > maximumCount else { return points }
        let mapPoints = points.map { MKMapPoint($0.locationCoordinate) }
        let maximumToleranceIndices = radialIndices(
            mapPoints,
            toleranceMeters: maximumErrorMeters
        )
        guard maximumToleranceIndices.count <= maximumCount else { return nil }

        var lowerTolerance = 0.0
        var upperTolerance = maximumErrorMeters
        var bestIndices = maximumToleranceIndices
        for _ in 0..<14 {
            let tolerance = (lowerTolerance + upperTolerance) / 2
            let indices = radialIndices(mapPoints, toleranceMeters: tolerance)
            if indices.count > maximumCount {
                lowerTolerance = tolerance
            } else {
                bestIndices = indices
                upperTolerance = tolerance
            }
        }
        return bestIndices.map { points[$0] }
    }

    private static func radialIndices(
        _ points: [MKMapPoint],
        toleranceMeters: Double
    ) -> [Int] {
        guard points.count > 1 else { return Array(points.indices) }
        var indices = [0]
        indices.reserveCapacity(points.count)
        var lastRetainedIndex = 0
        if points.count > 2 {
            for index in 1..<(points.count - 1)
            where points[lastRetainedIndex].distance(to: points[index]) >= toleranceMeters {
                indices.append(index)
                lastRetainedIndex = index
            }
        }
        if indices.last != points.count - 1 {
            indices.append(points.count - 1)
        }
        return indices
    }

    private static func retainsRouteLength(
        _ working: [RouteCoordinate],
        comparedTo canonical: [RouteCoordinate]
    ) -> Bool {
        let canonicalDistance = polylineDistance(canonical)
        let workingDistance = polylineDistance(working)
        return canonicalDistance.isFinite
            && workingDistance.isFinite
            && workingDistance >= minimumWorkingDistanceMeters
            && workingDistance >= canonicalDistance * minimumRetainedDistanceRatio
    }

    private static func polylineDistance(_ points: [RouteCoordinate]) -> Double {
        guard points.count > 1 else { return 0 }
        var distance = 0.0
        var previous = MKMapPoint(points[0].locationCoordinate)
        for point in points.dropFirst() {
            let current = MKMapPoint(point.locationCoordinate)
            let segmentDistance = previous.distance(to: current)
            if segmentDistance.isFinite,
               segmentDistance > minimumUsableSegmentDistanceMeters {
                distance += segmentDistance
            }
            previous = current
        }
        return distance
    }
}
