import Foundation
import MusicKit
import OSLog

@MainActor
final class AppleMusicService: MusicService {
    private static let logger = Logger(subsystem: "xhstudio.Outbound", category: "AppleMusic")

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
        Self.logger.info(
            "Refresh Apple Music snapshot. authStatus=\(String(describing: status), privacy: .public) canPlayCatalogContent=\(canPlayCatalogContent)"
        )
        return makeSnapshot(status: status, canPlayCatalogContent: canPlayCatalogContent)
    }

    func connect() async throws -> MusicConnectionSnapshot {
        let status = await MusicAuthorization.request()
        let canPlayCatalogContent = await fetchCanPlayCatalogContent(status: status)
        Self.logger.info(
            "Apple Music connect completed. authStatus=\(String(describing: status), privacy: .public) canPlayCatalogContent=\(canPlayCatalogContent)"
        )
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
        Self.logger.info(
            "Attempt Apple Music playback. quickPickID=\(quickPick.id, privacy: .public) kind=\(quickPick.kind.rawValue, privacy: .public)"
        )
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
                Self.logger.error(
                    "Apple Music search returned no songs. quickPickID=\(quickPick.id, privacy: .public) query=\(query, privacy: .public)"
                )
                throw NSError(domain: "OutboundMusic", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Apple Music did not return enough songs for this mix."
                ])
            }
            Self.logger.info(
                "Apple Music search returned songs. quickPickID=\(quickPick.id, privacy: .public) songCount=\(songs.count)"
            )
            queuedSongs = songs
            currentQuickPick = quickPick
            player.queue = ApplicationMusicPlayer.Queue(for: songs)
            try await player.play()
            Self.logger.info(
                "Apple Music player started. quickPickID=\(quickPick.id, privacy: .public) playbackStatus=\(String(describing: self.player.state.playbackStatus), privacy: .public)"
            )
        }

        return playbackSnapshot()
    }

    func pause() async -> MusicPlaybackSnapshot {
        Self.logger.info("Pause Apple Music playback.")
        player.pause()
        return playbackSnapshot()
    }

    func resume() async throws -> MusicPlaybackSnapshot {
        Self.logger.info("Resume Apple Music playback.")
        try await resumeIfPossible()
        return playbackSnapshot()
    }

    func skipToNext() async throws -> MusicPlaybackSnapshot {
        Self.logger.info("Skip Apple Music track.")
        try await player.skipToNextEntry()
        return playbackSnapshot()
    }

    func refreshPlayback() async -> MusicPlaybackSnapshot {
        playbackSnapshot()
    }

    func handleCoachSpeechEvent(_ event: CoachSpeechEvent) async -> MusicPlaybackSnapshot {
        Self.logger.info("Coach speech event received. event=\(String(describing: event), privacy: .public)")
        _ = event
        return playbackSnapshot()
    }

    private func resumeIfPossible() async throws {
        if queuedSongs != nil || currentQuickPick != nil {
            Self.logger.info("Resume existing Apple Music queue.")
            try await player.play()
            return
        }

        do {
            let fallbackSongs = try await loadSongs(for: "upbeat pop dance workout")
            guard !fallbackSongs.isEmpty else {
                Self.logger.error("Fallback Apple Music search returned no songs.")
                throw NSError(domain: "OutboundMusic", code: 3, userInfo: [
                    NSLocalizedDescriptionKey: "Connect Apple Music and pick a mix before starting playback."
                ])
            }
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
            Self.logger.info("Started fallback Apple Music queue.")
            return
        } catch {
            Self.logger.error("Fallback Apple Music playback failed. \(self.describe(error), privacy: .public)")
        }

        throw NSError(domain: "OutboundMusic", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "Connect Apple Music and pick a mix before starting playback."
        ])
    }

    private func loadSongs(for query: String) async throws -> MusicItemCollection<Song> {
        var request = MusicCatalogSearchRequest(term: query, types: [Song.self])
        request.limit = 20
        do {
            let response = try await request.response()
            return response.songs
        } catch {
            Self.logger.error("Apple Music search failed. query=\(query, privacy: .public) \(self.describe(error), privacy: .public)")
            throw userFacingError(from: error, fallbackMessage: "Apple Music could not load tracks for this mix.")
        }
    }

    private func fetchCanPlayCatalogContent(status: MusicAuthorization.Status) async -> Bool {
        guard status == .authorized else { return false }
        do {
            let subscription = try await MusicSubscription.current
            Self.logger.info(
                "Fetched Apple Music subscription. canPlayCatalogContent=\(subscription.canPlayCatalogContent)"
            )
            return subscription.canPlayCatalogContent
        } catch {
            Self.logger.error("Failed to fetch Apple Music subscription. \(self.describe(error), privacy: .public)")
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
                    : "Apple Music permission is granted, but catalog playback is unavailable. Check that this device has Apple Music playback access and that MusicKit is enabled for Outbound's App ID.",
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

    private func describe(_ error: Error) -> String {
        let nsError = error as NSError
        var details = [
            "error=\(nsError.domain)(\(nsError.code))",
            "localizedDescription=\(nsError.localizedDescription)"
        ]

        if !nsError.localizedFailureReason.isNilOrEmpty {
            details.append("failureReason=\(nsError.localizedFailureReason!)")
        }
        if !nsError.localizedRecoverySuggestion.isNilOrEmpty {
            details.append("recoverySuggestion=\(nsError.localizedRecoverySuggestion!)")
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            details.append("underlying=\(underlying.domain)(\(underlying.code)) \(underlying.localizedDescription)")
        }
        if !nsError.userInfo.isEmpty {
            details.append("userInfo=\(String(describing: nsError.userInfo))")
        }

        return details.joined(separator: " | ")
    }

    private func userFacingError(from error: Error, fallbackMessage: String) -> NSError {
        let nsError = error as NSError
        let normalizedDescription = nsError.localizedDescription.lowercased()
        let normalizedFailureReason = (nsError.localizedFailureReason ?? "").lowercased()
        let combined = normalizedDescription + " " + normalizedFailureReason

        if combined.contains("developer token") {
            return NSError(domain: "OutboundMusic", code: 101, userInfo: [
                NSLocalizedDescriptionKey: "Apple Music setup is incomplete. Outbound could not get a MusicKit developer token. Enable MusicKit for Outbound's App ID in the Apple Developer portal, then reinstall or relaunch the app."
            ])
        }

        if combined.contains("subscription") || combined.contains("can play catalog content") {
            return NSError(domain: "OutboundMusic", code: 102, userInfo: [
                NSLocalizedDescriptionKey: "Apple Music playback is unavailable for this account. Confirm the device is signed into an active Apple Music subscription."
            ])
        }

        return NSError(domain: "OutboundMusic", code: 100, userInfo: [
            NSLocalizedDescriptionKey: fallbackMessage,
            NSUnderlyingErrorKey: nsError
        ])
    }
}

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        switch self {
        case .none:
            return true
        case .some(let value):
            return value.isEmpty
        }
    }
}
