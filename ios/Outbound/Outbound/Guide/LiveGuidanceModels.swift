import Foundation

enum CoachingContract: String, Codable, CaseIterable, Identifiable {
    case quiet
    case responsive
    case coachMe = "coach_me"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .quiet: String(localized: "guide.contract.quiet", defaultValue: "Quiet")
        case .responsive: String(localized: "guide.contract.responsive", defaultValue: "Responsive")
        case .coachMe: String(localized: "guide.contract.coach_me", defaultValue: "Coach Me")
        }
    }

    var detail: String {
        switch self {
        case .quiet:
            String(localized: "guide.contract.quiet.detail", defaultValue: "Stats, workout transitions, route guidance, and safety only.")
        case .responsive:
            String(localized: "guide.contract.responsive.detail", defaultValue: "Adds coaching when a meaningful change is detected.")
        case .coachMe:
            String(localized: "guide.contract.coach_me.detail", defaultValue: "Offers more frequent coaching around useful moments.")
        }
    }

    var coachingCooldownSeconds: Int? {
        switch self {
        case .quiet: nil
        case .responsive: 180
        case .coachMe: 90
        }
    }
}

enum LiveGuidanceChallenge: String, Codable, CaseIterable, Identifiable {
    case off
    case twoMinutes = "two_minutes"
    case threeMinutes = "three_minutes"

    var id: String { rawValue }

    var durationSeconds: Int? {
        switch self {
        case .off: nil
        case .twoMinutes: 120
        case .threeMinutes: 180
        }
    }

    var displayName: String {
        switch self {
        case .off: String(localized: "guide.challenge.off", defaultValue: "Off")
        case .twoMinutes: String(localized: "guide.challenge.two_minutes", defaultValue: "2-minute lift")
        case .threeMinutes: String(localized: "guide.challenge.three_minutes", defaultValue: "3-minute lift")
        }
    }

    var detail: String {
        switch self {
        case .off:
            String(localized: "guide.challenge.off.detail", defaultValue: "No challenge during this activity.")
        case .twoMinutes:
            String(localized: "guide.challenge.two_minutes.detail", defaultValue: "A focused two-minute push when the timing is right.")
        case .threeMinutes:
            String(localized: "guide.challenge.three_minutes.detail", defaultValue: "A focused three-minute push when the timing is right.")
        }
    }
}

enum LiveGuidanceMomentType: String, Codable, CaseIterable, Hashable {
    case progress
    case earlyOverpace = "early_overpace"
    case paceAboveTarget = "pace_above_target"
    case paceBelowTarget = "pace_below_target"
    case paceInstability = "pace_instability"
    case targetLocked = "target_locked"
    case paceDrift = "pace_drift"
    case rhythmRecovery = "rhythm_recovery"
    case recoveryTooHard = "recovery_too_hard"
    case unexpectedStop = "unexpected_stop"
    case resumeAfterBreak = "resume_after_break"
    case climbStart = "climb_start"
    case crestRecovery = "crest_recovery"
    case segmentTransition = "segment_transition"
    case finishOpportunity = "finish_opportunity"
    case challengeStart = "challenge_start"
    case challengeComplete = "challenge_complete"
}

enum LiveGuidanceCueOutcome: String, Codable, Hashable {
    case pending
    case stabilized
    case improved
    case unchanged
    case worsened
    case notMeasured = "not_measured"

    var isHelpfulResult: Bool {
        self == .stabilized || self == .improved
    }
}

enum LiveGuidanceFeedback: String, Codable, CaseIterable, Identifiable {
    case helpful
    case tooMuch = "too_much"
    case tooGeneric = "too_generic"
    case badTiming = "bad_timing"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .helpful: String(localized: "guide.feedback.helpful", defaultValue: "Helpful")
        case .tooMuch: String(localized: "guide.feedback.too_much", defaultValue: "Too much")
        case .tooGeneric: String(localized: "guide.feedback.too_generic", defaultValue: "Too generic")
        case .badTiming: String(localized: "guide.feedback.bad_timing", defaultValue: "Bad timing")
        }
    }
}

