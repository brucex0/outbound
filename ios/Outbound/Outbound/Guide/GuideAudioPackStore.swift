import CryptoKit
import Foundation

@MainActor
protocol GuideAudioPackProviding: AnyObject {
    func preloadSelectedAudio() async
    func audioData(for cueKey: String, transcript: String?) async -> Data?
    func localAudioData(for cueKey: String, transcript: String?) -> Data?
    func localAudioCue(for cueKey: String) -> (transcript: String, audioData: Data)?
    func localAudioSequence(for cueKeys: [String]) -> [Data]?
}

@MainActor
final class GuideAudioPackStore: GuideAudioPackProviding {
    static let shared = GuideAudioPackStore()
    static let speedWarningCueKeys = ["coach.speed_increase", "coach.speed_decrease"]
    static let sessionControlCueKeys = speedWarningCueKeys + ["workout.pause", "workout.resume"]
    static let countdownCueKeys = [
        "countdown.five", "countdown.four", "countdown.three", "countdown.two", "countdown.one", "countdown.go"
    ]
    static let segmentCountdownCueKeys = [
        "countdown.five", "countdown.four", "countdown.three", "countdown.two", "countdown.one"
    ]

    private struct Manifest: Decodable {
        let contractVersion: Int
        let catalogVersion: String
        let entries: [Entry]
    }

    private struct SignedManifestEnvelope: Decodable {
        let contractVersion: Int
        let payload: String
        let signature: Signature

        struct Signature: Decodable {
            let algorithm: String
            let keyId: String
            let value: String
        }
    }

    private struct Entry: Decodable {
        let cueKey: String
        let locale: String
        let voiceProfileId: String
        let scriptStyleId: String
        let compatibleCoachPersonaIds: [String]
        let transcript: String
        let sha256: String
        let contentType: String
        let url: URL?
        let bundledResourceName: String?
        let approved: Bool
    }

    private let audioFiles = VerifiedGuideAudioFiles()
    private let verifiedAudio = NSCache<NSString, NSData>()
    private var selectedPreloadTask: Task<Void, Never>?
    private var manifestGeneration = UUID()
    private var manifest: Manifest?
    private var bundledManifest: Manifest?
    private var coachPersonaID = "plainstride_supportive_v1"
    private var voiceProfileID = "plainstride_warm_1"
    private var scriptStyleID = "standard"
    private let fileManager = FileManager.default
    private let cacheDirectoryOverride: URL?
    private let bundledAudioDirectory: URL?
    private let localeIdentifier: @MainActor () -> String

    init(cacheDirectory: URL? = nil, bundledAudioDirectory: URL? = nil,
         localeIdentifier: @escaping @MainActor () -> String = { AppLanguage.currentIdentifier }) {
        self.cacheDirectoryOverride = cacheDirectory
        self.bundledAudioDirectory = bundledAudioDirectory ?? Bundle.main.url(
            forResource: "manifest", withExtension: "json", subdirectory: "LiveCoachAudio"
        )?.deletingLastPathComponent()
        self.localeIdentifier = localeIdentifier
        verifiedAudio.totalCostLimit = 32 * 1024 * 1024
        bundledManifest = loadBundledManifest()
        manifest = loadCachedManifest() ?? bundledManifest
    }

    func select(coachPersonaID: String, voiceProfileID: String, scriptStyleID: String) {
        self.coachPersonaID = coachPersonaID
        self.voiceProfileID = voiceProfileID
        self.scriptStyleID = scriptStyleID
        selectedPreloadTask?.cancel()
        selectedPreloadTask = Task { [weak self] in
            await self?.preloadSelectedAudio()
        }
    }

