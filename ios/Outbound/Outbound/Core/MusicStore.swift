import Combine
import Foundation

@MainActor
final class MusicStore: ObservableObject {
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
        isConnected && snapshot.canPlayCatalogContent
    }

    var selectedQuickPick: MusicQuickPick? {
        quickPicks.first(where: { $0.id == selectedQuickPickID })
    }

    var musicSummaryLine: String {
        if playback.isPlaying {
            return "\(playback.title) • \(playback.subtitle)"
        }
        if let selectedQuickPick {
            return "Queued: \(selectedQuickPick.title)"
        }
        if isConnected {
            return "Pick a mix for this run."
        }
        return snapshot.statusDetail
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        snapshot = await service.refreshSnapshot()
        playback = await service.refreshPlayback()
        if canShowQuickPicks {
            await loadQuickPicks()
        } else {
            quickPicks = []
        }
    }

    func connectAppleMusic() async {
        lastErrorMessage = nil
        snapshot = snapshot.with(connectionState: .connecting)
        do {
            snapshot = try await service.connect()
            playback = await service.refreshPlayback()
            if canShowQuickPicks {
                await loadQuickPicks()
            }
        } catch {
            snapshot = await service.refreshSnapshot()
            lastErrorMessage = error.localizedDescription
        }
    }

    func loadQuickPicks() async {
        guard canShowQuickPicks else { return }
        isLoadingQuickPicks = true
        defer { isLoadingQuickPicks = false }

        do {
            quickPicks = try await service.loadQuickPicks()
            if selectedQuickPick == nil {
                selectedQuickPickID = quickPicks.first?.id
            }
            persistSelectedQuickPick()
        } catch {
            lastErrorMessage = error.localizedDescription
            quickPicks = []
        }
    }

    func selectQuickPick(_ quickPick: MusicQuickPick) {
        selectedQuickPickID = quickPick.id
        persistSelectedQuickPick()
    }

    func beginWorkoutPlaybackIfNeeded() async {
        guard canShowQuickPicks, let selectedQuickPick else { return }
        isStartingPlayback = true
        defer { isStartingPlayback = false }
        lastErrorMessage = nil

        do {
            playback = try await service.play(quickPick: selectedQuickPick)
        } catch {
            lastErrorMessage = error.localizedDescription
            playback = await service.refreshPlayback()
        }
    }

    func togglePlayback() async {
        lastErrorMessage = nil
        do {
            if playback.isPlaying {
                playback = await service.pause()
            } else {
                playback = try await service.resume()
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            playback = await service.refreshPlayback()
        }
    }

    func skipToNext() async {
        lastErrorMessage = nil
        do {
            playback = try await service.skipToNext()
        } catch {
            lastErrorMessage = error.localizedDescription
            playback = await service.refreshPlayback()
        }
    }

    func handleCoachSpeechEvent(_ event: CoachSpeechEvent) async {
        playback = await service.handleCoachSpeechEvent(event)
    }

    private func persistSelectedQuickPick() {
        defaults.set(selectedQuickPickID, forKey: selectedQuickPickKey)
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
