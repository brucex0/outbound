import Foundation

enum RunnerConfidence: String, Codable, Sendable {
    case low
    case medium
    case high
}

enum CalibrationStatus: String, Codable, Sendable {
    case notStarted
    case inProgress
    case completed
    case skipped
}

enum CalibrationSessionKind: String, Codable, Sendable {
    case comfortableRun
    case easyPickups
    case longerRelaxedRun
}

struct CalibrationSummaryDTO: Codable, Equatable, Sendable {
    let status: CalibrationStatus
    let completedSessionCount: Int
    let targetSessionCount: Int
    let currentSession: CalibrationSessionKind?
}

struct CalibrationWorkoutStepDTO: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let durationSeconds: Int
    let detail: String
}

struct CalibrationWorkoutDTO: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let kind: CalibrationSessionKind
    let title: String
    let purpose: String
    let durationSeconds: Int
    let steps: [CalibrationWorkoutStepDTO]

    var sessionIntent: SessionIntent {
        SessionIntent(
            id: id,
            sport: .run,
            title: title,
            detail: String(localized: "Run · \(durationLabel) · conversational effort"),
            guideLine: purpose,
            startLabel: String(localized: "Start workout"),
            targetDurationSeconds: durationSeconds,
            workoutSteps: steps.enumerated().map { index, step in
                SessionIntentStep(
                    id: step.id,
                    label: step.label,
                    durationSeconds: step.durationSeconds,
                    detail: step.detail,
                    coachingTarget: coachingTarget(for: index)
                )
            }
        )
    }

    private func coachingTarget(for index: Int) -> SessionCoachingTarget {
        if index == 0 { return .warmup }
        if index == steps.count - 1 { return .cooldown }
        return kind == .easyPickups ? .work : .easy
    }

    private var durationLabel: String {
        durationSeconds % 60 == 0
            ? "\(durationSeconds / 60) min"
            : "\(durationSeconds / 60)m \(durationSeconds % 60)s"
    }
}

enum RunnerInsightKind: String, Codable, Sendable {
    case effort
    case endurance
    case recovery
    case schedule
    case preference
    case consistency
}

struct RunnerInsightDTO: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let kind: RunnerInsightKind
    let label: String
    let value: String
    let confidence: RunnerConfidence
    let evidenceCount: Int
    let lastUpdatedAt: Date
}

enum AdjustmentReasonCode: String, Codable, Sendable {
    case fatigue
    case soreness
    case timeConstraint
    case harderThanExpected
    case missedWorkout
    case improving
}

struct PlanChangeDTO: Codable, Equatable, Sendable {
    let workoutId: String
    let beforeTitle: String
    let afterTitle: String
}

struct AdjustmentProposalDTO: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let reasonCode: AdjustmentReasonCode
    let explanation: String
    let requiresConfirmation: Bool
    let changes: [PlanChangeDTO]
}

struct PersonalizationSnapshotDTO: Codable, Equatable, Sendable {
    let contractVersion: Int
    let modelVersion: String
    let generatedAt: Date
    let calibration: CalibrationSummaryDTO
    let calibrationWorkouts: [CalibrationWorkoutDTO]
    let insights: [RunnerInsightDTO]
    let pendingAdjustment: AdjustmentProposalDTO?

    var currentCalibrationWorkout: CalibrationWorkoutDTO? {
        guard calibration.status == .inProgress,
              let currentSession = calibration.currentSession
        else { return nil }
        return calibrationWorkouts.first { $0.kind == currentSession }
    }
}

enum ReadinessChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case good
    case tired
    case sore
    case shortOnTime

    var id: Self { self }
}

struct ReadinessCheckInRequestDTO: Codable, Equatable, Sendable {
    let idempotencyKey: String
    let workoutId: String
    let recordedAt: Date
    let choice: ReadinessChoice
    let note: String?
}

enum RunEffort: String, Codable, CaseIterable, Identifiable, Sendable {
    case easy
    case aboutRight
    case tooHard

    var id: Self { self }
}

enum ContinuationCapacity: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case tenMinutes
    case muchLonger

    var id: Self { self }
}

