import Foundation
import Security

protocol SessionPersisting: Sendable {
    nonisolated func load() throws -> AuthSession?
    nonisolated func replace(_ session: AuthSession) throws
    nonisolated func delete() throws
}

struct KeychainSessionRepository: SessionPersisting {
    private let service = "plainstride.outbound.auth-session"
    private let account = "current"

    nonisolated init() {}

    nonisolated func load() throws -> AuthSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw KeychainError(status) }
        return try decoder.decode(AuthSession.self, from: data)
    }

    nonisolated func replace(_ session: AuthSession) throws {
        let data = try encoder.encode(session)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var query = baseQuery
            attributes.forEach { query[$0.key] = $0.value }
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status)
        }
    }

    nonisolated func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status) }
    }

    nonisolated private var baseQuery: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] }
    nonisolated private var encoder: JSONEncoder { let value = JSONEncoder(); value.dateEncodingStrategy = .iso8601; return value }
    nonisolated private var decoder: JSONDecoder { let value = JSONDecoder(); value.dateDecodingStrategy = .iso8601; return value }
}

private struct KeychainError: LocalizedError {
    let status: OSStatus
    nonisolated init(_ status: OSStatus) { self.status = status }
    nonisolated var errorDescription: String? { "Keychain error \(status)" }
}
