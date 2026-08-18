import AVFoundation
import Foundation
import Combine

enum GuideSpeechEvent {
    case didStart
    case didFinish
}

private enum GuidanceMomentRole {
    case progress
    case form
    case hype
    case paceAdjustment
    case segment
    case finish
    case caution
}

private struct GuidanceMoment {
    let role: GuidanceMomentRole

    var includesProgressContext: Bool {
        switch role {
        case .progress, .segment, .finish:
            return true
        case .form, .hype, .paceAdjustment, .caution:
            return false
        }
    }
}

private enum GoalMilestone: Hashable {
    case distanceOneThird
    case distanceHalfway
    case distanceTwoThirds
    case distanceLastUnit
    case distance300MetersRemaining
    case distance100MetersRemaining
    case distanceComplete
    case durationOneThird
    case durationHalfway
    case durationTwoThirds
    case durationLastFiveMinutes
    case durationLastMinute
    case durationComplete

    var isFinishCue: Bool {
        switch self {
        case .distance300MetersRemaining, .distance100MetersRemaining, .distanceComplete,
             .durationComplete:
            return true
        default:
            return false
        }
    }
}

// On-device real-time guide that analyzes active session snapshots and speaks
// short nudges through the configured SessionAnalysisProvider.
@MainActor
final class VirtualGuide: NSObject, ObservableObject {
    @Published var lastNudge: String = ""
    @Published private(set) var lastSpokenAnnouncement: String = ""
    @Published var latestAnalysis: SessionAnalysisResult?
    @Published var isAnalyzing = false
    @Published var providerName: String

    private let provider: any SessionAnalysisProvider
    private let fallbackProvider = RuleBasedSessionAnalysisProvider()
    private let synthesizer = GuideSpeechSynthesizer()
    private let speechEnabled: Bool
    private var profile: GuideProfile?
    private var persona: GuidePersona?
    private var sessionIntent: SessionIntent?
    private var companionBrief: CompanionSessionBriefDTO?
    private var snapshotHistory: [ActiveSessionSnapshot] = []
    private var analysisTask: Task<Void, Never>?
    private var lastAnalyzedElapsedSeconds: Int?
    private var lastProgressAnnouncementElapsedSeconds: Int?
    private var lastProgressTimeMilestone = 0
    private var lastProgressDistanceMilestone = 0
    private var lastGuideSpeechElapsedSeconds: Int?
    private var isActive = false
    private var recentSpokenFingerprints: [String] = []
    private var recentSpokenMessages: [String] = []
    private var recentSpokenRoles: [GuidanceMomentRole] = []
    private var spokenGoalMilestones: Set<GoalMilestone> = []
    private var spokenTimedBoundaryCues: Set<String> = []

    private let firstAnalysisAfterSeconds = 75
    private let maxSnapshotHistory = 20
    private let maxRecentSpokenFingerprints = 4
    private let maxRecentSpokenMessages = 4
    private let maxRecentSpokenRoles = 4
    private let minimumProgressAnnouncementGapSeconds = 30
    private let minimumDistanceProgressElapsedSeconds = 30
    private let minimumProgressAnnouncementElapsedSeconds = 300
    private let minimumProgressAnnouncementDistanceMeters: Double = 400
    private let minimumGuideSpeechGapSeconds = 75
    private let maximumRunningProgressAverageSpeedMetersPerSecond: Double = 10
    private let maximumCyclingProgressAverageSpeedMetersPerSecond: Double = 25
    var speechEventHandler: ((GuideSpeechEvent) -> Void)?

    init(provider: (any SessionAnalysisProvider)? = nil, speechEnabled: Bool = true) {
        let selectedProvider = provider ?? SessionAnalysisProviderFactory.makePreferredProvider()
        self.provider = selectedProvider
        self.speechEnabled = speechEnabled
        providerName = selectedProvider.displayName
        super.init()
        synthesizer.eventHandler = { [weak self] event in
            self?.speechEventHandler?(event)
        }
    }

