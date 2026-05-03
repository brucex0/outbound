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
            route: SavedRoute(points: SavedRoutePoint.simplified(from: summary.trackPoints)),
            photos: savedPhotos,
            sync: SavedActivitySyncState(
                clientActivityId: activityId.uuidString,
                serverActivityId: nil,
                lastAttemptAt: nil,
                syncedAt: nil,
                lastError: nil
            )
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

    static func replace(_ activity: SavedActivity) throws {
        var activities = try load()
        guard let index = activities.firstIndex(where: { $0.id == activity.id }) else { return }
        activities[index] = activity
        try saveManifest(activities)
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
    let route: SavedRoute?
    let photos: [SavedPhoto]
    let sync: SavedActivitySyncState?

    var routePoints: [SavedRoutePoint] { route?.points ?? [] }
    var routeCoordinates: [CLLocationCoordinate2D] { routePoints.map(\.coordinate) }
    var hasRoute: Bool { routePoints.count > 1 }

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
        if let savedRoute = try c.decodeIfPresent(SavedRoute.self, forKey: .route) {
            route = savedRoute
        } else {
            let legacyTrackPoints = (try? c.decode([SavedTrackPoint].self, forKey: .trackPoints)) ?? []
            route = legacyTrackPoints.isEmpty ? nil : SavedRoute(points: legacyTrackPoints.map(SavedRoutePoint.init))
        }
        photos = try c.decode([SavedPhoto].self, forKey: .photos)
        sync = try c.decodeIfPresent(SavedActivitySyncState.self, forKey: .sync)
        coachNudge = (try? c.decodeIfPresent(String.self, forKey: .coachNudge)) ?? ""
        let day = startedAt.formatted(.dateTime.weekday(.wide))
        title = ((try? c.decodeIfPresent(String.self, forKey: .title)) ?? nil) ?? "\(day) Run"
    }

    init(id: UUID, title: String, coachNudge: String, createdAt: Date,
         startedAt: Date, endedAt: Date, durationSecs: Int, distanceM: Double,
         avgPace: Double?, route: SavedRoute?, photos: [SavedPhoto], sync: SavedActivitySyncState?) {
        self.id = id; self.title = title; self.coachNudge = coachNudge
        self.createdAt = createdAt; self.startedAt = startedAt; self.endedAt = endedAt
        self.durationSecs = durationSecs; self.distanceM = distanceM; self.avgPace = avgPace
        self.route = route; self.photos = photos; self.sync = sync
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case coachNudge
        case createdAt
        case startedAt
        case endedAt
        case durationSecs
        case distanceM
        case avgPace
        case route
        case trackPoints
        case photos
        case sync
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(coachNudge, forKey: .coachNudge)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(endedAt, forKey: .endedAt)
        try c.encode(durationSecs, forKey: .durationSecs)
        try c.encode(distanceM, forKey: .distanceM)
        try c.encodeIfPresent(avgPace, forKey: .avgPace)
        try c.encodeIfPresent(route, forKey: .route)
        try c.encode(photos, forKey: .photos)
        try c.encodeIfPresent(sync, forKey: .sync)
    }
}

struct SavedActivitySyncState: Codable, Hashable {
    let clientActivityId: String
    let serverActivityId: String?
    let lastAttemptAt: Date?
    let syncedAt: Date?
    let lastError: String?

    var isSynced: Bool { syncedAt != nil }
}

struct SavedRoute: Codable, Hashable {
    let points: [SavedRoutePoint]

    init(points: [SavedRoutePoint]) {
        self.points = points
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            points = try container.decode([SavedRoutePoint].self, forKey: .points)
        } else {
            var container = try decoder.unkeyedContainer()
            points = try container.decode([SavedRoutePoint].self)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(points, forKey: .points)
    }

    private enum CodingKeys: String, CodingKey {
        case points
        case visibility
    }
}

