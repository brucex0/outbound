#if DEBUG
import SwiftUI

/// Developer-only entry using the production DTO conversion, details and countdown views.
struct DebugRunningPlanHarness: View {
    @Environment(\.outboundTheme) private var theme
    @EnvironmentObject private var guideCatalogStore: GuideCatalogStore
    @State private var fixture = DebugRunningPlanFixture.load()
    @State private var details = true
    @State private var index = 0
    @State private var failsNextBenchmarkSave = false
    @State private var showsLongRouteName = true
    @State private var simulatesCachedUndatedSchedule = false

    private var phases: [SessionIntentStep] {
        fixture?.todaySuggestion?.suggestedSession.intent.workoutSteps ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Synthetic planning fixture").font(.headline)
                    if !phases.isEmpty {
                        DebugRunningPhaseView(step: phases[index], index: index, count: phases.count,
                            routeName: showsLongRouteName ? "Interlaken–Grindelwald Panorama Trail · North ridge" : nil)
                        Button("Next phase") { index = (index + 1) % phases.count }
                        Toggle("Show long route name", isOn: $showsLongRouteName)
                        Toggle("Simulate saved schedule without dates", isOn: $simulatesCachedUndatedSchedule)
                        Button("Plan details") { details = true }
                    } else {
                        Text("Add planning-fixture.json to simulator Documents, then relaunch.")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .task {
                if ProcessInfo.processInfo.arguments.contains("-OutboundDebugReceiptRoundtrip") { await DebugRunningPlanFixture.verifyReceiptTransport() }
            }
            .sheet(isPresented: $details) {
                if let plan = fixture?.activePlan, let week = fixture?.currentWeek {
                    let reviewPlan = planForDisplay(plan)
                    let reviewWeek = weekForDisplay(week)
                    NavigationStack {
                        ActiveTrainingPlanDetailView(activePlan: reviewPlan, week: reviewWeek,
                            todaySuggestion: fixture?.todaySuggestion, accentColor: theme.accentColor, benchmarkSaveOverride: saveSyntheticBenchmark)
                            .safeAreaInset(edge: .bottom) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Toggle("Fail next benchmark save (synthetic)", isOn: $failsNextBenchmarkSave)
                                    Button {
                                        guideCatalogStore.setTheme(guideCatalogStore.selectedTheme == .victoryGold ? .neonPulse : .victoryGold)
                                    } label: {
                                        Text("Theme: \(guideCatalogStore.selectedTheme.displayName)")
                                            .fixedSize(horizontal: false, vertical: true)
                                            .frame(minHeight: 44, alignment: .leading)
                                    }
                                    .accessibilityValue(guideCatalogStore.selectedTheme.displayName)
                                    .accessibilityHint("Switches between Victory Gold and Neon Pulse.")
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                                .background(.bar)
                            }
                    }
                }
            }
        }
    }

    private func saveSyntheticBenchmark(_ report: RunningBenchmarkReport?) async throws {
        let request = RunningBenchmarkUpdateRequest(runningBenchmark: report)
        let encoded = try JSONEncoder().encode(request)
        if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try encoded.write(to: directory.appendingPathComponent("benchmark-request.json"))
        }
        let decoded = try JSONDecoder().decode(RunningBenchmarkUpdateRequest.self, from: encoded)
        guard decoded.runningBenchmark == report else { throw APIError.http(statusCode: 422, message: "Synthetic serialization failure", code: "running_benchmark_invalid") }
        if failsNextBenchmarkSave {
            failsNextBenchmarkSave = false
            throw APIError.http(statusCode: 422, message: "Synthetic rejected input", code: "running_benchmark_invalid")
        }
        guard let next = DebugRunningPlanFixture.load(filename: report == nil ? "planning-benchmark-removed.json" : "planning-benchmark-corrected.json") else {
            throw APIError.http(statusCode: 409, message: "Synthetic canonical state unavailable", code: nil)
        }
        fixture = next
    }

    private func planForDisplay(_ value: ActiveTrainingPlan) -> ActiveTrainingPlan {
        var result = value
        if simulatesCachedUndatedSchedule { result.plannedSchedule = nil }
        return result
    }

    private func weekForDisplay(_ value: TrainingPlanWeekSnapshot) -> TrainingPlanWeekSnapshot {
        guard simulatesCachedUndatedSchedule else { return value }
        let workouts = value.scheduledWorkouts.map { workout in
            TrainingPlanWorkout(
                id: workout.id,
                scheduledDate: nil,
                title: workout.title,
                kind: workout.kind,
                dayLabel: workout.dayLabel,
                summary: workout.summary,
                purpose: workout.purpose,
                guideCue: workout.guideCue,
                effortLabel: workout.effortLabel,
                durationSeconds: workout.durationSeconds,
                distanceLabel: workout.distanceLabel,
                targetCalories: workout.targetCalories,
                steps: workout.steps,
                isOptional: workout.isOptional,
                status: workout.status
            )
        }
        return TrainingPlanWeekSnapshot(
            currentWeekIndex: value.currentWeekIndex,
            totalWeeks: value.totalWeeks,
            completedSessions: value.completedSessions,
            targetSessions: value.targetSessions,
            completedMinutes: value.completedMinutes,
            targetMinutes: value.targetMinutes,
            progressPercent: value.progressPercent,
            summaryLine: value.summaryLine,
            guideLine: value.guideLine,
            focus: value.focus,
            weekSummary: value.weekSummary,
            scheduledWorkouts: workouts,
            notes: value.notes
        )
    }
}
#endif
