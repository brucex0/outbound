import Testing
@testable import Outbound

@MainActor
struct SessionAnalysisProviderTests {
    @Test func requestsWithoutDetectedMomentStaySilent() async throws {
        let provider = ServerLiveCoachProvider()
        let result = try await provider.analyze(.init(profile: nil, persona: nil, snapshot: .empty, recentSnapshots: []))
        #expect(result.message.isEmpty)
        #expect(!result.shouldSpeak)
        #expect(result.result == .invalid)
        #expect(result.providerID == provider.identifier)
    }

    @Test func distanceParserDoesNotTreatIntervalRepsAsSessionGoal() {
        #expect(SessionIntentGoalParser.distanceMeters(from: "4 x 800m effort") == nil)
        #expect(SessionIntentGoalParser.distanceMeters(from: "6x100m strides") == nil)
        #expect(SessionIntentGoalParser.distanceMeters(from: "5K Tempo") == 5_000)
    }
}
