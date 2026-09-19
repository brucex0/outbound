import Foundation

enum PlainstrideWorkoutActivity: String, Codable, CaseIterable, Sendable {
    case running
    case walking
    case cycling
    case hiking
    case swimming
    case strength
    case mobility
}

enum PlainstrideWorkoutOrigin: String, Codable, Sendable {
    case iPhone = "iphone"
    case appleWatch = "apple_watch"
}

enum PlainstrideWorkoutDevice: String, Codable, Sendable {
    case iPhone = "iphone"
    case appleWatch = "apple_watch"
}

enum PlainstrideWorkoutLifecycle: String, Codable, Sendable {
    case preparing
    case ready
    case active
    case paused
    case finishing
    case finished
    case recovering
    case failed
}

enum PlainstrideWorkoutConnection: String, Codable, Sendable {
    case connecting
    case connected
    case disconnected
    case unavailable
}

enum PlainstrideHeartRateEffort: String, Codable, Sendable {
    case unavailable
    case easy
    case moderate
    case hard
}

struct PlainstrideWorkoutIdentity: Codable, Equatable, Sendable {
    let activity: PlainstrideWorkoutActivity
    let isIndoor: Bool
    let origin: PlainstrideWorkoutOrigin
    let canonicalStartDate: Date?

    /// Optional `With dog` context configured on the phone. Optional and
    /// raw-encoded so older watch/phone builds ignore the field safely.
    var companionType: String? = nil
}

struct PlainstrideZoneDuration: Codable, Equatable, Sendable {
    let zone: Int
    let seconds: TimeInterval
}

struct PlainstrideLiveMetrics: Codable, Equatable, Sendable {
    let currentBPM: Int?
    let sampledAt: Date?
    let averageBPM: Int?
    let maximumBPM: Int?
    let currentZone: Int?
    let effort: PlainstrideHeartRateEffort
    let timeInZones: [PlainstrideZoneDuration]
    let elapsedTime: TimeInterval
    let distanceMeters: Double?
    let activeEnergyKilocalories: Double?
}

struct PlainstrideFinalWorkoutMetrics: Codable, Equatable, Sendable {
    let averageBPM: Int?
    let maximumBPM: Int?
    let timeInZones: [PlainstrideZoneDuration]
    let elapsedTime: TimeInterval
    let distanceMeters: Double?
    let activeEnergyKilocalories: Double?
}

enum PlainstrideWorkoutMessageKind: String, Codable, Sendable {
    case handshake
    case sessionIdentity
    case startReadiness
    case liveMetrics
    case pause
    case resume
    case finishRequest
    case finalMetrics
    case savedWorkout
    case recoverableError
    case connectionState
    case lifecycleState
}

/// Versioned, privacy-minimal payload sent only through HealthKit workout mirroring.
/// Every message carries ordering and identity fields so duplicates and stale data are harmless.
struct PlainstrideWorkoutMessage: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let sessionUUID: UUID
    let sequenceNumber: UInt64
    let eventTimestamp: Date
    let originDevice: PlainstrideWorkoutDevice
    let kind: PlainstrideWorkoutMessageKind
    let identity: PlainstrideWorkoutIdentity?
    let metrics: PlainstrideLiveMetrics?
    let finalMetrics: PlainstrideFinalWorkoutMetrics?
    let lifecycle: PlainstrideWorkoutLifecycle?
    let connection: PlainstrideWorkoutConnection?
    let externalWorkoutReference: String?
    let errorCategory: String?

    init(
        sessionUUID: UUID,
        sequenceNumber: UInt64,
        originDevice: PlainstrideWorkoutDevice,
        kind: PlainstrideWorkoutMessageKind,
        identity: PlainstrideWorkoutIdentity? = nil,
        metrics: PlainstrideLiveMetrics? = nil,
        finalMetrics: PlainstrideFinalWorkoutMetrics? = nil,
        lifecycle: PlainstrideWorkoutLifecycle? = nil,
        connection: PlainstrideWorkoutConnection? = nil,
        externalWorkoutReference: String? = nil,
        errorCategory: String? = nil,
        eventTimestamp: Date = Date()
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.sessionUUID = sessionUUID
        self.sequenceNumber = sequenceNumber
        self.eventTimestamp = eventTimestamp
        self.originDevice = originDevice
        self.kind = kind
        self.identity = identity
        self.metrics = metrics
        self.finalMetrics = finalMetrics
        self.lifecycle = lifecycle
        self.connection = connection
        self.externalWorkoutReference = externalWorkoutReference
        self.errorCategory = errorCategory
    }
}

enum PlainstrideWorkoutCodec {
    static func encode(_ message: PlainstrideWorkoutMessage) throws -> Data {
        try JSONEncoder().encode(message)
    }

    static func decode(_ data: Data) throws -> PlainstrideWorkoutMessage {
        let message = try JSONDecoder().decode(PlainstrideWorkoutMessage.self, from: data)
        guard message.schemaVersion == PlainstrideWorkoutMessage.currentSchemaVersion else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: "Unsupported workout message schema"
            ))
        }
        return message
    }
}
