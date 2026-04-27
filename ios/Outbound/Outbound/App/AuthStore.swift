import Foundation
import Combine
import FirebaseAuth

@MainActor
final class AuthStore: ObservableObject {
    static let isLoginSkipped = true

    @Published var isAuthenticated = isLoginSkipped
    @Published var isFirebaseConfigured = FirebaseBootstrap.isConfigured
    @Published var authError: String?
    @Published var user: FirebaseAuth.User?

    private var authStateListener: AuthStateDidChangeListenerHandle?

    static var currentUserId: String? {
        guard FirebaseBootstrap.isConfigured else { return nil }
        return Auth.auth().currentUser?.uid
    }

    init() {
        guard !Self.isLoginSkipped else {
            isFirebaseConfigured = false
            return
        }

        isFirebaseConfigured = FirebaseBootstrap.configureIfAvailable()
        guard isFirebaseConfigured else { return }

        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.user = user
                self?.isAuthenticated = user != nil
                if let token = try? await user?.getIDToken() {
                    APIClient.shared.setToken(token)
                }
            }
        }
    }

    deinit {
        if FirebaseBootstrap.isConfigured, let authStateListener {
            Auth.auth().removeStateDidChangeListener(authStateListener)
        }
    }

    func startLocalSession() {
        isAuthenticated = true
        user = nil
        authError = nil
    }

    func signOut() {
        guard !Self.isLoginSkipped else {
            isAuthenticated = true
            user = nil
            authError = nil
            return
        }

        guard FirebaseBootstrap.isConfigured else {
            isAuthenticated = false
            user = nil
            return
        }

        try? Auth.auth().signOut()
    }

    func sendVerificationCode(to phone: String, completion: @escaping (String?) -> Void) {
        guard FirebaseBootstrap.isConfigured else {
            authError = "Firebase configuration is missing."
            completion(nil)
            return
        }

        PhoneAuthProvider.provider().verifyPhoneNumber(phone, uiDelegate: nil) { [weak self] id, error in
            Task { @MainActor in
                self?.authError = error?.localizedDescription
                completion(id)
            }
        }
    }

    func verifyCode(verificationId: String, code: String) {
        guard FirebaseBootstrap.isConfigured else {
            authError = "Firebase configuration is missing."
            return
        }

        let credential = PhoneAuthProvider.provider().credential(
            withVerificationID: verificationId,
            verificationCode: code
        )

        Auth.auth().signIn(with: credential) { [weak self] _, error in
            Task { @MainActor in
                self?.authError = error?.localizedDescription
            }
        }
    }
}
