import Foundation
import OSLog

/// All mutable state is confined to queue. Forced checkpoints drain preceding
/// work synchronously so pause/finish retain their existing durability guarantee.
nonisolated final class RecoveryCheckpointWriter: @unchecked Sendable {
    static let shared = RecoveryCheckpointWriter()
    private let queue = DispatchQueue(label: "plainstride.recovery-checkpoints", qos: .utility)
    private let logger = Logger(subsystem: "plainstride.outbound", category: "ActivityRecovery")
    private var pendingPoints: [JournalTrackPoint] = []

    private init() {}

    func submit(
        metadata: ActiveSessionJournal.Metadata,
        points: [JournalTrackPoint],
        metadataURL: URL,
        trackURL: URL,
        force: Bool
    ) {
        let operation: @Sendable () -> Void = { [self] in
            pendingPoints.append(contentsOf: points)
            do {
                let metadataData = try JSONEncoder().encode(metadata)
                try FileManager.default.createDirectory(
                    at: metadataURL.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                if !pendingPoints.isEmpty {
                    var trackData = try JSONEncoder().encode(pendingPoints)
                    trackData.append(0x0A)
                    try append(trackData, to: trackURL)
                    pendingPoints.removeAll(keepingCapacity: true)
                }
                try metadataData.write(to: metadataURL, options: .atomic)
                if force {
                    logger.notice("Recovery checkpoint stage=\(metadata.recoveryStage?.rawValue ?? "recording", privacy: .public) result=success")
                }
            } catch {
                let technical = error as NSError
                logger.error("Recovery checkpoint failed domain=\(technical.domain, privacy: .public) code=\(technical.code, privacy: .public)")
                // Keep any uncommitted points; the next checkpoint retries them.
            }
        }
        if force { queue.sync(execute: operation) }
        else { queue.async(execute: operation) }
    }

    func drainAndReset() {
        queue.sync { pendingPoints.removeAll() }
    }

    private func append(_ data: Data, to url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            try data.write(to: url, options: .atomic)
            return
        }
        let handle = try FileHandle(forWritingTo: url)
        defer {
            do { try handle.close() }
            catch {
                let technical = error as NSError
                logger.error("Recovery track close failed code=\(technical.code, privacy: .public)")
            }
        }
        let offset = try handle.seekToEnd()
        do {
            // A newline separates a possibly truncated previous recovery chunk.
            try handle.write(contentsOf: Data([0x0A]) + data)
            try handle.synchronize()
        } catch {
            // Roll back a partial append before retrying, avoiding duplicate points.
            do { try handle.truncate(atOffset: offset) }
            catch {
                let technical = error as NSError
                logger.error("Recovery track rollback failed code=\(technical.code, privacy: .public)")
            }
            throw error
        }
    }
}
