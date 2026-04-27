import Foundation
import FirebaseCore

enum FirebaseBootstrap {
    nonisolated static var isConfigured: Bool {
        guard !isDisabledForUITests else { return false }
        return FirebaseApp.app() != nil
    }

    @discardableResult
    nonisolated static func configureIfAvailable() -> Bool {
        if isDisabledForUITests {
            print("[Outbound] Firebase disabled by UI test launch argument.")
            return false
        }

        if FirebaseApp.app() != nil {
            return true
        }

        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            print("[Outbound] GoogleService-Info.plist is missing; Firebase-backed auth is disabled.")
            return false
        }

        FirebaseApp.configure()
        return FirebaseApp.app() != nil
    }

    private nonisolated static var isDisabledForUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("-OutboundDisableFirebase")
    }
}
