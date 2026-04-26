import SwiftUI
import FirebaseCore

@main
struct OutboundApp: App {
    @StateObject private var authStore = AuthStore()
    @StateObject private var coachStore = CoachStore()

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            if authStore.isAuthenticated {
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