struct SavedRoutePoint: Codable, Hashable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double

    nonisolated init(location: CLLocation) {
        timestamp = location.timestamp
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
    }

    init(trackPoint: SavedTrackPoint) {
        timestamp = trackPoint.timestamp
        latitude = trackPoint.latitude
        longitude = trackPoint.longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static func simplified(from locations: [CLLocation]) -> [SavedRoutePoint] {
        guard locations.count > 2 else { return locations.map(Self.init) }

        var keptIndices = [0]
        var lastKeptIndex = 0

        for index in 1..<(locations.count - 1) {
            let current = locations[index]
            let lastKept = locations[lastKeptIndex]
            let next = locations[index + 1]

            let distanceFromLastKept = current.distance(from: lastKept)
            let secondsFromLastKept = current.timestamp.timeIntervalSince(lastKept.timestamp)
            let shouldKeepForDistance = distanceFromLastKept >= 10
            let shouldKeepForTime = secondsFromLastKept >= 15
            let shouldKeepForTurn = isMeaningfulTurn(previous: lastKept, current: current, next: next)

            if shouldKeepForDistance || shouldKeepForTime || shouldKeepForTurn {
                keptIndices.append(index)
                lastKeptIndex = index
            }
        }

        if keptIndices.last != locations.indices.last {
            keptIndices.append(locations.count - 1)
        }

        return keptIndices.map { SavedRoutePoint(location: locations[$0]) }
    }

    private static func isMeaningfulTurn(previous: CLLocation, current: CLLocation, next: CLLocation) -> Bool {
        let incomingDistance = previous.distance(from: current)
        let outgoingDistance = current.distance(from: next)
        guard incomingDistance >= 5, outgoingDistance >= 5 else { return false }

        let incomingBearing = bearing(from: previous.coordinate, to: current.coordinate)
        let outgoingBearing = bearing(from: current.coordinate, to: next.coordinate)
        let delta = abs(incomingBearing - outgoingBearing).truncatingRemainder(dividingBy: 360)
        let normalizedDelta = delta > 180 ? 360 - delta : delta
        return normalizedDelta >= 20
    }

    private static func bearing(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
        let startLat = start.latitude * .pi / 180
        let startLon = start.longitude * .pi / 180
        let endLat = end.latitude * .pi / 180
        let endLon = end.longitude * .pi / 180
        let deltaLon = endLon - startLon

        let y = sin(deltaLon) * cos(endLat)
        let x = cos(startLat) * sin(endLat) - sin(startLat) * cos(endLat) * cos(deltaLon)
        let angle = atan2(y, x) * 180 / .pi
        return angle >= 0 ? angle : angle + 360
    }
}

struct SavedTrackPoint: Codable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let horizontalAccuracy: Double
    let speed: Double
}

enum RouteExportFormat: String, CaseIterable, Identifiable {
    case gpx
    case geoJSON

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gpx: return "GPX"
        case .geoJSON: return "GeoJSON"
        }
    }

    var fileExtension: String {
        switch self {
        case .gpx: return "gpx"
        case .geoJSON: return "geojson"
        }
    }
}

enum RouteFileExporter {
    static func export(activity: SavedActivity, format: RouteExportFormat) throws -> URL {
        guard activity.hasRoute else { throw RouteExportError.missingRoute }

        let fileName = sanitizedFileName(for: activity, format: format)
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let data: Data

        switch format {
        case .gpx:
            data = Data(gpxString(for: activity).utf8)
        case .geoJSON:
            data = try geoJSONData(for: activity)
        }

        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    private static func gpxString(for activity: SavedActivity) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let points = activity.routePoints.map { point in
            """
                  <trkpt lat="\(point.latitude)" lon="\(point.longitude)">
                    <time>\(formatter.string(from: point.timestamp))</time>
                  </trkpt>
            """
        }.joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Outbound" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata>
            <name>\(escapedXML(activity.title))</name>
            <time>\(formatter.string(from: activity.startedAt))</time>
          </metadata>
          <trk>
            <name>\(escapedXML(activity.title))</name>
            <trkseg>
        \(points)
            </trkseg>
          </trk>
        </gpx>
        """
    }

    private static func geoJSONData(for activity: SavedActivity) throws -> Data {
        let payload: [String: Any] = [
            "type": "Feature",
            "properties": [
                "id": activity.id.uuidString,
                "title": activity.title,
                "startedAt": iso8601String(activity.startedAt),
                "endedAt": iso8601String(activity.endedAt),
                "distanceM": activity.distanceM,
                "durationSecs": activity.durationSecs,
                "visibility": "private"
            ],
            "geometry": [
                "type": "LineString",
                "coordinates": activity.routePoints.map { [$0.longitude, $0.latitude] }
            ]
        ]

        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    private static func sanitizedFileName(for activity: SavedActivity, format: RouteExportFormat) -> String {
        let rawTitle = activity.title
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted)
            .joined()
        let fallback = "route-\(activity.id.uuidString.prefix(8))"
        let title = rawTitle.isEmpty ? fallback : rawTitle
        return "\(title).\(format.fileExtension)"
    }

    private static func escapedXML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

enum RouteExportError: LocalizedError {
    case missingRoute

    var errorDescription: String? {
        switch self {
        case .missingRoute:
            return "This activity does not have enough route data to share yet."
        }
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
