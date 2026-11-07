import Combine
import Foundation
import SwiftUI
import UIKit

/// Transient delivery state only. The durable inbox remains TogetherStore's authority.
@MainActor
final class CompanionPresenceStore: ObservableObject {
    @Published private(set) var preview: NotificationCenterPresentationItem?
    @Published private(set) var deliveryToken: UUID?
    private var accountID: String?
    private var shownIDs: [String] = []
    private var lastDeliveryAt: Date?
    private var lastVisiblePreviewID: String?
    private var hasRecordedIdleExposure = false
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        #if DEBUG
        // Seeded UI fixtures start with an empty ledger so preview timing and the
        // per-day budget are reproducible across scenarios. Never clears inbox state.
        if ProcessInfo.processInfo.arguments.contains("-OutboundUITestSeedData"),
           ProcessInfo.processInfo.arguments.contains("-OutboundUITestResetCompanionPresence") {
            // Only the synthetic fixture account, never a real account's receipts.
            for key in ["fox_companion_shown_v1_ui_test", "fox_companion_delivery_date_v1_ui_test"] {
                defaults.removeObject(forKey: key)
            }
        }
        #endif
    }

    func activate(accountID: String?) {
        guard self.accountID != accountID else { return }
        self.accountID = accountID
        preview = nil
        deliveryToken = nil
        lastVisiblePreviewID = nil
        hasRecordedIdleExposure = false
        shownIDs = accountID.map { defaults.stringArray(forKey: ledgerKey($0)) ?? [] } ?? []
        lastDeliveryAt = accountID.flatMap { defaults.object(forKey: dateKey($0)) as? Date }
    }

    func resetIdleExposure() {
        hasRecordedIdleExposure = false
    }

    func recordVisibleIdleExposure() -> Bool {
        guard !hasRecordedIdleExposure else { return false }
        hasRecordedIdleExposure = true
        return true
    }

    func isActiveAccount(_ accountID: String?) -> Bool {
        accountID != nil && self.accountID == accountID
    }

    func reconcile(notifications: [SocialNotificationDTO]) {
        guard let preview else { return }
        let unreadIDs = Set(notifications.filter { $0.readAt == nil && NotificationPresentationPolicy.isCurrent($0) }.map(\.id))
        if !preview.notifications.contains(where: { unreadIDs.contains($0.id) }) {
            dismissPreview()
        }
    }

    func offerDelivery(notifications: [SocialNotificationDTO], now: Date = Date()) {
        guard accountID != nil, preview == nil,
              lastDeliveryAt.map({ !Calendar.current.isDate($0, inSameDayAs: now) }) ?? true else { return }
        let shown = Set(shownIDs)
        let eligible = notifications.filter {
            $0.readAt == nil && !shown.contains($0.id)
                && $0.createdAt > now.addingTimeInterval(-24 * 60 * 60)
                && $0.createdAt <= now.addingTimeInterval(5 * 60)
        }
        preview = NotificationPresentationPolicy.items(from: eligible, now: now).first {
            $0.presentation.tier == .needsYou || $0.presentation.tier == .cheersAndMilestones
        }
    }

    /// Called by the rendered preview, never by background refresh or candidate selection.
    @discardableResult
    func recordVisibleDelivery(id: String, now: Date = Date()) -> Bool {
        guard let accountID, let preview, preview.id == id,
              lastVisiblePreviewID != id, !shownIDs.contains(preview.primary.id) else { return false }
        lastVisiblePreviewID = id
        var retainedIDs = Set<String>()
        // Keep the current representative first, including unusually large batches.
        shownIDs = Array((preview.notifications.map(\.id) + shownIDs).filter {
            retainedIDs.insert($0).inserted
        }.prefix(512))
        lastDeliveryAt = now
        defaults.set(shownIDs, forKey: ledgerKey(accountID))
        defaults.set(now, forKey: dateKey(accountID))
        deliveryToken = UUID()
        return true
    }

    func dismissPreview() {
        preview = nil
        deliveryToken = nil
    }

    private func ledgerKey(_ accountID: String) -> String { "fox_companion_shown_v1_\(accountID)" }
    private func dateKey(_ accountID: String) -> String { "fox_companion_delivery_date_v1_\(accountID)" }
}

/// A presentation can originate inside any tab. Observe the owning window rather
/// than guessing every child sheet's binding. This never changes presentation state.
struct CompanionPresentationObserver: UIViewRepresentable {
    let onChange: (Bool) -> Void

    func makeUIView(context: Context) -> CompanionPresentationObserverView {
        let view = CompanionPresentationObserverView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ view: CompanionPresentationObserverView, context: Context) {
        view.onChange = onChange
    }
}

final class CompanionPresentationObserverView: UIView {
    var onChange: ((Bool) -> Void)?
    private var timer: Timer?
    private var lastValue: Bool?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        timer?.invalidate()
        guard window != nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPresentation() }
        }
        checkPresentation()
    }

    private func checkPresentation() {
        let isPresented = window?.rootViewController?.presentedViewController != nil
        guard lastValue != isPresented else { return }
        lastValue = isPresented
        // didMoveToWindow may run within SwiftUI's update pass.
        DispatchQueue.main.async { [weak self] in self?.onChange?(isPresented) }
    }

    deinit { timer?.invalidate() }
}
