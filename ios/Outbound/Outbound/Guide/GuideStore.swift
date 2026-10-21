import Foundation
import Combine

@MainActor
final class GuideStore: ObservableObject {
    @Published var profile: GuideProfile?
    @Published var isSyncing = false

    private let localKey = "guide_profile_v"
    private let api = APIClient.shared
    private var lastReferenceSource: String?
    var coachingReferenceSource: String { lastReferenceSource ?? "unavailable" }

    func syncIfNeeded() async {
        guard AuthStore.currentUserId != nil else { return }
        if profile == nil { loadLocal() }
        let localVersion = UserDefaults.standard.integer(forKey: localKey)
        do {
            let remote = try await api.fetchGuideProfile()
            if profile == nil || remote.version >= localVersion {
                save(remote)
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            ActivityDiagnosticLog.error(.lifecycle, "Guide profile fetch failed error=\(ActivityDiagnosticLog.errorCategory(error))")
            loadLocal()
        }
    }

    /// An in-memory reference from saved runs; never persisted as a server profile.
    func coachingProfile(activities: [SavedActivity], persona: GuidePersona, now: Date = Date()) -> GuideProfile? {
        if let profile, Self.hasReferencePace(profile) {
            recordReferenceSource("profile")
            return profile
        }
        let cutoff = now.addingTimeInterval(-30 * 86_400)
        let runs = activities.filter {
            $0.activityType == .running && $0.startedAt >= cutoff && $0.startedAt <= now
                && $0.durationSecs >= 300 && $0.distanceM >= 500
        }.sorted { $0.startedAt > $1.startedAt }.prefix(10)
        let paces = runs.compactMap { activity -> Double? in
            let pace = activity.avgPace ?? activity.activityType.plausibleAveragePace(
                durationSeconds: Double(activity.durationSecs), distanceMeters: activity.distanceM
            )
            guard let pace, pace.isFinite, (60...3_600).contains(pace) else { return nil }
            return pace
        }.sorted()
        guard !paces.isEmpty else {
            recordReferenceSource("unavailable")
            return profile
        }
        recordReferenceSource("local_history")
        let middle = paces.count / 2
        let reference = paces.count.isMultiple(of: 2) ? (paces[middle - 1] + paces[middle]) / 2 : paces[middle]
        let weekStart = now.addingTimeInterval(-7 * 86_400)
        let weeklyVolume = runs.filter { $0.startedAt >= weekStart }.reduce(0) { $0 + $1.distanceM } / 1_000
        return GuideProfile(
            version: profile?.version ?? 0,
            guideName: profile?.guideName ?? persona.template.displayName,
            coachPersonaId: profile?.coachPersonaId ?? persona.template.id,
            voiceProfileId: profile?.voiceProfileId ?? persona.voice.id,
            athlete: .init(
                fitnessLevel: profile?.athlete.fitnessLevel ?? "unknown",
                weeklyVolumeKm: profile?.athlete.weeklyVolumeKm ?? weeklyVolume,
                preferredPaceSecs: reference,
                strengths: profile?.athlete.strengths ?? [], weaknesses: profile?.athlete.weaknesses ?? [],
                records: profile?.athlete.records ?? [:]
            ),
            goals: profile?.goals ?? [],
            memorySnapshot: profile?.memorySnapshot ?? .init(
                recentActivities: [], weeklyVolumeKm: weeklyVolume,
                longestRunKm: runs.map { $0.distanceM / 1_000 }.max() ?? 0,
                consistencyScore: 0, recentInsight: ""
            ),
            builtAt: profile?.builtAt ?? runs.first!.startedAt
        )
    }

    private func recordReferenceSource(_ source: String) {
        guard source != lastReferenceSource else { return }
        lastReferenceSource = source
        ActivityDiagnosticLog.notice(.lifecycle, "Coaching reference source=\(source)")
    }

    private static func hasReferencePace(_ profile: GuideProfile) -> Bool {
        if let pace = profile.athlete.preferredPaceSecs, pace.isFinite, (60...3_600).contains(pace) { return true }
        return profile.memorySnapshot.recentActivities.contains { $0.avgPaceSecs.isFinite && (60...3_600).contains($0.avgPaceSecs) }
    }

    func rebuild() async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            let profile = try await api.rebuildGuideProfile()
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
