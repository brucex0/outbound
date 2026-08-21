import AVFoundation
import Foundation

@MainActor
final class GuideSpeechSynthesizer {
    enum StopBoundary {
        case immediate
        case currentWord
    }

    var eventHandler: ((GuideSpeechEvent) -> Void)? {
        didSet {
            appleSynthesizer.eventHandler = eventHandler
        }
    }

    var isSpeaking: Bool {
        appleSynthesizer.isSpeaking
    }

    private let appleSynthesizer = InstalledAppleSpeechSynthesizer()

    func speak(_ text: String, voice: GuideVoice, rate: Float, volume: Float) {
        stopSpeaking(at: .immediate)
        appleSynthesizer.speak(text, voice: voice, rate: rate, volume: volume)
    }

    func speakSequence(_ texts: [String], voice: GuideVoice, rate: Float, volume: Float) {
        stopSpeaking(at: .immediate)
        appleSynthesizer.speakSequence(texts, voice: voice, rate: rate, volume: volume)
    }

    func stopSpeaking(at boundary: StopBoundary) {
        let appleBoundary: AVSpeechBoundary = switch boundary {
        case .immediate: .immediate
        case .currentWord: .word
        }
        appleSynthesizer.stopSpeaking(at: appleBoundary)
    }
}

@MainActor
private final class InstalledAppleSpeechSynthesizer: NSObject, @preconcurrency AVSpeechSynthesizerDelegate {
    var eventHandler: ((GuideSpeechEvent) -> Void)?
    private(set) var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()
    private var pendingUtteranceCount = 0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, voice: GuideVoice, rate: Float, volume: Float) {
        do {
            try Self.activateAudioSession()
            isSpeaking = true
            pendingUtteranceCount = 1
            synthesizer.speak(Self.utterance(text, voice: voice, rate: rate, volume: volume))
        } catch {
            finishSpeaking()
        }
    }

    func speakSequence(_ texts: [String], voice: GuideVoice, rate: Float, volume: Float) {
        guard !texts.isEmpty else { return }

        do {
            try Self.activateAudioSession()
            isSpeaking = true
            pendingUtteranceCount = texts.count
            for (index, text) in texts.enumerated() {
                let utterance = Self.utterance(text, voice: voice, rate: rate, volume: volume)
                if index < texts.count - 1 {
                    utterance.postUtteranceDelay = 0.55
                }
                synthesizer.speak(utterance)
            }
        } catch {
            finishSpeaking()
        }
    }

    private static func utterance(_ text: String, voice: GuideVoice, rate: Float, volume: Float) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = installedVoice(for: voice)
        utterance.rate = max(AVSpeechUtteranceMinimumSpeechRate, min(AVSpeechUtteranceMaximumSpeechRate, rate))
        utterance.volume = max(0, min(1, volume))
        return utterance
    }

    private static func installedVoice(for voice: GuideVoice) -> AVSpeechSynthesisVoice? {
        guard let identifier = voice.appleVoiceIdentifier else {
            return AVSpeechSynthesisVoice(language: voice.locale)
        }

        // Some downloaded Enhanced/Premium voices are present in speechVoices()
        // even when recreating them with init(identifier:) returns nil. Reuse the
        // catalog instance so a selected voice such as Bobo does not become the
        // system's low-quality locale default during playback.
        return AVSpeechSynthesisVoice.speechVoices().first { $0.identifier == identifier }
            ?? AVSpeechSynthesisVoice(identifier: identifier)
    }

    func stopSpeaking(at boundary: AVSpeechBoundary) {
        guard isSpeaking else { return }
        pendingUtteranceCount = 0
        if !synthesizer.stopSpeaking(at: boundary) {
            finishSpeaking()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        eventHandler?(.didStart)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        pendingUtteranceCount = max(0, pendingUtteranceCount - 1)
        if pendingUtteranceCount == 0 {
            finishSpeaking()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finishSpeaking()
    }

    private func finishSpeaking() {
        let wasSpeaking = isSpeaking
        isSpeaking = false
        pendingUtteranceCount = 0
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        if wasSpeaking {
            eventHandler?(.didFinish)
        }
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
