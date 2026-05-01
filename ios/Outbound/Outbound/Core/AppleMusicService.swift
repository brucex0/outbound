import Foundation
import MusicKit

@MainActor
final class AppleMusicService: MusicService {
    private let player = ApplicationMusicPlayer.shared
    private var currentQuickPick: MusicQuickPick?
    private var queuedSongs: MusicItemCollection<Song>?

    var currentSnapshot: MusicConnectionSnapshot {
        makeSnapshot(
            status: MusicAuthorization.currentStatus,
            canPlayCatalogContent: false
        )
    }

    var currentPlayback: MusicPlaybackSnapshot {
        playbackSnapshot()
    }

    func refreshSnapshot() async -> MusicConnectionSnapshot {
        let status = MusicAuthorization.currentStatus
        let canPlayCatalogContent = await fetchCanPlayCatalogContent(status: status)
        return makeSnapshot(status: status, canPlayCatalogContent: canPlayCatalogContent)
    }

    func connect() async throws -> MusicConnectionSnapshot {
        let status = await MusicAuthorization.request()
        let canPlayCatalogContent = await fetchCanPlayCatalogContent(status: status)
        return makeSnapshot(status: status, canPlayCatalogContent: canPlayCatalogContent)
    }

    func loadQuickPicks() async throws -> [MusicQuickPick] {
        var picks: [MusicQuickPick] = []
        if queuedSongs != nil || currentQuickPick != nil {
            picks.append(
                MusicQuickPick(
                    id: "continue-current",
                    title: "Continue last mix",
                    subtitle: "Resume your last Outbound queue.",
                    symbolName: "play.circle.fill",
                    kind: .continueCurrent,
                    query: nil
                )
            )
        }

        picks.append(contentsOf: [
            MusicQuickPick(
                id: "outbound-upbeat",
                title: "Upbeat run mix",
                subtitle: "Fast pop and dance energy.",
                symbolName: "bolt.fill",
                kind: .searchSongs,
                query: "upbeat pop dance workout"
            ),
            MusicQuickPick(
                id: "outbound-electronic",
                title: "Electronic stride",
                subtitle: "Steady BPM for focused miles.",
                symbolName: "waveform.path.ecg",
                kind: .searchSongs,
                query: "electronic cardio running"
            ),
            MusicQuickPick(
                id: "outbound-recovery",
                title: "Easy day flow",
                subtitle: "Calmer tracks for recovery runs.",
                symbolName: "figure.walk.motion",
                kind: .searchSongs,
                query: "indie chill jogging"
            )
        ])

        return picks
    }