    func activate(
        with profile: GuideProfile?,
        persona: GuidePersona? = nil,
        sessionIntent: SessionIntent? = nil,
        companionBrief: CompanionSessionBriefDTO? = nil
    ) {
        self.profile = profile
        self.persona = persona
        self.sessionIntent = sessionIntent
        self.companionBrief = companionBrief
        isActive = true
        snapshotHistory = []
        lastAnalyzedElapsedSeconds = nil
        lastProgressAnnouncementElapsedSeconds = nil
        lastProgressTimeMilestone = 0
        lastProgressDistanceMilestone = 0
        lastGuideSpeechElapsedSeconds = nil
        recentSpokenFingerprints = []
        recentSpokenMessages = []
        recentSpokenRoles = []
        spokenGoalMilestones = []
        spokenTimedBoundaryCues = []
        lastNudge = sessionIntent.map { Self.initialNudge(for: $0) } ?? ""
        lastSpokenAnnouncement = ""
        latestAnalysis = nil
        provider.beginSession(profile: profile, persona: persona)
        fallbackProvider.beginSession(profile: profile, persona: persona)
    }

    func deactivate() {
        isActive = false
        persona = nil
        sessionIntent = nil
        companionBrief = nil
        analysisTask?.cancel()
        analysisTask = nil
        isAnalyzing = false
        provider.endSession()
        fallbackProvider.endSession()
        synthesizer.stopSpeaking(at: .immediate)
    }

