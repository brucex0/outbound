import Foundation
import Security

protocol SessionPersisting: Sendable {
    func load() throws -> AuthSession?
    func replace(_ session: AuthSession) throws
    func delete() throws
}

struct KeychainSessionRepository: SessionPersisting {
    private let service = "plainstride.outbound.auth-session"
    private let account = "current"

    func load() throws -> AuthSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw KeychainError(status) }
        return try decoder.decode(AuthSession.self, from: data)
    }

    func replace(_ session: AuthSession) throws {
        let data = try encoder.encode(session)
        SecItemDelete(baseQuery as CFDictionary)
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status) }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status) }
    }

    private var baseQuery: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] }
    private var encoder: JSONEncoder { let value = JSONEncoder(); value.dateEncodingStrategy = .iso8601; return value }
    private var decoder: JSONDecoder { let value = JSONDecoder(); value.dateDecodingStrategy = .iso8601; return value }
}

private struct KeychainError: LocalizedError { let status: OSStatus; init(_ status: OSStatus) { self.status = status }; var errorDescription: String? { "Keychain error \(status)" } }
