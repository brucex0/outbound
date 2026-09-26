import Foundation

/// Sport classification produced by activity-file parsing before the app maps it to `ActivityType`.
nonisolated enum ImportedActivitySport: String, Sendable, Hashable, CaseIterable, Identifiable {
    var id: String { rawValue }

    case running
    case cycling
    case hiking
    case walking
    case swimming
    case strength
    case mobility
    case other

    /// Maps a vendor sport string to the closest supported sport. Returns `nil` when the value is unusable.
    static func from(vendorValue rawValue: String?) -> ImportedActivitySport? {
        guard let normalized = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !normalized.isEmpty
        else { return nil }
        let compact = normalized.filter { $0.isLetter }
        switch compact {
        case "run", "running", "trailrun", "trailrunning", "virtualrun", "treadmillrun", "1":
            return .running
        case "ride", "bike", "cycling", "biking", "virtualride", "ebikeride", "ebike", "2", "cyclingride":
            return .cycling
        case "hike", "hiking", "3":
            return .hiking
        case "walk", "walking", "4":
            return .walking
        case "swim", "swimming", "5", "6":
            return .swimming
        case "weighttraining", "strength", "strengthtraining", "workout", "crossfit", "rowing", "elliptical", "stairstepper":
            return .strength
        case "yoga", "pilates", "mobility", "stretch", "stretching":
            return .mobility
        default:
            return .other
        }
    }
}

/// A single route sample parsed from an activity file.
nonisolated struct ImportedRoutePoint: Sendable, Hashable {
    let timestamp: Date?
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    let startsNewSegment: Bool

    init(
        timestamp: Date?,
        latitude: Double,
        longitude: Double,
        altitude: Double?,
        startsNewSegment: Bool = false
    ) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.startsNewSegment = startsNewSegment
    }
}

/// Everything the importer can recover from one GPX or TCX activity file.
nonisolated struct ParsedActivityFile: Sendable, Equatable {
    let sport: ImportedActivitySport?
    let startedAt: Date?
    let durationSeconds: Int?
    let distanceMeters: Double?
    let elevationGainMeters: Double?
    let averageHeartRateBPM: Int?
    let maxHeartRateBPM: Int?
    let averageCadence: Int?
    let routePoints: [ImportedRoutePoint]
    let titleFromFile: String?

    var hasRoute: Bool { routePoints.count > 1 }
}

/// One importable activity waiting for the runner to confirm it.
nonisolated struct StravaImportCandidate: Sendable, Identifiable, Equatable {
    enum Origin: String, Sendable, Equatable {
        /// Metrics came from a parsed GPX or TCX file.
        case activityFile
        /// Only the export summary row was readable, so the workout imports without a route.
        case exportSummary
    }

    let id: String
    let title: String
    let sport: ImportedActivitySport
    let startedAt: Date
    let durationSeconds: Int
    let distanceMeters: Double?
    let elevationGainMeters: Double?
    let averageHeartRateBPM: Int?
    let maxHeartRateBPM: Int?
    let averageCadence: Int?
    let routePoints: [ImportedRoutePoint]
    let origin: Origin
    let fileName: String?
    /// Stable vendor identifier used for duplicate detection across repeat imports.
    let externalID: String

    var hasRoute: Bool { routePoints.count > 1 }
}

/// A file or summary row the importer could not turn into an activity.
nonisolated struct StravaImportSkip: Sendable, Identifiable, Equatable {
    enum Reason: String, Sendable, Equatable {
        case unsupportedFile
        case unreadableFile
        case duplicate
        case missingDate
        case missingMetrics
        case noActivityFiles
    }

    let id: String
    let fileName: String
    let reason: Reason
}

/// Result of reading one export archive or selection of files.
nonisolated struct StravaImportReview: Sendable, Equatable {
    let sourceName: String
    let candidates: [StravaImportCandidate]
    let skipped: [StravaImportSkip]

    var isEmpty: Bool { candidates.isEmpty }

    var skippedReasonCounts: [StravaImportSkip.Reason: Int] {
        skipped.reduce(into: [:]) { counts, skip in counts[skip.reason, default: 0] += 1 }
    }
}

nonisolated enum StravaImportError: Error, Equatable {
    case emptySelection
    case unreadableArchive
    case noSupportedActivities
}
