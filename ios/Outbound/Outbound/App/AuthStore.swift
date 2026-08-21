import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import Security
import UIKit

@MainActor
final class AuthStore: ObservableObject {
    #if DEBUG
    enum TestPersona: String, CaseIterable, Identifiable {
        case newRunner = "New Runner", activeRunner = "Active Runner", socialRunner = "Social Runner"
        var id: String { rawValue }
        var apiValue: String { switch self { case .newRunner: "new"; case .activeRunner: "active"; case .socialRunner: "social" } }
    }
    #endif

    @Published var isAuthenticated = false
    @Published var isBusy = false
    @Published var authError: String?
    @Published var user: AuthenticatedUser?
    @Published var localSessionLabel: String?
    private var appleCoordinator: AppleAuthorizationCoordinator?

    static var currentUserId: String? { cachedUserID }
    private static var cachedUserID: String?
    var currentLoginLabel: String? { user?.email ?? user?.displayName ?? localSessionLabel }
    var connectedProviderLabels: [String] { user == nil ? [] : [String(localized: "Apple")] }
    var isAppleSignInAvailable: Bool { Self.hasAppleSignInEntitlement() }
    var isUsingDebugPersonas: Bool { ProcessInfo.processInfo.arguments.contains("-OutboundEnableDebugPersonas") }

    init() {
        if ProcessInfo.processInfo.arguments.contains("-OutboundDisableAuthentication") || ProcessInfo.processInfo.arguments.contains("-OutboundDisableFirebase") {
            isAuthenticated = true; localSessionLabel = "UI test session"; return
        }
        Task { [weak self] in
            guard let session = await SessionCoordinator.shared.storedSession(), session.isRefreshUsable else { return }
            self?.apply(session)
        }
        NotificationCenter.default.addObserver(forName: .outboundAuthenticationExpired, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.clearPresentation() }
        }
    }

    func signInWithApple() async {
        await performAuthentication {
            let credential = try await self.makeAppleCredential()
            let session = try await APIClient.shared.createAppleSession(credential.sessionRequest)
            try await SessionCoordinator.shared.replace(session)
            AppleProfileCache.remove(for: credential.userIdentifier)
            self.apply(session)
        }
    }

    #if DEBUG
    func signIn(as persona: TestPersona) async {
        guard isUsingDebugPersonas else { authError = String(localized: "Debug personas are unavailable in this build."); return }
        await performAuthentication {
            let session = try await APIClient.shared.createDebugPersonaSession(.init(persona: persona.apiValue, deviceLabel: UIDevice.current.name))
            try await SessionCoordinator.shared.replace(session); self.apply(session)
        }
    }
    #endif

    func signOut() {
        Task {
            let session = await SessionCoordinator.shared.storedSession()
            try? await APIClient.shared.logout(refreshToken: session?.refreshToken)
            await SessionCoordinator.shared.clear()
        }
        clearPresentation()
    }

    func deleteAccount() async {
        await performAuthentication {
            let credential = try await self.makeAppleCredential()
            try await APIClient.shared.deleteMyAccount(.init(identityToken: credential.identityToken, authorizationCode: credential.authorizationCode, rawNonce: credential.rawNonce))
            await SessionCoordinator.shared.clear()
            try? await ActivityPersistence.shared.deleteAll()
            for key in UserDefaults.standard.dictionaryRepresentation().keys { UserDefaults.standard.removeObject(forKey: key) }
            self.clearPresentation()
        }
    }

    func handleOpenURL(_ url: URL) -> Bool { false }

    private func performAuthentication(_ operation: () async throws -> Void) async {
        isBusy = true; authError = nil; defer { isBusy = false }
        do { try await operation() }
        catch let error as ASAuthorizationError where error.code == .canceled { }
        catch { authError = error.localizedDescription }
    }
    private func apply(_ session: AuthSession) { user = session.user; Self.cachedUserID = session.user.id; isAuthenticated = true; localSessionLabel = nil }
    private func clearPresentation() { user = nil; Self.cachedUserID = nil; isAuthenticated = false; localSessionLabel = nil }
    private func makeAppleCredential() async throws -> AppleCredentialResult {
        let coordinator = AppleAuthorizationCoordinator(); appleCoordinator = coordinator
        defer { appleCoordinator = nil }; return try await coordinator.credential()
    }
    private static func hasAppleSignInEntitlement() -> Bool {
        #if APPLE_SIGN_IN_ENABLED
        true
        #else
        false
        #endif
    }
}

