//
//  OutboundTests.swift
//  OutboundTests
//
//  Created by Zhi Feng Xia on 4/26/26.
//

import Testing
import Foundation
@testable import Outbound

struct OutboundTests {

    @Test func appBundleRegistersFirebasePhoneAuthCallbackScheme() throws {
        let infoDictionary = try #require(Bundle.main.infoDictionary)
        let urlTypes = try #require(infoDictionary["CFBundleURLTypes"] as? [[String: Any]])
        let urlSchemes = urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }

        #expect(urlSchemes.contains("app-1-186140050970-ios-e8305464ba7fbb30a033a3"))
    }

    @Test func firebaseConfigMatchesOutboundAppWhenPresent() throws {
        guard let configURL = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") else {
            return
        }

        let configData = try Data(contentsOf: configURL)
        let config = try #require(
            PropertyListSerialization.propertyList(from: configData, format: nil) as? [String: Any]
        )

        #expect(config["GOOGLE_APP_ID"] as? String == "1:186140050970:ios:e8305464ba7fbb30a033a3")
        #expect(config["PROJECT_ID"] as? String == "outbound-494602")
        #expect(config["BUNDLE_ID"] as? String == "xhstudio.Outbound")
    }

    @Test func appBundleDeclaresAppleMusicUsageDescription() throws {
        let infoDictionary = try #require(Bundle.main.infoDictionary)
        let usageDescription = try #require(infoDictionary["NSAppleMusicUsageDescription"] as? String)

        #expect(!usageDescription.isEmpty)
    }

    @MainActor
    @Test func musicStoreShowsRefreshActionWhenAuthorizedButPlaybackUnavailable() async throws {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let store = MusicStore(
            service: StubMusicService(
                snapshot: MusicConnectionSnapshot(
                    providerName: "Apple Music",
                    connectionState: .connected,
                    statusTitle: "Connected, playback unavailable",
                    statusDetail: "Apple Music permission is granted, but catalog playback is unavailable.",
                    canPlayCatalogContent: false
                )
            ),
            defaults: defaults
        )

        #expect(store.needsPlaybackSetup)
        #expect(store.primaryActionTitle == "Refresh Apple Music access")
        #expect(store.musicSummaryLine == "Apple Music permission is granted, but catalog playback is unavailable.")
        #expect(store.troubleshootingLine != nil)
    }

    @MainActor
    @Test func musicStoreShowsLoadMixesActionWhenConnectedAndPlayable() async throws {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let store = MusicStore(
            service: StubMusicService(
                snapshot: MusicConnectionSnapshot(
                    providerName: "Apple Music",
                    connectionState: .connected,
                    statusTitle: "Connected",
                    statusDetail: "Ready",
                    canPlayCatalogContent: true
                )
            ),
            defaults: defaults
        )

        #expect(store.primaryActionTitle == "Load workout mixes")
        #expect(store.troubleshootingLine == nil)
    }

}

@MainActor
private final class StubMusicService: MusicService {
    var currentSnapshot: MusicConnectionSnapshot
    var currentPlayback: MusicPlaybackSnapshot = .empty

    init(snapshot: MusicConnectionSnapshot) {
        currentSnapshot = snapshot
    }

    func refreshSnapshot() async -> MusicConnectionSnapshot { currentSnapshot }
    func connect() async throws -> MusicConnectionSnapshot { currentSnapshot }
    func loadQuickPicks() async throws -> [MusicQuickPick] { [] }
    func play(quickPick: MusicQuickPick) async throws -> MusicPlaybackSnapshot { currentPlayback }
    func pause() async -> MusicPlaybackSnapshot { currentPlayback }
    func resume() async throws -> MusicPlaybackSnapshot { currentPlayback }
    func skipToNext() async throws -> MusicPlaybackSnapshot { currentPlayback }
    func refreshPlayback() async -> MusicPlaybackSnapshot { currentPlayback }
    func handleCoachSpeechEvent(_ event: CoachSpeechEvent) async -> MusicPlaybackSnapshot { currentPlayback }
}
