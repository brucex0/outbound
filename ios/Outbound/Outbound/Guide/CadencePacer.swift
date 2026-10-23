import AVFoundation
import Foundation
import OSLog

/// Brief footfall beats, matched to measured cadence, never a speed prescription.
/// Missing or unstable cadence deliberately produces silence rather than a default target.
@MainActor
final class CadencePacer: NSObject, AVAudioPlayerDelegate {
    var eventHandler: ((String) -> Void)?
    private var player: AVAudioPlayer?
    private var finishTask: Task<Void, Never>?
    private var observations: [(date: Date, cadence: Int)] = []
    private var lastPlaybackSeconds: Int?
    private var lastSnapshot: ActiveSessionSnapshot?
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
    }

    func suspend() {
        stop()
        observations = []
        lastSnapshot = nil
    }

    func stop(deactivateSession: Bool = true) {
        guard let player else { return }
        finishTask?.cancel()
        finishTask = nil
        player.stop()
        self.player = nil
        if deactivateSession { deactivateAudioSession() }
        eventHandler?("interrupted")
    }

    func ingest(_ snapshot: ActiveSessionSnapshot, intent: SessionIntent?, allowed: Bool) {
        if let lastSnapshot,
           snapshot.recordedAt.timeIntervalSince(lastSnapshot.recordedAt) > 8
                || snapshot.recordedAt < lastSnapshot.recordedAt
                || snapshot.elapsedSeconds < lastSnapshot.elapsedSeconds {
            suspend()
        }
        lastSnapshot = snapshot
        observations.removeAll { snapshot.recordedAt.timeIntervalSince($0.date) > 25 }
        guard snapshot.isActive, snapshot.activityType == .running else { suspend(); return }
        guard let cadence = snapshot.cadenceStepsPerMinute,
              let timestamp = snapshot.cadenceEvidenceTimestamp,
              (100...220).contains(cadence),
              (-1...5).contains(snapshot.recordedAt.timeIntervalSince(timestamp)) else {
            observations = []
            stop()
            return
        }
        if observations.last.map({ timestamp > $0.date }) ?? true {
            observations.append((timestamp, cadence))
        }
        if let target = intent?.resolvedTargetDistanceMeters,
           target - snapshot.distanceMeters <= 200 { stop(); return }
        let phase = phaseWindow(intent: intent, elapsed: snapshot.elapsedSeconds)
        guard allowed, phase.eligible else { stop(); return }
        // One opportunity after settling into easy running, then at most every five minutes.
        // Never play over the next transition or during hard/recovery/race execution.
        guard player == nil, snapshot.elapsedSeconds >= 90,
              phase.elapsed >= 30, phase.remaining >= 35,
              lastPlaybackSeconds.map({ snapshot.elapsedSeconds - $0 >= 300 }) ?? true,
              observations.count >= 8,
              let first = observations.first, let last = observations.last,
              last.date.timeIntervalSince(first.date) >= 15,
              let low = observations.map(\.cadence).min(),
              let high = observations.map(\.cadence).max(), high - low <= 12 else { return }
        let sorted = observations.map(\.cadence).sorted()
        let cadenceTarget = sorted[sorted.count / 2]
        // Do not retry an audio failure on every snapshot.
        lastPlaybackSeconds = snapshot.elapsedSeconds
        play(cadence: cadenceTarget)
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

    private func play(cadence: Int) {
        do {
            let session = AVAudioSession.sharedInstance()
            // Mix beneath external music; speech owns ducking and always preempts beats.
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            let player = try AVAudioPlayer(data: Self.drumAudio(cadence: cadence))
            player.delegate = self
            player.volume = 0.32
            guard player.play() else {
                logger.error("Cadence pacer start failed: AVAudioPlayer.play returned false")
                deactivateAudioSession()
                eventHandler?("failed")
                return
            }
            self.player = player
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
        self.player = nil
        finishTask?.cancel()
        finishTask = nil
        deactivateAudioSession()
        eventHandler?(flag ? "completed" : "failed")
        if !flag { logger.error("Cadence pacer playback ended unsuccessfully") }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let error = error as NSError?
        logger.error("Cadence pacer decode failed: code=\(error?.code ?? -1)")
        stop()
        eventHandler?("failed")
    }

    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            let error = error as NSError
            logger.error("Cadence pacer audio deactivation failed: code=\(error.code)")
        }
    }

    /// A quiet, decaying low drum hit per footfall; PCM scheduling avoids timer jitter.
    private static func drumAudio(cadence: Int) -> Data {
        let sampleRate = 22_050
        let sampleCount = sampleRate * 20
        let interval = 60.0 / Double(cadence)
        var pcm = Data(capacity: sampleCount * 2)
        for index in 0..<sampleCount {
            let time = Double(index) / Double(sampleRate)
            let hitTime = time.truncatingRemainder(dividingBy: interval)
            let envelope = exp(-hitTime * 45)
            // An intrinsic fade also completes while the app is suspended.
            let fade = min(1.0, max(0, (20 - time) / 5))
            let sample = Int16(sin(2 * .pi * 150 * hitTime) * envelope * fade * 24_000)
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
