import Foundation
import AVFoundation
import Combine

@MainActor
private final class AudioSessionCoordinator {
    static let shared = AudioSessionCoordinator()

    private let session = AVAudioSession.sharedInstance()
    private var activeCoachUtterances = 0

    private init() {}

    func beginCoachSpeech() {
        activeCoachUtterances += 1
        guard activeCoachUtterances == 1 else { return }

        do {
            try session.setCategory(
                .playback,
                mode: .voicePrompt,
                options: [
                    .allowAirPlay,
                    .allowBluetooth,
                    .allowBluetoothA2DP,
                    .mixWithOthers,
                    .duckOthers
                ]
            )
            try session.setActive(true)
        } catch {
            activeCoachUtterances = 0
        }
    }

    func endCoachSpeech() {
        guard activeCoachUtterances > 0 else { return }
        activeCoachUtterances -= 1
        guard activeCoachUtterances == 0 else { return }

        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            activeCoachUtterances = 0
        }
    }
}

// On-device real-time coach that analyzes active session snapshots and speaks
// short nudges through the configured SessionAnalysisProvider.
@MainActor
final class VirtualCoach: NSObject, ObservableObject {
    @Published var lastNudge: String = ""
    @Published var latestAnalysis: SessionAnalysisResult?
    @Published var isAnalyzing = false
    @Published var providerName: String

    private let provider: any SessionAnalysisProvider
    private let fallbackProvider = RuleBasedSessionAnalysisProvider()
    private let synthesizer = AVSpeechSynthesizer()
    private let audioSessionCoordinator = AudioSessionCoordinator.shared
    private var profile: CoachProfile?
    private var persona: CoachPersona?
    private var sessionIntent: SessionIntent?
    private var snapshotHistory: [ActiveSessionSnapshot] = []
    private var analysisTask: Task<Void, Never>?
    private var lastAnalyzedElapsedSeconds: Int?
    private var isActive = false

    private let firstAnalysisAfterSeconds = 20
    private let maxSnapshotHistory = 20
    var speechEventHandler: ((CoachSpeechEvent) -> Void)?

    init(provider: (any SessionAnalysisProvider)? = nil) {
        let selectedProvider = provider ?? SessionAnalysisProviderFactory.makePreferredProvider()
        self.provider = selectedProvider
        providerName = selectedProvider.displayName
        super.init()
        synthesizer.delegate = self
    }

    func activate(
        with profile: CoachProfile?,
        persona: CoachPersona? = nil,
        sessionIntent: SessionIntent? = nil
    ) {
        self.profile = profile
        self.persona = persona
        self.sessionIntent = sessionIntent
        isActive = true
        snapshotHistory = []
        lastAnalyzedElapsedSeconds = nil
        lastNudge = sessionIntent?.coachLine ?? ""
        latestAnalysis = nil
        provider.beginSession(profile: profile, persona: persona)
        fallbackProvider.beginSession(profile: profile, persona: persona)
    }

    func deactivate() {
        isActive = false
        persona = nil
        sessionIntent = nil
        analysisTask?.cancel()
        analysisTask = nil
        isAnalyzing = false
        provider.endSession()
        fallbackProvider.endSession()
        synthesizer.stopSpeaking(at: .immediate)
        audioSessionCoordinator.endCoachSpeech()
    }

    func ingest(_ snapshot: ActiveSessionSnapshot) {
        guard isActive, snapshot.isActive else { return }

        snapshotHistory.append(snapshot)
        if snapshotHistory.count > maxSnapshotHistory {
            snapshotHistory.removeFirst(snapshotHistory.count - maxSnapshotHistory)
        }

        guard shouldAnalyze(snapshot) else { return }
        lastAnalyzedElapsedSeconds = snapshot.elapsedSeconds
        runAnalysis(for: snapshot)
    }

    // MARK: - Private

    private func shouldAnalyze(_ snapshot: ActiveSessionSnapshot) -> Bool {
        guard snapshot.elapsedSeconds >= firstAnalysisAfterSeconds else { return false }
        guard !isAnalyzing else { return false }

        guard let lastAnalyzedElapsedSeconds else {
            return true
        }

        return snapshot.elapsedSeconds - lastAnalyzedElapsedSeconds >= currentAnalysisIntervalSeconds
    }

    private func runAnalysis(for snapshot: ActiveSessionSnapshot) {
        let request = SessionAnalysisRequest(
            profile: profile,
            persona: persona,
            snapshot: snapshot,
            recentSnapshots: snapshotHistory
        )
        isAnalyzing = true

        analysisTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isAnalyzing = false
                self.analysisTask = nil
            }

            do {
                let analysis = try await self.provider.analyze(request)
                guard !Task.isCancelled else { return }
                self.apply(analysis)
            } catch {
                guard self.provider.identifier != self.fallbackProvider.identifier,
                      let fallback = try? await self.fallbackProvider.analyze(request),
                      !Task.isCancelled
                else {
                    return
                }
                self.apply(fallback)
            }
        }
    }

    private func apply(_ analysis: SessionAnalysisResult) {
        latestAnalysis = analysis
        guard !analysis.message.isEmpty else { return }

        lastNudge = analysis.message
        if analysis.shouldSpeak {
            speak(analysis.message)
        }
    }

    private func speak(_ text: String) {
        audioSessionCoordinator.beginCoachSpeech()
        let utterance = AVSpeechUtterance(string: text)
        if let voice = persona?.voice {
            if let identifier = voice.avFoundationIdentifier,
               let selectedVoice = AVSpeechSynthesisVoice(identifier: identifier) {
                utterance.voice = selectedVoice
            } else {
                utterance.voice = AVSpeechSynthesisVoice(language: voice.locale)
            }
            utterance.rate = voice.rate
            utterance.pitchMultiplier = voice.pitch
            utterance.volume = voice.volume
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = 0.5
            utterance.volume = 0.9
        }
        synthesizer.speak(utterance)
    }

    private var currentAnalysisIntervalSeconds: Int {
        persona?.nudgeFrequency.analysisIntervalSeconds ?? 75
    }
}

extension VirtualCoach: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.speechEventHandler?(.didStart)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.audioSessionCoordinator.endCoachSpeech()
            self?.speechEventHandler?(.didFinish)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.audioSessionCoordinator.endCoachSpeech()
            self?.speechEventHandler?(.didFinish)
        }
    }
}
