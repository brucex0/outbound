import CryptoKit
import Foundation

actor GuidePlannedAudioCache {
    static let shared = GuidePlannedAudioCache()

    private let fileManager = FileManager.default

    func audioData(planHash: String, voiceProfileID: String, phraseID: String) -> Data? {
        let url = cacheURL(planHash: planHash, voiceProfileID: voiceProfileID, phraseID: phraseID)
        guard let data = try? Data(contentsOf: url), Self.isValidWAV(data) else { return nil }
        return data
    }

    func store(_ data: Data, planHash: String, voiceProfileID: String, phraseID: String) {
        guard Self.isValidWAV(data) else { return }
        do {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try data.write(
                to: cacheURL(planHash: planHash, voiceProfileID: voiceProfileID, phraseID: phraseID),
                options: .atomic
            )
            purgeExpiredFiles()
        } catch {
            // Streaming and the reviewed fixed pack remain available.
        }
    }

    private var cacheDirectory: URL {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Plainstride/PlannedCoachAudio", isDirectory: true)
    }

    private func cacheURL(planHash: String, voiceProfileID: String, phraseID: String) -> URL {
        let key = "\(planHash):\(voiceProfileID):\(phraseID)"
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent("\(digest).wav")
    }

    private func purgeExpiredFiles() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for file in files {
            let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if date.map({ $0 < cutoff }) == true { try? fileManager.removeItem(at: file) }
        }
    }

    private static func isValidWAV(_ data: Data) -> Bool {
        guard (44...512 * 1_024).contains(data.count),
              String(data: data.prefix(4), encoding: .ascii) == "RIFF",
              String(data: data.dropFirst(8).prefix(4), encoding: .ascii) == "WAVE"
        else { return false }
        return true
    }
}
