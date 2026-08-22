import Foundation
import SwiftUI

/// Thread-safe fan-out point for every configured analytics destination.
actor AnalyticsManager {
    private var providers: [ObjectIdentifier: any AnalyticsService] = [:]
    private var isInitialized = false
    private var isCollectionEnabled = true
    private var isAuthenticated = false

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

    func track(_ event: ProductAnalyticsEvent) async {
        guard isCollectionEnabled,
              var properties = ProductAnalyticsSchema.validatedProperties(for: event)
        else { return }

        properties[.schemaVersion] = .integer(event.schemaVersion)
        properties[.appVersion] = .string(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown")
        properties[.appBuild] = .string(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown")
        properties[.osMajorVersion] = .integer(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
        properties[.language] = .string(Locale.current.language.languageCode?.identifier ?? "und")
        properties[.authenticationState] = .string(isAuthenticated ? "authenticated" : "anonymous")

        await initialize()
        for provider in providers.values {
            await provider.trackEvent(eventName: event.name.rawValue, parameters: properties.reduce(into: [:]) {
                $0[$1.key.rawValue] = $1.value
            })
        }
    }

    func setUserId(userId: String?) async {
        isAuthenticated = userId != nil
        await initialize()
        for provider in providers.values {
            await provider.setUserId(userId: userId)
        }
    }

    func setCollectionEnabled(_ enabled: Bool) async {
        isCollectionEnabled = enabled
        await initialize()
        for provider in providers.values {
            await provider.setCollectionEnabled(enabled)
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
