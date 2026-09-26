import CoreLocation
import SwiftUI

struct RunnerProgressView: View {
    @EnvironmentObject private var activityStore: ActivityStore
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    @EnvironmentObject private var gearStore: GearStore
    @Environment(\.analyticsManager) private var analyticsManager
    @State private var selectedTab: RunnerProgressTab = .now
    @State private var selectedTrendRange: ProgressTrendRange = .fourWeeks
    @State private var selectedTrendMetric: ProgressMetric = .distance
    @State private var selectedActivityType = ActivityType.running.rawValue
    @State private var showsManualWorkoutEntry = false
    @State private var saveToast: String?
    @State private var didTrackProgressOpen = false

    private var snapshot: ProgressStatsSnapshot {
        ProgressStatsEngine.snapshot(from: activityStore.activities.map(\.progressActivity))
    }

    private var recentActivities: [SavedActivity] {
        activityStore.activities.filter { $0.durationSecs > 60 }
    }

    private var availableActivityTypes: [String] {
        Array(Set(activityStore.activities.map { $0.activityType.rawValue })).sorted()
    }

    private var trendSnapshot: ProgressStatsSnapshot {
        let filtered = activityStore.activities.filter { $0.activityType.rawValue == selectedActivityType }
        return ProgressStatsEngine.snapshot(from: filtered.map(\.progressActivity))
    }