struct LiveGuidanceCueRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let momentType: LiveGuidanceMomentType
    let spokenAtElapsedSeconds: Int
    let baselinePaceSecondsPerKilometer: Double?
    let targetPaceSecondsPerKilometer: Double?
    let evaluationDelaySeconds: Int
    var outcome: LiveGuidanceCueOutcome
    var evaluatedAtElapsedSeconds: Int?

    init(
        id: UUID = UUID(),
        momentType: LiveGuidanceMomentType,
        spokenAtElapsedSeconds: Int,
        baselinePaceSecondsPerKilometer: Double? = nil,
        targetPaceSecondsPerKilometer: Double? = nil,
        evaluationDelaySeconds: Int = 75,
        outcome: LiveGuidanceCueOutcome = .pending,
        evaluatedAtElapsedSeconds: Int? = nil
    ) {
        self.id = id
        self.momentType = momentType
        self.spokenAtElapsedSeconds = spokenAtElapsedSeconds
        self.baselinePaceSecondsPerKilometer = baselinePaceSecondsPerKilometer
        self.targetPaceSecondsPerKilometer = targetPaceSecondsPerKilometer
        self.evaluationDelaySeconds = evaluationDelaySeconds
        self.outcome = outcome
        self.evaluatedAtElapsedSeconds = evaluatedAtElapsedSeconds
    }
}

struct LiveGuidanceSessionReport: Equatable {
    let coachingContract: CoachingContract
    let challenge: LiveGuidanceChallenge
    let cues: [LiveGuidanceCueRecord]

    static let empty = LiveGuidanceSessionReport(
        coachingContract: .responsive,
        challenge: .off,
        cues: []
    )

    var spokenCueCount: Int { cues.count }
    var evaluatedCueCount: Int { cues.filter { $0.outcome != .pending && $0.outcome != .notMeasured }.count }
    var helpfulCueCount: Int { cues.filter { $0.outcome.isHelpfulResult }.count }
}

enum LiveGuidanceTelemetryEvent: Equatable {
    case momentDetected(type: LiveGuidanceMomentType, contract: CoachingContract)
    case cueSpoken(type: LiveGuidanceMomentType, contract: CoachingContract)
    case cueEvaluated(type: LiveGuidanceMomentType, outcome: LiveGuidanceCueOutcome)
    case providerResult(
        source: LiveCoachCueSource,
        result: LiveCoachCueResult,
        mode: LiveCoachAudioMode,
        accessReason: LiveCoachAccessReason,
        latency: LiveCoachLatencyBucket
    )
    case audioFirstByte(source: LiveCoachCueSource, latency: LiveCoachLatencyBucket)
    case audioPlaybackRoute(route: GuideAudioPlaybackRoute)
}

struct DetectedLiveGuidanceMoment: Equatable {
    let type: LiveGuidanceMomentType
    let detectedAtElapsedSeconds: Int
    let baselinePaceSecondsPerKilometer: Double?
    let targetPaceSecondsPerKilometer: Double?
    let evaluationDelaySeconds: Int
    let preferredMessage: String?

    init(
        type: LiveGuidanceMomentType,
        detectedAtElapsedSeconds: Int,
        baselinePaceSecondsPerKilometer: Double? = nil,
        targetPaceSecondsPerKilometer: Double? = nil,
        evaluationDelaySeconds: Int = 75,
        preferredMessage: String? = nil
    ) {
        self.type = type
        self.detectedAtElapsedSeconds = detectedAtElapsedSeconds
        self.baselinePaceSecondsPerKilometer = baselinePaceSecondsPerKilometer
        self.targetPaceSecondsPerKilometer = targetPaceSecondsPerKilometer
        self.evaluationDelaySeconds = evaluationDelaySeconds
        self.preferredMessage = preferredMessage
    }
}

struct LiveGuidanceDirectorUpdate {
    let nextMoment: DetectedLiveGuidanceMoment?
    let evaluatedCues: [LiveGuidanceCueRecord]
}

@MainActor
final class LiveGuidanceDirector {
    private var contract: CoachingContract = .responsive
    private var challenge: LiveGuidanceChallenge = .off
    private var suppressedMomentTypes: Set<LiveGuidanceMomentType> = []
    private var history: [ActiveSessionSnapshot] = []
    private var records: [LiveGuidanceCueRecord] = []
    private var emittedOneShotMoments: Set<LiveGuidanceMomentType> = []
    private var emittedSegmentMoments: Set<String> = []
    private var lastMomentElapsedSeconds: Int?
    private var lastDriftElapsedSeconds: Int?
    private var lastInstabilityElapsedSeconds: Int?
    private var isOnClimb = false
    private var challengeStartedAtElapsedSeconds: Int?
    private var challengeStartQueued = false
    private var challengeCompleted = false

