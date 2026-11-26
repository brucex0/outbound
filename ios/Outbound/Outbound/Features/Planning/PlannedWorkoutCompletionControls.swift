import SwiftUI

func manualCompletionText(_ key: String) -> String {
    let resourceKey = "plan.completion." + key
    return String(localized: String.LocalizationValue(resourceKey))
}

func manualCompletionMatches(_ type: ActivityType, modality: String?) -> Bool {
    switch modality {
    case "run": return type == .running
    case "walk": return type == .walking || type == .hiking
    case "bike": return type == .cycling
    default: return type.rawValue == modality
    }
}

/// Only an explicitly unrecorded completion with no recorded association can
/// offer a first link from Today. Local hydration alone cannot establish this.
func canLinkUnrecordedWorkout(_ workout: TrainingPlanWorkout, store: TrainingPlanStore, activities: ActivityStore) -> Bool {
    workout.completionMode == "manual_unrecorded"
        && workout.status == "completed"
        && !activities.repositoryProjection.confirmedCompletions.contains {
            $0.plannedWorkoutId == workout.id && $0.status == "completed"
        }
        && !store.completedPlanActivities.contains { $0.workoutID == workout.id }
}

/// Online, explicit association editing. Saving the recording remains independently durable.
struct PlannedWorkoutCompletionControls: View {
    let workout: TrainingPlanWorkout
    var linkOnly = false
    var actionPresentation: OutboundSecondaryActionPresentation = .bordered
    var onSuccess: (() -> Void)? = nil
    @EnvironmentObject private var trainingPlanStore: TrainingPlanStore
    @EnvironmentObject private var activityStore: ActivityStore
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    @Environment(\.analyticsManager) private var analytics
    @State private var candidates: [RemoteActivityRecord] = []
    @State private var choosing = false
    @State private var confirming: String?
    @State private var busy = false
    @State private var toast: String?

    private var current: TrainingPlanWorkout {
        (trainingPlanStore.activePlan?.plannedSchedule ?? trainingPlanStore.currentWeek?.scheduledWorkouts ?? []).first { $0.id == workout.id } ?? workout
    }
    private var eligible: Bool {
        guard let date = current.logicalScheduledDate else { return false }
        return date <= trainingPlanStore.nutritionCalendar.startOfDay(for: Date())
            && (["planned", "missed"].contains(current.status ?? "planned") || current.completionMode?.hasPrefix("manual_") == true)
    }

