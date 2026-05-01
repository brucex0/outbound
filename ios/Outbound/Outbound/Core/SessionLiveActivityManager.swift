import ActivityKit
import Combine
import Foundation

@MainActor
final class SessionLiveActivityManager: ObservableObject {
    private var activity: Activity<OutboundLiveActivityAttributes>?
    private var lastContentState: OutboundLiveActivityAttributes.ContentState?

    func update(
        snapshot: ActiveSessionSnapshot,
        state: RecordingState,
        intent: SessionIntent?
    ) {
        guard state != .idle else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = OutboundLiveActivityAttributes(
            activityName: intent?.title ?? "Freestyle run",
            sportName: intent?.sport.displayName ?? "Run",
            sportSystemImageName: intent?.sport.systemImage ?? "figure.run"
        )
        let content = ActivityContent(
            state: makeContentState(snapshot: snapshot, state: state),
            staleDate: nil
        )
        lastContentState = content.state

        if let activity {
            Task {
                await activity.update(content)
            }
            return
        }

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
            #if DEBUG
            print("Failed to start Live Activity: \(error)")
            #endif
        }
    }

    func end(using snapshot: ActiveSessionSnapshot? = nil) {
        guard let activity else { return }
        self.activity = nil

        let finalState = snapshot.map {
            makeContentState(snapshot: $0, state: .paused)
        } ?? lastContentState ?? OutboundLiveActivityAttributes.ContentState(
            elapsedSeconds: 0,
            elapsedReferenceDate: nil,
            distanceText: "0.00 km",
            paceText: "--",
            statusText: "Finished",
            isPaused: true
        )
        lastContentState = nil
        let finalContent = ActivityContent(state: finalState, staleDate: nil)

        Task {
            await activity.end(finalContent, dismissalPolicy: .immediate)
        }
    }

    private func makeContentState(
        snapshot: ActiveSessionSnapshot,
        state: RecordingState
    ) -> OutboundLiveActivityAttributes.ContentState {
        let paceText: String
        if state == .paused {
            if snapshot.distanceMeters > 0 {
                paceText = (Double(snapshot.elapsedSeconds) / (snapshot.distanceMeters / 1000)).paceString
            } else {
                paceText = "--"
            }
        } else {
            paceText = snapshot.currentPaceSecsPerKm?.paceString ?? "--"
        }

        return OutboundLiveActivityAttributes.ContentState(
            elapsedSeconds: snapshot.elapsedSeconds,
            elapsedReferenceDate: state == .active
                ? Date().addingTimeInterval(-TimeInterval(snapshot.elapsedSeconds))
                : nil,
            distanceText: String(format: "%.2f km", snapshot.distanceMeters / 1000),
            paceText: paceText,
            statusText: state == .paused ? "Paused" : "Active",
            isPaused: state == .paused
        )
    }
}