    func reset(
        contract: CoachingContract,
        challenge: LiveGuidanceChallenge,
        suppressedMomentTypes: Set<LiveGuidanceMomentType> = []
    ) {
        self.contract = contract
        self.challenge = challenge
        self.suppressedMomentTypes = suppressedMomentTypes
        history = []
        records = []
        emittedOneShotMoments = []
        emittedSegmentMoments = []
        lastMomentElapsedSeconds = nil
        lastDriftElapsedSeconds = nil
        lastInstabilityElapsedSeconds = nil
        isOnClimb = false
        challengeStartedAtElapsedSeconds = nil
        challengeStartQueued = false
        challengeCompleted = false
    }

    func ingest(
        _ snapshot: ActiveSessionSnapshot,
        profile: GuideProfile?,
        intent: SessionIntent?
    ) -> LiveGuidanceDirectorUpdate {
        history.append(snapshot)
        if history.count > 240 {
            history.removeFirst(history.count - 240)
        }

        let evaluation = evaluatePendingCues(at: snapshot)
        if let recovery = evaluation.recoveryMoment {
            return LiveGuidanceDirectorUpdate(nextMoment: recovery, evaluatedCues: evaluation.records)
        }

        if let challengeMoment = challengeMomentIfNeeded(snapshot: snapshot, intent: intent) {
            lastMomentElapsedSeconds = snapshot.elapsedSeconds
            return LiveGuidanceDirectorUpdate(nextMoment: challengeMoment, evaluatedCues: evaluation.records)
        }

        if (challengeStartQueued || challengeStartedAtElapsedSeconds != nil), !challengeCompleted {
            return LiveGuidanceDirectorUpdate(nextMoment: nil, evaluatedCues: evaluation.records)
        }

        guard let cooldown = contract.coachingCooldownSeconds,
              lastMomentElapsedSeconds.map({ snapshot.elapsedSeconds - $0 >= cooldown }) ?? true
        else {
            return LiveGuidanceDirectorUpdate(nextMoment: nil, evaluatedCues: evaluation.records)
        }

        let athleteReferencePace = athleteReferencePace(from: profile)
        let activeSegment = intent?.activeCoachingSegment(at: snapshot.elapsedSeconds)
        let gradePercent = rollingGradePercent(through: snapshot.elapsedSeconds)
        let moment = terrainMoment(
            snapshot: snapshot,
            intent: intent,
            gradePercent: gradePercent
        )
            ?? earlyOverpaceMoment(
                snapshot: snapshot,
                activeSegment: activeSegment,
                athleteReferencePace: athleteReferencePace,
                gradePercent: gradePercent
            )
            ?? targetDeviationMoment(
                snapshot: snapshot,
                activeSegment: activeSegment,
                athleteReferencePace: athleteReferencePace,
                gradePercent: gradePercent
            )
            ?? finishOpportunityMoment(snapshot: snapshot, intent: intent)
            ?? paceDriftMoment(
                snapshot: snapshot,
                activeSegment: activeSegment,
                gradePercent: gradePercent
            )
            ?? paceInstabilityMoment(
                snapshot: snapshot,
                activeSegment: activeSegment,
                athleteReferencePace: athleteReferencePace,
                gradePercent: gradePercent
            )
            ?? targetLockedMoment(
                snapshot: snapshot,
                activeSegment: activeSegment,
                athleteReferencePace: athleteReferencePace,
                gradePercent: gradePercent
            )

        if moment != nil {
            lastMomentElapsedSeconds = snapshot.elapsedSeconds
        }
        return LiveGuidanceDirectorUpdate(nextMoment: moment, evaluatedCues: evaluation.records)
    }

