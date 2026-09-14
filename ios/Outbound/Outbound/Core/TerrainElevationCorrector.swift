import CoreLocation
import Foundation

enum TerrainElevationCorrector {
    private static let maximumRequestPoints = 450
    private static let minimumSampleSpacingMeters = 20.0

    static func correct(_ summary: ActivitySummary) async throws -> ActivitySummary {
        let sampled = sampledLocations(from: summary.trackSegments)
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
              response.elevationGainMeters >= 0
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
            walkingStepCount: summary.walkingStepCount,
            healthMetrics: summary.healthMetrics,
            heartRateZones: summary.heartRateZones,
            sessionMetadata: summary.sessionMetadata,
            routeGuidance: summary.routeGuidance,
            trackPoints: correctedLocations,
            trackSegmentStartIndices: sampled.segmentStartIndices
        )
    }

    private static func sampledLocations(from segments: [[CLLocation]]) -> SampledTrack {
        let nonemptySegments = segments.filter { !$0.isEmpty }
        let totalDistance = nonemptySegments.reduce(0.0) { total, segment in
            total + zip(segment, segment.dropFirst()).reduce(0.0) {
                $0 + $1.0.distance(from: $1.1)
            }
        }
        let availableIntervals = max(1, maximumRequestPoints - nonemptySegments.count * 2)
        let spacing = max(minimumSampleSpacingMeters, totalDistance / Double(availableIntervals))
        var locations: [CLLocation] = []
        var segmentStarts = Set<Int>()

        for segment in nonemptySegments {
            segmentStarts.insert(locations.count)
            locations.append(segment[0])
            var distanceSinceLastSample = 0.0
            for index in 1..<segment.count {
                distanceSinceLastSample += segment[index - 1].distance(from: segment[index])
                let isLast = index == segment.indices.last
                if distanceSinceLastSample >= spacing || isLast {
                    if locations.last?.timestamp != segment[index].timestamp {
                        locations.append(segment[index])
                    }
                    distanceSinceLastSample = 0
                }
            }
        }

        guard locations.count <= maximumRequestPoints else {
            return evenlyThinned(locations, segmentStarts: segmentStarts)
        }
        return SampledTrack(locations: locations, segmentStartIndices: segmentStarts)
    }

    private static func evenlyThinned(
        _ locations: [CLLocation],
        segmentStarts: Set<Int>
    ) -> SampledTrack {
        let mandatory = segmentStarts.union([locations.indices.last].compactMap { $0 })
        let remainingSlots = max(0, maximumRequestPoints - mandatory.count)
        let candidates = locations.indices.filter { !mandatory.contains($0) }
        let selectedCandidates: [Int]
        if remainingSlots == 0 || candidates.isEmpty {
            selectedCandidates = []
        } else {
            selectedCandidates = (0..<remainingSlots).map { slot in
                candidates[min(candidates.count - 1, slot * candidates.count / remainingSlots)]
            }
        }
        let selected = mandatory.union(selectedCandidates).sorted()
        let indexMap = Dictionary(uniqueKeysWithValues: selected.enumerated().map { ($0.element, $0.offset) })
        return SampledTrack(
            locations: selected.map { locations[$0] },
            segmentStartIndices: Set(segmentStarts.compactMap { indexMap[$0] })
        )
    }
}

private struct SampledTrack {
    let locations: [CLLocation]
    let segmentStartIndices: Set<Int>
}

private enum TerrainElevationCorrectionError: Error {
    case invalidResponse
}
