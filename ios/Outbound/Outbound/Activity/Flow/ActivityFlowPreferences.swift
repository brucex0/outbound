import Foundation

struct ActivityFlowPreferences {
    static func persisted<Value>(key: String, defaultValue: Value, store: UserDefaults = .standard) -> ActivityFlowPreference<Value> {
        ActivityFlowPreference(key: key, defaultValue: defaultValue, store: store)
    }

    let preferredSessionPageRawValue: ActivityFlowPreference<String>
    let isVoiceGuideEnabled: ActivityFlowPreference<Bool>
    let autoPauseRunningEnabled: ActivityFlowPreference<Bool>
    let autoPauseCyclingEnabled: ActivityFlowPreference<Bool>
    let autoPauseWalkingEnabled: ActivityFlowPreference<Bool>
    let autoPauseHikingEnabled: ActivityFlowPreference<Bool>
    let autoStopAtGoalEnabled: ActivityFlowPreference<Bool>
    let startWatchApp: ActivityFlowPreference<Bool>
#if DEBUG
    var routeTestMode: ActivityFlowPreference<Bool> = .init(key: "debug_route_test_mode", defaultValue: false, store: .standard)
#endif
}

/// A live storage accessor, deliberately independent of SwiftUI Binding's
/// view-update value caching. The coordinator publishes its own writes;
/// RecordView's AppStorage subscriptions observe edits from other surfaces.
struct ActivityFlowPreference<Value> {
    let key: String
    let defaultValue: Value
    let store: UserDefaults

    var wrappedValue: Value {
        get { store.object(forKey: key) as? Value ?? defaultValue }
        nonmutating set { store.set(newValue, forKey: key) }
    }
}
