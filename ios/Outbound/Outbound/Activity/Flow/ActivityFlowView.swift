import SwiftUI
import PhotosUI
import CoreLocation
import MapKit

struct ActivityFlowView: View {
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.outboundTheme) var theme
    @FocusState var focusedCustomGoalKind: CustomGoalKind?
    @StateObject var model: ActivityFlowCoordinator
    let host: ActivityFlowHost
    // A value snapshot ensures external AppStorage edits invalidate this host,
    // even though its retained coordinator keeps the original storage bindings.
    let preferenceValues: [String]

    init(initialIntent: SessionIntent?, dependencies: ActivityFlowDependencies, preferences: ActivityFlowPreferences, host: ActivityFlowHost, reduceMotion: Bool, analyticsManager: AnalyticsManager?) {
        self.host = host
        var values: [String] = []
        values.append(String(describing: preferences.preferredSessionPageRawValue.wrappedValue))
        values.append(String(describing: preferences.isVoiceGuideEnabled.wrappedValue))
        values.append(String(describing: preferences.autoPauseRunningEnabled.wrappedValue))
        values.append(String(describing: preferences.autoPauseCyclingEnabled.wrappedValue))
        values.append(String(describing: preferences.autoPauseWalkingEnabled.wrappedValue))
        values.append(String(describing: preferences.autoPauseHikingEnabled.wrappedValue))
        values.append(String(describing: preferences.autoStopAtGoalEnabled.wrappedValue))
        values.append(String(describing: preferences.startWatchApp.wrappedValue))
#if DEBUG
        values.append(String(describing: preferences.routeTestMode.wrappedValue))
#endif
        preferenceValues = values
        _model = StateObject(wrappedValue: ActivityFlowCoordinator(initialIntent: initialIntent, dependencies: dependencies, preferences: preferences, host: host, reduceMotion: reduceMotion, analyticsManager: analyticsManager))
    }

    var body: some View {
        // Refresh host inputs synchronously before evaluating visibility and handlers.
        // These are external inputs, not published session state.
        model.host = host
        model.reduceMotion = reduceMotion
        return flowBody
    }

    func binding<Value>(_ keyPath: ReferenceWritableKeyPath<ActivityFlowCoordinator, Value>) -> Binding<Value> {
        Binding(
            get: { model[keyPath: keyPath] },
            set: { model[keyPath: keyPath] = $0 }
        )
    }
}
