import Foundation
import Combine

enum GuideSpeechEvent {
    case didStart
    case didFinish
}

enum RouteGuidanceSpeechPriority: Equatable {
    case advisory
    case caution
    case arrival
}

private enum GuidanceMomentRole {
    case progress
    case form
    case hype
    case paceAdjustment
    case segment
    case breakStatus
    case finish
    case caution
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
    @Published private(set) var sessionReport: LiveGuidanceSessionReport = .empty

    private let provider: any SessionAnalysisProvider
    private let audioPlayer = GuideAudioPlayer()
    private let momentDirector = LiveGuidanceDirector()
    private var speechEnabled: Bool
    private var profile: GuideProfile?
    private var persona: GuidePersona?
    private var sessionIntent: SessionIntent?
    private var companionBrief: CompanionSessionBriefDTO?
    private var unitSystem: MeasurementUnitSystem = .metric
    private var snapshotHistory: [ActiveSessionSnapshot] = []
    private var analysisTask: Task<Void, Never>?
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
    private var lastObservedDistanceMilestone = 0
    private var lastObservedDistanceCheckpoint: (distanceMeters: Double, elapsedSeconds: Int)?
    private var latestDistanceCheckpointPace: Double?
    private var lastRouteGuidanceFingerprint: String?
    private var lastRouteGuidanceSpokenAt: Date?
    private var routeSpeechQuietUntil: Date?
    private var pendingMoment: DetectedLiveGuidanceMoment?
    private var queuedMoments: [DetectedLiveGuidanceMoment] = []

    private let maxSnapshotHistory = 240
    private let maxRecentSpokenFingerprints = 4
    private let maxRecentSpokenMessages = 4
    private let maxRecentSpokenRoles = 4
    private let minimumProgressAnnouncementGapSeconds = 30
    private let minimumDistanceProgressElapsedSeconds = 30
    private let minimumProgressAnnouncementElapsedSeconds = 300
    private let minimumProgressAnnouncementDistanceMeters: Double = 400
    private let minimumGuideSpeechGapSeconds = 75
    private let minimumStatSpeechGapSeconds = 20
    private let maximumRunningProgressAverageSpeedMetersPerSecond: Double = 10
    private let maximumCyclingProgressAverageSpeedMetersPerSecond: Double = 25
    var speechEventHandler: ((GuideSpeechEvent) -> Void)?
    var guidanceEventHandler: ((LiveGuidanceTelemetryEvent) -> Void)?

    init(provider: (any SessionAnalysisProvider)? = nil, speechEnabled: Bool = true) {
        let selectedProvider = provider ?? SessionAnalysisProviderFactory.makePreferredProvider()
        self.provider = selectedProvider
        self.speechEnabled = speechEnabled
        providerName = selectedProvider.displayName
        super.init()
        audioPlayer.eventHandler = { [weak self] event in
            self?.speechEventHandler?(event)
        }
        audioPlayer.playbackRouteHandler = { [weak self] route in
            self?.guidanceEventHandler?(.audioPlaybackRoute(route: route))
        }
    }

    func setSpeechEnabled(_ isEnabled: Bool) {
        speechEnabled = isEnabled
        if !isEnabled {
            audioPlayer.stopSpeaking(at: .immediate)
        }
    }

    func activate(
        with profile: GuideProfile?,
        persona: GuidePersona? = nil,
        sessionIntent: SessionIntent? = nil,
        companionBrief: CompanionSessionBriefDTO? = nil,
        unitSystem: MeasurementUnitSystem = .metric,
        weatherSnapshot: RunningWeatherSnapshot? = nil,
        isIndoor: Bool = false,
        challenge: LiveGuidanceChallenge = .off,
        suppressedMomentTypes: Set<LiveGuidanceMomentType> = []
    ) {
        self.profile = profile
        self.persona = persona
        self.sessionIntent = sessionIntent
        self.companionBrief = companionBrief
        self.unitSystem = unitSystem
        audioPlayer.pinOnDeviceVoice(presentation: persona?.voice.presentation)
        isActive = true
        snapshotHistory = []
        lastProgressAnnouncementElapsedSeconds = nil
        lastProgressTimeMilestone = 0
        lastProgressDistanceMilestone = 0
        lastGuideSpeechElapsedSeconds = nil
        recentSpokenFingerprints = []
        recentSpokenMessages = []
        recentSpokenRoles = []
        spokenGoalMilestones = []
        spokenTimedBoundaryCues = []
        lastObservedDistanceMilestone = 0
        lastObservedDistanceCheckpoint = nil
        latestDistanceCheckpointPace = nil
        lastRouteGuidanceFingerprint = nil
        lastRouteGuidanceSpokenAt = nil
        routeSpeechQuietUntil = nil
        pendingMoment = nil
        queuedMoments = []
        lastNudge = sessionIntent.map { Self.initialNudge(for: $0, unitSystem: unitSystem) } ?? ""
        lastSpokenAnnouncement = ""
        latestAnalysis = nil
        sessionReport = LiveGuidanceSessionReport(
            coachingContract: persona?.coachingContract ?? .responsive,
            challenge: challenge,
            cues: []
        )
        momentDirector.reset(
            contract: persona?.coachingContract ?? .responsive,
            challenge: challenge,
            suppressedMomentTypes: suppressedMomentTypes
        )
        provider.beginSession(
            profile: profile,
            persona: persona,
            sessionIntent: sessionIntent,
            companionBrief: companionBrief,
            unitSystem: unitSystem,
            weatherSnapshot: weatherSnapshot,
            isIndoor: isIndoor
        )
    }

