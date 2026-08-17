import Foundation
import Combine

@MainActor
final class GuideStore: ObservableObject {
    @Published var profile: GuideProfile?
    @Published var isSyncing = false

    private let localKey = "guide_profile_v"
    private let api = APIClient.shared

    func syncIfNeeded() async {
        guard let userId = AuthStore.currentUserId else { return }
        let localVersion = UserDefaults.standard.integer(forKey: localKey)
        do {
            let remote = try await api.fetchGuideProfile(userId: userId)
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
            let profile = try await api.rebuildGuideProfile(userId: userId)
            save(profile)
        } catch {
            print("[GuideStore] rebuild failed: \(error)")
        }
    }

    private func save(_ profile: GuideProfile) {
        self.profile = profile
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: "guide_profile_data")
            UserDefaults.standard.set(profile.version, forKey: localKey)
        }
    }

    private func loadLocal() {
        guard let data = UserDefaults.standard.data(forKey: "guide_profile_data"),
              let profile = try? JSONDecoder().decode(GuideProfile.self, from: data)
        else { return }
        self.profile = profile
    }
}
