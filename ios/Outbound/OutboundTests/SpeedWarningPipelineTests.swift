import AVFAudio
import Combine
import CoreLocation
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
        let key = direction > 0 ? "coach.speed_increase" : "coach.speed_decrease"
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
        #expect(fixture.player.played == [Data("coach.speed_increase".utf8)])
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
        #expect(fixture.player.played == [Data("coach.speed_increase".utf8)])
    }

    @Test(arguments: ["en", "es", "zh-Hans"], ["plainstride_warm_1", "plainstride_clear_1"])
    func bundledScriptsPlayWithOldCachedManifestAndNoDownloadedAudio(locale: String, voice: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // The actual installed phone had an older cached manifest. It must not
        // hide the explicit recordings bundled in this app, even offline.
        let oldManifest: [String: Any] = ["contractVersion": 1, "catalogVersion": "2026-09-08.1", "entries": []]
        try JSONSerialization.data(withJSONObject: oldManifest).write(to: directory.appendingPathComponent("last-known-good-manifest.json"))
        let pack = GuideAudioPackStore(cacheDirectory: directory, localeIdentifier: { locale })
        pack.select(coachPersonaID: "plainstride_supportive_v1", voiceProfileID: voice, scriptStyleID: "standard")
        await pack.preloadSelectedAudio()
        for direction in [1, -1] {
            let key = direction > 0 ? "coach.speed_increase" : "coach.speed_decrease"
            #expect(pack.localAudioData(for: key, transcript: "Settle the effort and find a sustainable rhythm.") == nil)
            let cue = try #require(pack.localAudioCue(for: key))
            #expect(cue.audioData.starts(with: Data("RIFF".utf8)))
            #expect(cue.audioData.count > 44)
            let fixture = WarningFixture(audioPack: pack)
            fixture.feed(0...40, direction: direction)
            #expect(fixture.speedEvents.last == "\(direction > 0 ? "increase" : "decrease"):spoken")
            #expect(fixture.player.played == [cue.audioData])
            #expect(fixture.guide.lastNudge == cue.transcript)
            #expect(fixture.guide.lastSpokenAnnouncement == cue.transcript)
            fixture.guide.deactivate()
        }
    }

    @Test(arguments: [1, 10], [4, 6, 7, 24])
    func walkingAndRunningRampsPlayExplicitBundledCue(rate: Int, startingSpeed: Int) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pack = GuideAudioPackStore(cacheDirectory: directory, localeIdentifier: { "en" })
        pack.select(coachPersonaID: "plainstride_supportive_v1", voiceProfileID: "plainstride_clear_1", scriptStyleID: "standard")
        await pack.preloadSelectedAudio()
        let direction = startingSpeed == 24 ? -1 : 1
        let key = direction > 0 ? "coach.speed_increase" : "coach.speed_decrease"
        let cue = try #require(pack.localAudioCue(for: key))
        let fixture = WarningFixture(audioPack: pack)
        let recorder = ActivityRecorder(locationManager: LocationManager())
        let route = HarvestHalfMarathonSimulation.route
        recorder.startRunSimulation(routeGuidance: .init(route: route, recoverySeed: nil),
                                    route: route, speedKilometersPerHour: Double(startingSpeed))
        defer {
            fixture.guide.deactivate()
            _ = recorder.finish()
            ActiveSessionJournal.clear(reason: .discarded)
        }
        let subscription = recorder.$liveSnapshot.sink { fixture.guide.ingest($0) }
        defer { subscription.cancel() }
        recorder.advanceRunSimulation(by: 45)
        // The actual plus/minus buttons change 1 km/h. Taps over four wall-clock
        // seconds must exercise the same ramp at both simulation clock rates.
        let targetSpeed = startingSpeed == 4 ? 19 : (startingSpeed == 24 ? 7 : 24)
        let tapCount = abs(targetSpeed - startingSpeed)
        for tap in 1...tapCount {
            recorder.adjustRunSimulationSpeed(byKilometersPerHour: Double(direction))
            let seconds = tap * 4 * rate / tapCount - (tap - 1) * 4 * rate / tapCount
            if seconds > 0 { recorder.advanceRunSimulation(by: seconds) }
        }
        // Stay before the independent cadence-pacer opportunity at 90 seconds.
        recorder.advanceRunSimulation(by: max(0, 89 - recorder.elapsedSeconds))
        #expect(fixture.speedEvents.contains("\(direction > 0 ? "increase" : "decrease"):spoken"))
        #expect(fixture.player.played.contains(cue.audioData))
        #expect(fixture.guide.lastNudge == cue.transcript)
    }
    @Test func independentSpeedChangeSurvivesRecentTargetCorrection() {
        let director = LiveGuidanceDirector()
        director.reset(contract: .responsive, challenge: .off)
        let target = SessionCoachingTarget(phase: .easy, pace: SessionPaceTarget(
            reference: .absolute, targetSecondsPerKilometer: 300,
            fasterToleranceSeconds: 30, slowerToleranceSeconds: 30))
        let intent = SessionIntent(id: "targeted-run", sport: .run, title: "", detail: "",
            guideLine: "", startLabel: "", coachingTarget: target)
        var moments: [DetectedLiveGuidanceMoment] = []
        for second in 0...70 {
            if let moment = director.ingest(warningSnapshot(second: second,
                speed: (second < 50 ? 6.0 : 24.0) / 3.6), profile: nil, intent: intent).nextMoment {
                moments.append(moment)
            }
        }
        #expect(moments.contains { $0.type == .paceBelowTarget })
        #expect(moments.contains { $0.speedChangeDirection == 1 })
    }

    @Test(arguments: AppLanguage.allCases, ["plainstride_warm_1", "plainstride_clear_1"])
    func everyFixedFallbackHasMatchingPlayableRecording(language: AppLanguage, voice: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pack = GuideAudioPackStore(cacheDirectory: directory, localeIdentifier: { language.rawValue })
        pack.select(coachPersonaID: "plainstride_supportive_v1", voiceProfileID: voice, scriptStyleID: "standard")
        await pack.preloadSelectedAudio()
        for moment in LiveGuidanceMomentType.allCases {
            let fallback = ServerLiveCoachProvider.fallback(for: moment, language: language)
            if moment == .progress {
                // Generic progress cannot truthfully claim that a target is held.
                #expect(fallback.text.isEmpty)
                continue
            }
            let data = try #require(pack.localAudioData(for: fallback.key, transcript: fallback.text))
            #expect(data.starts(with: Data("RIFF".utf8)))
            #expect(pack.localAudioData(for: fallback.key, transcript: "An unrelated sentence.") == nil)
        }
        let manifestURL = try #require(Bundle.main.url(forResource: "manifest", withExtension: "json", subdirectory: "LiveCoachAudio"))
        let manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        let entries = try #require(manifest["entries"] as? [[String: Any]])
        for entry in entries where entry["locale"] as? String == language.rawValue && entry["voiceProfileId"] as? String == voice {
            let key = try #require(entry["cueKey"] as? String)
            let script = try #require(entry["transcript"] as? String)
            let data = try #require(pack.localAudioData(for: key, transcript: script))
            let properties = try await Task.detached {
                let decoder = try AVAudioPlayer(data: data)
                let properties = (decoder.prepareToPlay(), decoder.duration, decoder.numberOfChannels)
                decoder.stop()
                return properties
            }.value
            #expect(properties.0)
            #expect(properties.1 > 0 && properties.1 <= 8)
            #expect(properties.2 == 1)
        }
        #expect(pack.localAudioSequence(for: GuideAudioPackStore.segmentCountdownCueKeys)?.count == 5)
    }

    @Test func unreviewedBundledRecordingsAreNotGrantedApprovalByPlaybackCode() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pack = try unreviewedAudioPackFixture(directory: directory, locale: "en", voice: "plainstride_clear_1")
        pack.select(coachPersonaID: "plainstride_supportive_v1", voiceProfileID: "plainstride_clear_1", scriptStyleID: "standard")
        await pack.preloadSelectedAudio()
        #expect(pack.localAudioCue(for: "coach.speed_increase") == nil)
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
        let transcript = cueKey == "coach.speed_increase"
            ? String(localized: "live_guidance.sudden_speed_increase", defaultValue: "You sped up too fast. Keep a steady pace and speed up gradually.")
            : String(localized: "live_guidance.sudden_speed_decrease", defaultValue: "Your speed dropped sharply. If you meant to keep running, return to your pace gradually.")
        return (transcript, audio)
    }
    func localAudioSequence(for cueKeys: [String]) -> [Data]? { nil }
}

