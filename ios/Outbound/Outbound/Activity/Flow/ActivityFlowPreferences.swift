import SwiftUI

struct ActivityFlowPreferences {
    let preferredSessionPageRawValue: Binding<String>
    let isVoiceGuideEnabled: Binding<Bool>
    let autoPauseRunningEnabled: Binding<Bool>
    let autoPauseCyclingEnabled: Binding<Bool>
    let autoPauseWalkingEnabled: Binding<Bool>
    let autoPauseHikingEnabled: Binding<Bool>
    let autoStopAtGoalEnabled: Binding<Bool>
    let startWatchApp: Binding<Bool>
#if DEBUG
    var routeTestMode: Binding<Bool> = .constant(false)
#endif
}
