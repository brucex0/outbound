import Combine
import CoreLocation
import CryptoKit
import Foundation
import Testing
@testable import Outbound

@MainActor
@Suite(.serialized)
struct SpeedWarningPipelineTests {
    @Test(arguments: [1, -1])
    func qualifyingChangesReachReviewedAudioWithoutProfileOrTarget(direction: Int) {
        let fixture = WarningFixture()
        defer { fixture.guide.deactivate() }
        fixture.feed(0...40, direction: direction)
        #expect(fixture.speedEvents == ["\(direction > 0 ? "increase" : "decrease"):detected",
                                       "\(direction > 0 ? "increase" : "decrease"):spoken"])
        let key = direction > 0 ? "coach.settle" : "coach.restore_rhythm"
        #expect(fixture.pack.requests.map(\.key) == [key])
        #expect(fixture.player.played == [Data(key.utf8)])
        #expect(fixture.pack.requests.first?.transcript == nil)
        #expect(!fixture.guide.lastNudge.isEmpty)
        #expect(fixture.provider.analysisCount == 0)
        #expect(!fixture.guide.isAnalyzing)
    }

    @Test func busyAudioDelaysWarningUntilPlayerBecomesFree() {
        let fixture = WarningFixture()
        defer { fixture.guide.deactivate() }
        fixture.player.isSpeaking = true
        fixture.feed(0...40)
        #expect(fixture.speedEvents == ["increase:detected"])
        #expect(fixture.player.played.isEmpty)
        fixture.player.isSpeaking = false
        fixture.feed(41...41)
        #expect(fixture.speedEvents == ["increase:detected", "increase:spoken"])
        #expect(fixture.player.played == [Data("coach.settle".utf8)])
    }

    @Test func warningExpiresWhileAudioIsBusy() {
        let fixture = WarningFixture()
        defer { fixture.guide.deactivate() }
        fixture.player.isSpeaking = true
        fixture.feed(0...49)
        fixture.player.isSpeaking = false
        fixture.feed(50...55)
        #expect(fixture.speedEvents == ["increase:detected"])
        #expect(fixture.pack.requests.isEmpty)
        #expect(fixture.player.played.isEmpty)
    }

    @Test func losingReliableEvidenceDropsQueuedWarning() {
        let fixture = WarningFixture()
        defer { fixture.guide.deactivate() }
        fixture.player.isSpeaking = true
        fixture.feed(0...38)
        fixture.player.isSpeaking = false
        var snapshot = warningSnapshot(second: 39, speed: 4.5)
        snapshot.paceEvidenceTimestamp = nil
        fixture.guide.ingest(snapshot)
        fixture.feed(40...45)
        #expect(fixture.speedEvents == ["increase:detected"])
        #expect(fixture.player.played.isEmpty)
    }

    @Test func missingClipReportsUnavailableWithoutClaimingSpeechOrRetrying() {
        let fixture = WarningFixture()
        defer { fixture.guide.deactivate() }
        fixture.pack.hasClip = false
        fixture.feed(0...40)
        #expect(fixture.speedEvents == ["increase:detected", "increase:audio_unavailable"])
        #expect(fixture.player.played.isEmpty)
        #expect(fixture.guide.lastNudge.isEmpty)
        fixture.pack.hasClip = true
        fixture.feed(41...50)
        #expect(fixture.pack.requests.count == 1)
        #expect(fixture.player.played.isEmpty)
    }

    @Test func playbackFailureReportsUnavailable() {
        let fixture = WarningFixture()
        defer { fixture.guide.deactivate() }
        fixture.player.acceptsPlayback = false
        fixture.feed(0...40)
        #expect(fixture.speedEvents == ["increase:detected", "increase:audio_unavailable"])
        #expect(fixture.player.played.count == 1)
        #expect(fixture.guide.lastNudge.isEmpty)
    }

    @Test(arguments: [CoachingContract.responsive, .coachMe, .quiet])
    func coachingContractControlsIndependentWarning(contract: CoachingContract) {
        let fixture = WarningFixture(contract: contract)
        defer { fixture.guide.deactivate() }
        fixture.feed(0...40)
        #expect(fixture.player.played.count == (contract == .quiet ? 0 : 1))
        #expect(fixture.speedEvents.count == (contract == .quiet ? 0 : 2))
    }

    @Test(arguments: [SportType.walk, .bike])
    func nonRunningSessionsDoNotRequestSpeedCoaching(sport: SportType) {
        let fixture = WarningFixture(sport: sport)
        defer { fixture.guide.deactivate() }
        fixture.feed(0...40)
        #expect(fixture.speedEvents.isEmpty)
        #expect(fixture.player.played.isEmpty)
    }

    @Test func actualSimulationPublishesMatchingSpeedAndEvidenceAndDeliversWarning() throws {
        let fixture = WarningFixture()
        let locationManager = LocationManager()
        let recorder = ActivityRecorder(locationManager: locationManager)
        let route = PreparedRoute(id: "speed-warning-fixture", name: "Synthetic straight route",
            points: [RouteCoordinate(latitude: 0, longitude: 0),
                     RouteCoordinate(latitude: 0, longitude: 0.1)], source: .imported)
        recorder.startRunSimulation(routeGuidance: ActiveRouteGuidanceJournal(route: route, recoverySeed: nil),
                                    route: route, speedKilometersPerHour: 10)
        defer {
            fixture.guide.deactivate()
            _ = recorder.finish()
            ActiveSessionJournal.clear(reason: .discarded)
        }
        var snapshots: [ActiveSessionSnapshot] = []
        let subscription = recorder.$liveSnapshot.sink { snapshot in
            snapshots.append(snapshot)
            fixture.guide.ingest(snapshot)
        }
        defer { subscription.cancel() }
        // Simulated session seconds advance synchronously, with no wall-clock sleep.
        recorder.advanceRunSimulation(by: 45)
        #expect(fixture.speedEvents.isEmpty)
        recorder.adjustRunSimulationSpeed(byKilometersPerHour: 6)
        recorder.advanceRunSimulation(by: 1)
        let changed = try #require(snapshots.last)
        #expect(changed.elapsedSeconds == 46)
        #expect(try #require(changed.location?.speedMetersPerSecond) == 16 / 3.6)
        #expect(changed.paceEvidenceTimestamp == changed.startedAt?.addingTimeInterval(46))
        recorder.advanceRunSimulation(by: 12)
        #expect(fixture.speedEvents == ["increase:detected", "increase:spoken"])
        #expect(fixture.player.played == [Data("coach.settle".utf8)])
    }

    @Test(arguments: ["en", "es", "zh-Hans"], ["plainstride_warm_1", "plainstride_clear_1"])
    func publishedScriptsPlayThroughRealPackWithoutWeakeningSentenceMatching(locale: String, voice: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scripts = recordedSpeedWarningScripts(locale: locale)
        let audio = try writeRecordedSpeedWarningCache(directory: directory, scripts: scripts, voice: voice, locale: locale)
        let pack = GuideAudioPackStore(cacheDirectory: directory, localeIdentifier: { locale })
        pack.select(coachPersonaID: "plainstride_supportive_v1", voiceProfileID: voice, scriptStyleID: "standard")
        await pack.preloadSelectedAudio()
        for direction in [1, -1] {
            let key = direction > 0 ? "coach.settle" : "coach.restore_rhythm"
            // The on-phone published script differs from the app's proposed sentence.
            // Generic sentence fallback must still reject a mismatched transcript.
            #expect(pack.localAudioData(for: key, transcript: "Unrelated unreviewed sentence.") == nil)
            let proposedSentence = direction > 0
                ? String(localized: "live_guidance.sudden_speed_increase", defaultValue: "Slow down until you can speak a full sentence.")
                : String(localized: "live_guidance.sudden_speed_decrease", defaultValue: "Keep the effort easy; there is no need to make up lost time.")
            #expect(pack.localAudioData(for: key, transcript: proposedSentence) == nil)
            let fixture = WarningFixture(audioPack: pack)
            fixture.feed(0...40, direction: direction)
            #expect(fixture.speedEvents.last == "\(direction > 0 ? "increase" : "decrease"):spoken")
            #expect(fixture.player.played == [audio])
            #expect(fixture.guide.lastNudge == scripts[key])
            #expect(fixture.guide.lastSpokenAnnouncement == scripts[key])
            fixture.guide.deactivate()
        }
    }

    @Test(arguments: [1, 10])
    func sevenToTwentyKilometersPerHourUsesPublishedClipInSimulation(rate: Int) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scripts = recordedSpeedWarningScripts(locale: "en")
        let audio = try writeRecordedSpeedWarningCache(directory: directory, scripts: scripts,
                                                       voice: "plainstride_clear_1", locale: "en")
        let pack = GuideAudioPackStore(cacheDirectory: directory, localeIdentifier: { "en" })
        pack.select(coachPersonaID: "plainstride_supportive_v1", voiceProfileID: "plainstride_clear_1", scriptStyleID: "standard")
        await pack.preloadSelectedAudio()
        let fixture = WarningFixture(audioPack: pack)
        let recorder = ActivityRecorder(locationManager: LocationManager())
        let route = HarvestHalfMarathonSimulation.route
        recorder.startRunSimulation(routeGuidance: .init(route: route, recoverySeed: nil),
                                    route: route, speedKilometersPerHour: 7)
        defer {
            fixture.guide.deactivate()
            _ = recorder.finish()
            ActiveSessionJournal.clear(reason: .discarded)
        }
        let subscription = recorder.$liveSnapshot.sink { fixture.guide.ingest($0) }
        defer { subscription.cancel() }
        recorder.advanceRunSimulation(by: 45)
        // The actual plus button adds 1 km/h. Thirteen taps over four wall-clock
        // seconds must exercise the same ramp at both simulation clock rates.
        for tap in 1...13 {
            recorder.adjustRunSimulationSpeed(byKilometersPerHour: 1)
            let seconds = tap * 4 * rate / 13 - (tap - 1) * 4 * rate / 13
            if seconds > 0 { recorder.advanceRunSimulation(by: seconds) }
        }
        // Stay before the independent cadence-pacer opportunity at 90 seconds.
        recorder.advanceRunSimulation(by: max(0, 60 - recorder.elapsedSeconds))
        #expect(fixture.speedEvents.contains("increase:spoken"))
        #expect(fixture.player.played.contains(audio))
        #expect(fixture.guide.lastNudge == scripts["coach.settle"])
    }
}