    var body: some View {
        if eligible && (!linkOnly || canLinkUnrecordedWorkout(current, store: trainingPlanStore, activities: activityStore)) {
            VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                ViewThatFits(in: .horizontal) {
                    HStack { actions }
                    VStack(alignment: .leading) { actions }
                }
                if busy && !linkOnly { ProgressView().accessibilityLabel(Text(manualCompletionText("loading"))) }
            }
            .outboundSecondaryActionStyle(actionPresentation)
            .disabled(busy)
            .sheet(isPresented: $choosing) { candidateSheet }
            .confirmationDialog(manualCompletionText(confirming == "undo" ? "undo_title" : "manual_title"), isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }), titleVisibility: .visible) {
                Button(manualCompletionText(confirming == "undo" ? "undo" : "manual"), role: confirming == "undo" ? .destructive : nil) {
                    let action = confirming ?? "complete"
                    confirming = nil
                    Task { await apply(action) }
                }
                Button(String(localized: "Cancel"), role: .cancel) { confirming = nil }
            } message: { Text(manualCompletionText(confirming == "undo" ? "undo_message" : "manual_message")) }
            .overlay(alignment: .top) {
                if let toast { Text(toast).font(.subheadline).padding().background(.regularMaterial, in: Capsule()).accessibilityAddTraits(.updatesFrequently) }
            }
            .task(id: toast) {
                guard toast != nil else { return }
                do { try await Task.sleep(for: .seconds(4)); toast = nil } catch { /* Toast replaced or dismissed. */ }
            }
        }
    }

    @ViewBuilder private var actions: some View {
        Button { Task { await loadCandidates() } } label: {
            if linkOnly {
                Text(String(localized: "today.workout.link", defaultValue: "Link activity"))
            } else {
                Text(manualCompletionText("link")).outboundTapTarget()
            }
        }
        .frame(minHeight: 44)
        .accessibilityLabel(manualCompletionText("link"))
        .accessibilityValue(busy ? manualCompletionText("loading") : "")
        if !linkOnly && current.status != "completed" {
            Button { confirming = "complete" } label: { Text(manualCompletionText("manual")).outboundTapTarget() }
        } else if !linkOnly {
            Button(role: .destructive) { confirming = "undo" } label: { Text(manualCompletionText("undo")).outboundTapTarget() }
        }
    }

    private var candidateSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                    Text(manualCompletionText("choose_message")).font(.subheadline).foregroundStyle(.secondary)
                    if candidates.isEmpty { Text(manualCompletionText("empty")).foregroundStyle(.secondary) }
                    ForEach(candidates, id: \.id) { candidate in
                        Button {
                            choosing = false
                            Task { await apply("link", activityID: candidate.id) }
                        } label: {
                            VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                                Text(candidate.title).font(.headline)
                                Text(candidate.startedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: trainingPlanStore.nutritionCalendar.timeZone))).font(.subheadline)
                                Text(measurementPreferences.unitSystem.distanceValueString(meters: candidate.distanceM) + " " + measurementPreferences.unitSystem.distanceUnit + " · " + Duration.seconds(candidate.durationSecs).formatted(.time(pattern: .hourMinuteSecond))).font(.subheadline)
                            }.frame(maxWidth: .infinity, alignment: .leading).outboundTapTarget()
                        }.buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: OutboundRadius.control))
                    }
                }.padding()
            }
            .navigationTitle(manualCompletionText("link"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Cancel")) { choosing = false } } }
        }
    }

    private func loadCandidates() async {
        guard !busy, !linkOnly || canLinkUnrecordedWorkout(current, store: trainingPlanStore, activities: activityStore) else { return }
        busy = true
        defer { busy = false }
        if linkOnly {
            await analytics?.track(.init(.featureExposed, properties: [.feature: .string("manual_workout_completion"), .selectionType: .string("link"), .result: .string("opened"), .entrySource: .string("today_complete_footer")]))
        }
        let context = ActivityAccountBoundary.current
        do {
            try await ActivityAccountBoundary.$operation.withValue(context) {
                let cutoff = Date().addingTimeInterval(-30 * 86400)
                let calendar = trainingPlanStore.nutritionCalendar
                // Schedule keys are logical date labels, not UTC instants.
                let workoutDate = current.scheduledDateKey.flatMap { PlanningCalendarContext.logicalDate($0, calendar: calendar) } ?? current.logicalScheduledDate
                var cursor: String?
                var loaded: [RemoteActivityRecord] = []
                repeat {
                    let response = try await APIClient.shared.fetchActivities(cursor: cursor, includeRoute: false, limit: 200)
                    try Task.checkCancellation()
                    try ActivityAccountBoundary.validate()
                    loaded += response.activities.filter { candidate in candidate.deletedAt == nil && candidate.completionPolicyVersion == "manual-completion-v1" && candidate.completion == nil && candidate.clientData?.performedWorkoutReference == nil && manualCompletionMatches(candidate.activityType, modality: current.modality) && candidate.startedAt <= Date() && candidate.startedAt > cutoff && workoutDate.map { calendar.isDate(candidate.startedAt, inSameDayAs: $0) } == true }
                    if !response.hasMore || response.activities.last.map({ $0.startedAt <= cutoff }) == true { break }
                    guard let next = response.nextCursor, next != cursor else { throw URLError(.badServerResponse) }
                    cursor = next
                } while true
                candidates = loaded
                await analytics?.track(.init(.featureExposed, properties: [.feature: .string("manual_workout_completion_picker"), .sourceType: .string("same_day"), .result: .string(loaded.isEmpty ? "empty" : "shown")]))
                choosing = true
            }
        } catch is CancellationError { }
        catch {
            ActivityDiagnosticLog.error(.sync, "Manual workout candidate load failed error=\(ActivityDiagnosticLog.errorCategory(error))")
            toast = manualCompletionText("failed")
        }
    }

    private func apply(_ action: String, activityID: String? = nil) async {
        guard !linkOnly || canLinkUnrecordedWorkout(current, store: trainingPlanStore, activities: activityStore) else { return }
        busy = true
        defer { busy = false }
        do {
            try await trainingPlanStore.setManualCompletion(workoutID: current.id, action: action, activityID: activityID)
            // Today replaces Link with View as soon as the command checkpoints.
            // Let its stable page own success feedback before this control unmounts.
            onSuccess?()
            // Accepted command is already checkpointed. A metadata failure must not suggest it was rejected.
            do { try await activityStore.refreshCompletionAssociations() }
            catch is CancellationError { return }
            catch { ActivityDiagnosticLog.error(.sync, "Manual workout association refresh failed error=\(ActivityDiagnosticLog.errorCategory(error))") }
            if onSuccess == nil { toast = manualCompletionText("saved") }
            await analytics?.track(.init(.featureExposed, properties: [.feature: .string("manual_workout_completion"), .selectionType: .string(action), .result: .string("success")]))
        } catch is CancellationError { }
        catch {
            ActivityDiagnosticLog.error(.sync, "Manual workout completion failed error=\(ActivityDiagnosticLog.errorCategory(error))")
            toast = manualCompletionText("failed")
            await analytics?.track(.init(.featureExposed, properties: [.feature: .string("manual_workout_completion"), .selectionType: .string(action), .result: .string("failure")]))
        }
    }
}

