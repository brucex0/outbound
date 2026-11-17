#if DEBUG && targetEnvironment(simulator)
import Foundation
import CoreFoundation

/// Opt-in manual Simulator probe; it only signals the normal Today input path.
/// No observer is installed in production or without the explicit launch flag.
enum TodayPrescriptionRefreshProbe {
    static let notification = Notification.Name("OutboundTodayPrescriptionRefreshProbe")
    static let launchArgument = "-OutboundUITestTodayPrescriptionRefresh"

    static func installIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains(launchArgument) else { return }
        _ = installation
    }

    private static let installation: Void = {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), nil,
            { _, _, _, _, _ in
                Task { @MainActor in
                    NotificationCenter.default.post(name: notification, object: nil)
                }
            },
            "com.plainstride.outbound.debug.today-prescription-refresh" as CFString,
            nil, .deliverImmediately
        )
    }()
}
#endif
