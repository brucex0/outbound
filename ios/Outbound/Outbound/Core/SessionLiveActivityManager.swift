import ActivityKit
import Combine
import Foundation

enum SessionLiveActivityReconciliationResult: String {
    case restored
    case duplicatesRemoved = "duplicates_removed"
    case staleReplaced = "stale_replaced"
}

@MainActor
final class SessionLiveActivityManager: ObservableObject {
    private var activity: Activity<OutboundLiveActivityAttributes>?
    private var lastContentState: OutboundLiveActivityAttributes.ContentState?

    @discardableResult
    func update(
        snapshot: ActiveSessionSnapshot,
        state: RecordingState,
        intent: SessionIntent?,
        unitSystem: MeasurementUnitSystem
    ) -> SessionLiveActivityReconciliationResult? {
        guard state != .idle else { return nil }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return nil }

        let attributes = OutboundLiveActivityAttributes(
            sessionStartedAt: snapshot.startedAt,
            activityName: intent?.title ?? String(localized: "Freestyle run"),
            sportName: intent?.sport.displayName ?? String(localized: "Run"),
            sportSystemImageName: intent?.sport.systemImage ?? "figure.run"
        )
        let content = ActivityContent(
            state: makeContentState(snapshot: snapshot, state: state, unitSystem: unitSystem),
            staleDate: nil
        )
        lastContentState = content.state

        let reconciliationResult = reconcileExistingActivities(
            sessionStartedAt: snapshot.startedAt,
            state: state,
            finalContent: content
        )

        if let activity {
            Task {
                await activity.update(content)
            }
            return reconciliationResult
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
        return reconciliationResult
    }

    func end(using snapshot: ActiveSessionSnapshot? = nil, unitSystem: MeasurementUnitSystem = .metric) {
        let trackedActivity = activity
        self.activity = nil

        let finalState = snapshot.map {
            makeContentState(snapshot: $0, state: .paused, unitSystem: unitSystem)
        } ?? lastContentState ?? OutboundLiveActivityAttributes.ContentState(
            elapsedSeconds: 0,
            elapsedReferenceDate: nil,
            distanceText: unitSystem.distanceString(meters: 0),
            paceText: "--",
            statusText: String(localized: "Finished"),
            isPaused: true
        )
        lastContentState = nil
        let finalContent = ActivityContent(state: finalState, staleDate: nil)

        Task {
            var activities = Activity<OutboundLiveActivityAttributes>.activities
            if let trackedActivity, !activities.contains(where: { $0.id == trackedActivity.id }) {
                activities.append(trackedActivity)
            }
            for activity in activities {
                await activity.end(finalContent, dismissalPolicy: .immediate)
            }
        }
    }

    private func reconcileExistingActivities(
        sessionStartedAt: Date?,
        state: RecordingState,
        finalContent: ActivityContent<OutboundLiveActivityAttributes.ContentState>
    ) -> SessionLiveActivityReconciliationResult? {
        guard activity == nil else { return nil }

        let existingActivities = Activity<OutboundLiveActivityAttributes>.activities
        guard !existingActivities.isEmpty else { return nil }

        let matchingActivity = sessionStartedAt.flatMap { sessionStartedAt in
            existingActivities.first { existingActivity in
                guard let existingStartedAt = existingActivity.attributes.sessionStartedAt else {
                    return false
                }
                return abs(existingStartedAt.timeIntervalSince(sessionStartedAt)) < 1
            }
        }
        let legacyRecoveryActivity = state == .paused
            ? existingActivities.first { $0.attributes.sessionStartedAt == nil }
            : nil

        if let retainedActivity = matchingActivity ?? legacyRecoveryActivity {
            activity = retainedActivity
            let duplicates = existingActivities.filter { $0.id != retainedActivity.id }
            dismiss(duplicates, finalContent: finalContent)
            return duplicates.isEmpty ? .restored : .duplicatesRemoved
        }

        dismiss(existingActivities, finalContent: finalContent)
        return .staleReplaced
    }

    private func dismiss(
        _ activities: [Activity<OutboundLiveActivityAttributes>],
        finalContent: ActivityContent<OutboundLiveActivityAttributes.ContentState>
    ) {
        guard !activities.isEmpty else { return }
        Task {
            for activity in activities {
                await activity.end(finalContent, dismissalPolicy: .immediate)
            }
        }
    }

    private func makeContentState(
        snapshot: ActiveSessionSnapshot,
        state: RecordingState,
        unitSystem: MeasurementUnitSystem
    ) -> OutboundLiveActivityAttributes.ContentState {
        let paceText: String
        if state == .paused {
            if snapshot.distanceMeters > 0 {
                paceText = (Double(snapshot.elapsedSeconds) / (snapshot.distanceMeters / 1000)).paceString(for: unitSystem)
            } else {
                paceText = "--"
            }
        } else {
            paceText = snapshot.currentPaceSecsPerKm?.paceString(for: unitSystem) ?? "--"
        }

        return OutboundLiveActivityAttributes.ContentState(
            elapsedSeconds: snapshot.elapsedSeconds,
            elapsedReferenceDate: state == .active
                ? Date().addingTimeInterval(-TimeInterval(snapshot.elapsedSeconds))
                : nil,
            distanceText: unitSystem.distanceString(meters: snapshot.distanceMeters),
            paceText: paceText,
            statusText: state == .paused ? String(localized: "Paused") : String(localized: "Active"),
            isPaused: state == .paused
        )
    }
}
