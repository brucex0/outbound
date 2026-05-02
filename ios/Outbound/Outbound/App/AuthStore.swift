import Foundation
import Combine
import FirebaseAuth

@MainActor
final class AuthStore: ObservableObject {
    enum Backend {
        case firebase
        case local
    }

    enum AuthIdentifier: Equatable {
        case email(String)
        case phone(String)

        var normalizedCredentialEmail: String {
            switch self {
            case let .email(email):
                return email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            case let .phone(phone):
                let digits = phone.filter(\.isNumber)
                return "phone.\(digits)@users.outbound.local"
            }
        }

        var displayValue: String {
            switch self {
            case let .email(email):
                return email.trimmingCharacters(in: .whitespacesAndNewlines)
            case let .phone(phone):
                return phone.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    @Published var isAuthenticated = false
    @Published var isFirebaseConfigured = FirebaseBootstrap.isConfigured
    @Published var isBusy = false
    @Published var authError: String?
    @Published var user: FirebaseAuth.User?
    @Published var localSessionLabel: String?
    @Published private(set) var backend: Backend = .local

    private var authStateListener: AuthStateDidChangeListenerHandle?
    private let localCredentialStore: LocalCredentialStore

    static var currentUserId: String? {
        guard FirebaseBootstrap.isConfigured else { return nil }
        return Auth.auth().currentUser?.uid
    }

    init(localCredentialStore: LocalCredentialStore = LocalCredentialStore()) {
        self.localCredentialStore = localCredentialStore
        isFirebaseConfigured = FirebaseBootstrap.configureIfAvailable()
        backend = isFirebaseConfigured ? .firebase : .local

        if !isFirebaseConfigured {
            isAuthenticated = false
            localSessionLabel = nil
            return
        }

        user = Auth.auth().currentUser
        isAuthenticated = user != nil

        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.user = user
                self?.isAuthenticated = user != nil
                self?.localSessionLabel = nil
                let token = try? await user?.getIDToken()
                APIClient.shared.setToken(token)
            }
        }
    }

    deinit {
        if FirebaseBootstrap.isConfigured, let authStateListener {
            Auth.auth().removeStateDidChangeListener(authStateListener)
        }
    }

    var currentLoginLabel: String? {
        if let user {
            if let email = user.email {
                return Self.displayIdentifier(fromStoredEmail: email)
            }

            return user.phoneNumber
        }

        return localSessionLabel
    }

    var backendDescription: String {
        switch backend {
        case .firebase:
            return "Firebase account"
        case .local:
            return "Stored only on this device"
        }
    }

    func startLocalSession(label: String = "Local session") {
        backend = .local
        isAuthenticated = true
        user = nil
        authError = nil
        localSessionLabel = label
        APIClient.shared.setToken(nil)
    }

    func signOut() {
        guard isFirebaseConfigured else {
            backend = .local
            isAuthenticated = false
            user = nil
            localSessionLabel = nil
            authError = nil
            localCredentialStore.setActiveAccount(nil)
            APIClient.shared.setToken(nil)
            return
        }

        backend = .firebase
        try? Auth.auth().signOut()
        isAuthenticated = false
        user = nil
        localSessionLabel = nil
        authError = nil
        APIClient.shared.setToken(nil)
    }

    func signIn(identifier rawIdentifier: String, password: String) async {
        guard isFirebaseConfigured else {
            authError = "Firebase configuration is missing. Add GoogleService-Info.plist to use real sign-in."
            return
        }

        do {
            let identifier = try Self.parseIdentifier(rawIdentifier)
            let password = try Self.validatePassword(password)

            isBusy = true
            authError = nil
            defer { isBusy = false }

            backend = .firebase
            let result = try await Auth.auth().signIn(
                withEmail: identifier.normalizedCredentialEmail,
                password: password
            )

            user = result.user
            isAuthenticated = true
            localSessionLabel = nil
            let token = try? await result.user.getIDToken()
            APIClient.shared.setToken(token)
        } catch {
            authError = Self.userFacingMessage(for: error)
        }
    }

    func signInWithGoogle() async {
        guard isFirebaseConfigured else {
            authError = "Google sign-in is only available when Firebase is configured for this build."
            return
        }

        do {
            isBusy = true
            authError = nil
            defer { isBusy = false }

            backend = .firebase
            let provider = OAuthProvider.provider(providerID: .google)
            provider.scopes = ["email"]
            provider.customParameters = ["prompt": "select_account"]

            let result = try await Auth.auth().signIn(with: provider, uiDelegate: nil)
            user = result.user
            isAuthenticated = true
            localSessionLabel = nil
            let token = try? await result.user.getIDToken()
            APIClient.shared.setToken(token)
        } catch {
            authError = Self.userFacingMessage(for: error)
        }
    }