@MainActor
private final class WarningFixture {
    let player = WarningAudioPlayer()
    let pack = WarningAudioPack()
    let provider = WarningAnalysisProvider()
    let guide: VirtualGuide
    var speedEvents: [String] = []

    init(contract: CoachingContract = .responsive, sport: SportType = .run,
         audioPack: (any GuideAudioPackProviding)? = nil) {
        guide = VirtualGuide(provider: provider, audioPlayer: player, audioPack: audioPack ?? pack)
        guide.guidanceEventHandler = { [weak self] event in
            if case let .speedChange(direction, result) = event {
                self?.speedEvents.append("\(direction):\(result)")
            }
        }
        let template = GuideTemplate.fixtures[0]
        let persona = GuidePersona(template: template, voice: template.defaultVoice,
            intensity: .balanced, nudgeFrequency: .normal, coachingContract: contract)
        let intent = SessionIntent(id: "speed-warning-fixture", sport: sport, title: "",
            detail: "", guideLine: "", startLabel: "")
        guide.activate(with: nil, persona: persona, sessionIntent: intent)
    }

    func feed(_ seconds: ClosedRange<Int>, direction: Int = 1) {
        for second in seconds {
            guide.ingest(warningSnapshot(second: second,
                speed: second < 30 ? (direction > 0 ? 2.5 : 4.5) : (direction > 0 ? 4.5 : 2.5)))
        }
    }
}

