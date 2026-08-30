import CoreLocation
import Foundation
import UIKit

struct ActiveSessionJournal {
    let startedAt: Date
    let elapsedSeconds: Int
    let wasPaused: Bool
    let activityType: ActivityType?
    let routeGuidanceRecoverySeed: RouteGuidanceRecoverySeed?
    let trackPoints: [JournalTrackPoint]

    init(
        startedAt: Date,
        elapsedSeconds: Int,
        wasPaused: Bool,
        activityType: ActivityType?,
        routeGuidanceRecoverySeed: RouteGuidanceRecoverySeed?,
        trackPoints: [JournalTrackPoint] = []
    ) {
        self.startedAt = startedAt
        self.elapsedSeconds = elapsedSeconds
        self.wasPaused = wasPaused
        self.activityType = activityType
        self.routeGuidanceRecoverySeed = routeGuidanceRecoverySeed
        self.trackPoints = trackPoints
    }

    static func load() -> ActiveSessionJournal? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let metadata = try? JSONDecoder().decode(Metadata.self, from: data) else { return nil }
        return ActiveSessionJournal(
            startedAt: metadata.startedAt,
            elapsedSeconds: metadata.elapsedSeconds,
            wasPaused: metadata.wasPaused,
            activityType: metadata.activityType,
            routeGuidanceRecoverySeed: metadata.routeGuidanceRecoverySeed,
            trackPoints: ActiveSessionTrackJournal.load()
        )
    }

    func save() {
        let metadata = Metadata(
            startedAt: startedAt,
            elapsedSeconds: elapsedSeconds,
            wasPaused: wasPaused,
            activityType: activityType,
            routeGuidanceRecoverySeed: routeGuidanceRecoverySeed
        )
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        let directory = Self.fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
        ActiveSessionTrackJournal.clear()
        ActiveRouteGuidanceSnapshot.clear()
    }

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Outbound", isDirectory: true)
            .appendingPathComponent("active-session.json")
    }

    private struct Metadata: Codable {
        let startedAt: Date
        let elapsedSeconds: Int
        let wasPaused: Bool
        let activityType: ActivityType?
        let routeGuidanceRecoverySeed: RouteGuidanceRecoverySeed?
    }
}

enum ActiveSessionTrackJournal {
    static func load() -> [JournalTrackPoint] {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return [] }
        let decoder = JSONDecoder()
        return data.split(separator: 0x0A).flatMap { line in
            (try? decoder.decode([JournalTrackPoint].self, from: Data(line))) ?? []
        }
    }

    @discardableResult
    static func append(_ points: [JournalTrackPoint]) -> Bool {
        guard !points.isEmpty else { return true }
        guard var data = try? JSONEncoder().encode(points) else { return false }
        data.append(0x0A)
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                try data.write(to: fileURL, options: .atomic)
                return true
            }
            let file = try FileHandle(forWritingTo: fileURL)
            defer { try? file.close() }
            try file.seekToEnd()
            var appendedData = Data([0x0A])
            appendedData.append(data)
            try file.write(contentsOf: appendedData)
            try file.synchronize()
            return true
        } catch {
            return false
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Outbound", isDirectory: true)
            .appendingPathComponent("active-session-track.jsonl")
    }
}

@MainActor
enum ActiveSessionPhotoJournal {
    static func load() -> [(UIImage, PhotoMetadata)] {
        loadEntries().compactMap { entry in
            let imageURL = directoryURL.appendingPathComponent(entry.fileName)
            guard let image = UIImage(contentsOfFile: imageURL.path) else { return nil }
            return (image, entry.metadata)
        }
    }