    func createAccount(identifier rawIdentifier: String, password: String, confirmPassword: String) async {
        guard isFirebaseConfigured else {
            authError = "Firebase configuration is missing. Add GoogleService-Info.plist to create a real account."
            return
        }

        do {
            let identifier = try Self.parseIdentifier(rawIdentifier)
            let password = try Self.validatePassword(password)
            guard password == confirmPassword else {
                throw AuthInputError.passwordsDoNotMatch
            }

            isBusy = true
            authError = nil
            defer { isBusy = false }

            backend = .firebase
            let result = try await Auth.auth().createUser(
                withEmail: identifier.normalizedCredentialEmail,
                password: password
            )

            user = result.user
            isAuthenticated = true
            localSessionLabel = nil
            let token = try? await result.user.getIDToken()
            APIClient.shared.setToken(token)
        } catch {
            authError = Self.userFacingMessage(for: error)
        }
    }

    private static func parseIdentifier(_ rawValue: String) throws -> AuthIdentifier {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AuthInputError.emptyIdentifier
        }

        if trimmed.contains("@") {
            guard isLikelyEmail(trimmed) else {
                throw AuthInputError.invalidEmail
            }

            return .email(trimmed)
        }

        let digits = trimmed.filter(\.isNumber)
        guard digits.count >= 7 else {
            throw AuthInputError.invalidPhone
        }

        return .phone(trimmed)
    }

    private static func validatePassword(_ rawValue: String) throws -> String {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 6 else {
            throw AuthInputError.passwordTooShort
        }

        return value
    }

    private static func isLikelyEmail(_ value: String) -> Bool {
        let parts = value.split(separator: "@")
        guard parts.count == 2 else { return false }
        return parts[1].contains(".")
    }

    private static func displayIdentifier(fromStoredEmail email: String) -> String {
        let prefix = "phone."
        let suffix = "@users.outbound.local"

        guard email.hasPrefix(prefix), email.hasSuffix(suffix) else {
            return email
        }

        let start = email.index(email.startIndex, offsetBy: prefix.count)
        let end = email.index(email.endIndex, offsetBy: -suffix.count)
        let digits = String(email[start..<end])
        return digits.isEmpty ? email : digits
    }

    private static func userFacingMessage(for error: Error) -> String {
        if let inputError = error as? AuthInputError {
            return inputError.localizedDescription
        }

        if let localError = error as? LocalCredentialStoreError {
            return localError.localizedDescription
        }

        if let authError = error as NSError?, authError.domain == AuthErrorDomain {
            switch AuthErrorCode(rawValue: authError.code) {
            case .invalidEmail:
                return "Enter a valid email address."
            case .wrongPassword, .invalidCredential:
                return "That password is incorrect."
            case .userNotFound:
                return "No account matches that email or phone number."
            case .emailAlreadyInUse:
                return "An account with that email or phone number already exists."
            case .weakPassword:
                return "Choose a stronger password with at least 6 characters."
            case .networkError:
                return "Network error. Check your connection and try again."
            case .webContextCancelled:
                return "Google sign-in was canceled."
            case .webNetworkRequestFailed:
                return "Google sign-in could not reach the network. Check your connection and try again."
            case .webInternalError, .webSignInUserInteractionFailure:
                return "Google sign-in could not be completed. Try again in a moment."
            case .accountExistsWithDifferentCredential:
                return "An account already exists for that email with a different sign-in method."
            default:
                break
            }
        }

        return error.localizedDescription
    }
}

private enum AuthInputError: LocalizedError {
    case emptyIdentifier
    case invalidEmail
    case invalidPhone
    case passwordTooShort
    case passwordsDoNotMatch

    var errorDescription: String? {
        switch self {
        case .emptyIdentifier:
            return "Enter an email address or phone number."
        case .invalidEmail:
            return "Enter a valid email address."
        case .invalidPhone:
            return "Enter a valid phone number."
        case .passwordTooShort:
            return "Password must be at least 6 characters."
        case .passwordsDoNotMatch:
            return "Passwords do not match."
        }
    }
}
