import CoreLocation
import Foundation
import UIKit

enum LocalActivityStore {
    private static let manifestFileName = "activities.json"

    @discardableResult
    static func save(summary: ActivitySummary, photos: [(UIImage, PhotoMetadata)]) throws -> SavedActivity {
        let activityId = UUID()
        let activityDirectory = try directory(for: activityId)
        let photoDirectory = activityDirectory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoDirectory, withIntermediateDirectories: true)

        let savedPhotos = try photos.enumerated().compactMap { index, capture -> SavedPhoto? in
            let fileName = String(format: "photo-%02d.jpg", index + 1)
            let photoURL = photoDirectory.appendingPathComponent(fileName)
            guard let data = capture.0.jpegData(compressionQuality: 0.9) else { return nil }
            try data.write(to: photoURL, options: .atomic)
            return SavedPhoto(metadata: capture.1, relativePath: "\(activityId.uuidString)/photos/\(fileName)")
        }

        let activity = SavedActivity(
            id: activityId,
            createdAt: Date(),
            startedAt: summary.startedAt,
            endedAt: summary.endedAt,
            durationSecs: summary.durationSecs,
            distanceM: summary.distanceM,
            avgPace: summary.avgPace,
            trackPoints: summary.trackPoints.map(SavedTrackPoint.init),
            photos: savedPhotos
        )

        var activities = try load()
        activities.insert(activity, at: 0)
        try saveManifest(activities)
        return activity
    }

    static func load() throws -> [SavedActivity] {
        let manifest = try manifestURL()
        guard FileManager.default.fileExists(atPath: manifest.path) else { return [] }
        let data = try Data(contentsOf: manifest)
        return try decoder.decode([SavedActivity].self, from: data)
    }

    private static func saveManifest(_ activities: [SavedActivity]) throws {
        let data = try encoder.encode(activities)
        try data.write(to: try manifestURL(), options: .atomic)
    }

    private static func directory(for activityId: UUID) throws -> URL {
        let url = try activitiesDirectory().appendingPathComponent(activityId.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func manifestURL() throws -> URL {
        try activitiesDirectory().appendingPathComponent(manifestFileName)
    }

    private static func activitiesDirectory() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support.appendingPathComponent("Outbound/Activities", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

struct SavedActivity: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let startedAt: Date
    let endedAt: Date
    let durationSecs: Int
    let distanceM: Double
    let avgPace: Double?
    let trackPoints: [SavedTrackPoint]
    let photos: [SavedPhoto]
}

struct SavedTrackPoint: Codable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let horizontalAccuracy: Double
    let speed: Double

    nonisolated init(location: CLLocation) {
        timestamp = location.timestamp
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        altitude = location.altitude
        horizontalAccuracy = location.horizontalAccuracy
        speed = location.speed
    }
}

struct SavedPhoto: Codable, Identifiable {
    let id: UUID
    let takenAt: Date
    let paceAtShot: Double?
    let hrAtShot: Int?
    let distAtShot: Double
    let coordinate: SavedCoordinate?
    let relativePath: String

    nonisolated init(metadata: PhotoMetadata, relativePath: String) {
        id = UUID()
        takenAt = metadata.takenAt
        paceAtShot = metadata.paceAtShot
        hrAtShot = metadata.hrAtShot
        distAtShot = metadata.distAtShot
        coordinate = metadata.coordinate.map { SavedCoordinate(coordinate: $0) }
        self.relativePath = relativePath
    }
}

struct SavedCoordinate: Codable {
    let latitude: Double
    let longitude: Double

    nonisolated init(coordinate: CLLocationCoordinate2D) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }
}
