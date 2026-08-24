import SwiftUI

struct TrainingPlanPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let recommendations: [TrainingPlanRecommendation]
    let isRefreshing: Bool
    let accentColor: Color
    let onSelectPlan: (TrainingPlanRecommendation) -> Void
    let onUsePlan: (TrainingPlanRecommendation) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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
                    Text("Week \(week.index): \(week.focus)")
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
                Text(workout.title)
                    .font(.subheadline.weight(.semibold))
                Text("\(workout.durationLabel) • \(workout.effortLabel)")
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

    let activePlan: ActiveTrainingPlan
    let week: TrainingPlanWeekSnapshot
    let todaySuggestion: TodayTrainingSuggestion?
    let accentColor: Color
    var onChangePlan: (() -> Void)? = nil
    var onEndPlan: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(activePlan.localizedTitle)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                    Text(activePlan.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    activeStat("Plan length", value: "\(activePlan.durationWeeks) weeks")
                    activeStat("Current week", value: "\(week.currentWeekIndex) of \(week.totalWeeks)")
                    activeStat("Weekly rhythm", value: "\(activePlan.sessionsPerWeek)x sessions")
                    activeStat("Target time", value: "\(activePlan.targetWeeklyMinutes) min")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("This week")
                        .font(.headline)
                    Text(week.focus)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(accentColor)
                    Text(week.summaryLine)
                        .font(.subheadline.weight(.semibold))
                    Text(week.weekSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    TrainingPlanProgressBar(progress: week.progressPercent, accentColor: accentColor)
                    Text(week.guideLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                if let todaySuggestion {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Today's recommendation")
                            .font(.headline)
                        Text(todaySuggestion.title)
                            .font(.title3.weight(.bold))
                        Text(todaySuggestion.detail)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(accentColor)
                        Text(todaySuggestion.guideLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let adjustmentLine = todaySuggestion.adjustmentLine {
                            Label(adjustmentLine, systemImage: "heart.text.square.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(accentColor)
                        }

                        ForEach(todaySuggestion.stepSummary.prefix(4), id: \.self) { step in
                            Text(step)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(18)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Today's recommendation")
                            .font(.headline)
                        Text("No session scheduled today")
                            .font(.title3.weight(.bold))
                        Text("Use the week schedule below, or change/end the plan from Plan Details options.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Week schedule")
                        .font(.headline)
                    ForEach(week.scheduledWorkouts) { workout in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("\(workout.dayLabel) • \(workout.title)")
                                    .font(.subheadline.weight(.semibold))
                                if workout.isOptional {
                                    Spacer()
                                    Text("Optional")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text("\(workout.durationLabel) • \(workout.effortLabel)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(accentColor)
                            Text(workout.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 4)
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
            }
            .padding()
        }
        .navigationTitle("Plan Details")
        .toolbar {
            if onChangePlan != nil || onEndPlan != nil {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        if let onChangePlan {
                            Button("Change plan", systemImage: "arrow.triangle.2.circlepath", action: onChangePlan)
                        }
                        if let onEndPlan {
                            Button("End plan", systemImage: "calendar.badge.minus", role: .destructive, action: onEndPlan)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Plan options")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }

    private func activeStat(_ label: String, value: String) -> some View {
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
}

struct ActiveTrainingPlanPendingDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let activePlan: ActiveTrainingPlan
    let accentColor: Color

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(activePlan.localizedTitle)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                    Text(activePlan.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    activeStat("Plan length", value: "\(activePlan.durationWeeks) weeks")
                    activeStat("Weekly rhythm", value: "\(activePlan.sessionsPerWeek)x sessions")
                    activeStat("Target time", value: "\(activePlan.targetWeeklyMinutes) min")
                    activeStat("Long session", value: "\(activePlan.longSessionMinutes) min")
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

    private func activeStat(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(accentColor)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
