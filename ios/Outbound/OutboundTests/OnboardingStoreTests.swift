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
        #expect(store.step == .intent)
        #expect(!store.canAdvance)

        store.selectIntent(.restartGently)
        store.advance()
        store.selectSport(.bike)
        store.selectExperience(.steady)
        store.selectSessionLength(.twenty)
        store.selectWeeklyRhythm(.three)
        store.advance()

        let completedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let profile = store.complete(now: completedAt)

        #expect(!store.isPresented)
        #expect(profile.intent == .restartGently)
        #expect(profile.sport == .bike)
        #expect(profile.experience == .steady)
        #expect(profile.sessionLength == .twenty)
        #expect(profile.weeklyRhythm == .three)
        #expect(profile.suggestedSession.title == "20 min gentle ride")

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
        store.selectIntent(.moveToday)
        _ = store.complete(now: Date(timeIntervalSince1970: 1_800_000_001))

        store.restartForDebug()

        #expect(store.isPresented)
        #expect(store.step == .welcome)
        #expect(store.draft == .fresh)
    }
}