    func play(quickPick: MusicQuickPick) async throws -> MusicPlaybackSnapshot {
        switch quickPick.kind {
        case .continueCurrent:
            try await resumeIfPossible()
        case .searchSongs:
            guard let query = quickPick.query else {
                throw NSError(domain: "OutboundMusic", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "This Apple Music mix is missing its search query."
                ])
            }
            let songs = try await loadSongs(for: query)
            guard !songs.isEmpty else {
                throw NSError(domain: "OutboundMusic", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Apple Music did not return enough songs for this mix."
                ])
            }
            queuedSongs = songs
            currentQuickPick = quickPick
            player.queue = ApplicationMusicPlayer.Queue(for: songs)
            try await player.play()
        }

        return playbackSnapshot()
    }

    func pause() async -> MusicPlaybackSnapshot {
        player.pause()
        return playbackSnapshot()
    }

    func resume() async throws -> MusicPlaybackSnapshot {
        try await resumeIfPossible()
        return playbackSnapshot()
    }

    func skipToNext() async throws -> MusicPlaybackSnapshot {
        try await player.skipToNextEntry()
        return playbackSnapshot()
    }

    func refreshPlayback() async -> MusicPlaybackSnapshot {
        playbackSnapshot()
    }

    func handleCoachSpeechEvent(_ event: CoachSpeechEvent) async -> MusicPlaybackSnapshot {
        _ = event
        return playbackSnapshot()
    }

    private func resumeIfPossible() async throws {
        if queuedSongs != nil || currentQuickPick != nil {
            try await player.play()
            return
        }

        if let fallbackSongs = try? await loadSongs(for: "upbeat pop dance workout"), !fallbackSongs.isEmpty {
            queuedSongs = fallbackSongs
            currentQuickPick = MusicQuickPick(
                id: "outbound-upbeat",
                title: "Upbeat run mix",
                subtitle: "Fast pop and dance energy.",
                symbolName: "bolt.fill",
                kind: .searchSongs,
                query: "upbeat pop dance workout"
            )
            player.queue = ApplicationMusicPlayer.Queue(for: fallbackSongs)
            try await player.play()
            return
        }

        throw NSError(domain: "OutboundMusic", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "Connect Apple Music and pick a mix before starting playback."
        ])
    }

    private func loadSongs(for query: String) async throws -> MusicItemCollection<Song> {
        var request = MusicCatalogSearchRequest(term: query, types: [Song.self])
        request.limit = 20
        let response = try await request.response()
        return response.songs
    }

    private func fetchCanPlayCatalogContent(status: MusicAuthorization.Status) async -> Bool {
        guard status == .authorized else { return false }
        do {
            let subscription = try await MusicSubscription.current
            return subscription.canPlayCatalogContent
        } catch {
            return false
        }
    }

    private func makeSnapshot(
        status: MusicAuthorization.Status,
        canPlayCatalogContent: Bool
    ) -> MusicConnectionSnapshot {
        switch status {
        case .authorized:
            return MusicConnectionSnapshot(
                providerName: "Apple Music",
                connectionState: .connected,
                statusTitle: canPlayCatalogContent ? "Connected" : "Connected, playback unavailable",
                statusDetail: canPlayCatalogContent
                    ? "Play Apple Music mixes during workouts and control them inside Outbound."
                    : "Apple Music access is granted, but this account cannot play catalog content right now.",
                canPlayCatalogContent: canPlayCatalogContent
            )
        case .denied:
            return MusicConnectionSnapshot(
                providerName: "Apple Music",
                connectionState: .denied,
                statusTitle: "Access denied",
                statusDetail: "Allow Apple Music access in Settings to choose a run mix inside Outbound.",
                canPlayCatalogContent: false
            )
        case .notDetermined:
            return MusicConnectionSnapshot(
                providerName: "Apple Music",
                connectionState: .notConnected,
                statusTitle: "Not connected",
                statusDetail: "Connect Apple Music to bring workout mixes and playback controls into your run.",
                canPlayCatalogContent: false
            )
        case .restricted:
            return MusicConnectionSnapshot(
                providerName: "Apple Music",
                connectionState: .unavailable,
                statusTitle: "Unavailable",
                statusDetail: "Apple Music is restricted on this device.",
                canPlayCatalogContent: false
            )
        @unknown default:
            return MusicConnectionSnapshot(
                providerName: "Apple Music",
                connectionState: .unavailable,
                statusTitle: "Unavailable",
                statusDetail: "Apple Music could not be initialized on this device.",
                canPlayCatalogContent: false
            )
        }
    }

    private func playbackSnapshot() -> MusicPlaybackSnapshot {
        let isPlaying = player.state.playbackStatus == .playing
        if let song = player.queue.currentEntry?.item as? Song {
            return MusicPlaybackSnapshot(
                title: song.title,
                subtitle: song.artistName,
                isPlaying: isPlaying,
                hasActiveQueue: true
            )
        }
        if let currentQuickPick {
            return MusicPlaybackSnapshot(
                title: currentQuickPick.title,
                subtitle: currentQuickPick.subtitle,
                isPlaying: isPlaying,
                hasActiveQueue: queuedSongs != nil
            )
        }
        return .empty
    }
}
