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

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, voice: GuideVoice, rate: Float, volume: Float) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.installedVoice(for: voice)
        utterance.rate = max(AVSpeechUtteranceMinimumSpeechRate, min(AVSpeechUtteranceMaximumSpeechRate, rate))
        utterance.volume = max(0, min(1, volume))

        do {
            try Self.activateAudioSession()
            isSpeaking = true
            synthesizer.speak(utterance)
        } catch {
            finishSpeaking()
        }
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
        if !synthesizer.stopSpeaking(at: boundary) {
            finishSpeaking()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        eventHandler?(.didStart)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finishSpeaking()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finishSpeaking()
    }

    private func finishSpeaking() {
        let wasSpeaking = isSpeaking
        isSpeaking = false
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
