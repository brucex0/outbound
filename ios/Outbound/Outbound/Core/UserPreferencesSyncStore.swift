import Combine
import Foundation
import OSLog

struct UserPreferencesSnapshotDTO: Codable, Equatable {
    let schemaVersion: Int
    let measurementUnitSystem: MeasurementUnitSystem
    let temperatureUnit: TemperatureUnit
    let voiceGuideEnabled: Bool
    let appearanceMode: AppearanceMode
    let guideSelection: GuideSelection
    let shoes: [GearItem]
    let defaultShoeId: UUID?
    let music: MusicPreferencesSnapshot
    let preferredSessionPage: String
    let preferredLaunchGoalMode: String?
}

struct UserPreferencesResponseDTO: Decodable {
    let contractVersion: Int
    let preferences: UserPreferencesSnapshotDTO?
    let updatedAt: Date?
}

@MainActor
final class UserPreferencesSyncStore: ObservableObject {
    private static let logger = Logger(
        subsystem: "plainstride.outbound",
        category: "UserPreferencesSync"
    )

    private let api: APIClient
    private let defaults: UserDefaults
    private var cancellables: Set<AnyCancellable> = []
    private var uploadTask: Task<Void, Never>?
    private var currentUserID: String?
    private var hasCompletedInitialMerge = false
    private var hasLocalChanges = false
    private var isApplyingRemotePreferences = false
    private var lastUploadedPreferences: UserPreferencesSnapshotDTO?

    private var measurementPreferences: MeasurementPreferences?
    private var appearancePreferences: AppearancePreferences?
    private var guideCatalog: GuideCatalogStore?
    private var gearStore: GearStore?
    private var musicStore: MusicStore?

    init(api: APIClient? = nil, defaults: UserDefaults = .standard) {
        self.api = api ?? .shared
        self.defaults = defaults
    }

    func start(
        userID: String,
        measurementPreferences: MeasurementPreferences,
        appearancePreferences: AppearancePreferences,
        guideCatalog: GuideCatalogStore,
        gearStore: GearStore,
        musicStore: MusicStore
    ) async {
        if currentUserID != userID {
            reset(for: userID)
            self.measurementPreferences = measurementPreferences
            self.appearancePreferences = appearancePreferences
            self.guideCatalog = guideCatalog
            self.gearStore = gearStore
            self.musicStore = musicStore
            beginObserving()
        }
        await refresh()
    }

    func refresh() async {
        guard currentUserID != nil else { return }
        do {
            let response = try await api.fetchUserPreferences()
            guard currentUserID != nil else { return }
            if hasLocalChanges {
                hasCompletedInitialMerge = true
                await uploadCurrentPreferences()
            } else if let remote = response.preferences {
                lastUploadedPreferences = remote
                apply(remote)
                hasCompletedInitialMerge = true
            } else {
                hasCompletedInitialMerge = true
                hasLocalChanges = true
                await uploadCurrentPreferences()
            }
        } catch {
            Self.logger.error("Preference refresh failed; keeping the local snapshot. \(error.localizedDescription, privacy: .public)")
        }
    }

    private func reset(for userID: String) {
        uploadTask?.cancel()
        uploadTask = nil
        cancellables.removeAll()
        currentUserID = userID
        hasCompletedInitialMerge = false
        hasLocalChanges = false
        isApplyingRemotePreferences = false
        lastUploadedPreferences = nil
    }

    private func beginObserving() {
        let publishers: [AnyPublisher<Void, Never>] = [
            measurementPreferences?.objectWillChange.eraseToAnyPublisher(),
            appearancePreferences?.objectWillChange.eraseToAnyPublisher(),
            guideCatalog?.objectWillChange.eraseToAnyPublisher(),
            gearStore?.objectWillChange.eraseToAnyPublisher(),
            musicStore?.objectWillChange.eraseToAnyPublisher(),
        ].compactMap { $0 }

        Publishers.MergeMany(publishers)
            .sink { [weak self] in self?.preferenceDidChange() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification, object: defaults)
            .sink { [weak self] _ in self?.preferenceDidChange() }
            .store(in: &cancellables)
    }

    private func preferenceDidChange() {
        guard !isApplyingRemotePreferences else { return }
        hasLocalChanges = true
        guard hasCompletedInitialMerge else { return }
        uploadTask?.cancel()
        uploadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await self?.uploadCurrentPreferences()
        }
    }

    private func uploadCurrentPreferences() async {
        guard let snapshot = captureSnapshot() else { return }
        if snapshot == lastUploadedPreferences {
            hasLocalChanges = false
            return
        }
        do {
            let response = try await api.updateUserPreferences(snapshot)
            guard currentUserID != nil else { return }
            lastUploadedPreferences = response.preferences ?? snapshot
            if captureSnapshot() == snapshot {
                hasLocalChanges = false
            }
        } catch {
            hasLocalChanges = true
            Self.logger.error("Preference upload failed; it will retry later. \(error.localizedDescription, privacy: .public)")
        }
    }

    private func captureSnapshot() -> UserPreferencesSnapshotDTO? {
        guard let measurementPreferences,
              let appearancePreferences,
              let guideCatalog,
              let gearStore,
              let musicStore
        else { return nil }

        let preferredSessionPage = defaults.string(forKey: "preferred_session_page_v1") == "camera"
            ? "camera"
            : "map"
        let preferredGoal = defaults.string(forKey: "preferred_launch_goal_mode_v1")
            .flatMap { $0.isEmpty ? nil : $0 }
        let voiceGuideEnabled = defaults.object(forKey: "voice_guide_enabled_v1") as? Bool ?? true

        return UserPreferencesSnapshotDTO(
            schemaVersion: 1,
            measurementUnitSystem: measurementPreferences.unitSystem,
            temperatureUnit: measurementPreferences.temperatureUnit,
            voiceGuideEnabled: voiceGuideEnabled,
            appearanceMode: appearancePreferences.mode,
            guideSelection: guideCatalog.selection,
            shoes: gearStore.shoes,
            defaultShoeId: gearStore.defaultShoeID,
            music: musicStore.persistedPreferences,
            preferredSessionPage: preferredSessionPage,
            preferredLaunchGoalMode: preferredGoal
        )
    }

    private func apply(_ preferences: UserPreferencesSnapshotDTO) {
        guard let measurementPreferences,
              let appearancePreferences,
              let guideCatalog,
              let gearStore,
              let musicStore
        else { return }

        isApplyingRemotePreferences = true
        measurementPreferences.unitSystem = preferences.measurementUnitSystem
        measurementPreferences.temperatureUnit = preferences.temperatureUnit
        appearancePreferences.mode = preferences.appearanceMode
        guideCatalog.applySyncedSelection(preferences.guideSelection)
        gearStore.applySyncedPreferences(
            shoes: preferences.shoes,
            defaultShoeID: preferences.defaultShoeId
        )
        musicStore.applySyncedPreferences(preferences.music)
        defaults.set(preferences.voiceGuideEnabled, forKey: "voice_guide_enabled_v1")
        defaults.set(preferences.preferredSessionPage, forKey: "preferred_session_page_v1")
        defaults.set(preferences.preferredLaunchGoalMode ?? "", forKey: "preferred_launch_goal_mode_v1")
        isApplyingRemotePreferences = false
        hasLocalChanges = false
    }
}
