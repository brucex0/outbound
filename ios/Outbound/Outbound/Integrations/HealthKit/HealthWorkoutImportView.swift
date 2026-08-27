import SwiftUI

struct HealthWorkoutImportView: View {
    @Environment(\.analyticsManager) private var analyticsManager
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var activityStore: ActivityStore
    @EnvironmentObject private var healthImportStore: HealthImportStore
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    @State private var selectedIDs: Set<String> = []
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(healthImportStore.importCandidates) { workout in
                        Button {
                            if selectedIDs.contains(workout.id) {
                                selectedIDs.remove(workout.id)
                            } else {
                                selectedIDs.insert(workout.id)
                            }
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
            .countBucket: .string(ProductAnalyticsBucket.count(selected.count))
        ])
        isImporting = false
        dismiss()
    }

    private func track(_ name: ProductEventName, properties: [ProductPropertyKey: AnalyticsValue]) {
        guard let analyticsManager else { return }
        Task { await analyticsManager.track(.init(name, properties: properties)) }
    }
}
