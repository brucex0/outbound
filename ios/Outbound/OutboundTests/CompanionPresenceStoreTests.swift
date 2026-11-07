import Foundation
import Testing
@testable import Outbound

/// Focused coverage for companion preview eligibility, ranking, and account isolation.
/// The durable inbox stays authoritative; these tests only exercise transient presentation state.
@MainActor
struct CompanionPresenceStoreTests {
    private let account = "fixture-account"
    private let now = Date()

    private func makeDefaults() -> UserDefaults {
        let suite = "companion_presence_tests_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func notification(
        id: String,
        type: String,
        objectID: String? = nil,
        message: String = "Synthetic notification",
        readAt: Date? = nil,
        createdAt: Date,
        actorName: String? = nil
    ) -> SocialNotificationDTO {
        SocialNotificationDTO(
            id: id,
            type: type,
            objectId: objectID,
            message: message,
            readAt: readAt,
            createdAt: createdAt,
            actor: actorName.map {
                SocialPersonDTO(id: "person-\(id)", username: "actor-\(id)", displayName: $0, avatarUrl: nil)
            }
        )
    }

    @Test func offerPrefersNewestNeedsYouItemOverNewerCheer() {
        let store = CompanionPresenceStore(defaults: makeDefaults())
        store.activate(accountID: account)
        store.offerDelivery(notifications: [
            notification(id: "cheer", type: "cheer", objectID: "post-1", createdAt: now.addingTimeInterval(-30)),
            notification(id: "request", type: "connectionRequest", objectID: "person-1", createdAt: now.addingTimeInterval(-3_600)),
            notification(id: "run", type: "runInvitation", objectID: "event-1", createdAt: now.addingTimeInterval(-120)),
        ], now: now)

        // Existing policy ranks Needs you first and, within that tier, newest first.
        #expect(store.preview?.primary.id == "run")
        #expect(store.preview?.presentation.tier == .needsYou)
    }

    @Test func offerFallsBackToCheersWhenNoActionableItemExists() {
        let store = CompanionPresenceStore(defaults: makeDefaults())
        store.activate(accountID: account)
        store.offerDelivery(notifications: [
            notification(id: "accepted", type: "connectionAccepted", objectID: "person-1", createdAt: now.addingTimeInterval(-60)),
            notification(id: "cheer", type: "cheer", objectID: "post-1", createdAt: now.addingTimeInterval(-120)),
        ], now: now)

        #expect(store.preview?.primary.id == "cheer")
        #expect(store.preview?.presentation.tier == .cheersAndMilestones)
    }

    @Test func offerIgnoresReadNotification() {
        let store = CompanionPresenceStore(defaults: makeDefaults())
        store.activate(accountID: account)
        store.offerDelivery(notifications: [
            notification(id: "read", type: "connectionRequest", readAt: now.addingTimeInterval(-30), createdAt: now.addingTimeInterval(-60)),
        ], now: now)

        #expect(store.preview == nil)
    }

    @Test func offerIgnoresStaleAndFutureNotifications() {
        let store = CompanionPresenceStore(defaults: makeDefaults())
        store.activate(accountID: account)
        store.offerDelivery(notifications: [
            notification(id: "stale", type: "connectionRequest", createdAt: now.addingTimeInterval(-25 * 60 * 60)),
            notification(id: "future", type: "connectionRequest", createdAt: now.addingTimeInterval(10 * 60)),
        ], now: now)

        #expect(store.preview == nil)
    }

    @Test func offerSkipsExpiredLiveCheerInvitationButKeepsOtherStaleTypesWithinADay() {
        let store = CompanionPresenceStore(defaults: makeDefaults())
        store.activate(accountID: account)

        // Cached live invitations expire from delivery after eight hours even though
        // other types remain eligible for a full day.
        store.offerDelivery(notifications: [
            notification(id: "live-old", type: "liveCheerInvitation", objectID: "session-1",
                         createdAt: now.addingTimeInterval(-9 * 60 * 60)),
        ], now: now)
        #expect(store.preview == nil)

        store.offerDelivery(notifications: [
            notification(id: "cheer-old", type: "cheer", objectID: "post-1",
                         createdAt: now.addingTimeInterval(-9 * 60 * 60)),
        ], now: now)
        #expect(store.preview?.primary.id == "cheer-old")
        #expect(store.preview?.presentation.tier == .cheersAndMilestones)
    }

    @Test func offerDeliversFreshLiveCheerInvitationAheadOfCheer() {
        let store = CompanionPresenceStore(defaults: makeDefaults())
        store.activate(accountID: account)
        store.offerDelivery(notifications: [
            notification(id: "cheer", type: "cheer", objectID: "post-1", createdAt: now.addingTimeInterval(-60)),
            notification(id: "live", type: "liveCheerInvitation", objectID: "session-1", createdAt: now.addingTimeInterval(-3_600)),
        ], now: now)

        #expect(store.preview?.primary.id == "live")
        #expect(store.preview?.presentation.tier == .needsYou)
    }

    @Test func offerIgnoresUnsolicitedUpdatesOnly() {
        let store = CompanionPresenceStore(defaults: makeDefaults())
        store.activate(accountID: account)
        store.offerDelivery(notifications: [
            notification(id: "update", type: "connectionAccepted", objectID: "person-1", createdAt: now.addingTimeInterval(-60)),
            notification(id: "generic", type: "activity", objectID: "activity-1", createdAt: now.addingTimeInterval(-30)),
        ], now: now)

        #expect(store.preview == nil)
    }

