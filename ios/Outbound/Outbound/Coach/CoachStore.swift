import Foundation
import Combine

@MainActor
final class CoachStore: ObservableObject {
    @Published var profile: CoachProfile?
    @Published var isSyncing = false

    private let localKey = "coach_profile_v"
    private let api = APIClient.shared

    func syncIfNeeded() async {
        guard let userId = AuthStore.currentUserId else { return }
        let localVersion = UserDefaults.standard.integer(forKey: localKey)
        do {
            let remote = try await api.fetchCoachProfile(userId: userId)
            if remote.version > localVersion {
                save(remote)
            }
        } catch {
            loadLocal()
        }
    }

    func rebuild(userId: String) async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            let profile = try await api.rebuildCoachProfile(userId: userId)
            save(profile)
        } catch {
            print("[CoachStore] rebuild failed: \(error)")
        }
    }

    private func save(_ profile: CoachProfile) {
        self.profile = profile
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: "coach_profile_data")
            UserDefaults.standard.set(profile.version, forKey: localKey)
        }
    }

    private func loadLocal() {
        guard let data = UserDefaults.standard.data(forKey: "coach_profile_data"),
              let profile = try? JSONDecoder().decode(CoachProfile.self, from: data)
        else { return }
        self.profile = profile
    }
}