    func refresh(from url: URL, expectedCatalogVersion: String) async {
        let expectedGeneration = UUID()
        manifestGeneration = expectedGeneration
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            try Task.checkCancellation()
            guard expectedGeneration == manifestGeneration else { return }
            guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true else { return }
            let verified = try verifiedRemoteManifest(from: data)
            let decoded = verified.manifest
            guard decoded.contractVersion == 1,
                  decoded.catalogVersion == expectedCatalogVersion,
                  decoded.entries.allSatisfy({
                      $0.approved && $0.contentType == "audio/wav" && $0.url != nil
                  })
            else { return }
            manifest = decoded
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try verified.payload.write(to: manifestCacheURL, options: .atomic)
        } catch is CancellationError {
            // Ending/replacing a session intentionally cancels refresh.
        } catch {
            ActivityDiagnosticLog.error(.lifecycle,
                "Coach audio manifest refresh failed error=\(ActivityDiagnosticLog.errorCategory(error))")
            // Keep the last known-good manifest and bundled fallback state.
        }
    }

    func audioData(for cueKey: String, transcript: String? = nil) async -> Data? {
        guard let entry = matchingEntry(cueKey: cueKey, transcript: transcript) else { return nil }
        if let local = localAudioData(for: entry) { return local }
        if let local = await loadLocalAudio(for: entry) { return local }
        guard !Task.isCancelled, let url = entry.url else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            try Task.checkCancellation()
            guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true,
                  await audioFiles.verifyAndStore(data, sha256: entry.sha256, url: cacheURL(for: entry.sha256))
            else { return nil }
            remember(data, checksum: entry.sha256)
            return data
        } catch is CancellationError {
            return nil // Session replacement/cue cancellation is expected.
        } catch {
            ActivityDiagnosticLog.error(.lifecycle,
                "Coach audio asset fetch failed error=\(ActivityDiagnosticLog.errorCategory(error))")
            return nil
        }
    }

    /// Local-only cold lookup for fallback; never waits for a network download.
    func cachedOrBundledAudioData(for cueKey: String, transcript: String? = nil) async -> Data? {
        guard let entry = matchingEntry(cueKey: cueKey, transcript: transcript) else { return nil }
        if let cached = localAudioData(for: entry) { return cached }
        return await loadLocalAudio(for: entry)
    }

    func preloadSelectedAudio() async {
        await preloadAudio(for: Self.speedWarningCueKeys)
        let ready = Self.speedWarningCueKeys.filter { localAudioData(for: $0) != nil }.count
        ActivityDiagnosticLog.notice(.lifecycle, "Speed warning audio prepared ready=\(ready) expected=2")
        await preloadAudio(for: ["workout.pause", "workout.resume"] + Self.countdownCueKeys)
        let entries = availableEntries.filter {
            $0.locale == localeIdentifier()
                && $0.voiceProfileId == voiceProfileID
                && $0.compatibleCoachPersonaIds.contains(coachPersonaID)
        }
        for entry in entries {
            guard !Task.isCancelled else { return }
            if localAudioData(for: entry) == nil { _ = await loadLocalAudio(for: entry) }
        }
    }

    func preloadAudio(for cueKeys: [String]) async {
        for cueKey in cueKeys where !Task.isCancelled {
            guard localAudioData(for: cueKey) == nil else { continue }
            _ = await audioData(for: cueKey)
        }
    }

    func localAudioData(for cueKey: String, transcript: String? = nil) -> Data? {
        guard let entry = matchingEntry(cueKey: cueKey, transcript: transcript) else { return nil }
        return localAudioData(for: entry)
    }

    /// Semantic callers use the reviewed script and bytes together. Sentence
    /// fallback callers must continue to use the transcript-constrained lookup.
    func localAudioCue(for cueKey: String) -> (transcript: String, audioData: Data)? {
        guard let entry = matchingEntry(cueKey: cueKey, transcript: nil) else {
            ActivityDiagnosticLog.error(.lifecycle, "Coach semantic clip unavailable reason=no_matching_entry")
            return nil
        }
        guard let data = localAudioData(for: entry) else {
            ActivityDiagnosticLog.error(.lifecycle, "Coach semantic clip unavailable reason=not_preloaded")
            return nil
        }
        return (entry.transcript, data)
    }

    func localAudioSequence(for cueKeys: [String]) -> [Data]? {
        let clips = cueKeys.compactMap { localAudioData(for: $0) }
        return clips.count == cueKeys.count ? clips : nil
    }

    private func localAudioData(for entry: Entry) -> Data? {
        verifiedAudio.object(forKey: entry.sha256 as NSString).map { $0 as Data }
    }

    private func remember(_ data: Data, checksum: String) {
        verifiedAudio.setObject(data as NSData, forKey: checksum as NSString, cost: data.count)
    }

    private func loadLocalAudio(for entry: Entry) async -> Data? {
        let bundledURL = entry.bundledResourceName.flatMap {
            bundledAudioDirectory?.appendingPathComponent($0).appendingPathExtension("wav")
        }
        let data = await audioFiles.load(
            cachedURL: cacheURL(for: entry.sha256), bundledURL: bundledURL, sha256: entry.sha256
        )
        guard !Task.isCancelled, let data else { return nil }
        remember(data, checksum: entry.sha256)
        return data
    }

    // A supplied transcript protects sentence cues from mismatched recorded speech.
    // Fixed countdown callers omit it: "3" and localized spoken "Three." are
    // equivalent countdown beats but deliberately not text-equivalent sentences.
    private func matchingEntry(cueKey: String, transcript: String?) -> Entry? {
        let locale = localeIdentifier()
        let candidates = availableEntries.filter {
            $0.cueKey == cueKey
                && $0.locale == locale
                && $0.voiceProfileId == voiceProfileID
                && $0.compatibleCoachPersonaIds.contains(coachPersonaID)
                && (transcript == nil || normalize($0.transcript) == normalize(transcript!))
        }
        if let styled = candidates.first(where: { $0.scriptStyleId == scriptStyleID }) { return styled }
        if let standard = candidates.first(where: { $0.scriptStyleId == "standard" }) { return standard }
        guard let transcript else { return nil }
        let normalized = normalize(transcript)
        return availableEntries.first {
            $0.locale == locale
                && $0.voiceProfileId == voiceProfileID
                && $0.compatibleCoachPersonaIds.contains(coachPersonaID)
                && normalize($0.transcript) == normalized
        }
    }

    // An older downloaded pack cannot hide the app's purpose-built recordings.
    // Keep normal sentence matching and selected locale/voice/persona checks.
    private var availableEntries: [Entry] {
        (bundledManifest?.entries ?? []) + (manifest?.entries ?? [])
    }

    private func loadCachedManifest() -> Manifest? {
        guard let data = try? Data(contentsOf: manifestCacheURL),
              let decoded = try? JSONDecoder().decode(Manifest.self, from: data),
              decoded.contractVersion == 1,
              decoded.entries.allSatisfy({ $0.approved && $0.contentType == "audio/wav" })
        else { return nil }
        return decoded
    }

    private func loadBundledManifest() -> Manifest? {
        guard let url = bundledAudioDirectory?.appendingPathComponent("manifest.json"),
        let data = try? Data(contentsOf: url),
        let decoded = try? JSONDecoder().decode(Manifest.self, from: data),
        decoded.contractVersion == 1,
        decoded.entries.allSatisfy({
            $0.approved && $0.contentType == "audio/wav" && $0.bundledResourceName != nil
        })
        else { return nil }
        return decoded
    }

    private func verifiedRemoteManifest(from data: Data) throws -> (manifest: Manifest, payload: Data) {
        let envelope = try JSONDecoder().decode(SignedManifestEnvelope.self, from: data)
        guard envelope.contractVersion == 1,
              envelope.signature.algorithm == "ES256",
              let payload = Data(base64URLEncoded: envelope.payload),
              let signatureData = Data(base64URLEncoded: envelope.signature.value),
              let keyMap = Bundle.main.object(forInfoDictionaryKey: "LiveCoachAudioManifestPublicKeys") as? [String: String],
              let publicKeyPEM = keyMap[envelope.signature.keyId]
        else { throw GuideAudioPackError.untrustedManifest }
        let publicKey = try P256.Signing.PublicKey(pemRepresentation: publicKeyPEM)
        let signature = try P256.Signing.ECDSASignature(derRepresentation: signatureData)
        guard publicKey.isValidSignature(signature, for: payload) else {
            throw GuideAudioPackError.untrustedManifest
        }
        return (try JSONDecoder().decode(Manifest.self, from: payload), payload)
    }

    private var cacheDirectory: URL {
        if let cacheDirectoryOverride { return cacheDirectoryOverride }
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Plainstride/LiveCoachAudio", isDirectory: true)
    }

    private var manifestCacheURL: URL {
        cacheDirectory.appendingPathComponent("last-known-good-manifest.json")
    }

    private func cacheURL(for sha256: String) -> URL {
        cacheDirectory.appendingPathComponent("\(sha256).wav")
    }

    private func checksum(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func normalize(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: "[^\\p{L}\\p{N}]", with: "", options: .regularExpression)
    }
}

