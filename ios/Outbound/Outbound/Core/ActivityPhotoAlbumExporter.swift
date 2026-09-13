import CoreLocation
import Foundation
import Photos

enum ActivityPhotoAlbumPreferences {
    static let savesPhotosKey = "saveActivityPhotosToPhotoAlbum"

    static var savesPhotos: Bool {
        get {
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: savesPhotosKey) != nil else { return true }
            return defaults.bool(forKey: savesPhotosKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: savesPhotosKey)
        }
    }
}

enum ActivityPhotoAlbumExportOutcome: Equatable {
    case skipped
    case alreadySaved
    case saved(Int)
    case permissionDenied
    case failed
}

struct ActivityPhotoAlbumNotice: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let isError: Bool
}

@MainActor
final class ActivityPhotoAlbumExporter {
    static let shared = ActivityPhotoAlbumExporter()

    private let albumTitle = "Plainstride"
    private let albumIdentifierKey = "plainstrideActivityPhotoAlbumIdentifier"
    private let exportedPhotoIdentifiersKey = "plainstrideExportedActivityPhotoIdentifiers"

    private init() {}

    func exportPhotos(from activity: SavedActivity) async -> ActivityPhotoAlbumExportOutcome {
        guard ActivityPhotoAlbumPreferences.savesPhotos, !activity.photos.isEmpty else { return .skipped }

        let authorization = await authorizationStatus()
        guard authorization == .authorized || authorization == .limited else {
            ActivityPhotoAlbumPreferences.savesPhotos = false
            return .permissionDenied
        }

        let exportedIdentifiers = Set(
            UserDefaults.standard.stringArray(forKey: exportedPhotoIdentifiersKey) ?? []
        )
        let pendingPhotos = activity.photos.filter { !exportedIdentifiers.contains($0.id.uuidString) }
        guard !pendingPhotos.isEmpty else { return .alreadySaved }

        do {
            let album = try await findOrCreateAlbum()
            let photoFiles = pendingPhotos.compactMap { photo -> (SavedPhoto, URL)? in
                let url = ActivityPersistence.imageURL(for: photo)
                return FileManager.default.fileExists(atPath: url.path) ? (photo, url) : nil
            }
            guard photoFiles.count == pendingPhotos.count else { return .failed }

            try await PHPhotoLibrary.shared().performChanges {
                var placeholders: [PHObjectPlaceholder] = []
                for (photo, fileURL) in photoFiles {
                    let request = PHAssetCreationRequest.forAsset()
                    request.creationDate = photo.takenAt
                    if let coordinate = photo.coordinate {
                        request.location = CLLocation(
                            latitude: coordinate.latitude,
                            longitude: coordinate.longitude
                        )
                    }
                    request.addResource(with: .photo, fileURL: fileURL, options: nil)
                    if let placeholder = request.placeholderForCreatedAsset {
                        placeholders.append(placeholder)
                    }
                }
                PHAssetCollectionChangeRequest(for: album)?.addAssets(placeholders as NSArray)
            }

            let updatedIdentifiers = exportedIdentifiers.union(pendingPhotos.map { $0.id.uuidString })
            UserDefaults.standard.set(Array(updatedIdentifiers).sorted(), forKey: exportedPhotoIdentifiersKey)
            return .saved(pendingPhotos.count)
        } catch {
            ActivityDiagnosticLog.error(
                .persistence,
                "Activity photo album export failed photos=\(ActivityDiagnosticLog.countBucket(pendingPhotos.count)) error=\(ActivityDiagnosticLog.errorCategory(error))"
            )
            return .failed
        }
    }

    private func authorizationStatus() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard current == .notDetermined else { return current }
        return await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    private func findOrCreateAlbum() async throws -> PHAssetCollection {
        let defaults = UserDefaults.standard
        if let identifier = defaults.string(forKey: albumIdentifierKey),
           let album = PHAssetCollection.fetchAssetCollections(
               withLocalIdentifiers: [identifier],
               options: nil
           ).firstObject {
            return album
        }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", albumTitle)
        if let album = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: options
        ).firstObject {
            defaults.set(album.localIdentifier, forKey: albumIdentifierKey)
            return album
        }

        var createdIdentifier: String?
        try await PHPhotoLibrary.shared().performChanges {
            createdIdentifier = PHAssetCollectionChangeRequest
                .creationRequestForAssetCollection(withTitle: self.albumTitle)
                .placeholderForCreatedAssetCollection
                .localIdentifier
        }
        guard let createdIdentifier,
              let album = PHAssetCollection.fetchAssetCollections(
                  withLocalIdentifiers: [createdIdentifier],
                  options: nil
              ).firstObject else {
            throw ActivityPhotoAlbumExportError.albumUnavailable
        }
        defaults.set(createdIdentifier, forKey: albumIdentifierKey)
        return album
    }
}

private enum ActivityPhotoAlbumExportError: Error {
    case albumUnavailable
}
