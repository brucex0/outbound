import CoreLocation
import CoreTransferable
import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// A photo picked from the user's library whose original file metadata was
/// recovered from EXIF when available.
///
/// `PhotosPicker` runs out of process and needs no photo-library permission;
/// it hands back a copy of the original file. Reading that file (rather than a
/// decoded `UIImage`) is what keeps the capture date, and usually the GPS
/// coordinate, intact.
struct ImportedActivityPhoto {
    let image: UIImage
    let takenAt: Date?
    let coordinate: CLLocationCoordinate2D?
}

/// File representation of a picked photo. The transfer URL is temporary, so we
/// copy it into our own temp file before reading metadata and pixels.
struct PickedPhotoFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let fileExtension = received.file.pathExtension.isEmpty
                ? "image"
                : received.file.pathExtension
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(fileExtension)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedPhotoFile(url: copy)
        }
    }
}

/// Loads picked photos and recovers their metadata and a bounded-size image.
enum ActivityPhotoImporter {
    /// Longest-edge cap for stored imports. Keeps memory and the upload size
    /// cap in check without losing display quality for full-screen viewing.
    nonisolated static let maxPixelSize = 2048

    static func importItem(_ item: PhotosPickerItem) async -> ImportedActivityPhoto? {
        guard let file = try? await item.loadTransferable(type: PickedPhotoFile.self) else {
            return nil
        }
        defer { try? FileManager.default.removeItem(at: file.url) }
        return load(fileURL: file.url)
    }

