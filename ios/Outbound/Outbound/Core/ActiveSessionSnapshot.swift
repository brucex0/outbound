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

enum SessionCoachingPhase: String, Codable, Hashable {
    case warmup
    case easy
    case work
    case recovery
    case walk
    case cooldown
    case open
}

enum SessionPaceReference: String, Codable, Hashable {
    case athleteReference = "athlete_reference"
    case absolute
}

struct SessionPaceTarget: Codable, Hashable {
    let reference: SessionPaceReference
    let targetSecondsPerKilometer: Double?
    let athleteReferenceOffsetSeconds: Double
    let fasterToleranceSeconds: Double
    let slowerToleranceSeconds: Double?

    init(
        reference: SessionPaceReference,
        targetSecondsPerKilometer: Double? = nil,
        athleteReferenceOffsetSeconds: Double = 0,
        fasterToleranceSeconds: Double,
        slowerToleranceSeconds: Double? = nil
    ) {
        self.reference = reference
        self.targetSecondsPerKilometer = targetSecondsPerKilometer
        self.athleteReferenceOffsetSeconds = athleteReferenceOffsetSeconds
        self.fasterToleranceSeconds = fasterToleranceSeconds
        self.slowerToleranceSeconds = slowerToleranceSeconds
    }

    func resolvedTarget(athleteReferencePace: Double?) -> Double? {
        let value: Double?
        switch reference {
        case .athleteReference:
            value = athleteReferencePace.map { $0 + athleteReferenceOffsetSeconds }
        case .absolute:
            value = targetSecondsPerKilometer
        }
        guard let value, value.isFinite, (60...3_600).contains(value) else { return nil }
        return value
    }
}

struct SessionCoachingTarget: Codable, Hashable {
    let phase: SessionCoachingPhase
    let pace: SessionPaceTarget?
    let recognizesTargetLock: Bool

    init(
        phase: SessionCoachingPhase,
        pace: SessionPaceTarget? = nil,
        recognizesTargetLock: Bool = false
    ) {
        self.phase = phase
        self.pace = pace
        self.recognizesTargetLock = recognizesTargetLock
    }

    static let warmup = SessionCoachingTarget(
        phase: .warmup,
        pace: SessionPaceTarget(
            reference: .athleteReference,
            athleteReferenceOffsetSeconds: 30,
            fasterToleranceSeconds: 20
        )
    )

    static let easy = SessionCoachingTarget(
        phase: .easy,
        pace: SessionPaceTarget(
            reference: .athleteReference,
            fasterToleranceSeconds: 20,
            slowerToleranceSeconds: 35
        ),
        recognizesTargetLock: true
    )

    static let work = SessionCoachingTarget(phase: .work)

    static let recovery = SessionCoachingTarget(
        phase: .recovery,
        pace: SessionPaceTarget(
            reference: .athleteReference,
            athleteReferenceOffsetSeconds: 45,
            fasterToleranceSeconds: 25
        )
    )

    static let walk = SessionCoachingTarget(phase: .walk)

    static let cooldown = SessionCoachingTarget(
        phase: .cooldown,
        pace: SessionPaceTarget(
            reference: .athleteReference,
            athleteReferenceOffsetSeconds: 60,
            fasterToleranceSeconds: 30
        )
    )

    static let open = SessionCoachingTarget(phase: .open)
}

struct SessionIntentStep: Identifiable, Hashable, Codable {
    let id: String
    let label: String
    let durationSeconds: Int
    let detail: String?
    let coachingTarget: SessionCoachingTarget?

    init(
        id: String,
        label: String,
        durationSeconds: Int,
        detail: String?,
        coachingTarget: SessionCoachingTarget? = nil
    ) {
        self.id = id
        self.label = label
        self.durationSeconds = durationSeconds
        self.detail = detail
        self.coachingTarget = coachingTarget
    }
}

struct ActiveSessionCoachingSegment: Hashable {
    let id: String
    let target: SessionCoachingTarget
    let elapsedSeconds: Int
    let durationSeconds: Int?
}

struct SessionIntent: Identifiable, Hashable {
    let id: String
    let sport: SportType
    let title: String
    let detail: String
    let guideLine: String
    let startLabel: String
    let targetDistanceMeters: Double?
    let targetDurationSeconds: Int?
    let targetCalories: Int?
    let routeName: String?
    let preparedRoute: PreparedRoute?
    let activityTypeOverride: ActivityType?
    let workoutSteps: [SessionIntentStep]
    let coachingTarget: SessionCoachingTarget?
    let activityEvent: ActivityEventLaunchContext?

    init(
        id: String,
        sport: SportType,
        title: String,
        detail: String,
        guideLine: String,
        startLabel: String,
        targetDistanceMeters: Double? = nil,
        targetDurationSeconds: Int? = nil,
        targetCalories: Int? = nil,
        routeName: String? = nil,
        preparedRoute: PreparedRoute? = nil,
        activityTypeOverride: ActivityType? = nil,
        workoutSteps: [SessionIntentStep] = [],
        coachingTarget: SessionCoachingTarget? = nil,
        activityEvent: ActivityEventLaunchContext? = nil
    ) {
        self.id = id
        self.sport = sport
        self.title = title
        self.detail = detail
        self.guideLine = guideLine
        self.startLabel = startLabel
        self.targetDistanceMeters = targetDistanceMeters
        self.targetDurationSeconds = targetDurationSeconds
        self.targetCalories = targetCalories
        self.routeName = routeName
        self.preparedRoute = preparedRoute
        self.activityTypeOverride = activityTypeOverride
        self.workoutSteps = workoutSteps
        self.coachingTarget = coachingTarget
        self.activityEvent = activityEvent
    }

