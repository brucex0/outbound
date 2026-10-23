import Foundation

/// Uses distinct trusted GPS speeds, independently of profile and rolling display pace.
struct SuddenSpeedChangeDetector {
    private struct Sample { let second: Int; let evidence: Double; let speed: Double }
    private var samples: [Sample] = []
    private var baseline: Double?
    private var stableReference: (speed: Double, observedAt: Int)?
    private var candidateSince: Int?
    private var candidateDirection: Int?
    private var lastAlert: Int?
    private var segment: String?

    mutating func resetEvidence() { samples = []; baseline = nil; stableReference = nil; candidateSince = nil; candidateDirection = nil }
    mutating func ingest(second: Int, evidence: Double?, speed: Double?, segmentID: String?, phase: String?, segmentSeconds: Int?) -> Int? {
        if segment != segmentID { resetEvidence(); segment = segmentID }
        guard let evidence, let speed, speed.isFinite, speed >= 0, speed <= 15 else { resetEvidence(); return nil }
        if let last = samples.last {
            if evidence == last.evidence { return nil }
            if evidence < last.evidence || evidence - last.evidence > 5 || second < last.second || second - last.second > 5 { resetEvidence() }
        }
        // Location delivery and the UI timer can publish distinct fixes within
        // one active second. Keep the latest without discarding the baseline or
        // counting extra fixes toward the duration/coverage requirements.
        if samples.last?.second == second { samples.removeLast() }
        samples.append(Sample(second: second, evidence: evidence, speed: speed))
        samples.removeAll { $0.second < second - 25 }
        guard segmentSeconds.map({ $0 >= 30 }) ?? true else { baseline = nil; candidateSince = nil; return nil }
        if lastAlert.map({ second - $0 < 60 }) ?? false {
            baseline = nil; candidateSince = nil; candidateDirection = nil; return nil
        }
        let recent = samples.filter { $0.second >= second - 4 }
        guard recent.count >= 4, let first = recent.first, second - first.second >= 3 else { return nil }
        func median(_ values: [Double]) -> Double { let s = values.sorted(); return (s[(s.count - 1)/2] + s[s.count/2])/2 }
        let current = median(recent.map(\.speed))
        let reference: Double
        if let baseline { reference = baseline } else {
            let earlier = samples.filter { $0.second >= second - 24 && $0.second <= second - 5 }
            if earlier.count >= 8, let start = earlier.first, let end = earlier.last,
               end.second - start.second >= 14 {
                let established = median(earlier.map(\.speed))
                if established >= 1.5,
                   earlier.allSatisfy({ abs($0.speed - established) <= established * 0.2 }) {
                    stableReference = (established, second)
                }
            }
            // A ramp can disrupt the earlier window before crossing the alert
            // threshold. Briefly retain its trusted reference so incremental
            // speed changes cannot erase the very baseline they depart from.
            guard let stableReference, second - stableReference.observedAt <= 15 else { return nil }
            reference = stableReference.speed
        }
        let delta = current - reference
        let direction = delta > 0 ? 1 : -1
        guard abs(delta) >= max(reference * 0.4, 3.0 / 3.6),
              !(direction < 0 && ["warmup", "recovery", "cooldown", "walk"].contains(phase ?? "")) else {
            baseline = nil; candidateSince = nil; candidateDirection = nil; return nil
        }
        if candidateDirection != direction { baseline = reference; candidateSince = second; candidateDirection = direction }
        guard let since = candidateSince, second - since >= 5 else { return nil }
        guard lastAlert.map({ second - $0 >= 60 }) ?? true else { return nil }
        lastAlert = second
        resetEvidence()
        return direction
    }
}
