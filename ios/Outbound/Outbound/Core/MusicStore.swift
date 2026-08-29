import Combine
import Foundation
import OSLog

@MainActor
final class MusicStore: ObservableObject {
    private static let logger = Logger(subsystem: "plainstride.outbound", category: "MusicStore")

    @Published private(set) var snapshot: MusicConnectionSnapshot
    @Published private(set) var quickPicks: [MusicQuickPick] = []
    @Published private(set) var playback: MusicPlaybackSnapshot
    @Published private(set) var searchResultsByCategory: [MusicSearchCategory: [MusicSearchResult]] = [:]
    @Published private(set) var selectedCustomItems: [MusicSearchResult] = []
    @Published private(set) var isMusicDisabled: Bool
    @Published private(set) var searchingCategories: Set<MusicSearchCategory> = []
    @Published var repeatsQueue = true
    @Published var shufflesQueue = false
    @Published var selectedQuickPickID: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isLoadingQuickPicks = false
    @Published private(set) var isStartingPlayback = false
    @Published private(set) var lastErrorMessage: String?

    private let service: any MusicService
    private let defaults: UserDefaults
    private let selectedQuickPickKey = "music_selected_quick_pick_v1"
    private let selectedCustomItemsKey = "music_selected_custom_items_v1"
    private let musicDisabledKey = "music_disabled_v1"
    private let workoutPlaybackOwnedKey = "music_workout_playback_owned_v1"
    private let workoutPlaybackShouldResumeKey = "music_workout_playback_should_resume_v1"
    private let workoutQuickPickKey = "music_workout_quick_pick_v1"
    private var pendingWorkoutPlayback = false
    private var startedPlaybackForWorkout = false
    private var shouldResumeWorkoutPlayback = false
    private var activeWorkoutQuickPick: MusicQuickPick?
    private var didAttemptRecoveredWorkoutPlayback = false
    private var didChooseMusicForCurrentSetup = false

    init(
        service: (any MusicService)? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.service = service ?? MusicServiceFactory.makeDefault()
        self.defaults = defaults
        snapshot = self.service.currentSnapshot
        playback = self.service.currentPlayback
        isMusicDisabled = defaults.bool(forKey: musicDisabledKey)
        selectedQuickPickID = isMusicDisabled ? nil : defaults.string(forKey: selectedQuickPickKey)
        selectedCustomItems = Self.decode(
            [MusicSearchResult].self,
            from: defaults.data(forKey: selectedCustomItemsKey)
        ) ?? []
        startedPlaybackForWorkout = defaults.bool(forKey: workoutPlaybackOwnedKey)
        shouldResumeWorkoutPlayback = defaults.bool(forKey: workoutPlaybackShouldResumeKey)
        activeWorkoutQuickPick = Self.decode(
            MusicQuickPick.self,
            from: defaults.data(forKey: workoutQuickPickKey)
        )
    }

    var isConnected: Bool {
        snapshot.connectionState == .connected
    }

    var canConnect: Bool {
        snapshot.connectionState == .notConnected || snapshot.connectionState == .denied
    }

    var canShowQuickPicks: Bool {
        isConnected
    }

    var needsPlaybackSetup: Bool {
        isConnected && !snapshot.canPlayCatalogContent
    }

    var selectedQuickPick: MusicQuickPick? {
        quickPicks.first(where: { $0.id == selectedQuickPickID })
    }

    var isSearching: Bool { !searchingCategories.isEmpty }

    func searchResults(for category: MusicSearchCategory) -> [MusicSearchResult] {
        searchResultsByCategory[category] ?? []
    }

    func isSearching(_ category: MusicSearchCategory) -> Bool {
        searchingCategories.contains(category)
    }

    var hasDeveloperTokenError: Bool {
        guard let lastErrorMessage else { return false }
        let normalized = lastErrorMessage.lowercased()
        return normalized.contains("musickit developer token") || normalized.contains("setup is incomplete")
    }

    var musicSummaryLine: String {
        if playback.isPlaying {
            return "\(playback.title) • \(playback.subtitle)"
        }
        if hasDeveloperTokenError {
            return "Music is unavailable in this build right now."
        }
        if let selectedQuickPick {
            return "Queued: \(selectedQuickPick.title)"
        }
        if isConnected {
            if needsPlaybackSetup {
                return "Pick a mix now. Playback may still fail until Apple Music playback access is fully available."
            }
            return "Pick a mix for this run."
        }
        return snapshot.statusDetail
    }

