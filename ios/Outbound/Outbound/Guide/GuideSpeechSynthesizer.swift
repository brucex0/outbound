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

    private let appleSynthesizer = AppleBestSpeechSynthesizer()

    func speak(_ text: String, voice: GuideVoice, speed: Float, volume: Float) {
        stopSpeaking(at: .immediate)
        appleSynthesizer.speak(text, voice: voice, speed: speed, volume: volume)
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
private final class AppleBestSpeechSynthesizer: NSObject, @preconcurrency AVSpeechSynthesizerDelegate {
    var eventHandler: ((GuideSpeechEvent) -> Void)?
    private(set) var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, voice: GuideVoice, speed: Float, volume: Float) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice.appleVoiceIdentifier
            .flatMap(AVSpeechSynthesisVoice.init(identifier:))
            ?? Self.bestAvailableVoice(for: AppLanguage.speechLocale)
        utterance.rate = max(
            AVSpeechUtteranceMinimumSpeechRate,
            min(AVSpeechUtteranceMaximumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * speed)
        )
        utterance.volume = max(0, min(1, volume))

        do {
            try Self.activateAudioSession()
            isSpeaking = true
            synthesizer.speak(utterance)
        } catch {
            finishSpeaking()
        }
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

    private static func bestAvailableVoice(for locale: Locale) -> AVSpeechSynthesisVoice? {
        let targetLanguage = locale.language.languageCode?.identifier
        let targetRegion = locale.region?.identifier

        let languageVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { voice in
                let voiceLocale = Locale(identifier: voice.language)
                return voiceLocale.language.languageCode?.identifier == targetLanguage
                    && !voice.voiceTraits.contains(.isNoveltyVoice)
                    && !voice.voiceTraits.contains(.isPersonalVoice)
            }

        let regionalVoices = languageVoices.filter {
            Locale(identifier: $0.language).region?.identifier == targetRegion
        }
        let candidates = regionalVoices.isEmpty ? languageVoices : regionalVoices
        return candidates.max { qualityScore($0) < qualityScore($1) }
    }

    private static func qualityScore(_ voice: AVSpeechSynthesisVoice) -> Int {
        switch voice.quality {
        case .premium: 300
        case .enhanced: 200
        default: 100
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
