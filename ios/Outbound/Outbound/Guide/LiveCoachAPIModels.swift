import Foundation

enum LiveCoachAudioMode: String, Codable, Equatable {
    case disabled
    case fixedOnly = "fixed_only"
    case dynamic
}

enum LiveCoachAccessReason: String, Codable, Equatable {
    case openBeta = "open_beta"
    case verifiedSubscription = "verified_subscription"
    case promotion
    case entitlementRequired = "entitlement_required"
    case quotaExhausted = "quota_exhausted"
    case featureDisabled = "feature_disabled"
}

enum LiveCoachCueSource: String, Codable, Equatable {
    case dynamicGeneration = "dynamic_generation"
    case fixedPack = "fixed_pack"
    case cachedFallback = "cached_fallback"
}

enum LiveCoachCueResult: String, Codable, Equatable {
    case success
    case offline
    case timeout
    case stale
    case invalid
    case unavailable
    case featureDisabled = "feature_disabled"
    case entitlementRequired = "entitlement_required"
    case quotaExhausted = "quota_exhausted"
    case budgetExhausted = "budget_exhausted"
}

enum LiveCoachLatencyBucket: String, Equatable {
    case underOneSecond = "under_1s"
    case oneToTwoSeconds = "1s_2s"
    case twoToFourSeconds = "2s_4s"
    case fourSecondsPlus = "4s_plus"

    init(seconds: TimeInterval) {
        switch seconds {
        case ..<1: self = .underOneSecond
        case ..<2: self = .oneToTwoSeconds
        case ..<4: self = .twoToFourSeconds
        default: self = .fourSecondsPlus
        }
    }
}

struct LiveCoachAccessDTO: Codable, Equatable {
    let dynamicCoaching: String
    let reason: LiveCoachAccessReason
    let paywallAvailable: Bool
}

struct LiveCoachConfigDTO: Codable, Equatable {
    let contractVersion: Int
    let configVersion: String
    let mode: LiveCoachAudioMode
    let catalogVersion: String
    let access: LiveCoachAccessDTO
}

struct LiveCoachCatalogDTO: Codable, Equatable {
    let contractVersion: Int
    let catalogVersion: String
    let coachPersonas: [CoachPersonaDTO]
    let voices: [VoiceProfileDTO]
    let audioPack: LiveCoachAudioPackDTO?

    struct CoachPersonaDTO: Codable, Equatable, Identifiable {
        let id: String
        let displayName: String
        let description: String
        let defaultVoiceProfileId: String
        let allowedVoiceProfileIds: [String]
        let fixedScriptStyleId: String
        let access: String
    }

    struct VoiceProfileDTO: Codable, Equatable, Identifiable {
        let id: String
        let displayName: String
        let description: String
        let style: String
        let previewAssetId: String
    }
}

struct LiveCoachAudioPackDTO: Codable, Equatable {
    let manifestVersion: String
    let manifestUrl: URL
}

struct CreateLiveCoachSessionRequest: Encodable {
    let contractVersion = 1
    let clientSessionId: UUID
    let workoutId: String?
    let locale: String
    let coachPersonaId: String
    let voiceProfileId: String
    let coachingContract: String
    let sessionIntent: SessionIntentDTO
    let appDistributionHint = "global"

    struct SessionIntentDTO: Encodable {
        let activityType: String
        let goalType: String
    }
}

struct CreateLiveCoachSessionResponse: Decodable {
    let contractVersion: Int
    let sessionId: String
    let contextVersion: Int
    let expiresAt: Date
    let effectiveMode: LiveCoachAudioMode
    let dynamicCoachingAvailable: Bool
    let access: LiveCoachAccessDTO
    let audioPack: LiveCoachAudioPackDTO
    let limits: Limits

    struct Limits: Decodable {
        let cueValidityMilliseconds: Int
        let maximumDynamicCues: Int
    }
}

struct LiveCoachCueRequest: Encodable {
    let contractVersion = 1
    let cueRequestId: UUID
    let moment: String
    let detectedAtElapsedSeconds: Int
    let validForMilliseconds: Int
    let liveState: LiveState

    struct LiveState: Encodable {
        let elapsedSeconds: Int
        let distanceMeters: Double
        let currentPaceSecondsPerKilometer: Double?
        let rollingPaceSecondsPerKilometer: Double?
        let targetPaceSecondsPerKilometer: Double?
        let workoutSegmentIndex: Int?
        let workoutSegmentPhase: String?
        let routeGuidanceActive: Bool
    }
}

struct LiveCoachCueResponse: Decodable {
    let contractVersion: Int
    let cueRequestId: UUID
    let source: LiveCoachCueSource
    let result: LiveCoachCueResult
    let moment: String
    let urgency: String
    let transcript: String
    let fixedCueKey: String?
    let audio: Audio?
    let generatedAt: Date
    let expiresAt: Date

    struct Audio: Decodable {
        let contentType: String
        let base64: String
        let durationMilliseconds: Int
    }
}

struct EndLiveCoachSessionRequest: Encodable {
    let contractVersion = 1
    let spokenCueCount: Int
    let helpfulCueCount: Int
    let outcome: String
}

struct EndLiveCoachSessionResponse: Decodable {
    let contractVersion: Int
    let ended: Bool
}
