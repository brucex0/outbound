import AVFoundation
import Foundation

enum GuideAudioPlaybackRoute: String, Equatable {
    case cloudStream = "cloud_stream"
    case recordedAudio = "recorded_audio"
    case onDeviceSpeech = "on_device_speech"
}

@MainActor
final class GuideAudioPlayer: NSObject, @preconcurrency AVAudioPlayerDelegate, @preconcurrency AVSpeechSynthesizerDelegate {
    enum StopBoundary {
        case immediate
        case currentCue
    }

    var eventHandler: ((GuideSpeechEvent) -> Void)?
    var playbackRouteHandler: ((GuideAudioPlaybackRoute) -> Void)?
    private(set) var isSpeaking = false

    private var player: AVAudioPlayer?
    private var queuedAudio: [Data] = []
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var streamTask: Task<Void, Never>?
    private var deadlineTask: Task<Void, Never>?
    private var scheduledPCMBufferCount = 0
    private var pcmStreamEnded = false
    private var pcmPlaybackStarted = false
    private var didEmitStart = false
    private var didEmitPlaybackRoute = false
    private var requiresPinnedOnDeviceVoice = false
    private var pinnedOnDeviceVoice: AVSpeechSynthesisVoice?
    private let speechSynthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        speechSynthesizer.delegate = self
    }

    func pinOnDeviceVoice(presentation: GuideVoicePresentation?) {
        requiresPinnedOnDeviceVoice = presentation != nil
        pinnedOnDeviceVoice = presentation.flatMap(Self.onDeviceVoice(for:))
    }

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

    @discardableResult
    func play(
        _ stream: LiveCoachPCMStream,
        fallbackData: Data?,
        fallbackText: String,
        interrupt: Bool = false
    ) -> Bool {
        if isSpeaking {
            guard interrupt else { return false }
            stopSpeaking(at: .immediate)
        }
        do {
            try Self.activateAudioSession()
            let format = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 24_000,
                channels: 1,
                interleaved: false
            )!
            let engine = AVAudioEngine()
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            try engine.start()
            audioEngine = engine
            playerNode = node
            scheduledPCMBufferCount = 0
            pcmStreamEnded = false
            pcmPlaybackStarted = false
            didEmitStart = false
            didEmitPlaybackRoute = false
            isSpeaking = true

            let remaining = max(
                0,
                LiveCoachAudioTiming.cloudAudioDeadlineSeconds
                    - Date().timeIntervalSince(stream.requestStartedAt)
            )
            deadlineTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.handlePCMFailureBeforePlayback(fallbackData: fallbackData, fallbackText: fallbackText)
            }
            streamTask = Task { @MainActor [weak self] in
                guard let self else { return }
                var pending = Data()
                do {
                    for try await chunk in stream.chunks {
                        guard !Task.isCancelled else { return }
                        pending.append(chunk)
                        let playableByteCount = pending.count - pending.count % 2
                        guard playableByteCount > 0 else { continue }
                        let playable = Data(pending.prefix(playableByteCount))
                        pending.removeFirst(playableByteCount)
                        self.schedulePCM(playable, format: format)
                    }
                    self.pcmStreamEnded = true
                    self.finishPCMIfReady()
                } catch {
                    if !self.pcmPlaybackStarted {
                        self.handlePCMFailureBeforePlayback(fallbackData: fallbackData, fallbackText: fallbackText)
                    } else {
                        self.pcmStreamEnded = true
                        self.finishPCMIfReady()
                    }
                }
            }
            return true
        } catch {
            if let fallbackData { return play(fallbackData, interrupt: interrupt) }
            finishSpeaking()
            return false
        }
    }

    @discardableResult
    func speakOnDevice(_ text: String, interrupt: Bool = false) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        if isSpeaking {
            guard interrupt else { return false }
            stopSpeaking(at: .immediate)
        }
        guard !requiresPinnedOnDeviceVoice || pinnedOnDeviceVoice != nil else { return false }
        do {
            try Self.activateAudioSession()
            let utterance = AVSpeechUtterance(string: normalized)
            utterance.voice = pinnedOnDeviceVoice
                ?? AVSpeechSynthesisVoice(language: AppLanguage.speechLocale.identifier)
                ?? AVSpeechSynthesisVoice(language: AppLanguage.currentIdentifier)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            isSpeaking = true
            didEmitStart = true
            emitPlaybackRoute(.onDeviceSpeech)
            eventHandler?(.didStart)
            speechSynthesizer.speak(utterance)
            return true
        } catch {
            finishSpeaking()
            return false
        }
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
            if speechSynthesizer.isSpeaking {
                speechSynthesizer.stopSpeaking(at: .immediate)
            }
            stopPCMResources()
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

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finishSpeaking()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        if isSpeaking { finishSpeaking() }
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
            if isSpeaking && !wasSpeaking {
                didEmitStart = true
                emitPlaybackRoute(.recordedAudio)
                eventHandler?(.didStart)
            }
            if !isSpeaking { finishSpeaking() }
        } catch {
            finishSpeaking()
        }
    }

    private func finishSpeaking() {
        let shouldEmitFinish = didEmitStart
        isSpeaking = false
        didEmitStart = false
        didEmitPlaybackRoute = false
        player = nil
        queuedAudio = []
        stopPCMResources()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        if shouldEmitFinish { eventHandler?(.didFinish) }
    }

    private func schedulePCM(_ data: Data, format: AVAudioFormat) {
        guard let playerNode, !data.isEmpty else { return }
        let frameCount = AVAudioFrameCount(data.count / MemoryLayout<Int16>.size)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.int16ChannelData?[0]
        else { return }
        buffer.frameLength = frameCount
        data.withUnsafeBytes { bytes in
            guard let source = bytes.baseAddress else { return }
            memcpy(channel, source, data.count)
        }
        scheduledPCMBufferCount += 1
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.scheduledPCMBufferCount = max(0, self.scheduledPCMBufferCount - 1)
                self.finishPCMIfReady()
            }
        }
        if !pcmPlaybackStarted {
            pcmPlaybackStarted = true
            deadlineTask?.cancel()
            deadlineTask = nil
            playerNode.play()
            didEmitStart = true
            emitPlaybackRoute(.cloudStream)
            eventHandler?(.didStart)
        }
    }

    private func finishPCMIfReady() {
        guard pcmStreamEnded, scheduledPCMBufferCount == 0 else { return }
        finishSpeaking()
    }

    private func handlePCMFailureBeforePlayback(fallbackData: Data?, fallbackText: String) {
        guard !pcmPlaybackStarted else { return }
        streamTask?.cancel()
        stopPCMResources()
        if let fallbackData {
            isSpeaking = false
            queuedAudio = [fallbackData]
            playNext()
        } else {
            isSpeaking = false
            _ = speakOnDevice(fallbackText, interrupt: false)
        }
    }

    private func stopPCMResources() {
        streamTask?.cancel()
        streamTask = nil
        deadlineTask?.cancel()
        deadlineTask = nil
        playerNode?.stop()
        audioEngine?.stop()
        playerNode = nil
        audioEngine = nil
        scheduledPCMBufferCount = 0
        pcmStreamEnded = false
        pcmPlaybackStarted = false
    }

    private func emitPlaybackRoute(_ route: GuideAudioPlaybackRoute) {
        guard !didEmitPlaybackRoute else { return }
        didEmitPlaybackRoute = true
        playbackRouteHandler?(route)
    }

    private static func onDeviceVoice(for presentation: GuideVoicePresentation) -> AVSpeechSynthesisVoice? {
        let requestedLocale = AppLanguage.speechLocale
        let requestedLanguageCode = requestedLocale.language.languageCode?.identifier
        let requestedIdentifier = requestedLocale.identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        let requestedGender: AVSpeechSynthesisVoiceGender = presentation == .female ? .female : .male
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { voice in
                voice.gender == requestedGender
                    && Locale(identifier: voice.language).language.languageCode?.identifier == requestedLanguageCode
            }
            .sorted { left, right in
                let leftExact = left.language.replacingOccurrences(of: "_", with: "-").lowercased() == requestedIdentifier
                let rightExact = right.language.replacingOccurrences(of: "_", with: "-").lowercased() == requestedIdentifier
                if leftExact != rightExact { return leftExact }
                if left.quality != right.quality { return left.quality.rawValue > right.quality.rawValue }
                return left.identifier < right.identifier
            }
            .first
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
