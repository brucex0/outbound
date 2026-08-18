import Foundation

/// Vendor-neutral analytics contract. Implementations serialize their own SDK access.
protocol AnalyticsService: AnyObject, Sendable {
    func initialize() async
    func trackEvent(eventName: String, parameters: [String: Any]?) async
    func setUserId(userId: String?) async
    func setUserProperty(key: String, value: String) async
    func setCurrentScreen(screenName: String, screenClass: String?) async
}
