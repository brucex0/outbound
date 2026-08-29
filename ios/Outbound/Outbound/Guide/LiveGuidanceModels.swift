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
    case fastStart = "fast_start"
    case paceDrift = "pace_drift"
    case rhythmRecovery = "rhythm_recovery"
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
    private var lastMomentElapsedSeconds: Int?
    private var lastDriftElapsedSeconds: Int?
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
        lastMomentElapsedSeconds = nil
        lastDriftElapsedSeconds = nil
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

        let moment = fastStartMoment(snapshot: snapshot, profile: profile)
            ?? finishOpportunityMoment(snapshot: snapshot, intent: intent)
            ?? paceDriftMoment(snapshot: snapshot)

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

    private func fastStartMoment(
        snapshot: ActiveSessionSnapshot,
        profile: GuideProfile?
    ) -> DetectedLiveGuidanceMoment? {
        guard !suppressedMomentTypes.contains(.fastStart),
              !emittedOneShotMoments.contains(.fastStart),
              (75...240).contains(snapshot.elapsedSeconds),
              let target = profile?.athlete.preferredPaceSecs,
              let recent = averagePace(from: snapshot.elapsedSeconds - 30, through: snapshot.elapsedSeconds)
        else { return nil }

        let threshold = contract == .coachMe ? 15.0 : 25.0
        guard target - recent >= threshold else { return nil }
        emittedOneShotMoments.insert(.fastStart)
        return DetectedLiveGuidanceMoment(
            type: .fastStart,
            detectedAtElapsedSeconds: snapshot.elapsedSeconds,
            baselinePaceSecondsPerKilometer: recent,
            targetPaceSecondsPerKilometer: target
        )
    }

    private func paceDriftMoment(snapshot: ActiveSessionSnapshot) -> DetectedLiveGuidanceMoment? {
        guard !suppressedMomentTypes.contains(.paceDrift),
              snapshot.elapsedSeconds >= 300,
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
               record.momentType == .fastStart || record.momentType == .paceDrift {
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
        let values = history
            .filter { $0.elapsedSeconds >= start && $0.elapsedSeconds <= end }
            .compactMap(\.currentPaceSecsPerKm)
            .filter { $0.isFinite && $0 > 0 }
        guard values.count >= 4 else { return nil }
        return values.reduce(0, +) / Double(values.count)
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
