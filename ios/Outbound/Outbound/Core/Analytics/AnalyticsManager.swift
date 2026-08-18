import Foundation
import SwiftUI

/// Thread-safe fan-out point for every configured analytics destination.
actor AnalyticsManager {
    private var providers: [ObjectIdentifier: any AnalyticsService] = [:]
    private var isInitialized = false

    init(providers: [any AnalyticsService] = []) {
        for provider in providers {
            self.providers[ObjectIdentifier(provider)] = provider
        }
    }

    func initialize() async {
        guard !isInitialized else { return }
        isInitialized = true
        for provider in providers.values {
            await provider.initialize()
        }
    }

    func register(_ provider: any AnalyticsService) async {
        let identifier = ObjectIdentifier(provider)
        guard providers[identifier] == nil else { return }
        providers[identifier] = provider
        if isInitialized {
            await provider.initialize()
        }
    }

    func unregister(_ provider: any AnalyticsService) {
        providers.removeValue(forKey: ObjectIdentifier(provider))
    }

    func trackEvent(eventName: String, parameters: [String: Any]? = nil) async {
        await initialize()
        for provider in providers.values {
            await provider.trackEvent(eventName: eventName, parameters: parameters)
        }
    }

    func setUserId(userId: String?) async {
        await initialize()
        for provider in providers.values {
            await provider.setUserId(userId: userId)
        }
    }

    func setUserProperty(key: String, value: String) async {
        await initialize()
        for provider in providers.values {
            await provider.setUserProperty(key: key, value: value)
        }
    }

    func setCurrentScreen(screenName: String, screenClass: String? = nil) async {
        await initialize()
        for provider in providers.values {
            await provider.setCurrentScreen(screenName: screenName, screenClass: screenClass)
        }
    }
}

private struct AnalyticsManagerEnvironmentKey: EnvironmentKey {
    static let defaultValue: AnalyticsManager? = nil
}

extension EnvironmentValues {
    var analyticsManager: AnalyticsManager? {
        get { self[AnalyticsManagerEnvironmentKey.self] }
        set { self[AnalyticsManagerEnvironmentKey.self] = newValue }
    }
}
