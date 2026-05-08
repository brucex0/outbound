import Foundation
import AVFoundation
import Combine

enum CoachSpeechEvent {
    case didStart
    case didFinish
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
    private var profile: CoachProfile?
    private var persona: CoachPersona?
    private var sessionIntent: SessionIntent?
    private var snapshotHistory: [ActiveSessionSnapshot] = []
    private var analysisTask: Task<Void, Never>?
    private var lastAnalyzedElapsedSeconds: Int?
    private var lastProgressAnnouncementElapsedSeconds: Int?
    private var lastProgressTimeMilestone = 0
    private var lastProgressDistanceMilestone = 0
    private var isActive = false
    private var recentSpokenFingerprints: [String] = []
    private var recentSpokenMessages: [String] = []

    private let firstAnalysisAfterSeconds = 20
    private let maxSnapshotHistory = 20
    private let maxRecentSpokenFingerprints = 4
    private let maxRecentSpokenMessages = 4
    private let minimumProgressAnnouncementGapSeconds = 30
    var speechEventHandler: ((CoachSpeechEvent) -> Void)?

    init(provider: (any SessionAnalysisProvider)? = nil) {
        let selectedProvider = provider ?? SessionAnalysisProviderFactory.makePreferredProvider()
        self.provider = selectedProvider
        providerName = selectedProvider.displayName
        super.init()
        // Apple documents this path as the synthesizer creating its own short-
        // lived session and automatically managing ducking and interruptions.
        #if os(iOS)
        synthesizer.usesApplicationAudioSession = false
        #endif
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
        lastProgressAnnouncementElapsedSeconds = nil
        lastProgressTimeMilestone = 0
        lastProgressDistanceMilestone = 0
        recentSpokenFingerprints = []
        recentSpokenMessages = []
        lastNudge = sessionIntent.map { Self.initialNudge(for: $0) } ?? ""
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
    }