    func recordSpoken(_ moment: DetectedLiveGuidanceMoment) -> LiveGuidanceCueRecord {
        if moment.type == .challengeStart {
            challengeStartQueued = false
            challengeStartedAtElapsedSeconds = moment.detectedAtElapsedSeconds
        }
        let hasEvaluationTarget = moment.baselinePaceSecondsPerKilometer != nil
            && moment.targetPaceSecondsPerKilometer != nil
        let record = LiveGuidanceCueRecord(
            momentType: moment.type,
            spokenAtElapsedSeconds: moment.detectedAtElapsedSeconds,
            baselinePaceSecondsPerKilometer: moment.baselinePaceSecondsPerKilometer,
            targetPaceSecondsPerKilometer: moment.targetPaceSecondsPerKilometer,
            evaluationDelaySeconds: moment.evaluationDelaySeconds,
            outcome: hasEvaluationTarget ? .pending : .notMeasured
        )
        records.append(record)
        return record
    }

    func recordSystemCue(type: LiveGuidanceMomentType, elapsedSeconds: Int) -> LiveGuidanceCueRecord {
        let moment = DetectedLiveGuidanceMoment(type: type, detectedAtElapsedSeconds: elapsedSeconds)
        return recordSpoken(moment)
    }

    func report(finalizing: Bool) -> LiveGuidanceSessionReport {
        let reportRecords = records.map { record in
            guard finalizing, record.outcome == .pending else { return record }
            var finalized = record
            finalized.outcome = .notMeasured
            return finalized
        }
        return LiveGuidanceSessionReport(
            coachingContract: contract,
            challenge: challenge,
            cues: reportRecords
        )
    }

    private func earlyOverpaceMoment(
        snapshot: ActiveSessionSnapshot,
        activeSegment: ActiveSessionCoachingSegment?,
        athleteReferencePace: Double?,
        gradePercent: Double?
    ) -> DetectedLiveGuidanceMoment? {
        let target: Double?
        if let activeSegment {
            target = resolvedPaceTarget(
                for: activeSegment,
                athleteReferencePace: athleteReferencePace
            )
        } else {
            target = athleteReferencePace
        }
        guard !suppressedMomentTypes.contains(.earlyOverpace),
              !emittedOneShotMoments.contains(.earlyOverpace),
              (75...240).contains(snapshot.elapsedSeconds),
              !isMeaningfulGrade(gradePercent),
              let target,
              let recent = averagePace(from: snapshot.elapsedSeconds - 30, through: snapshot.elapsedSeconds)
        else { return nil }

        let configuredTolerance = activeSegment?.target.pace?.fasterToleranceSeconds
        let threshold = configuredTolerance ?? (contract == .coachMe ? 15.0 : 25.0)
        guard target - recent >= threshold else { return nil }
        emittedOneShotMoments.insert(.earlyOverpace)
        return DetectedLiveGuidanceMoment(
            type: .earlyOverpace,
            detectedAtElapsedSeconds: snapshot.elapsedSeconds,
            baselinePaceSecondsPerKilometer: recent,
            targetPaceSecondsPerKilometer: target
        )
    }

    private func targetDeviationMoment(
        snapshot: ActiveSessionSnapshot,
        activeSegment: ActiveSessionCoachingSegment?,
        athleteReferencePace: Double?,
        gradePercent: Double?
    ) -> DetectedLiveGuidanceMoment? {
        guard let activeSegment,
              activeSegment.elapsedSeconds >= 45,
              !isMeaningfulGrade(gradePercent),
              let paceTarget = activeSegment.target.pace,
              let target = paceTarget.resolvedTarget(athleteReferencePace: athleteReferencePace),
              let recent = averagePace(from: snapshot.elapsedSeconds - 30, through: snapshot.elapsedSeconds)
        else { return nil }

        let isRecovery = activeSegment.target.phase == .recovery
            || activeSegment.target.phase == .warmup
            || activeSegment.target.phase == .cooldown
        let aboveType: LiveGuidanceMomentType = isRecovery ? .recoveryTooHard : .paceAboveTarget
        if !suppressedMomentTypes.contains(aboveType),
           !hasEmitted(aboveType, in: activeSegment),
           target - recent >= paceTarget.fasterToleranceSeconds {
            markEmitted(aboveType, in: activeSegment)
            return DetectedLiveGuidanceMoment(
                type: aboveType,
                detectedAtElapsedSeconds: snapshot.elapsedSeconds,
                baselinePaceSecondsPerKilometer: recent,
                targetPaceSecondsPerKilometer: target
            )
        }

        if let slowerTolerance = paceTarget.slowerToleranceSeconds,
           !suppressedMomentTypes.contains(.paceBelowTarget),
           !hasEmitted(.paceBelowTarget, in: activeSegment),
           recent - target >= slowerTolerance {
            markEmitted(.paceBelowTarget, in: activeSegment)
            return DetectedLiveGuidanceMoment(
                type: .paceBelowTarget,
                detectedAtElapsedSeconds: snapshot.elapsedSeconds,
                baselinePaceSecondsPerKilometer: recent,
                targetPaceSecondsPerKilometer: target
            )
        }
        return nil
    }