    static func load(fileURL: URL) -> ImportedActivityPhoto? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, sourceOptions),
              let image = downsampledImage(from: source)
        else { return nil }

        var takenAt: Date?
        var coordinate: CLLocationCoordinate2D?
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, sourceOptions) as? [CFString: Any] {
            takenAt = captureDate(from: properties)
            coordinate = location(from: properties)
        }
        return ImportedActivityPhoto(image: image, takenAt: takenAt, coordinate: coordinate)
    }

    nonisolated static func downsampledImage(from source: CGImageSource) -> UIImage? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - EXIF

    nonisolated static func captureDate(from properties: [CFString: Any]) -> Date? {
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let raw = (exif?[kCGImagePropertyExifDateTimeOriginal] as? String)
            ?? (exif?[kCGImagePropertyExifDateTimeDigitized] as? String)
            ?? (tiff?[kCGImagePropertyTIFFDateTime] as? String)
        guard let raw else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.timeZone = offsetTimeZone(exif: exif) ?? .current
        return formatter.date(from: raw)
    }

    nonisolated static func location(from properties: [CFString: Any]) -> CLLocationCoordinate2D? {
        guard let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
              let latitude = (gps[kCGImagePropertyGPSLatitude] as? NSNumber)?.doubleValue,
              let longitude = (gps[kCGImagePropertyGPSLongitude] as? NSNumber)?.doubleValue
        else { return nil }

        let signedLatitude = (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" ? -latitude : latitude
        let signedLongitude = (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" ? -longitude : longitude
        let coordinate = CLLocationCoordinate2D(latitude: signedLatitude, longitude: signedLongitude)
        guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        return coordinate
    }

    nonisolated private static func offsetTimeZone(exif: [CFString: Any]?) -> TimeZone? {
        let raw = (exif?[kCGImagePropertyExifOffsetTimeOriginal] as? String)
            ?? (exif?[kCGImagePropertyExifOffsetTimeDigitized] as? String)
            ?? (exif?[kCGImagePropertyExifOffsetTime] as? String)
        guard let raw, raw.count == 6, let signCharacter = raw.first,
              signCharacter == "+" || signCharacter == "-"
        else { return nil }

        let parts = raw.dropFirst().split(separator: ":")
        guard parts.count == 2, let hours = Int(parts[0]), let minutes = Int(parts[1]) else {
            return nil
        }
        let sign = signCharacter == "-" ? -1 : 1
        return TimeZone(secondsFromGMT: sign * (hours * 3600 + minutes * 60))
    }
}

/// Route geometry plus the activity facts needed to place an imported photo.
///
/// Placement uses the photo's capture time to interpolate a distance along the
/// recorded route, and only accepts EXIF GPS when it lands close to the route
/// so a photo taken somewhere else never produces a misleading map pin.
struct ActivityPhotoPlacementContext {
    struct RouteSample {
        let timestamp: Date
        let coordinate: CLLocationCoordinate2D
        /// Cumulative route distance at this sample, meters.
        let distanceM: Double
    }

    let startedAt: Date
    let endedAt: Date
    let distanceM: Double
    let avgPace: Double?
    let heartRateBPM: Int?
    let samples: [RouteSample]

    /// How close EXIF GPS must be to the route to be trusted, meters.
    static let plausibleRadiusM = 500.0

    init(
        startedAt: Date,
        endedAt: Date,
        distanceM: Double,
        avgPace: Double?,
        heartRateBPM: Int?,
        samples: [RouteSample]
    ) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.distanceM = distanceM
        self.avgPace = avgPace
        self.heartRateBPM = heartRateBPM
        self.samples = samples
    }

    init(summary: ActivitySummary) {
        self.init(
            startedAt: summary.startedAt,
            endedAt: summary.endedAt,
            distanceM: summary.distanceM,
            avgPace: summary.avgPace,
            heartRateBPM: summary.healthMetrics?.averageHeartRateBPM,
            samples: Self.samples(from: summary.trackPoints)
        )
    }

    init(activity: SavedActivity) {
        self.init(
            startedAt: activity.startedAt,
            endedAt: activity.endedAt,
            distanceM: activity.distanceM,
            avgPace: activity.avgPace,
            heartRateBPM: activity.healthMetrics?.averageHeartRateBPM,
            samples: Self.samples(from: activity.routePoints)
        )
    }

    func metadata(for photo: ImportedActivityPhoto) -> PhotoMetadata {
        let takenAt = photo.takenAt ?? Date()
        return PhotoMetadata(
            takenAt: takenAt,
            paceAtShot: avgPace,
            hrAtShot: heartRateBPM,
            distAtShot: distance(at: takenAt),
            coordinate: plausibleCoordinate(photo.coordinate, at: takenAt),
            captureContext: captureContext(at: takenAt)
        )
    }

    /// Route distance at a capture time, interpolated between the bracketing
    /// samples. Photos outside the recorded window clamp to the start or end.
    func distance(at date: Date) -> Double {
        guard let first = samples.first, let last = samples.last else { return 0 }
        if date <= first.timestamp { return first.distanceM }
        if date >= last.timestamp { return last.distanceM }

        for index in 1..<samples.count {
            let start = samples[index - 1]
            let end = samples[index]
            guard date >= start.timestamp, date <= end.timestamp else { continue }
            let span = end.timestamp.timeIntervalSince(start.timestamp)
            guard span > 0 else { return end.distanceM }
            let progress = date.timeIntervalSince(start.timestamp) / span
            return start.distanceM + (end.distanceM - start.distanceM) * progress
        }
        return last.distanceM
    }

    private func captureContext(at date: Date) -> PhotoCaptureContext {
        if date < startedAt { return .preActivity }
        if date >= endedAt { return .paused }
        return .active
    }

    private func plausibleCoordinate(_ coordinate: CLLocationCoordinate2D?, at date: Date) -> CLLocationCoordinate2D? {
        guard let coordinate, !samples.isEmpty else { return nil }
        guard let nearest = samples.min(by: {
            abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date))
        }) else { return nil }
        guard haversineMeters(coordinate, nearest.coordinate) <= Self.plausibleRadiusM else {
            return nil
        }
        return coordinate
    }

    // MARK: - Route sampling

    static func samples(from trackPoints: [CLLocation]) -> [RouteSample] {
        var result: [RouteSample] = []
        var cumulative = 0.0
        var previous: CLLocation?
        for location in trackPoints {
            if let previous {
                cumulative += haversineMeters(previous.coordinate, location.coordinate)
            }
            result.append(RouteSample(
                timestamp: location.timestamp,
                coordinate: location.coordinate,
                distanceM: cumulative
            ))
            previous = location
        }
        return result
    }

    static func samples(from points: [SavedRoutePoint]) -> [RouteSample] {
        var result: [RouteSample] = []
        var cumulative = 0.0
        var previous: CLLocationCoordinate2D?
        for point in points {
            // A resumed recording begins a new segment; the gap before it is
            // paused time, so its apparent map distance is excluded.
            if let previous, !point.startsNewSegment {
                cumulative += haversineMeters(previous, point.coordinate)
            }
            result.append(RouteSample(
                timestamp: point.timestamp,
                coordinate: point.coordinate,
                distanceM: cumulative
            ))
            previous = point.coordinate
        }
        return result
    }
}

private func haversineMeters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
    let radius = 6_371_000.0
    let deltaLatitude = (b.latitude - a.latitude) * .pi / 180
    let deltaLongitude = (b.longitude - a.longitude) * .pi / 180
    let value = sin(deltaLatitude / 2) * sin(deltaLatitude / 2)
        + cos(a.latitude * .pi / 180) * cos(b.latitude * .pi / 180)
        * sin(deltaLongitude / 2) * sin(deltaLongitude / 2)
    return radius * 2 * atan2(sqrt(value), sqrt(1 - value))
}
