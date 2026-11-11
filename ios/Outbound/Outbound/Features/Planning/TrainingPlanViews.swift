import SwiftUI

private struct TrainingPlanWorkoutWeekGroup: Identifiable {
    let index: Int
    let title: String
    let workouts: [TrainingPlanWorkout]
    var id: Int { index }
}

struct TrainingPlanPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let recommendations: [TrainingPlanRecommendation]
    let isRefreshing: Bool
    let accentColor: Color
    let onBuildPlan: () -> Void
    let onSelectPlan: (TrainingPlanRecommendation) -> Void
    let onUsePlan: (TrainingPlanRecommendation) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Button(action: onBuildPlan) {
                    HStack(spacing: 14) {
                        Image(systemName: "sparkles").font(.title2.weight(.bold))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(String(localized: "plan_builder.build", defaultValue: "Build my plan")).font(.headline)
                            Text(String(localized: "plan_builder.build.detail", defaultValue: "Create a plan around your goals, activities, and week.")).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)

                if recommendations.isEmpty {
                    HStack(spacing: 10) {
                        if isRefreshing {
                            ProgressView()
                        }
                        Text(isRefreshing ? "Loading plans..." : "No alternate plans are available right now.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else if isRefreshing {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Refreshing plans")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(recommendations) { recommendation in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(recommendation.template.localizedTitle)
                            .font(.headline)

                        Text(recommendation.template.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 8) {
                            pill("\(recommendation.durationWeeks) weeks")
                            pill("\(recommendation.sessionsPerWeek)x / week")
                            pill("\(recommendation.targetWeeklyMinutes) min")
                        }

                        Label(recommendation.template.source?.name == "Plainstride plan standards" ? "Curated" : "Reviewed plan", systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(accentColor)

                        if let openingWeek = recommendation.template.weeks.first {
                            Text(openingWeek.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Text(recommendation.rationale)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 10) {
                            Button("Details") {
                                onSelectPlan(recommendation)
                            }
                            .buttonStyle(.bordered)
                            .tint(accentColor)

                            Button("Use plan") {
                                onUsePlan(recommendation)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(accentColor)
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            .padding()
        }
        .navigationTitle("More Plans")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemBackground), in: Capsule())
    }
}
struct TrainingPlanRecommendationDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let recommendation: TrainingPlanRecommendation
    let accentColor: Color
    let onUsePlan: () -> Void
    let onMorePlans: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                statGrid
                section("Plan standard", text: planStandardText)
                section("Why this fits", text: recommendation.rationale)
                section("What to expect", text: recommendation.template.summary)
                section("Tradeoff", text: recommendation.tradeoff)
                highlightsSection
                weekPreviewSection
            }
            .padding()
        }
        .navigationTitle("Plan Details")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Button("More plans") {
                    dismiss()
                    onMorePlans()
                }
                .buttonStyle(.bordered)
                .tint(accentColor)

                Button("Use this plan") {
                    onUsePlan()
                }
                .buttonStyle(.borderedProminent)
                .tint(accentColor)
            }
            .font(.headline)
            .padding(.horizontal)
            .padding(.top, 10)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(recommendation.template.localizedTitle)
                .font(.system(.title2, design: .rounded).weight(.bold))
            Text(recommendation.template.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            detailStat("Length", value: "\(recommendation.durationWeeks) weeks")
            detailStat("Weekly rhythm", value: "\(recommendation.sessionsPerWeek)x sessions")
            detailStat("Target time", value: "\(recommendation.targetWeeklyMinutes) min")
            detailStat("Long day", value: "\(recommendation.longSessionMinutes) min")
        }
    }

    private func detailStat(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func section(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var highlightsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Plan shape")
                .font(.headline)
            ForEach(recommendation.template.highlights, id: \.self) { highlight in
                Label(highlight, systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var weekPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Week Preview")
                .font(.headline)
            ForEach(recommendation.template.weeks.prefix(2)) { week in
                VStack(alignment: .leading, spacing: 8) {
                    Text("Week \(week.index): \(BuiltinWorkoutText.localized(week.focus))")
                        .font(.subheadline.weight(.semibold))
                    Text(week.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(week.workouts.filter { $0.durationSeconds > 0 }.prefix(3)) { workout in
                        workoutPreviewRow(workout)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private func workoutPreviewRow(_ workout: TrainingPlanWorkout) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(workout.dayLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(accentColor)
                .frame(width: 32, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(BuiltinWorkoutText.localized(workout.title))
                    .font(.subheadline.weight(.semibold))
                Text("\(workout.durationLabel) • \(workout.intervalEffortLabel ?? BuiltinWorkoutText.localized(workout.effortLabel))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var planStandardText: String {
        if recommendation.template.source?.name == "Plainstride plan standards" {
            return "Plainstride-authored and benchmarked against established road-running structure: mostly easy running, controlled quality, cutback weeks, and event-specific tapering."
        }
        return "Reviewed against Plainstride's guidance standards for safe progression, clear recovery, and practical workout purpose."
    }
}

struct ActiveTrainingPlanDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.analyticsManager) private var analyticsManager
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    @State private var expandedWorkoutIDs: Set<String> = []

    let activePlan: ActiveTrainingPlan
    let week: TrainingPlanWeekSnapshot
    let todaySuggestion: TodayTrainingSuggestion?
    let accentColor: Color
    var onChangePlan: (() -> Void)? = nil
    var onEndPlan: (() -> Void)? = nil
    var benchmarkSaveOverride: ((RunningBenchmarkReport?) async throws -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                    Text(activePlan.localizedTitle)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                    TrainingPlanManagementActions(onChangePlan: onChangePlan, onEndPlan: onEndPlan)
                    if let progress = activePlan.programmeProgress, progress.programme != nil || progress.requiresReview { RunningProgrammeProgressView(progress: progress) }
                    if let benchmark = activePlan.runningBenchmark {
                        RunningBenchmarkManagementRow(context: benchmark, saveOverride: benchmarkSaveOverride)
                    }
                    if let goal = activePlan.raceGoal {
                        RaceGoalCard(goal: goal)
                    } else {
                        Text(String(format: String(localized: "plan.details.weekly_rhythm", defaultValue: "%d planned sessions each week"), activePlan.sessionsPerWeek))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(String(localized: "plan.details.your_scheduled_workouts", defaultValue: "Your scheduled workouts"))
                        .font(.headline)
                    if let throughDate = scheduleCoverageDate {
                        Text(String(format: String(localized: "plan.details.scheduled_through", defaultValue: "Workouts scheduled through %@"), throughDate.formatted(date: .abbreviated, time: .omitted)))
                            .font(.subheadline.weight(.semibold))
                    }
                    Text(String(localized: "plan.details.schedule_adapts", defaultValue: "Your scheduled workouts can change as your training progresses."))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("This week")
                            .font(.subheadline.weight(.semibold))
                        Text(week.summaryLine)
                            .font(.subheadline)
                        TrainingPlanProgressBar(progress: week.progressPercent, accentColor: accentColor)
                        if week.weekSummary != activePlan.subtitle {
                            Text(week.weekSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(week.guideLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 6)

                    if let todaySuggestion, !scheduleWorkouts.contains(where: { $0.id == todaySuggestion.suggestedSession.plannedWorkoutID }) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(String(localized: "plan.details.today_recommendation", defaultValue: "Today's recommendation"))
                                .font(.subheadline.weight(.semibold))
                            Text(todaySuggestion.title)
                                .font(.subheadline.weight(.semibold))
                            Text(todaySuggestion.detail)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(accentColor)
                            Text(todaySuggestion.guideLine)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 6)
                    }

                    if scheduleGroups.isEmpty {
                        Text(String(localized: "plan.details.no_scheduled_workouts", defaultValue: "No workouts are scheduled right now."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(scheduleGroups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(group.workouts) { workout in
                                scheduledWorkoutRow(workout)
                            }
                        }
                        .padding(.top, 6)
                    }
                    ForEach(week.notes, id: \.self) { note in
                        Label(note, systemImage: "info.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(18)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                if activePlan.raceGoal?.targetDate != nil, let roadmap = activePlan.roadmap {
                    TrainingPlanRoadmapSection(roadmap: roadmap)
                } else if activePlan.raceGoal?.targetDate != nil {
                    Text(String(localized: "plan.details.roadmap_syncing", defaultValue: "The training roadmap will appear when the latest plan details finish syncing."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "plan.details.what_comes_next", defaultValue: "What comes next"))
                            .font(.headline)
                        Text(activePlan.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(String(localized: "plan.details.rolling_outlook", defaultValue: "This is a rolling schedule based on your goal and recent training. New workouts appear as the plan updates."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(18)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            .padding()
        }
        .navigationTitle("Plan Details")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }

    private var scheduleCoverageDate: Date? {
        if activePlan.plannedSchedule != nil, activePlan.raceGoal != nil, let value = activePlan.roadmap?.detailedThroughDate {
            return raceDate(value)
        }
        return scheduleWorkouts.compactMap(\.scheduledDate).max()
    }

    private var scheduleWorkouts: [TrainingPlanWorkout] {
        activePlan.plannedSchedule ?? week.scheduledWorkouts
    }

    private var scheduleGroups: [TrainingPlanWorkoutWeekGroup] {
        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: activePlan.createdAt)
        let dated = scheduleWorkouts.compactMap { workout -> (Int, TrainingPlanWorkout)? in
            guard let date = workout.scheduledDate,
                  let days = calendar.dateComponents([.day], from: anchor, to: calendar.startOfDay(for: date)).day else { return nil }
            return (max(0, days / 7), workout)
        }
        let grouped = Dictionary(grouping: dated, by: { $0.0 })
        var groups = grouped.keys.sorted().compactMap { index -> TrainingPlanWorkoutWeekGroup? in
            guard let start = calendar.date(byAdding: .day, value: index * 7, to: anchor),
                  let end = calendar.date(byAdding: .day, value: 6, to: start),
                  let entries = grouped[index]?.map(\.1) else { return nil }
            let format = String(localized: "plan.details.workout_week", defaultValue: "Week %1$d · %2$@–%3$@")
            let title = String(format: format, index + 1,
                               start.formatted(date: .abbreviated, time: .omitted),
                               end.formatted(date: .abbreviated, time: .omitted))
            return TrainingPlanWorkoutWeekGroup(index: index, title: title, workouts: entries.sorted { ($0.scheduledDate ?? .distantPast) < ($1.scheduledDate ?? .distantPast) })
        }
        let undated = scheduleWorkouts.filter { $0.scheduledDate == nil }
        if !undated.isEmpty {
            groups.append(TrainingPlanWorkoutWeekGroup(
                index: Int.min,
                title: String(localized: "plan.details.undated_workouts", defaultValue: "Saved workouts · dates unavailable"),
                workouts: undated
            ))
        }
        return groups
    }

    @ViewBuilder
    private func scheduledWorkoutRow(_ workout: TrainingPlanWorkout) -> some View {
        let effectiveWorkout = todaySuggestion?.suggestedSession.plannedWorkoutID == workout.id ? todaySuggestion?.workout : nil
        let displayTitle = effectiveWorkout?.title ?? workout.title
        let displayDuration = effectiveWorkout?.durationLabel ?? workout.durationLabel
        let displayEffort = effectiveWorkout.map { $0.intervalEffortLabel ?? BuiltinWorkoutText.localized($0.effortLabel) }
            ?? workout.intervalEffortLabel
            ?? BuiltinWorkoutText.localized(workout.effortLabel)
        let displaySteps = effectiveWorkout?.steps ?? workout.steps
        let scheduledGoal = workout.targetCalories.map {
            String(format: String(localized: "activity.goal.calories.format", defaultValue: "%d kcal"), locale: .autoupdatingCurrent, $0)
        } ?? workout.distanceLabel
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(workout.scheduledDate?.formatted(date: .complete, time: .omitted) ?? workout.dayLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(BuiltinWorkoutText.localized(displayTitle))
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if workout.isOptional {
                    Text("Optional")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            if effectiveWorkout != nil, let todaySuggestion {
                Text(todaySuggestion.detail)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor)
                    .fixedSize(horizontal: false, vertical: true)
                if (effectiveWorkout?.targetCalories != nil || effectiveWorkout?.distanceLabel != nil),
                   let phaseEffort = effectiveWorkout?.intervalEffortLabel {
                    Text(phaseEffort)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accentColor)
                }
                Text(todaySuggestion.guideLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let adjustment = todaySuggestion.adjustmentLine {
                    Label(adjustment, systemImage: "heart.text.square.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accentColor)
                }
            } else {
                Text([scheduledGoal, displayDuration, displayEffort].compactMap { $0 }.joined(separator: " • "))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor)
            }
                if let status = workout.status, status != "planned" {
                    Text(workoutStatusLabel(status))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !displaySteps.isEmpty {
                    DisclosureGroup(isExpanded: Binding(
                        get: { expandedWorkoutIDs.contains(workout.id) },
                        set: { isExpanded in
                            if isExpanded { expandedWorkoutIDs.insert(workout.id) }
                            else { expandedWorkoutIDs.remove(workout.id) }
                            Task {
                                await analyticsManager?.track(.init(.featureExposed, properties: [
                                    .feature: .string("plan_workout_phases"),
                                    .result: .string(isExpanded ? "expanded" : "collapsed"),
                                ]))
                            }
                        }
                    )) {
                        ForEach(displaySteps) { step in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(BuiltinWorkoutText.localized(step.label)) · \(step.durationLabel)")
                                    .font(.caption.weight(.semibold))
                                if let detail = step.detail, !detail.isEmpty {
                                    Text(BuiltinWorkoutText.localized(detail))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                if let pace = step.estimatedPace?.rangeLabel(units: measurementPreferences.unitSystem) {
                                    Text(pace).font(.caption).foregroundStyle(.secondary)
                                }
                                if let rpe = step.rpeLabel {
                                    Text(rpe)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    } label: {
                        Text(String(localized: "plan.details.workout_phases", defaultValue: "Workout phases"))
                            .font(.caption.weight(.semibold))
                            .frame(minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("plan.details.phases.\(workout.id)")
                }
            Text(workout.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
    }

    private func workoutStatusLabel(_ status: String) -> String {
        switch status {
        case "completed": return String(localized: "plan.details.status.completed", defaultValue: "Completed")
        case "skipped": return String(localized: "plan.details.status.skipped", defaultValue: "Skipped")
        case "missed": return String(localized: "plan.details.status.missed", defaultValue: "Missed")
        default: return String(localized: "plan.details.status.scheduled", defaultValue: "Scheduled")
        }
    }

}

private struct TrainingPlanManagementActions: View {
    @Environment(\.analyticsManager) private var analyticsManager

    let onChangePlan: (() -> Void)?
    let onEndPlan: (() -> Void)?
    @State private var confirmsEndPlan = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: OutboundSpacing.section) { actionButtons }
            VStack(alignment: .leading, spacing: 0) { actionButtons }
        }
        .confirmationDialog(String(localized: "plan.details.end_title", defaultValue: "End this plan?"), isPresented: $confirmsEndPlan, titleVisibility: .visible) {
            Button("End plan", role: .destructive) { onEndPlan?() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(String(localized: "plan.details.end_message", defaultValue: "This will remove the active plan and its upcoming workouts. Your saved activities will stay."))
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if let onChangePlan {
            Button(action: onChangePlan) {
                Text("Change plan")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .accessibilityIdentifier("plan.details.change")
        }
        if onEndPlan != nil {
            Button(role: .destructive) {
                confirmsEndPlan = true
                Task {
                    await analyticsManager?.track(.init(.featureExposed, properties: [
                        .feature: .string("plan_end_confirmation"),
                    ]))
                }
            } label: {
                Text("End plan")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .accessibilityIdentifier("plan.details.end")
        }
    }
}

struct ActiveTrainingPlanPendingDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let activePlan: ActiveTrainingPlan
    let accentColor: Color
    var onChangePlan: (() -> Void)? = nil
    var onEndPlan: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                    Text(activePlan.localizedTitle)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                    TrainingPlanManagementActions(onChangePlan: onChangePlan, onEndPlan: onEndPlan)
                    if let benchmark = activePlan.runningBenchmark { RunningBenchmarkManagementRow(context: benchmark) }
                    if let goal = activePlan.raceGoal {
                        RaceGoalCard(goal: goal)
                    } else {
                        Text(String(format: String(localized: "plan.details.weekly_rhythm", defaultValue: "%d planned sessions each week"), activePlan.sessionsPerWeek))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Plan details are loading")
                        .font(.headline)
                    Text("The active plan is set. The week schedule will appear here as soon as the latest plan snapshot finishes syncing.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                if let roadmap = activePlan.roadmap {
                    TrainingPlanRoadmapSection(roadmap: roadmap)
                }
            }
            .padding()
        }
        .navigationTitle("Plan Details")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }

}

struct ActiveTrainingPlanSyncingDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProgressView()
                .tint(accentColor)

            Text("Plan details are syncing")
                .font(.system(.title2, design: .rounded).weight(.bold))

            Text("The activity suggestion is linked to an active plan. The full plan will appear here as soon as the latest plan state finishes loading.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .navigationTitle("Plan Details")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}

struct TrainingPlanProgressBar: View {
    let progress: Double
    let accentColor: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.systemBackground))
                Capsule()
                    .fill(accentColor)
                    .frame(width: geometry.size.width * progress)
            }
        }
        .frame(height: 10)
    }
}
