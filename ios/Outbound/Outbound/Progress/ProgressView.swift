import CoreLocation
import SwiftUI

struct RunnerProgressView: View {
    @EnvironmentObject private var activityStore: ActivityStore
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    @EnvironmentObject private var gearStore: GearStore
    @State private var selectedTab: RunnerProgressTab = .now

    private var snapshot: ProgressStatsSnapshot {
        ProgressStatsEngine.snapshot(from: activityStore.activities.map(\.progressActivity))
    }

    private var recentActivities: [SavedActivity] {
        activityStore.activities.filter { $0.durationSecs > 60 }
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
                coachNote
                recentStatsSection
            }
        case .trends:
            VStack(alignment: .leading, spacing: 18) {
                trendsSection
            }
        case .records:
            VStack(alignment: .leading, spacing: 18) {
                bestEffortsSection
                personalRecordsSection
                racePredictionsSection
            }
        case .gear:
            VStack(alignment: .leading, spacing: 18) {
                gearMileageSection
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
                    title: "Distance",
                    value: measurementPreferences.unitSystem.distanceValueString(
                        meters: snapshot.currentWeek.distanceMeters,
                        fractionDigits: 1
                    ),
                    unit: measurementPreferences.unitSystem.distanceUnit
                )
                ProgressMetricTile(
                    title: "Runs",
                    value: "\(snapshot.currentWeek.activityCount)",
                    unit: "activities"
                )
            }

            HStack(spacing: 10) {
                ProgressMetricTile(
                    title: "Time",
                    value: snapshot.currentWeek.durationSeconds.formatted(),
                    unit: "moving"
                )
                ProgressMetricTile(
                    title: "Avg Pace",
                    value: snapshot.currentWeek.averagePaceSecondsPerKilometer?
                        .paceString(for: measurementPreferences.unitSystem) ?? "--",
                    unit: measurementPreferences.unitSystem.paceUnitSuffix
                )
            }
        }
    }

    private var trendsSection: some View {
        ProgressSection(title: "Last 4 Weeks") {
            let maxDistance = max(snapshot.weeklyBuckets.map(\.distanceMeters).max() ?? 0, 1)
            VStack(spacing: 12) {
                ForEach(snapshot.weeklyBuckets) { bucket in
                    WeeklyTrendRow(
                        bucket: bucket,
                        maxDistance: maxDistance,
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

    private var gearMileageSection: some View {
        let summaries = gearStore.mileageSummaries(from: activityStore.activities)
        return ProgressSection(title: "Shoe Mileage") {
            if summaries.isEmpty {
                Text("Add shoes in Settings to track mileage by pair.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(summaries) { summary in
                        GearMileageRow(summary: summary, unitSystem: measurementPreferences.unitSystem)
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

    private var coachNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(.orange)
            Text(snapshot.coachNote)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private enum RunnerProgressTab: String, CaseIterable, Identifiable {
    case now
    case trends
    case records
    case gear

    var id: Self { self }

    var title: String {
        switch self {
        case .now: return "Now"
        case .trends: return "Trends"
        case .records: return "Records"
        case .gear: return "Gear"
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
                            title: "Runs",
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

private struct WeeklyTrendRow: View {
    let bucket: ProgressWeekBucket
    let maxDistance: Double
    let unitSystem: MeasurementUnitSystem

    var body: some View {
        HStack(spacing: 10) {
            Text(shortWeekLabel)
                .font(.caption.weight(.semibold))
                .frame(width: 44, alignment: .leading)
                .foregroundStyle(.secondary)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.tertiarySystemFill))
                    Capsule()
                        .fill(Color.orange)
                        .frame(width: max(4, geometry.size.width * bucket.distanceMeters / maxDistance))
                }
            }
            .frame(height: 10)

            Text(unitSystem.distanceString(meters: bucket.distanceMeters, fractionDigits: 1))
                .font(.caption.monospacedDigit())
                .frame(width: 68, alignment: .trailing)
        }
        .frame(height: 24)
    }

    private var shortWeekLabel: String {
        bucket.startDate.formatted(.dateTime.month(.abbreviated).day())
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

private struct GearMileageRow: View {
    let summary: GearMileageSummary
    let unitSystem: MeasurementUnitSystem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(summary.item.displayName, systemImage: "shoeprints.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(unitSystem.distanceString(meters: summary.distanceMeters, fractionDigits: 1))
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: summary.usageFraction)
                .tint(.orange)

            Text("\(unitSystem.distanceString(meters: summary.remainingMeters, fractionDigits: 0)) before suggested retirement")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct RecentProgressActivityRow: View {
    let activity: SavedActivity
    let notableEfforts: [ProgressBestEffort]
    let unitSystem: MeasurementUnitSystem

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
                if let gear = activity.gear {
                    Text(gear.shoeName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Text(unitSystem.distanceString(meters: activity.distanceM, fractionDigits: 2))
                Text(activity.durationSecs.formatted())
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
        case .importedFile: return "doc.badge.arrow.up"
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
            routePoints: progressRoutePoints
        )
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
