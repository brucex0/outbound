import Foundation
import SwiftUI

/// Thread-safe fan-out point for every configured analytics destination.
actor AnalyticsManager {
    private var providers: [ObjectIdentifier: any AnalyticsService] = [:]
    private var isInitialized = false
    // Firebase collection is opt-in: only authenticated account activity should
    // contribute to the product's active-user metrics.
    private var isCollectionEnabled = false
    private var isAuthenticated = false
    private var authenticationRevision: UInt = 0

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
        authenticationRevision &+= 1
        let revision = authenticationRevision
        isAuthenticated = userId != nil
        // Fail closed while providers transition between identities. This keeps
        // events from being attributed to the previous account or to no account.
        isCollectionEnabled = false
        await initialize()
        guard authenticationRevision == revision else { return }

        for provider in providers.values {
            await provider.setCollectionEnabled(false)
            guard authenticationRevision == revision else { return }
        }
        for provider in providers.values {
            await provider.setUserId(userId: userId)
            guard authenticationRevision == revision else { return }
        }

        // Do not collect anonymous app-open/session activity. Enable collection
        // only after the provider has received the stable first-party account ID.
        let shouldCollect = userId != nil
        if shouldCollect {
            for provider in providers.values {
                await provider.setCollectionEnabled(true)
                guard authenticationRevision == revision else { return }
            }
        }
        isCollectionEnabled = shouldCollect
    }

    func setCollectionEnabled(_ enabled: Bool) async {
        // Even callers that request collection cannot opt an anonymous device in.
        let revision = authenticationRevision
        isCollectionEnabled = enabled && isAuthenticated
        await initialize()
        guard authenticationRevision == revision else { return }
        for provider in providers.values {
            await provider.setCollectionEnabled(isCollectionEnabled)
            guard authenticationRevision == revision else { return }
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
