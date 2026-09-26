import SwiftUI
import UniformTypeIdentifiers

/// Runner-facing wizard for bringing activity history over from a Strava data export.
///
/// The flow is deliberately manual: the runner requests and downloads their own archive from
/// Strava, picks it in Files, reviews what Plainstride found, and confirms what to import.
struct StravaImportView: View {
    @Environment(\.analyticsManager) private var analyticsManager
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var activityStore: ActivityStore
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    @EnvironmentObject private var stravaImportStore: StravaImportStore

    @State private var selectedIDs: Set<String> = []
    @State private var includedSports = Set(ImportedActivitySport.allCases)
    @State private var isPickingFiles = false
    @State private var selectionControlUsage: Set<StravaImportSelectionControl> = []

    var body: some View {
        NavigationStack {
            Group {
                switch stravaImportStore.phase {
                case .instructions: instructionsView
                case .reading: readingView
                case .review: reviewView
                case .importing: importingView
                case .result: resultView
                }
            }
            .navigationTitle(String(localized: "strava.import.title", defaultValue: "Import from Strava"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(closeTitle) {
                        stravaImportStore.isPresented = false
                        stravaImportStore.reset()
                        dismiss()
                    }
                }
                if stravaImportStore.phase == .review {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(importButtonTitle) { Task { await importSelected() } }
                            .disabled(selectedIDs.isEmpty)
                    }
                }
            }
            .fileImporter(
                isPresented: $isPickingFiles,
                allowedContentTypes: allowedContentTypes,
                allowsMultipleSelection: true
            ) { result in
                handlePickedFiles(result)
            }
            .onAppear {
                track(.stravaImportPromptViewed, properties: [.sourceType: .string(Self.analyticsSource)])
            }
        }
    }

    // MARK: - Toolbar

    private var closeTitle: String {
        switch stravaImportStore.phase {
        case .result, .instructions: String(localized: "common.done", defaultValue: "Done")
        default: String(localized: "common.cancel", defaultValue: "Cancel")
        }
    }

    // MARK: - Instructions

    private var instructionsView: some View {
        List {
            Section {
                Text(String(
                    localized: "strava.import.intro",
                    defaultValue: "Your Strava history stays yours. Plainstride never connects to your Strava account — you download your own export and choose what to bring over."
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Section {
                instructionStep(
                    number: 1,
                    title: String(localized: "strava.import.step1.title", defaultValue: "Open Strava settings"),
                    detail: String(
                        localized: "strava.import.step1.detail",
                        defaultValue: "On strava.com, open Settings, then My Account, and find Download or Delete Your Account."
                    )
                )
                instructionStep(
                    number: 2,
                    title: String(localized: "strava.import.step2.title", defaultValue: "Request your archive"),
                    detail: String(
                        localized: "strava.import.step2.detail",
                        defaultValue: "Tap Request Your Archive. Strava prepares the file and emails a download link, which can take up to a few hours."
                    )
                )
                instructionStep(
                    number: 3,
                    title: String(localized: "strava.import.step3.title", defaultValue: "Download and unzip"),
                    detail: String(
                        localized: "strava.import.step3.detail",
                        defaultValue: "Open the email on this iPhone, download the ZIP, and either select the ZIP here or unzip it in Files first. Both work."
                    )
                )
                instructionStep(
                    number: 4,
                    title: String(localized: "strava.import.step4.title", defaultValue: "Pick it in Plainstride"),
                    detail: String(
                        localized: "strava.import.step4.detail",
                        defaultValue: "Select the export ZIP, the unzipped export folder, or individual GPX and TCX files. Plainstride then shows you what it found before anything is saved."
                    )
                )
            } header: {
                Text(String(localized: "strava.import.steps.header", defaultValue: "HOW TO EXPORT"))
            }

            Section {
                Label {
                    Text(String(
                        localized: "strava.import.privacy",
                        defaultValue: "Plainstride reads only activity files. Photos, clubs, and social data in the export are ignored."
                    ))
                } icon: {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(OutboundPalette.companion)
                }
                .font(.caption)

                if let statusMessage = stravaImportStore.statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Button {
                    isPickingFiles = true
                } label: {
                    Label(
                        String(localized: "strava.import.choose_file", defaultValue: "Choose Strava export"),
                        systemImage: "folder.badge.plus"
                    )
                    .font(.body.weight(.semibold))
                }
            }
        }
    }

    private func instructionStep(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number.formatted())
                .font(.caption.weight(.bold).monospacedDigit())
                .frame(width: 22, height: 22)
                .background(OutboundPalette.companion.opacity(0.15), in: Circle())
                .foregroundStyle(OutboundPalette.companion)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Reading / importing

    private var readingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(String(localized: "strava.import.reading", defaultValue: "Reading your export…"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(String(
                localized: "strava.import.reading.detail",
                defaultValue: "Large exports can take a moment. Nothing is saved yet."
            ))
            .font(.caption)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var importingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(String(localized: "strava.import.importing", defaultValue: "Importing activities…"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Review

    private var reviewView: some View {
        List {
            Section {
                ForEach(ImportedActivitySport.allCases) { sport in
                    if candidateCount(for: sport) > 0 {
                        Button {
                            toggleSport(sport)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: sportSelectionState(for: sport).systemImage)
                                    .foregroundStyle(sportSelectionState(for: sport) == .unselected ? Color.secondary : OutboundPalette.companion)
                                Image(systemName: sport.systemImage)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22)
                                Text(sport.displayName).foregroundStyle(.primary)
                                Spacer()
                                Text(candidateCount(for: sport).formatted())
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(sportSelectionState(for: sport).accessibilityValue)
                    }
                }
            } header: {
                HStack {
                    Text(String(localized: "strava.import.types.header", defaultValue: "ACTIVITY TYPES"))
                    Spacer()
                    Button(selectedIDs.count == stravaImportStore.candidates.count
                           ? String(localized: "strava.import.deselect_all", defaultValue: "Deselect All")
                           : String(localized: "strava.import.select_all", defaultValue: "Select All")) {
                        toggleAll()
                    }
                    .font(.caption)
                    .textCase(nil)
                }
            } footer: {
                Text(String(
                    localized: "strava.import.review.footer",
                    defaultValue: "Only selected activities are added. Anything you already have in Plainstride is excluded."
                ))
            }

            if stravaImportStore.candidates.isEmpty {
                Section {
                    Text(String(
                        localized: "strava.import.review.empty",
                        defaultValue: "No new activities were found in that selection."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(stravaImportStore.candidates) { candidate in
                        Button {
                            toggleCandidate(candidate)
                        } label: {
                            candidateRow(candidate)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(String(
                        format: String(localized: "strava.import.review.header.format", defaultValue: "%d found in %@"),
                        locale: .autoupdatingCurrent,
                        stravaImportStore.candidates.count,
                        stravaImportStore.displaySourceName
                    ))
                }
            }

            if !stravaImportStore.skipped.isEmpty {
                Section {
                    ForEach(skippedGroups) { group in
                        HStack {
                            Text(group.reason.displayName).font(.caption)
                            Spacer()
                            Text(group.count.formatted())
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(String(localized: "strava.import.skipped.header", defaultValue: "NOT IMPORTABLE"))
                } footer: {
                    Text(String(
                        localized: "strava.import.skipped.footer",
                        defaultValue: "Compressed FIT activity files can't be read yet. Those workouts still import using the export's summary, but without their route."
                    ))
                }
            }
        }
    }

    private func candidateRow(_ candidate: StravaImportCandidate) -> some View {
        HStack(spacing: 12) {
            Image(systemName: selectedIDs.contains(candidate.id) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selectedIDs.contains(candidate.id) ? OutboundPalette.companion : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.importDisplayTitle).font(.headline).foregroundStyle(.primary)
                Text(candidate.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
                if !candidate.hasRoute {
                    Text(String(localized: "strava.import.no_route", defaultValue: "No route"))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Text(candidate.summaryLine(unitSystem: measurementPreferences.unitSystem))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Result

    private var resultView: some View {
        List {
            Section {
                Label {
                    Text(importSummaryTitle)
                        .font(.headline)
                } icon: {
                    Image(systemName: (stravaImportStore.outcome?.importedIDs.isEmpty ?? true)
                          ? "exclamationmark.triangle"
                          : "checkmark.circle.fill")
                    .foregroundStyle((stravaImportStore.outcome?.importedIDs.isEmpty ?? true) ? .orange : OutboundPalette.companion)
                }
                Text(importSummaryDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let outcome = stravaImportStore.outcome, !outcome.failedIDs.isEmpty {
                Section {
                    Text(String(
                        format: String(localized: "strava.import.result.failed.format", defaultValue: "%d activities could not be saved."),
                        locale: .autoupdatingCurrent,
                        outcome.failedIDs.count
                    ))
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }
        }
    }

    private var importSummaryTitle: String {
        let count = stravaImportStore.outcome?.importedIDs.count ?? 0
        if count == 0 { return String(localized: "strava.import.result.none", defaultValue: "Nothing was imported") }
        return String(
            format: String(localized: "strava.import.result.title.format", defaultValue: "Imported %d activities"),
            locale: .autoupdatingCurrent,
            count
        )
    }

    private var importSummaryDetail: String {
        guard let outcome = stravaImportStore.outcome, !outcome.importedIDs.isEmpty else {
            return String(
                localized: "strava.import.result.none_detail",
                defaultValue: "None of the selected activities could be saved. They may already exist in your history, or the files could not be read."
            )
        }
        return String(
            localized: "strava.import.result.detail",
            defaultValue: "They now appear in your activity history as imported activities. They are not posted to anyone and are not treated as new recordings."
        )
    }

    // MARK: - Helpers

    private var allowedContentTypes: [UTType] {
        var types: [UTType] = [.zip, .folder, .item]
        if let gpx = UTType(filenameExtension: "gpx") { types.append(gpx) }
        if let tcx = UTType(filenameExtension: "tcx") { types.append(tcx) }
        return types
    }

    private static let analyticsSource = "strava_export"

    private var importButtonTitle: String {
        String(
            format: String(localized: "strava.import.button.format", defaultValue: "Import %d"),
            locale: .autoupdatingCurrent,
            selectedIDs.count
        )
    }

    private func candidateCount(for sport: ImportedActivitySport) -> Int {
        stravaImportStore.candidates.count { $0.sport == sport }
    }

    private func sportSelectionState(for sport: ImportedActivitySport) -> StravaImportSelectionState {
        let ids = Set(stravaImportStore.candidates.filter { $0.sport == sport }.map(\.id))
        guard !ids.isEmpty else { return includedSports.contains(sport) ? .selected : .unselected }
        let selectedCount = selectedIDs.intersection(ids).count
        if selectedCount == 0 { return .unselected }
        if selectedCount == ids.count { return .selected }
        return .partiallySelected
    }

    private func toggleSport(_ sport: ImportedActivitySport) {
        selectionControlUsage.insert(.activityType)
        let ids = Set(stravaImportStore.candidates.filter { $0.sport == sport }.map(\.id))
        switch sportSelectionState(for: sport) {
        case .selected, .partiallySelected:
            includedSports.remove(sport)
            selectedIDs.subtract(ids)
        case .unselected:
            includedSports.insert(sport)
            selectedIDs.formUnion(ids)
        }
    }

    private func toggleCandidate(_ candidate: StravaImportCandidate) {
        selectionControlUsage.insert(.individualActivity)
        if selectedIDs.contains(candidate.id) {
            selectedIDs.remove(candidate.id)
        } else {
            selectedIDs.insert(candidate.id)
        }
        let ids = stravaImportStore.candidates.filter { $0.sport == candidate.sport }.map(\.id)
        if ids.contains(where: selectedIDs.contains) {
            includedSports.insert(candidate.sport)
        } else {
            includedSports.remove(candidate.sport)
        }
    }

    private func toggleAll() {
        selectionControlUsage.insert(.selectAll)
        if selectedIDs.count == stravaImportStore.candidates.count {
            selectedIDs.removeAll()
            includedSports.removeAll()
        } else {
            selectedIDs = Set(stravaImportStore.candidates.map(\.id))
            includedSports = Set(ImportedActivitySport.allCases)
        }
    }

    private var skippedGroups: [SkippedGroup] {
        stravaImportStore.skipped
            .reduce(into: [StravaImportSkip.Reason: Int]()) { counts, skip in counts[skip.reason, default: 0] += 1 }
            .map { SkippedGroup(reason: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    private func handlePickedFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            selectedIDs = []
            includedSports = Set(ImportedActivitySport.allCases)
            selectionControlUsage = []
            Task {
                await stravaImportStore.readSelection(
                    urls: urls,
                    existingExternalIDs: activityStore.importedStravaExternalIDs
                )
                selectedIDs = Set(stravaImportStore.candidates.map(\.id))
            }
        case .failure:
            stravaImportStore.statusMessage = String(
                localized: "strava.import.pick_failed",
                defaultValue: "That file could not be opened. Try choosing it again from the Files app."
            )
        }
    }

    private func importSelected() async {
        let selected = stravaImportStore.candidates.filter { selectedIDs.contains($0.id) }
        guard !selected.isEmpty else { return }
        let candidateCount = stravaImportStore.candidates.count
        await stravaImportStore.importSelected(selected, into: activityStore)
        let imported = stravaImportStore.outcome?.importedIDs.count ?? 0
        track(.stravaImportCompleted, properties: [
            .sourceType: .string(Self.analyticsSource),
            .result: .string(imported == selected.count ? "completed" : (imported == 0 ? "failed" : "partial")),
            .selectionType: .string(selected.count == candidateCount ? "all" : "subset"),
            .control: .string(selectionControlAnalyticsValue),
            .countBucket: .string(ProductAnalyticsBucket.count(selected.count))
        ])
    }

    private var selectionControlAnalyticsValue: String {
        if selectionControlUsage.isEmpty { return "default" }
        if selectionControlUsage == [.activityType] { return "activity_type" }
        if selectionControlUsage == [.individualActivity] { return "individual_activity" }
        if selectionControlUsage == [.selectAll] { return "select_all" }
        return "mixed"
    }

    private func track(_ name: ProductEventName, properties: [ProductPropertyKey: AnalyticsValue]) {
        guard let analyticsManager else { return }
        Task { await analyticsManager.track(.init(name, properties: properties)) }
    }
}

private struct SkippedGroup: Identifiable {
    let reason: StravaImportSkip.Reason
    let count: Int

    var id: StravaImportSkip.Reason { reason }
}

private enum StravaImportSelectionControl: Hashable {
    case activityType
    case individualActivity
    case selectAll
}

private enum StravaImportSelectionState: Equatable {
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
        case .selected: String(localized: "strava.import.selection.selected", defaultValue: "Selected")
        case .partiallySelected: String(localized: "strava.import.selection.partial", defaultValue: "Partially selected")
        case .unselected: String(localized: "strava.import.selection.unselected", defaultValue: "Not selected")
        }
    }
}

extension ImportedActivitySport {
    var displayName: String {
        switch self {
        case .running: String(localized: "strava.sport.run", defaultValue: "Run")
        case .cycling: String(localized: "strava.sport.ride", defaultValue: "Ride")
        case .hiking: String(localized: "strava.sport.hike", defaultValue: "Hike")
        case .walking: String(localized: "strava.sport.walk", defaultValue: "Walk")
        case .swimming: String(localized: "strava.sport.swim", defaultValue: "Swim")
        case .strength: String(localized: "strava.sport.strength", defaultValue: "Strength")
        case .mobility: String(localized: "strava.sport.mobility", defaultValue: "Mobility")
        case .other: String(localized: "strava.sport.other", defaultValue: "Workout")
        }
    }

    var systemImage: String {
        switch self {
        case .running: "figure.run"
        case .cycling: "figure.outdoor.cycle"
        case .hiking: "figure.hiking"
        case .walking: "figure.walk"
        case .swimming: "figure.pool.swim"
        case .strength: "figure.strengthtraining.traditional"
        case .mobility: "figure.flexibility"
        case .other: "figure.mixed.cardio"
        }
    }
}

private extension StravaImportCandidate {
    var importDisplayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? sport.displayName : trimmed
    }

    func summaryLine(unitSystem: MeasurementUnitSystem) -> String {
        let duration = durationSeconds.formatted()
        guard let distanceMeters, distanceMeters > 0 else { return duration }
        return "\(duration) · \(unitSystem.distanceString(meters: distanceMeters, fractionDigits: 1))"
    }
}

private extension StravaImportSkip.Reason {
    var displayName: String {
        switch self {
        case .unsupportedFile: String(localized: "strava.skip.unsupported", defaultValue: "Unsupported file format")
        case .unreadableFile: String(localized: "strava.skip.unreadable", defaultValue: "Could not be read")
        case .duplicate: String(localized: "strava.skip.duplicate", defaultValue: "Already in your history")
        case .missingDate: String(localized: "strava.skip.missing_date", defaultValue: "Missing a start date")
        case .missingMetrics: String(localized: "strava.skip.missing_metrics", defaultValue: "Missing duration and distance")
        case .noActivityFiles: String(localized: "strava.skip.no_files", defaultValue: "No activity files found")
        }
    }
}
