import Foundation

struct HeartRateEffortConfiguration: Codable, Equatable, Sendable {
    let maximumHeartRate: Int
    let restingHeartRate: Int?

    /// Deterministic non-medical fallback used until a reliable personalized value exists.
    static let fallback = HeartRateEffortConfiguration(maximumHeartRate: 190, restingHeartRate: nil)

    init(maximumHeartRate: Int?, restingHeartRate: Int?) {
        self.maximumHeartRate = min(230, max(120, maximumHeartRate ?? 190))
        if let restingHeartRate, (30...120).contains(restingHeartRate) {
            self.restingHeartRate = restingHeartRate
        } else {
            self.restingHeartRate = nil
        }
    }
}

struct HeartRateEffortSnapshot: Codable, Equatable, Sendable {
    let currentBPM: Int?
    let currentZone: Int?
    let effort: PlainstrideHeartRateEffort
    let averageBPM: Int?
    let maximumBPM: Int?
    let sampleCount: Int
    let timeInZones: [PlainstrideZoneDuration]
    let lastSampleDate: Date?
}

/// Pure, deterministic time-weighted zone accumulator shared by live and saved summaries.
struct HeartRateEffortEngine: Codable, Equatable, Sendable {
    private(set) var configuration: HeartRateEffortConfiguration
    private(set) var sampleCount = 0
    private(set) var weightedBPMSeconds: Double = 0
    private(set) var weightedSeconds: TimeInterval = 0
    private(set) var maximumBPM: Int?
    private(set) var currentBPM: Int?
    private(set) var currentZone: Int?
    private(set) var lastSampleDate: Date?
    private var zoneSeconds = Array(repeating: TimeInterval.zero, count: 5)

    init(configuration: HeartRateEffortConfiguration = .fallback) {
        self.configuration = configuration
    }

    @discardableResult
    mutating func ingest(bpm: Int, sampledAt: Date) -> Bool {
        guard (30...240).contains(bpm) else { return false }
        if let lastSampleDate, sampledAt <= lastSampleDate { return false }

        if let previousDate = lastSampleDate,
           let previousBPM = currentBPM,
           let previousZone = currentZone {
            // Cap gaps so a removed watch is not interpreted as hours in one zone.
            let duration = min(15, max(0, sampledAt.timeIntervalSince(previousDate)))
            if duration > 0 {
                zoneSeconds[previousZone - 1] += duration
                weightedBPMSeconds += Double(previousBPM) * duration
                weightedSeconds += duration
            }
        }

        sampleCount += 1
        maximumBPM = max(maximumBPM ?? bpm, bpm)
        currentBPM = bpm
        currentZone = zone(for: bpm)
        lastSampleDate = sampledAt
        return true
    }

    mutating func close(at date: Date) {
        guard let previousDate = lastSampleDate,
              let previousBPM = currentBPM,
              let previousZone = currentZone,
              date > previousDate else { return }
        let duration = min(15, date.timeIntervalSince(previousDate))
        zoneSeconds[previousZone - 1] += duration
        weightedBPMSeconds += Double(previousBPM) * duration
        weightedSeconds += duration
        lastSampleDate = date
    }

    func zone(for bpm: Int) -> Int {
        let intensity: Double
        if let resting = configuration.restingHeartRate,
           configuration.maximumHeartRate > resting {
            intensity = Double(bpm - resting) / Double(configuration.maximumHeartRate - resting)
        } else {
            intensity = Double(bpm) / Double(configuration.maximumHeartRate)
        }
        return switch intensity {
        case ..<0.60: 1
        case ..<0.70: 2
        case ..<0.80: 3
        case ..<0.90: 4
        default: 5
        }
    }

    func bounds(for zone: Int) -> (lower: Int, upper: Int?) {
        let fractions: [(Double, Double?)] = [
            (0.50, 0.60), (0.60, 0.70), (0.70, 0.80), (0.80, 0.90), (0.90, nil)
        ]
        let index = min(4, max(0, zone - 1))
        let pair = fractions[index]
        if let resting = configuration.restingHeartRate {
            let reserve = configuration.maximumHeartRate - resting
            let lower = resting + Int((Double(reserve) * pair.0).rounded())
            let upper = pair.1.map { resting + Int((Double(reserve) * $0).rounded()) }
            return (lower, upper)
        }
        return (
            Int((Double(configuration.maximumHeartRate) * pair.0).rounded()),
            pair.1.map { Int((Double(configuration.maximumHeartRate) * $0).rounded()) }
        )
    }

    var snapshot: HeartRateEffortSnapshot {
        HeartRateEffortSnapshot(
            currentBPM: currentBPM,
            currentZone: currentZone,
            effort: Self.effort(for: currentZone),
            averageBPM: weightedSeconds > 0
                ? Int((weightedBPMSeconds / weightedSeconds).rounded())
                : currentBPM,
            maximumBPM: maximumBPM,
            sampleCount: sampleCount,
            timeInZones: zoneSeconds.enumerated().map {
                PlainstrideZoneDuration(zone: $0.offset + 1, seconds: $0.element)
            },
            lastSampleDate: lastSampleDate
        )
    }

    static func effort(for zone: Int?) -> PlainstrideHeartRateEffort {
        switch zone {
        case 1, 2: .easy
        case 3: .moderate
        case 4, 5: .hard
        default: .unavailable
        }
    }
}
