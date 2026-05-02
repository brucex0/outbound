import Combine
import Foundation
import OSLog

@MainActor
final class MusicStore: ObservableObject {
    private static let logger = Logger(subsystem: "xhstudio.Outbound", category: "MusicStore")

    @Published private(set) var snapshot: MusicConnectionSnapshot
    @Published private(set) var quickPicks: [MusicQuickPick] = []
    @Published private(set) var playback: MusicPlaybackSnapshot
    @Published var selectedQuickPickID: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isLoadingQuickPicks = false
    @Published private(set) var isStartingPlayback = false
    @Published private(set) var lastErrorMessage: String?

    private let service: any MusicService
    private let defaults: UserDefaults
    private let selectedQuickPickKey = "music_selected_quick_pick_v1"
    private var pendingWorkoutPlayback = false

    init(
        service: (any MusicService)? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.service = service ?? MusicServiceFactory.makeDefault()
        self.defaults = defaults
        snapshot = self.service.currentSnapshot
        playback = self.service.currentPlayback
        selectedQuickPickID = defaults.string(forKey: selectedQuickPickKey)
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
        return "If you're testing on a real device, make sure the device is signed into an active Apple Music subscription and that MusicKit is enabled for Outbound's App ID in the Apple Developer portal."
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
            if selectedQuickPick == nil {
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
        persistSelectedQuickPick()
    }

    func beginWorkoutPlaybackIfNeeded() async {
        guard isConnected, let selectedQuickPick else { return }
        Self.logger.info("Begin workout playback. quickPickID=\(selectedQuickPick.id, privacy: .public)")
        pendingWorkoutPlayback = true
        isStartingPlayback = true
        defer { isStartingPlayback = false }
        lastErrorMessage = nil

        do {
            playback = try await service.play(quickPick: selectedQuickPick)
            pendingWorkoutPlayback = !playback.hasActiveQueue
        } catch {
            Self.logger.error("Begin workout playback failed. \(self.describe(error), privacy: .public)")
            lastErrorMessage = error.localizedDescription
            playback = await service.refreshPlayback()
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
        } catch {
            Self.logger.error("Skip music track failed. \(self.describe(error), privacy: .public)")
            lastErrorMessage = error.localizedDescription
            playback = await service.refreshPlayback()
        }
    }

    func handleCoachSpeechEvent(_ event: CoachSpeechEvent) async {
        Self.logger.info("Handle coach speech event. event=\(String(describing: event), privacy: .public)")
        playback = await service.handleCoachSpeechEvent(event)
    }

    func retryPendingWorkoutPlaybackIfNeeded() async {
        guard pendingWorkoutPlayback, !isStartingPlayback else { return }
        Self.logger.info("Retry pending workout playback.")
        await beginWorkoutPlaybackIfNeeded()
    }

    func clearPendingWorkoutPlayback() {
        pendingWorkoutPlayback = false
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

struct MusicQuickPick: Identifiable, Equatable, Hashable {
    enum Kind: String, Hashable {
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

enum CoachSpeechEvent {
    case didStart
    case didFinish
}

@MainActor
protocol MusicService: AnyObject {
    var currentSnapshot: MusicConnectionSnapshot { get }
    var currentPlayback: MusicPlaybackSnapshot { get }

    func refreshSnapshot() async -> MusicConnectionSnapshot
    func connect() async throws -> MusicConnectionSnapshot
    func loadQuickPicks() async throws -> [MusicQuickPick]
    func play(quickPick: MusicQuickPick) async throws -> MusicPlaybackSnapshot
    func pause() async -> MusicPlaybackSnapshot
    func resume() async throws -> MusicPlaybackSnapshot
    func skipToNext() async throws -> MusicPlaybackSnapshot
    func refreshPlayback() async -> MusicPlaybackSnapshot
    func handleCoachSpeechEvent(_ event: CoachSpeechEvent) async -> MusicPlaybackSnapshot
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