    private var selectedTrendSeries: ProgressTrendSeries? {
        trendSnapshot.trendSeries.first { $0.range == selectedTrendRange }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if snapshot.eligibleActivityCount == 0 {
                    emptyState
                } else {
                    progressTabs
                    selectedTabContent
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsManualWorkoutEntry = true
                } label: {
                    Label("Add Workout", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showsManualWorkoutEntry) {
            ManualWorkoutEntryView { _ in showSaveToast() }
                .environmentObject(activityStore)
                .environmentObject(gearStore)
                .environmentObject(measurementPreferences)
        }
        .overlay(alignment: .top) {
            if let saveToast {
                Text(saveToast)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task {
            if !availableActivityTypes.contains(selectedActivityType), let first = availableActivityTypes.first {
                selectedActivityType = first
            }
            guard !didTrackProgressOpen else { return }
            didTrackProgressOpen = true
            await analyticsManager?.track(.init(.progressSurfaceOpened, properties: [
                .entrySource: .string("me"),
                .countBucket: .string(ProductAnalyticsBucket.count(snapshot.eligibleActivityCount))
            ]))
            if let firstInsight = snapshot.insights.first {
                await analyticsManager?.track(.init(.progressInsightsExposed, properties: [
                    .countBucket: .string(ProductAnalyticsBucket.count(snapshot.insights.count)),
                    .sourceType: .string(firstInsight.category.rawValue)
                ]))
            }
        }
        .onChange(of: selectedTab) { _, value in
            trackProgressControl("tab", selection: value.rawValue)
        }
        .onChange(of: selectedTrendRange) { _, value in
            trackProgressControl("range", selection: value.rawValue)
        }
        .onChange(of: selectedTrendMetric) { _, value in
            trackProgressControl("metric", selection: value.rawValue)
        }
        .onChange(of: selectedActivityType) { _, value in
            trackProgressControl("activity_type", selection: value)
        }
    }

    private var progressTabs: some View {
        Picker("Progress view", selection: $selectedTab) {
            ForEach(RunnerProgressTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Progress sections")
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .now:
            VStack(alignment: .leading, spacing: 18) {
                topSummary
                companionSummary
                recentStatsSection
            }
        case .trends:
            VStack(alignment: .leading, spacing: 18) {
                comparisonSection
                trendsSection
            }
        case .insights:
            insightsSection
        case .records:
            VStack(alignment: .leading, spacing: 18) {
                bestEffortsSection
                personalRecordsSection
                racePredictionsSection
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(.orange)
            Text("Save your first activity to start building stats.")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Weekly totals, best efforts, and trends will appear here after you record.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .padding()
    }

    private var topSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("This Week")
                .font(.title2.bold())

            HStack(spacing: 10) {
                ProgressMetricTile(
                    title: String(localized: "Distance"),
                    value: measurementPreferences.unitSystem.distanceValueString(
                        meters: snapshot.currentWeek.distanceMeters,
                        fractionDigits: 1
                    ),
                    unit: measurementPreferences.unitSystem.distanceUnit,
                    comparison: weekDeltaLabel(for: .distance)
                )
                ProgressMetricTile(
                    title: String(localized: "progress.activities", defaultValue: "Activities"),
                    value: "\(snapshot.currentWeek.activityCount)",
                    unit: String(localized: "progress.saved", defaultValue: "saved"),
                    comparison: weekDeltaLabel(for: .activities)
                )
            }

            HStack(spacing: 10) {
                ProgressMetricTile(
                    title: String(localized: "Time"),
                    value: snapshot.currentWeek.durationSeconds.formatted(),
                    unit: String(localized: "progress.moving", defaultValue: "moving"),
                    comparison: weekDeltaLabel(for: .duration)
                )
                ProgressMetricTile(
                    title: String(localized: "progress.elevation", defaultValue: "Elevation"),
                    value: measurementPreferences.unitSystem.elevationString(
                        meters: snapshot.currentWeek.elevationMeters
                    ),
                    unit: String(localized: "progress.gained", defaultValue: "gained"),
                    comparison: weekDeltaLabel(for: .elevation)
                )
            }
        }
    }

    private var comparisonSection: some View {
        ProgressSection(title: String(localized: "progress.period_comparisons", defaultValue: "Period Comparisons")) {
            VStack(spacing: 0) {
                ForEach(snapshot.comparisons) { comparison in
                    ProgressComparisonRow(
                        comparison: comparison,
                        unitSystem: measurementPreferences.unitSystem
                    )
                    if comparison.id != snapshot.comparisons.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private var trendsSection: some View {
        ProgressSection(title: String(localized: "progress.trend_history", defaultValue: "Trend History")) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    progressMenu(title: activityTypeTitle(selectedActivityType), systemImage: "figure.run") {
                        ForEach(availableActivityTypes, id: \.self) { type in
                            Button(activityTypeTitle(type)) { selectedActivityType = type }
                        }
                    }
                    progressMenu(title: trendRangeTitle(selectedTrendRange), systemImage: "calendar") {
                        ForEach(ProgressTrendRange.allCases) { range in
                            Button(trendRangeTitle(range)) { selectedTrendRange = range }
                        }
                    }
                    progressMenu(title: metricTitle(selectedTrendMetric), systemImage: "chart.bar") {
                        ForEach(ProgressMetric.allCases) { metric in
                            Button(metricTitle(metric)) { selectedTrendMetric = metric }
                        }
                    }
                }

                if let series = selectedTrendSeries, !series.buckets.isEmpty {
                    let maximum = trendMaximum(series.buckets, metric: selectedTrendMetric)
                    VStack(spacing: 10) {
                        ForEach(series.buckets) { bucket in
                            ProgressTrendRow(
                                bucket: bucket,
                                range: selectedTrendRange,
                                metric: selectedTrendMetric,
                                maximum: maximum,
                                unitSystem: measurementPreferences.unitSystem
                            )
                        }
                    }
                } else {
                    Text(String(localized: "progress.no_trend_data", defaultValue: "Save activities in this sport to build its trend."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "progress.insights_intro", defaultValue: "Plainstride explains the strongest patterns it can support with your saved activity data."))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if snapshot.insights.isEmpty {
                ProgressSection(title: String(localized: "progress.insights", defaultValue: "Insights")) {
                    Text(String(localized: "progress.insights_empty", defaultValue: "A few more saved activities will unlock grounded comparisons and patterns."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(snapshot.insights) { insight in
                    ProgressInsightCard(
                        insight: insight,
                        unitSystem: measurementPreferences.unitSystem
                    )
                }
            }
        }
    }

    private var bestEffortsSection: some View {
        ProgressSection(title: "Best Efforts") {
            VStack(spacing: 0) {
                ForEach(snapshot.bestEfforts) { effort in
                    BestEffortRow(effort: effort, unitSystem: measurementPreferences.unitSystem)
                    if effort.id != snapshot.bestEfforts.last?.id {
                        Divider().padding(.leading, 42)
                    }
                }
            }
        }
    }

    private var personalRecordsSection: some View {
        ProgressSection(title: "PR History") {
            if snapshot.personalRecords.isEmpty {
                Text("Longer saved runs unlock more PR distances.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(snapshot.personalRecords.prefix(8)) { record in
                        PersonalRecordRow(record: record)
                        if record.id != snapshot.personalRecords.prefix(8).last?.id {
                            Divider().padding(.leading, 42)
                        }
                    }
                }
            }
        }
    }

    private var racePredictionsSection: some View {
        ProgressSection(title: "Race Predictions") {
            if snapshot.racePredictions.isEmpty {
                Text("Save a few runs with clean distances to estimate race ranges.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(snapshot.racePredictions) { prediction in
                        RacePredictionRow(prediction: prediction)
                    }
                }
            }
        }
    }

    private var recentStatsSection: some View {
        ProgressSection(title: "Recent Activity Stats") {
            VStack(spacing: 10) {
                ForEach(recentActivities.prefix(6)) { activity in
                    RecentProgressActivityRow(
                        activity: activity,
                        notableEfforts: snapshot.bestEfforts.filter { $0.activityID == activity.id.uuidString },
                        unitSystem: measurementPreferences.unitSystem
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var companionSummary: some View {
        if let insight = snapshot.insights.first {
            ProgressInsightCard(
                insight: insight,
                unitSystem: measurementPreferences.unitSystem,
                compact: true
            )
        } else {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.orange)
                Text(String(localized: "progress.insights_empty", defaultValue: "A few more saved activities will unlock grounded comparisons and patterns."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func showSaveToast() {
        withAnimation { saveToast = String(localized: "Workout added") }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation { saveToast = nil }
        }
    }

    private func weekDeltaLabel(for metric: ProgressMetric) -> String? {
        guard let comparison = snapshot.comparisons.first(where: { $0.kind == .week }),
              let delta = comparison.delta(for: metric) else { return nil }
        if delta.previous == 0 {
            return delta.current > 0
                ? String(localized: "progress.new_this_period", defaultValue: "New this period")
                : nil
        }
        let percent = Int((delta.percent ?? 0).rounded())
        return String(
            format: String(localized: "progress.vs_last_week.format", defaultValue: "%+d%% vs last week"),
            locale: .autoupdatingCurrent,
            percent
        )
    }

    private func trendMaximum(_ buckets: [ProgressTrendBucket], metric: ProgressMetric) -> Double {
        if metric == .averagePace {
            return max(buckets.compactMap { $0.totals.averagePaceSecondsPerKilometer }.map { 1 / $0 }.max() ?? 0, 0.001)
        }
        return max(buckets.compactMap { $0.totals.value(for: metric) }.max() ?? 0, 1)
    }

    private func progressMenu<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu(content: content) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func trackProgressControl(_ control: String, selection: String) {
        Task {
            await analyticsManager?.track(.init(.progressControlChanged, properties: [
                .control: .string(control),
                .selectionType: .string(selection)
            ]))
        }
    }
}

private enum RunnerProgressTab: String, CaseIterable, Identifiable {
    case now
    case trends
    case insights
    case records

    var id: Self { self }

    var title: String {
        switch self {
        case .now: return String(localized: "progress.tab.now", defaultValue: "Now")
        case .trends: return String(localized: "progress.tab.trends", defaultValue: "Trends")
        case .insights: return String(localized: "progress.tab.insights", defaultValue: "Insights")
        case .records: return String(localized: "progress.tab.records", defaultValue: "Records")
        }
    }
}

private func activityTypeTitle(_ rawValue: String) -> String {
    switch rawValue {
    case ActivityType.running.rawValue: String(localized: "progress.sport.running", defaultValue: "Running")
    case ActivityType.cycling.rawValue: String(localized: "progress.sport.cycling", defaultValue: "Cycling")
    case ActivityType.hiking.rawValue: String(localized: "progress.sport.hiking", defaultValue: "Hiking")
    case ActivityType.walking.rawValue: String(localized: "progress.sport.walking", defaultValue: "Walking")
    case ActivityType.swimming.rawValue: String(localized: "progress.sport.swimming", defaultValue: "Swimming")
    case ActivityType.strengthTraining.rawValue: String(localized: "progress.sport.strength", defaultValue: "Strength")
    case ActivityType.mobility.rawValue: String(localized: "progress.sport.mobility", defaultValue: "Mobility")
    default: String(localized: "progress.sport.activity", defaultValue: "Activity")
    }
}

private func trendRangeTitle(_ range: ProgressTrendRange) -> String {
    switch range {
    case .fourWeeks: String(localized: "progress.range.4w", defaultValue: "4W")
    case .threeMonths: String(localized: "progress.range.3m", defaultValue: "3M")
    case .sixMonths: String(localized: "progress.range.6m", defaultValue: "6M")
    case .oneYear: String(localized: "progress.range.1y", defaultValue: "1Y")
    }
}

private func metricTitle(_ metric: ProgressMetric) -> String {
    switch metric {
    case .distance: String(localized: "Distance")
    case .duration: String(localized: "Time")
    case .activities: String(localized: "progress.activities", defaultValue: "Activities")
    case .elevation: String(localized: "progress.elevation", defaultValue: "Elevation")
    case .averagePace: String(localized: "progress.average_pace", defaultValue: "Avg Pace")
    }
}

private func comparisonTitle(_ kind: ProgressPeriodComparison.Kind) -> String {
    switch kind {
    case .week: String(localized: "progress.comparison.week", defaultValue: "Week over week")
    case .month: String(localized: "progress.comparison.month", defaultValue: "Month over month")
    case .rolling28Days: String(localized: "progress.comparison.rolling", defaultValue: "Rolling 28 days")
    }
}

private struct ProgressComparisonRow: View {
    let comparison: ProgressPeriodComparison
    let unitSystem: MeasurementUnitSystem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(comparisonTitle(comparison.kind))
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(deltaText)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 12) {
                Text(unitSystem.distanceString(meters: comparison.current.distanceMeters, fractionDigits: 1))
                Text(comparison.current.durationSeconds.formatted())
                Text(activityCountText)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
    }

    private var subtitle: String {
        switch comparison.kind {
        case .week, .month:
            String(localized: "progress.comparison.matched", defaultValue: "Compared at the same point in the period")
        case .rolling28Days:
            String(localized: "progress.comparison.previous_window", defaultValue: "Compared with the previous 28 days")
        }
    }

    private var deltaText: String {
        let primaryMetric: ProgressMetric = comparison.current.distanceMeters > 0 || comparison.previous.distanceMeters > 0
            ? .distance
            : .duration
        guard let delta = comparison.delta(for: primaryMetric) else { return "--" }
        if delta.previous == 0 {
            return delta.current > 0
                ? String(localized: "progress.new", defaultValue: "New")
                : String(localized: "progress.steady", defaultValue: "Steady")
        }
        return String(
            format: String(localized: "progress.percent_signed.format", defaultValue: "%+d%%"),
            locale: .autoupdatingCurrent,
            Int((delta.percent ?? 0).rounded())
        )
    }

    private var activityCountText: String {
        String(
            format: String(localized: "progress.activity_count.format", defaultValue: "%d activities"),
            locale: .autoupdatingCurrent,
            comparison.current.activityCount
        )
    }
}

private struct ProgressTrendRow: View {
    let bucket: ProgressTrendBucket
    let range: ProgressTrendRange
    let metric: ProgressMetric
    let maximum: Double
    let unitSystem: MeasurementUnitSystem

    var body: some View {
        HStack(spacing: 10) {
            Text(periodLabel)
                .font(.caption.weight(.semibold))
                .frame(width: 48, alignment: .leading)
                .foregroundStyle(.secondary)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill))
                    Capsule()
                        .fill(Color.orange)
                        .frame(width: max(value == nil ? 0 : 4, geometry.size.width * fillFraction))
                }
            }
            .frame(height: 10)

            Text(valueText)
                .font(.caption.monospacedDigit())
                .frame(width: 76, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(height: 24)
    }

    private var value: Double? { bucket.totals.value(for: metric) }

    private var fillFraction: Double {
        guard let value, value > 0, maximum > 0 else { return 0 }
        if metric == .averagePace { return min(1, (1 / value) / maximum) }
        return min(1, value / maximum)
    }

    private var periodLabel: String {
        switch range {
        case .fourWeeks, .threeMonths:
            bucket.startDate.formatted(.dateTime.month(.abbreviated).day())
        case .sixMonths, .oneYear:
            bucket.startDate.formatted(.dateTime.month(.abbreviated))
        }
    }

    private var valueText: String {
        guard let value else { return "--" }
        switch metric {
        case .distance:
            return unitSystem.distanceString(meters: value, fractionDigits: 1)
        case .duration:
            return Int(value.rounded()).formatted()
        case .activities:
            return String(Int(value.rounded()))
        case .elevation:
            return unitSystem.elevationString(meters: value)
        case .averagePace:
            return value.paceString(for: unitSystem)
        }
    }
}

private struct ProgressInsightCard: View {
    let insight: ProgressInsight
    let unitSystem: MeasurementUnitSystem
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: insight.symbolName)
                    .foregroundStyle(.orange)
                    .frame(width: 28, height: 28)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(confidenceTitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text(bodyText)
                .font(compact ? .subheadline : .body)
                .foregroundStyle(compact ? .secondary : .primary)

            if !compact {
                Label(evidenceText, systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "arrow.forward.circle.fill")
                        .foregroundStyle(.orange)
                    Text(actionText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var title: String {
        switch insight.category {
        case .volume: String(localized: "progress.insight.volume", defaultValue: "Training volume")
        case .consistency: String(localized: "progress.insight.consistency", defaultValue: "Consistency")
        case .endurance: String(localized: "progress.insight.endurance", defaultValue: "Long-run balance")
        case .efficiency: String(localized: "progress.insight.efficiency", defaultValue: "Pace efficiency")
        case .trainingLoad: String(localized: "progress.insight.load", defaultValue: "Training load")
        case .trainingBalance: String(localized: "progress.insight.balance", defaultValue: "Intensity balance")
        case .goals: String(localized: "progress.insight.goals", defaultValue: "Goal follow-through")
        case .pattern: String(localized: "progress.insight.pattern", defaultValue: "Your routine")
        }
    }

    private var confidenceTitle: String {
        switch insight.confidence {
        case .emerging: String(localized: "progress.confidence.emerging", defaultValue: "Emerging pattern")
        case .solid: String(localized: "progress.confidence.solid", defaultValue: "Solid pattern")
        case .strong: String(localized: "progress.confidence.strong", defaultValue: "Strong pattern")
        }
    }

    private var bodyText: String {
        switch insight.evidence {
        case .rollingDistance(let percent, _, _):
            return String(
                format: percent >= 0
                    ? String(localized: "progress.insight.volume.up.format", defaultValue: "Your rolling 28-day distance is %d%% higher than the previous 28 days.")
                    : String(localized: "progress.insight.volume.down.format", defaultValue: "Your rolling 28-day distance is %d%% lower than the previous 28 days."),
                locale: .autoupdatingCurrent,
                abs(percent)
            )
        case .activeWeeks(let count, let total):
            return String(
                format: String(localized: "progress.insight.consistency.body.format", defaultValue: "You recorded activity in %d of the last %d weeks."),
                locale: .autoupdatingCurrent,
                count,
                total
            )
        case .longRunShare(let percent, _, _):
            return String(
                format: String(localized: "progress.insight.endurance.body.format", defaultValue: "Your longest activity accounts for %d%% of this week's distance."),
                locale: .autoupdatingCurrent,
                percent
            )
        case .heartRateEfficiency(let pacePercent, let heartRateDifference):
            return String(
                format: pacePercent >= 0
                    ? String(localized: "progress.insight.efficiency.up.format", defaultValue: "Recent runs were %d%% faster at a similar average heart rate (%+d bpm).")
                    : String(localized: "progress.insight.efficiency.down.format", defaultValue: "Recent runs were %d%% slower at a similar average heart rate (%+d bpm)."),
                locale: .autoupdatingCurrent,
                abs(pacePercent),
                heartRateDifference
            )
        case .loadRamp(let percent, _, _):
            return String(
                format: percent >= 0
                    ? String(localized: "progress.insight.load.up.format", defaultValue: "Heart-rate-weighted load rose %d%% over the previous seven days.")
                    : String(localized: "progress.insight.load.down.format", defaultValue: "Heart-rate-weighted load fell %d%% from the previous seven days."),
                locale: .autoupdatingCurrent,
                abs(percent)
            )
        case .intensityBalance(let percent):
            return String(
                format: String(localized: "progress.insight.balance.body.format", defaultValue: "%d%% of recent heart-rate time was in zones 4–5."),
                locale: .autoupdatingCurrent,
                percent
            )
        case .goalCompletion(let completed, let total):
            return String(
                format: String(localized: "progress.insight.goals.body.format", defaultValue: "You completed %d of %d measurable activity goals in the last 28 days."),
                locale: .autoupdatingCurrent,
                completed,
                total
            )
        case .preferredTime(let dayPart, let percent, _):
            return String(
                format: String(localized: "progress.insight.pattern.body.format", defaultValue: "%d%% of your recent activities started in the %@."),
                locale: .autoupdatingCurrent,
                percent,
                dayPartTitle(dayPart)
            )
        }
    }

    private var evidenceText: String {
        switch insight.evidence {
        case .rollingDistance(_, let current, let previous):
            return String(
                format: String(localized: "progress.evidence.distance.format", defaultValue: "%@ now · %@ before"),
                locale: .autoupdatingCurrent,
                unitSystem.distanceString(meters: current, fractionDigits: 1),
                unitSystem.distanceString(meters: previous, fractionDigits: 1)
            )
        case .activeWeeks(let count, let total):
            return String(format: String(localized: "progress.evidence.weeks.format", defaultValue: "%d active weeks · %d-week window"), locale: .autoupdatingCurrent, count, total)
        case .longRunShare(_, let longest, let week):
            return String(
                format: String(localized: "progress.evidence.long_run.format", defaultValue: "%@ longest · %@ this week"),
                locale: .autoupdatingCurrent,
                unitSystem.distanceString(meters: longest, fractionDigits: 1),
                unitSystem.distanceString(meters: week, fractionDigits: 1)
            )
        case .heartRateEfficiency(let pace, let heartRate):
            return String(format: String(localized: "progress.evidence.efficiency.format", defaultValue: "%+d%% pace · %+d bpm"), locale: .autoupdatingCurrent, pace, heartRate)
        case .loadRamp(_, let current, let previous):
            return String(format: String(localized: "progress.evidence.load.format", defaultValue: "%.0f load now · %.0f before"), locale: .autoupdatingCurrent, current, previous)
        case .intensityBalance(let percent):
            return String(format: String(localized: "progress.evidence.intensity.format", defaultValue: "%d%% high intensity"), locale: .autoupdatingCurrent, percent)
        case .goalCompletion(let completed, let total):
            return String(format: String(localized: "progress.evidence.goals.format", defaultValue: "%d completed · %d measured"), locale: .autoupdatingCurrent, completed, total)
        case .preferredTime(let dayPart, let percent, let total):
            return String(format: String(localized: "progress.evidence.pattern.format", defaultValue: "%d%% %@ · %d activities"), locale: .autoupdatingCurrent, percent, dayPartTitle(dayPart), total)
        }
    }

    private var actionText: String {
        switch insight.evidence {
        case .rollingDistance(let percent, _, _):
            return abs(percent) >= 25 && percent > 0
                ? String(localized: "progress.action.volume_high", defaultValue: "Leave room for recovery before adding more volume.")
                : String(localized: "progress.action.volume", defaultValue: "Keep the next change gradual and let consistency lead.")
        case .activeWeeks:
            return String(localized: "progress.action.consistency", defaultValue: "Protect the routine with a short, doable next session.")
        case .longRunShare(let percent, _, _):
            return percent > 50
                ? String(localized: "progress.action.endurance_high", defaultValue: "Keep the next session easy; one activity carried most of the week.")
                : String(localized: "progress.action.endurance", defaultValue: "Build endurance gradually while keeping the rest of the week comfortable.")
        case .heartRateEfficiency(let pace, _):
            return pace >= 0
                ? String(localized: "progress.action.efficiency_up", defaultValue: "Keep effort controlled—the faster pace does not need to become a new minimum.")
                : String(localized: "progress.action.efficiency_down", defaultValue: "Treat this as context, not a verdict; terrain, fatigue, and weather can all matter.")
        case .loadRamp(let percent, _, _):
            return percent > 35
                ? String(localized: "progress.action.load_high", defaultValue: "Consider an easier day before the next demanding session.")
                : String(localized: "progress.action.load", defaultValue: "Watch how you feel and keep load changes gradual.")
        case .intensityBalance(let percent):
            return percent > 30
                ? String(localized: "progress.action.intensity_high", defaultValue: "A larger easy share can help absorb the harder work.")
                : String(localized: "progress.action.intensity", defaultValue: "Keep easy work genuinely easy and add intensity with purpose.")
        case .goalCompletion:
            return String(localized: "progress.action.goals", defaultValue: "Set targets that support the week instead of forcing every activity.")
        case .preferredTime(let dayPart, _, _):
            return String(
                format: String(localized: "progress.action.pattern.format", defaultValue: "When practical, protect a %@ window for the next session."),
                locale: .autoupdatingCurrent,
                dayPartTitle(dayPart)
            )
        }
    }

    private func dayPartTitle(_ dayPart: ProgressDayPart) -> String {
        switch dayPart {
        case .morning: String(localized: "progress.day_part.morning", defaultValue: "morning")
        case .afternoon: String(localized: "progress.day_part.afternoon", defaultValue: "afternoon")
        case .evening: String(localized: "progress.day_part.evening", defaultValue: "evening")
        }
    }
}

struct ProgressSummaryCard: View {
    @EnvironmentObject private var activityStore: ActivityStore
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    @EnvironmentObject private var gearStore: GearStore

    private var snapshot: ProgressStatsSnapshot {
        ProgressStatsEngine.snapshot(from: activityStore.activities.map(\.progressActivity))
    }

    var body: some View {
        NavigationLink {
                RunnerProgressView()
                    .environmentObject(activityStore)
                    .environmentObject(measurementPreferences)
                    .environmentObject(gearStore)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Progress", systemImage: "chart.bar.fill")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }

                if snapshot.eligibleActivityCount == 0 {
                    Text("Save your first activity to start building stats.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 16) {
                        SummaryStat(
                            title: "This week",
                            value: measurementPreferences.unitSystem.distanceString(
                                meters: snapshot.currentWeek.distanceMeters,
                                fractionDigits: 1
                            )
                        )
                        SummaryStat(
                            title: String(localized: "progress.activities", defaultValue: "Activities"),
                            value: "\(snapshot.currentWeek.activityCount)"
                        )
                        if let topEffort = snapshot.bestEfforts.first {
                            SummaryStat(
                                title: topEffort.kind.title,
                                value: compactValue(for: topEffort)
                            )
                        }
                    }

                    if let momentumNote = snapshot.momentumNote {
                        HStack(spacing: 8) {
                            Image(systemName: momentumNote.symbolName)
                                .foregroundStyle(.orange)
                            Text(momentumNote.text)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func compactValue(for effort: ProgressBestEffort) -> String {
        if let duration = effort.durationSeconds,
           [.fastestKilometer, .fastestMile, .fastestFiveKilometer].contains(effort.kind) {
            return duration.formatted()
        }
        if let distance = effort.distanceMeters {
            return measurementPreferences.unitSystem.distanceString(meters: distance, fractionDigits: 1)
        }
        if let elevation = effort.elevationMeters {
            return measurementPreferences.unitSystem.elevationString(meters: elevation)
        }
        return "--"
    }
}

private struct ProgressMetricTile: View {
    let title: String
    let value: String
    let unit: String
    let comparison: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            if let comparison {
                Text(comparison)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ProgressSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct BestEffortRow: View {
    let effort: ProgressBestEffort
    let unitSystem: MeasurementUnitSystem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.headline)
                .foregroundStyle(.orange)
                .frame(width: 30, height: 30)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(effort.kind.title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 9)
    }

    private var iconName: String {
        switch effort.kind {
        case .fastestKilometer, .fastestMile, .fastestFiveKilometer: return "bolt.fill"
        case .longestRun: return "arrow.left.and.right"
        case .mostElevation: return "mountain.2.fill"
        case .bestWeeklyDistance: return "calendar"
        }
    }

    private var value: String {
        switch effort.kind {
        case .fastestKilometer, .fastestMile, .fastestFiveKilometer:
            return effort.durationSeconds?.formatted() ?? "--"
        case .longestRun, .bestWeeklyDistance:
            return unitSystem.distanceString(meters: effort.distanceMeters ?? 0, fractionDigits: 1)
        case .mostElevation:
            return unitSystem.elevationString(meters: effort.elevationMeters ?? 0)
        }
    }

    private var subtitle: String {
        let date = effort.date.formatted(date: .abbreviated, time: .omitted)
        let sourceSuffix = effort.source == .wholeActivityFallback ? " · activity avg" : ""
        if let activityTitle = effort.activityTitle {
            return "\(activityTitle) · \(date)\(sourceSuffix)"
        }
        return "\(date)\(sourceSuffix)"
    }
}

private struct PersonalRecordRow: View {
    let record: ProgressPersonalRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "rosette")
                .font(.headline)
                .foregroundStyle(.orange)
                .frame(width: 30, height: 30)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(record.title)
                    .font(.subheadline.weight(.semibold))
                Text(record.effort.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(record.effort.durationSeconds?.formatted() ?? "--")
                .font(.subheadline.weight(.bold).monospacedDigit())
        }
        .padding(.vertical, 9)
    }
}

private struct RacePredictionRow: View {
    let prediction: ProgressRacePrediction

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(prediction.title)
                    .font(.subheadline.weight(.semibold))
                Text("\(prediction.confidence.title) confidence")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(prediction.predictedSeconds.formatted())
                .font(.subheadline.weight(.bold).monospacedDigit())
        }
        .padding(10)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct RecentProgressActivityRow: View {
    @EnvironmentObject private var onboardingStore: OnboardingStore
    let activity: SavedActivity
    let notableEfforts: [ProgressBestEffort]
    let unitSystem: MeasurementUnitSystem

    private var calorieEstimate: WorkoutCalorieEstimate {
        WorkoutCalorieEstimator.estimate(
            for: activity,
            weightKilograms: onboardingStore.latestWeightKilograms
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(activity.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(activity.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let effort = notableEfforts.first {
                    Text(effort.kind.title)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 6) {
                SourceBadge(activity: activity)
            }

            HStack(spacing: 12) {
                Text(unitSystem.distanceString(meters: activity.distanceM, fractionDigits: 2))
                Text(WorkoutCalorieEstimator.durationAndCalorieLine(
                    durationSeconds: activity.durationSecs,
                    kilocalories: calorieEstimate.kilocalories
                ))
                Text(activity.avgPace?.paceString(for: unitSystem) ?? "--")
                if let elevation = activity.elevationGainM {
                    Text(unitSystem.elevationString(meters: elevation))
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .padding(10)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SourceBadge: View {
    let activity: SavedActivity

    var body: some View {
        Label(sourceLabel, systemImage: sourceIcon)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color(.quaternarySystemFill))
            .clipShape(Capsule())
    }

    private var sourceLabel: String {
        if activity.indoor?.isIndoor == true { return "Indoor" }
        if activity.manualEdits != nil { return "Edited" }
        return activity.source.displayName
    }

    private var sourceIcon: String {
        if activity.indoor?.isIndoor == true { return "figure.run.treadmill" }
        if activity.manualEdits != nil { return "pencil" }
        switch activity.source.kind {
        case .outbound: return "iphone"
        case .appleHealth, .garminViaHealth: return "heart.text.square.fill"
        case .manual: return "square.and.pencil"
        case .strava, .importedFile: return "doc.badge.arrow.up"
        }
    }
}

private struct SummaryStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.subheadline.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension SavedActivity {
    var progressActivity: ProgressActivity {
        ProgressActivity(
            id: id.uuidString,
            title: title,
            startedAt: startedAt,
            durationSeconds: durationSecs,
            distanceMeters: distanceM,
            elevationGainMeters: elevationGainM,
            averageHeartRate: healthMetrics?.averageHeartRateBPM,
            routePoints: progressRoutePoints,
            activityType: activityType.rawValue,
            goalCompleted: progressGoalCompleted,
            heartRateZoneSeconds: Dictionary(
                uniqueKeysWithValues: (heartRateZones?.zones ?? []).map { ($0.index, $0.seconds) }
            )
        )
    }

    var progressGoalCompleted: Bool? {
        guard let goal else { return nil }
        switch goal {
        case .freestyle:
            return nil
        case .distanceMeters(let target):
            return distanceM >= target * 0.98
        case .timeSeconds(let target):
            return Double(durationSecs) >= Double(target) * 0.98
        case .calories(let target):
            guard let energyKilocalories else { return nil }
            return Double(energyKilocalories) >= Double(target) * 0.98
        }
    }

    var progressRoutePoints: [ProgressRoutePoint] {
        guard routePoints.count >= 2 else { return [] }

        var cumulativeDistance: Double = 0
        var previousLocation: CLLocation?

        return routePoints.map { point in
            let location = CLLocation(latitude: point.latitude, longitude: point.longitude)
            if let previousLocation {
                cumulativeDistance += max(0, location.distance(from: previousLocation))
            }
            previousLocation = location
            return ProgressRoutePoint(
                timestamp: point.timestamp,
                cumulativeDistanceMeters: cumulativeDistance
            )
        }
    }
}