@MainActor
private func warningSnapshot(second: Int, speed: Double) -> ActiveSessionSnapshot {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let timestamp = start.addingTimeInterval(Double(second))
    let location = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
        altitude: 0, horizontalAccuracy: 3, verticalAccuracy: 3, course: 90,
        speed: speed, timestamp: timestamp)
    return ActiveSessionSnapshot(recordedAt: timestamp, startedAt: start, elapsedSeconds: second,
        distanceMeters: Double(second) * 2.5, currentPaceSecsPerKm: 1_000 / speed,
        activityType: .running, heartRate: nil, location: SessionLocation(location),
        isActive: true, paceEvidenceTimestamp: timestamp)
}

@MainActor
private final class WarningAudioPlayer: GuideAudioPlaying {
    var eventHandler: ((GuideSpeechEvent) -> Void)?
    var playbackRouteHandler: ((GuideAudioPlaybackRoute) -> Void)?
    var isSpeaking = false
    var acceptsPlayback = true
    var played: [Data] = []

    func play(_ data: Data, interrupt: Bool) -> Bool {
        played.append(data)
        return acceptsPlayback
    }
    func play(_ stream: LiveCoachPCMStream, fallbackData: Data?, interrupt: Bool) -> Bool {
        Issue.record("Independent speed warnings must use reviewed local audio")
        return false
    }
    func playSequence(_ data: [Data], completion: (() -> Void)?) -> Bool {
        Issue.record("Unexpected audio sequence in speed-warning fixture")
        return false
    }
    func stopSpeaking(at boundary: GuideAudioPlayer.StopBoundary) { isSpeaking = false }
}

