import Foundation
import Testing
@testable import Outbound

@MainActor
struct SuddenSpeedChangeDetectorTests {
    @Test(arguments: [1, -1])
    func sustainedChangeTriggersAfterPersistence(direction: Int) {
        var detector = SuddenSpeedChangeDetector()
        let alerts = replay(&detector, through: 60) { second in
            second < 30 ? (direction > 0 ? 2.5 : 4.5) : (direction > 0 ? 4.5 : 2.5)
        }
        #expect(alerts.map(\.direction) == [direction])
        #expect(alerts.map(\.second) == [37])
    }

    @Test func distinctFixesWithinOneSecondPreserveHistory() {
        var detector = SuddenSpeedChangeDetector()
        var alerts: [Int] = []
        for second in 0...60 {
            for fraction in [0.0, 0.2] {
                if let direction = detector.ingest(
                    second: second, evidence: Double(second) + fraction,
                    speed: second < 30 ? 2.5 : 4.5,
                    segmentID: nil, phase: nil, segmentSeconds: nil
                ) { alerts.append(direction) }
            }
        }
        #expect(alerts == [1])
    }

    @Test func repeatedFixDoesNotCountAsFreshEvidence() {
        var detector = SuddenSpeedChangeDetector()
        _ = replay(&detector, through: 29) { _ in 2.5 }
        let alerts = (30...60).compactMap { second in
            detector.ingest(second: second, evidence: 29, speed: 4.5,
                            segmentID: nil, phase: nil, segmentSeconds: nil)
        }
        #expect(alerts.isEmpty)
    }

    @Test(arguments: ["steady", "spike", "short_change", "rapid_alternation"])
    func rejectsUnsustainedChanges(scenario: String) {
        var detector = SuddenSpeedChangeDetector()
        let alerts = replay(&detector, through: 60) { second in
            switch scenario {
            case "spike": return second == 30 ? 4.5 : 2.5
            case "short_change": return (30...33).contains(second) ? 4.5 : 2.5
            case "rapid_alternation": return second >= 30 && second.isMultiple(of: 2) ? 4.5 : 2.5
            default: return 2.5
            }
        }
        #expect(alerts.isEmpty)
    }

    @Test(arguments: [(4.0, 5.2), (1.5, 2.2), (0.9, 4.5)])
    func requiresBothThresholdsAndMovingBaseline(speeds: (Double, Double)) {
        var detector = SuddenSpeedChangeDetector()
        #expect(replay(&detector, through: 60) { $0 < 30 ? speeds.0 : speeds.1 }.isEmpty)
    }

    @Test func walkingToFastRunningTriggersIncrease() {
        var detector = SuddenSpeedChangeDetector()
        #expect(replay(&detector, through: 60) { $0 < 30 ? 4 / 3.6 : 19 / 3.6 }.map(\.direction) == [1])
    }

    @Test func walkingToStoppedDoesNotTriggerRunningSlowdown() {
        var detector = SuddenSpeedChangeDetector()
        #expect(replay(&detector, through: 60) { $0 < 30 ? 4 / 3.6 : 0 }.isEmpty)
    }

    @Test(arguments: [Double.nan, Double.infinity, -1, 16])
    func invalidSpeedClearsPendingEvidence(speed: Double) {
        var detector = SuddenSpeedChangeDetector()
        #expect(replay(&detector, through: 35) { $0 < 30 ? 2.5 : 4.5 }.isEmpty)
        #expect(detector.ingest(second: 36, evidence: 36, speed: speed,
                                segmentID: nil, phase: nil, segmentSeconds: nil) == nil)
        #expect(replay(&detector, from: 37, through: 65) { _ in 4.5 }.isEmpty)
    }

    @Test(arguments: ["gap", "reverse_evidence", "reverse_clock", "pause", "segment", "missing"])
    func discontinuityClearsPendingEvidence(reason: String) {
        var detector = SuddenSpeedChangeDetector()
        #expect(replay(&detector, through: 35) { $0 < 30 ? 2.5 : 4.5 }.isEmpty)
        switch reason {
        case "pause": detector.resetEvidence()
        case "gap":
            #expect(detector.ingest(second: 42, evidence: 42, speed: 4.5,
                                    segmentID: nil, phase: nil, segmentSeconds: nil) == nil)
        default:
            #expect(detector.ingest(
                second: reason == "reverse_clock" ? 34 : 36,
                evidence: reason == "missing" ? nil : (reason == "reverse_evidence" ? 34 : 36),
                speed: 4.5, segmentID: reason == "segment" ? "new" : nil,
                phase: nil, segmentSeconds: nil
            ) == nil)
        }
        let nextSecond = reason == "gap" ? 43 : (reason == "pause" ? 36 : 37)
        #expect(replay(&detector, from: nextSecond, through: 70,
                      segmentID: reason == "segment" ? "new" : nil) { _ in 4.5 }.isEmpty)
    }

    @Test(arguments: ["warmup", "recovery", "cooldown", "walk"])
    func easyPhasesSuppressSlowdowns(phase: String) {
        var detector = SuddenSpeedChangeDetector()
        var alerts: [Int] = []
        for second in 0...80 {
            if let result = detector.ingest(second: second, evidence: Double(second),
                speed: second < 40 ? 4.5 : 2.5,
                segmentID: "step", phase: phase, segmentSeconds: second) { alerts.append(result) }
        }
        #expect(alerts.isEmpty)
    }

    @Test func segmentStartupSuppressesOtherwiseQualifyingChange() {
        var detector = SuddenSpeedChangeDetector()
        for second in 0...29 {
            #expect(detector.ingest(second: second, evidence: Double(second),
                speed: second < 20 ? 2.5 : 4.5,
                segmentID: "step", phase: "work", segmentSeconds: second) == nil)
        }
    }

    @Test func cooldownDiscardsOldChangesAndAllowsNewChange() {
        var detector = SuddenSpeedChangeDetector()
        let alerts = replay(&detector, through: 140) { second in
            switch second {
            case ..<30: return 2.5
            case 30..<60: return 4.5
            case 60..<120: return 2.5 // Change during cooldown must not surface later.
            default: return 4.5
            }
        }
        #expect(alerts.map(\.direction) == [1, 1])
        #expect(alerts.map(\.second) == [37, 127])
    }

    @Test func gradualSpeedProgressionDoesNotUseAnOldBaseline() {
        var detector = SuddenSpeedChangeDetector()
        #expect(replay(&detector, through: 600) { 2.5 + Double($0) * 0.003 }.isEmpty)
    }

    private func replay(
        _ detector: inout SuddenSpeedChangeDetector, from start: Int = 0,
        through end: Int, segmentID: String? = nil, speed: (Int) -> Double
    ) -> [(second: Int, direction: Int)] {
        (start...end).compactMap { second in
            detector.ingest(second: second, evidence: Double(second), speed: speed(second),
                segmentID: segmentID, phase: nil, segmentSeconds: nil).map { (second, $0) }
        }
    }
}
