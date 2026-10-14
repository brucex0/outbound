import Foundation

/// Sensor cadence is total footfalls (both feet), never inferred from GPS speed.
nonisolated struct RunningCadenceReading {
    let stepsPerMinute: Double
    let measuredAt: Date
}

/// Persists measured coverage rather than treating missing readings as zero.
nonisolated struct RunningCadenceTracker: Codable, Sendable {
    private(set) var samples: [ActivityCadenceSample] = []
    private var weightedTotal = 0.0
    private var measuredSeconds = 0.0
    private var maximum = 0
    private var segment = 0
    private var segmentStartedAt = Date.distantPast
    private var lastMeasuredAt: Date?
    private var lastElapsedSeconds: Int?
    private var recent: [Measurement] = []
    private(set) var currentStepsPerMinute: Int?

    private struct Measurement: Codable {
        let date: Date
        let value: Double
    }

    mutating func beginSegment(at date: Date) {
        segment += 1
        segmentStartedAt = date
        lastMeasuredAt = nil
        lastElapsedSeconds = nil
        recent = []
        currentStepsPerMinute = nil
    }

    mutating func suspend() {
        lastElapsedSeconds = nil
        recent = []
        currentStepsPerMinute = nil
    }

    mutating func update(reading: RunningCadenceReading?, elapsedSeconds: Int, now: Date) {
        guard let reading,
              reading.measuredAt >= segmentStartedAt,
              now.timeIntervalSince(reading.measuredAt) >= -1,
              now.timeIntervalSince(reading.measuredAt) <= 10,
              reading.stepsPerMinute.isFinite,
              reading.stepsPerMinute > 0,
              reading.stepsPerMinute <= 300
        else {
            suspend()
            return
        }
        guard lastMeasuredAt.map({ reading.measuredAt > $0 }) ?? true else { return }
        // Break the plotted line across signal gaps, as well as pauses.
        if let lastMeasuredAt, reading.measuredAt.timeIntervalSince(lastMeasuredAt) > 10 {
            segment += 1
            recent = []
            lastElapsedSeconds = nil
        }
        recent.removeAll { reading.measuredAt.timeIntervalSince($0.date) > 5 }
        recent.append(Measurement(date: reading.measuredAt, value: reading.stepsPerMinute))
        let smoothed = Int((recent.reduce(0) { $0 + $1.value } / Double(recent.count)).rounded())
        currentStepsPerMinute = smoothed
        let coverage = lastElapsedSeconds.map { min(10, max(0, elapsedSeconds - $0)) }
            ?? min(1, max(0, elapsedSeconds))
        weightedTotal += reading.stepsPerMinute * Double(coverage)
        measuredSeconds += Double(coverage)
        maximum = max(maximum, Int(reading.stepsPerMinute.rounded()))
        lastMeasuredAt = reading.measuredAt
        lastElapsedSeconds = elapsedSeconds
        // Keep the saved series compact: at most one point per five active seconds.
        if let last = samples.last, last.segment == segment, elapsedSeconds - last.elapsedSeconds < 5 {
            return
        }
        samples.append(ActivityCadenceSample(
            elapsedSeconds: elapsedSeconds, stepsPerMinute: smoothed, segment: segment
        ))
    }

    var summary: ActivityCadenceSummary? {
        guard measuredSeconds > 0 else { return nil }
        return ActivityCadenceSummary(
            averageStepsPerMinute: Int((weightedTotal / measuredSeconds).rounded()),
            maxStepsPerMinute: maximum,
            samples: samples
        )
    }
}
