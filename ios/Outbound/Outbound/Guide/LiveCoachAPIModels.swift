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
    case plannedCache = "planned_cache"
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
        let presentation: GuideVoicePresentation
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
    let measurementUnitSystem: String
    let sessionIntent: SessionIntentDTO
    let clientWorkout: ClientWorkoutDTO?
    let environment: EnvironmentDTO?
    let appDistributionHint = "global"

    struct SessionIntentDTO: Encodable {
        let activityType: String
        let goalType: String
    }

    struct ClientWorkoutDTO: Encodable {
        let title: String
        let detail: String
        let guideLine: String
        let targetDistanceMeters: Double?
        let targetDurationSeconds: Int?
        let steps: [StepDTO]
        let route: RouteDTO?

        struct StepDTO: Encodable {
            let label: String
            let durationSeconds: Int
            let detail: String?
            let phase: String?
            let targetPaceSecondsPerKilometer: Double?
        }

        struct RouteDTO: Encodable {
            let name: String?
            let shape: String?
            let direction: String?
            let distanceMeters: Double?
            let elevationGainMeters: Double?
            let approximateStartLatitude: Double?
            let approximateStartLongitude: Double?
            let approximateStartAltitudeMeters: Double?
        }
    }

    struct EnvironmentDTO: Encodable {
        let timeZoneIdentifier: String
        let indoor: Bool
        let approximateLocation: ApproximateLocationDTO?
        let weather: WeatherDTO?

        struct ApproximateLocationDTO: Encodable {
            let placeName: String?
            let latitude: Double?
            let longitude: Double?
            let altitudeMeters: Double?
        }

        struct WeatherDTO: Encodable {
            let observedAt: Date
            let condition: String
            let temperatureCelsius: Double
            let apparentTemperatureCelsius: Double
            let windKilometersPerHour: Double
            let precipitationChance: Double
            let impact: String
            let headline: String
            let guidance: String?
            let bestWindow: String?
        }
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
    let guidancePlan: LiveCoachGuidancePlanDTO
    let guidancePlanHash: String
    let planner: Planner

    struct Limits: Decodable {
        let cueValidityMilliseconds: Int
        let maximumDynamicCues: Int
    }


    struct Planner: Decodable {
        let status: String
        let model: String?
        let promptVersion: String
    }
}

struct LiveCoachGuidancePlanDTO: Decodable, Equatable {
    let contractVersion: Int
    let planVersion: String
    let locale: String
    let summary: String
    let progressPolicy: LiveCoachProgressPolicyDTO
    let cues: [Cue]

    struct Cue: Decodable, Equatable {
        let id: String
        let moment: String
        let phases: [String]
        let priority: String
        let cooldownSeconds: Int
        let phrases: [Phrase]
    }

    struct Phrase: Decodable, Equatable {
        let id: String
        let text: String
    }
}

struct LiveCoachProgressPolicyDTO: Decodable, Equatable {
    let announceEverySeconds: Int
    let announceEveryMeters: Double
    let includePace: Bool
}

struct LiveCoachCueRequest: Encodable {
    let contractVersion = 1
    let cueRequestId: UUID
    let moment: String
    let detectedAtElapsedSeconds: Int
    let validForMilliseconds: Int
    let selectedPhraseId: String?
    let liveState: LiveState

    struct LiveState: Encodable {
        let elapsedSeconds: Int
        let distanceMeters: Double
        let currentPaceSecondsPerKilometer: Double?
        let rollingPaceSecondsPerKilometer: Double?
        let targetPaceSecondsPerKilometer: Double?
        let gradePercent: Double?
        let workoutSegmentIndex: Int?
        let workoutSegmentPhase: String?
        let routeGuidanceActive: Bool
    }
}

struct LiveCoachCueStreamMetadata: Decodable {
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
    let timing: Timing

    struct Audio: Decodable {
        let contentType: String
        let codec: String
        let sampleRateHz: Double
        let channels: Int
    }

    struct Timing: Decodable {
        let serverReceivedAtUnixMilliseconds: Double
        let providerStartedAtUnixMilliseconds: Double?
    }
}

final class LiveCoachFirstAudioRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var firstAudioHandler: ((Date) -> Void)?
    private var firstAudioAt: Date?

    func setFirstAudioHandler(_ handler: @escaping (Date) -> Void) {
        lock.lock()
        firstAudioHandler = handler
        let alreadyReceived = firstAudioAt
        lock.unlock()
        if let alreadyReceived { handler(alreadyReceived) }
    }

    func reportFirstAudio(at date: Date) {
        lock.lock()
        guard firstAudioAt == nil else {
            lock.unlock()
            return
        }
        firstAudioAt = date
        let handler = firstAudioHandler
        lock.unlock()
        handler?(date)
    }

}

final class LiveCoachPCMStream: @unchecked Sendable, Equatable {
    let chunks: AsyncThrowingStream<Data, Error>
    let requestStartedAt: Date
    private let relay: LiveCoachFirstAudioRelay

    init(
        chunks: AsyncThrowingStream<Data, Error>,
        requestStartedAt: Date,
        relay: LiveCoachFirstAudioRelay
    ) {
        self.chunks = chunks
        self.requestStartedAt = requestStartedAt
        self.relay = relay
    }

    func setFirstAudioHandler(_ handler: @escaping (Date) -> Void) {
        relay.setFirstAudioHandler(handler)
    }

    static func == (lhs: LiveCoachPCMStream, rhs: LiveCoachPCMStream) -> Bool { lhs === rhs }
}

struct LiveCoachCueStreamResponse {
    let metadata: LiveCoachCueStreamMetadata
    let audioStream: LiveCoachPCMStream?
    let cachedAudioData: Data?
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