    func deactivate() {
        isActive = false
        persona = nil
        sessionIntent = nil
        companionBrief = nil
        analysisTask?.cancel()
        analysisTask = nil
        isAnalyzing = false
        provider.endSession(report: sessionReport)
        audioPlayer.stopSpeaking(at: .immediate)
        audioPlayer.pinOnDeviceVoice(presentation: nil)
    }

    func finalizedSessionReport() -> LiveGuidanceSessionReport {
        let report = momentDirector.report(finalizing: true)
        sessionReport = report
        return report
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
        let update = momentDirector.ingest(snapshot, profile: profile, intent: sessionIntent)
        update.evaluatedCues.forEach { record in
            guidanceEventHandler?(.cueEvaluated(type: record.momentType, outcome: record.outcome))
        }
        sessionReport = momentDirector.report(finalizing: false)

        if let moment = update.nextMoment {
            guidanceEventHandler?(.momentDetected(
                type: moment.type,
                contract: persona?.coachingContract ?? .responsive
            ))
            if pendingMoment == nil {
                pendingMoment = moment
            } else if pendingMoment?.type != moment.type,
                      !queuedMoments.contains(where: { $0.type == moment.type }) {
                queuedMoments.append(moment)
            }
        }
        processPendingMoment(using: snapshot)
    }

    func handleRecordingStateTransition(
        from previousState: RecordingState,
        to state: RecordingState,
        autoPaused: Bool,
        snapshot: ActiveSessionSnapshot
    ) {
        guard isActive, autoPaused else { return }
        let momentType: LiveGuidanceMomentType
        let message: String
        let cueKey: String
        switch (previousState, state) {
        case (.active, .paused):
            momentType = .unexpectedStop
            message = String(localized: "live_guidance.auto_pause", defaultValue: "Workout paused.")
            cueKey = "workout.pause"
        case (.paused, .active):
            momentType = .resumeAfterBreak
            message = String(localized: "live_guidance.auto_resume", defaultValue: "Workout resumed.")
            cueKey = "workout.resume"
        default:
            return
        }

        guidanceEventHandler?(.momentDetected(
            type: momentType,
            contract: persona?.coachingContract ?? .responsive
        ))
        guard speak(message, urgency: .caution, role: .breakStatus, fixedCueKey: cueKey) else { return }
        rememberGuideSpeech(at: snapshot.elapsedSeconds)
        _ = momentDirector.recordSystemCue(type: momentType, elapsedSeconds: snapshot.elapsedSeconds)
        sessionReport = momentDirector.report(finalizing: false)
        guidanceEventHandler?(.cueSpoken(
            type: momentType,
            contract: persona?.coachingContract ?? .responsive
        ))
    }

    func announceStartCountdown(_ texts: [String]) {
        guard speechEnabled else { return }
        let keys = ["countdown.three", "countdown.two", "countdown.one", "countdown.go"]
        Task { @MainActor [weak self] in
            guard let self else { return }
            var clips: [Data] = []
            for (index, key) in keys.enumerated() {
                let transcript = texts.indices.contains(index) ? texts[index] : nil
                guard let data = await GuideAudioPackStore.shared.audioData(for: key, transcript: transcript) else {
                    return
                }
                clips.append(data)
            }
            guard self.speechEnabled else { return }
            self.audioPlayer.playSequence(clips)
        }
    }

