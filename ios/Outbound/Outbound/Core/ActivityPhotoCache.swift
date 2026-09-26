import CryptoKit
import Foundation
import ImageIO
import UIKit

/// Resolves activity photo render URLs through a local photo cache.
///
/// Saved photos render from a local JPEG, a freshly signed remote media URL
/// (Social-rendered activities), or a remote photo id (after upload or
/// restore). The cache remembers which local file already represents each
/// photo identity so thumbnails and the lightbox render instantly from disk
/// instead of re-downloading full-size photos, and it stores downsampled
/// thumbnail variants for small render surfaces such as map pins and the
/// carousel strip. The identity mapping survives app restarts through a
/// small on-disk mapping file, and remote photo ids stay stable across
/// signed-URL reissuance.
@MainActor
final class ActivityPhotoCache {
    static let shared = ActivityPhotoCache()

    private static let remoteIdentityPrefix = "remote:"
    private static let mappingFileName = "PhotoCacheMappings.plist"

    private let memoryCache = NSCache<NSString, UIImage>()
    private var inFlightTasks: [String: Task<UIImage?, Never>] = [:]
    /// Cache identity keys mapped to a local file URL that can render them.
    private var fileURLsByIdentityKey: [String: URL] = [:]
    /// Render URLs mapped to the photo identity they were resolved for, so
    /// refreshed signed URLs keep using the same cache identity.
    private var identitiesByURLString: [String: String] = [:]

    /// Internal so tests can exercise persistence with fresh instances.
    init() {
        memoryCache.countLimit = 120
        let mapping = (try? Self.loadMapping()) ?? [:]
        for (key, urlString) in mapping {
            guard let url = URL(string: urlString) else { continue }
            fileURLsByIdentityKey[key] = url
            if url.isFileURL {
                identitiesByURLString[url.standardizedFileURL.absoluteString] = key
            }
        }
    }

    // MARK: - Identity

    /// Stable identity for a photo's source content. Remote photo ids win over
    /// stored paths so re-signed media URLs and uploaded photos share one cache
    /// identity across sessions.
    nonisolated static func cacheIdentity(for photo: SavedPhoto) -> String {
        if let remotePhotoId = photo.remotePhotoId {
            return remoteIdentityPrefix + sanitizedKey(remotePhotoId.lowercased())
        }
        return "path:\(photo.relativePath)"
    }

