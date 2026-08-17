import XCTest
@testable import OutboundSessionAnalysis

@MainActor
final class VirtualGuideTests: XCTestCase {
    func testIngestWaitsForInitialThresholdBeforeAnalyzing() async throws {
        let provider = FakeSessionAnalysisProvider()
        let guide = VirtualGuide(provider: provider)
        guide.activate(with: nil)

        guide.ingest(makeSnapshot(elapsedSeconds: 74, distanceMeters: 260, paceSecsPerKm: 320))
        try await waitForMainActor()

        XCTAssertNil(guide.latestAnalysis)
        XCTAssertEqual(provider.requests.count, 0)

        guide.ingest(makeSnapshot(elapsedSeconds: 75, distanceMeters: 270, paceSecsPerKm: 320))
        try await waitUntil { guide.latestAnalysis != nil }

        XCTAssertEqual(provider.requests.count, 1)
        XCTAssertEqual(guide.providerName, provider.displayName)
        XCTAssertEqual(guide.lastNudge, "Hold steady.")
        XCTAssertEqual(guide.latestAnalysis?.providerID, provider.identifier)

        guide.deactivate()
    }

    func testIngestRespectsAnalysisInterval() async throws {
        let provider = FakeSessionAnalysisProvider()
        let guide = VirtualGuide(provider: provider)
        guide.activate(with: nil)

        guide.ingest(makeSnapshot(elapsedSeconds: 75, distanceMeters: 270, paceSecsPerKm: 320))
        try await waitUntil { provider.requests.count == 1 }

        guide.ingest(makeSnapshot(elapsedSeconds: 149, distanceMeters: 650, paceSecsPerKm: 320))
        try await waitForMainActor()
        XCTAssertEqual(provider.requests.count, 1)

        guide.ingest(makeSnapshot(elapsedSeconds: 150, distanceMeters: 660, paceSecsPerKm: 320))
        try await waitUntil { provider.requests.count == 2 }

        guide.deactivate()
    }

    func testFallsBackWhenPrimaryProviderThrows() async throws {
        let provider = FakeSessionAnalysisProvider(error: TestError.primaryFailed)
        let guide = VirtualGuide(provider: provider)
        guide.activate(with: makeProfile(preferredPaceSecs: 300))

        guide.ingest(makeSnapshot(elapsedSeconds: 75, distanceMeters: 260, paceSecsPerKm: 330))
        try await waitUntil { guide.latestAnalysis != nil }

        XCTAssertEqual(provider.requests.count, 1)
        XCTAssertEqual(guide.latestAnalysis?.providerID, "rule-based-session-analyzer")
        XCTAssertTrue(guide.lastNudge.contains("stronger rhythm"))

        guide.deactivate()
    }

    func testSpokenAnalysisDoesNotAlwaysPrefixProgressStats() async throws {
        let provider = FakeSessionAnalysisProvider(shouldSpeak: true)
        let guide = VirtualGuide(provider: provider, speechEnabled: false)
        guide.activate(with: nil)

        guide.ingest(makeSnapshot(elapsedSeconds: 75, distanceMeters: 270, paceSecsPerKm: 320))
        try await waitUntil { guide.latestAnalysis != nil }

        XCTAssertEqual(guide.lastNudge, "Hold steady.")
        XCTAssertEqual(guide.lastSpokenAnnouncement, "Hold steady.")

        guide.deactivate()
    }

    func testProviderDistanceClaimIsCorrectedWhenItExceedsCurrentDistance() async throws {
        let provider = FakeSessionAnalysisProvider(message: "1 km in. Stay smooth.", shouldSpeak: true)
        let guide = VirtualGuide(provider: provider, speechEnabled: false)
        guide.activate(with: nil)

        guide.ingest(makeSnapshot(elapsedSeconds: 75, distanceMeters: 130, paceSecsPerKm: 320))
        try await waitUntil { guide.latestAnalysis != nil }

        XCTAssertEqual(guide.lastNudge, "130 meters in. Stay smooth.")
        XCTAssertTrue(guide.lastSpokenAnnouncement.contains("130 meters in."))
        XCTAssertFalse(guide.lastSpokenAnnouncement.localizedCaseInsensitiveContains("1 km in"))

        guide.deactivate()
    }

    func testProgressAndAnalysisDoNotBothSpeakOnSameTick() async throws {
        let provider = FakeSessionAnalysisProvider(shouldSpeak: true)
        let guide = VirtualGuide(provider: provider, speechEnabled: false)
        guide.activate(with: nil)

        guide.ingest(makeSnapshot(elapsedSeconds: 300, distanceMeters: 1_000, paceSecsPerKm: 320))
        try await waitUntil { guide.latestAnalysis != nil }

        XCTAssertTrue(guide.lastSpokenAnnouncement.contains("5 minutes in."))
        XCTAssertTrue(guide.lastSpokenAnnouncement.contains("1 kilometer."))
        XCTAssertFalse(guide.lastSpokenAnnouncement.contains("Hold steady."))

        guide.deactivate()
    }