    private func paceDriftMoment(
        snapshot: ActiveSessionSnapshot,
        activeSegment: ActiveSessionCoachingSegment?,
        gradePercent: Double?
    ) -> DetectedLiveGuidanceMoment? {
        guard !suppressedMomentTypes.contains(.paceDrift),
              snapshot.elapsedSeconds >= 300,
              activeSegment?.target.phase != .work,
              activeSegment?.target.phase != .recovery,
              !isMeaningfulGrade(gradePercent),
              lastDriftElapsedSeconds.map({ snapshot.elapsedSeconds - $0 >= 600 }) ?? true,
              let earlier = averagePace(from: snapshot.elapsedSeconds - 100, through: snapshot.elapsedSeconds - 45),
              let recent = averagePace(from: snapshot.elapsedSeconds - 30, through: snapshot.elapsedSeconds)
        else { return nil }

        let threshold = contract == .coachMe ? 18.0 : 25.0
        guard recent - earlier >= threshold else { return nil }
        lastDriftElapsedSeconds = snapshot.elapsedSeconds
        return DetectedLiveGuidanceMoment(
            type: .paceDrift,
            detectedAtElapsedSeconds: snapshot.elapsedSeconds,
            baselinePaceSecondsPerKilometer: recent,
            targetPaceSecondsPerKilometer: earlier
        )
    }

    private func paceInstabilityMoment(
        snapshot: ActiveSessionSnapshot,
        activeSegment: ActiveSessionCoachingSegment?,
        athleteReferencePace: Double?,
        gradePercent: Double?
    ) -> DetectedLiveGuidanceMoment? {
        guard !suppressedMomentTypes.contains(.paceInstability),
              let activeSegment,
              activeSegment.elapsedSeconds >= 120,
              !isMeaningfulGrade(gradePercent),
              lastInstabilityElapsedSeconds.map({ snapshot.elapsedSeconds - $0 >= 600 }) ?? true,
              let target = resolvedPaceTarget(
                for: activeSegment,
                athleteReferencePace: athleteReferencePace
              )
        else { return nil }

        let values = paceValues(from: snapshot.elapsedSeconds - 90, through: snapshot.elapsedSeconds)
        guard values.count >= 8 else { return nil }
        let sorted = values.sorted()
        let spread = percentile(0.9, in: sorted) - percentile(0.1, in: sorted)
        guard spread >= max(60, target * 0.15) else { return nil }
        lastInstabilityElapsedSeconds = snapshot.elapsedSeconds
        return DetectedLiveGuidanceMoment(
            type: .paceInstability,
            detectedAtElapsedSeconds: snapshot.elapsedSeconds,
            baselinePaceSecondsPerKilometer: values.reduce(0, +) / Double(values.count),
            targetPaceSecondsPerKilometer: target
        )
    }