/// Optional after-save question; never holds the local Save transaction open.
struct GroupWorkoutCompletionPrompt: View {
    let activity: SavedActivity
    @EnvironmentObject private var trainingPlanStore: TrainingPlanStore
    @EnvironmentObject private var activityStore: ActivityStore
    @Environment(\.analyticsManager) private var analytics
    @State private var dismissed = false
    @State private var busy = false
    @State private var toast: String?

    private var match: TrainingPlanWorkout? {
        let calendar = trainingPlanStore.nutritionCalendar
        guard activity.activityEventID != nil, activity.performedWorkoutReference == nil,
              calendar.isDateInToday(activity.startedAt),
              !activityStore.repositoryProjection.confirmedCompletions.contains(where: { $0.activityId == activityStore.activity(id: activity.id)?.sync?.serverActivityId }) else { return nil }
        let matches = (trainingPlanStore.activePlan?.plannedSchedule ?? []).filter {
            !$0.isOptional && ["planned", "missed"].contains($0.status ?? "planned")
                && $0.logicalScheduledDate.map { calendar.isDateInToday($0) } == true
                && manualCompletionMatches(activity.activityType, modality: $0.modality)
                && activity.durationSecs >= $0.durationSeconds / 2
        }
        return matches.count == 1 ? matches.first : nil
    }

    var body: some View {
        if !dismissed, let match {
            VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                Text(manualCompletionText("group_question")).font(.headline)
                Text(BuiltinWorkoutText.localized(match.title)).font(.subheadline).foregroundStyle(.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack { groupActions(match) }
                    VStack(alignment: .leading) { groupActions(match) }
                }.buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: OutboundRadius.control)).disabled(busy)
                if busy { ProgressView() }
            }
            .overlay(alignment: .top) {
                if let toast { Text(toast).font(.subheadline).padding().background(.regularMaterial, in: Capsule()).accessibilityAddTraits(.updatesFrequently) }
            }
            .task(id: toast) {
                guard toast != nil else { return }
                do { try await Task.sleep(for: .seconds(4)); toast = nil } catch { /* Toast dismissed. */ }
            }
        }
    }

    @ViewBuilder private func groupActions(_ workout: TrainingPlanWorkout) -> some View {
        Button { Task { await link(workout) } } label: { Text(manualCompletionText("count")).outboundTapTarget() }
        Button { dismissed = true } label: { Text(manualCompletionText("not_now")).outboundTapTarget() }
    }

    private func link(_ workout: TrainingPlanWorkout) async {
        busy = true
        defer { busy = false }
        let context = ActivityAccountBoundary.current
        do {
            try await ActivityAccountBoundary.$operation.withValue(context) {
                await activityStore.syncPendingActivitiesIfNeeded()
                try ActivityAccountBoundary.validate()
                guard let serverID = activityStore.activity(id: activity.id)?.sync?.serverActivityId else {
                    toast = manualCompletionText("sync_first")
                    return
                }
                try await trainingPlanStore.setManualCompletion(workoutID: workout.id, action: "link", activityID: serverID)
                do { try await activityStore.refreshCompletionAssociations() }
                catch is CancellationError { return }
                catch { ActivityDiagnosticLog.error(.sync, "Group workout association refresh failed error=\(ActivityDiagnosticLog.errorCategory(error))") }
                dismissed = true
                await analytics?.track(.init(.featureExposed, properties: [.feature: .string("group_workout_completion"), .result: .string("success")]))
            }
        } catch is CancellationError { }
        catch {
            ActivityDiagnosticLog.error(.sync, "Group workout completion failed error=\(ActivityDiagnosticLog.errorCategory(error))")
            toast = manualCompletionText("failed")
            await analytics?.track(.init(.featureExposed, properties: [.feature: .string("group_workout_completion"), .result: .string("failure")]))
        }
    }
}
