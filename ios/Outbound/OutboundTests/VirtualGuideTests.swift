import XCTest
@testable import Outbound

/// The guide is now moment-driven and app-dependent. Keep its tests in the iOS
/// target rather than compiling the retired timer/rule-based guide in SwiftPM.
@MainActor
final class VirtualGuideTests: XCTestCase {
    func testSessionLifecycleForwardsIntentAndEndsWithReport() {
        let provider = GuideTestProvider()
        let guide = makeGuide(provider)
        guide.activate(with: nil, sessionIntent: .freestyleRun, unitSystem: .imperial)
        XCTAssertEqual(provider.begunIntent, .freestyleRun)
        XCTAssertEqual(provider.unitSystem, .imperial)
        guide.deactivate()
        XCTAssertNotNil(provider.endedReport)
    }

    func testInactiveAndPausedSnapshotsDoNotRequestAnalysis() async throws {
        let provider = GuideTestProvider(instruction: "Stay smooth.")
        let guide = makeGuide(provider)
        guide.ingest(snapshot(1, active: true))
        guide.activate(with: nil, sessionIntent: .freestyleRun)
        defer { guide.deactivate() }
        guide.ingest(snapshot(1, active: false))
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(provider.requests.isEmpty)
    }

    func testWorkoutInstructionIsDeliveredOnceAtItsBoundary() async throws {
        let provider = GuideTestProvider(instruction: "Stay smooth.")
        let guide = makeGuide(provider)
        activate(guide)
        defer { guide.deactivate() }
        guide.ingest(snapshot(0))
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(provider.requests.isEmpty)
        guide.ingest(snapshot(1))
        try await waitUntil { guide.latestAnalysis != nil }
        XCTAssertEqual(provider.requests.count, 1)
        XCTAssertEqual(provider.requests.first?.momentType, .workoutInstruction)
        XCTAssertEqual(provider.requests.first?.instructionID, "fixture-instruction")
        XCTAssertEqual(guide.lastNudge, "Stay smooth.")
        XCTAssertEqual(guide.lastSpokenAnnouncement, "Stay smooth.")
        guide.ingest(snapshot(2))
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(provider.requests.count, 1)
    }

    func testProviderFailureReleasesAnalysisWithoutInventingFallbackSpeech() async throws {
        let provider = GuideTestProvider(instruction: "Stay smooth.")
        provider.fails = true
        let guide = makeGuide(provider)
        activate(guide)
        defer { guide.deactivate() }
        let initialNudge = guide.lastNudge
        guide.ingest(snapshot(1))
        try await waitUntil { !provider.requests.isEmpty && !guide.isAnalyzing }
        XCTAssertNil(guide.latestAnalysis)
        XCTAssertEqual(guide.lastNudge, initialNudge)
        XCTAssertEqual(guide.lastSpokenAnnouncement, "")
        guide.ingest(snapshot(2))
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(provider.requests.count, 1)
    }

    func testExpiredProviderResultCannotBecomeANudge() async throws {
        let provider = GuideTestProvider(instruction: "Stay smooth.")
        provider.expired = true
        let guide = makeGuide(provider)
        activate(guide)
        defer { guide.deactivate() }
        let initialNudge = guide.lastNudge
        guide.ingest(snapshot(1))
        try await waitUntil { guide.latestAnalysis != nil }
        XCTAssertEqual(guide.lastNudge, initialNudge)
        XCTAssertEqual(guide.lastSpokenAnnouncement, "")
    }

    func testProviderDistanceClaimIsCorrectedBeforeDisplayAndSpeech() async throws {
        let provider = GuideTestProvider(instruction: "1 km in. Stay smooth.")
        let guide = makeGuide(provider)
        activate(guide)
        defer { guide.deactivate() }
        guide.ingest(snapshot(1, distance: 130))
        try await waitUntil { guide.latestAnalysis != nil }
        XCTAssertEqual(guide.lastNudge, "130 meters in. Stay smooth.")
        XCTAssertFalse(guide.lastSpokenAnnouncement.localizedCaseInsensitiveContains("1 km in"))
    }

    func testDistanceMilestoneUsesRawKilometerAndIgnoresStartupJump() async throws {
        let provider = GuideTestProvider()
        let guide = makeGuide(provider)
        activate(guide)
        defer { guide.deactivate() }
        guide.ingest(snapshot(5, distance: 1_000))
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(provider.requests.isEmpty)
        // Start a fresh session so the startup outlier is not a route checkpoint.
        guide.deactivate()
        activate(guide)
        guide.ingest(snapshot(120, distance: 999))
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(provider.requests.isEmpty)
        guide.ingest(snapshot(121, distance: 1_000))
        try await waitUntil { guide.latestAnalysis != nil }
        XCTAssertEqual(provider.requests.first?.momentType, .progress)
        XCTAssertTrue(guide.lastSpokenAnnouncement.contains("1 kilometer"))
    }