private enum AppleAuthorizationError: LocalizedError {
    case missingIdentityToken, invalidIdentityToken, missingNonce, missingAuthorizationCode, randomNonceGenerationFailed
    var errorDescription: String? { String(localized: "Apple sign-in could not be completed. Please try again.") }
}

private struct AppleCredentialResult {
    let identityToken: String; let authorizationCode: String; let rawNonce: String
    let userIdentifier: String; let givenName: String?; let familyName: String?
    var sessionRequest: AppleSessionRequest { .init(identityToken: identityToken, authorizationCode: authorizationCode, rawNonce: rawNonce,
        givenName: givenName, familyName: familyName, deviceLabel: UIDevice.current.name) }
}

private final class AppleAuthorizationCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<AppleCredentialResult, Error>?; private var nonce: String?
    func credential() async throws -> AppleCredentialResult { try await withCheckedThrowingContinuation { continuation in
        self.continuation = continuation
        do { let nonce = try Self.randomNonce(); self.nonce = nonce; let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]; request.nonce = Self.sha256(nonce)
            let controller = ASAuthorizationController(authorizationRequests: [request]); controller.delegate = self
            controller.presentationContextProvider = self; controller.performRequests()
        } catch { resume(error) }
    }}
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let value = authorization.credential as? ASAuthorizationAppleIDCredential,
              let nonce, let tokenData = value.identityToken, let token = String(data: tokenData, encoding: .utf8),
              let codeData = value.authorizationCode, let code = String(data: codeData, encoding: .utf8) else { resume(AppleAuthorizationError.invalidIdentityToken); return }
        let receivedProfile = AppleProfileCache.Profile(givenName: value.fullName?.givenName, familyName: value.fullName?.familyName)
        if receivedProfile.hasName { try? AppleProfileCache.save(receivedProfile, for: value.user) }
        let profile = receivedProfile.hasName ? receivedProfile : (AppleProfileCache.load(for: value.user) ?? receivedProfile)
        continuation?.resume(returning: .init(identityToken: token, authorizationCode: code, rawNonce: nonce,
            userIdentifier: value.user, givenName: profile.givenName, familyName: profile.familyName)); continuation = nil; self.nonce = nil
    }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) { resume(error) }
    private func resume(_ error: Error) { continuation?.resume(throwing: error); continuation = nil; nonce = nil }
    private static func sha256(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined() }
    private static func randomNonce(length: Int = 32) throws -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._"); var result = ""
        while result.count < length { var byte: UInt8 = 0; guard SecRandomCopyBytes(kSecRandomDefault, 1, &byte) == errSecSuccess else { throw AppleAuthorizationError.randomNonceGenerationFailed }; if byte < chars.count { result.append(chars[Int(byte)]) } }
        return result
    }
}

private enum AppleProfileCache {
    struct Profile: Codable {
        let givenName: String?; let familyName: String?
        var hasName: Bool { givenName?.isEmpty == false || familyName?.isEmpty == false }
    }

    private static let service = "run.plainstride.apple-profile"
    private static func query(for userIdentifier: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: userIdentifier]
    }
    static func load(for userIdentifier: String) -> Profile? {
        var query = query(for: userIdentifier)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Profile.self, from: data)
    }
    static func save(_ profile: Profile, for userIdentifier: String) throws {
        let data = try JSONEncoder().encode(profile)
        let base = query(for: userIdentifier)
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(base as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = base; attributes.forEach { item[$0.key] = $0.value }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { return }
        }
    }
    static func remove(for userIdentifier: String) { SecItemDelete(query(for: userIdentifier) as CFDictionary) }
}