    var troubleshootingLine: String? {
        guard !hasDeveloperTokenError else { return nil }
        guard needsPlaybackSetup else { return nil }
        return "If you're testing on a real device, make sure the device is signed into an active Apple Music subscription and that MusicKit is enabled for Plainstride's App ID in the Apple Developer portal."
    }

    var musicKitSetupBannerText: String? {
        nil
    }

    var primaryActionTitle: String {
        if isRefreshing || isLoadingQuickPicks || isStartingPlayback {
            return "Working..."
        }
        if canShowQuickPicks {
            return quickPicks.isEmpty ? "Load workout mixes" : "Refresh mixes"
        }
        return "Connect Apple Music"
    }

    var isPrimaryActionEnabled: Bool {
        !(isRefreshing || isLoadingQuickPicks || isStartingPlayback || snapshot.connectionState == .connecting)
    }

    func refresh() async {
        Self.logger.info("Refresh music store state.")
        isRefreshing = true
        defer { isRefreshing = false }

        snapshot = await service.refreshSnapshot()
        playback = await service.refreshPlayback()
        if isConnected {
            await loadQuickPicks()
        } else {
            quickPicks = []
        }
    }

    func connectAppleMusic() async {
        Self.logger.info("Connect Apple Music requested from UI.")
        lastErrorMessage = nil
        snapshot = snapshot.with(connectionState: .connecting)
        do {
            snapshot = try await service.connect()
            playback = await service.refreshPlayback()
            if isConnected {
                await loadQuickPicks()
            }
        } catch {
            Self.logger.error("Connect Apple Music failed. \(self.describe(error), privacy: .public)")
            snapshot = await service.refreshSnapshot()
            lastErrorMessage = error.localizedDescription
        }
    }

    func loadQuickPicks() async {
        guard isConnected else { return }
        Self.logger.info("Load Apple Music quick picks.")
        isLoadingQuickPicks = true
        defer { isLoadingQuickPicks = false }

        do {
            quickPicks = try await service.loadQuickPicks()
            if selectedQuickPick == nil, selectedCustomItems.isEmpty, !isMusicDisabled {
                selectedQuickPickID = quickPicks.first?.id
            }
            persistSelectedQuickPick()
        } catch {
            Self.logger.error("Load Apple Music quick picks failed. \(self.describe(error), privacy: .public)")
            lastErrorMessage = error.localizedDescription
            quickPicks = []
        }
    }

    func selectQuickPick(_ quickPick: MusicQuickPick) {
        Self.logger.info("Selected music quick pick. quickPickID=\(quickPick.id, privacy: .public)")
        selectedQuickPickID = quickPick.id
        selectedCustomItems = []
        isMusicDisabled = false
        didChooseMusicForCurrentSetup = true
        persistMusicDisabled()
        persistSelectedQuickPick()
        persistSelectedCustomItems()
    }

    func disableMusic() {
        Self.logger.info("Music disabled from workout setup.")
        selectedQuickPickID = nil
        selectedCustomItems = []
        isMusicDisabled = true
        didChooseMusicForCurrentSetup = true
        pendingWorkoutPlayback = false
        clearWorkoutPlaybackRecoveryState()
        persistMusicDisabled()
        persistSelectedQuickPick()
        persistSelectedCustomItems()
    }

    func applyWorkoutSuggestion(title: String, detail: String, sport: SportType) {
        guard !didChooseMusicForCurrentSetup, !isMusicDisabled, !quickPicks.isEmpty else { return }
        let text = "\(title) \(detail)".lowercased()
        let preferredID: String
        if text.contains("easy") || text.contains("recovery") || text.contains("walk") {
            preferredID = "outbound-recovery"
        } else if text.contains("tempo") || text.contains("threshold") || text.contains("interval") || text.contains("speed") {
            preferredID = "outbound-electronic"
        } else {
            preferredID = sport == .bike ? "outbound-electronic" : "outbound-upbeat"
        }
        if let suggestion = quickPicks.first(where: { $0.id == preferredID }) {
            selectedQuickPickID = suggestion.id
            persistSelectedQuickPick()
        }
    }