    func testGoalProgressPreservesDistanceAndTimeMilestones() async throws {
        for intent in [SessionIntent.freestyleRun.replacingGoal(.distanceMeters(5_000), unitSystem: .metric),
                       SessionIntent.freestyleRun.replacingGoal(.timeSeconds(1_800), unitSystem: .metric)] {
            let provider = GuideTestProvider()
            let guide = makeGuide(provider)
            activate(guide, intent: intent)
            guide.ingest(snapshot(900, distance: 2_500))
            try await waitUntil { guide.latestAnalysis != nil }
            XCTAssertTrue(guide.lastSpokenAnnouncement.localizedCaseInsensitiveContains("halfway"))
            XCTAssertEqual(provider.requests.first?.momentType, .progress)
            guide.deactivate()
        }
    }

    private func makeGuide(_ provider: GuideTestProvider) -> VirtualGuide {
        VirtualGuide(provider: provider, speechEnabled: false, audioPack: GuideTestAudioPack())
    }

    private func activate(_ guide: VirtualGuide, intent: SessionIntent? = nil) {
        guide.activate(with: nil, sessionIntent: intent ?? .freestyleRun, suppressedMomentTypes: Set(
            LiveGuidanceMomentType.allCases.filter { $0 != .progress && $0 != .workoutInstruction }
        ))
    }

    private func snapshot(_ seconds: Int, distance: Double = 100, active: Bool = true) -> ActiveSessionSnapshot {
        ActiveSessionSnapshot(recordedAt: Date(timeIntervalSince1970: Double(seconds)), startedAt: Date(timeIntervalSince1970: 0),
            elapsedSeconds: seconds, distanceMeters: distance, currentPaceSecsPerKm: 320,
            activityType: .running, heartRate: nil, location: nil, isActive: active)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Guide did not finish processing the supplied moment")
    }
}

@MainActor
private final class GuideTestProvider: SessionAnalysisProvider {
    let identifier = "guide-fixture"
    let displayName = "Guide fixture"
    var progressPolicy: LiveCoachProgressPolicyDTO? { nil }
    var requests: [SessionAnalysisRequest] = []
    var begunIntent: SessionIntent?
    var unitSystem: MeasurementUnitSystem?
    var endedReport: LiveGuidanceSessionReport?
    var fails = false
    var expired = false
    let instruction: String?
    init(instruction: String? = nil) { self.instruction = instruction }
    var scheduledInstructions: [ScheduledGuideInstruction] {
        guard let instruction else { return [] }
        return [.init(id: "fixture-instruction", trigger: .init(type: .elapsedTime, startMeters: nil,
            endMeters: nil, startSeconds: 1, endSeconds: 90), message: instruction)]
    }
    func beginSession(profile: GuideProfile?, persona: GuidePersona?, sessionIntent: SessionIntent?,
                      companionBrief: CompanionSessionBriefDTO?, unitSystem: MeasurementUnitSystem,
                      weatherSnapshot: RunningWeatherSnapshot?, isIndoor: Bool) {
        begunIntent = sessionIntent
        self.unitSystem = unitSystem
    }
    func endSession(report: LiveGuidanceSessionReport?) { endedReport = report }
    func analyze(_ request: SessionAnalysisRequest) async throws -> SessionAnalysisResult {
        requests.append(request)
        if fails { throw URLError(.notConnectedToInternet) }
        return .init(message: request.preferredMessage ?? "Stay smooth.", urgency: .steady, shouldSpeak: true,
            generatedAt: Date(), expiresAt: Date().addingTimeInterval(expired ? -60 : 60), providerID: identifier,
            source: .plannedCache, result: .success, effectiveMode: .fixedOnly, accessReason: .openBeta,
            latencyBucket: .underOneSecond, fixedCueKey: nil, audioData: nil, audioStream: nil)
    }
}

@MainActor
private final class GuideTestAudioPack: GuideAudioPackProviding {
    func preloadSelectedAudio() async {}
    func audioData(for cueKey: String, transcript: String?) async -> Data? { nil }
    func localAudioData(for cueKey: String, transcript: String?) -> Data? { nil }
    func localAudioCue(for cueKey: String) -> (transcript: String, audioData: Data)? { nil }
    func localAudioSequence(for cueKeys: [String]) -> [Data]? { nil }
}
