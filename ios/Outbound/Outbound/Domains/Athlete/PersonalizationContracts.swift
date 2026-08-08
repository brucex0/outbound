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
    let coachingDetail: String
    let constraints: [String: String]
    let complete: Bool
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
