import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var coachStore: CoachStore
    @EnvironmentObject var activityStore: ActivityStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    coachCard
                    myRunsSection
                }
                .padding()
            }
            .navigationTitle("Me")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign Out") { authStore.signOut() }
                        .foregroundStyle(.red)
                }
            }
            .navigationDestination(for: SavedActivity.self) { activity in
                ActivityDetailView(activity: activity)
                    .environmentObject(activityStore)
            }
        }
    }

    // MARK: - Coach card

    private var coachCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text(coachStore.profile?.coachName ?? "Your Coach")
                        .font(.title2.bold())
                    Text(coachStore.profile?.personality.capitalized ?? "Not set up yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if coachStore.isSyncing {
                    ProgressView()
                } else {
                    Image(systemName: "brain.head.profile")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                }
            }

            if let profile = coachStore.profile {
                HStack(spacing: 20) {
                    StatBlock(label: "Weekly",
                              value: "\(String(format: "%.0f", profile.athlete.weeklyVolumeKm)) km")
                    StatBlock(label: "Level",
                              value: profile.athlete.fitnessLevel.capitalized)
                    StatBlock(label: "Consistency",
                              value: "\(Int(profile.memorySnapshot.consistencyScore * 100))%")
                }
            }
        }
        .padding()
        .background(.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - My Runs

    private var myRunsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("My Runs")
                    .font(.title3.bold())
                Spacer()
                Text("\(activityStore.activities.count) total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if activityStore.activities.isEmpty {
                emptyRunsPlaceholder
            } else {
                ForEach(activityStore.activities) { activity in
                    NavigationLink(value: activity) {
                        RunCard(activity: activity, activityStore: activityStore)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyRunsPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.run.circle")
                .font(.system(size: 44))
                .foregroundStyle(.orange.opacity(0.6))
            Text("No runs yet — hit Record to start.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - Run card

private struct RunCard: View {
    let activity: SavedActivity
    let activityStore: ActivityStore

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 5) {
                Text(activity.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(activity.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Label(String(format: "%.2f km", activity.distanceM / 1000),
                          systemImage: "figure.run")
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
            AsyncImage(url: url) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                Color.orange.opacity(0.25)
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.15))
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "figure.run").foregroundStyle(.orange)
                }
        }
    }
}
