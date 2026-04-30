import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var coachStore: CoachStore
    @EnvironmentObject var coachCatalog: CoachCatalogStore
    @EnvironmentObject var activityStore: ActivityStore
    @EnvironmentObject var healthAuthorizationStore: HealthAuthorizationStore

    private let sectionPreviewLimit = 3

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    coachCard
                    appleHealthCard
                    highlightsSection
                    myActivitiesSection
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
                Text("Coach")
                    .font(.title3.bold())
                Spacer()
                if coachStore.isSyncing {
                    ProgressView()
                } else {
                    NavigationLink {
                        CoachSelectionView()
                            .environmentObject(coachCatalog)
                    } label: {
                        Label("Change", systemImage: "slider.horizontal.3")
                            .font(.subheadline.bold())
                    }
                }
            }

            CoachTemplateSummaryView(persona: coachCatalog.selectedPersona)

            if let profile = coachStore.profile {
                HStack(spacing: 20) {
                    StatBlock(label: "Weekly",
                              value: "\(String(format: "%.0f", profile.athlete.weeklyVolumeKm)) km")
                    StatBlock(label: "Level",
                              value: profile.athlete.fitnessLevel.capitalized)
                    StatBlock(label: "Consistency",
                              value: "\(Int(profile.memorySnapshot.consistencyScore * 100))%")
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var highlightsSection: some View {
        HStack(spacing: 12) {
            ProfileMetricCard(
                label: "Activities",
                value: "\(activityStore.activities.count)",
                systemImage: "figure.run"
            )
            ProfileMetricCard(
                label: "Photos",
                value: "\(totalPhotoCount)",
                systemImage: "camera"
            )
            ProfileMetricCard(
                label: "This Week",
                value: String(format: "%.1f km", weeklyDistanceKm),
                systemImage: "calendar"
            )
        }
    }

    private var appleHealthCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Apple Health")
                        .font(.title3.bold())
                    Text(healthAuthorizationStore.snapshot.statusTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                Spacer()

                if healthAuthorizationStore.isRefreshing || healthAuthorizationStore.isRequestingAccess {
                    ProgressView()
                } else {
                    Image(systemName: "heart.text.square.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                }
            }

            Text(healthAuthorizationStore.snapshot.statusDetail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !healthAuthorizationStore.snapshot.readDataTypeTitles.isEmpty {
                Text(healthAuthorizationStore.snapshot.readDataTypeTitles.joined(separator: " • "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let lastErrorMessage = healthAuthorizationStore.lastErrorMessage {
                Text(lastErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if healthAuthorizationStore.snapshot.isHealthDataAvailable {
                Button {
                    Task { await healthAuthorizationStore.requestAuthorization() }
                } label: {
                    HStack {
                        Text(healthAuthorizationStore.actionLabel)
                            .font(.subheadline.bold())
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(healthAuthorizationStore.isRequestingAccess)
            }
        }
        .padding()
        .background(.red.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var myActivitiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("My Activities")
                    .font(.title3.bold())
                Spacer()
                if activityStore.activities.count > sectionPreviewLimit {
                    NavigationLink("See All") {
                        ActivityHistoryView()
                            .environmentObject(activityStore)
                    }
                    .font(.caption.weight(.semibold))
                }
            }

            if activityStore.activities.isEmpty {
                emptyActivitiesPlaceholder
            } else {
                ForEach(Array(activityStore.activities.prefix(sectionPreviewLimit))) { activity in
                    NavigationLink(value: activity) {
                        ActivityCard(activity: activity, activityStore: activityStore)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyActivitiesPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.run.circle")
                .font(.system(size: 44))
                .foregroundStyle(.orange.opacity(0.6))
            Text("No activities yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var weeklyDistanceKm: Double {
        let calendar = Calendar.current
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? .distantPast
        return activityStore.activities
            .filter { $0.startedAt >= startOfWeek }
            .reduce(0) { $0 + $1.distanceM } / 1000
    }

    private var totalPhotoCount: Int {
        activityStore.activities.reduce(0) { $0 + $1.photos.count }
    }
}

private struct ProfileMetricCard: View {
    let label: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.orange)
            Text(value)
                .font(.title3.bold().monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct ActivityCard: View {
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
            LocalImageView(url: url) {
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
