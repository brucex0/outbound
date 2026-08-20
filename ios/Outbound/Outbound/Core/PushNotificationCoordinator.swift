import FirebaseMessaging
import Combine
import Foundation
import UIKit
import UserNotifications

struct PushDeviceRegistrationDTO: Codable, Sendable {
    let token: String
    let platform: String
    let appBundle: String
    let locale: String
}

@MainActor
final class PushNotificationCoordinator: NSObject, ObservableObject {
    static let shared = PushNotificationCoordinator()

    @Published private(set) var pendingNotificationID: String?
    private var latestToken: String?

    func activate() async {
        let center = UNUserNotificationCenter.current()
        await clearAppIconBadge(using: center)
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
        }
        let refreshedSettings = await center.notificationSettings()
        guard refreshedSettings.authorizationStatus == .authorized || refreshedSettings.authorizationStatus == .provisional else { return }
        UIApplication.shared.registerForRemoteNotifications()
        if let token = Messaging.messaging().fcmToken { await register(token: token) }
    }

    func receivedMessagingToken(_ token: String?) {
        guard let token else { return }
        Task { await register(token: token) }
    }

    func receivedNotification(userInfo: [AnyHashable: Any]) {
        pendingNotificationID = userInfo["notificationId"] as? String
    }

    func consumePendingNotification() {
        pendingNotificationID = nil
    }

    func clearAppIconBadge() async {
        await clearAppIconBadge(using: UNUserNotificationCenter.current())
    }

    private func clearAppIconBadge(using center: UNUserNotificationCenter) async {
        try? await center.setBadgeCount(0)
    }

    private func register(token: String) async {
        guard token != latestToken else { return }
        do {
            _ = try await APIClient.shared.registerPushDevice(PushDeviceRegistrationDTO(
                token: token,
                platform: "ios",
                appBundle: Bundle.main.bundleIdentifier ?? "plainstride.outbound",
                locale: Locale.current.identifier
            ))
            latestToken = token
        } catch {
            // Authentication or connectivity may not be ready yet; the next app activation retries.
        }
    }
}
