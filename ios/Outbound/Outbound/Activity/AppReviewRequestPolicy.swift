import Foundation

/// Installation-local milestone; imports, edits, sync, and failed saves never advance it.
@MainActor
enum AppReviewRequestPolicy {
    private static let savesKey = "appReview.successfulRecordingIDs.v1"
    private static let requestedKey = "appReview.requested.v1"

    static func recordSuccessfulSave(id: UUID, defaults: UserDefaults = .standard) {
        var ids = defaults.stringArray(forKey: savesKey) ?? []
        guard ids.count < 3, !ids.contains(id.uuidString) else { return }
        ids.append(id.uuidString)
        defaults.set(ids, forKey: savesKey)
    }

    /// Persist before calling StoreKit: it offers no presentation or submission callback.
    static func consumeEligibleRequest(defaults: UserDefaults = .standard) -> Bool {
        guard !defaults.bool(forKey: requestedKey),
              (defaults.stringArray(forKey: savesKey) ?? []).count >= 3 else { return false }
        defaults.set(true, forKey: requestedKey)
        return true
    }
}
