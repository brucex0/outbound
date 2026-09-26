import CoreLocation
import Foundation
import Testing
import UIKit
@testable import Outbound

@MainActor
struct ActivityPhotoImportTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func placement() -> ActivityPhotoPlacementContext {
        let samples = [
            ActivityPhotoPlacementContext.RouteSample(
                timestamp: start,
                coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
                distanceM: 0
            ),
            ActivityPhotoPlacementContext.RouteSample(
                timestamp: start.addingTimeInterval(600),
                coordinate: CLLocationCoordinate2D(latitude: 37.0018, longitude: -122.0),
                distanceM: 200
            ),
            ActivityPhotoPlacementContext.RouteSample(
                timestamp: start.addingTimeInterval(1200),
                coordinate: CLLocationCoordinate2D(latitude: 37.0036, longitude: -122.0),
                distanceM: 400
            )
        ]
        return ActivityPhotoPlacementContext(
            startedAt: start,
            endedAt: start.addingTimeInterval(1200),
            distanceM: 400,
            avgPace: 300,
            heartRateBPM: 150,
            samples: samples
        )
    }

    private func photo(
        takenAt: Date?,
        coordinate: CLLocationCoordinate2D? = nil
    ) -> ImportedActivityPhoto {
        ImportedActivityPhoto(image: UIImage(), takenAt: takenAt, coordinate: coordinate)
    }

    @Test func distanceInterpolatesBetweenSamples() {
        let placement = placement()
        let midpoint = start.addingTimeInterval(300)
        #expect(abs(placement.distance(at: midpoint) - 100) < 0.5)
    }

    @Test func distanceClampsOutsideTheRecordedWindow() {
        let placement = placement()
        #expect(placement.distance(at: start.addingTimeInterval(-60)) == 0)
        #expect(placement.distance(at: start.addingTimeInterval(9999)) == 400)
    }

    @Test func metadataUsesActiveContextDuringTheActivity() {
        let placement = placement()
        let metadata = placement.metadata(for: photo(takenAt: start.addingTimeInterval(300)))
        #expect(metadata.captureContext == .active)
        #expect(abs(metadata.distAtShot - 100) < 0.5)
        #expect(metadata.hrAtShot == 150)
    }

    @Test func metadataMarksPhotosBeforeAndAfterTheActivity() {
        let placement = placement()
        let before = placement.metadata(for: photo(takenAt: start.addingTimeInterval(-60)))
        #expect(before.captureContext == .preActivity)
        #expect(before.distAtShot == 0)

        let after = placement.metadata(for: photo(takenAt: start.addingTimeInterval(2000)))
        #expect(after.captureContext == .paused)
        #expect(after.distAtShot == 400)
    }

    @Test func nearbyGPSCoordinateIsKept() {
        let placement = placement()
        let coordinate = CLLocationCoordinate2D(latitude: 37.0001, longitude: -122.0)
        let metadata = placement.metadata(for: photo(
            takenAt: start.addingTimeInterval(60),
            coordinate: coordinate
        ))
        #expect(metadata.coordinate != nil)
    }

    @Test func distantGPSCoordinateIsDiscarded() {
        let placement = placement()
        let coordinate = CLLocationCoordinate2D(latitude: 40.0, longitude: -73.0)
        let metadata = placement.metadata(for: photo(
            takenAt: start.addingTimeInterval(60),
            coordinate: coordinate
        ))
        #expect(metadata.coordinate == nil)
    }

    @Test func coordinateIsDiscardedWhenThereIsNoRoute() {
        let empty = ActivityPhotoPlacementContext(
            startedAt: start,
            endedAt: start.addingTimeInterval(1200),
            distanceM: 0,
            avgPace: nil,
            heartRateBPM: nil,
            samples: []
        )
        let coordinate = CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0)
        let metadata = empty.metadata(for: photo(takenAt: start, coordinate: coordinate))
        #expect(metadata.coordinate == nil)
        #expect(metadata.distAtShot == 0)
    }

    @Test func captureDateParsesExifWithTimezoneOffset() {
        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2022:05:26 14:28:29",
                kCGImagePropertyExifOffsetTimeOriginal: "+00:00"
            ] as [CFString: Any]
        ]
        let date = ActivityPhotoImporter.captureDate(from: properties)
        #expect(date == Date(timeIntervalSince1970: 1_653_575_309))
    }

    @Test func locationAppliesHemisphereReferences() {
        let properties: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 33.8688,
                kCGImagePropertyGPSLatitudeRef: "S",
                kCGImagePropertyGPSLongitude: 151.2093,
                kCGImagePropertyGPSLongitudeRef: "W"
            ] as [CFString: Any]
        ]
        let coordinate = ActivityPhotoImporter.location(from: properties)
        #expect(coordinate?.latitude == -33.8688)
        #expect(coordinate?.longitude == -151.2093)
    }
}
