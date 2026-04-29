import SwiftUI

struct ActivityHistoryView: View {
    @EnvironmentObject var activityStore: ActivityStore
    @State private var selectedActivity: SavedActivity?

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
    }

    private var list: some View {
        List {
            ForEach(activityStore.activities) { activity in
                ActivityRowCard(activity: activity, activityStore: activityStore)
                    .onTapGesture { selectedActivity = activity }
                    .listRowInsets(.init(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .onDelete { indexSet in
                for i in indexSet {
                    try? activityStore.delete(activityStore.activities[i])
                }
            }
        }
        .listStyle(.plain)
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
    let activity: SavedActivity
    let activityStore: ActivityStore

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 6) {
                Text(activity.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(activity.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    Label(String(format: "%.2f km", activity.distanceM / 1000), systemImage: "figure.run")
                    Label(activity.durationSecs.formatted(), systemImage: "timer")
                    if let pace = activity.avgPace {
                        Label(pace.paceString, systemImage: "speedometer")
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
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.15))
                .frame(width: 60, height: 60)
                .overlay {
                    Image(systemName: "figure.run")
                        .foregroundStyle(.orange)
                }
        }
    }
}
