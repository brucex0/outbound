import Foundation

@MainActor
final class MockMusicService: MusicService {
    private var isConnected = false
    private var currentIndex = 0
    private var currentQuickPick: MusicQuickPick?
    private var isPlaying = false
    private var shouldResumeAfterCoachSpeech = false

    private let quickPickFixtures: [MusicQuickPick] = [
        MusicQuickPick(
            id: "mock-upbeat",
            title: "Mock upbeat run mix",
            subtitle: "UI test friendly energy.",
            symbolName: "bolt.fill",
            kind: .searchSongs,
            query: "mock upbeat"
        ),
        MusicQuickPick(
            id: "mock-focus",
            title: "Mock focus stride",
            subtitle: "Steady background rhythm.",
            symbolName: "waveform.path.ecg",
            kind: .searchSongs,
            query: "mock focus"
        ),
        MusicQuickPick(
            id: "mock-recovery",
            title: "Mock easy day flow",
            subtitle: "Low-key recovery miles.",
            symbolName: "figure.walk.motion",
            kind: .searchSongs,
            query: "mock recovery"
        )
    ]

    var currentSnapshot: MusicConnectionSnapshot {
        snapshot()
    }

    var currentPlayback: MusicPlaybackSnapshot {
        playback()
    }

    func refreshSnapshot() async -> MusicConnectionSnapshot {
        snapshot()
    }

    func connect() async throws -> MusicConnectionSnapshot {
        isConnected = true
        return snapshot()
    }

    func loadQuickPicks() async throws -> [MusicQuickPick] {
        var picks = quickPickFixtures
        if currentQuickPick != nil {
            picks.insert(
                MusicQuickPick(
                    id: "continue-current",
                    title: "Continue last mix",
                    subtitle: "Resume the last mock workout queue.",
                    symbolName: "play.circle.fill",
                    kind: .continueCurrent,
                    query: nil
                ),
                at: 0
            )
        }
        return picks
    }

    func play(quickPick: MusicQuickPick) async throws -> MusicPlaybackSnapshot {
        if quickPick.kind == .continueCurrent, currentQuickPick == nil {
            currentQuickPick = quickPickFixtures.first
        } else if quickPick.kind != .continueCurrent {
            currentQuickPick = quickPick
            currentIndex = 0
        }
        isPlaying = true
        return playback()
    }

    func pause() async -> MusicPlaybackSnapshot {
        isPlaying = false
        return playback()
    }

    func resume() async throws -> MusicPlaybackSnapshot {
        if currentQuickPick == nil {
            currentQuickPick = quickPickFixtures.first
            currentIndex = 0
        }
        isPlaying = true
        return playback()
    }

    func skipToNext() async throws -> MusicPlaybackSnapshot {
        guard currentQuickPick != nil else {
            currentQuickPick = quickPickFixtures.first
            currentIndex = 0
            isPlaying = true
            return playback()
        }
        currentIndex = (currentIndex + 1) % mockTrackTitles.count
        isPlaying = true
        return playback()
    }

    func refreshPlayback() async -> MusicPlaybackSnapshot {
        playback()
    }

    func handleCoachSpeechEvent(_ event: CoachSpeechEvent) async -> MusicPlaybackSnapshot {
        switch event {
        case .didStart:
            shouldResumeAfterCoachSpeech = isPlaying
            if shouldResumeAfterCoachSpeech {
                isPlaying = false
            }
        case .didFinish:
            if shouldResumeAfterCoachSpeech {
                isPlaying = true
                shouldResumeAfterCoachSpeech = false
            }
        }
        return playback()
    }

    private func snapshot() -> MusicConnectionSnapshot {
        MusicConnectionSnapshot(
            providerName: "Apple Music",
            connectionState: isConnected ? .connected : .notConnected,
            statusTitle: isConnected ? "Connected" : "Not connected",
            statusDetail: isConnected
                ? "Mock music is active for simulator and UI tests."
                : "Connect Apple Music to bring workout mixes and playback controls into your run.",
            canPlayCatalogContent: isConnected
        )
    }

    private func playback() -> MusicPlaybackSnapshot {
        guard let currentQuickPick else { return .empty }
        return MusicPlaybackSnapshot(
            title: mockTrackTitles[currentIndex],
            subtitle: currentQuickPick.title,
            isPlaying: isPlaying,
            hasActiveQueue: true
        )
    }

    private var mockTrackTitles: [String] {
        [
            "Warm Up Forward",
            "Cadence Locked In",
            "Last Mile Lift"
        ]
    }
}