struct WorkoutFeedbackRequestDTO: Codable, Equatable, Sendable {
    let idempotencyKey: String
    let workoutId: String
    let activityId: String?
    let recordedAt: Date
    let effort: RunEffort
    let continuationCapacity: ContinuationCapacity?
    let note: String?
}

struct RunnerProfileRequestDTO: Codable, Equatable, Sendable {
    let goalSummary: String?
    let scheduleSummary: String?
    let comfortableDurationMinutes: Int?
    let recentSessionsPerWeek: Int?
    let targetSessionsPerWeek: Int
    let preferredLongRunDay: String?
    let guidanceDetail: String
    let primaryMotivation: RunnerPrimaryMotivation
    let preferredRunGoalType: PreferredRunGoalType
    let constraints: [String: String]
    let complete: Bool
}

enum RunnerPrimaryMotivation: String, Codable, CaseIterable, Identifiable, Sendable {
    case generalFitness
    case consistency
    case performance
    case weightLoss
    case weightMaintenance

    var id: Self { self }

    var title: String {
        switch self {
        case .generalFitness: String(localized: "profile.motivation.general_fitness", defaultValue: "General fitness")
        case .consistency: String(localized: "profile.motivation.consistency", defaultValue: "Run consistently")
        case .performance: String(localized: "profile.motivation.performance", defaultValue: "Performance")
        case .weightLoss: String(localized: "profile.motivation.weight_loss", defaultValue: "Support weight loss")
        case .weightMaintenance: String(localized: "profile.motivation.weight_maintenance", defaultValue: "Maintain weight")
        }
    }
}

enum PreferredRunGoalType: String, Codable, CaseIterable, Identifiable, Sendable {
    case time
    case distance
    case calories

    var id: Self { self }

    var title: String {
        switch self {
        case .time: String(localized: "record.goal.time", defaultValue: "Time")
        case .distance: String(localized: "record.goal.distance", defaultValue: "Distance")
        case .calories: String(localized: "record.goal.calories", defaultValue: "Calories")
        }
    }
}

enum TrainingProfileSex: String, Codable, CaseIterable, Identifiable, Sendable {
    case female
    case male

    var id: Self { self }
    var title: String { self == .female ? String(localized: "Female") : String(localized: "Male") }
}

struct TrainingProfileDTO: Codable, Equatable, Sendable {
    let sexAtBirth: TrainingProfileSex?
    let birthDate: String?
    let heightCentimeters: Double?
    let weightKilograms: Double?
    let primaryMotivation: RunnerPrimaryMotivation
    let preferredRunGoalType: PreferredRunGoalType
}

struct TrainingProfileUpdateDTO: Encodable, Equatable, Sendable {
    let sexAtBirth: TrainingProfileSex?
    let birthDate: String?
    let heightCentimeters: Double?
    let weightKilograms: Double?
    let primaryMotivation: RunnerPrimaryMotivation
    let preferredRunGoalType: PreferredRunGoalType

    private enum CodingKeys: String, CodingKey {
        case sexAtBirth
        case birthDate
        case heightCentimeters
        case weightKilograms
        case primaryMotivation
        case preferredRunGoalType
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(sexAtBirth, forKey: .sexAtBirth)
        try container.encodeIfPresent(birthDate, forKey: .birthDate)
        try container.encodeIfPresent(heightCentimeters, forKey: .heightCentimeters)
        try container.encodeIfPresent(weightKilograms, forKey: .weightKilograms)
        try container.encode(primaryMotivation, forKey: .primaryMotivation)
        try container.encode(preferredRunGoalType, forKey: .preferredRunGoalType)

        if sexAtBirth == nil { try container.encodeNil(forKey: .sexAtBirth) }
        if birthDate == nil { try container.encodeNil(forKey: .birthDate) }
        if heightCentimeters == nil { try container.encodeNil(forKey: .heightCentimeters) }
        if weightKilograms == nil { try container.encodeNil(forKey: .weightKilograms) }
    }
}

struct PersonalizationMutationResponseDTO: Codable, Sendable {
    let accepted: Bool?
    let adjustment: AdjustmentProposalDTO?
    let personalization: PersonalizationSnapshotDTO
}

