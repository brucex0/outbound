import Foundation
import Combine
import FirebaseAuth
import AuthenticationServices
import CryptoKit
import Security
import UIKit

@MainActor
final class AuthStore: ObservableObject {
    enum Backend {
        case firebase
        case local
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
    private var pendingFederatedCredential: AuthCredential?
    private var appleAuthorizationCoordinator: AppleAuthorizationCoordinator?

    static var currentUserId: String? {
        guard FirebaseBootstrap.isConfigured else { return nil }
        return Auth.auth().currentUser?.uid
    }

    init() {
        if ProcessInfo.processInfo.arguments.contains("-OutboundDisableFirebase") {
            backend = .local
            isAuthenticated = true
            user = nil
            localSessionLabel = "UI test session"
            APIClient.shared.setToken(nil)
            return
        }

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
        if providerIDs.contains("apple.com") {
            labels.append("Apple")
        }
        if providerIDs.contains("password") {
            labels.append("Legacy email")
        }

        return labels.isEmpty ? ["Firebase"] : labels
    }

    var isGoogleLinked: Bool {
        user?.providerData.contains { $0.providerID == "google.com" } == true
    }

    var isAppleLinked: Bool {
        user?.providerData.contains { $0.providerID == "apple.com" } == true
    }

    var isAppleSignInAvailable: Bool {
        isFirebaseConfigured && Self.hasAppleSignInEntitlement()
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
            let resolvedResult = try await linkPendingFederatedCredentialIfNeeded(after: result)
            print("[Outbound][Auth] Google sign-in completed for user: \(result.user.uid)")
            await completeSignIn(with: resolvedResult)
        } catch {
            print("[Outbound][Auth] Google sign-in failed: \(error.localizedDescription)")
            if !storePendingFederatedLink(from: error) {
                resetFirebaseSessionPreservingPendingLinkIfNeeded()
                authError = Self.userFacingMessage(for: error)
            }
        }
    }