private enum GuideAudioPackError: Error {
    case untrustedManifest
}

private extension Data {
    init?(base64URLEncoded value: String) {
        var normalized = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        normalized += String(repeating: "=", count: (4 - normalized.count % 4) % 4)
        self.init(base64Encoded: normalized)
    }
}

/// Reads and hashes reviewed audio away from the UI executor. Only verified
/// bytes cross back into the main-actor, bounded memory cache.
private actor VerifiedGuideAudioFiles {
    func load(cachedURL: URL, bundledURL: URL?, sha256: String) -> Data? {
        for url in [cachedURL, bundledURL].compactMap({ $0 }) {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                let values = try url.resourceValues(forKeys: [.fileSizeKey])
                guard (values.fileSize ?? Int.max) <= 512 * 1024 else { continue }
                let data = try Data(contentsOf: url)
                if isVerified(data, sha256: sha256) { return data }
                log("Coach local audio checksum rejected")
            } catch {
                let technical = error as NSError
                log("Coach local audio read failed domain=\(technical.domain) code=\(technical.code)")
            }
        }
        return nil
    }

    func verifyAndStore(_ data: Data, sha256: String, url: URL) -> Bool {
        guard isVerified(data, sha256: sha256) else {
            log("Coach downloaded audio checksum rejected")
            return false
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            let technical = error as NSError
            log("Coach audio cache write failed domain=\(technical.domain) code=\(technical.code)")
            // Verified bytes remain usable in memory if disk caching fails.
        }
        return true
    }

    private func isVerified(_ data: Data, sha256: String) -> Bool {
        data.count <= 512 * 1024
            && SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == sha256
    }

    private func log(_ message: String) {
        Task { @MainActor in ActivityDiagnosticLog.error(.lifecycle, message) }
    }
}
