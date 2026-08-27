import SwiftUI

struct HealthWorkoutImportView: View {
    @Environment(\.analyticsManager) private var analyticsManager
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var activityStore: ActivityStore
    @EnvironmentObject private var healthImportStore: HealthImportStore
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    @State private var selectedIDs: Set<String> = []
    @State private var selectedActivityTypes = Set(ActivityType.allCases)
    @State private var selectionControlUsage: Set<HealthImportSelectionControl> = []
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(SportType.allCases) { sport in
                        Button {
                            toggleActivityType(sport.activityType)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: typeSelectionState(for: sport.activityType).systemImage)
                                    .foregroundStyle(typeSelectionState(for: sport.activityType) == .unselected ? Color.secondary : OutboundPalette.companion)
                                Image(systemName: sport.systemImage)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22)
                                Text(sport.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(workoutCount(for: sport.activityType).formatted())
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(typeSelectionState(for: sport.activityType).accessibilityValue)
                    }
                } header: {
                    Text(String(localized: "health.import.types.section", defaultValue: "ACTIVITY TYPES"))
                } footer: {
                    Text(String(
                        localized: "health.import.types.footer",
                        defaultValue: "All five types are selected by default. Uncheck a type to exclude every matching workout."
                    ))
                }

                Section {
                    ForEach(healthImportStore.importCandidates) { workout in
                        Button {
                            toggleWorkout(workout)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedIDs.contains(workout.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedIDs.contains(workout.id) ? OutboundPalette.companion : .secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(workout.activityName).font(.headline).foregroundStyle(.primary)
                                    Text(workout.startedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(workout.summaryLine(unitSystem: measurementPreferences.unitSystem))
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(String(localized: "health.import.section", defaultValue: "NEW IN APPLE HEALTH"))
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "health.import.footer", defaultValue: "Only selected workouts are added. Plainstride workouts and activities already imported are excluded."))
                        if hasWalkingCandidates {
                            Label {
                                Text(String(
                                    localized: "health.import.walking_warning",
                                    defaultValue: "Walking workouts can make your activity history feel crowded. Uncheck any you don't want to import."
                                ))
                            } icon: {
                                Image(systemName: "exclamationmark.triangle")
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "health.import.title", defaultValue: "Import Workouts"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.not_now", defaultValue: "Not Now")) {
                        healthImportStore.closeReview()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(importButtonTitle) { Task { await importSelected() } }
                        .disabled(selectedIDs.isEmpty || isImporting)
                }
            }
            .onAppear {
                selectedIDs = Set(healthImportStore.importCandidates.map(\.id))
                selectedActivityTypes = Set(ActivityType.allCases)
                selectionControlUsage = []
                track(.healthImportPromptViewed, properties: [.sourceType: .string("apple_health")])
            }
        }
    }

    private var importButtonTitle: String {
        if isImporting { return String(localized: "health.import.importing", defaultValue: "Importing…") }
        return String(
            format: String(localized: "health.import.button.format", defaultValue: "Import %d"),
            locale: .autoupdatingCurrent,
            selectedIDs.count
        )
    }

    private var hasWalkingCandidates: Bool {
        healthImportStore.importCandidates.contains { $0.activityType == .walking }
    }

    private func workoutCount(for activityType: ActivityType) -> Int {
        healthImportStore.importCandidates.count { $0.activityType == activityType }
    }

    private func typeSelectionState(for activityType: ActivityType) -> HealthImportTypeSelectionState {
        let candidateIDs = Set(
            healthImportStore.importCandidates
                .filter { $0.activityType == activityType }
                .map(\.id)
        )
        guard !candidateIDs.isEmpty else {
            return selectedActivityTypes.contains(activityType) ? .selected : .unselected
        }

        let selectedCount = selectedIDs.intersection(candidateIDs).count
        if selectedCount == 0 { return .unselected }
        if selectedCount == candidateIDs.count { return .selected }
        return .partiallySelected
    }

    private func toggleActivityType(_ activityType: ActivityType) {
        selectionControlUsage.insert(.activityType)
        let matchingIDs = Set(
            healthImportStore.importCandidates
                .filter { $0.activityType == activityType }
                .map(\.id)
        )

        switch typeSelectionState(for: activityType) {
        case .selected, .partiallySelected:
            selectedActivityTypes.remove(activityType)
            selectedIDs.subtract(matchingIDs)
        case .unselected:
            selectedActivityTypes.insert(activityType)
            selectedIDs.formUnion(matchingIDs)
        }
    }

    private func toggleWorkout(_ workout: ImportedWorkout) {
        selectionControlUsage.insert(.individualWorkout)
        if selectedIDs.contains(workout.id) {
            selectedIDs.remove(workout.id)
        } else {
            selectedIDs.insert(workout.id)
        }

        let matchingIDs = healthImportStore.importCandidates
            .filter { $0.activityType == workout.activityType }
            .map(\.id)
        if matchingIDs.contains(where: selectedIDs.contains) {
            selectedActivityTypes.insert(workout.activityType)
        } else {
            selectedActivityTypes.remove(workout.activityType)
        }
    }

    private func importSelected() async {
        isImporting = true
        let candidateCount = healthImportStore.importCandidates.count
        let selected = healthImportStore.importCandidates.filter { selectedIDs.contains($0.id) }
        let importedIDs = await activityStore.importHealthWorkouts(selected)
        healthImportStore.finishImport(importedIDs: importedIDs)
        track(.healthImportCompleted, properties: [
            .sourceType: .string("apple_health"),
            .result: .string(importedIDs.count == selected.count ? "completed" : "partial"),
            .selectionType: .string(selected.count == candidateCount ? "all" : "subset"),
            .control: .string(selectionControlAnalyticsValue),
            .countBucket: .string(ProductAnalyticsBucket.count(selected.count))
        ])
        isImporting = false
        dismiss()
    }

    private func track(_ name: ProductEventName, properties: [ProductPropertyKey: AnalyticsValue]) {
        guard let analyticsManager else { return }
        Task { await analyticsManager.track(.init(name, properties: properties)) }
    }

    private var selectionControlAnalyticsValue: String {
        if selectionControlUsage.isEmpty { return "default" }
        if selectionControlUsage == [.activityType] { return "activity_type" }
        if selectionControlUsage == [.individualWorkout] { return "individual_workout" }
        return "mixed"
    }
}

private enum HealthImportSelectionControl: Hashable {
    case activityType
    case individualWorkout
}

private enum HealthImportTypeSelectionState: Equatable {
    case selected
    case partiallySelected
    case unselected

    var systemImage: String {
        switch self {
        case .selected: "checkmark.square.fill"
        case .partiallySelected: "minus.square.fill"
        case .unselected: "square"
        }
    }

    var accessibilityValue: String {
        switch self {
        case .selected: String(localized: "health.import.selection.selected", defaultValue: "Selected")
        case .partiallySelected: String(localized: "health.import.selection.partial", defaultValue: "Partially selected")
        case .unselected: String(localized: "health.import.selection.unselected", defaultValue: "Not selected")
        }
    }
}
