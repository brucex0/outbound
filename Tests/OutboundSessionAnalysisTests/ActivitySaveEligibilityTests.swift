import Testing
@testable import OutboundSessionAnalysis

struct ActivitySaveEligibilityTests {
    @Test func requiresEitherMinimumDurationOrDistance() {
        #expect(ActivitySaveEligibility.evaluate(durationSecs: 299, distanceM: 499) == .tooShort)
        #expect(ActivitySaveEligibility.evaluate(durationSecs: 300, distanceM: 0) == .eligible)
        #expect(ActivitySaveEligibility.evaluate(durationSecs: 0, distanceM: 500) == .eligible)
        #expect(ActivitySaveEligibility.evaluate(durationSecs: 300, distanceM: 500) == .eligible)
    }
}