@MainActor
private final class WarningAudioPack: GuideAudioPackProviding {
    var hasClip = true
    var requests: [(key: String, transcript: String?)] = []
    func preloadSelectedAudio() async {}
    func audioData(for cueKey: String, transcript: String?) async -> Data? {
        Issue.record("Independent speed warnings must not download audio")
        return nil
    }
    func localAudioData(for cueKey: String, transcript: String?) -> Data? {
        requests.append((cueKey, transcript))
        return hasClip ? Data(cueKey.utf8) : nil
    }
    func localAudioCue(for cueKey: String) -> (transcript: String, audioData: Data)? {
        guard let audio = localAudioData(for: cueKey, transcript: nil) else { return nil }
        let transcript = cueKey == "coach.settle"
            ? String(localized: "live_guidance.sudden_speed_increase", defaultValue: "Slow down until you can speak a full sentence.")
            : String(localized: "live_guidance.sudden_speed_decrease", defaultValue: "Keep the effort easy; there is no need to make up lost time.")
        return (transcript, audio)
    }
    func localAudioSequence(for cueKeys: [String]) -> [Data]? { nil }
}

// Recorded wording from the on-device signed 2026-09-08.1 manifest. Keep this
// independent of current catalog/app prose so a proposed-script mismatch recurs.
private func recordedSpeedWarningScripts(locale: String) -> [String: String] {
    switch locale {
    case "zh-Hans": return ["coach.settle": "稍微收住强度，找到可持续的节奏。",
                            "coach.restore_rhythm": "放松肩膀，慢慢找回刚才的节奏。"]
    case "es": return ["coach.settle": "Baja un poco el esfuerzo y encuentra un ritmo sostenible.",
                       "coach.restore_rhythm": "Relaja los hombros y recupera el ritmo poco a poco."]
    default: return ["coach.settle": "Settle the effort and find a sustainable rhythm.",
                     "coach.restore_rhythm": "Relax your shoulders and gently find your rhythm again."]
    }
}

private func writeRecordedSpeedWarningCache(directory: URL, scripts: [String: String], voice: String, locale: String) throws -> Data {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    // Deterministic local bytes exercise real disk/checksum/manifest selection;
    // the playback spy captures them without opening an audio device.
    let audio = Data("reviewed speed warning fixture bytes".utf8)
    let sha = SHA256.hash(data: audio).map { String(format: "%02x", $0) }.joined()
    try audio.write(to: directory.appendingPathComponent("\(sha).wav"))
    let entries = scripts.map { key, script in
        ["cueKey": key, "locale": locale, "voiceProfileId": voice, "scriptStyleId": "standard",
         "compatibleCoachPersonaIds": ["plainstride_supportive_v1"], "transcript": script,
         "sha256": sha, "contentType": "audio/wav", "approved": true] as [String: Any]
    }
    let manifest: [String: Any] = ["contractVersion": 1, "catalogVersion": "2026-09-08.1", "entries": entries]
    try JSONSerialization.data(withJSONObject: manifest).write(to: directory.appendingPathComponent("last-known-good-manifest.json"))
    return audio
}

@MainActor
private final class WarningAnalysisProvider: SessionAnalysisProvider {
    let identifier = "speed-warning-fixture"
    let displayName = "Speed warning fixture"
    var progressPolicy: LiveCoachProgressPolicyDTO? { nil }
    var analysisCount = 0
    func beginSession(profile: GuideProfile?, persona: GuidePersona?, sessionIntent: SessionIntent?,
        companionBrief: CompanionSessionBriefDTO?, unitSystem: MeasurementUnitSystem,
        weatherSnapshot: RunningWeatherSnapshot?, isIndoor: Bool) {}
    func analyze(_ request: SessionAnalysisRequest) async throws -> SessionAnalysisResult {
        analysisCount += 1
        Issue.record("Independent speed warnings must not call AI analysis")
        throw CancellationError()
    }
    func endSession(report: LiveGuidanceSessionReport?) {}
}
