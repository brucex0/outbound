import Foundation
import AVFoundation

// On-device real-time coach that analyzes active session snapshots and speaks
// short nudges through the configured SessionAnalysisProvider.
@MainActor
final class VirtualCoach: ObservableObject {
    @Published var lastNudge: String = ""
    @Published var latestAnalysis: SessionAnalysisResult?
    @Published var isAnalyzing = false
    @Published var providerName: String

    private let provider: any SessionAnalysisProvider
    private let fallbackProvider = RuleBasedSessionAnalysisProvider()
    private let synthesizer = AVSpeechSynthesizer()
    private var profile: CoachProfile?
    private var snapshotHistory: [ActiveSessionSnapshot] = []
    private var analysisTask: Task<Void, Never>?
    private var lastAnalyzedElapsedSeconds: Int?
    private var isActive = false

    private let firstAnalysisAfterSeconds = 20
    private let analysisIntervalSeconds = 75
    private let maxSnapshotHistory = 20

    init(provider: (any SessionAnalysisProvider)? = nil) {
        let selectedProvider = provider ?? SessionAnalysisProviderFactory.makePreferredProvider()
        self.provider = selectedProvider
        providerName = selectedProvider.displayName
    }

    func activate(with profile: CoachProfile?) {
        self.profile = profile
        isActive = true
        snapshotHistory = []
        lastAnalyzedElapsedSeconds = nil
        lastNudge = ""
        latestAnalysis = nil
        provider.beginSession(profile: profile)
        fallbackProvider.beginSession(profile: profile)
    }

    func deactivate() {
        isActive = false
        analysisTask?.cancel()
        analysisTask = nil
        isAnalyzing = false
        provider.endSession()
        fallbackProvider.endSession()
        synthesizer.stopSpeaking(at: .immediate)
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

        return snapshot.elapsedSeconds - lastAnalyzedElapsedSeconds >= analysisIntervalSeconds
    }

    private func runAnalysis(for snapshot: ActiveSessionSnapshot) {
        let request = SessionAnalysisRequest(
            profile: profile,
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
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        utterance.volume = 0.9
        synthesizer.speak(utterance)
    }
}