    func ingest(_ snapshot: ActiveSessionSnapshot) {
        guard isActive, snapshot.isActive else { return }

        snapshotHistory.append(snapshot)
        if snapshotHistory.count > maxSnapshotHistory {
            snapshotHistory.removeFirst(snapshotHistory.count - maxSnapshotHistory)
        }

        announceProgressIfNeeded(for: snapshot)

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
            recentSnapshots: snapshotHistory,
            sessionIntent: sessionIntent,
            recentNudges: recentSpokenMessages
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
                self.apply(analysis, for: snapshot)
            } catch {
                guard self.provider.identifier != self.fallbackProvider.identifier,
                      let fallback = try? await self.fallbackProvider.analyze(request),
                      !Task.isCancelled
                else {
                    return
                }
                self.apply(fallback, for: snapshot)
            }
        }
    }

    private func apply(_ analysis: SessionAnalysisResult, for snapshot: ActiveSessionSnapshot) {
        latestAnalysis = analysis
        guard !analysis.message.isEmpty else { return }

        lastNudge = analysis.message
        guard analysis.shouldSpeak else { return }

        let fingerprint = normalizedFingerprint(for: analysis.message)
        guard !recentSpokenFingerprints.contains(fingerprint) else { return }

        recentSpokenFingerprints.append(fingerprint)
        if recentSpokenFingerprints.count > maxRecentSpokenFingerprints {
            recentSpokenFingerprints.removeFirst(recentSpokenFingerprints.count - maxRecentSpokenFingerprints)
        }
        recentSpokenMessages.append(analysis.message)
        if recentSpokenMessages.count > maxRecentSpokenMessages {
            recentSpokenMessages.removeFirst(recentSpokenMessages.count - maxRecentSpokenMessages)
        }

        speak(coachingAnnouncement(for: snapshot, message: analysis.message), urgency: analysis.urgency)
    }

    private func announceProgressIfNeeded(for snapshot: ActiveSessionSnapshot) {
        let timeInterval = currentProgressIntervalSeconds
        let distanceIntervalMeters = currentProgressDistanceIntervalMeters

        let nextTimeMilestone = snapshot.elapsedSeconds / timeInterval
        let nextDistanceMilestone = Int(snapshot.distanceMeters / distanceIntervalMeters)
        let reachedTimeMilestone = nextTimeMilestone > lastProgressTimeMilestone
        let reachedDistanceMilestone = nextDistanceMilestone > lastProgressDistanceMilestone

        guard reachedTimeMilestone || reachedDistanceMilestone else { return }

        if let lastProgressAnnouncementElapsedSeconds,
           snapshot.elapsedSeconds - lastProgressAnnouncementElapsedSeconds < minimumProgressAnnouncementGapSeconds {
            return
        }

        lastProgressTimeMilestone = nextTimeMilestone
        lastProgressDistanceMilestone = nextDistanceMilestone
        lastProgressAnnouncementElapsedSeconds = snapshot.elapsedSeconds
        speak(progressAnnouncement(for: snapshot))
    }

    private func progressAnnouncement(for snapshot: ActiveSessionSnapshot) -> String {
        var parts = [
            "Time \(snapshot.elapsedSeconds.spokenDurationString).",
            String(format: "Distance %.2f kilometers.", snapshot.distanceKilometers)
        ]

        if let pace = snapshot.currentPaceSecsPerKm {
            parts.append("Current pace \(pace.spokenPaceString).")
        } else {
            parts.append("Pace still settling.")
        }

        return parts.joined(separator: " ")
    }

    private func coachingAnnouncement(for snapshot: ActiveSessionSnapshot, message: String) -> String {
        "\(progressAnnouncement(for: snapshot)) \(message)"
    }

    private func speak(_ text: String, urgency: SessionAnalysisUrgency = .steady) {
        let utterance = AVSpeechUtterance(string: spokenText(for: text))
        if let voice = persona?.voice {
            utterance.voice = selectedSpeechVoice(for: voice)
            utterance.rate = adjustedRate(for: voice, urgency: urgency)
            utterance.pitchMultiplier = adjustedPitch(for: voice, urgency: urgency)
            utterance.volume = voice.volume
        } else {
            utterance.voice = preferredVoice(for: "en-US")
            utterance.rate = 0.47
            utterance.volume = 0.9
        }
        utterance.preUtteranceDelay = 0.06
        utterance.postUtteranceDelay = 0.12
        synthesizer.speak(utterance)
    }

    private var currentAnalysisIntervalSeconds: Int {
        persona?.nudgeFrequency.analysisIntervalSeconds ?? 75
    }

    private var currentProgressIntervalSeconds: Int {
        persona?.nudgeFrequency.progressAnnouncementIntervalSeconds ?? 180
    }

    private var currentProgressDistanceIntervalMeters: Double {
        switch persona?.template.sport ?? .run {
        case .run:
            1_000
        case .bike:
            5_000
        }
    }

    private func spokenText(for message: String) -> String {
        message
            .replacingOccurrences(of: ";", with: ", ")
            .replacingOccurrences(of: "—", with: ", ")
    }

    private func selectedSpeechVoice(for voice: CoachVoice) -> AVSpeechSynthesisVoice? {
        if let identifier = voice.avFoundationIdentifier,
           let selectedVoice = AVSpeechSynthesisVoice(identifier: identifier) {
            return selectedVoice
        }

        return preferredVoice(for: voice.locale) ?? AVSpeechSynthesisVoice(language: voice.locale)
    }

    private func preferredVoice(for locale: String) -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { candidate in
                candidate.language == locale || candidate.language.hasPrefix(locale.replacingOccurrences(of: "_", with: "-"))
            }
            .sorted { lhs, rhs in
                voiceScore(lhs) > voiceScore(rhs)
            }
            .first
    }

    private func voiceScore(_ voice: AVSpeechSynthesisVoice) -> Int {
        let qualityScore: Int
        switch voice.quality {
        case .premium:
            qualityScore = 30
        case .enhanced:
            qualityScore = 20
        default:
            qualityScore = 10
        }

        let siriBonus = voice.name.localizedCaseInsensitiveContains("Siri") ? 5 : 0
        return qualityScore + siriBonus
    }

    private func adjustedRate(for voice: CoachVoice, urgency: SessionAnalysisUrgency) -> Float {
        let delta: Float
        switch urgency {
        case .steady:
            delta = -0.03
        case .opportunity:
            delta = 0.0
        case .caution:
            delta = -0.05
        }

        return max(0.42, min(0.56, voice.rate + delta))
    }

    private func adjustedPitch(for voice: CoachVoice, urgency: SessionAnalysisUrgency) -> Float {
        let delta: Float
        switch urgency {
        case .steady:
            delta = 0.0
        case .opportunity:
            delta = 0.02
        case .caution:
            delta = -0.02
        }

        return max(0.9, min(1.2, voice.pitch + delta))
    }

    private func normalizedFingerprint(for message: String) -> String {
        message
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func initialNudge(for intent: SessionIntent) -> String {
        var parts = [intent.coachLine]

        if let targetDistance = intent.resolvedTargetDistanceMeters {
            parts.append("Goal: \(spokenDistance(targetDistance)).")
        } else if let targetDuration = intent.resolvedTargetDurationSeconds {
            parts.append("Goal: \(spokenDuration(targetDuration)).")
        } else if let routeName = intent.routeName, !routeName.isEmpty {
            parts.append("Route: \(routeName).")
        }

        return parts.joined(separator: " ")
    }

    private static func spokenDistance(_ meters: Double) -> String {
        if meters < 1000 {
            let roundedMeters = Int(meters.rounded())
            return roundedMeters == 1 ? "1 meter" : "\(roundedMeters) meters"
        }

        let kilometers = meters / 1000
        if abs(kilometers.rounded() - kilometers) < 0.05 {
            let roundedKilometers = Int(kilometers.rounded())
            return roundedKilometers == 1 ? "1 kilometer" : "\(roundedKilometers) kilometers"
        }

        return String(format: "%.1f kilometers", kilometers)
    }

    private static func spokenDuration(_ seconds: Int) -> String {
        if seconds >= 3600, seconds % 3600 == 0 {
            return "\(seconds / 3600) hours"
        }

        if seconds >= 3600 {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            return minutes > 0 ? "\(hours) hours \(minutes) minutes" : "\(hours) hours"
        }

        let minutes = max(1, Int((Double(seconds) / 60.0).rounded()))
        return "\(minutes) minutes"
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
            self?.speechEventHandler?(.didFinish)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.speechEventHandler?(.didFinish)
        }
    }
}