    func searchCatalog(_ term: String, category: MusicSearchCategory) async {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { searchResultsByCategory[category] = []; return }
        searchingCategories.insert(category)
        defer { searchingCategories.remove(category) }
        do {
            searchResultsByCategory[category] = try await service.search(term: trimmed, category: category)
        } catch {
            lastErrorMessage = error.localizedDescription
            searchResultsByCategory[category] = []
        }
    }

    func preloadCatalog(_ term: String) async {
        async let songs: Void = searchCatalog(term, category: .songs)
        async let albums: Void = searchCatalog(term, category: .albums)
        async let playlists: Void = searchCatalog(term, category: .playlists)
        _ = await (songs, albums, playlists)
    }

    func toggleCustomSelection(_ item: MusicSearchResult) {
        if item.category != .songs {
            selectedCustomItems = selectedCustomItems == [item] ? [] : [item]
        } else if let index = selectedCustomItems.firstIndex(of: item) {
            selectedCustomItems.remove(at: index)
        } else {
            if selectedCustomItems.first?.category != .songs { selectedCustomItems = [] }
            selectedCustomItems.append(item)
        }
        if !selectedCustomItems.isEmpty {
            selectedQuickPickID = nil
            isMusicDisabled = false
            didChooseMusicForCurrentSetup = true
            persistMusicDisabled()
            persistSelectedQuickPick()
        }
        persistSelectedCustomItems()
    }

    func beginWorkoutPlaybackIfNeeded() async {
        guard isConnected, !isMusicDisabled else { return }
        guard selectedQuickPick != nil || !selectedCustomItems.isEmpty else { return }
        activeWorkoutQuickPick = selectedQuickPick
        pendingWorkoutPlayback = true
        isStartingPlayback = true
        defer { isStartingPlayback = false }
        lastErrorMessage = nil

        do {
            if selectedCustomItems.isEmpty, let selectedQuickPick {
                Self.logger.info("Begin workout playback. quickPickID=\(selectedQuickPick.id, privacy: .public)")
                playback = try await service.play(
                    quickPick: selectedQuickPick,
                    repeatAll: repeatsQueue,
                    shuffle: shufflesQueue
                )
            } else {
                playback = try await service.play(selection: selectedCustomItems, repeatAll: repeatsQueue, shuffle: shufflesQueue)
            }
            pendingWorkoutPlayback = !playback.hasActiveQueue
            startedPlaybackForWorkout = playback.hasActiveQueue
            shouldResumeWorkoutPlayback = playback.isPlaying
            persistWorkoutPlaybackRecoveryState()
        } catch {
            Self.logger.error("Begin workout playback failed. \(self.describe(error), privacy: .public)")
            lastErrorMessage = error.localizedDescription
            playback = await service.refreshPlayback()
            startedPlaybackForWorkout = false
            shouldResumeWorkoutPlayback = false
            persistWorkoutPlaybackRecoveryState()
        }
    }

    func resumeRecoveredWorkoutPlaybackIfNeeded() async -> WorkoutMusicRecoveryOutcome? {
        guard startedPlaybackForWorkout,
              shouldResumeWorkoutPlayback,
              !didAttemptRecoveredWorkoutPlayback
        else { return nil }

        didAttemptRecoveredWorkoutPlayback = true
        isStartingPlayback = true
        defer { isStartingPlayback = false }
        lastErrorMessage = nil
        Self.logger.info("Recover workout music after interrupted activity resumed.")

        snapshot = await service.refreshSnapshot()
        guard isConnected else {
            lastErrorMessage = snapshot.statusDetail
            pendingWorkoutPlayback = true
            return .failed
        }

        playback = await service.refreshPlayback()
        if playback.isPlaying {
            pendingWorkoutPlayback = false
            return .alreadyPlaying
        }

        do {
            let outcome: WorkoutMusicRecoveryOutcome
            if playback.hasActiveQueue {
                playback = try await service.resume()
                outcome = .resumedExistingQueue
            } else {
                if quickPicks.isEmpty {
                    await loadQuickPicks()
                }
                let quickPick = selectedQuickPick ?? activeWorkoutQuickPick
                if selectedCustomItems.isEmpty, let quickPick {
                    playback = try await service.play(
                        quickPick: quickPick,
                        repeatAll: repeatsQueue,
                        shuffle: shufflesQueue
                    )
                } else if !selectedCustomItems.isEmpty {
                    playback = try await service.play(
                        selection: selectedCustomItems,
                        repeatAll: repeatsQueue,
                        shuffle: shufflesQueue
                    )
                } else {
                    lastErrorMessage = snapshot.statusDetail
                    pendingWorkoutPlayback = true
                    return .failed
                }
                outcome = .rebuiltSelection
            }

            guard playback.isPlaying else {
                pendingWorkoutPlayback = true
                return .failed
            }
            pendingWorkoutPlayback = false
            startedPlaybackForWorkout = true
            shouldResumeWorkoutPlayback = true
            persistWorkoutPlaybackRecoveryState()
            return outcome
        } catch {
            Self.logger.error("Recover workout playback failed. \(self.describe(error), privacy: .public)")
            lastErrorMessage = error.localizedDescription
            playback = await service.refreshPlayback()
            pendingWorkoutPlayback = true
            return .failed
        }
    }