    nonisolated private static func sanitizedKey(_ raw: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        let sanitized = String(raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }.prefix(120))
        return sanitized.isEmpty ? "photo" : sanitized
    }

    nonisolated private static func thumbnailSuffix(_ maxPixelSize: CGFloat?) -> String {
        guard let maxPixelSize else { return "" }
        return "-t\(Int(maxPixelSize.rounded(.up)))"
    }

    nonisolated private static func identityBase(forKey key: String) -> String {
        guard let range = key.range(of: "-t\\d+$", options: .regularExpression) else { return key }
        return String(key[..<range.lowerBound])
    }

    // MARK: - Render URL resolution

    /// Resolves the URL a photo should render from, preferring a remembered
    /// local cache or saved file over a signed remote URL. Also registers the
    /// photo identity so later image loads reuse the same cache identity.
    func renderedURL(for photo: SavedPhoto, thumbnailPixelHeight: CGFloat? = nil) -> URL {
        let identity = Self.cacheIdentity(for: photo)
        let identityKey = identity + Self.thumbnailSuffix(thumbnailPixelHeight)
        if let cachedURL = fileURLsByIdentityKey[identityKey],
           FileManager.default.fileExists(atPath: cachedURL.path) {
            return cachedURL
        }

        let localURL = ActivityPersistence.imageURL(for: photo)
        if thumbnailPixelHeight == nil,
           FileManager.default.fileExists(atPath: localURL.path(percentEncoded: false)) {
            if identity.hasPrefix(Self.remoteIdentityPrefix) {
                remember(localURL, forIdentityKey: identity)
                identitiesByURLString[localURL.standardizedFileURL.absoluteString] = identity
            }
            return localURL
        }

        if let remoteURL = photo.remoteRenderURL {
            let registeredIdentity = Self.isActivityPhotoThumbnailURL(remoteURL) ? identity + "-preview" : identity
            identitiesByURLString[remoteURL.absoluteString] = registeredIdentity
            return remoteURL
        }

        return localURL
    }

    // MARK: - Image loading

    func cachedImage(for url: URL, maxPixelSize: CGFloat? = nil) -> UIImage? {
        memoryCache.object(forKey: cacheKey(for: url, maxPixelSize: maxPixelSize) as NSString)
    }

    /// Loads a photo for rendering, routing through the local cache. When
    /// `maxPixelSize` is set the image is decoded downsampled, which keeps
    /// thumbnail surfaces fast even for full-size camera JPEGs.
    func image(for url: URL, maxPixelSize: CGFloat? = nil) async -> UIImage? {
        let key = cacheKey(for: url, maxPixelSize: maxPixelSize)
        if let image = memoryCache.object(forKey: key as NSString) { return image }
        if let inFlight = inFlightTasks[key] { return await inFlight.value }

        let task = Task<UIImage?, Never> { [weak self] in
            defer { self?.inFlightTasks[key] = nil }
            return await self?.loadImage(for: url, maxPixelSize: maxPixelSize, cacheKey: key)
        }
        inFlightTasks[key] = task
        return await task.value
    }

    private func loadImage(for url: URL, maxPixelSize: CGFloat?, cacheKey: String) async -> UIImage? {
        if url.isFileURL {
            let path = url.path(percentEncoded: false)
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            let image = await Task.detached(priority: .userInitiated) {
                ActivityPhotoCache.decodedImage(contentsOf: path, maxPixelSize: maxPixelSize)
            }.value
            if let image {
                memoryCache.setObject(image, forKey: cacheKey as NSString)
                await persistThumbnailVariant(image, cacheKey: cacheKey)
            }
            return image
        }

        let data: Data
        if let photoID = Self.activityPhotoID(from: url) {
            // Social feed URLs are intentionally short and authenticated. Use
            // APIClient here so the bearer token is attached; a raw URLSession
            // request would otherwise turn the compact URL into a 401.
            let isThumbnail = url.pathComponents.last == "thumbnail"
            guard let downloaded = try? await APIClient.shared.downloadActivityPhoto(id: photoID, thumbnail: isThumbnail) else { return nil }
            data = downloaded
        } else {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            guard let (downloaded, response) = try? await URLSession.shared.data(for: request),
                  let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else { return nil }
            data = downloaded
        }

        let image = await Task.detached(priority: .userInitiated) {
            ActivityPhotoCache.decodedImage(data: data, maxPixelSize: maxPixelSize)
        }.value
        guard let image else { return nil }
        memoryCache.setObject(image, forKey: cacheKey as NSString)
        await persistRemoteData(data, cacheKey: cacheKey)
        return image
    }

    /// Maps a photo identity to an already-saved local file, so it keeps
    /// rendering locally after its remote upload completes.
    func rememberUploadedPhoto(_ photo: SavedPhoto, savedAt: URL) {
        let identity = Self.cacheIdentity(for: photo)
        remember(savedAt, forIdentityKey: identity)
        identitiesByURLString[savedAt.standardizedFileURL.absoluteString] = identity
    }

    // MARK: - Cache persistence

    private func remember(_ url: URL, forIdentityKey identityKey: String) {
        guard fileURLsByIdentityKey[identityKey] != url else { return }
        fileURLsByIdentityKey[identityKey] = url
        persistMapping()
    }

    /// Persists remote photo data locally: the original bytes for full-size
    /// renders and, when a thumbnail was requested, a downsampled JPEG variant.
    private func persistRemoteData(_ data: Data, cacheKey: String) async {
        let identityBase = Self.identityBase(forKey: cacheKey)
        let fullURL = await Task.detached(priority: .utility) {
            ActivityPhotoCache.writeOriginal(data, identityKey: identityBase)
        }.value
        if let fullURL {
            remember(fullURL, forIdentityKey: identityBase)
        }

        if cacheKey != identityBase {
            await persistThumbnail(data: data, cacheKey: cacheKey)
        }
    }

    private func persistThumbnailVariant(_ image: UIImage, cacheKey: String) async {
        guard cacheKey.hasPrefix(Self.remoteIdentityPrefix),
              cacheKey != Self.identityBase(forKey: cacheKey) else { return }
        await persistThumbnail(decodedImage: image, cacheKey: cacheKey)
    }

    private func persistThumbnail(
        data: Data? = nil,
        decodedImage: UIImage? = nil,
        cacheKey: String
    ) async {
        let fileURL = await Task.detached(priority: .utility) {
            ActivityPhotoCache.writeDownsampled(data, decodedImage: decodedImage, identityKey: cacheKey)
        }.value
        if let fileURL {
            remember(fileURL, forIdentityKey: cacheKey)
        }
    }

    private func persistMapping() {
        // Mapping writes are rare and tiny, so a synchronous write keeps the
        // on-disk mapping deterministic for tests and app restarts.
        ActivityPhotoCache.writeMapping(fileURLsByIdentityKey.mapValues(\.absoluteString))
    }

    // MARK: - Cache key helpers

    private func cacheKey(for url: URL, maxPixelSize: CGFloat?) -> String {
        let representationSuffix = Self.isActivityPhotoThumbnailURL(url) ? "-preview" : ""
        let suffix = representationSuffix + Self.thumbnailSuffix(maxPixelSize)
        if let identity = identitiesByURLString[url.standardizedFileURL.absoluteString]
            ?? identitiesByURLString[url.absoluteString] {
            return identity + suffix
        }
        if url.isFileURL {
            return "file:\(url.standardizedFileURL.path(percentEncoded: false))" + suffix
        }
        return "url:\(url.absoluteString)" + suffix
    }

    // MARK: - Disk helpers

    nonisolated private static func cacheDirectoryURL() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support.appendingPathComponent("Outbound/PhotosCache", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    nonisolated private static func mappingURL() throws -> URL {
        try cacheDirectoryURL().appendingPathComponent(mappingFileName)
    }

    nonisolated private static func fileName(forIdentityKey identityKey: String) -> String {
        let digest = SHA256.hash(data: Data(identityKey.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".jpg"
    }

    nonisolated private static func loadMapping() throws -> [String: String] {
        let url = try mappingURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        return try PropertyListDecoder().decode([String: String].self, from: data)
    }

    nonisolated private static func writeMapping(_ mapping: [String: String]) {
        guard let url = try? mappingURL(),
              let data = try? PropertyListEncoder().encode(mapping) else { return }
        try? data.write(to: url, options: .atomic)
    }

    nonisolated private static func writeOriginal(_ data: Data, identityKey: String) -> URL? {
        guard let directory = try? cacheDirectoryURL() else { return nil }
        let fileURL = directory.appendingPathComponent(fileName(forIdentityKey: identityKey))
        do {
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            return nil
        }
    }

    nonisolated private static func writeDownsampled(
        _ data: Data?,
        decodedImage: UIImage?,
        identityKey: String
    ) -> URL? {
        let image: UIImage?
        if let decodedImage {
            image = decodedImage
        } else if let data, let source = CGImageSourceCreateWithData(data as CFData, nil) {
            image = Self.decodedImage(from: source, maxPixelSize: nil) ?? UIImage(data: data)
        } else {
            image = nil
        }
        guard let image, let jpeg = image.jpegData(compressionQuality: 0.85) else { return nil }
        guard let directory = try? cacheDirectoryURL() else { return nil }
        let fileURL = directory.appendingPathComponent(fileName(forIdentityKey: identityKey))
        do {
            try jpeg.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            return nil
        }
    }

    // MARK: - Decoding

    nonisolated private static func activityPhotoID(from url: URL) -> String? {
        let components = url.pathComponents
        guard let marker = components.firstIndex(of: "activity-photos"),
              components.indices.contains(marker + 2),
              ["content", "thumbnail"].contains(components[marker + 2]) else { return nil }
        return components[marker + 1]
    }

    nonisolated private static func isActivityPhotoThumbnailURL(_ url: URL) -> Bool {
        url.pathComponents.last == "thumbnail"
    }

    nonisolated private static func decodedImage(data: Data, maxPixelSize: CGFloat?) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return decodedImage(from: source, maxPixelSize: maxPixelSize) ?? UIImage(data: data)
    }

    nonisolated private static func decodedImage(contentsOf path: String, maxPixelSize: CGFloat?) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
        return decodedImage(from: source, maxPixelSize: maxPixelSize) ?? UIImage(contentsOfFile: path)
    }

    nonisolated private static func decodedImage(from source: CGImageSource, maxPixelSize: CGFloat?) -> UIImage? {
        if let maxPixelSize {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize.rounded(.up))
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return UIImage(cgImage: cgImage)
        }
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

extension SavedPhoto {
    /// The signed remote media URL when the photo's stored path points at remote media.
    var remoteRenderURL: URL? {
        guard let url = URL(string: relativePath),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }
}
