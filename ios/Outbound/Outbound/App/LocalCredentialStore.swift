import Foundation
import Security

struct LocalAccountRecord: Codable, Equatable {
    let identifierKey: String
    let displayIdentifier: String
    let createdAt: Date
}

enum LocalCredentialStoreError: LocalizedError {
    case accountAlreadyExists
    case accountNotFound
    case invalidPassword
    case unexpectedStatus(OSStatus)
    case invalidStoredData

    var errorDescription: String? {
        switch self {
        case .accountAlreadyExists:
            return "An account with that email or phone number already exists on this device."
        case .accountNotFound:
            return "No local account matches that email or phone number."
        case .invalidPassword:
            return "That password is incorrect."
        case let .unexpectedStatus(status):
            return "Local login failed with status \(status)."
        case .invalidStoredData:
            return "Stored local login data is invalid."
        }
    }
}

final class LocalCredentialStore {
    private let defaults: UserDefaults
    private let service = "run.outbound.local-auth"
    private let accountListKey = "local_auth_accounts_v1"
    private let activeAccountKey = "local_auth_active_account_v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func activeAccount() throws -> LocalAccountRecord? {
        guard let identifierKey = defaults.string(forKey: activeAccountKey) else {
            return nil
        }

        return try accounts().first(where: { $0.identifierKey == identifierKey })
    }

    func setActiveAccount(_ account: LocalAccountRecord?) {
        defaults.set(account?.identifierKey, forKey: activeAccountKey)
    }

    func createAccount(identifierKey: String, displayIdentifier: String, password: String) throws -> LocalAccountRecord {
        var existingAccounts = try accounts()
        guard !existingAccounts.contains(where: { $0.identifierKey == identifierKey }) else {
            throw LocalCredentialStoreError.accountAlreadyExists
        }

        try savePassword(password, for: identifierKey)

        let record = LocalAccountRecord(
            identifierKey: identifierKey,
            displayIdentifier: displayIdentifier,
            createdAt: Date()
        )
        existingAccounts.append(record)
        try saveAccounts(existingAccounts)
        setActiveAccount(record)
        return record
    }

    func signIn(identifierKey: String, password: String) throws -> LocalAccountRecord {
        let allAccounts = try accounts()
        guard let account = allAccounts.first(where: { $0.identifierKey == identifierKey }) else {
            throw LocalCredentialStoreError.accountNotFound
        }

        let storedPassword = try storedPassword(for: identifierKey)
        guard storedPassword == password else {
            throw LocalCredentialStoreError.invalidPassword
        }

        setActiveAccount(account)
        return account
    }

    private func accounts() throws -> [LocalAccountRecord] {
        guard let data = defaults.data(forKey: accountListKey) else {
            return []
        }

        do {
            return try JSONDecoder().decode([LocalAccountRecord].self, from: data)
        } catch {
            throw LocalCredentialStoreError.invalidStoredData
        }
    }

    private func saveAccounts(_ accounts: [LocalAccountRecord]) throws {
        let data = try JSONEncoder().encode(accounts)
        defaults.set(data, forKey: accountListKey)
    }

    private func savePassword(_ password: String, for identifierKey: String) throws {
        let encodedPassword = Data(password.utf8)
        let query = keychainQuery(for: identifierKey)

        let existingStatus = SecItemCopyMatching(query as CFDictionary, nil)
        if existingStatus == errSecSuccess {
            let attributes = [kSecValueData as String: encodedPassword]
            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw LocalCredentialStoreError.unexpectedStatus(updateStatus)
            }
            return
        }

        if existingStatus != errSecItemNotFound {
            throw LocalCredentialStoreError.unexpectedStatus(existingStatus)
        }

        var newItem = query
        newItem[kSecValueData as String] = encodedPassword
        let addStatus = SecItemAdd(newItem as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw LocalCredentialStoreError.unexpectedStatus(addStatus)
        }
    }

    private func storedPassword(for identifierKey: String) throws -> String {
        var query = keychainQuery(for: identifierKey)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw LocalCredentialStoreError.accountNotFound
            }

            throw LocalCredentialStoreError.unexpectedStatus(status)
        }

        guard let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw LocalCredentialStoreError.invalidStoredData
        }

        return password
    }

    private func keychainQuery(for identifierKey: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identifierKey
        ]
    }
}