    func announceRouteGuidance(
        _ message: String,
        priority: RouteGuidanceSpeechPriority = .caution,
        semanticCueKey: String? = nil
    ) {
        guard isActive, !message.isEmpty else { return }
        lastNudge = message
        let fingerprint = normalizedFingerprint(for: message)
        if lastRouteGuidanceFingerprint == fingerprint,
           let lastRouteGuidanceSpokenAt,
           Date().timeIntervalSince(lastRouteGuidanceSpokenAt) < 90 {
            return
        }
        if priority == .advisory, speechEnabled, audioPlayer.isSpeaking {
            return
        }
        let urgency: SessionAnalysisUrgency = priority == .advisory ? .steady : .caution
        let defaultCueKey = switch priority {
        case .advisory: "route.advisory"
        case .caution: "route.caution"
        case .arrival: "route.arrival"
        }
        let cueKey = semanticCueKey ?? defaultCueKey
        if speak(
            message,
            urgency: urgency,
            role: priority == .advisory ? nil : .caution,
            fixedCueKey: cueKey
        ) {
            lastRouteGuidanceFingerprint = fingerprint
            lastRouteGuidanceSpokenAt = Date()
            routeSpeechQuietUntil = Date().addingTimeInterval(TimeInterval(minimumGuideSpeechGapSeconds))
            recentSpokenMessages.append(message)
            if recentSpokenMessages.count > maxRecentSpokenMessages {
                recentSpokenMessages.removeFirst(recentSpokenMessages.count - maxRecentSpokenMessages)
            }
        }
    }

    // MARK: - Private

    private func processPendingMoment(using snapshot: ActiveSessionSnapshot) {
        guard let moment = pendingMoment,
              !isAnalyzing,
              routeSpeechQuietUntil.map({ Date() >= $0 }) ?? true,
              canSpeakPendingMoment(moment, at: snapshot.elapsedSeconds)
        else { return }

        pendingMoment = nil
        runAnalysis(for: snapshot, moment: moment)
    }

