import Combine
import Foundation

/// Drives the runner-controlled Strava export import: explain, read, review, import, report.
///
/// Reading and parsing run off the main actor because a full account export can hold thousands of
/// files. Nothing is saved until the runner confirms a selection.
@MainActor
final class StravaImportStore: ObservableObject {
    enum Phase: Equatable {
        case instructions
        case reading
        case review
        case importing
        case result
    }

    @Published var phase: Phase = .instructions
    @Published private(set) var candidates: [StravaImportCandidate] = []
    @Published private(set) var skipped: [StravaImportSkip] = []
    @Published private(set) var sourceName = ""
    @Published private(set) var selectionCount = 0
    @Published private(set) var outcome: StravaImportOutcome?
    @Published var statusMessage: String?
    @Published var isPresented = false

    var canRetryReview: Bool { !candidates.isEmpty }

    func present() {
        reset()
        isPresented = true
    }

    func reset() {
        phase = .instructions
        candidates = []
        skipped = []
        sourceName = ""
        selectionCount = 0
        outcome = nil
        statusMessage = nil
    }

    /// Reads the picked files, parses every supported activity, and prepares the review list.
    func readSelection(urls: [URL], existingExternalIDs: Set<String>) async {
        guard !urls.isEmpty else { return }
        phase = .reading
        statusMessage = nil
        outcome = nil

        let result = await Task.detached(priority: .userInitiated) {
            StravaImportFileReader.read(urls: urls)
        }.value

        sourceName = result.sourceName
        selectionCount = result.selectionCount

        guard !result.entries.isEmpty else {
            phase = .instructions
            statusMessage = String(
                localized: "strava.import.read_failed",
                defaultValue: "Plainstride could not read that selection. Choose the Strava export ZIP, the unzipped export folder, or individual GPX or TCX files."
            )
            return
        }

        let review = StravaExportImporter.review(
            sourceName: result.sourceName,
            entries: result.entries,
            existingExternalIDs: existingExternalIDs
        )
        candidates = review.candidates
        skipped = result.skipped + review.skipped
        phase = .review
    }

    /// Saves exactly the activities the runner selected and moves to the result summary.
    func importSelected(
        _ selected: [StravaImportCandidate],
        into activityStore: ActivityStore
    ) async {
        guard !selected.isEmpty else { return }
        phase = .importing
        outcome = await activityStore.importStravaActivities(selected)
        phase = .result
    }

    var displaySourceName: String {
        if !sourceName.isEmpty { return sourceName }
        return String(
            format: String(localized: "strava.import.source.multiple.format", defaultValue: "%d files"),
            locale: .autoupdatingCurrent,
            selectionCount
        )
    }
}
