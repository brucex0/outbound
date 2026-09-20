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
            elevationGainM: 42,
            healthMetrics: ActivityHealthMetrics(
                averageHeartRateBPM: 145,
                maxHeartRateBPM: 158,
                heartRateSampleCount: 6
            ),
            trackPoints: [
                CLLocation(latitude: 37.3317, longitude: -122.0301),
                CLLocation(latitude: 37.3321, longitude: -122.0310)
            ]
        )

        let savedActivity = try LocalActivityStore.save(
            summary: summary,
            photos: [(makeTestImage(), metadata)],
            title: "Photo Persistence Test",
            guideNudge: "Keep the cadence steady.",
            reflection: nil,
            goal: nil
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
        #expect(reloadedActivity.elevationGainM == 42)
        #expect(reloadedActivity.healthMetrics?.averageHeartRateBPM == 145)
        #expect(reloadedActivity.healthMetrics?.maxHeartRateBPM == 158)
        #expect(reloadedActivity.healthMetrics?.heartRateSampleCount == 6)
        #expect(FileManager.default.fileExists(atPath: photoURL.path(percentEncoded: false)))
        #expect(UIImage(contentsOfFile: photoURL.path(percentEncoded: false)) != nil)
    }

    @Test func saveStoresRouteOutsideManifestAndRoundTripsSidecar() throws {
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let summary = ActivitySummary(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(60),
            durationSecs: 60,
            distanceM: 500,
            avgPace: 120,
            trackPoints: [
                CLLocation(latitude: 37.3317, longitude: -122.0301),
                CLLocation(latitude: 37.3321, longitude: -122.0310),
                CLLocation(latitude: 37.3330, longitude: -122.0320),
            ]
        )
        let saved = try LocalActivityStore.save(
            summary: summary,
            photos: [],
            title: "Route Sidecar Test",
            guideNudge: "",
            reflection: nil,
            goal: nil
        )
        defer { try? LocalActivityStore.delete(saved) }

        let manifestURL = URL.applicationSupportDirectory
            .appendingPathComponent("Outbound/Activities/activities.json")
        let manifest = try String(contentsOf: manifestURL)
        let sidecarURL = URL.applicationSupportDirectory
            .appendingPathComponent("Outbound/Activities/\(saved.id.uuidString)/route.bin")
        #expect(!manifest.contains("\"points\""))
        #expect(FileManager.default.fileExists(atPath: sidecarURL.path))
        #expect(try Data(contentsOf: sidecarURL).count < manifest.utf8.count)

        let restored = try #require(LocalActivityStore.load().first { $0.id == saved.id })
        #expect(restored.routePoints.count == saved.routePoints.count)
        #expect(abs(restored.routePoints[1].latitude - saved.routePoints[1].latitude) < 0.000001)
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
