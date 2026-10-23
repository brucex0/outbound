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
    private struct PendingUpdate {
        let activity: Activity<OutboundLiveActivityAttributes>
        let content: ActivityContent<OutboundLiveActivityAttributes.ContentState>
    }
    private enum Operation {
        case update(PendingUpdate)
        case end([Activity<OutboundLiveActivityAttributes>], ActivityContent<OutboundLiveActivityAttributes.ContentState>)
    }
    private var operations: [Operation] = []
    private var updateTask: Task<Void, Never>?
    private var endingActivityIDs = Set<String>()
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
            activityName: intent?.title ?? SportType.run.displayName,
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
            enqueueUpdate(activity: activity, content: content)
            return reconciliationResult
        }

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
            ActivityDiagnosticLog.error(.lifecycle,
                "Live Activity start failed error=\(ActivityDiagnosticLog.errorCategory(error))")
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

        // Capture targets before yielding so a subsequent session is never ended.
        var targets = Activity<OutboundLiveActivityAttributes>.activities
        if let trackedActivity, !targets.contains(where: { $0.id == trackedActivity.id }) {
            targets.append(trackedActivity)
        }
        dismiss(targets, finalContent: finalContent)
    }

    private func enqueueUpdate(
        activity: Activity<OutboundLiveActivityAttributes>,
        content: ActivityContent<OutboundLiveActivityAttributes.ContentState>
    ) {
        guard !endingActivityIDs.contains(activity.id) else { return }
        // Coalesce metrics within a phase, retaining pause/resume transitions.
        let next = PendingUpdate(activity: activity, content: content)
        if case let .update(last) = operations.last,
           last.activity.id == activity.id,
           last.content.state.isPaused == content.state.isPaused {
            operations[operations.count - 1] = .update(next)
        } else {
            operations.append(.update(next))
        }
        drainOperations()
    }

    private func drainOperations() {
        guard updateTask == nil else { return }
        updateTask = Task { [weak self] in
            guard let self else { return }
            while !operations.isEmpty {
                switch operations.removeFirst() {
                case let .update(next):
                    guard !endingActivityIDs.contains(next.activity.id) else { continue }
                    await next.activity.update(next.content)
                case let .end(targets, content):
                    for target in targets {
                        await target.end(content, dismissalPolicy: .immediate)
                        endingActivityIDs.remove(target.id)
                    }
                }
            }
            updateTask = nil
        }
    }

    private func reconcileExistingActivities(
        sessionStartedAt: Date?,
        state: RecordingState,
        finalContent: ActivityContent<OutboundLiveActivityAttributes.ContentState>
    ) -> SessionLiveActivityReconciliationResult? {
        guard activity == nil else { return nil }

        let existingActivities = Activity<OutboundLiveActivityAttributes>.activities
            .filter { !endingActivityIDs.contains($0.id) }
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
        let targets = activities.filter { !endingActivityIDs.contains($0.id) }
        guard !targets.isEmpty else { return }
        let ids = Set(targets.map(\.id))
        endingActivityIDs.formUnion(ids)
        operations.removeAll {
            if case let .update(update) = $0 { return ids.contains(update.activity.id) }
            return false
        }
        // An in-flight update completes before this end operation. Subsequent
        // sessions enqueue behind teardown and cannot be captured by it.
        operations.append(.end(targets, finalContent))
        drainOperations()
    }

    private func makeContentState(
        snapshot: ActiveSessionSnapshot,
        state: RecordingState,
        unitSystem: MeasurementUnitSystem
    ) -> OutboundLiveActivityAttributes.ContentState {
        let paceText: String
        if state == .paused {
            paceText = snapshot.averagePaceSecsPerKm?.paceString(for: unitSystem) ?? "--"
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
