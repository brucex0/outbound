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
    @Published private(set) var pendingNotificationType: String?
    @Published private(set) var pendingObjectID: String?
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var notificationsEnabled = false
    @Published private(set) var hasResolvedAuthorization = false
    private var latestToken: String?

    func activate() async {
        guard await refreshAuthorizationStatus() else { return }
        UIApplication.shared.registerForRemoteNotifications()
        if let token = Messaging.messaging().fcmToken { await register(token: token) }
    }

    @discardableResult
    func refreshAuthorizationStatus() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
        let enabled = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        notificationsEnabled = enabled
        hasResolvedAuthorization = true
        return enabled
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
        if settings.authorizationStatus == .notDetermined {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        }
        let enabled = await refreshAuthorizationStatus()
        if enabled {
            UIApplication.shared.registerForRemoteNotifications()
            if let token = Messaging.messaging().fcmToken { await register(token: token) }
        }
        return enabled
    }

    func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func enableFromPrompt(entrySource: String, analyticsManager: AnalyticsManager?) async {
        await analyticsManager?.track(.init(.pushNotificationPromptActionSelected, properties: [
            .entrySource: .string(entrySource),
            .selectionType: .string("enable"),
        ]))
        let enabled = await refreshAuthorizationStatus()
        guard !enabled else { return }
        guard authorizationStatus == .notDetermined else {
            openNotificationSettings()
            return
        }
        let granted = await requestAuthorization()
        await analyticsManager?.track(.init(.pushNotificationPermissionCompleted, properties: [
            .permission: .string("notifications"),
            .result: .string(granted ? "granted" : "denied"),
        ]))
    }

    func receivedMessagingToken(_ token: String?) {
        guard let token else { return }
        Task { await register(token: token) }
    }

    func receivedNotification(userInfo: [AnyHashable: Any]) {
        pendingNotificationType = userInfo["type"] as? String
        pendingObjectID = userInfo["objectId"] as? String
        // Publish the notification ID last; views use it as the routing trigger.
        pendingNotificationID = userInfo["notificationId"] as? String
    }

    func consumePendingNotification() {
        pendingNotificationID = nil
        pendingNotificationType = nil
        pendingObjectID = nil
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