    private func targetLockedMoment(
        snapshot: ActiveSessionSnapshot,
        activeSegment: ActiveSessionCoachingSegment?,
        athleteReferencePace: Double?,
        gradePercent: Double?
    ) -> DetectedLiveGuidanceMoment? {
        guard !suppressedMomentTypes.contains(.targetLocked),
              let activeSegment,
              activeSegment.target.recognizesTargetLock,
              activeSegment.elapsedSeconds >= 90,
              !hasEmitted(.targetLocked, in: activeSegment),
              !isMeaningfulGrade(gradePercent),
              let target = resolvedPaceTarget(
                for: activeSegment,
                athleteReferencePace: athleteReferencePace
              )
        else { return nil }

        let values = paceValues(from: snapshot.elapsedSeconds - 60, through: snapshot.elapsedSeconds)
        guard values.count >= 8 else { return nil }
        let average = values.reduce(0, +) / Double(values.count)
        let sorted = values.sorted()
        guard abs(average - target) <= 12,
              percentile(0.9, in: sorted) - percentile(0.1, in: sorted) <= 25
        else { return nil }
        markEmitted(.targetLocked, in: activeSegment)
        return DetectedLiveGuidanceMoment(
            type: .targetLocked,
            detectedAtElapsedSeconds: snapshot.elapsedSeconds
        )
    }

    private func terrainMoment(
        snapshot: ActiveSessionSnapshot,
        intent: SessionIntent?,
        gradePercent: Double?
    ) -> DetectedLiveGuidanceMoment? {
        guard intent?.resolvedActivityType == .running,
              snapshot.elapsedSeconds >= 90,
              let gradePercent
        else { return nil }

        if !isOnClimb, gradePercent >= 3.5 {
            isOnClimb = true
            guard !suppressedMomentTypes.contains(.climbStart) else { return nil }
            return DetectedLiveGuidanceMoment(
                type: .climbStart,
                detectedAtElapsedSeconds: snapshot.elapsedSeconds
            )
        }

        if isOnClimb, gradePercent <= 1.25 {
            isOnClimb = false
            guard !suppressedMomentTypes.contains(.crestRecovery) else { return nil }
            return DetectedLiveGuidanceMoment(
                type: .crestRecovery,
                detectedAtElapsedSeconds: snapshot.elapsedSeconds
            )
        }
        return nil
    }

    private func finishOpportunityMoment(
        snapshot: ActiveSessionSnapshot,
        intent: SessionIntent?
    ) -> DetectedLiveGuidanceMoment? {
        guard !suppressedMomentTypes.contains(.finishOpportunity),
              !emittedOneShotMoments.contains(.finishOpportunity),
              snapshot.elapsedSeconds >= 300,
              isInFinishWindow(snapshot: snapshot, intent: intent)
        else { return nil }

        emittedOneShotMoments.insert(.finishOpportunity)
        return DetectedLiveGuidanceMoment(
            type: .finishOpportunity,
            detectedAtElapsedSeconds: snapshot.elapsedSeconds
        )
    }

    private func challengeMomentIfNeeded(
        snapshot: ActiveSessionSnapshot,
        intent: SessionIntent?
    ) -> DetectedLiveGuidanceMoment? {
        guard let duration = challenge.durationSeconds else { return nil }

        if let startedAt = challengeStartedAtElapsedSeconds {
            guard !challengeCompleted, snapshot.elapsedSeconds - startedAt >= duration else { return nil }
            challengeCompleted = true
            return DetectedLiveGuidanceMoment(
                type: .challengeComplete,
                detectedAtElapsedSeconds: snapshot.elapsedSeconds,
                preferredMessage: challengeCompleteMessage
            )
        }

        guard !challengeStartQueued,
              snapshot.elapsedSeconds >= 360,
              hasRoomForChallenge(snapshot: snapshot, intent: intent, duration: duration),
              let baseline = averagePace(from: snapshot.elapsedSeconds - 45, through: snapshot.elapsedSeconds)
        else { return nil }

        challengeStartQueued = true
        return DetectedLiveGuidanceMoment(
            type: .challengeStart,
            detectedAtElapsedSeconds: snapshot.elapsedSeconds,
            baselinePaceSecondsPerKilometer: baseline,
            targetPaceSecondsPerKilometer: baseline * 0.95,
            evaluationDelaySeconds: duration,
            preferredMessage: challengeStartMessage(durationSeconds: duration)
        )
    }

