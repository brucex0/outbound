import CoreLocation
import Foundation
import UIKit

enum LocalActivityStore {
    private static let manifestFileName = "activities.json"

    @discardableResult
    static func save(
        summary: ActivitySummary,
        photos: [(UIImage, PhotoMetadata)],
        title: String,
        coachNudge: String
    ) throws -> SavedActivity {
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
            title: title,
            coachNudge: coachNudge,
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

    static func delete(_ activity: SavedActivity) throws {
        var activities = try load()
        activities.removeAll { $0.id == activity.id }
        try saveManifest(activities)
        let photoDir = try activitiesDirectory().appendingPathComponent(activity.id.uuidString)
        try? FileManager.default.removeItem(at: photoDir)
    }

    static func imageURL(for photo: SavedPhoto) throws -> URL {
        try activitiesDirectory().appendingPathComponent(photo.relativePath)
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
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

struct SavedActivity: Codable, Identifiable, Hashable {
    static func == (lhs: SavedActivity, rhs: SavedActivity) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    let id: UUID
    let title: String
    let coachNudge: String
    let createdAt: Date
    let startedAt: Date
    let endedAt: Date
    let durationSecs: Int
    let distanceM: Double
    let avgPace: Double?
    let trackPoints: [SavedTrackPoint]
    let photos: [SavedPhoto]

    // Backward-compatible decoder for activities saved before title/coachNudge existed
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        endedAt = try c.decode(Date.self, forKey: .endedAt)
        durationSecs = try c.decode(Int.self, forKey: .durationSecs)
        distanceM = try c.decode(Double.self, forKey: .distanceM)
        avgPace = try c.decodeIfPresent(Double.self, forKey: .avgPace)
        trackPoints = try c.decode([SavedTrackPoint].self, forKey: .trackPoints)
        photos = try c.decode([SavedPhoto].self, forKey: .photos)
        coachNudge = (try? c.decodeIfPresent(String.self, forKey: .coachNudge)) ?? ""
        let day = startedAt.formatted(.dateTime.weekday(.wide))
        title = ((try? c.decodeIfPresent(String.self, forKey: .title)) ?? nil) ?? "\(day) Run"
    }

    init(id: UUID, title: String, coachNudge: String, createdAt: Date,
         startedAt: Date, endedAt: Date, durationSecs: Int, distanceM: Double,
         avgPace: Double?, trackPoints: [SavedTrackPoint], photos: [SavedPhoto]) {
        self.id = id; self.title = title; self.coachNudge = coachNudge
        self.createdAt = createdAt; self.startedAt = startedAt; self.endedAt = endedAt
        self.durationSecs = durationSecs; self.distanceM = distanceM; self.avgPace = avgPace
        self.trackPoints = trackPoints; self.photos = photos
    }
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
    let captureContext: PhotoCaptureContext
    let relativePath: String

    nonisolated init(metadata: PhotoMetadata, relativePath: String) {
        id = UUID()
        takenAt = metadata.takenAt
        paceAtShot = metadata.paceAtShot
        hrAtShot = metadata.hrAtShot
        distAtShot = metadata.distAtShot
        coordinate = metadata.coordinate.map { SavedCoordinate(coordinate: $0) }
        captureContext = metadata.captureContext
        self.relativePath = relativePath
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        takenAt = try c.decode(Date.self, forKey: .takenAt)
        paceAtShot = try c.decodeIfPresent(Double.self, forKey: .paceAtShot)
        hrAtShot = try c.decodeIfPresent(Int.self, forKey: .hrAtShot)
        distAtShot = try c.decode(Double.self, forKey: .distAtShot)
        coordinate = try c.decodeIfPresent(SavedCoordinate.self, forKey: .coordinate)
        captureContext = (try? c.decode(PhotoCaptureContext.self, forKey: .captureContext)) ?? .active
        relativePath = try c.decode(String.self, forKey: .relativePath)
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
