import AVFoundation
import Foundation

@MainActor
final class GuideAudioPlayer: NSObject, @preconcurrency AVAudioPlayerDelegate {
    enum StopBoundary {
        case immediate
        case currentCue
    }

    var eventHandler: ((GuideSpeechEvent) -> Void)?
    private(set) var isSpeaking = false

    private var player: AVAudioPlayer?
    private var queuedAudio: [Data] = []

    @discardableResult
    func play(_ data: Data, interrupt: Bool = false) -> Bool {
        if isSpeaking {
            guard interrupt else { return false }
            stopSpeaking(at: .immediate)
        }
        queuedAudio = [data]
        playNext()
        return isSpeaking
    }

    func playSequence(_ data: [Data]) {
        stopSpeaking(at: .immediate)
        queuedAudio = data
        playNext()
    }

    func stopSpeaking(at boundary: StopBoundary) {
        queuedAudio = []
        if boundary == .immediate {
            player?.stop()
            finishSpeaking()
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        self.player = nil
        if queuedAudio.isEmpty {
            finishSpeaking()
        } else {
            playNext()
        }
    }

    func audioPlayerBeginInterruption(_ player: AVAudioPlayer) {
        // Keep the current cue and queue so iOS can resume the same generated voice.
    }

    func audioPlayerEndInterruption(_ player: AVAudioPlayer, withOptions flags: Int) {
        let options = AVAudioSession.InterruptionOptions(rawValue: UInt(flags))
        guard options.contains(.shouldResume) else {
            finishSpeaking()
            return
        }
        do {
            try Self.activateAudioSession()
            guard player.play() else {
                finishSpeaking()
                return
            }
            isSpeaking = true
        } catch {
            finishSpeaking()
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        finishSpeaking()
    }

    private func playNext() {
        guard !queuedAudio.isEmpty else {
            finishSpeaking()
            return
        }
        do {
            try Self.activateAudioSession()
            let next = queuedAudio.removeFirst()
            let player = try AVAudioPlayer(data: next)
            player.delegate = self
            player.prepareToPlay()
            self.player = player
            let wasSpeaking = isSpeaking
            isSpeaking = player.play()
            if isSpeaking && !wasSpeaking { eventHandler?(.didStart) }
            if !isSpeaking { finishSpeaking() }
        } catch {
            finishSpeaking()
        }
    }

    private func finishSpeaking() {
        let wasSpeaking = isSpeaking
        isSpeaking = false
        player = nil
        queuedAudio = []
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        if wasSpeaking { eventHandler?(.didFinish) }
    }

    private static func activateAudioSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playback,
            mode: .spokenAudio,
            options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
        )
        try session.setActive(true)
        #endif
    }
}