    func togglePlayback() async {
        Self.logger.info("Toggle music playback. currentlyPlaying=\(self.playback.isPlaying)")
        lastErrorMessage = nil
        do {
            if playback.isPlaying {
                playback = await service.pause()
            } else {
                playback = try await service.resume()
            }
            if startedPlaybackForWorkout {
                shouldResumeWorkoutPlayback = playback.isPlaying
                persistWorkoutPlaybackRecoveryState()
            }
        } catch {
            Self.logger.error("Toggle music playback failed. \(self.describe(error), privacy: .public)")
            lastErrorMessage = error.localizedDescription
            playback = await service.refreshPlayback()
        }
    }

    func skipToNext() async {
        Self.logger.info("Skip to next music track.")
        lastErrorMessage = nil
        do {
            playback = try await service.skipToNext()
            if startedPlaybackForWorkout {
                shouldResumeWorkoutPlayback = playback.isPlaying
                persistWorkoutPlaybackRecoveryState()
            }
        } catch {
            Self.logger.error("Skip music track failed. \(self.describe(error), privacy: .public)")
            lastErrorMessage = error.localizedDescription
            playback = await service.refreshPlayback()
        }
    }

    func handleGuideSpeechEvent(_ event: GuideSpeechEvent) async {
        Self.logger.info("Handle guide speech event. event=\(String(describing: event), privacy: .public)")
        playback = await service.handleGuideSpeechEvent(event)
    }

    func retryPendingWorkoutPlaybackIfNeeded() async {
        guard pendingWorkoutPlayback, !isStartingPlayback else { return }
        Self.logger.info("Retry pending workout playback.")
        await beginWorkoutPlaybackIfNeeded()
    }

    func endWorkoutPlaybackIfNeeded() async {
        pendingWorkoutPlayback = false
        guard startedPlaybackForWorkout else {
            clearWorkoutPlaybackRecoveryState()
            return
        }
        clearWorkoutPlaybackRecoveryState()
        playback = await service.stop()
    }

    func performPrimaryAction() async {
        Self.logger.info(
            "Perform music primary action. isConnected=\(self.isConnected) canShowQuickPicks=\(self.canShowQuickPicks) needsPlaybackSetup=\(self.needsPlaybackSetup) action=\(self.primaryActionTitle, privacy: .public)"
        )
        if isConnected {
            await loadQuickPicks()
        } else {
            await connectAppleMusic()
        }
    }

    private func persistSelectedQuickPick() {
        defaults.set(selectedQuickPickID, forKey: selectedQuickPickKey)
    }

    private func persistSelectedCustomItems() {
        defaults.set(try? JSONEncoder().encode(selectedCustomItems), forKey: selectedCustomItemsKey)
    }

    private func persistMusicDisabled() {
        defaults.set(isMusicDisabled, forKey: musicDisabledKey)
    }

    private func persistWorkoutPlaybackRecoveryState() {
        defaults.set(startedPlaybackForWorkout, forKey: workoutPlaybackOwnedKey)
        defaults.set(shouldResumeWorkoutPlayback, forKey: workoutPlaybackShouldResumeKey)
        defaults.set(try? JSONEncoder().encode(activeWorkoutQuickPick), forKey: workoutQuickPickKey)
    }

