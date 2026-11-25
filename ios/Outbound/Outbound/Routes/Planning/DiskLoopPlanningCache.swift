import CryptoKit
import Foundation
import OSLog

/// All filesystem work runs on this actor, never on the UI actor. One current schema; no migrations.
actor DiskLoopPlanningCache: LoopPlanningCache {
    static let shared = DiskLoopPlanningCache()
    private let logger = Logger(subsystem: "plainstride.outbound", category: "ActivityPersistence")
    private let directory: URL
    private let now: @Sendable () -> Date
    private struct File: Codable {
        let schema: Int
        let owner: String
        let entries: [LoopPlanningCacheEntry]
    }
    init(directory: URL? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory ?? URL.applicationSupportDirectory.appending(path: "LoopSuggestions-v1", directoryHint: .isDirectory)
        self.now = now
    }
    private func url(_ account: ActivityAccountContext) -> URL {
        let digest = SHA256.hash(data: Data(account.owner.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: digest + ".json")
    }
    private func validate(_ account: ActivityAccountContext) throws {
        try ActivityAccountBoundary.validate(account)
        guard account.owner.hasPrefix("account:") else { throw CancellationError() }
    }
    func load(account: ActivityAccountContext) throws -> LoopPlanningCacheRead {
        try validate(account)
        let path = url(account)
        guard FileManager.default.fileExists(atPath: path.path) else { return .init(entries: []) }
        do {
            let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: path))
            try validate(account)
            guard file.schema == 1, file.owner == account.owner else {
                try FileManager.default.removeItem(at: path)
                logger.notice("route_cache_discard category=schema_or_owner")
                return .init(entries: [])
            }
            let entries = Array(file.entries.filter { $0.fresh(at: now()) && $0.valid }.suffix(30))
            if entries.count != file.entries.count {
                logger.notice("route_cache_discard category=expired_or_invalid")
                try write(entries, account: account)
            }
            return .init(entries: entries, discardedExpired: file.entries.contains { !$0.fresh(at: now()) })
        } catch is DecodingError {
            try FileManager.default.removeItem(at: path)
            logger.error("route_cache_read_failed category=decoding")
            return .init(entries: [])
        }
    }
    func store(_ routes: [LoopPlanningCandidate], request: LoopPlanningRequest, account: ActivityAccountContext) throws {
        try validate(account)
        let added = routes.map { LoopPlanningCacheEntry(storedAt: now(), request: request, route: $0) }.filter(\.valid)
        guard !added.isEmpty else { return } // Empty/error responses never replace good routes.
        var entries = try load(account: account).entries
        entries.removeAll { old in added.contains { $0.route.id == old.route.id } }
        entries.append(contentsOf: added)
        try write(Array(entries.suffix(30)), account: account)
    }
    private func write(_ entries: [LoopPlanningCacheEntry], account: ActivityAccountContext) throws {
        try validate(account)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var dataDirectory = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try dataDirectory.setResourceValues(values)
        let data = try JSONEncoder().encode(File(schema: 1, owner: account.owner, entries: entries))
        try validate(account)
        try data.write(to: url(account), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func purge(_ account: ActivityAccountContext) throws {
        // A late logout must never erase a newly signed-in copy of the same account.
        guard ActivityAccountBoundary.current.owner != account.owner else { return }
        let path = url(account)
        if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
    }
}