    private func evaluatePendingCues(
        at snapshot: ActiveSessionSnapshot
    ) -> (records: [LiveGuidanceCueRecord], recoveryMoment: DetectedLiveGuidanceMoment?) {
        var evaluated: [LiveGuidanceCueRecord] = []
        var recoveryMoment: DetectedLiveGuidanceMoment?

        for index in records.indices where records[index].outcome == .pending {
            let record = records[index]
            guard snapshot.elapsedSeconds - record.spokenAtElapsedSeconds >= record.evaluationDelaySeconds,
                  let baseline = record.baselinePaceSecondsPerKilometer,
                  let target = record.targetPaceSecondsPerKilometer,
                  let current = averagePace(from: snapshot.elapsedSeconds - 30, through: snapshot.elapsedSeconds)
            else { continue }

            let baselineError = abs(baseline - target)
            let currentError = abs(current - target)
            let outcome: LiveGuidanceCueOutcome
            if currentError <= 10 {
                outcome = .stabilized
            } else if currentError + 8 < baselineError {
                outcome = .improved
            } else if currentError > baselineError + 10 {
                outcome = .worsened
            } else {
                outcome = .unchanged
            }

            records[index].outcome = outcome
            records[index].evaluatedAtElapsedSeconds = snapshot.elapsedSeconds
            evaluated.append(records[index])

            if outcome.isHelpfulResult,
               recoveryMoment == nil,
               [.earlyOverpace, .paceAboveTarget, .paceBelowTarget, .paceDrift, .recoveryTooHard]
                .contains(record.momentType) {
                recoveryMoment = DetectedLiveGuidanceMoment(
                    type: .rhythmRecovery,
                    detectedAtElapsedSeconds: snapshot.elapsedSeconds,
                    preferredMessage: recoveryMessage
                )
            }
        }

        return (evaluated, recoveryMoment)
    }

