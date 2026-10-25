import Foundation
import OSLog
import Network

struct AccountConfigurationValue: Codable, Equatable {
    var selection: String? = nil
    var launch: ActivitySportLaunchPreference? = nil
    var entries: [StretchEntry]? = nil
}
struct AccountConfigurationRecord: Codable, Equatable {
    let key: String
    var revision: Int
    var value: AccountConfigurationValue?
}
struct AccountConfigurationResponse: Decodable { let records: [AccountConfigurationRecord] }
struct AccountConfigurationMutation: Encodable {
    let key: String
    let expectedRevision: Int
    let value: AccountConfigurationValue?
    // A reset must be explicit JSON null rather than Codable's omitted optional.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(key, forKey: .key)
        try c.encode(expectedRevision, forKey: .expectedRevision)
        try c.encode(value, forKey: .value)
    }
    enum CodingKeys: String, CodingKey { case key, expectedRevision, value }
}
struct AccountConfigurationMutationResponse: Decodable { let record: AccountConfigurationRecord }

/// Durable account-scoped cache and outbox. Drafts never enter this store.
@MainActor
final class AccountConfigurationStore {
    static let shared = AccountConfigurationStore()
    static let changed = Notification.Name("AccountConfigurationChanged")
    private static let logger = Logger(subsystem: "plainstride.outbound", category: "AccountConfiguration")
    private struct Cache: Codable {
        var records: [String: AccountConfigurationRecord] = [:]
        var pending: [String: AccountConfigurationRecord] = [:]
        var imported = false
    }
    private let defaults = UserDefaults.standard
    private let monitor = NWPathMonitor()
    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in await self?.refresh() }
        }
        monitor.start(queue: DispatchQueue(label: "plainstride.configuration.connectivity"))
    }
    private var task: Task<Void, Never>?
    private var syncing = false
    var analytics: AnalyticsManager?
    private func storageKey(_ id: String?) -> String { "account_configuration_v1_" + (id ?? "guest") }
    private func load(_ id: String?) -> Cache {
        guard let data = defaults.data(forKey: storageKey(id)) else { return Cache() }
        do { return try JSONDecoder().decode(Cache.self, from: data) }
        catch {
            Self.logger.error("Configuration cache decode failed; using defaults type=\(String(describing: type(of: error)), privacy: .public)")
            return Cache()
        }
    }
    private func save(_ cache: Cache, _ id: String?) {
        do { defaults.set(try JSONEncoder().encode(cache), forKey: storageKey(id)) }
        catch { Self.logger.error("Configuration cache encode failed type=\(String(describing: type(of: error)), privacy: .public)") }
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }
    func record(_ key: String) -> AccountConfigurationRecord? {
        let cache = load(AuthStore.currentUserId)
        return cache.pending[key] ?? cache.records[key]
    }
    func set(_ key: String, _ value: AccountConfigurationValue?) {
        let id = AuthStore.currentUserId
        var cache = load(id)
        let old = cache.pending[key] ?? cache.records[key]
        guard old?.value != value || old == nil else { return }
        cache.pending[key] = AccountConfigurationRecord(key: key, revision: old?.revision ?? 0, value: value)
        save(cache, id)
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }
    func refresh() async {
        guard !syncing, let id = AuthStore.currentUserId else { return }
        syncing = true
        defer { syncing = false }
        do {
            importExistingPreferences(id)
            let response = try await APIClient.shared.fetchAccountConfiguration()
            guard AuthStore.currentUserId == id else { return }
            var cache = load(id)
            cache.records = Dictionary(uniqueKeysWithValues: response.records.map { ($0.key, $0) })
            save(cache, id)
            // Snapshot the outbox. New edits during an upload remain queued.
            let pending = cache.pending
            for (key, change) in pending {
                guard AuthStore.currentUserId == id else { return }
                let accepted: AccountConfigurationRecord
                var conflict = false
                do {
                    accepted = try await APIClient.shared.patchAccountConfiguration(.init(key: key, expectedRevision: change.revision, value: change.value)).record
                } catch let APIError.http(statusCode, _, _) where statusCode == 409 {
                    // Server wins concurrent edits of one complete value; unrelated keys survive.
                    let current = try await APIClient.shared.fetchAccountConfiguration()
                    accepted = current.records.first { $0.key == key } ?? .init(key: key, revision: 0, value: nil)
                    conflict = true
                    Self.logger.notice("Configuration conflict resolved using server value status=409")
                }
                guard AuthStore.currentUserId == id else { return }
                cache = load(id)
                cache.records[key] = accepted
                if cache.pending[key] == change {
                    cache.pending.removeValue(forKey: key)
                } else if var newer = cache.pending[key] {
                    newer.revision = accepted.revision
                    cache.pending[key] = newer
                }
                save(cache, id)
                await analytics?.track(.init(.preferenceChanged, properties: [.changeType: .string("account_configuration_sync"), .selectionType: .string(conflict ? "conflict" : "saved")]))
            }
            if !load(id).pending.isEmpty {
                task = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    await self?.refresh()
                }
            }
        } catch {
            guard !Task.isCancelled, (error as? URLError)?.code != .cancelled else { return }
            Self.logger.error("Configuration sync failed; durable outbox retained \(Self.safeError(error), privacy: .public)")
            await analytics?.track(.init(.preferenceChanged, properties: [.changeType: .string("account_configuration_sync"), .selectionType: .string("failed")]))
        }
    }
    private static func safeError(_ error: Error) -> String {
        if case let APIError.http(status, _, _) = error { return "status=\(status)" }
        if let error = error as? URLError { return "network_code=\(error.code.rawValue)" }
        return "type=\(String(describing: type(of: error)))"
    }
    private func decodeExisting<T: Decodable>(_ type: T.Type, data: Data) -> T? {
        do { return try JSONDecoder().decode(type, from: data) }
        catch {
            Self.logger.error("Existing configuration decode failed \(Self.safeError(error), privacy: .public)")
            return nil
        }
    }
    private func importExistingPreferences(_ id: String) {
        var cache = load(id)
        guard !cache.imported else { return }
        // Legacy stretch keys had no owner: claim them once, never copy them to a
        // second account. New phones with no local values do not enqueue defaults.
        let ownerKey = "stretch_configuration_import_owner_v1"
        if defaults.string(forKey: ownerKey) == nil { defaults.set(id, forKey: ownerKey) }
        func seed(_ key: String, _ value: AccountConfigurationValue) {
            guard cache.records[key] == nil, cache.pending[key] == nil else { return }
            cache.pending[key] = .init(key: key, revision: 0, value: value)
        }
        if defaults.string(forKey: ownerKey) == id {
            for (local, remote) in [("stretch_last_routine_v1", "stretch/last"), ("stretch_last_standing_routine_v1", "stretch/standing")] {
                if let selection = defaults.string(forKey: local) { seed(remote, .init(selection: selection)) }
            }
            for template in StretchCatalogData.templates {
                if let data = defaults.data(forKey: "stretch_customization_v1_" + template.id),
                   let entries = decodeExisting([StretchEntry].self, data: data), StretchCatalog.valid(entries) {
                    seed("stretch/custom/" + template.id, .init(entries: entries))
                }
            }
        }
        if let data = defaults.data(forKey: "activity_launch_preferences_v1_account_" + id),
           let old = decodeExisting(ActivityLaunchPreferenceSnapshot.self, data: data) {
            if let sport = old.lastManualSportRawValue { seed("launch/lastSport", .init(selection: sport)) }
            for (sport, preference) in old.sports { seed("launch/" + sport, .init(launch: preference)) }
        }
        cache.imported = true
        save(cache, id)
    }
}