    var systemImage: String { sport.systemImage }

    var resolvedActivityType: ActivityType {
        activityTypeOverride ?? sport.activityType
    }

    var resolvedTargetDistanceMeters: Double? {
        if let targetDistanceMeters { return targetDistanceMeters }
        guard preparedRoute == nil else { return nil }
        return SessionIntentGoalParser.distanceMeters(from: title)
            ?? SessionIntentGoalParser.distanceMeters(from: detail)
    }

    var resolvedTargetDurationSeconds: Int? {
        if let targetDurationSeconds { return targetDurationSeconds }
        guard preparedRoute == nil else { return nil }
        return SessionIntentGoalParser.durationSeconds(from: detail)
    }

    var resolvedTargetCalories: Int? {
        targetCalories
    }

    var hasPlannedStructure: Bool {
        resolvedTargetDistanceMeters != nil
            || resolvedTargetDurationSeconds != nil
            || resolvedTargetCalories != nil
            || routeName != nil
            || !workoutSteps.isEmpty
    }

    func activeCoachingSegment(at elapsedSeconds: Int) -> ActiveSessionCoachingSegment? {
        let timedSteps = workoutSteps.filter { $0.durationSeconds > 0 }
        var boundary = 0
        for step in timedSteps {
            let start = boundary
            boundary += step.durationSeconds
            guard elapsedSeconds < boundary else { continue }
            guard let target = step.coachingTarget else { return nil }
            return ActiveSessionCoachingSegment(
                id: step.id,
                target: target,
                elapsedSeconds: max(0, elapsedSeconds - start),
                durationSeconds: step.durationSeconds
            )
        }

        if let last = timedSteps.last, let target = last.coachingTarget {
            return ActiveSessionCoachingSegment(
                id: last.id,
                target: target,
                elapsedSeconds: max(0, elapsedSeconds - max(0, boundary - last.durationSeconds)),
                durationSeconds: last.durationSeconds
            )
        }

        guard let coachingTarget else { return nil }
        return ActiveSessionCoachingSegment(
            id: "session",
            target: coachingTarget,
            elapsedSeconds: max(0, elapsedSeconds),
            durationSeconds: resolvedTargetDurationSeconds
        )
    }

    static let freestyleRun = SessionIntent(
        id: "freestyle-run",
        sport: .run,
        title: String(localized: "Freestyle run"),
        detail: String(localized: "activity.goal.freestyle.detail.short", defaultValue: "Run • no preset target"),
        guideLine: String(localized: "activity.goal.companion.freestyle", defaultValue: "No pressure. Just start where you are."),
        startLabel: String(localized: "Start now")
    )
}

struct ActivityEventLaunchContext: Hashable {
    let id: String
    let title: String
    let role: String
    let attendanceMode: String?
    let organizerName: String
}

enum SessionIntentGoalParser {
    nonisolated static func distanceMeters(from text: String) -> Double? {
        let lowercased = text.lowercased()
        guard !lowercased.contains("no preset") else { return nil }
        if lowercased.range(of: #"\b[0-9]+(?:\.[0-9]+)?\s*x\s*[0-9]"#, options: .regularExpression) != nil {
            return nil
        }

        let patterns: [(String, Double)] = [
            (#"([0-9]+(?:\.[0-9]+)?)\s*(?:km|kilometer|kilometers|kilómetro|kilómetros|公里)\b"#, 1000),
            (#"\b([0-9]+(?:\.[0-9]+)?)\s*k\b"#, 1000),
            (#"([0-9]+(?:\.[0-9]+)?)\s*(?:mi|mile|miles|milla|millas|英里)\b"#, 1609.344),
            (#"([0-9]+(?:\.[0-9]+)?)\s*(?:m|meter|meters|metro|metros|米)\b"#, 1)
        ]

        for (pattern, multiplier) in patterns {
            guard let value = firstNumber(in: lowercased, pattern: pattern) else { continue }
            if multiplier == 1, value < 100 { continue }
            return value * multiplier
        }

        return nil
    }

    nonisolated static func durationSeconds(from text: String) -> Int? {
        let lowercased = text.lowercased()
        guard !lowercased.contains("no preset") else { return nil }

        if let minutes = firstNumber(in: lowercased, pattern: #"([0-9]+(?:\.[0-9]+)?)\s*(?:min|mins|minute|minutes|minuto|minutos|分钟)\b"#) {
            return Int((minutes * 60).rounded())
        }

        if let hours = firstNumber(in: lowercased, pattern: #"([0-9]+(?:\.[0-9]+)?)\s*(?:hr|hrs|hour|hours|hora|horas|小时)\b"#) {
            return Int((hours * 3600).rounded())
        }

        return nil
    }

    nonisolated private static func firstNumber(in text: String, pattern: String) -> Double? {
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
    let verticalAccuracyMeters: Double
    let speedMetersPerSecond: Double?
    let courseDegrees: Double?

    init(_ location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        altitudeMeters = location.altitude
        horizontalAccuracyMeters = location.horizontalAccuracy
        verticalAccuracyMeters = location.verticalAccuracy
        speedMetersPerSecond = location.speed >= 0 ? location.speed : nil
        courseDegrees = location.course >= 0 ? location.course : nil
    }
}
