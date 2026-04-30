import CoreLocation
import Foundation
import Testing
import UIKit
@testable import Outbound

struct LocalActivityStorePhotoTests {

    @MainActor
    @Test func savePersistsPhotoMetadataAndJpegFile() throws {
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let endedAt = startedAt.addingTimeInterval(900)
        let takenAt = startedAt.addingTimeInterval(300)
        let coordinate = CLLocationCoordinate2D(latitude: 37.3317, longitude: -122.0301)
        let metadata = PhotoMetadata(
            takenAt: takenAt,
            paceAtShot: 315,
            hrAtShot: 142,
            distAtShot: 1200,
            coordinate: coordinate,
            captureContext: .active
        )
        let summary = ActivitySummary(
            startedAt: startedAt,
            endedAt: endedAt,
            durationSecs: 900,
            distanceM: 3000,
            avgPace: 300,
            trackPoints: [
                CLLocation(latitude: 37.3317, longitude: -122.0301),
                CLLocation(latitude: 37.3321, longitude: -122.0310)
            ]
        )

        let savedActivity = try LocalActivityStore.save(
            summary: summary,
            photos: [(makeTestImage(), metadata)],
            title: "Photo Persistence Test",
            coachNudge: "Keep the cadence steady."
        )
        defer { try? LocalActivityStore.delete(savedActivity) }

        let reloadedActivity = try #require(
            LocalActivityStore.load().first { $0.id == savedActivity.id }
        )
        let savedPhoto = try #require(reloadedActivity.photos.first)
        let photoURL = try LocalActivityStore.imageURL(for: savedPhoto)

        #expect(reloadedActivity.photos.count == 1)
        #expect(savedPhoto.relativePath == "\(savedActivity.id.uuidString)/photos/photo-01.jpg")
        #expect(savedPhoto.takenAt == takenAt)
        #expect(savedPhoto.paceAtShot == 315)
        #expect(savedPhoto.hrAtShot == 142)
        #expect(savedPhoto.distAtShot == 1200)
        #expect(savedPhoto.coordinate?.latitude == coordinate.latitude)
        #expect(savedPhoto.coordinate?.longitude == coordinate.longitude)
        #expect(FileManager.default.fileExists(atPath: photoURL.path(percentEncoded: false)))
        #expect(UIImage(contentsOfFile: photoURL.path(percentEncoded: false)) != nil)
    }

    @MainActor
    private func makeTestImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        return renderer.image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: 8, height: 8)))
        }
    }
}
