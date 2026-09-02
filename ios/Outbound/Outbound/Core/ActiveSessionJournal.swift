import CoreLocation
import Foundation
import UIKit

struct ActiveSessionJournal {
    let startedAt: Date
    let elapsedSeconds: Int
    let wasPaused: Bool
    let activityType: ActivityType?
    let walkingStepCount: Int?
    let routeGuidanceRecoverySeed: RouteGuidanceRecoverySeed?
    let recoveryStage: ActiveSessionRecoveryStage
    let trackPoints: [JournalTrackPoint]

    init(
        startedAt: Date,
        elapsedSeconds: Int,
        wasPaused: Bool,
        activityType: ActivityType?,
        walkingStepCount: Int? = nil,
        routeGuidanceRecoverySeed: RouteGuidanceRecoverySeed?,
        recoveryStage: ActiveSessionRecoveryStage = .recording,
        trackPoints: [JournalTrackPoint] = []
    ) {
        self.startedAt = startedAt
        self.elapsedSeconds = elapsedSeconds
        self.wasPaused = wasPaused
        self.activityType = activityType
        self.walkingStepCount = walkingStepCount
        self.routeGuidanceRecoverySeed = routeGuidanceRecoverySeed
        self.recoveryStage = recoveryStage
        self.trackPoints = trackPoints
    }

    static func load() -> ActiveSessionJournal? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            let metadata = try JSONDecoder().decode(Metadata.self, from: data)
            return ActiveSessionJournal(
                startedAt: metadata.startedAt,
                elapsedSeconds: metadata.elapsedSeconds,
                wasPaused: metadata.wasPaused,
                activityType: metadata.activityType,
                walkingStepCount: metadata.walkingStepCount,
                routeGuidanceRecoverySeed: metadata.routeGuidanceRecoverySeed,
                recoveryStage: metadata.recoveryStage ?? .recording,
                trackPoints: ActiveSessionTrackJournal.load()
            )
        } catch {
            ActivityDiagnosticLog.error(
                .recovery,
                "Recovery metadata load failed error=\(ActivityDiagnosticLog.errorCategory(error))"
            )
            return nil
        }
    }

    @discardableResult
    func save() -> Bool {
        do {
            let metadata = Metadata(
                startedAt: startedAt,
                elapsedSeconds: elapsedSeconds,
                wasPaused: wasPaused,
                activityType: activityType,
                walkingStepCount: walkingStepCount,
                routeGuidanceRecoverySeed: routeGuidanceRecoverySeed,
                recoveryStage: recoveryStage
            )
            let data = try JSONEncoder().encode(metadata)
            let directory = Self.fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: Self.fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func clear(reason: ActiveSessionClearReason) {
        let metadataPresent = FileManager.default.fileExists(atPath: fileURL.path)
        let metadataCleared = removeIfPresent(fileURL)
        let trackCleared = ActiveSessionTrackJournal.clear()
        let routeCleared = ActiveRouteGuidanceSnapshot.clear()
        let succeeded = metadataCleared && trackCleared && routeCleared
        ActivityDiagnosticLog.notice(
            .recovery,
            "Recovery artifacts cleared reason=\(reason.rawValue) metadata_present=\(metadataPresent) result=\(succeeded ? "success" : "failure")"
        )
    }

    private static func removeIfPresent(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            return false
        }
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
        let walkingStepCount: Int?
        let routeGuidanceRecoverySeed: RouteGuidanceRecoverySeed?
        let recoveryStage: ActiveSessionRecoveryStage?
    }
}

enum ActiveSessionRecoveryStage: String, Codable {
    case recording
    case awaitingSave
}

enum ActiveSessionClearReason: String {
    case newRecording = "new_recording"
    case saved
    case discarded
}

