import Foundation
import Testing
@testable import Outbound

struct OnboardingStoreTests {

    @MainActor
    @Test func freshIdentityPresentsAndCompletionPersists() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let store = OnboardingStore(defaults: defaults)

        store.prepareForAuthenticatedUser(identity: "user-a")

        #expect(store.isPresented)
        #expect(store.step == .welcome)

        store.advance()
        #expect(store.step == .goal)
        #expect(!store.canAdvance)

        store.updateGoalText("Restart cycling gently after time away")
        store.advance()
        #expect(store.step == .body)
        store.updateAgeText("35")
        store.updateHeightText("70")
        store.updateWeightText("170")
        store.selectSex(.male)
        store.advance()
        #expect(store.step == .baseline)
        store.updateBaselineText("I can ride comfortably for 20 minutes twice a week")
        store.updateScheduleText("I can train three times per week")
        store.selectEffortPreference(.easier)
        store.advance()
        #expect(store.step == .review)
        store.advance()
        #expect(store.step == .setup)

        let completedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let profile = store.complete(now: completedAt)

        #expect(!store.isPresented)
        #expect(profile.intakeSummary.focus == .comeback)
        #expect(profile.intakeSummary.sport == .bike)
        #expect(profile.intakeSummary.effortPreference == .easier)
        #expect(profile.intakeSummary.firstSessionLength == .fifteen)
        #expect(profile.intakeSummary.weeklyRhythm == .three)
        #expect(profile.bodyProfile.hasRequiredBasics)
        #expect(profile.suggestedSession.title == "15 min gentle ride")

        let reloadedStore = OnboardingStore(defaults: defaults)
        reloadedStore.prepareForAuthenticatedUser(identity: "user-a")

        #expect(!reloadedStore.isPresented)
        #expect(reloadedStore.completedProfile == profile)
    }

    @MainActor
    @Test func debugRestartPresentsEvenAfterCompletion() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let store = OnboardingStore(defaults: defaults)
        store.prepareForAuthenticatedUser(identity: "debug-user")
        store.updateGoalText("Move today with an easy run")
        _ = store.complete(now: Date(timeIntervalSince1970: 1_800_000_001))

        store.restartForDebug()

        #expect(store.isPresented)
        #expect(store.step == .welcome)
        #expect(store.draft == .fresh)
    }
}