    func testEarlyProgressAnnouncementSuppressesTinyDistanceRecap() async throws {
        let provider = FakeSessionAnalysisProvider(shouldSpeak: false)
        let guide = VirtualGuide(provider: provider, speechEnabled: false)
        guide.activate(with: nil)

        guide.ingest(makeSnapshot(elapsedSeconds: 300, distanceMeters: 20, paceSecsPerKm: 320))
        try await waitForMainActor()

        XCTAssertEqual(guide.lastSpokenAnnouncement, "")

        guide.deactivate()
    }

    func testDistanceProgressMilestoneWaitsForRawKilometerBeforeAnnouncing() async throws {
        let provider = FakeSessionAnalysisProvider(shouldSpeak: false)
        let guide = VirtualGuide(provider: provider, speechEnabled: false)
        guide.activate(with: nil)

        guide.ingest(makeSnapshot(elapsedSeconds: 120, distanceMeters: 999, paceSecsPerKm: 320))
        try await waitForMainActor()
        XCTAssertEqual(guide.lastSpokenAnnouncement, "")

        guide.ingest(makeSnapshot(elapsedSeconds: 121, distanceMeters: 1_000, paceSecsPerKm: 320))
        try await waitForMainActor()
        XCTAssertTrue(guide.lastSpokenAnnouncement.contains("1 kilometer."))

        guide.deactivate()
    }

    func testDistanceProgressMilestoneIgnoresImplausibleStartupJump() async throws {
        let provider = FakeSessionAnalysisProvider(shouldSpeak: false)
        let guide = VirtualGuide(provider: provider, speechEnabled: false)
        guide.activate(with: nil)

        guide.ingest(makeSnapshot(elapsedSeconds: 5, distanceMeters: 1_000, paceSecsPerKm: 320))
        try await waitForMainActor()

        XCTAssertEqual(guide.lastSpokenAnnouncement, "")

        guide.deactivate()
    }

    func testDistanceGoalSpeaksHalfwayAndLastMileMilestones() async throws {
        let provider = FakeSessionAnalysisProvider(shouldSpeak: false)
        let guide = VirtualGuide(provider: provider, speechEnabled: false)
        guide.activate(with: nil, sessionIntent: SessionIntent(
            id: "three-mile-run",
            sport: .run,
            title: "3 mile run",
            detail: "Run • 3 miles",
            guideLine: "Settle in.",
            startLabel: "Start",
            targetDistanceMeters: 3 * 1_609.344
        ))

        guide.ingest(makeSnapshot(elapsedSeconds: 300, distanceMeters: 2_500, paceSecsPerKm: 320))
        try await waitForMainActor()
        XCTAssertTrue(guide.lastSpokenAnnouncement.contains("Halfway through your distance goal."))

        guide.ingest(makeSnapshot(elapsedSeconds: 375, distanceMeters: 3_300, paceSecsPerKm: 320))
        try await waitForMainActor()
        XCTAssertTrue(guide.lastSpokenAnnouncement.contains("Last mile"))

        guide.deactivate()
    }

    func testTimeGoalSpeaksHalfwayAndLastMinuteMilestones() async throws {
        let provider = FakeSessionAnalysisProvider(shouldSpeak: false)
        let guide = VirtualGuide(provider: provider, speechEnabled: false)
        guide.activate(with: nil, sessionIntent: SessionIntent(
            id: "thirty-minute-run",
            sport: .run,
            title: "30 minute run",
            detail: "Run • 30 minutes",
            guideLine: "Settle in.",
            startLabel: "Start",
            targetDurationSeconds: 30 * 60
        ))

        guide.ingest(makeSnapshot(elapsedSeconds: 15 * 60, distanceMeters: 2_500, paceSecsPerKm: 320))
        try await waitForMainActor()
        XCTAssertTrue(guide.lastSpokenAnnouncement.contains("Halfway through your time goal."))

        guide.ingest(makeSnapshot(elapsedSeconds: 29 * 60, distanceMeters: 4_700, paceSecsPerKm: 320))
        try await waitForMainActor()
        XCTAssertTrue(guide.lastSpokenAnnouncement.contains("Last minute of the time goal."))

        guide.deactivate()
    }
}

@MainActor
private final class FakeSessionAnalysisProvider: SessionAnalysisProvider {
    let identifier = "fake-session-analyzer"
    let displayName = "Fake Session Analyzer"

    private(set) var requests: [SessionAnalysisRequest] = []
    private let error: Error?
    private let message: String
    private let shouldSpeak: Bool

    init(error: Error? = nil, message: String = "Hold steady.", shouldSpeak: Bool = false) {
        self.error = error
        self.message = message
        self.shouldSpeak = shouldSpeak
    }

    func analyze(_ request: SessionAnalysisRequest) async throws -> SessionAnalysisResult {
        requests.append(request)

        if let error {
            throw error
        }

        return SessionAnalysisResult(
            message: message,
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
