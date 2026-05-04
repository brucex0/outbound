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

    struct PendingFederatedLink: Equatable {
        let email: String
        let providerName: String
    }

    @Published var isAuthenticated = false
    @Published var isFirebaseConfigured = FirebaseBootstrap.isConfigured
    @Published var isBusy = false
    @Published var authError: String?
    @Published var user: FirebaseAuth.User?
    @Published var localSessionLabel: String?
    @Published private(set) var pendingFederatedLink: PendingFederatedLink?
    @Published private(set) var backend: Backend = .local

    private var authStateListener: AuthStateDidChangeListenerHandle?
    private let localCredentialStore: LocalCredentialStore
    private var pendingFederatedCredential: AuthCredential?

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

            if let providerEmail = user.providerData.compactMap(\.email).first {
                return Self.displayIdentifier(fromStoredEmail: providerEmail)
            }

            return user.phoneNumber
        }

        return localSessionLabel
    }

    var connectedProviderLabels: [String] {
        guard let user else {
            return backend == .local ? ["Local"] : []
        }

        let providerIDs = Set(user.providerData.map(\.providerID))
        var labels: [String] = []
        if providerIDs.contains("google.com") {
            labels.append("Google")
        }
        if providerIDs.contains("password") {
            labels.append(Self.isPhoneAlias(user.email) ? "Phone" : "Email")
        }
        if providerIDs.contains("phone") {
            labels.append("Phone")
        }

        return labels.isEmpty ? ["Firebase"] : labels
    }

    var isGoogleLinked: Bool {
        user?.providerData.contains { $0.providerID == "google.com" } == true
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
        pendingFederatedLink = nil
        pendingFederatedCredential = nil
        APIClient.shared.setToken(nil)
    }

    func signOut() {
        guard isFirebaseConfigured else {
            backend = .local
            isAuthenticated = false
            user = nil
            localSessionLabel = nil
            authError = nil
            pendingFederatedLink = nil
            pendingFederatedCredential = nil
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
        pendingFederatedLink = nil
        pendingFederatedCredential = nil
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
            let credentialEmail = identifier.normalizedCredentialEmail
            let result = try await Auth.auth().signIn(
                withEmail: credentialEmail,
                password: password
            )
            let resolvedResult = try await linkPendingFederatedCredentialIfNeeded(
                after: result,
                signedInEmail: credentialEmail
            )

            await completeSignIn(with: resolvedResult)
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
            print("[Outbound][Auth] Starting Google sign-in flow.")
            let provider = Self.makeGoogleProvider()
            let result = try await Auth.auth().signIn(with: provider, uiDelegate: nil)
            print("[Outbound][Auth] Google sign-in completed for user: \(result.user.uid)")
            pendingFederatedLink = nil
            pendingFederatedCredential = nil
            await completeSignIn(with: result)
        } catch {
            print("[Outbound][Auth] Google sign-in failed: \(error.localizedDescription)")
            if !storePendingFederatedLink(from: error, providerName: "Google") {
                authError = Self.userFacingMessage(for: error)
            }
        }
    }

    func connectGoogleAccount() async {
        guard isFirebaseConfigured else {
            authError = "Google sign-in is only available when Firebase is configured for this build."
            return
        }

        guard let currentUser = Auth.auth().currentUser else {
            authError = "Sign in before connecting Google."
            return
        }

        guard !isGoogleLinked else {
            authError = nil
            user = currentUser
            return
        }

        do {
            isBusy = true
            authError = nil
            defer { isBusy = false }

            let result = try await currentUser.link(with: Self.makeGoogleProvider(), uiDelegate: nil)
            print("[Outbound][Auth] Google linked for user: \(result.user.uid)")
            await completeSignIn(with: result, forcingTokenRefresh: true)
        } catch {
            print("[Outbound][Auth] Google link failed: \(error.localizedDescription)")
            authError = Self.userFacingMessage(for: error)
        }
    }

    func handleOpenURL(_ url: URL) -> Bool {
        guard isFirebaseConfigured else { return false }
        let handled = Auth.auth().canHandle(url)
        print("[Outbound][Auth] handleOpenURL handled=\(handled) url=\(url.absoluteString)")
        return handled
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

            await completeSignIn(with: result)
        } catch {
            authError = Self.userFacingMessage(for: error)
        }
    }

    private static func makeGoogleProvider() -> OAuthProvider {
        let provider = OAuthProvider.provider(providerID: .google)
        provider.scopes = ["email", "profile"]
        provider.customParameters = ["prompt": "select_account"]
        return provider
    }

    private func completeSignIn(
        with result: AuthDataResult,
        forcingTokenRefresh: Bool = false
    ) async {
        user = result.user
        isAuthenticated = true
        localSessionLabel = nil
        pendingFederatedLink = nil
        pendingFederatedCredential = nil
        let token = try? await result.user.getIDToken(forcingRefresh: forcingTokenRefresh)
        APIClient.shared.setToken(token)
    }

    private func linkPendingFederatedCredentialIfNeeded(
        after result: AuthDataResult,
        signedInEmail: String
    ) async throws -> AuthDataResult {
        guard let pendingFederatedLink, let pendingFederatedCredential else {
            return result
        }

        guard Self.normalizedEmail(pendingFederatedLink.email) == signedInEmail else {
            throw AuthInputError.pendingLinkEmailMismatch(pendingFederatedLink.email)
        }

        if result.user.providerData.contains(where: { $0.providerID == pendingFederatedCredential.provider }) {
            self.pendingFederatedLink = nil
            self.pendingFederatedCredential = nil
            return result
        }

        do {
            let linkedResult = try await result.user.link(with: pendingFederatedCredential)
            _ = try? await linkedResult.user.getIDToken(forcingRefresh: true)
            self.pendingFederatedLink = nil
            self.pendingFederatedCredential = nil
            return linkedResult
        } catch {
            if Self.authErrorCode(for: error) == .providerAlreadyLinked {
                self.pendingFederatedLink = nil
                self.pendingFederatedCredential = nil
                return result
            }

            throw error
        }
    }

    @discardableResult
    private func storePendingFederatedLink(from error: Error, providerName: String) -> Bool {
        guard
            Self.authErrorCode(for: error) == .accountExistsWithDifferentCredential,
            let nsError = error as NSError?,
            let credential = nsError.userInfo[AuthErrorUserInfoUpdatedCredentialKey] as? AuthCredential,
            let email = nsError.userInfo[AuthErrorUserInfoEmailKey] as? String
        else {
            return false
        }

        pendingFederatedCredential = credential
        pendingFederatedLink = PendingFederatedLink(email: email, providerName: providerName)
        self.authError = "Enter the password for \(email) once to connect \(providerName) to the same Outbound account."
        return true
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

    private static func normalizedEmail(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func isPhoneAlias(_ email: String?) -> Bool {
        guard let email else { return false }
        let normalized = normalizedEmail(email)
        return normalized.hasPrefix("phone.") && normalized.hasSuffix("@users.outbound.local")
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
            case .providerAlreadyLinked:
                return "Google is already connected to this account."
            case .credentialAlreadyInUse:
                return "That Google account is already connected to another Outbound sign-in."
            default:
                break
            }
        }

        return error.localizedDescription
    }

    private static func authErrorCode(for error: Error) -> AuthErrorCode? {
        guard let authError = error as NSError?, authError.domain == AuthErrorDomain else {
            return nil
        }

        return AuthErrorCode(rawValue: authError.code)
    }
}

private enum AuthInputError: LocalizedError {
    case emptyIdentifier
    case invalidEmail
    case invalidPhone
    case passwordTooShort
    case passwordsDoNotMatch
    case pendingLinkEmailMismatch(String)

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
        case let .pendingLinkEmailMismatch(email):
            return "Sign in as \(email) to finish connecting this provider."
        }
    }
}