    func signInWithApple() async {
        guard isFirebaseConfigured else {
            authError = "Apple sign-in is only available when Firebase is configured for this build."
            return
        }

        guard Self.hasAppleSignInEntitlement() else {
            authError = "Apple sign-in needs a provisioning profile with the Sign in with Apple capability."
            return
        }

        do {
            isBusy = true
            authError = nil
            defer { isBusy = false }

            backend = .firebase
            print("[Outbound][Auth] Starting Apple sign-in flow.")
            let credential = try await makeAppleCredential()
            let result = try await Auth.auth().signIn(with: credential)
            let resolvedResult = try await linkPendingFederatedCredentialIfNeeded(after: result)
            print("[Outbound][Auth] Apple sign-in completed for user: \(result.user.uid)")
            await completeSignIn(with: resolvedResult)
        } catch {
            print("[Outbound][Auth] Apple sign-in failed: \(error.localizedDescription)")
            if !storePendingFederatedLink(from: error) {
                resetFirebaseSessionPreservingPendingLinkIfNeeded()
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

    func connectAppleAccount() async {
        guard isFirebaseConfigured else {
            authError = "Apple sign-in is only available when Firebase is configured for this build."
            return
        }

        guard Self.hasAppleSignInEntitlement() else {
            authError = "Apple sign-in needs a provisioning profile with the Sign in with Apple capability."
            return
        }

        guard let currentUser = Auth.auth().currentUser else {
            authError = "Sign in before connecting Apple."
            return
        }

        guard !isAppleLinked else {
            authError = nil
            user = currentUser
            return
        }

        do {
            isBusy = true
            authError = nil
            defer { isBusy = false }

            let credential = try await makeAppleCredential()
            let result = try await currentUser.link(with: credential)
            print("[Outbound][Auth] Apple linked for user: \(result.user.uid)")
            await completeSignIn(with: result, forcingTokenRefresh: true)
        } catch {
            print("[Outbound][Auth] Apple link failed: \(error.localizedDescription)")
            authError = Self.userFacingMessage(for: error)
        }
    }

    func handleOpenURL(_ url: URL) -> Bool {
        guard isFirebaseConfigured else { return false }
        let handled = Auth.auth().canHandle(url)
        print("[Outbound][Auth] handleOpenURL handled=\(handled) url=\(url.absoluteString)")
        return handled
    }

    private static func makeGoogleProvider() -> OAuthProvider {
        let provider = OAuthProvider.provider(providerID: .google)
        provider.scopes = ["email", "profile"]
        provider.customParameters = ["prompt": "select_account"]
        return provider
    }

    private static func hasAppleSignInEntitlement() -> Bool {
        #if APPLE_SIGN_IN_ENABLED
            return true
        #else
            return false
        #endif
    }

    private func makeAppleCredential() async throws -> AuthCredential {
        let coordinator = AppleAuthorizationCoordinator()
        appleAuthorizationCoordinator = coordinator
        defer { appleAuthorizationCoordinator = nil }
        return try await coordinator.credential()
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

    private func resetFirebaseSessionPreservingPendingLinkIfNeeded() {
        guard pendingFederatedLink != nil, Auth.auth().currentUser != nil else {
            return
        }

        let link = pendingFederatedLink
        let credential = pendingFederatedCredential
        try? Auth.auth().signOut()
        user = nil
        isAuthenticated = false
        localSessionLabel = nil
        APIClient.shared.setToken(nil)
        pendingFederatedLink = link
        pendingFederatedCredential = credential
    }

    private func linkPendingFederatedCredentialIfNeeded(after result: AuthDataResult) async throws -> AuthDataResult {
        guard let pendingFederatedLink, let pendingFederatedCredential else {
            return result
        }

        let signedInEmails = Self.normalizedEmails(for: result.user)
        guard signedInEmails.contains(Self.normalizedEmail(pendingFederatedLink.email)) else {
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
    private func storePendingFederatedLink(from error: Error) -> Bool {
        guard
            Self.authErrorCode(for: error) == .accountExistsWithDifferentCredential,
            let nsError = error as NSError?,
            let credential = nsError.userInfo[AuthErrorUserInfoUpdatedCredentialKey] as? AuthCredential,
            let email = nsError.userInfo[AuthErrorUserInfoEmailKey] as? String
        else {
            return false
        }

        pendingFederatedCredential = credential
        let providerName = Self.providerName(for: credential.provider)
        pendingFederatedLink = PendingFederatedLink(email: email, providerName: providerName)
        self.authError = "\(providerName) matches an existing Outbound account for \(email). Continue with the existing provider once to connect both sign-in methods."
        return true
    }

    private static func normalizedEmail(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedEmails(for user: FirebaseAuth.User) -> Set<String> {
        var emails = Set<String>()
        if let email = user.email {
            emails.insert(normalizedEmail(email))
        }
        for profile in user.providerData {
            if let email = profile.email {
                emails.insert(normalizedEmail(email))
            }
        }
        return emails
    }

    private static func providerName(for providerID: String) -> String {
        switch providerID {
        case "google.com":
            return "Google"
        case "apple.com":
            return "Apple"
        case "password":
            return "Email"
        default:
            return "That provider"
        }
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

        if let appleError = error as? AppleAuthorizationError {
            return appleError.localizedDescription
        }

        if let authorizationError = error as? ASAuthorizationError,
           authorizationError.code == .canceled {
            return "Apple sign-in was canceled."
        }

        if let authError = error as NSError?, authError.domain == AuthErrorDomain {
            switch AuthErrorCode(rawValue: authError.code) {
            case .invalidEmail:
                return "Enter a valid email address."
            case .wrongPassword, .invalidCredential:
                return "That sign-in could not be verified."
            case .userNotFound:
                return "No account matches that sign-in method."
            case .emailAlreadyInUse:
                return "An account with that email already exists."
            case .networkError:
                return "Network error. Check your connection and try again."
            case .webContextCancelled:
                return "Sign-in was canceled."
            case .webNetworkRequestFailed:
                return "Sign-in could not reach the network. Check your connection and try again."
            case .webInternalError, .webSignInUserInteractionFailure:
                return "Sign-in could not be completed. Try again in a moment."
            case .accountExistsWithDifferentCredential:
                return "An account already exists for that email with a different sign-in method."
            case .providerAlreadyLinked:
                return "That sign-in method is already connected to this account."
            case .credentialAlreadyInUse:
                return "That sign-in method is already connected to another Outbound account."
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
    case pendingLinkEmailMismatch(String)

    var errorDescription: String? {
        switch self {
        case let .pendingLinkEmailMismatch(email):
            return "Sign in with the account already connected to \(email) to finish linking this provider."
        }
    }
}

private enum AppleAuthorizationError: LocalizedError {
    case missingIdentityToken
    case invalidIdentityToken
    case missingNonce
    case randomNonceGenerationFailed

    var errorDescription: String? {
        switch self {
        case .missingIdentityToken:
            return "Apple did not return an identity token."
        case .invalidIdentityToken:
            return "Apple returned an identity token Outbound could not read."
        case .missingNonce:
            return "Apple sign-in could not verify the request."
        case .randomNonceGenerationFailed:
            return "Apple sign-in could not create a secure request."
        }
    }
}

private final class AppleAuthorizationCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<AuthCredential, Error>?
    private var currentNonce: String?

    func credential() async throws -> AuthCredential {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            do {
                let nonce = try Self.randomNonceString()
                currentNonce = nonce

                let request = ASAuthorizationAppleIDProvider().createRequest()
                request.requestedScopes = [.fullName, .email]
                request.nonce = Self.sha256(nonce)

                let controller = ASAuthorizationController(authorizationRequests: [request])
                controller.delegate = self
                controller.presentationContextProvider = self
                controller.performRequests()
            } catch {
                self.continuation = nil
                continuation.resume(throwing: error)
            }
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            resume(throwing: AppleAuthorizationError.missingIdentityToken)
            return
        }

        guard let nonce = currentNonce else {
            resume(throwing: AppleAuthorizationError.missingNonce)
            return
        }

        guard let identityToken = appleIDCredential.identityToken else {
            resume(throwing: AppleAuthorizationError.missingIdentityToken)
            return
        }

        guard let idTokenString = String(data: identityToken, encoding: .utf8) else {
            resume(throwing: AppleAuthorizationError.invalidIdentityToken)
            return
        }

        let credential = OAuthProvider.credential(
            providerID: .apple,
            idToken: idTokenString,
            rawNonce: nonce
        )
        resume(returning: credential)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        resume(throwing: error)
    }

    private func resume(returning credential: AuthCredential) {
        continuation?.resume(returning: credential)
        continuation = nil
        currentNonce = nil
    }

    private func resume(throwing error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
        currentNonce = nil
    }

    private static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.map { String(format: "%02x", $0) }.joined()
    }

    private static func randomNonceString(length: Int = 32) throws -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            guard status == errSecSuccess else {
                throw AppleAuthorizationError.randomNonceGenerationFailed
            }

            randoms.forEach { random in
                guard remainingLength > 0, random < UInt8(charset.count) else { return }
                result.append(charset[Int(random)])
                remainingLength -= 1
            }
        }

        return result
    }
}