    private func runAnalysis(
        for snapshot: ActiveSessionSnapshot,
        moment: DetectedLiveGuidanceMoment
    ) {
        let request = SessionAnalysisRequest(
            profile: profile,
            persona: persona,
            snapshot: snapshot,
            recentSnapshots: snapshotHistory,
            sessionIntent: sessionIntent,
            companionBrief: companionBrief,
            momentType: moment.type,
            preferredMessage: moment.preferredMessage,
            routeGuidanceActive: routeSpeechQuietUntil.map { Date() < $0 } ?? false
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
                self.guidanceEventHandler?(.providerResult(
                    source: analysis.source,
                    result: analysis.result,
                    mode: analysis.effectiveMode,
                    accessReason: analysis.accessReason,
                    latency: analysis.latencyBucket
                ))
                self.apply(analysis, for: snapshot, moment: moment)
            } catch {
                guard !(error is CancellationError) else { return }
                self.guidanceEventHandler?(.providerResult(
                    source: .cachedFallback,
                    result: .unavailable,
                    mode: .disabled,
                    accessReason: .featureDisabled,
                    latency: .fourSecondsPlus
                ))
                self.advancePendingMoment()
            }
        }
    }

    private func apply(
        _ analysis: SessionAnalysisResult,
        for snapshot: ActiveSessionSnapshot,
        moment: DetectedLiveGuidanceMoment
    ) {
        latestAnalysis = analysis
        guard analysis.expiresAt > Date() else {
            guidanceEventHandler?(.providerResult(
                source: analysis.source,
                result: .stale,
                mode: analysis.effectiveMode,
                accessReason: analysis.accessReason,
                latency: analysis.latencyBucket
            ))
            if pendingMoment == nil { advancePendingMoment() }
            return
        }
        let message = analysis.message.correctingPrematureCurrentDistanceClaims(
            currentDistanceMeters: snapshot.distanceMeters,
            unitSystem: unitSystem
        )
        guard !message.isEmpty, analysis.shouldSpeak else {
            if pendingMoment == nil { advancePendingMoment() }
            return
        }

        lastNudge = message

        let fingerprint = normalizedFingerprint(for: message)
        guard !recentSpokenFingerprints.contains(fingerprint) else { return }
        guard canSpeakGuideMoment(at: snapshot.elapsedSeconds, urgency: analysis.urgency) else {
            pendingMoment = DetectedLiveGuidanceMoment(
                type: moment.type,
                detectedAtElapsedSeconds: snapshot.elapsedSeconds,
                baselinePaceSecondsPerKilometer: moment.baselinePaceSecondsPerKilometer,
                targetPaceSecondsPerKilometer: moment.targetPaceSecondsPerKilometer,
                evaluationDelaySeconds: moment.evaluationDelaySeconds,
                preferredMessage: message
            )
            return
        }

        recentSpokenFingerprints.append(fingerprint)
        if recentSpokenFingerprints.count > maxRecentSpokenFingerprints {
            recentSpokenFingerprints.removeFirst(recentSpokenFingerprints.count - maxRecentSpokenFingerprints)
        }
        recentSpokenMessages.append(message)
        if recentSpokenMessages.count > maxRecentSpokenMessages {
            recentSpokenMessages.removeFirst(recentSpokenMessages.count - maxRecentSpokenMessages)
        }

        if speak(
            message,
            urgency: analysis.urgency,
            role: role(for: moment.type),
            fixedCueKey: analysis.fixedCueKey,
            audioData: analysis.audioData,
            audioStream: analysis.audioStream
        ) {
            rememberGuideSpeech(at: snapshot.elapsedSeconds)
            recordSpokenMoment(moment, spokenAtElapsedSeconds: snapshot.elapsedSeconds)
            if pendingMoment == nil { advancePendingMoment() }
        } else {
            pendingMoment = DetectedLiveGuidanceMoment(
                type: moment.type,
                detectedAtElapsedSeconds: snapshot.elapsedSeconds,
                baselinePaceSecondsPerKilometer: moment.baselinePaceSecondsPerKilometer,
                targetPaceSecondsPerKilometer: moment.targetPaceSecondsPerKilometer,
                evaluationDelaySeconds: moment.evaluationDelaySeconds,
                preferredMessage: message
            )
        }
    }

    private func recordSpokenMoment(
        _ moment: DetectedLiveGuidanceMoment,
        spokenAtElapsedSeconds: Int
    ) {
        let spokenMoment = DetectedLiveGuidanceMoment(
            type: moment.type,
            detectedAtElapsedSeconds: spokenAtElapsedSeconds,
            baselinePaceSecondsPerKilometer: moment.baselinePaceSecondsPerKilometer,
            targetPaceSecondsPerKilometer: moment.targetPaceSecondsPerKilometer,
            evaluationDelaySeconds: moment.evaluationDelaySeconds,
            preferredMessage: moment.preferredMessage
        )
        _ = momentDirector.recordSpoken(spokenMoment)
        sessionReport = momentDirector.report(finalizing: false)
        guidanceEventHandler?(.cueSpoken(
            type: moment.type,
            contract: persona?.coachingContract ?? .responsive
        ))
    }

    private func canSpeakPendingMoment(
        _ moment: DetectedLiveGuidanceMoment,
        at elapsedSeconds: Int
    ) -> Bool {
        if moment.type == .challengeComplete || moment.type == .segmentTransition {
            return canSpeakProgressUpdate(at: elapsedSeconds)
        }
        return canSpeakGuideMoment(at: elapsedSeconds, urgency: .opportunity)
    }

    private func advancePendingMoment() {
        pendingMoment = queuedMoments.isEmpty ? nil : queuedMoments.removeFirst()
    }

    private func role(for type: LiveGuidanceMomentType) -> GuidanceMomentRole {
        switch type {
        case .progress: .progress
        case .earlyOverpace, .paceAboveTarget, .paceBelowTarget, .paceInstability,
             .paceDrift, .recoveryTooHard: .paceAdjustment
        case .targetLocked, .rhythmRecovery, .crestRecovery,
             .challengeStart, .challengeComplete: .hype
        case .unexpectedStop, .resumeAfterBreak: .breakStatus
        case .climbStart: .form
        case .segmentTransition: .segment
        case .finishOpportunity: .finish
        }
    }

    private static func fixedCueKey(for milestone: GoalMilestone) -> String {
        switch milestone {
        case .distanceOneThird, .durationOneThird: "progress.one_third"
        case .distanceHalfway, .durationHalfway: "progress.halfway"
        case .distanceTwoThirds, .durationTwoThirds: "progress.two_thirds"
        case .distanceLastUnit, .distance300MetersRemaining, .distance100MetersRemaining,
             .durationLastFiveMinutes, .durationLastMinute: "progress.finish_soon"
        case .distanceComplete, .durationComplete: "workout.complete"
        }
    }

    private static func countdownCueKey(for text: String) -> String? {
        switch text.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "3": "countdown.three"
        case "2": "countdown.two"
        case "1": "countdown.one"
        default: nil
        }
    }

    private func announceProgressIfNeeded(for snapshot: ActiveSessionSnapshot) {
        observeDistanceCheckpoint(for: snapshot)
        guard routeSpeechQuietUntil.map({ Date() >= $0 }) ?? true else { return }
        if announceTimedBoundaryIfNeeded(for: snapshot) {
            return
        }

        if let goalMilestone = nextGoalMilestone(for: snapshot) {
            let isFinishCue = goalMilestone.isFinishCue
            guard isFinishCue || canAnnounceProgress(at: snapshot.elapsedSeconds) else { return }
            guard isFinishCue || canSpeakProgressUpdate(at: snapshot.elapsedSeconds) else { return }

            let announcement = goalProgressAnnouncement(for: goalMilestone, snapshot: snapshot)
            if isFinishCue {
                guard speakPriorityIfNeeded(
                    announcement,
                    isPriority: true,
                    fixedCueKey: Self.fixedCueKey(for: goalMilestone)
                ) else { return }
                spokenGoalMilestones.insert(goalMilestone)
                rememberProgressMilestones(for: snapshot)
                lastProgressAnnouncementElapsedSeconds = snapshot.elapsedSeconds
                rememberGuideSpeech(at: snapshot.elapsedSeconds)
            } else {
                spokenGoalMilestones.insert(goalMilestone)
                rememberProgressMilestones(for: snapshot)
                lastProgressAnnouncementElapsedSeconds = snapshot.elapsedSeconds
                requestProgressAnalysis(for: snapshot, localAnnouncement: announcement)
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
        let checkpointPace = progressPace(
            for: snapshot,
            reachedDistanceMilestone: reachedDistanceMilestone
        )
        let includesAveragePace = reachedDistanceMilestone
            && nextDistanceMilestone > 0
            && Int((Double(nextDistanceMilestone) * distanceIntervalMeters).rounded()) % 5_000 == 0

        let announcement = progressAnnouncement(
            for: snapshot,
            pace: checkpointPace,
            includesAveragePace: includesAveragePace
        )
        lastProgressAnnouncementElapsedSeconds = snapshot.elapsedSeconds
        requestProgressAnalysis(for: snapshot, localAnnouncement: announcement)
    }

    private func requestProgressAnalysis(
        for snapshot: ActiveSessionSnapshot,
        localAnnouncement: String
    ) {
        lastNudge = localAnnouncement
        let moment = DetectedLiveGuidanceMoment(
            type: .progress,
            detectedAtElapsedSeconds: snapshot.elapsedSeconds,
            preferredMessage: localAnnouncement
        )
        guidanceEventHandler?(.momentDetected(
            type: .progress,
            contract: persona?.coachingContract ?? .responsive
        ))
        if pendingMoment == nil {
            pendingMoment = moment
        } else if pendingMoment?.type != .progress,
                  !queuedMoments.contains(where: { $0.type == .progress }) {
            queuedMoments.append(moment)
        }
        processPendingMoment(using: snapshot)
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
            return canSpeakProgressUpdate(at: snapshot.elapsedSeconds)
        }

        guard snapshot.elapsedSeconds >= minimumProgressAnnouncementElapsedSeconds else { return false }
        guard snapshot.distanceMeters >= minimumProgressAnnouncementDistanceMeters else { return false }
        return canSpeakProgressUpdate(at: snapshot.elapsedSeconds)
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
        let lastUnitMeters = preferredLastDistanceUnitMeters
        let shortDistanceMeters = unitSystem == .metric ? 100.0 : 160.9344
        let mediumDistanceMeters = unitSystem == .metric ? 300.0 : 402.336
        let candidates: [(GoalMilestone, Bool)] = [
            (.distanceComplete, progress >= 1),
            (.distance100MetersRemaining, targetDistance > shortDistanceMeters * 4 && remaining > 0 && remaining <= shortDistanceMeters),
            (.distance300MetersRemaining, targetDistance > mediumDistanceMeters * 2 && remaining > shortDistanceMeters && remaining <= mediumDistanceMeters),
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

    private func goalProgressAnnouncement(
        for milestone: GoalMilestone,
        snapshot: ActiveSessionSnapshot
    ) -> String {
        let lastUnitName = unitSystem == .imperial ? "mile" : "kilometer"
        let message = switch milestone {
        case .distanceOneThird:
            "One third of your distance goal done. Keep it smooth."
        case .distanceHalfway:
            "Halfway through your distance goal. Stay patient."
        case .distanceTwoThirds:
            "Two thirds of the distance goal done. Keep stacking it."
        case .distanceLastUnit:
            "Last \(lastUnitName) of the distance goal. Stay tall."
        case .distance300MetersRemaining:
            "\(unitSystem.spokenDistanceString(meters: unitSystem == .metric ? 300 : 402.336)) to go."
        case .distance100MetersRemaining:
            "\(unitSystem.spokenDistanceString(meters: unitSystem == .metric ? 100 : 160.9344)) to go."
        case .distanceComplete:
            "Distance goal covered. Ease through the finish."
        case .durationOneThird:
            "One third of your time goal done. Settle into the rhythm."
        case .durationHalfway:
            "Halfway through your time goal. Keep the effort even."
        case .durationTwoThirds:
            "Two thirds of the time goal done. Stay composed."
        case .durationLastFiveMinutes:
            "Last 5 minutes of the time goal. Keep the rhythm calm."
        case .durationLastMinute:
            "Last minute of the time goal. Finish steady."
        case .durationComplete:
            "Time goal covered. Bring it down smoothly."
        }

        switch milestone {
        case .distanceHalfway, .distanceTwoThirds, .distanceComplete,
             .durationHalfway, .durationTwoThirds, .durationComplete:
            let summary = keyProgressSummary(for: snapshot)
            return summary.isEmpty ? message : "\(message) \(summary)"
        default:
            return message
        }
    }

    private func announceTimedBoundaryIfNeeded(for snapshot: ActiveSessionSnapshot) -> Bool {
        guard var cue = nextTimedBoundaryCue(at: snapshot.elapsedSeconds) else { return false }
        if cue.isCompletion {
            let summary = keyProgressSummary(for: snapshot)
            if !summary.isEmpty {
                cue.text += " \(summary)"
            }
        }
        audioPlayer.stopSpeaking(at: .immediate)
        let cueKey = cue.isCompletion ? "workout.complete"
            : cue.isSegmentTransition ? "workout.segment_start"
            : Self.countdownCueKey(for: cue.text)
        guard speak(
            cue.text,
            urgency: .opportunity,
            role: cue.isCompletion ? .finish : .segment,
            fixedCueKey: cueKey
        ) else {
            return false
        }
        spokenTimedBoundaryCues.insert(cue.id)
        lastProgressAnnouncementElapsedSeconds = snapshot.elapsedSeconds
        rememberGuideSpeech(at: snapshot.elapsedSeconds)
        if cue.isCompletion {
            spokenGoalMilestones.insert(.durationComplete)
        }
        if cue.isSegmentTransition {
            let contract = persona?.coachingContract ?? .responsive
            guidanceEventHandler?(.momentDetected(type: .segmentTransition, contract: contract))
            _ = momentDirector.recordSystemCue(
                type: .segmentTransition,
                elapsedSeconds: snapshot.elapsedSeconds
            )
            sessionReport = momentDirector.report(finalizing: false)
            guidanceEventHandler?(.cueSpoken(type: .segmentTransition, contract: contract))
        }
        return true
    }

    private func nextTimedBoundaryCue(
        at elapsedSeconds: Int
    ) -> (id: String, text: String, isCompletion: Bool, isSegmentTransition: Bool)? {
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
                    return (id, "\(remaining)", false, false)
                }
            } else if remaining <= 0 {
                let id = "boundary-\(index)-complete"
                guard !spokenTimedBoundaryCues.contains(id) else { continue }
                if let nextLabel = boundary.nextLabel {
                    return (id, "Go. \(nextLabel).", false, true)
                }
                return (id, "Workout complete.", true, false)
            }
        }
        return nil
    }

    private func speakPriorityIfNeeded(
        _ text: String,
        isPriority: Bool,
        fixedCueKey: String? = nil
    ) -> Bool {
        if isPriority {
            audioPlayer.stopSpeaking(at: .immediate)
        }
        return speak(
            text,
            urgency: isPriority ? .opportunity : .steady,
            role: isPriority ? .finish : .progress,
            fixedCueKey: fixedCueKey
        )
    }

    private var preferredLastDistanceUnitMeters: Double {
        unitSystem == .imperial ? 1_609.344 : 1_000
    }

    private func hasReliableDistanceProgress(_ snapshot: ActiveSessionSnapshot) -> Bool {
        guard snapshot.distanceMeters > 0 else { return false }
        guard snapshot.elapsedSeconds >= minimumDistanceProgressElapsedSeconds else { return false }

        let averageSpeed = snapshot.distanceMeters / Double(max(snapshot.elapsedSeconds, 1))
        return averageSpeed <= maximumReliableProgressAverageSpeedMetersPerSecond
    }

    private var maximumReliableProgressAverageSpeedMetersPerSecond: Double {
        switch persona?.template.sport ?? sessionIntent?.sport ?? .run {
        case .run, .walk, .hike, .swim:
            return maximumRunningProgressAverageSpeedMetersPerSecond
        case .bike:
            return maximumCyclingProgressAverageSpeedMetersPerSecond
        }
    }

    private func progressAnnouncement(
        for snapshot: ActiveSessionSnapshot,
        pace: Double?,
        includesAveragePace: Bool = false
    ) -> String {
        var parts: [String] = []

        if snapshot.distanceMeters >= minimumProgressAnnouncementDistanceMeters {
            parts.append("\(unitSystem.spokenDistanceString(meters: snapshot.distanceMeters)).")
        }

        if snapshot.elapsedSeconds >= 60 {
            parts.append("\(snapshot.elapsedSeconds.conversationalDurationString).")
        }

        if let pace {
            parts.append("\(paceLabel) \(unitSystem.spokenPaceString(secondsPerKilometer: pace)).")
        } else {
            parts.append(paceSettlingAnnouncement)
        }

        if includesAveragePace, let averagePace = averagePace(for: snapshot) {
            parts.append(averagePaceAnnouncement(averagePace))
        }

        return parts.isEmpty ? "Settle in and keep it easy." : parts.joined(separator: " ")
    }

    private func progressPace(
        for snapshot: ActiveSessionSnapshot,
        reachedDistanceMilestone: Bool
    ) -> Double? {
        reachedDistanceMilestone
            ? latestDistanceCheckpointPace ?? snapshot.currentPaceSecsPerKm
            : snapshot.currentPaceSecsPerKm
    }

    private func observeDistanceCheckpoint(for snapshot: ActiveSessionSnapshot) {
        let milestone = Int(snapshot.distanceMeters / currentProgressDistanceIntervalMeters)
        guard milestone > lastObservedDistanceMilestone else { return }

        let previous = lastObservedDistanceCheckpoint ?? (distanceMeters: 0, elapsedSeconds: 0)
        let distanceDelta = snapshot.distanceMeters - previous.distanceMeters
        let elapsedDelta = snapshot.elapsedSeconds - previous.elapsedSeconds
        if distanceDelta >= currentProgressDistanceIntervalMeters * 0.75,
           elapsedDelta > 0 {
            latestDistanceCheckpointPace = Double(elapsedDelta) / (distanceDelta / 1_000)
        } else {
            latestDistanceCheckpointPace = snapshot.currentPaceSecsPerKm
        }

        lastObservedDistanceMilestone = milestone
        lastObservedDistanceCheckpoint = (snapshot.distanceMeters, snapshot.elapsedSeconds)
    }

    private func averagePace(for snapshot: ActiveSessionSnapshot) -> Double? {
        guard hasReliableDistanceProgress(snapshot),
              snapshot.distanceMeters >= minimumProgressAnnouncementDistanceMeters
        else {
            return nil
        }
        return Double(snapshot.elapsedSeconds) / (snapshot.distanceMeters / 1_000)
    }

    private func keyProgressSummary(for snapshot: ActiveSessionSnapshot) -> String {
        var parts: [String] = []
        if snapshot.distanceMeters >= minimumProgressAnnouncementDistanceMeters {
            parts.append("\(unitSystem.spokenDistanceString(meters: snapshot.distanceMeters)).")
        }
        if snapshot.elapsedSeconds >= 60 {
            parts.append("\(snapshot.elapsedSeconds.conversationalDurationString).")
        }
        if let averagePace = averagePace(for: snapshot) {
            parts.append(averagePaceAnnouncement(averagePace))
        }
        return parts.joined(separator: " ")
    }

    private var paceLabel: String {
        switch AppLanguage.current {
        case .english: "Pace"
        case .spanish: "Ritmo"
        case .simplifiedChinese: "配速"
        }
    }

    private var paceSettlingAnnouncement: String {
        switch AppLanguage.current {
        case .english: "Pace still settling."
        case .spanish: "El ritmo todavía se está estabilizando."
        case .simplifiedChinese: "配速仍在稳定中。"
        }
    }

    private func averagePaceAnnouncement(_ pace: Double) -> String {
        switch AppLanguage.current {
        case .english: "Average pace \(unitSystem.spokenPaceString(secondsPerKilometer: pace))."
        case .spanish: "Ritmo medio \(unitSystem.spokenPaceString(secondsPerKilometer: pace))."
        case .simplifiedChinese: "平均配速 \(unitSystem.spokenPaceString(secondsPerKilometer: pace))。"
        }
    }

    @discardableResult
    private func speak(
        _ text: String,
        urgency: SessionAnalysisUrgency = .steady,
        role: GuidanceMomentRole? = nil,
        fixedCueKey: String? = nil,
        audioData: Data? = nil,
        audioStream: LiveCoachPCMStream? = nil
    ) -> Bool {
        let announcement = spokenText(for: text)
        if speechEnabled, audioPlayer.isSpeaking {
            guard urgency == .caution else { return false }
            audioPlayer.stopSpeaking(at: .currentCue)
        }

        lastSpokenAnnouncement = announcement
        if let role {
            rememberSpokenRole(role)
        }
        guard speechEnabled else { return true }
        if let audioStream {
            audioStream.setFirstAudioHandler { [weak self] firstAudioAt in
                #if DEBUG
                let milliseconds = Int((firstAudioAt.timeIntervalSince(audioStream.requestStartedAt) * 1_000).rounded())
                print("[LiveCoach] device_to_first_audio_ms=\(milliseconds)")
                #endif
                Task { @MainActor in
                    self?.guidanceEventHandler?(.audioFirstByte(
                        source: .dynamicGeneration,
                        latency: LiveCoachLatencyBucket(seconds: firstAudioAt.timeIntervalSince(audioStream.requestStartedAt))
                    ))
                }
            }
            return audioPlayer.play(
                audioStream,
                fallbackData: audioData,
                fallbackText: announcement,
                interrupt: urgency == .caution
            )
        } else if let audioData {
            return audioPlayer.play(audioData, interrupt: urgency == .caution)
        }
        if let data = GuideAudioPackStore.shared.localAudioData(
            for: fixedCueKey ?? "",
            transcript: announcement
        ) {
            return audioPlayer.play(data, interrupt: urgency == .caution)
        }
        return audioPlayer.speakOnDevice(announcement, interrupt: urgency == .caution)
    }

    private func canSpeakGuideMoment(
        at elapsedSeconds: Int,
        urgency: SessionAnalysisUrgency = .steady
    ) -> Bool {
        guard urgency != .caution else { return true }
        guard let lastGuideSpeechElapsedSeconds else { return true }
        return elapsedSeconds - lastGuideSpeechElapsedSeconds >= minimumGuideSpeechGapSeconds
    }

    private func canSpeakProgressUpdate(at elapsedSeconds: Int) -> Bool {
        guard let lastGuideSpeechElapsedSeconds else { return true }
        return elapsedSeconds - lastGuideSpeechElapsedSeconds >= minimumStatSpeechGapSeconds
    }

    private func rememberGuideSpeech(at elapsedSeconds: Int) {
        lastGuideSpeechElapsedSeconds = elapsedSeconds
    }

    private func rememberSpokenRole(_ role: GuidanceMomentRole) {
        recentSpokenRoles.append(role)
        if recentSpokenRoles.count > maxRecentSpokenRoles {
            recentSpokenRoles.removeFirst(recentSpokenRoles.count - maxRecentSpokenRoles)
        }
    }

    private var currentProgressIntervalSeconds: Int {
        provider.progressPolicy?.announceEverySeconds
            ?? persona?.nudgeFrequency.progressAnnouncementIntervalSeconds
            ?? 180
    }

    private var currentProgressDistanceIntervalMeters: Double {
        if let planned = provider.progressPolicy?.announceEveryMeters { return planned }
        return switch persona?.template.sport ?? .run {
        case .run, .walk, .hike, .swim:
            unitSystem == .imperial ? 1_609.344 : 1_000
        case .bike:
            unitSystem == .imperial ? 8_046.72 : 5_000
        }
    }

    private func spokenText(for message: String) -> String {
        message
            .replacingOccurrences(of: ";", with: ", ")
            .replacingOccurrences(of: "—", with: ", ")
    }

    private func normalizedFingerprint(for message: String) -> String {
        message
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func initialNudge(
        for intent: SessionIntent,
        unitSystem: MeasurementUnitSystem
    ) -> String {
        var parts = [intent.guideLine]

        if let targetDistance = intent.resolvedTargetDistanceMeters {
            parts.append("Goal: \(unitSystem.spokenDistanceString(meters: targetDistance)).")
        } else if let targetDuration = intent.resolvedTargetDurationSeconds {
            parts.append("Goal: \(spokenDuration(targetDuration)).")
        } else if let routeName = intent.routeName, !routeName.isEmpty {
            parts.append("Route: \(routeName).")
        }

        return parts.joined(separator: " ")
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
