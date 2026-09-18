import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import Outbound

@MainActor
struct ActivityPhotoCacheTests {

    @Test func cacheIdentityPrefersRemotePhotoIDOverSignedPath() {
        let remotePhoto = SavedPhoto(
            id: UUID(),
            takenAt: Date(timeIntervalSince1970: 1_800_000_000),
            paceAtShot: nil,
            hrAtShot: nil,
            distAtShot: 0,
            coordinate: nil,
            captureContext: .active,
            relativePath: "https://storage.example.com/signed/photo.jpg?X-Goog-Expires=900&signature=abc",
            remotePhotoId: "photo-123",
            remoteUploadedAt: nil
        )
        let localPhoto = SavedPhoto(
            metadata: PhotoMetadata(
                takenAt: Date(timeIntervalSince1970: 1_800_000_000),
                paceAtShot: nil,
                hrAtShot: nil,
                distAtShot: 0,
                coordinate: nil,
                captureContext: .active
            ),
            relativePath: "activity-id/photos/photo-01.jpg"
        )

        let remoteIdentity = ActivityPhotoCache.cacheIdentity(for: remotePhoto)
        #expect(remoteIdentity.hasPrefix("remote:"))
        #expect(remoteIdentity.contains("photo-123"))
        #expect(!remoteIdentity.contains("signature=abc"))
        #expect(ActivityPhotoCache.cacheIdentity(for: localPhoto) == "path:activity-id/photos/photo-01.jpg")
        #expect(ActivityPhotoCache.cacheIdentity(for: remotePhoto) == ActivityPhotoCache.cacheIdentity(for: remotePhoto))
    }

    @Test func rememberedUploadMappingSurvivesNewCacheInstance() {
        let photo = SavedPhoto(
            id: UUID(),
            takenAt: Date(timeIntervalSince1970: 1_800_000_000),
            paceAtShot: nil,
            hrAtShot: nil,
            distAtShot: 0,
            coordinate: nil,
            captureContext: .active,
            relativePath: "uploaded-activity/photos/photo-99.jpg",
            remotePhotoId: "upload-test-photo",
            remoteUploadedAt: nil
        )
        let savedURL = ActivityPersistence.imageURL(for: photo)
        try? FileManager.default.createDirectory(
            at: savedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let jpeg = Self.makeTestJPEG()
        try? jpeg.write(to: savedURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: savedURL) }

        let cache = ActivityPhotoCache()
        cache.rememberUploadedPhoto(photo, savedAt: savedURL)

        // Same photo, different signed path — should resolve to the saved file.
        let refreshed = SavedPhoto(
            id: photo.id,
            takenAt: photo.takenAt,
            paceAtShot: nil,
            hrAtShot: nil,
            distAtShot: 0,
            coordinate: nil,
            captureContext: .active,
            relativePath: "https://storage.example.com/signed/photo-refreshed.jpg?X-Goog-Expires=900",
            remotePhotoId: photo.remotePhotoId,
            remoteUploadedAt: photo.remoteUploadedAt
        )
        #expect(cache.renderedURL(for: refreshed) == savedURL)
        // And the mapping must survive a fresh cache instance (persistence).
        #expect(ActivityPhotoCache().renderedURL(for: refreshed) == savedURL)
    }

    @Test func thumbnailVariantResolvesWithoutNetworkForSavedPhoto() {
        let photo = SavedPhoto(
            metadata: PhotoMetadata(
                takenAt: Date(timeIntervalSince1970: 1_800_000_000),
                paceAtShot: nil,
                hrAtShot: nil,
                distAtShot: 0,
                coordinate: nil,
                captureContext: .active
            ),
            relativePath: "thumbnail-test-activity/photos/photo-01.jpg"
        )
        let fullURL = ActivityPersistence.imageURL(for: photo)
        try? FileManager.default.createDirectory(
            at: fullURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? Self.makeTestJPEG().write(to: fullURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: fullURL) }

        let cache = ActivityPhotoCache()
        let thumbnailURL = cache.renderedURL(for: photo, thumbnailPixelHeight: 84)
        // A saved local photo never falls back to the network for thumbnails.
        #expect(thumbnailURL.isFileURL)
    }

    @Test func downsampledThumbnailRoundTripKeepsAspectRatio() async throws {
        let photo = SavedPhoto(
            metadata: PhotoMetadata(
                takenAt: Date(timeIntervalSince1970: 1_800_000_000),
                paceAtShot: nil,
                hrAtShot: nil,
                distAtShot: 0,
                coordinate: nil,
                captureContext: .active
            ),
            relativePath: "downsample-test-activity/photos/photo-01.jpg"
        )
        let fullURL = ActivityPersistence.imageURL(for: photo)
        try? FileManager.default.createDirectory(
            at: fullURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? Self.makeTestJPEG(pixelWidth: 1200, pixelHeight: 900).write(to: fullURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: fullURL) }

        let cache = ActivityPhotoCache()
        let loaded = await cache.image(for: fullURL, maxPixelSize: 84)
        let image = try #require(loaded)
        #expect(max(image.size.width, image.size.height) <= 84 * image.scale)
        #expect(min(image.size.width, image.size.height) > 0)
    }

    // MARK: - Helpers

    private static func makeTestJPEG(
        pixelWidth: CGFloat = 200,
        pixelHeight: CGFloat = 150
    ) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: pixelWidth, height: pixelHeight), format: format)
            .image { context in
                UIColor.orange.setFill()
                context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
            }
        return image.jpegData(compressionQuality: 0.9)!
    }
}
