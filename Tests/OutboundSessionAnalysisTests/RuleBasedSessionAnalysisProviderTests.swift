import XCTest
@testable import OutboundSessionAnalysis

@MainActor
final class RuleBasedSessionAnalysisProviderTests: XCTestCase {
    func testSuggestsStrongerRhythmWhenPaceFallsBehindTarget() async throws {
        let provider = RuleBasedSessionAnalysisProvider()
        let request = SessionAnalysisRequest(
            profile: makeProfile(preferredPaceSecs: 300),
            persona: nil,
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
            persona: nil,
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
            persona: nil,
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
            persona: nil,
            snapshot: recentSnapshots[3],
            recentSnapshots: recentSnapshots
        )

        let result = try await provider.analyze(request)

        XCTAssertEqual(result.urgency, .steady)
        XCTAssertTrue(result.message.contains("Cadence is drifting"))
    }

    func testOpeningNudgeUsesSessionIntentGoal() async throws {
        let provider = RuleBasedSessionAnalysisProvider()
        let request = SessionAnalysisRequest(
            profile: makeProfile(preferredPaceSecs: nil),
            persona: nil,
            snapshot: makeSnapshot(elapsedSeconds: 30, distanceMeters: 120, paceSecsPerKm: 330),
            recentSnapshots: [],
            sessionIntent: SessionIntent(
                id: "tempo-5k",
                sport: .run,
                title: "5K Tempo",
                detail: "5 km • Tempo",
                coachLine: "Start controlled.",
                startLabel: "Start tempo",
                targetDistanceMeters: 5000
            )
        )

        let result = try await provider.analyze(request)

        XCTAssertTrue(result.message.contains("5K Tempo is underway"))
        XCTAssertTrue(result.message.contains("Goal is 5 kilometers"))
    }

    func testDistanceParserDoesNotTreatIntervalRepsAsSessionGoal() {
        XCTAssertNil(SessionIntentGoalParser.distanceMeters(from: "4 x 800m effort"))
        XCTAssertNil(SessionIntentGoalParser.distanceMeters(from: "6x100m strides"))
        XCTAssertEqual(SessionIntentGoalParser.distanceMeters(from: "5K Tempo"), 5000)
    }
}