    private func averagePace(from start: Int, through end: Int) -> Double? {
        let values = paceValues(from: start, through: end)
        guard values.count >= 4 else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func paceValues(from start: Int, through end: Int) -> [Double] {
        history
            .filter { $0.elapsedSeconds >= start && $0.elapsedSeconds <= end }
            .compactMap(\.currentPaceSecsPerKm)
            .filter { $0.isFinite && (60...3_600).contains($0) }
    }

    private func athleteReferencePace(from profile: GuideProfile?) -> Double? {
        if let preferred = profile?.athlete.preferredPaceSecs,
           preferred.isFinite,
           (60...3_600).contains(preferred) {
            return preferred
        }
        let values = profile?.memorySnapshot.recentActivities
            .map(\.avgPaceSecs)
            .filter { $0.isFinite && (60...3_600).contains($0) }
            .sorted() ?? []
        guard !values.isEmpty else { return nil }
        let middle = values.count / 2
        return values.count.isMultiple(of: 2)
            ? (values[middle - 1] + values[middle]) / 2
            : values[middle]
    }

    private func resolvedPaceTarget(
        for segment: ActiveSessionCoachingSegment,
        athleteReferencePace: Double?
    ) -> Double? {
        segment.target.pace?.resolvedTarget(athleteReferencePace: athleteReferencePace)
    }

    private func hasEmitted(
        _ type: LiveGuidanceMomentType,
        in segment: ActiveSessionCoachingSegment
    ) -> Bool {
        emittedSegmentMoments.contains("\(type.rawValue)|\(segment.id)")
    }

    private func markEmitted(
        _ type: LiveGuidanceMomentType,
        in segment: ActiveSessionCoachingSegment
    ) {
        emittedSegmentMoments.insert("\(type.rawValue)|\(segment.id)")
    }

    private func percentile(_ fraction: Double, in sortedValues: [Double]) -> Double {
        guard let first = sortedValues.first else { return 0 }
        let index = min(sortedValues.count - 1, max(0, Int((Double(sortedValues.count - 1) * fraction).rounded())))
        return sortedValues.indices.contains(index) ? sortedValues[index] : first
    }

    private func isMeaningfulGrade(_ gradePercent: Double?) -> Bool {
        guard let gradePercent else { return false }
        return abs(gradePercent) >= 2.5
    }

    private func rollingGradePercent(through elapsedSeconds: Int) -> Double? {
        let locations = history
            .filter { $0.elapsedSeconds >= elapsedSeconds - 45 && $0.elapsedSeconds <= elapsedSeconds }
            .compactMap(\.location)
            .filter {
                $0.horizontalAccuracyMeters >= 0
                    && $0.horizontalAccuracyMeters <= 25
                    && $0.verticalAccuracyMeters >= 0
                    && $0.verticalAccuracyMeters <= 10
            }
        guard locations.count >= 6 else { return nil }
        let endpointCount = min(3, locations.count / 2)
        let startLocations = Array(locations.prefix(endpointCount))
        let endLocations = Array(locations.suffix(endpointCount))
        let start = averagedLocation(startLocations)
        let end = averagedLocation(endLocations)
        let horizontalMeters = haversineDistanceMeters(
            latitudeA: start.latitude,
            longitudeA: start.longitude,
            latitudeB: end.latitude,
            longitudeB: end.longitude
        )
        guard horizontalMeters >= 45 else { return nil }
        let grade = (end.altitude - start.altitude) / horizontalMeters * 100
        guard grade.isFinite, abs(grade) <= 40 else { return nil }
        return grade
    }

    private func averagedLocation(
        _ locations: [SessionLocation]
    ) -> (latitude: Double, longitude: Double, altitude: Double) {
        let divisor = Double(locations.count)
        return (
            locations.reduce(0) { $0 + $1.latitude } / divisor,
            locations.reduce(0) { $0 + $1.longitude } / divisor,
            locations.reduce(0) { $0 + $1.altitudeMeters } / divisor
        )
    }

    private func haversineDistanceMeters(
        latitudeA: Double,
        longitudeA: Double,
        latitudeB: Double,
        longitudeB: Double
    ) -> Double {
        let degreesToRadians = Double.pi / 180
        let latitudeDelta = (latitudeB - latitudeA) * degreesToRadians
        let longitudeDelta = (longitudeB - longitudeA) * degreesToRadians
        let firstLatitude = latitudeA * degreesToRadians
        let secondLatitude = latitudeB * degreesToRadians
        let value = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(firstLatitude) * cos(secondLatitude)
            * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        return 6_371_000 * 2 * atan2(sqrt(value), sqrt(max(0, 1 - value)))
    }

    private func isInFinishWindow(
        snapshot: ActiveSessionSnapshot,
        intent: SessionIntent?
    ) -> Bool {
        if let targetDistance = intent?.resolvedTargetDistanceMeters, targetDistance > 0 {
            let remaining = targetDistance - snapshot.distanceMeters
            return remaining > 300 && remaining <= min(800, targetDistance * 0.12)
        }
        if let targetDuration = intent?.resolvedTargetDurationSeconds, targetDuration > 0 {
            let remaining = targetDuration - snapshot.elapsedSeconds
            return remaining > 120 && remaining <= min(300, Int(Double(targetDuration) * 0.12))
        }
        return false
    }

    private func hasRoomForChallenge(
        snapshot: ActiveSessionSnapshot,
        intent: SessionIntent?,
        duration: Int
    ) -> Bool {
        if let targetDuration = intent?.resolvedTargetDurationSeconds {
            return targetDuration - snapshot.elapsedSeconds >= duration + 60
        }
        if let targetDistance = intent?.resolvedTargetDistanceMeters,
           let pace = snapshot.currentPaceSecsPerKm {
            let estimatedRemainingSeconds = (targetDistance - snapshot.distanceMeters) / 1_000 * pace
            return estimatedRemainingSeconds >= Double(duration + 60)
        }
        return true
    }

    private func challengeStartMessage(durationSeconds: Int) -> String {
        let minutes = durationSeconds / 60
        return switch AppLanguage.current {
        case .english: "Challenge starts now. Build the pace smoothly for \(minutes) minutes."
        case .spanish: "El reto empieza ahora. Aumenta el ritmo con control durante \(minutes) minutos."
        case .simplifiedChinese: "挑战现在开始。接下来 \(minutes) 分钟平稳提速。"
        }
    }

    private var challengeCompleteMessage: String {
        switch AppLanguage.current {
        case .english: "Challenge complete. Settle back into your run."
        case .spanish: "Reto completado. Vuelve a tu ritmo normal."
        case .simplifiedChinese: "挑战完成。回到正常跑步节奏。"
        }
    }

    private var recoveryMessage: String {
        switch AppLanguage.current {
        case .english: "That adjustment worked. You found the rhythm again."
        case .spanish: "Ese ajuste funcionó. Recuperaste el ritmo."
        case .simplifiedChinese: "刚才的调整有效。你重新找回节奏了。"
        }
    }
}
