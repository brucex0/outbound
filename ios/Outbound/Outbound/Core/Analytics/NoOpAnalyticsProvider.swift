import Foundation
import OSLog

actor NoOpAnalyticsProvider: AnalyticsService {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Plainstride", category: "Analytics")

    func initialize() async {
        logger.debug("No-op analytics initialized")
    }

    func trackEvent(eventName: String, parameters: [String: Any]?) async {
        logger.debug("Event: \(AnalyticsSanitizer.eventName(eventName), privacy: .public), parameters: \(String(describing: parameters), privacy: .private)")
    }

    func setUserId(userId: String?) async {
        logger.debug("User ID updated: \(userId == nil ? "cleared" : "set", privacy: .public)")
    }

    func setUserProperty(key: String, value: String) async {
        logger.debug("User property: \(AnalyticsSanitizer.userPropertyKey(key), privacy: .public)=\(value, privacy: .private)")
    }

    func setCurrentScreen(screenName: String, screenClass: String?) async {
        logger.debug("Screen: \(AnalyticsSanitizer.screenName(screenName), privacy: .public), class: \(screenClass ?? "unspecified", privacy: .public)")
    }
}
