import Combine
import Foundation
import OSLog

/// Local-first trusted-contact state with server persistence so the list
/// survives delete/reinstall. Locally, only the account-scoped cache is erased
/// when the app is deleted; the server copy is authoritative after sign-in.
@MainActor
final class SafetyContactStore: ObservableObject {
    private static let logger = Logger(
        subsystem: "plainstride.outbound",
        category: "SafetyContacts"
    )

    @Published private(set) var trustedConnectionIDs: Set<String> = []
    @Published private(set) var sharesWithTrustedContactsByDefault = false

    private let api: APIClient
    private let defaults: UserDefaults
    private let trustedIDsKeyPrefix = "trusted_connection_ids_v1_account_"
    private let defaultSharingKeyPrefix = "trusted_connections_default_share_v1_account_"
    private let migratedFlagPrefix = "trusted_contacts_server_sync_migrated_v1_account_"
    private var activeUserID: String?
    private var isApplyingRemoteState = false
    private var syncTask: Task<Void, Never>?
    // iOS has no per-contact default concept; echo the server value so iOS
    // edits never clear a default set from Android.
    private var serverDefaultContactUserID: String?

    init(api: APIClient? = nil, defaults: UserDefaults = .standard) {
        self.api = api ?? .shared
        self.defaults = defaults
    }

    func activate(userID: String?) {
        guard activeUserID != userID else { return }
        activeUserID = userID
        syncTask?.cancel()
        syncTask = nil
        serverDefaultContactUserID = nil
        guard let userID else {
            trustedConnectionIDs = []
            sharesWithTrustedContactsByDefault = false
            return
        }
        trustedConnectionIDs = Set(defaults.stringArray(forKey: trustedIDsKey(for: userID)) ?? [])
        sharesWithTrustedContactsByDefault = defaults.bool(forKey: defaultSharingKey(for: userID))

        // One-time migration: push any pre-existing local-only trusted contacts
        // to the server before the first fetch overwrites the local cache.
        let hasMigrated = defaults.bool(forKey: migratedFlagKey(for: userID))
        if !hasMigrated && !trustedConnectionIDs.isEmpty {
            defaults.set(true, forKey: migratedFlagKey(for: userID))
            syncTask = Task { [weak self] in
                await self?.pushLocalStateToServer(userID: userID)
            }
            return
        }
        defaults.set(true, forKey: migratedFlagKey(for: userID))
        syncTask = Task { [weak self] in
            await self?.refreshFromServer(userID: userID)
        }
    }

    func isTrusted(_ userID: String) -> Bool {
        trustedConnectionIDs.contains(userID)
    }

    func setTrusted(_ userID: String, isTrusted: Bool) {
        guard let activeUserID else { return }
        if isTrusted { trustedConnectionIDs.insert(userID) }
        else { trustedConnectionIDs.remove(userID) }
        persistLocal(activeUserID)
        schedulePush(activeUserID)
    }

    func setSharesWithTrustedContactsByDefault(_ enabled: Bool) {
        guard let activeUserID else { return }
        sharesWithTrustedContactsByDefault = enabled
        defaults.set(enabled, forKey: defaultSharingKey(for: activeUserID))
        schedulePush(activeUserID)
    }

    /// Re-pull server state; used after connections refresh or app foreground.
    func refreshFromServer() {
        guard let userID = activeUserID else { return }
        schedulePush(userID, pullOnly: true)
    }

    // MARK: - Server sync

    private func schedulePush(_ userID: String, pullOnly: Bool = false) {
        if pullOnly {
            syncTask?.cancel()
            syncTask = Task { [weak self] in
                await self?.refreshFromServer(userID: userID)
            }
            return
        }
        // Debounced: collapse rapid toggle changes into one request.
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await self?.pushLocalStateToServer(userID: userID)
        }
    }

    private func pushLocalStateToServer(userID: String) async {
        guard !isApplyingRemoteState else { return }
        let contactUserIds = Array(trustedConnectionIDs).sorted()
        do {
            let response = try await api.updateTrustedContacts(
                TrustedContactsUpdateRequest(
                    contactUserIds: contactUserIds,
                    defaultContactUserId: serverDefaultContactUserID
                )
            )
            guard activeUserID == userID, !Task.isCancelled else { return }
            applyRemote(response, userID: userID, overwriteLocal: false)
        } catch {
            guard !Task.isCancelled else { return }
            Self.logger.error("Trusted contacts upload failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func refreshFromServer(userID: String) async {
        do {
            let response = try await api.fetchTrustedContacts()
            guard activeUserID == userID, !Task.isCancelled else { return }
            applyRemote(response, userID: userID, overwriteLocal: true)
        } catch {
            guard !Task.isCancelled else { return }
            // Offline or signed out mid-flight: keep the local cache.
            Self.logger.error("Trusted contacts refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func applyRemote(_ response: TrustedContactsResponse, userID: String, overwriteLocal: Bool) {
        isApplyingRemoteState = true
        defer { isApplyingRemoteState = false }

        serverDefaultContactUserID = response.defaultContactUserId
        let remote = Set(response.contactUserIds)
        if overwriteLocal {
            trustedConnectionIDs = remote
        }
        persistLocal(userID)
    }

    private func persistLocal(_ userID: String) {
        defaults.set(Array(trustedConnectionIDs).sorted(), forKey: trustedIDsKey(for: userID))
    }

    private func trustedIDsKey(for userID: String) -> String { trustedIDsKeyPrefix + userID }
    private func defaultSharingKey(for userID: String) -> String { defaultSharingKeyPrefix + userID }
    private func migratedFlagKey(for userID: String) -> String { migratedFlagPrefix + userID }
}