struct AdjustmentDecisionRequestDTO: Codable, Sendable {
    let decision: String
}

extension PersonalizationSnapshotDTO {
    static let preview = PersonalizationSnapshotDTO(
        contractVersion: 1,
        modelVersion: "runner-model-demo-1",
        generatedAt: Date(timeIntervalSince1970: 1_775_843_200),
        calibration: CalibrationSummaryDTO(
            status: .inProgress,
            completedSessionCount: 0,
            targetSessionCount: 3,
            currentSession: .comfortableRun
        ),
        calibrationWorkouts: [
            CalibrationWorkoutDTO(
                id: "calibration-comfortable-run",
                kind: .comfortableRun,
                title: "Comfortable run",
                purpose: "Learn your natural easy effort without testing your speed.",
                durationSeconds: 30 * 60,
                steps: [
                    CalibrationWorkoutStepDTO(id: "settle", label: "Settle in", durationSeconds: 5 * 60, detail: "Very easy"),
                    CalibrationWorkoutStepDTO(id: "main", label: "Run naturally", durationSeconds: 20 * 60, detail: "Conversational effort"),
                    CalibrationWorkoutStepDTO(id: "finish", label: "Easy finish", durationSeconds: 5 * 60, detail: "Ease down"),
                ]
            ),
        ],
        insights: [
            RunnerInsightDTO(
                id: "comfortable-duration",
                kind: .endurance,
                label: "Comfortable duration",
                value: "About 30 minutes",
                confidence: .low,
                evidenceCount: 1,
                lastUpdatedAt: Date(timeIntervalSince1970: 1_775_843_200)
            ),
        ],
        pendingAdjustment: nil
    )
}

struct WorkoutAdjustmentApplyRequestDTO: Codable, Equatable {
    let idempotencyKey: String
    let workoutId: String
    let suggestionId: String
    let validForDate: String
    let choice: ReadinessChoice
    let minutes: Int
    let note: String?
    var action: String? = nil
    var catalogWorkoutId: String? = nil
    var catalogVersion: Int? = nil
}

struct WorkoutAdjustmentApplyResponseDTO: Decodable {
    let accepted: Bool
}

// Manual edits are separate from readiness and adaptive proposals. The server owns capabilities and revisions.
struct WorkoutEditContextDTO: Codable, Equatable {
    let baseRevision: String
    let canEditTarget: Bool
    let canEditEffort: Bool
    let canConvertGoal: Bool
    let limitation: String?
    let minimumDurationSeconds: Int
    let maximumDurationSeconds: Int
    let minimumDistanceMeters: Double
    let maximumDistanceMeters: Double
    let effortPresets: [EffortPreset]
    let currentEffortPreset: String?
    struct EffortPreset: Codable, Equatable { let id: String; let min: Int; let max: Int }
}
struct WorkoutEditApplyRequestDTO: Codable, Equatable {
    var idempotencyKey: String
    let plannedWorkoutId: String?
    let suggestionId: String
    let validForDate: String
    let baseRevision: String
    let reason: String?
    let change: Change
    // Null is meaningful on this authenticated contract, so encode it explicitly.
    enum CodingKeys: String, CodingKey { case idempotencyKey, plannedWorkoutId, suggestionId, validForDate, baseRevision, reason, change }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(idempotencyKey, forKey: .idempotencyKey)
        try c.encode(plannedWorkoutId, forKey: .plannedWorkoutId)
        try c.encode(suggestionId, forKey: .suggestionId)
        try c.encode(validForDate, forKey: .validForDate)
        try c.encode(baseRevision, forKey: .baseRevision)
        try c.encode(reason, forKey: .reason)
        try c.encode(change, forKey: .change)
    }
    struct Change: Codable, Equatable {
        let operation: String
        var edits: Edits? = nil
        var catalogWorkoutId: String? = nil
        var catalogVersion: Int? = nil
    }
    struct Edits: Codable, Equatable {
        let target: Target?
        let effortPreset: String?
    }
    struct Target: Codable, Equatable {
        let kind: String
        var seconds: Int? = nil
        var meters: Double? = nil
    }
}