    static func append(_ photo: (UIImage, PhotoMetadata)) {
        let entry = Entry(metadata: photo.1)
        let imageURL = directoryURL.appendingPathComponent(entry.fileName)
        guard let imageData = photo.0.jpegData(compressionQuality: 0.9) else { return }

        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try imageData.write(to: imageURL, options: .atomic)
            var entries = loadEntries()
            entries.append(entry)
            try save(entries)
        } catch {
            try? FileManager.default.removeItem(at: imageURL)
        }
    }

    static func replace(with photos: [(UIImage, PhotoMetadata)]) {
        clear()
        photos.forEach(append)
    }

    static func removePreActivityPhotos() {
        let entries = loadEntries()
        let removedEntries = entries.filter { $0.captureContext == .preActivity }
        guard !removedEntries.isEmpty else { return }
        let retainedEntries = entries.filter { $0.captureContext != .preActivity }

        if retainedEntries.isEmpty {
            clear()
            return
        }

        do {
            try save(retainedEntries)
            for entry in removedEntries {
                try? FileManager.default.removeItem(
                    at: directoryURL.appendingPathComponent(entry.fileName)
                )
            }
        } catch {
            return
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    private static func loadEntries() -> [Entry] {
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        else { return [] }
        return manifest.photos
    }

    private static func save(_ entries: [Entry]) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Manifest(photos: entries))
        try data.write(to: manifestURL, options: .atomic)
    }

    private static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Outbound", isDirectory: true)
            .appendingPathComponent("active-session-photos", isDirectory: true)
    }

    private static var manifestURL: URL {
        directoryURL.appendingPathComponent("manifest.json")
    }

    private struct Manifest: Codable {
        let photos: [Entry]
    }

    private struct Entry: Codable {
        let id: UUID
        let takenAt: Date
        let paceAtShot: Double?
        let hrAtShot: Int?
        let distAtShot: Double
        let latitude: Double?
        let longitude: Double?
        let captureContext: PhotoCaptureContext

        init(metadata: PhotoMetadata) {
            id = UUID()
            takenAt = metadata.takenAt
            paceAtShot = metadata.paceAtShot
            hrAtShot = metadata.hrAtShot
            distAtShot = metadata.distAtShot
            latitude = metadata.coordinate?.latitude
            longitude = metadata.coordinate?.longitude
            captureContext = metadata.captureContext
        }

        var fileName: String {
            "photo-\(id.uuidString).jpg"
        }

        var metadata: PhotoMetadata {
            let coordinate = latitude.flatMap { latitude in
                longitude.map { longitude in
                    CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                }
            }
            return PhotoMetadata(
                takenAt: takenAt,
                paceAtShot: paceAtShot,
                hrAtShot: hrAtShot,
                distAtShot: distAtShot,
                coordinate: coordinate,
                captureContext: captureContext
            )
        }
    }
}

struct ActiveRouteGuidanceJournal: Codable, Equatable {
    let route: PreparedRoute
    let recoverySeed: RouteGuidanceRecoverySeed?
}

private struct ActiveRouteGuidanceSnapshot: Codable {
    let route: PreparedRoute

    static func load() -> PreparedRoute? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let route = try? JSONDecoder().decode(Self.self, from: data).route,
              route.isUsableForGuidance
        else { return nil }
        return route
    }

    static func save(route: PreparedRoute) {
        guard let data = try? JSONEncoder().encode(Self(route: route)) else { return }
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Outbound", isDirectory: true)
            .appendingPathComponent("active-route-guidance.json")
    }
}

extension ActiveRouteGuidanceJournal {
    static func load(recoverySeed: RouteGuidanceRecoverySeed?) -> ActiveRouteGuidanceJournal? {
        ActiveRouteGuidanceSnapshot.load().map { ActiveRouteGuidanceJournal(route: $0, recoverySeed: recoverySeed) }
    }

    func saveRouteSnapshot() {
        ActiveRouteGuidanceSnapshot.save(route: route)
    }
}

struct JournalTrackPoint: Codable {
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let horizontalAccuracy: Double
    let verticalAccuracy: Double
    let course: Double
    let speed: Double
    let timestamp: Date

    init(_ location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        altitude = location.altitude
        horizontalAccuracy = location.horizontalAccuracy
        verticalAccuracy = location.verticalAccuracy
        course = location.course
        speed = location.speed
        timestamp = location.timestamp
    }

    var location: CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            course: course,
            speed: speed,
            timestamp: timestamp
        )
    }
}
