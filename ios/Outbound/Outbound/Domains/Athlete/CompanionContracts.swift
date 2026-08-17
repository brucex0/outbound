import Foundation

enum CompanionTask: String, Codable, Sendable {
    case answerTrainingQuestion = "answer_training_question"
    case adaptToday = "adapt_today"
    case prepareWeek = "prepare_week"
    case postRunReflection = "post_run_reflection"
    case liveGuidance = "live_guidance"
    case inspectMemory = "inspect_memory"
    case productHelp = "product_help"
}

enum CompanionSurface: String, Codable, Sendable {
    case assistant
    case today
    case postRun = "post_run"
    case weeklyReview = "weekly_review"
    case liveSession = "live_session"
    case memory
}

struct CompanionPriorMessageDTO: Codable, Sendable {
    let role: String
    let text: String
}

struct CompanionSituationalSignalDTO: Codable, Sendable {
    let idempotencyKey: String
    let type: String
    let value: String
    let source: String
    let confidence: Double
    let privacy: String
    let consequenceLevel: String
    let possibleEffects: [String]
    let scope: [String: String]
    let observedAt: Date
    let freshUntil: Date
}

struct CompanionTurnRequestDTO: Codable, Sendable {
    let task: CompanionTask
    let surface: CompanionSurface
    let prompt: String
    let conversationKey: String
    let recentMessages: [CompanionPriorMessageDTO]
    let currentEntityIds: [String]
    let clientCapabilities: [String]
    let isOffline: Bool
    let timeZoneIdentifier: String?
    let signals: [CompanionSituationalSignalDTO]
}

struct CompanionActionDTO: Codable, Identifiable, Sendable {
    let id: String
    let actionType: String
    let permissionTier: Int
    let requiresConfirmation: Bool
    let status: String
    let explanation: String
}

struct CompanionConfirmationDTO: Codable, Sendable {
    let actionId: String
    let title: String
    let explanation: String
    let acceptLabel: String
    let rejectLabel: String
}

struct CompanionContextReceiptDTO: Codable, Sendable {
    let manifestId: String
    let task: CompanionTask
    let tokenBudget: Int
    let estimatedTokens: Int
    let includedReferenceCount: Int
}

struct CompanionTurnResponseDTO: Codable, Sendable {
    let message: String
    let locale: String?
    let action: CompanionActionDTO?
    let confirmationRequest: CompanionConfirmationDTO?
    let suggestedReplies: [String]
    let runnerModelVersion: String
    let contextReceipt: CompanionContextReceiptDTO
}

struct CompanionActionDecisionRequestDTO: Codable, Sendable {
    let decision: String
}

struct CompanionActionDecisionResponseDTO: Codable, Sendable {
    let action: CompanionDecidedActionDTO
}

struct CompanionDecidedActionDTO: Codable, Sendable {
    let id: String
    let status: String
    let explanation: String
}

struct CompanionMemoryDTO: Codable, Identifiable, Sendable {
    var id: String { stableKey }
    let stableKey: String
    let kind: String
    let label: String
    let summary: String
    let confidence: Double
    let status: String
    let source: String
    let evidenceCount: Int
    let contradictionCount: Int
    let sensitivity: String
    let consequenceLevel: String
    let refreshedAt: Date
    let expiresAt: Date?
}

struct CompanionMemoriesResponseDTO: Codable, Sendable {
    let memories: [CompanionMemoryDTO]
}

struct CompanionMemoryCorrectionRequestDTO: Codable, Sendable {
    let value: String
    let summary: String
    let label: String?
    let idempotencyKey: String
}

struct CompanionMemoryCorrectionResponseDTO: Codable, Sendable {
    let memory: CompanionMemoryDTO
}

struct CompanionMemoryForgetRequestDTO: Codable, Sendable {
    let idempotencyKey: String
}

struct CompanionMemoryForgetResponseDTO: Codable, Sendable {
    let forgotten: Bool
}

struct CompanionSessionBriefDTO: Codable, Sendable {
    let version: Int
    let runnerModelVersion: String
    let workout: CompanionSessionWorkoutDTO?
    let readiness: CompanionSessionReadinessDTO?
    let guidancePriorities: [String]
    let cuePreferences: [String]
    let forbiddenBehavior: [String]
}

struct CompanionSessionWorkoutDTO: Codable, Sendable {
    let id: String
    let title: String
    let purpose: String
    let durationSeconds: Int
}

struct CompanionSessionReadinessDTO: Codable, Sendable {
    let choice: String?
    let energy: Int
    let soreness: Int
    let illnessOrPain: Bool
}
