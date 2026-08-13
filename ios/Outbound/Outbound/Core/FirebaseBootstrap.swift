import Foundation
import FirebaseAuth
import FirebaseCore

enum FirebaseBootstrap {
    nonisolated static var isConfigured: Bool {
        guard !isDisabledForUITests else { return false }
        return FirebaseApp.app() != nil
    }

    @discardableResult
    nonisolated static func configureIfAvailable() -> Bool {
        if isDisabledForUITests {
            print("[Plainstride] Firebase disabled by UI test launch argument.")
            return false
        }

        if FirebaseApp.app() != nil {
            return true
        }

        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            print("[Plainstride] GoogleService-Info.plist is missing; Firebase-backed auth is disabled.")
            return false
        }

        FirebaseApp.configure()
        configureAuthEmulatorIfRequested()
        return FirebaseApp.app() != nil
    }

    #if DEBUG
    nonisolated static var isUsingAuthEmulator: Bool {
        ProcessInfo.processInfo.arguments.contains("-OutboundUseFirebaseAuthEmulator")
    }

    private nonisolated static func configureAuthEmulatorIfRequested() {
        guard isUsingAuthEmulator else { return }
        let host = launchArgumentValue(after: "-OutboundFirebaseAuthEmulatorHost") ?? "127.0.0.1"
        let port = Int(launchArgumentValue(after: "-OutboundFirebaseAuthEmulatorPort") ?? "9099") ?? 9099
        Auth.auth().useEmulator(withHost: host, port: port)
        print("[Plainstride] Firebase Auth Emulator enabled at \(host):\(port).")
    }

    private nonisolated static func launchArgumentValue(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
    #else
    nonisolated static let isUsingAuthEmulator = false

    private nonisolated static func configureAuthEmulatorIfRequested() {}
    #endif

    private nonisolated static var isDisabledForUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("-OutboundDisableFirebase")
    }
}
