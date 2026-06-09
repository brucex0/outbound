import XCTest
@testable import OutboundSessionAnalysis

@MainActor
final class VirtualCoachTests: XCTestCase {
    func testIngestWaitsForInitialThresholdBeforeAnalyzing() async throws {
        let provider = FakeSessionAnalysisProvider()
        let coach = VirtualCoach(provider: provider)
        coach.activate(with: nil)

        coach.ingest(makeSnapshot(elapsedSeconds: 19, distanceMeters: 80, paceSecsPerKm: 320))
        try await waitForMainActor()

        XCTAssertNil(coach.latestAnalysis)
        XCTAssertEqual(provider.requests.count, 0)

        coach.ingest(makeSnapshot(elapsedSeconds: 20, distanceMeters: 90, paceSecsPerKm: 320))
        try await waitUntil { coach.latestAnalysis != nil }

        XCTAssertEqual(provider.requests.count, 1)
        XCTAssertEqual(coach.providerName, provider.displayName)
        XCTAssertEqual(coach.lastNudge, "Hold steady.")
        XCTAssertEqual(coach.latestAnalysis?.providerID, provider.identifier)

        coach.deactivate()
    }

    func testIngestRespectsAnalysisInterval() async throws {
        let provider = FakeSessionAnalysisProvider()
        let coach = VirtualCoach(provider: provider)
        coach.activate(with: nil)

        coach.ingest(makeSnapshot(elapsedSeconds: 20, distanceMeters: 90, paceSecsPerKm: 320))
        try await waitUntil { provider.requests.count == 1 }

        coach.ingest(makeSnapshot(elapsedSeconds: 94, distanceMeters: 400, paceSecsPerKm: 320))
        try await waitForMainActor()
        XCTAssertEqual(provider.requests.count, 1)

        coach.ingest(makeSnapshot(elapsedSeconds: 95, distanceMeters: 410, paceSecsPerKm: 320))
        try await waitUntil { provider.requests.count == 2 }

        coach.deactivate()
    }

    func testFallsBackWhenPrimaryProviderThrows() async throws {
        let provider = FakeSessionAnalysisProvider(error: TestError.primaryFailed)
        let coach = VirtualCoach(provider: provider)
        coach.activate(with: makeProfile(preferredPaceSecs: 300))

        coach.ingest(makeSnapshot(elapsedSeconds: 20, distanceMeters: 100, paceSecsPerKm: 330))
        try await waitUntil { coach.latestAnalysis != nil }

        XCTAssertEqual(provider.requests.count, 1)
        XCTAssertEqual(coach.latestAnalysis?.providerID, "rule-based-session-analyzer")
        XCTAssertTrue(coach.lastNudge.contains("stronger rhythm"))

        coach.deactivate()
    }

    func testSpokenAnalysisDoesNotAlwaysPrefixProgressStats() async throws {
        let provider = FakeSessionAnalysisProvider(shouldSpeak: true)
        let coach = VirtualCoach(provider: provider, speechEnabled: false)
        coach.activate(with: nil)

        coach.ingest(makeSnapshot(elapsedSeconds: 20, distanceMeters: 90, paceSecsPerKm: 320))
        try await waitUntil { coach.latestAnalysis != nil }

        XCTAssertEqual(coach.lastNudge, "Hold steady.")
        XCTAssertEqual(coach.lastSpokenAnnouncement, "Hold steady.")

        coach.deactivate()
    }

    func testProgressMomentKeepsProgressContext() async throws {
        let provider = FakeSessionAnalysisProvider(shouldSpeak: true)
        let coach = VirtualCoach(provider: provider, speechEnabled: false)
        coach.activate(with: nil)

        coach.ingest(makeSnapshot(elapsedSeconds: 180, distanceMeters: 1_000, paceSecsPerKm: 320))
        try await waitUntil { coach.latestAnalysis != nil }

        XCTAssertTrue(coach.lastSpokenAnnouncement.contains("3 minutes in."))
        XCTAssertTrue(coach.lastSpokenAnnouncement.contains("1 kilometer."))
        XCTAssertTrue(coach.lastSpokenAnnouncement.contains("Hold steady."))

        coach.deactivate()
    }