    func updateCompanionBrief(_ brief: CompanionSessionBriefDTO) {
        companionBrief = brief
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

    func announceStartCountdown(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        speak(text, urgency: .opportunity)
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
            recentNudges: recentSpokenMessages,
            companionBrief: companionBrief
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
        let message = analysis.message.correctingPrematureCurrentDistanceClaims(
            currentDistanceMeters: snapshot.distanceMeters
        )
        guard !message.isEmpty else { return }

        lastNudge = message
        guard analysis.shouldSpeak else { return }

        let fingerprint = normalizedFingerprint(for: message)
        guard !recentSpokenFingerprints.contains(fingerprint) else { return }
        guard canSpeakGuideMoment(at: snapshot.elapsedSeconds, urgency: analysis.urgency) else { return }

        recentSpokenFingerprints.append(fingerprint)
        if recentSpokenFingerprints.count > maxRecentSpokenFingerprints {
            recentSpokenFingerprints.removeFirst(recentSpokenFingerprints.count - maxRecentSpokenFingerprints)
        }
        recentSpokenMessages.append(message)
        if recentSpokenMessages.count > maxRecentSpokenMessages {
            recentSpokenMessages.removeFirst(recentSpokenMessages.count - maxRecentSpokenMessages)
        }

        let moment = guidanceMoment(for: snapshot, analysis: analysis)
        if speak(
            guidanceAnnouncement(for: snapshot, message: message, moment: moment),
            urgency: analysis.urgency,
            role: moment.role
        ) {
            rememberGuideSpeech(at: snapshot.elapsedSeconds)
        }
    }

    private func announceProgressIfNeeded(for snapshot: ActiveSessionSnapshot) {
        if announceTimedBoundaryIfNeeded(for: snapshot) {
            return
        }

        if let goalMilestone = nextGoalMilestone(for: snapshot) {
            let isFinishCue = goalMilestone.isFinishCue
            guard isFinishCue || canAnnounceProgress(at: snapshot.elapsedSeconds) else { return }
            guard isFinishCue || canSpeakGuideMoment(at: snapshot.elapsedSeconds) else { return }

            if speakPriorityIfNeeded(goalProgressAnnouncement(for: goalMilestone), isPriority: isFinishCue) {
                spokenGoalMilestones.insert(goalMilestone)
                rememberProgressMilestones(for: snapshot)
                lastProgressAnnouncementElapsedSeconds = snapshot.elapsedSeconds
                rememberGuideSpeech(at: snapshot.elapsedSeconds)
            }
            return
        }

        let timeInterval = currentProgressIntervalSeconds
        let distanceIntervalMeters = currentProgressDistanceIntervalMeters

        let nextTimeMilestone = snapshot.elapsedSeconds / timeInterval
        let nextDistanceMilestone = Int(snapshot.distanceMeters / distanceIntervalMeters)
        let reachedTimeMilestone = nextTimeMilestone > lastProgressTimeMilestone
        let reachedDistanceMilestone = (
            nextDistanceMilestone > lastProgressDistanceMilestone
            && hasReliableDistanceProgress(snapshot)
        )

        guard reachedTimeMilestone || reachedDistanceMilestone else { return }

        guard canAnnounceProgress(at: snapshot.elapsedSeconds) else { return }
        guard shouldSpeakProgressAnnouncement(for: snapshot, reachedDistanceMilestone: reachedDistanceMilestone) else {
            lastProgressTimeMilestone = max(lastProgressTimeMilestone, nextTimeMilestone)
            return
        }

        lastProgressTimeMilestone = nextTimeMilestone
        lastProgressDistanceMilestone = nextDistanceMilestone
        if speak(progressAnnouncement(for: snapshot), role: .progress) {
            lastProgressAnnouncementElapsedSeconds = snapshot.elapsedSeconds
            rememberGuideSpeech(at: snapshot.elapsedSeconds)
        }
    }

    private func canAnnounceProgress(at elapsedSeconds: Int) -> Bool {
        guard let lastProgressAnnouncementElapsedSeconds else { return true }
        return elapsedSeconds - lastProgressAnnouncementElapsedSeconds >= minimumProgressAnnouncementGapSeconds
    }

    private func shouldSpeakProgressAnnouncement(
        for snapshot: ActiveSessionSnapshot,
        reachedDistanceMilestone: Bool
    ) -> Bool {
        if reachedDistanceMilestone {
            return canSpeakGuideMoment(at: snapshot.elapsedSeconds)
        }

        guard snapshot.elapsedSeconds >= minimumProgressAnnouncementElapsedSeconds else { return false }
        guard snapshot.distanceMeters >= minimumProgressAnnouncementDistanceMeters else { return false }
        return canSpeakGuideMoment(at: snapshot.elapsedSeconds)
    }

    private func rememberProgressMilestones(for snapshot: ActiveSessionSnapshot) {
        lastProgressTimeMilestone = snapshot.elapsedSeconds / currentProgressIntervalSeconds
        lastProgressDistanceMilestone = Int(snapshot.distanceMeters / currentProgressDistanceIntervalMeters)
    }

    private func nextGoalMilestone(for snapshot: ActiveSessionSnapshot) -> GoalMilestone? {
        if let distanceMilestone = nextDistanceGoalMilestone(for: snapshot) {
            return distanceMilestone
        }

        return nextDurationGoalMilestone(for: snapshot)
    }

    private func nextDistanceGoalMilestone(for snapshot: ActiveSessionSnapshot) -> GoalMilestone? {
        guard let targetDistance = sessionIntent?.resolvedTargetDistanceMeters, targetDistance > 0 else {
            return nil
        }
        guard hasReliableDistanceProgress(snapshot) else {
            return nil
        }

        let progress = snapshot.distanceMeters / targetDistance
        let remaining = targetDistance - snapshot.distanceMeters
        let lastUnitMeters = preferredLastDistanceUnitMeters(for: targetDistance)
        let candidates: [(GoalMilestone, Bool)] = [
            (.distanceComplete, progress >= 1),
            (.distance100MetersRemaining, targetDistance > 400 && remaining > 0 && remaining <= 100),
            (.distance300MetersRemaining, targetDistance > 600 && remaining > 100 && remaining <= 300),
            (.distanceLastUnit, targetDistance > lastUnitMeters * 1.5 && remaining > 0 && remaining <= lastUnitMeters),
            (.distanceTwoThirds, progress >= 2.0 / 3.0),
            (.distanceHalfway, progress >= 0.5),
            (.distanceOneThird, progress >= 1.0 / 3.0)
        ]

        return candidates.first { milestone, isReached in
            isReached && !spokenGoalMilestones.contains(milestone)
        }?.0
    }

    private func nextDurationGoalMilestone(for snapshot: ActiveSessionSnapshot) -> GoalMilestone? {
        guard let targetDuration = sessionIntent?.resolvedTargetDurationSeconds, targetDuration > 0 else {
            return nil
        }

        let progress = Double(snapshot.elapsedSeconds) / Double(targetDuration)
        let remaining = targetDuration - snapshot.elapsedSeconds
        let candidates: [(GoalMilestone, Bool)] = [
            (.durationComplete, progress >= 1),
            (.durationLastMinute, targetDuration > 120 && remaining > 0 && remaining <= 60),
            (.durationLastFiveMinutes, targetDuration > 600 && remaining > 60 && remaining <= 300),
            (.durationTwoThirds, progress >= 2.0 / 3.0),
            (.durationHalfway, progress >= 0.5),
            (.durationOneThird, progress >= 1.0 / 3.0)
        ]

        return candidates.first { milestone, isReached in
            isReached && !spokenGoalMilestones.contains(milestone)
        }?.0
    }

    private func goalProgressAnnouncement(for milestone: GoalMilestone) -> String {
        switch milestone {
        case .distanceOneThird:
            return "One third of your distance goal done. Keep it smooth."
        case .distanceHalfway:
            return "Halfway through your distance goal. Stay patient."
        case .distanceTwoThirds:
            return "Two thirds of the distance goal done. Keep stacking it."
        case .distanceLastUnit:
            let unitName = isMileBasedDistanceGoal(sessionIntent?.resolvedTargetDistanceMeters ?? 0) ? "mile" : "kilometer"
            return "Last \(unitName) of the distance goal. Stay tall."
        case .distance300MetersRemaining:
            return "300 meters to go."
        case .distance100MetersRemaining:
            return "100 meters to go."
        case .distanceComplete:
            return "Distance goal covered. Ease through the finish."
        case .durationOneThird:
            return "One third of your time goal done. Settle into the rhythm."
        case .durationHalfway:
            return "Halfway through your time goal. Keep the effort even."
        case .durationTwoThirds:
            return "Two thirds of the time goal done. Stay composed."
        case .durationLastFiveMinutes:
            return "Last 5 minutes of the time goal. Keep the rhythm calm."
        case .durationLastMinute:
            return "Last minute of the time goal. Finish steady."
        case .durationComplete:
            return "Time goal covered. Bring it down smoothly."
        }
    }

    private func announceTimedBoundaryIfNeeded(for snapshot: ActiveSessionSnapshot) -> Bool {
        guard let cue = nextTimedBoundaryCue(at: snapshot.elapsedSeconds) else { return false }
        synthesizer.stopSpeaking(at: .immediate)
        guard speak(cue.text, urgency: .opportunity, role: cue.isCompletion ? .finish : .segment) else {
            return false
        }
        spokenTimedBoundaryCues.insert(cue.id)
        lastProgressAnnouncementElapsedSeconds = snapshot.elapsedSeconds
        rememberGuideSpeech(at: snapshot.elapsedSeconds)
        if cue.isCompletion {
            spokenGoalMilestones.insert(.durationComplete)
        }
        return true
    }

    private func nextTimedBoundaryCue(at elapsedSeconds: Int) -> (id: String, text: String, isCompletion: Bool)? {
        guard let sessionIntent else { return nil }
        let steps = sessionIntent.workoutSteps.filter { $0.durationSeconds > 0 }
        let boundaries: [(seconds: Int, nextLabel: String?)]
        if steps.isEmpty {
            guard let duration = sessionIntent.resolvedTargetDurationSeconds, duration > 0 else { return nil }
            boundaries = [(duration, nil)]
        } else {
            var cumulative = 0
            boundaries = steps.enumerated().map { index, step in
                cumulative += step.durationSeconds
                return (cumulative, index + 1 < steps.count ? steps[index + 1].label : nil)
            }
        }

        for (index, boundary) in boundaries.enumerated() {
            let remaining = boundary.seconds - elapsedSeconds
            if (1...5).contains(remaining) {
                let id = "boundary-\(index)-count-\(remaining)"
                if !spokenTimedBoundaryCues.contains(id) {
                    return (id, "\(remaining)", false)
                }
            } else if remaining <= 0 {
                let id = "boundary-\(index)-complete"
                guard !spokenTimedBoundaryCues.contains(id) else { continue }
                if let nextLabel = boundary.nextLabel {
                    return (id, "Go. \(nextLabel).", false)
                }
                return (id, "Workout complete.", true)
            }
        }
        return nil
    }

    private func speakPriorityIfNeeded(_ text: String, isPriority: Bool) -> Bool {
        if isPriority {
            synthesizer.stopSpeaking(at: .immediate)
        }
        return speak(text, urgency: isPriority ? .opportunity : .steady, role: isPriority ? .finish : .progress)
    }

    private func preferredLastDistanceUnitMeters(for targetDistance: Double) -> Double {
        if isMileBasedDistanceGoal(targetDistance) {
            return 1_609.344
        }

        return 1_000
    }

    private func isMileBasedDistanceGoal(_ targetDistance: Double) -> Bool {
        let miles = targetDistance / 1_609.344
        let roundedMiles = miles.rounded()
        return roundedMiles >= 2 && abs(miles - roundedMiles) < 0.03
    }

    private func hasReliableDistanceProgress(_ snapshot: ActiveSessionSnapshot) -> Bool {
        guard snapshot.distanceMeters > 0 else { return false }
        guard snapshot.elapsedSeconds >= minimumDistanceProgressElapsedSeconds else { return false }

        let averageSpeed = snapshot.distanceMeters / Double(max(snapshot.elapsedSeconds, 1))
        return averageSpeed <= maximumReliableProgressAverageSpeedMetersPerSecond
    }

    private var maximumReliableProgressAverageSpeedMetersPerSecond: Double {
        switch persona?.template.sport ?? sessionIntent?.sport ?? .run {
        case .run:
            return maximumRunningProgressAverageSpeedMetersPerSecond
        case .bike:
            return maximumCyclingProgressAverageSpeedMetersPerSecond
        }
    }

    private func progressAnnouncement(for snapshot: ActiveSessionSnapshot) -> String {
        var parts: [String] = []

        if snapshot.elapsedSeconds >= 60 {
            parts.append("\(snapshot.elapsedSeconds.conversationalDurationString).")
        }

        if snapshot.distanceMeters >= minimumProgressAnnouncementDistanceMeters {
            parts.append("\(snapshot.distanceMeters.spokenDistanceString).")
        }

        if let pace = snapshot.currentPaceSecsPerKm {
            parts.append("Pace \(pace.spokenPaceString).")
        } else {
            parts.append("Pace still settling.")
        }

        return parts.isEmpty ? "Settle in and keep it easy." : parts.joined(separator: " ")
    }

    private func guidanceAnnouncement(
        for snapshot: ActiveSessionSnapshot,
        message: String,
        moment: GuidanceMoment
    ) -> String {
        guard moment.includesProgressContext else { return message }
        return "\(progressAnnouncement(for: snapshot)) \(message)"
    }

    @discardableResult
    private func speak(
        _ text: String,
        urgency: SessionAnalysisUrgency = .steady,
        role: GuidanceMomentRole? = nil
    ) -> Bool {
        let announcement = spokenText(for: text)
        if speechEnabled, synthesizer.isSpeaking {
            guard urgency == .caution else { return false }
            synthesizer.stopSpeaking(at: .currentWord)
        }

        lastSpokenAnnouncement = announcement
        if let role {
            rememberSpokenRole(role)
        }
        guard speechEnabled else { return true }

        let voice = persona?.voice ?? GuideVoice.defaultOption
        synthesizer.speak(
            announcement,
            voice: voice,
            rate: speechRate(for: voice, urgency: urgency),
            volume: voice.volume
        )
        return true
    }

    private func canSpeakGuideMoment(
        at elapsedSeconds: Int,
        urgency: SessionAnalysisUrgency = .steady
    ) -> Bool {
        guard urgency != .caution else { return true }
        guard let lastGuideSpeechElapsedSeconds else { return true }
        return elapsedSeconds - lastGuideSpeechElapsedSeconds >= minimumGuideSpeechGapSeconds
    }

    private func rememberGuideSpeech(at elapsedSeconds: Int) {
        lastGuideSpeechElapsedSeconds = elapsedSeconds
    }

    private func guidanceMoment(
        for snapshot: ActiveSessionSnapshot,
        analysis: SessionAnalysisResult
    ) -> GuidanceMoment {
        let role = preferredGuidanceMomentRole(for: snapshot, analysis: analysis)
        return GuidanceMoment(role: role)
    }

    private func preferredGuidanceMomentRole(
        for snapshot: ActiveSessionSnapshot,
        analysis: SessionAnalysisResult
    ) -> GuidanceMomentRole {
        if analysis.urgency == .caution || (snapshot.heartRate ?? 0) > 185 {
            return .caution
        }

        if isNearFinish(snapshot) {
            return .finish
        }

        if isSegmentCheckIn(snapshot) {
            return .segment
        }

        if analysis.urgency == .opportunity {
            return .paceAdjustment
        }

        if shouldUseProgressRole(for: snapshot) {
            return .progress
        }

        let naturalRole: GuidanceMomentRole = recentSpokenRoles.last == .hype ? .form : .hype
        if roleWouldRepeatTooMuch(naturalRole) {
            return naturalRole == .hype ? .form : .hype
        }
        return naturalRole
    }

    private func shouldUseProgressRole(for snapshot: ActiveSessionSnapshot) -> Bool {
        guard snapshot.elapsedSeconds >= currentProgressIntervalSeconds else { return false }
        guard !roleWouldRepeatTooMuch(.progress) else { return false }

        let nearTimeMilestone = snapshot.elapsedSeconds % currentProgressIntervalSeconds <= 8
        let completedDistanceMilestone = Int(snapshot.distanceMeters / currentProgressDistanceIntervalMeters)
        let distanceRemainder = snapshot.distanceMeters.truncatingRemainder(dividingBy: currentProgressDistanceIntervalMeters)
        let nearDistanceMilestone = completedDistanceMilestone > 0 && distanceRemainder <= 80
        return nearTimeMilestone || nearDistanceMilestone
    }

    private func isNearFinish(_ snapshot: ActiveSessionSnapshot) -> Bool {
        if let targetDistance = sessionIntent?.resolvedTargetDistanceMeters, targetDistance > 0 {
            return targetDistance - snapshot.distanceMeters <= 400
        }
        if let targetDuration = sessionIntent?.resolvedTargetDurationSeconds, targetDuration > 0 {
            return targetDuration - snapshot.elapsedSeconds <= 120
        }
        return false
    }

    private func isSegmentCheckIn(_ snapshot: ActiveSessionSnapshot) -> Bool {
        guard let sessionIntent else { return false }
        let timedSteps = sessionIntent.workoutSteps.filter { $0.durationSeconds > 0 }
        guard timedSteps.count > 1 else { return false }
        let elapsedInWorkout = timedSteps.reduce(snapshot.elapsedSeconds) { remaining, step in
            remaining >= step.durationSeconds ? remaining - step.durationSeconds : remaining
        }
        return elapsedInWorkout <= 12
    }

    private func roleWouldRepeatTooMuch(_ role: GuidanceMomentRole) -> Bool {
        recentSpokenRoles.suffix(2).allSatisfy { $0 == role } && recentSpokenRoles.count >= 2
    }

    private func rememberSpokenRole(_ role: GuidanceMomentRole) {
        recentSpokenRoles.append(role)
        if recentSpokenRoles.count > maxRecentSpokenRoles {
            recentSpokenRoles.removeFirst(recentSpokenRoles.count - maxRecentSpokenRoles)
        }
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

    private func speechRate(for voice: GuideVoice, urgency: SessionAnalysisUrgency) -> Float {
        let delta: Float
        switch urgency {
        case .steady:
            delta = -0.04
        case .opportunity:
            delta = 0.03
        case .caution:
            delta = -0.08
        }
        return max(
            AVSpeechUtteranceMinimumSpeechRate,
            min(AVSpeechUtteranceMaximumSpeechRate, voice.rate + delta)
        )
    }

    private func normalizedFingerprint(for message: String) -> String {
        message
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func initialNudge(for intent: SessionIntent) -> String {
        var parts = [intent.guideLine]

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
        meters.spokenDistanceString
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
