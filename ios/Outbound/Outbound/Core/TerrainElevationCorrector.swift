import CoreLocation
import Foundation

enum TerrainElevationCorrector {
    static let algorithmVersion = "terrain-v2"
    private static let maximumRequestPoints = 450
    private static let minimumSampleSpacingMeters = 20.0

    static func correct(_ summary: ActivitySummary) async throws -> ActivitySummary {
        let sampled = try sampledLocations(from: summary.trackSegments)
        guard sampled.locations.count >= 2 else { return summary }

        let response = try await APIClient.shared.correctTerrainElevation(
            TerrainElevationCorrectionRequest(points: sampled.locations.enumerated().map { index, location in
                TerrainElevationRequestPoint(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    startsNewSegment: sampled.segmentStartIndices.contains(index)
                )
            })
        )
        guard response.elevationsMeters.count == sampled.locations.count,
              response.elevationGainMeters.isFinite,
              response.elevationGainMeters >= 0,
              response.elevationsMeters.allSatisfy({ $0.isFinite }),
              response.algorithmVersion == algorithmVersion
        else {
            throw TerrainElevationCorrectionError.invalidResponse
        }

        let correctedLocations = zip(sampled.locations, response.elevationsMeters).map { location, elevation in
            CLLocation(
                coordinate: location.coordinate,
                altitude: elevation,
                horizontalAccuracy: location.horizontalAccuracy,
                verticalAccuracy: max(1, response.approximateResolutionMeters),
                course: location.course,
                speed: location.speed,
                timestamp: location.timestamp
            )
        }
        return ActivitySummary(
            startedAt: summary.startedAt,
            endedAt: summary.endedAt,
            durationSecs: summary.durationSecs,
            distanceM: summary.distanceM,
            avgPace: summary.avgPace,
            elevationGainM: response.elevationGainMeters,
            elevationMetadata: ActivityElevationMetadata(
                algorithmVersion: response.algorithmVersion,
                provider: response.attribution.provider,
                attributionText: response.attribution.text,
                attributionURL: response.attribution.url,
                modified: response.attribution.modified
            ),
            originalElevationRoute: summary.originalElevationRoute ?? (summary.elevationMetadata == nil
                ? SavedRoute.original(from: summary.trackSegments) : nil),
            walkingStepCount: summary.walkingStepCount,
            cadence: summary.cadence,
            healthMetrics: summary.healthMetrics,
            heartRateZones: summary.heartRateZones,
            sessionMetadata: summary.sessionMetadata,
            routeGuidance: summary.routeGuidance,
            trackPoints: correctedLocations,
            trackSegmentStartIndices: sampled.segmentStartIndices
        )
    }

    private static func sampledLocations(from segments: [[CLLocation]]) throws -> SampledTrack {
        let segments = segments.filter { !$0.isEmpty }
        let reservedEndpoints = segments.reduce(0) { $0 + min(2, $1.count) }
        guard reservedEndpoints <= maximumRequestPoints else {
            throw TerrainElevationCorrectionError.tooManySegments
        }
        let totalDistance = segments.reduce(0.0) { total, segment in
            total + zip(segment, segment.dropFirst()).reduce(0.0) { $0 + $1.0.distance(from: $1.1) }
        }
        let intervals = max(1, maximumRequestPoints - reservedEndpoints)
        let spacing = max(minimumSampleSpacingMeters, totalDistance / Double(intervals))
        var locations: [CLLocation] = []
        var starts = Set<Int>()
        for segment in segments {
            starts.insert(locations.count)
            locations.append(segment[0])
            var traversed = 0.0
            var nextSample = spacing
            for index in 1..<segment.count {
                let a = segment[index - 1]
                let b = segment[index]
                let length = a.distance(from: b)
                while length > 0, nextSample < traversed + length {
                    let fraction = (nextSample - traversed) / length
                    let longitudeDelta = (b.coordinate.longitude - a.coordinate.longitude + 540)
                        .truncatingRemainder(dividingBy: 360) - 180
                    let longitude = (a.coordinate.longitude + longitudeDelta * fraction + 540)
                        .truncatingRemainder(dividingBy: 360) - 180
                    locations.append(CLLocation(
                        coordinate: CLLocationCoordinate2D(
                            latitude: a.coordinate.latitude + (b.coordinate.latitude - a.coordinate.latitude) * fraction,
                            longitude: longitude
                        ),
                        altitude: a.altitude + (b.altitude - a.altitude) * fraction,
                        horizontalAccuracy: max(a.horizontalAccuracy, b.horizontalAccuracy),
                        verticalAccuracy: max(a.verticalAccuracy, b.verticalAccuracy),
                        course: a.course,
                        speed: a.speed >= 0 && b.speed >= 0
                            ? a.speed + (b.speed - a.speed) * fraction : -1,
                        timestamp: a.timestamp.addingTimeInterval(b.timestamp.timeIntervalSince(a.timestamp) * fraction)
                    ))
                    nextSample += spacing
                }
                traversed += length
            }
            if segment.count > 1 { locations.append(segment[segment.count - 1]) }
        }
        guard locations.count <= maximumRequestPoints else {
            throw TerrainElevationCorrectionError.tooManySegments
        }
        return SampledTrack(locations: locations, segmentStartIndices: starts)
    }

}

private struct SampledTrack {
    let locations: [CLLocation]
    let segmentStartIndices: Set<Int>
}

private enum TerrainElevationCorrectionError: Error {
    case invalidResponse
    case tooManySegments
}