enum ActiveSessionTrackJournal {
    static func load() -> [JournalTrackPoint] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            ActivityDiagnosticLog.error(
                .recovery,
                "Recovery track load failed error=\(ActivityDiagnosticLog.errorCategory(error))"
            )
            return []
        }
        guard !data.isEmpty else { return [] }
        let decoder = JSONDecoder()
        var malformedChunks = 0
        let points = data.split(separator: 0x0A).flatMap { line in
            do {
                return try decoder.decode([JournalTrackPoint].self, from: Data(line))
            } catch {
                malformedChunks += 1
                return []
            }
        }
        if malformedChunks > 0 {
            ActivityDiagnosticLog.error(
                .recovery,
                "Recovery track load skipped malformed_chunks=\(ActivityDiagnosticLog.countBucket(malformedChunks))"
            )
        }
        return points
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

    static func clear() -> Bool {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return true }
        do {
            try FileManager.default.removeItem(at: fileURL)
            return true
        } catch {
            return false
        }
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

    @discardableResult
    static func append(_ photo: (UIImage, PhotoMetadata)) -> Bool {
        let entry = Entry(metadata: photo.1)
        let imageURL = directoryURL.appendingPathComponent(entry.fileName)
        guard let imageData = photo.0.jpegData(compressionQuality: 0.9) else {
            ActivityDiagnosticLog.error(.recovery, "Recovery photo save failed error=image_encoding")
            return false
        }

        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try imageData.write(to: imageURL, options: .atomic)
            var entries = loadEntries()
            entries.append(entry)
            try save(entries)
            return true
        } catch {
            try? FileManager.default.removeItem(at: imageURL)
            ActivityDiagnosticLog.error(
                .recovery,
                "Recovery photo save failed error=\(ActivityDiagnosticLog.errorCategory(error))"
            )
            return false
        }
    }

    static func replace(with photos: [(UIImage, PhotoMetadata)]) {
        let cleared = clear()
        let saved = photos.map(append).allSatisfy { $0 }
        ActivityDiagnosticLog.notice(
            .recovery,
            "Recovery photo set replaced photos=\(ActivityDiagnosticLog.countBucket(photos.count)) result=\(cleared && saved ? "success" : "failure")"
        )
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
            ActivityDiagnosticLog.error(
                .recovery,
                "Recovery pre-activity photo removal failed error=\(ActivityDiagnosticLog.errorCategory(error))"
            )
            return
        }
    }

    @discardableResult
    static func clear() -> Bool {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return true }
        do {
            try FileManager.default.removeItem(at: directoryURL)
            return true
        } catch {
            ActivityDiagnosticLog.error(
                .recovery,
                "Recovery photo clear failed error=\(ActivityDiagnosticLog.errorCategory(error))"
            )
            return false
        }
    }

    private static func loadEntries() -> [Entry] {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: manifestURL)
            return try JSONDecoder().decode(Manifest.self, from: data).photos
        } catch {
            ActivityDiagnosticLog.error(
                .recovery,
                "Recovery photo manifest load failed error=\(ActivityDiagnosticLog.errorCategory(error))"
            )
            return []
        }
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
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            let route = try JSONDecoder().decode(Self.self, from: data).route
            guard route.isUsableForGuidance else {
                ActivityDiagnosticLog.error(.recovery, "Recovery route load failed error=invalid_route")
                return nil
            }
            return route
        } catch {
            ActivityDiagnosticLog.error(
                .recovery,
                "Recovery route load failed error=\(ActivityDiagnosticLog.errorCategory(error))"
            )
            return nil
        }
    }

    static func save(route: PreparedRoute) {
        do {
            let data = try JSONEncoder().encode(Self(route: route))
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            ActivityDiagnosticLog.error(
                .recovery,
                "Recovery route save failed error=\(ActivityDiagnosticLog.errorCategory(error))"
            )
        }
    }

    static func clear() -> Bool {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return true }
        do {
            try FileManager.default.removeItem(at: fileURL)
            return true
        } catch {
            return false
        }
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
    let courseAccuracy: Double
    let speed: Double
    let speedAccuracy: Double
    let timestamp: Date
    let startsNewSegment: Bool

    init(_ location: CLLocation, startsNewSegment: Bool = false) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        altitude = location.altitude
        horizontalAccuracy = location.horizontalAccuracy
        verticalAccuracy = location.verticalAccuracy
        course = location.course
        courseAccuracy = location.courseAccuracy
        speed = location.speed
        speedAccuracy = location.speedAccuracy
        timestamp = location.timestamp
        self.startsNewSegment = startsNewSegment
    }

    var location: CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            course: course,
            courseAccuracy: courseAccuracy,
            speed: speed,
            speedAccuracy: speedAccuracy,
            timestamp: timestamp
        )
    }

    private enum CodingKeys: String, CodingKey {
        case latitude, longitude, altitude, horizontalAccuracy, verticalAccuracy
        case course, courseAccuracy, speed, speedAccuracy, timestamp, startsNewSegment
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        altitude = try container.decode(Double.self, forKey: .altitude)
        horizontalAccuracy = try container.decode(Double.self, forKey: .horizontalAccuracy)
        verticalAccuracy = try container.decode(Double.self, forKey: .verticalAccuracy)
        course = try container.decode(Double.self, forKey: .course)
        courseAccuracy = try container.decodeIfPresent(Double.self, forKey: .courseAccuracy) ?? -1
        speed = try container.decode(Double.self, forKey: .speed)
        speedAccuracy = try container.decodeIfPresent(Double.self, forKey: .speedAccuracy) ?? -1
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        startsNewSegment = try container.decodeIfPresent(Bool.self, forKey: .startsNewSegment) ?? false
    }
}