    @Test func recordVisibleDeliveryClaimsOneCalendarDayAndSurvivesDismissal() {
        let defaults = makeDefaults()
        let store = CompanionPresenceStore(defaults: defaults)
        store.activate(accountID: account)
        let request = notification(id: "request", type: "connectionRequest", createdAt: now.addingTimeInterval(-60))
        store.offerDelivery(notifications: [request], now: now)
        #expect(store.preview?.primary.id == "request")

        #expect(store.recordVisibleDelivery(id: "request", now: now))
        #expect(store.deliveryToken != nil)
        #expect(store.recordVisibleDelivery(id: "request", now: now) == false)

        store.dismissPreview()
        #expect(store.preview == nil)

        // A dismissal after the preview rendered must not re-offer anything that day,
        // even when a genuinely new, fresh actionable item arrives or the shell reloads.
        let laterItem = notification(id: "later", type: "runInvitation", createdAt: now.addingTimeInterval(-60))
        store.offerDelivery(notifications: [request, laterItem], now: now)
        #expect(store.preview == nil)

        let reloaded = CompanionPresenceStore(defaults: defaults)
        reloaded.activate(accountID: account)
        reloaded.offerDelivery(notifications: [laterItem], now: now)
        #expect(reloaded.preview == nil)
    }

    @Test func deliveryIsLimitedPerAccountAndSurvivesNewStoreInstance() {
        let defaults = makeDefaults()
        let store = CompanionPresenceStore(defaults: defaults)
        store.activate(accountID: "account-a")
        let item = notification(id: "a-item", type: "connectionRequest", createdAt: now.addingTimeInterval(-60))
        store.offerDelivery(notifications: [item], now: now)
        #expect(store.recordVisibleDelivery(id: "a-item", now: now))

        // A new store object reads the ledger back from defaults for the same account.
        let reloaded = CompanionPresenceStore(defaults: defaults)
        reloaded.activate(accountID: "account-a")
        reloaded.offerDelivery(notifications: [item], now: now)
        #expect(reloaded.preview == nil)

        // A different signed-in account is isolated from the first account's ledger.
        reloaded.activate(accountID: "account-b")
        let otherItem = notification(id: "b-item", type: "connectionRequest", createdAt: now.addingTimeInterval(-60))
        reloaded.offerDelivery(notifications: [otherItem], now: now)
        #expect(reloaded.preview?.primary.id == "b-item")

        // Returning to the claimed account restores its receipt state.
        reloaded.activate(accountID: "account-a")
        #expect(reloaded.preview == nil)
        reloaded.offerDelivery(notifications: [item], now: now)
        #expect(reloaded.preview == nil)
    }

    @Test func offerAllowsOneDeliveryOnTheNextCalendarDay() {
        let store = CompanionPresenceStore(defaults: makeDefaults())
        store.activate(accountID: account)
        let item = notification(id: "request", type: "connectionRequest", createdAt: now.addingTimeInterval(-60))
        store.offerDelivery(notifications: [item], now: now)
        #expect(store.recordVisibleDelivery(id: "request", now: now))
        // The rendered preview expires on its own in real UI; the next day starts clean.
        store.dismissPreview()

        let tomorrow = now.addingTimeInterval(25 * 60 * 60)
        let tomorrowItem = notification(id: "tomorrow", type: "connectionRequest", createdAt: tomorrow.addingTimeInterval(-60))
        store.offerDelivery(notifications: [tomorrowItem], now: tomorrow)
        #expect(store.preview?.primary.id == "tomorrow")
    }

    @Test func reconcileClearsPreviewOnceItemIsRead() {
        let store = CompanionPresenceStore(defaults: makeDefaults())
        store.activate(accountID: account)
        let item = notification(id: "request", type: "connectionRequest", createdAt: now.addingTimeInterval(-60))
        store.offerDelivery(notifications: [item], now: now)
        #expect(store.preview != nil)

        store.reconcile(notifications: [
            notification(id: "request", type: "connectionRequest", readAt: now, createdAt: now.addingTimeInterval(-60)),
        ])
        #expect(store.preview == nil)
    }

    @Test func reconcileKeepsPreviewWhileItemStaysUnread() {
        let store = CompanionPresenceStore(defaults: makeDefaults())
        store.activate(accountID: account)
        let item = notification(id: "request", type: "connectionRequest", createdAt: now.addingTimeInterval(-60))
        store.offerDelivery(notifications: [item], now: now)
        store.reconcile(notifications: [item])
        #expect(store.preview?.primary.id == "request")
    }

    @Test func activationWithoutAccountClearsPreviewAndNeverDelivers() {
        let store = CompanionPresenceStore(defaults: makeDefaults())
        store.activate(accountID: nil)
        store.offerDelivery(notifications: [
            notification(id: "request", type: "connectionRequest", createdAt: now.addingTimeInterval(-60)),
        ], now: now)

        #expect(store.preview == nil)
        #expect(store.isActiveAccount(nil) == false)
        #expect(store.isActiveAccount(account) == false)
    }
}
