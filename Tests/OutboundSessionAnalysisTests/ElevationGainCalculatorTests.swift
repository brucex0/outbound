import CoreLocation
import Foundation
import Testing
@testable import OutboundSessionAnalysis

struct ElevationGainCalculatorTests {
    @Test func returnsSanitizedElevationRangeInsteadOfAccumulatedNoise() {
        let altitudes = [
            31.9, 31.8, 32.3, 32.8, 33.2, 33.8, 32.9, 33.1, 33.4, 32.6,
            32.0, 33.6, 33.8, 33.3, 31.7, 31.5, 33.3, 33.1, 35.4, 33.9,
            34.1, 32.6, 32.3, 34.3, 33.0, 33.5, 33.6, 32.4, 31.7, 32.8,
            33.9, 32.5, 34.0, 32.7, 33.8, 32.4, 33.9, 32.6, 34.1, 32.5
        ]
        let locations = makeLocations(altitudes: altitudes, verticalAccuracy: 8)

        let naiveGain = zip(altitudes, altitudes.dropFirst()).reduce(0.0) { total, pair in
            let gain = pair.1 - pair.0
            return gain > 1 ? total + gain : total
        }
        let sanitizedRange = ElevationGainCalculator.sanitizedElevationRangeMeters(from: locations)

        #expect(naiveGain > 15)
        #expect(sanitizedRange < naiveGain)
        #expect(sanitizedRange >= 2)
        #expect(sanitizedRange <= 4)
    }

    @Test func rejectsPoorVerticalAccuracySamples() {
        let locations = [
            makeLocation(index: 0, altitude: 10, verticalAccuracy: 8),
            makeLocation(index: 1, altitude: 80, verticalAccuracy: 75),
            makeLocation(index: 2, altitude: 12, verticalAccuracy: 8)
        ]

        let sanitizedRange = ElevationGainCalculator.sanitizedElevationRangeMeters(from: locations)

        #expect(sanitizedRange == 2)
    }

    @Test func rejectsImplausibleVerticalJumps() {
        let locations = [
            makeLocation(index: 0, altitude: 10, verticalAccuracy: 8),
            makeLocation(index: 1, altitude: 70, verticalAccuracy: 8),
            makeLocation(index: 12, altitude: 13, verticalAccuracy: 8)
        ]

        let sanitizedRange = ElevationGainCalculator.sanitizedElevationRangeMeters(from: locations)

        #expect(sanitizedRange == 3)
    }

    private func makeLocations(altitudes: [Double], verticalAccuracy: CLLocationAccuracy) -> [CLLocation] {
        altitudes.enumerated().map { index, altitude in
            makeLocation(index: index, altitude: altitude, verticalAccuracy: verticalAccuracy)
        }
    }

    private func makeLocation(
        index: Int,
        altitude: CLLocationDistance,
        verticalAccuracy: CLLocationAccuracy
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(
                latitude: 47.5725 + Double(index) * 0.0001,
                longitude: -122.1732
            ),
            altitude: altitude,
            horizontalAccuracy: 5,
            verticalAccuracy: verticalAccuracy,
            timestamp: Date(timeIntervalSince1970: Double(index) * 5)
        )
    }
}
