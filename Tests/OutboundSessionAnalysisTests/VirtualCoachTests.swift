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
}

@MainActor
private final class FakeSessionAnalysisProvider: SessionAnalysisProvider {
    let identifier = "fake-session-analyzer"
    let displayName = "Fake Session Analyzer"

    private(set) var requests: [SessionAnalysisRequest] = []
    private let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func analyze(_ request: SessionAnalysisRequest) async throws -> SessionAnalysisResult {
        requests.append(request)

        if let error {
            throw error
        }

        return SessionAnalysisResult(
            message: "Hold steady.",
            urgency: .steady,
            shouldSpeak: false,
            generatedAt: Date(),
            providerID: identifier
        )
    }
}

private enum TestError: Error {
    case primaryFailed
}
