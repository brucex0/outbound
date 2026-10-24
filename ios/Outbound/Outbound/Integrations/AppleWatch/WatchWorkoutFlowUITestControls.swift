#if DEBUG && targetEnvironment(simulator)
import SwiftUI

/// Only visible in explicitly requested seeded simulator scenarios. These controls
/// inject encoded remote messages; normal recording/review/save remain production UI.
struct WatchWorkoutFlowUITestControls: View {
    @EnvironmentObject private var activityStore: ActivityStore
    @ObservedObject var coordinator: PhoneWorkoutSessionCoordinator
    let allowsControls: Bool
    let phase: String

    var body: some View {
        VStack(spacing: 2) {
            Text("Watch fixture")
                .accessibilityIdentifier("WatchFlowProbe")
                .accessibilityValue(report)
            HStack {
                ForEach(["pause", "resume", "disconnect", "reconnect", "stale"], id: \.self) { action in
                    Button(action) { coordinator.watchFlowUITestAction(action) }
                        .accessibilityIdentifier("WatchFixture-" + action)
                }
            }
        }
        .font(.system(size: 9))
        .buttonStyle(.bordered)
        .padding(4)
        .background(.regularMaterial)
        .offset(y: 60)
        .allowsHitTesting(allowsControls)
    }
    private static var didSeedRecording = false

    static func claimRecordingSeed() -> Bool {
        // Review dismissal can recreate the flow. Seed once per process for
        // ordinary live fixtures as well as Watch scenarios.
        guard !didSeedRecording else { return false }
        didSeedRecording = true
        return true
    }

    static func resetRecordingIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-OutboundUITestSeedData"),
              arguments.contains("-OutboundUITestWatchScenario") else { return }
        // Each scenario starts from its own seeded recording, even when an
        // earlier assertion failed while a review/recovery journal was open.
        ActiveSessionJournal.clear(reason: .discarded)
        _ = ActiveSessionPhotoJournal.clear()
    }

    private var report: String {
        let saved = activityStore.activities.filter {
            $0.recordingSession?.sessionUUID == coordinator.uiTestSessionUUID
        }
        let metadata = saved.first?.recordingSession
        return coordinator.watchFlowUITestReport + ";phase=" + phase +
            ";saved_count=\(saved.count);saved_ownership=\(metadata?.healthKitOwnership.rawValue ?? "none");saved_reference=\(metadata?.healthKitWorkoutExternalReference == nil ? "none" : "saved")"
    }

}
#endif
