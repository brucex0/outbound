import AVFoundation
import Foundation
import OSLog

enum CadencePacerBlockReason: String {
    case audioDisabled = "audio_disabled"
    case quiet
    case speech
    case analysis
    case queuedCue = "queued_cue"
    case routePriority = "route_priority"
}

/// Brief footfall beats, matched to measured cadence, never a speed prescription.
/// Missing or unstable cadence deliberately produces silence rather than a default target.
@MainActor
final class CadencePacer: NSObject, AVAudioPlayerDelegate {
    var eventHandler: ((String) -> Void)?
    var introductionAudio: (() -> Data?)?
    private var player: AVAudioPlayer?
    private var isPlayingIntroduction = false
    private var beatReadyAt: Date?
    private var finishTask: Task<Void, Never>?
    private var observations: [(date: Date, cadence: Int)] = []
    private var lastPlaybackSeconds: Int?
    private var lastSnapshot: ActiveSessionSnapshot?
    private var lastReportedState: String?
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?
    private let logger = Logger(subsystem: "com.plainstride", category: "CadencePacer")

    override init() {
        super.init()
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.suspend() }
        }
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            Task { @MainActor [weak self] in self?.suspend() }
        }
    }

    deinit {
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
        finishTask?.cancel()
    }

    func reset() {
        suspend()
        lastPlaybackSeconds = nil
        lastReportedState = nil
    }

    func suspend() {
        stop()
        observations = []
        lastSnapshot = nil
    }

    func stop(deactivateSession: Bool = true) {
        beatReadyAt = nil
        guard let player else { return }
        let result = isPlayingIntroduction ? "introduction_interrupted" : "interrupted"
        isPlayingIntroduction = false
        finishTask?.cancel()
        finishTask = nil
        player.stop()
        self.player = nil
        if deactivateSession { deactivateAudioSession() }
        reportState(result)
        eventHandler?(result)
    }

    func ingest(
        _ snapshot: ActiveSessionSnapshot, intent: SessionIntent?, allowed: Bool,
        blockReason: CadencePacerBlockReason? = nil
    ) {
        if let lastSnapshot,
           snapshot.recordedAt.timeIntervalSince(lastSnapshot.recordedAt) > 8
                || snapshot.recordedAt < lastSnapshot.recordedAt
                || snapshot.elapsedSeconds < lastSnapshot.elapsedSeconds {
            suspend()
        }
        lastSnapshot = snapshot
        let evidenceNow = snapshot.isSimulated
            ? snapshot.startedAt?.addingTimeInterval(Double(snapshot.elapsedSeconds)) ?? snapshot.recordedAt
            : snapshot.recordedAt
        observations.removeAll { evidenceNow.timeIntervalSince($0.date) > 25 }
        guard snapshot.isActive, snapshot.activityType == .running else {
            suspend()
            reportState("inactive_or_unsupported")
            return
        }
        guard let cadence = snapshot.cadenceStepsPerMinute,
              let timestamp = snapshot.cadenceEvidenceTimestamp,
              (100...220).contains(cadence),
              (-1...5).contains(evidenceNow.timeIntervalSince(timestamp)) else {
            observations = []
            stop()
            reportState("cadence_unavailable")
            return
        }
        if observations.last.map({ timestamp > $0.date }) ?? true {
            observations.append((timestamp, cadence))
        }
        if let target = intent?.resolvedTargetDistanceMeters,
           target - snapshot.distanceMeters <= 200 {
            stop()
            reportState("near_finish")
            return
        }
        let phase = phaseWindow(intent: intent, elapsed: snapshot.elapsedSeconds)
        guard allowed, phase.eligible else {
            stop()
            reportState(allowed ? "phase_ineligible" : blockReason?.rawValue ?? "audio_priority")
            return
        }
        // One opportunity after settling into easy running, then at most every five minutes.
        // Never play over the next transition or during hard/recovery/race execution.
        guard player == nil else { return }
        if let beatReadyAt, Date().timeIntervalSince(beatReadyAt) > 5 {
            self.beatReadyAt = nil
        }
        guard snapshot.elapsedSeconds >= 90, phase.elapsed >= 30, phase.remaining >= 35 else {
            beatReadyAt = nil
            reportState("settling_or_transition")
            return
        }
        guard beatReadyAt != nil
                || (lastPlaybackSeconds.map({ snapshot.elapsedSeconds - $0 >= 300 }) ?? true) else {
            reportState("cooldown")
            return
        }
        guard observations.count >= 8,
              let first = observations.first, let last = observations.last,
              last.date.timeIntervalSince(first.date) >= 15,
              let low = observations.map(\.cadence).min(),
              let high = observations.map(\.cadence).max(), high - low <= 12 else {
            reportState("cadence_not_established")
            return
        }
        let sorted = observations.map(\.cadence).sorted()
        let cadenceTarget = sorted[sorted.count / 2]
        // Do not retry an audio failure on every snapshot.
        lastPlaybackSeconds = snapshot.elapsedSeconds
        if beatReadyAt != nil {
            beatReadyAt = nil
            play(cadence: cadenceTarget)
        } else if let introduction = introductionAudio?() {
            playIntroduction(introduction)
        } else {
            reportState("introduction_unavailable")
            eventHandler?("introduction_unavailable")
            logger.notice("Cadence pacer introduction unavailable; continuing with beat")
            play(cadence: cadenceTarget)
        }
    }

    private func phaseWindow(intent: SessionIntent?, elapsed: Int) -> (eligible: Bool, elapsed: Int, remaining: Int) {
        guard intent?.raceIntent == nil else { return (false, 0, 0) }
        var start = 0
        for step in intent?.workoutSteps ?? [] {
            let end = start + max(0, step.durationSeconds)
            if elapsed < end {
                let phase = step.coachingTarget?.phase
                return (phase == .easy, elapsed - start, end - elapsed)
            }
            start = end
        }
        // Structured workouts stop receiving beats after the final step.
        guard intent?.workoutSteps.isEmpty ?? true else { return (false, 0, 0) }
        let phase = intent?.coachingTarget?.phase ?? .open
        let remaining = intent?.resolvedTargetDurationSeconds.map { $0 - elapsed } ?? Int.max
        return (phase == .easy || phase == .open, elapsed, remaining)
    }

    private func playIntroduction(_ audio: Data) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio,
                                    options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try session.setActive(true)
            let player = try AVAudioPlayer(data: audio)
            player.delegate = self
            guard player.play() else {
                logger.error("Cadence pacer introduction failed: AVAudioPlayer.play returned false")
                deactivateAudioSession()
                beatReadyAt = Date()
                reportState("introduction_failed")
                eventHandler?("introduction_failed")
                return
            }
            self.player = player
            isPlayingIntroduction = true
            reportState("introduction_started")
            eventHandler?("introduction_started")
        } catch {
            let error = error as NSError
            logger.error("Cadence pacer introduction failed: domain=\(error.domain, privacy: .public) code=\(error.code)")
            deactivateAudioSession()
            beatReadyAt = Date()
            reportState("introduction_failed")
            eventHandler?("introduction_failed")
        }
    }

    private func play(cadence: Int) {
        do {
            let session = AVAudioSession.sharedInstance()
            // Mix beneath external music; speech owns ducking and always preempts beats.
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            let player = try AVAudioPlayer(data: Self.drumAudio(cadence: cadence))
            player.delegate = self
            player.volume = 0.7
            guard player.play() else {
                logger.error("Cadence pacer start failed: AVAudioPlayer.play returned false")
                deactivateAudioSession()
                eventHandler?("failed")
                return
            }
            self.player = player
            let output = session.outputVolume == 0 ? "muted" : "nonzero"
            let route = session.currentRoute.outputs.first?.portType.rawValue ?? "none"
            logger.notice("Cadence pacer started route=\(route, privacy: .public) output=\(output, privacy: .public) media_volume=\(session.outputVolume, privacy: .public) player_gain=\(player.volume, privacy: .public) sound=drum_v2")
            reportState("playing")
            eventHandler?("started")
            finishTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                self?.player?.setVolume(0, fadeDuration: 5)
            }
        } catch {
            let error = error as NSError
            logger.error("Cadence pacer prepare failed: domain=\(error.domain, privacy: .public) code=\(error.code)")
            deactivateAudioSession()
            eventHandler?("failed")
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard self.player === player else { return }
        self.player = nil
        if isPlayingIntroduction {
            isPlayingIntroduction = false
            beatReadyAt = Date()
            deactivateAudioSession()
            let result = flag ? "introduction_completed" : "introduction_failed"
            reportState(result)
            eventHandler?(result)
            if !flag { logger.error("Cadence pacer introduction ended unsuccessfully") }
            return
        }
        finishTask?.cancel()
        finishTask = nil
        deactivateAudioSession()
        reportState(flag ? "completed" : "failed")
        eventHandler?(flag ? "completed" : "failed")
        if !flag { logger.error("Cadence pacer playback ended unsuccessfully") }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard self.player === player else { return }
        let error = error as NSError?
        logger.error("Cadence pacer decode failed: code=\(error?.code ?? -1)")
        if isPlayingIntroduction {
            player.stop()
            self.player = nil
            isPlayingIntroduction = false
            deactivateAudioSession()
            beatReadyAt = Date()
            reportState("introduction_failed")
            eventHandler?("introduction_failed")
            return
        }
        stop()
        eventHandler?("failed")
    }

    private func reportState(_ state: String) {
        guard state != lastReportedState else { return }
        lastReportedState = state
        // Closed technical states only; no cadence, timestamps, names or workout content.
        logger.notice("Cadence pacer state=\(state, privacy: .public)")
    }

    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            let error = error as NSError
            logger.error("Cadence pacer audio deactivation failed: code=\(error.code)")
        }
    }

    /// A short drum hit with a midrange attack so the rhythm carries on phone speakers.
    /// PCM scheduling avoids timer jitter; a smooth onset avoids a hard digital click.
    private static func drumAudio(cadence: Int) -> Data {
        let sampleRate = 22_050
        let sampleCount = sampleRate * 20
        let interval = 60.0 / Double(cadence)
        var pcm = Data(capacity: sampleCount * 2)
        for index in 0..<sampleCount {
            let time = Double(index) / Double(sampleRate)
            let hitTime = time.truncatingRemainder(dividingBy: interval)
            let onset = min(1, hitTime / 0.0015)
            let body = 0.55 * sin(2 * .pi * 240 * hitTime) * exp(-hitTime * 28)
            let attack = 0.30 * sin(2 * .pi * 840 * hitTime) * exp(-hitTime * 45)
            let overtone = 0.15 * sin(2 * .pi * 1_680 * hitTime) * exp(-hitTime * 90)
            // An intrinsic fade also completes while the app is suspended.
            let fade = min(1.0, max(0, (20 - time) / 5))
            let sample = Int16((body + attack + overtone) * onset * fade * 30_000)
            var littleEndian = sample.littleEndian
            withUnsafeBytes(of: &littleEndian) { pcm.append(contentsOf: $0) }
        }
        var wav = Data()
        func word(_ value: UInt32, bytes: Int) {
            for index in 0..<bytes { wav.append(UInt8(truncatingIfNeeded: value >> (index * 8))) }
        }
        wav.append(contentsOf: "RIFF".utf8)
        word(UInt32(36 + pcm.count), bytes: 4)
        wav.append(contentsOf: "WAVEfmt ".utf8)
        word(16, bytes: 4); word(1, bytes: 2); word(1, bytes: 2)
        word(UInt32(sampleRate), bytes: 4); word(UInt32(sampleRate * 2), bytes: 4)
        word(2, bytes: 2); word(16, bytes: 2)
        wav.append(contentsOf: "data".utf8)
        word(UInt32(pcm.count), bytes: 4)
        wav.append(pcm)
        return wav
    }
}
