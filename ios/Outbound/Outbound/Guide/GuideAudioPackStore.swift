import CryptoKit
import Foundation

@MainActor
final class GuideAudioPackStore {
    static let shared = GuideAudioPackStore()

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

    private var manifest: Manifest?
    private var coachPersonaID = "plainstride_supportive_v1"
    private var voiceProfileID = "plainstride_warm_1"
    private var scriptStyleID = "standard"
    private let fileManager = FileManager.default

    private init() {
        manifest = loadCachedManifest() ?? loadBundledManifest()
    }

    func select(coachPersonaID: String, voiceProfileID: String, scriptStyleID: String) {
        self.coachPersonaID = coachPersonaID
        self.voiceProfileID = voiceProfileID
        self.scriptStyleID = scriptStyleID
    }

    func refresh(from url: URL, expectedCatalogVersion: String) async {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
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
        } catch {
            // Keep the last known-good manifest and bundled fallback state.
        }
    }

    func audioData(for cueKey: String, transcript: String? = nil) async -> Data? {
        guard let entry = matchingEntry(cueKey: cueKey, transcript: transcript) else { return nil }
        if let local = localAudioData(for: entry) { return local }
        guard let url = entry.url else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true,
                  data.count <= 512 * 1024,
                  checksum(data) == entry.sha256
            else { return nil }
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try data.write(to: cacheURL(for: entry.sha256), options: .atomic)
            return data
        } catch {
            return nil
        }
    }

    func localAudioData(for cueKey: String, transcript: String? = nil) -> Data? {
        guard let entry = matchingEntry(cueKey: cueKey, transcript: transcript) else { return nil }
        return localAudioData(for: entry)
    }

    private func localAudioData(for entry: Entry) -> Data? {
        let cachedURL = cacheURL(for: entry.sha256)
        if let data = try? Data(contentsOf: cachedURL), checksum(data) == entry.sha256 {
            return data
        }
        if let resourceName = entry.bundledResourceName,
           let resourceURL = Bundle.main.url(
               forResource: resourceName,
               withExtension: "wav",
               subdirectory: "LiveCoachAudio"
           ),
           let data = try? Data(contentsOf: resourceURL),
            checksum(data) == entry.sha256 {
            return data
        }
        return nil
    }

    private func matchingEntry(cueKey: String, transcript: String?) -> Entry? {
        let locale = AppLanguage.currentIdentifier
        let candidates = manifest?.entries.filter {
            $0.cueKey == cueKey
                && $0.locale == locale
                && $0.voiceProfileId == voiceProfileID
                && $0.compatibleCoachPersonaIds.contains(coachPersonaID)
        } ?? []
        if let styled = candidates.first(where: { $0.scriptStyleId == scriptStyleID }) { return styled }
        if let standard = candidates.first(where: { $0.scriptStyleId == "standard" }) { return standard }
        guard let transcript else { return nil }
        let normalized = normalize(transcript)
        return manifest?.entries.first {
            $0.locale == locale
                && $0.voiceProfileId == voiceProfileID
                && $0.compatibleCoachPersonaIds.contains(coachPersonaID)
                && normalize($0.transcript) == normalized
        }
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
        guard let url = Bundle.main.url(
            forResource: "manifest",
            withExtension: "json",
            subdirectory: "LiveCoachAudio"
        ),
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
