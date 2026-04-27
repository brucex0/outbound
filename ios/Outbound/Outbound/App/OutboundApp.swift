import SwiftUI

@main
struct OutboundApp: App {
    @StateObject private var authStore = AuthStore()
    @StateObject private var coachStore = CoachStore()
    @StateObject private var activityStore = ActivityStore()

    init() {
        FirebaseBootstrap.configureIfAvailable()
    }

    var body: some Scene {
        WindowGroup {
            if AuthStore.isLoginSkipped || authStore.isAuthenticated {
                MainTabView()
                    .environmentObject(authStore)
                    .environmentObject(coachStore)
                    .environmentObject(activityStore)
                    .task { await coachStore.syncIfNeeded() }
            } else {
                AuthView()
                    .environmentObject(authStore)
            }
        }
    }
}
