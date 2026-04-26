import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var coachStore: CoachStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    coachCard
                    Divider()
                    // TODO: activity history list
                }
                .padding()
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign Out") { authStore.signOut() }
                        .foregroundStyle(.red)
                }
            }
        }
    }

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
                    StatBlock(label: "Weekly", value: "\(String(format: "%.0f", profile.athlete.weeklyVolumeKm)) km")
                    StatBlock(label: "Level", value: profile.athlete.fitnessLevel.capitalized)
                    StatBlock(label: "Consistency", value: "\(Int(profile.memorySnapshot.consistencyScore * 100))%")
                }
            }
        }
        .padding()
        .background(.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
