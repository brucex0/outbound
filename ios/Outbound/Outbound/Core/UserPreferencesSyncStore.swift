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

private struct UserDefaultsPreferenceSlice: Equatable {
    let voiceGuideEnabled: Bool
    let preferredSessionPage: String
    let preferredLaunchGoalMode: String?
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
    private var lastRejectedPreferences: UserPreferencesSnapshotDTO?
    private var lastObservedDefaultsPreferences: UserDefaultsPreferenceSlice?

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
        lastRejectedPreferences = nil
        lastObservedDefaultsPreferences = nil
    }

    private func beginObserving() {
        guard let measurementPreferences,
              let appearancePreferences,
              let guideCatalog,
              let gearStore,
              let musicStore
        else { return }

        let publishers: [AnyPublisher<Void, Never>] = [
            measurementPreferences.$unitSystem.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            measurementPreferences.$temperatureUnit.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            appearancePreferences.$mode.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            guideCatalog.$selection.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            gearStore.$shoes.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            gearStore.$defaultShoeID.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            musicStore.$selectedQuickPickID.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            musicStore.$selectedCustomItems.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            musicStore.$isMusicDisabled.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            musicStore.$repeatsQueue.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            musicStore.$shufflesQueue.dropFirst().map { _ in () }.eraseToAnyPublisher(),
        ]

        Publishers.MergeMany(publishers)
            .sink { [weak self] in self?.preferenceDidChange() }
            .store(in: &cancellables)

        lastObservedDefaultsPreferences = captureDefaultsPreferences()
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification, object: defaults)
            .sink { [weak self] _ in self?.userDefaultsDidChange() }
            .store(in: &cancellables)
    }

    private func userDefaultsDidChange() {
        let current = captureDefaultsPreferences()
        guard current != lastObservedDefaultsPreferences else { return }
        lastObservedDefaultsPreferences = current
        preferenceDidChange()
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
        if snapshot == lastRejectedPreferences {
            hasLocalChanges = false
            return
        }
        do {
            let response = try await api.updateUserPreferences(snapshot)
            guard currentUserID != nil else { return }
            lastUploadedPreferences = response.preferences ?? snapshot
            lastRejectedPreferences = nil
            if captureSnapshot() == snapshot {
                hasLocalChanges = false
            }
        } catch {
            if let apiError = error as? APIError,
               case let .http(statusCode, _, _) = apiError,
               statusCode == 400 {
                lastRejectedPreferences = snapshot
                hasLocalChanges = false
                Self.logger.error("Preference upload was rejected; this snapshot will not retry until a preference changes. \(error.localizedDescription, privacy: .public)")
            } else {
                hasLocalChanges = true
                Self.logger.error("Preference upload failed; it will retry later. \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func captureSnapshot() -> UserPreferencesSnapshotDTO? {
        guard let measurementPreferences,
              let appearancePreferences,
              let guideCatalog,
              let gearStore,
              let musicStore
        else { return nil }

        let defaultsPreferences = captureDefaultsPreferences()

        return UserPreferencesSnapshotDTO(
            schemaVersion: 1,
            measurementUnitSystem: measurementPreferences.unitSystem,
            temperatureUnit: measurementPreferences.temperatureUnit,
            voiceGuideEnabled: defaultsPreferences.voiceGuideEnabled,
            appearanceMode: appearancePreferences.mode,
            guideSelection: guideCatalog.selection,
            shoes: gearStore.shoes,
            defaultShoeId: gearStore.defaultShoeID,
            music: musicStore.persistedPreferences,
            preferredSessionPage: defaultsPreferences.preferredSessionPage,
            preferredLaunchGoalMode: defaultsPreferences.preferredLaunchGoalMode
        )
    }

    private func captureDefaultsPreferences() -> UserDefaultsPreferenceSlice {
        let preferredSessionPage = defaults.string(forKey: "preferred_session_page_v1") == "camera"
            ? "camera"
            : "map"
        let preferredLaunchGoalMode = defaults.string(forKey: "preferred_launch_goal_mode_v1")
            .flatMap { $0.isEmpty ? nil : $0 }
        let voiceGuideEnabled = defaults.object(forKey: "voice_guide_enabled_v1") as? Bool ?? true
        return UserDefaultsPreferenceSlice(
            voiceGuideEnabled: voiceGuideEnabled,
            preferredSessionPage: preferredSessionPage,
            preferredLaunchGoalMode: preferredLaunchGoalMode
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
