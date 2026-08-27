import SwiftUI

struct ActivityHistoryView: View {
    @EnvironmentObject var activityStore: ActivityStore
    @EnvironmentObject var recognitionStore: RecognitionStore
    @Environment(\.analyticsManager) private var analyticsManager
    @State private var selectedActivity: SavedActivity?
    @State private var selectedActivityIDs: Set<UUID> = []
    @State private var isSelecting = false
    @State private var confirmsDeletion = false
    @State private var deletionFailed = false
    @State private var visibleActivityCount = Self.pageSize

    private static let pageSize = 20

    private var visibleActivities: [SavedActivity] {
        Array(activityStore.activities.prefix(visibleActivityCount))
    }

    var body: some View {
        Group {
            if activityStore.activities.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("My Activities")
        .navigationDestination(item: $selectedActivity) { activity in
            ActivityDetailView(activity: activity)
                .environmentObject(activityStore)
        }
        .toolbar {
            if !activityStore.activities.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSelecting
                        ? String(localized: "activity.history.selection.done", defaultValue: "Done")
                        : String(localized: "activity.history.selection.select", defaultValue: "Select")
                    ) {
                        isSelecting.toggle()
                        if !isSelecting { selectedActivityIDs.removeAll() }
                    }
                }
            }
            if isSelecting {
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) {
                        confirmsDeletion = true
                    } label: {
                        Label(
                            String(localized: "activity.history.delete.selected", defaultValue: "Delete Selected"),
                            systemImage: "trash"
                        )
                    }
                    .disabled(selectedActivityIDs.isEmpty)
                }
            }
        }
        .confirmationDialog(
            deletionConfirmationTitle,
            isPresented: $confirmsDeletion,
            titleVisibility: .visible
        ) {
            Button(deletionButtonTitle, role: .destructive) { deleteSelectedActivities() }
            Button(String(localized: "common.cancel", defaultValue: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "activity.history.delete.message", defaultValue: "This cannot be undone."))
        }
        .alert(
            String(localized: "activity.history.delete.failed.title", defaultValue: "Unable to Delete Activities"),
            isPresented: $deletionFailed
        ) {
            Button(String(localized: "common.ok", defaultValue: "OK"), role: .cancel) {}
        } message: {
            Text(String(localized: "activity.history.delete.failed.message", defaultValue: "Some activities could not be deleted. Please try again."))
        }
    }

    private var list: some View {
        List {
            ForEach(visibleActivities) { activity in
                HStack(spacing: 12) {
                    if isSelecting {
                        Image(systemName: selectedActivityIDs.contains(activity.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedActivityIDs.contains(activity.id) ? OutboundPalette.companion : .secondary)
                            .accessibilityHidden(true)
                    }
                    ActivityRowCard(activity: activity, activityStore: activityStore)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if isSelecting {
                        toggleSelection(for: activity.id)
                    } else {
                        selectedActivity = activity
                    }
                }
                .accessibilityAddTraits(isSelecting && selectedActivityIDs.contains(activity.id) ? .isSelected : [])
                .listRowInsets(.init(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .onDelete { indexSet in
                let activitiesToDelete = indexSet.compactMap { index in
                    visibleActivities.indices.contains(index) ? visibleActivities[index] : nil
                }
                Task {
                    for activity in activitiesToDelete {
                        try? await activityStore.delete(activity)
                    }
                }
            }
            .deleteDisabled(isSelecting)

            if visibleActivities.count < activityStore.activities.count {
                Button {
                    loadNextPage()
                } label: {
                    Text(String(localized: "common.load_more", defaultValue: "Load more"))
                        .frame(maxWidth: .infinity)
                }
                .listRowSeparator(.hidden)
                .accessibilityHint(String(localized: "activity.history.load_more.hint", defaultValue: "Shows older activities."))
            }
        }
        .listStyle(.plain)
    }

    private func loadNextPage() {
        let priorCount = visibleActivities.count
        visibleActivityCount = min(activityStore.activities.count, visibleActivityCount + Self.pageSize)
        let appendedCount = visibleActivities.count - priorCount
        let page = Int(ceil(Double(visibleActivities.count) / Double(Self.pageSize)))
        Task {
            await analyticsManager?.track(.init(.paginatedListPageLoaded, properties: [
                .sourceType: .string("activity_history"),
                .countBucket: .string(ProductAnalyticsBucket.count(appendedCount)),
                .pageDepthBucket: .string(ProductAnalyticsBucket.pageDepth(page))
            ]))
        }
    }

    private var selectedActivities: [SavedActivity] {
        activityStore.activities.filter { selectedActivityIDs.contains($0.id) }
    }

    private var deletionConfirmationTitle: String {
        let count = selectedActivityIDs.count
        if count == 1 {
            return String(localized: "activity.history.delete.confirmation.one", defaultValue: "Delete Activity?")
        }
        let format = String(localized: "activity.history.delete.confirmation.many", defaultValue: "Delete %lld Activities?")
        return String.localizedStringWithFormat(format, count)
    }

    private var deletionButtonTitle: String {
        let count = selectedActivityIDs.count
        if count == 1 {
            return String(localized: "activity.history.delete.action.one", defaultValue: "Delete Activity")
        }
        let format = String(localized: "activity.history.delete.action.many", defaultValue: "Delete %lld Activities")
        return String.localizedStringWithFormat(format, count)
    }

    private func toggleSelection(for id: UUID) {
        if selectedActivityIDs.contains(id) {
            selectedActivityIDs.remove(id)
        } else {
            selectedActivityIDs.insert(id)
        }
    }

    private func deleteSelectedActivities() {
        let activitiesToDelete = selectedActivities
        let count = activitiesToDelete.count
        guard count > 0 else { return }
        Task {
            do {
                try await activityStore.delete(activitiesToDelete)
                selectedActivityIDs.removeAll()
                isSelecting = false
                await analyticsManager?.track(.init(.activityDeleted, properties: [
                    .sourceType: .string("activity_history"),
                    .countBucket: .string(ProductAnalyticsBucket.count(count))
                ]))
            } catch {
                selectedActivityIDs.formIntersection(Set(activityStore.activities.map(\.id)))
                deletionFailed = true
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.run.circle")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
            Text("No activities yet")
                .font(.title3.bold())
            Text("Tap Record to start your first activity.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ActivityRowCard: View {
    @EnvironmentObject private var recognitionStore: RecognitionStore
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    let activity: SavedActivity
    let activityStore: ActivityStore

    private var recognitionPreview: RecognitionPreview? {
        recognitionStore.topRecognition(for: activity.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                thumbnail
                VStack(alignment: .leading, spacing: 6) {
                    Text(activity.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(activity.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if activity.activityEventID != nil {
                        Label("Shared activity", systemImage: "person.2.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(OutboundPalette.companion)
                    }
                    HStack(spacing: 14) {
                        Label(measurementPreferences.unitSystem.distanceString(meters: activity.distanceM), systemImage: "figure.run")
                        Label(activity.durationSecs.formatted(), systemImage: "timer")
                        if let pace = activity.avgPace {
                            Label(pace.paceString(for: measurementPreferences.unitSystem), systemImage: "speedometer")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if let recognitionPreview {
                RecognitionPill(preview: recognitionPreview)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let photo = activity.photos.first, let url = activityStore.imageURL(for: photo) {
            LocalImageView(url: url) {
                Color.orange.opacity(0.25)
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .topTrailing) {
                if let recognitionPreview {
                    RecognitionOrb(preview: recognitionPreview, size: 22)
                        .offset(x: 6, y: -6)
                }
            }
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.15))
                .frame(width: 60, height: 60)
                .overlay {
                    Image(systemName: "figure.run")
                        .foregroundStyle(.orange)
                }
                .overlay(alignment: .topTrailing) {
                    if let recognitionPreview {
                        RecognitionOrb(preview: recognitionPreview, size: 22)
                            .offset(x: 6, y: -6)
                    }
                }
        }
    }
}
