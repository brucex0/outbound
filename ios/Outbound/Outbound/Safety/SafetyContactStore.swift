import Combine
import Foundation

@MainActor
final class SafetyContactStore: ObservableObject {
    @Published private(set) var trustedConnectionIDs: Set<String> = []
    @Published private(set) var sharesWithTrustedContactsByDefault = false

    private let defaults: UserDefaults
    private let trustedIDsKeyPrefix = "trusted_connection_ids_v1_account_"
    private let defaultSharingKeyPrefix = "trusted_connections_default_share_v1_account_"
    private var activeUserID: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func activate(userID: String?) {
        guard activeUserID != userID else { return }
        activeUserID = userID
        guard let userID else {
            trustedConnectionIDs = []
            sharesWithTrustedContactsByDefault = false
            return
        }
        trustedConnectionIDs = Set(defaults.stringArray(forKey: trustedIDsKey(for: userID)) ?? [])
        sharesWithTrustedContactsByDefault = defaults.bool(forKey: defaultSharingKey(for: userID))
    }

    func isTrusted(_ userID: String) -> Bool {
        trustedConnectionIDs.contains(userID)
    }

    func setTrusted(_ userID: String, isTrusted: Bool) {
        guard let activeUserID else { return }
        if isTrusted { trustedConnectionIDs.insert(userID) }
        else { trustedConnectionIDs.remove(userID) }
        defaults.set(Array(trustedConnectionIDs).sorted(), forKey: trustedIDsKey(for: activeUserID))
    }

    func setSharesWithTrustedContactsByDefault(_ enabled: Bool) {
        guard let activeUserID else { return }
        sharesWithTrustedContactsByDefault = enabled
        defaults.set(enabled, forKey: defaultSharingKey(for: activeUserID))
    }

    private func trustedIDsKey(for userID: String) -> String { trustedIDsKeyPrefix + userID }
    private func defaultSharingKey(for userID: String) -> String { defaultSharingKeyPrefix + userID }
}