    func testEarlyProgressAnnouncementSpeaksMetersNotFirstKilometer() async throws {
        let provider = FakeSessionAnalysisProvider(shouldSpeak: false)
        let coach = VirtualCoach(provider: provider, speechEnabled: false)
        coach.activate(with: nil)

        coach.ingest(makeSnapshot(elapsedSeconds: 180, distanceMeters: 20, paceSecsPerKm: 320))
        try await waitForMainActor()

        XCTAssertTrue(coach.lastSpokenAnnouncement.contains("20 meters."))
        XCTAssertFalse(coach.lastSpokenAnnouncement.localizedCaseInsensitiveContains("kilometer"))

        coach.deactivate()
    }

    func testDistanceProgressMilestoneWaitsForRawKilometerBeforeAnnouncing() async throws {
        let provider = FakeSessionAnalysisProvider(shouldSpeak: false)
        let coach = VirtualCoach(provider: provider, speechEnabled: false)
        coach.activate(with: nil)

        coach.ingest(makeSnapshot(elapsedSeconds: 60, distanceMeters: 999, paceSecsPerKm: 320))
        try await waitForMainActor()
        XCTAssertEqual(coach.lastSpokenAnnouncement, "")

        coach.ingest(makeSnapshot(elapsedSeconds: 61, distanceMeters: 1_000, paceSecsPerKm: 320))
        try await waitForMainActor()
        XCTAssertTrue(coach.lastSpokenAnnouncement.contains("1 kilometer."))

        coach.deactivate()
    }

    func testDistanceGoalSpeaksHalfwayAndLastMileMilestones() async throws {
        let provider = FakeSessionAnalysisProvider(shouldSpeak: false)
        let coach = VirtualCoach(provider: provider, speechEnabled: false)
        coach.activate(with: nil, sessionIntent: SessionIntent(
            id: "three-mile-run",
            sport: .run,
            title: "3 mile run",
            detail: "Run • 3 miles",
            coachLine: "Settle in.",
            startLabel: "Start",
            targetDistanceMeters: 3 * 1_609.344
        ))

        coach.ingest(makeSnapshot(elapsedSeconds: 300, distanceMeters: 2_500, paceSecsPerKm: 320))
        try await waitForMainActor()
        XCTAssertTrue(coach.lastSpokenAnnouncement.contains("Halfway through your distance goal."))

        coach.ingest(makeSnapshot(elapsedSeconds: 360, distanceMeters: 3_300, paceSecsPerKm: 320))
        try await waitForMainActor()
        XCTAssertTrue(coach.lastSpokenAnnouncement.contains("Last mile"))

        coach.deactivate()
    }

    func testTimeGoalSpeaksHalfwayAndLastMinuteMilestones() async throws {
        let provider = FakeSessionAnalysisProvider(shouldSpeak: false)
        let coach = VirtualCoach(provider: provider, speechEnabled: false)
        coach.activate(with: nil, sessionIntent: SessionIntent(
            id: "thirty-minute-run",
            sport: .run,
            title: "30 minute run",
            detail: "Run • 30 minutes",
            coachLine: "Settle in.",
            startLabel: "Start",
            targetDurationSeconds: 30 * 60
        ))

        coach.ingest(makeSnapshot(elapsedSeconds: 15 * 60, distanceMeters: 2_500, paceSecsPerKm: 320))
        try await waitForMainActor()
        XCTAssertTrue(coach.lastSpokenAnnouncement.contains("Halfway through your time goal."))

        coach.ingest(makeSnapshot(elapsedSeconds: 29 * 60, distanceMeters: 4_700, paceSecsPerKm: 320))
        try await waitForMainActor()
        XCTAssertTrue(coach.lastSpokenAnnouncement.contains("Last minute of the time goal."))

        coach.deactivate()
    }
}

@MainActor
private final class FakeSessionAnalysisProvider: SessionAnalysisProvider {
    let identifier = "fake-session-analyzer"
    let displayName = "Fake Session Analyzer"

    private(set) var requests: [SessionAnalysisRequest] = []
    private let error: Error?
    private let shouldSpeak: Bool

    init(error: Error? = nil, shouldSpeak: Bool = false) {
        self.error = error
        self.shouldSpeak = shouldSpeak
    }

    func analyze(_ request: SessionAnalysisRequest) async throws -> SessionAnalysisResult {
        requests.append(request)

        if let error {
            throw error
        }

        return SessionAnalysisResult(
            message: "Hold steady.",
            urgency: .steady,
            shouldSpeak: shouldSpeak,
            generatedAt: Date(),
            providerID: identifier
        )
    }
}

private enum TestError: Error {
    case primaryFailed
}
