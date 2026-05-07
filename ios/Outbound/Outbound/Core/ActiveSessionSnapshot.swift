import CoreLocation
import Foundation

struct ActiveSessionSnapshot: Equatable {
    let recordedAt: Date
    let startedAt: Date?
    let elapsedSeconds: Int
    let distanceMeters: Double
    let currentPaceSecsPerKm: Double?
    let heartRate: Int?
    let location: SessionLocation?
    let isActive: Bool

    static var empty: ActiveSessionSnapshot {
        ActiveSessionSnapshot(
            recordedAt: Date(),
            startedAt: nil,
            elapsedSeconds: 0,
            distanceMeters: 0,
            currentPaceSecsPerKm: nil,
            heartRate: nil,
            location: nil,
            isActive: false
        )
    }

    var distanceKilometers: Double {
        distanceMeters / 1000
    }
}

struct SessionIntentStep: Identifiable, Hashable, Codable {
    let id: String
    let label: String
    let durationSeconds: Int
    let detail: String?
}

struct SessionIntent: Identifiable, Hashable {
    let id: String
    let sport: SportType
    let title: String
    let detail: String
    let coachLine: String
    let startLabel: String
    let targetDistanceMeters: Double?
    let targetDurationSeconds: Int?
    let routeName: String?
    let workoutSteps: [SessionIntentStep]

    init(
        id: String,
        sport: SportType,
        title: String,
        detail: String,
        coachLine: String,
        startLabel: String,
        targetDistanceMeters: Double? = nil,
        targetDurationSeconds: Int? = nil,
        routeName: String? = nil,
        workoutSteps: [SessionIntentStep] = []
    ) {
        self.id = id
        self.sport = sport
        self.title = title
        self.detail = detail
        self.coachLine = coachLine
        self.startLabel = startLabel
        self.targetDistanceMeters = targetDistanceMeters
        self.targetDurationSeconds = targetDurationSeconds
        self.routeName = routeName
        self.workoutSteps = workoutSteps
    }

    var systemImage: String { sport.systemImage }

    var resolvedTargetDistanceMeters: Double? {
        targetDistanceMeters
            ?? SessionIntentGoalParser.distanceMeters(from: title)
            ?? SessionIntentGoalParser.distanceMeters(from: detail)
    }

    var resolvedTargetDurationSeconds: Int? {
        targetDurationSeconds ?? SessionIntentGoalParser.durationSeconds(from: detail)
    }

    var hasPlannedStructure: Bool {
        resolvedTargetDistanceMeters != nil
            || resolvedTargetDurationSeconds != nil
            || routeName != nil
            || !workoutSteps.isEmpty
    }

    static let freestyleRun = SessionIntent(
        id: "freestyle-run",
        sport: .run,
        title: "Freestyle run",
        detail: "Run • no preset target",
        coachLine: "No pressure. Just start where you are.",
        startLabel: "Start now"
    )
}

enum SessionIntentGoalParser {
    static func distanceMeters(from text: String) -> Double? {
        let lowercased = text.lowercased()
        guard !lowercased.contains("no preset") else { return nil }
        if lowercased.range(of: #"\b[0-9]+(?:\.[0-9]+)?\s*x\s*[0-9]"#, options: .regularExpression) != nil {
            return nil
        }

        let patterns: [(String, Double)] = [
            (#"([0-9]+(?:\.[0-9]+)?)\s*(?:km|kilometer|kilometers)\b"#, 1000),
            (#"\b([0-9]+(?:\.[0-9]+)?)\s*k\b"#, 1000),
            (#"([0-9]+(?:\.[0-9]+)?)\s*(?:mi|mile|miles)\b"#, 1609.344),
            (#"([0-9]+(?:\.[0-9]+)?)\s*m\b"#, 1)
        ]

        for (pattern, multiplier) in patterns {
            guard let value = firstNumber(in: lowercased, pattern: pattern) else { continue }
            if multiplier == 1, value < 100 { continue }
            return value * multiplier
        }

        return nil
    }

    static func durationSeconds(from text: String) -> Int? {
        let lowercased = text.lowercased()
        guard !lowercased.contains("no preset") else { return nil }

        if let minutes = firstNumber(in: lowercased, pattern: #"([0-9]+(?:\.[0-9]+)?)\s*(?:min|mins|minute|minutes)\b"#) {
            return Int((minutes * 60).rounded())
        }

        if let hours = firstNumber(in: lowercased, pattern: #"([0-9]+(?:\.[0-9]+)?)\s*(?:hr|hrs|hour|hours)\b"#) {
            return Int((hours * 3600).rounded())
        }

        return nil
    }

    private static func firstNumber(in text: String, pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }

        return Double(text[valueRange])
    }
}

struct SessionLocation: Equatable {
    let latitude: Double
    let longitude: Double
    let altitudeMeters: Double
    let horizontalAccuracyMeters: Double
    let speedMetersPerSecond: Double?
    let courseDegrees: Double?

    init(_ location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        altitudeMeters = location.altitude
        horizontalAccuracyMeters = location.horizontalAccuracy
        speedMetersPerSecond = location.speed >= 0 ? location.speed : nil
        courseDegrees = location.course >= 0 ? location.course : nil
    }
}
