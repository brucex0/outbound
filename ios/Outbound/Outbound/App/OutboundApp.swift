import SwiftUI

@main
struct OutboundApp: App {
    @StateObject private var authStore = AuthStore()
    @StateObject private var coachStore = CoachStore()

    init() {
        FirebaseBootstrap.configureIfAvailable()
    }

    var body: some Scene {
        WindowGroup {
            if AuthStore.isLoginSkipped || authStore.isAuthenticated {
                MainTabView()
                    .environmentObject(authStore)
                    .environmentObject(coachStore)
                    .task { await coachStore.syncIfNeeded() }
            } else {
                AuthView()
                    .environmentObject(authStore)
            }
        }
    }
}
