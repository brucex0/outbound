import FirebaseAnalytics
import Foundation

actor FirebaseAnalyticsProvider: AnalyticsService {
    private var isInitialized = false

    func initialize() async {
        guard !isInitialized, FirebaseBootstrap.configureIfAvailable() else { return }
        Analytics.setAnalyticsCollectionEnabled(true)
        isInitialized = true
    }

    func trackEvent(eventName: String, parameters: [String: Any]?) async {
        guard isInitialized else { return }
        Analytics.logEvent(
            AnalyticsSanitizer.eventName(eventName),
            parameters: AnalyticsSanitizer.firebaseParameters(parameters)
        )
    }

    func setUserId(userId: String?) async {
        guard isInitialized else { return }
        Analytics.setUserID(userId.map { String($0.prefix(256)) })
    }

    func setUserProperty(key: String, value: String) async {
        guard isInitialized else { return }
        Analytics.setUserProperty(
            String(value.prefix(36)),
            forName: AnalyticsSanitizer.userPropertyKey(key)
        )
    }

    func setCurrentScreen(screenName: String, screenClass: String?) async {
        guard isInitialized else { return }
        var parameters: [String: Any] = [
            AnalyticsParameterScreenName: AnalyticsSanitizer.screenName(screenName)
        ]
        if let screenClass {
            parameters[AnalyticsParameterScreenClass] = AnalyticsSanitizer.screenName(screenClass)
        }
        Analytics.logEvent(AnalyticsEventScreenView, parameters: parameters)
    }
}
