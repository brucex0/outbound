import XCTest
@testable import OutboundSessionAnalysis

@MainActor
final class RuleBasedSessionAnalysisProviderTests: XCTestCase {
    func testSuggestsStrongerRhythmWhenPaceFallsBehindTarget() async throws {
        let provider = RuleBasedSessionAnalysisProvider()
        let request = SessionAnalysisRequest(
            profile: makeProfile(preferredPaceSecs: 300),
            snapshot: makeSnapshot(elapsedSeconds: 240, distanceMeters: 900, paceSecsPerKm: 330),
            recentSnapshots: []
        )

        let result = try await provider.analyze(request)

        XCTAssertEqual(result.urgency, .opportunity)
        XCTAssertEqual(result.providerID, provider.identifier)
        XCTAssertTrue(result.shouldSpeak)
        XCTAssertTrue(result.message.contains("stronger rhythm"))
    }

    func testSuggestsBackingOffWhenPaceIsAheadOfTarget() async throws {
        let provider = RuleBasedSessionAnalysisProvider()
        let request = SessionAnalysisRequest(
            profile: makeProfile(preferredPaceSecs: 330),
            snapshot: makeSnapshot(elapsedSeconds: 360, distanceMeters: 1200, paceSecsPerKm: 300),
            recentSnapshots: []
        )

        let result = try await provider.analyze(request)

        XCTAssertEqual(result.urgency, .opportunity)
        XCTAssertTrue(result.message.contains("Back off slightly"))
    }

    func testMarksHighHeartRateAsCaution() async throws {
        let provider = RuleBasedSessionAnalysisProvider()
        let request = SessionAnalysisRequest(
            profile: makeProfile(preferredPaceSecs: 300),
            snapshot: makeSnapshot(
                elapsedSeconds: 600,
                distanceMeters: 1800,
                paceSecsPerKm: 300,
                heartRate: 190
            ),
            recentSnapshots: []
        )

        let result = try await provider.analyze(request)

        XCTAssertEqual(result.urgency, .caution)
        XCTAssertTrue(result.message.contains("Heart rate is high"))
    }

    func testUsesRecentTrendWhenNoTargetPaceExists() async throws {
        let provider = RuleBasedSessionAnalysisProvider()
        let recentSnapshots = [
            makeSnapshot(elapsedSeconds: 60, distanceMeters: 150, paceSecsPerKm: 300),
            makeSnapshot(elapsedSeconds: 120, distanceMeters: 300, paceSecsPerKm: 305),
            makeSnapshot(elapsedSeconds: 180, distanceMeters: 420, paceSecsPerKm: 335),
            makeSnapshot(elapsedSeconds: 240, distanceMeters: 530, paceSecsPerKm: 350)
        ]
        let request = SessionAnalysisRequest(
            profile: makeProfile(preferredPaceSecs: nil),
            snapshot: recentSnapshots[3],
            recentSnapshots: recentSnapshots
        )

        let result = try await provider.analyze(request)

        XCTAssertEqual(result.urgency, .steady)
        XCTAssertTrue(result.message.contains("Cadence is drifting"))
    }
}
