import Foundation
import FirebaseAuth

@MainActor
final class AuthStore: ObservableObject {
    @Published var isAuthenticated = false
    @Published var user: FirebaseAuth.User?

    static var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }

    init() {
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.user = user
                self?.isAuthenticated = user != nil
                if let token = try? await user?.getIDToken() {
                    APIClient.shared.setToken(token)
                }
            }
        }
    }

    func signOut() {
        try? Auth.auth().signOut()
    }
}