    private func clearWorkoutPlaybackRecoveryState() {
        startedPlaybackForWorkout = false
        shouldResumeWorkoutPlayback = false
        activeWorkoutQuickPick = nil
        defaults.removeObject(forKey: workoutPlaybackOwnedKey)
        defaults.removeObject(forKey: workoutPlaybackShouldResumeKey)
        defaults.removeObject(forKey: workoutQuickPickKey)
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, from data: Data?) -> Value? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func describe(_ error: Error) -> String {
        let nsError = error as NSError
        var details = [
            "error=\(nsError.domain)(\(nsError.code))",
            "localizedDescription=\(nsError.localizedDescription)"
        ]

        if let failureReason = nsError.localizedFailureReason, !failureReason.isEmpty {
            details.append("failureReason=\(failureReason)")
        }
        if let recoverySuggestion = nsError.localizedRecoverySuggestion, !recoverySuggestion.isEmpty {
            details.append("recoverySuggestion=\(recoverySuggestion)")
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            details.append("underlying=\(underlying.domain)(\(underlying.code)) \(underlying.localizedDescription)")
        }
        if !nsError.userInfo.isEmpty {
            details.append("userInfo=\(String(describing: nsError.userInfo))")
        }

        return details.joined(separator: " | ")
    }
}

enum MusicConnectionState: Equatable {
    case unavailable
    case notConnected
    case connecting
    case connected
    case denied
}

struct MusicConnectionSnapshot: Equatable {
    let providerName: String
    let connectionState: MusicConnectionState
    let statusTitle: String
    let statusDetail: String
    let canPlayCatalogContent: Bool

    func with(connectionState: MusicConnectionState) -> MusicConnectionSnapshot {
        MusicConnectionSnapshot(
            providerName: providerName,
            connectionState: connectionState,
            statusTitle: statusTitle,
            statusDetail: statusDetail,
            canPlayCatalogContent: canPlayCatalogContent
        )
    }
}

struct MusicPlaybackSnapshot: Equatable {
    let title: String
    let subtitle: String
    let isPlaying: Bool
    let hasActiveQueue: Bool

    static let empty = MusicPlaybackSnapshot(
        title: "No music selected",
        subtitle: "Pick a mix before you start.",
        isPlaying: false,
        hasActiveQueue: false
    )
}

struct MusicQuickPick: Identifiable, Codable, Equatable, Hashable {
    enum Kind: String, Codable, Hashable {
        case continueCurrent
        case searchSongs
    }

    let id: String
    let title: String
    let subtitle: String
    let symbolName: String
    let kind: Kind
    let query: String?
}

enum MusicSearchCategory: String, Codable, CaseIterable, Identifiable {
    case songs
    case albums
    case playlists
    var id: String { rawValue }
}

struct MusicSearchResult: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let category: MusicSearchCategory
}

enum WorkoutMusicRecoveryOutcome {
    case alreadyPlaying
    case resumedExistingQueue
    case rebuiltSelection
    case failed
}

@MainActor
protocol MusicService: AnyObject {
    var currentSnapshot: MusicConnectionSnapshot { get }
    var currentPlayback: MusicPlaybackSnapshot { get }

    func refreshSnapshot() async -> MusicConnectionSnapshot
    func connect() async throws -> MusicConnectionSnapshot
    func loadQuickPicks() async throws -> [MusicQuickPick]
    func search(term: String, category: MusicSearchCategory) async throws -> [MusicSearchResult]
    func play(quickPick: MusicQuickPick, repeatAll: Bool, shuffle: Bool) async throws -> MusicPlaybackSnapshot
    func play(selection: [MusicSearchResult], repeatAll: Bool, shuffle: Bool) async throws -> MusicPlaybackSnapshot
    func pause() async -> MusicPlaybackSnapshot
    func stop() async -> MusicPlaybackSnapshot
    func resume() async throws -> MusicPlaybackSnapshot
    func skipToNext() async throws -> MusicPlaybackSnapshot
    func refreshPlayback() async -> MusicPlaybackSnapshot
    func handleGuideSpeechEvent(_ event: GuideSpeechEvent) async -> MusicPlaybackSnapshot
}

enum MusicServiceFactory {
    @MainActor
    static func makeDefault() -> any MusicService {
        if shouldUseMockMusic {
            return MockMusicService()
        }
        return AppleMusicService()
    }

    private static var shouldUseMockMusic: Bool {
        let processInfo = ProcessInfo.processInfo
        return processInfo.arguments.contains("-OutboundUseMockMusic")
            || processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