// Exercise rejection with an explicitly unreviewed copy; all positive playback
// checks above use the actual owner-approved app bundle directly.
@MainActor
private func unreviewedAudioPackFixture(directory: URL, locale: String, voice: String) throws -> GuideAudioPackStore {
    let manifestURL = try #require(Bundle.main.url(forResource: "manifest", withExtension: "json", subdirectory: "LiveCoachAudio"))
    var manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
    let all = try #require(manifest["entries"] as? [[String: Any]])
    let fixtureDirectory = directory.appendingPathComponent("reviewed-fixture")
    try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
    var entries: [[String: Any]] = []
    for var entry in all where entry["locale"] as? String == locale && entry["voiceProfileId"] as? String == voice {
        let name = try #require(entry["bundledResourceName"] as? String)
        let fileName = name + ".wav"
        let target = fixtureDirectory.appendingPathComponent(fileName)
        if !FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.copyItem(at: manifestURL.deletingLastPathComponent().appendingPathComponent(fileName), to: target)
        }
        entry["approved"] = false
        entries.append(entry)
    }
    manifest["entries"] = entries
    try JSONSerialization.data(withJSONObject: manifest).write(to: fixtureDirectory.appendingPathComponent("manifest.json"))
    return GuideAudioPackStore(cacheDirectory: directory, bundledAudioDirectory: fixtureDirectory,
                               localeIdentifier: { locale })
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
