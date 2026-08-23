import Foundation

enum SessionAnalysisUrgency: String {
    case steady
    case opportunity
    case caution
}

struct SessionAnalysisRequest {
    let profile: GuideProfile?
    let persona: GuidePersona?
    let snapshot: ActiveSessionSnapshot
    let recentSnapshots: [ActiveSessionSnapshot]
    let sessionIntent: SessionIntent?
    let recentNudges: [String]
    let companionBrief: CompanionSessionBriefDTO?
    let momentType: LiveGuidanceMomentType?

    init(
        profile: GuideProfile?,
        persona: GuidePersona?,
        snapshot: ActiveSessionSnapshot,
        recentSnapshots: [ActiveSessionSnapshot],
        sessionIntent: SessionIntent? = nil,
        recentNudges: [String] = [],
        companionBrief: CompanionSessionBriefDTO? = nil,
        momentType: LiveGuidanceMomentType? = nil
    ) {
        self.profile = profile
        self.persona = persona
        self.snapshot = snapshot
        self.recentSnapshots = recentSnapshots
        self.sessionIntent = sessionIntent
        self.recentNudges = recentNudges
        self.companionBrief = companionBrief
        self.momentType = momentType
    }
}

struct SessionNudgePacket: Encodable {
    let session: SessionData
    let plan: PlanData
    let athlete: AthleteData
    let guide: GuideData
    let decision: DecisionData
    let history: HistoryData

    struct SessionData: Encodable {
        let activityType: String
        let workoutType: String
        let phase: String
        let elapsedSeconds: Int
        let distanceMeters: Double
        let paceSecondsPerKm: Double?
        let heartRateBpm: Int?
        let elevationGainMeters: Double?
        let gradePercent: Double?
        let signalConfidence: SignalConfidence
    }

    struct SignalConfidence: Encodable {
        let pace: String
        let heartRate: String
        let gps: String
    }

    struct PlanData: Encodable {
        let title: String
        let segmentName: String?
        let segmentGoal: String?
        let targetDistanceMeters: Double?
        let targetDurationSeconds: Int?
        let targetPaceSecondsPerKm: Double?
    }

    struct AthleteData: Encodable {
        let fitnessLevel: String?
        let weeklyVolumeKm: Double?
        let preferredPaceSecondsPerKm: Double?
        let goal: String?
        let recentPatterns: [String]
    }

    struct GuideData: Encodable {
        let persona: String
        let style: String
        let intensity: String
        let spokenLanguage: String
        let maxWords: Int
    }

    struct DecisionData: Encodable {
        let shouldNudge: Bool
        let reason: String
        let intent: String
        let urgency: String
    }

    struct HistoryData: Encodable {
        let lastNudges: [String]
    }
}

extension SessionAnalysisRequest {
    var nudgePacket: SessionNudgePacket {
        let sport = persona?.template.sport ?? .run
        let phase = sessionPhase
        let reason = nudgeReason
        let intent = nudgeIntent
        let currentStep = activeStep

        return SessionNudgePacket(
            session: .init(
                activityType: sport.rawValue,
                workoutType: sessionIntent?.title.replacingOccurrences(of: " ", with: "_").lowercased() ?? "freestyle_\(sport.rawValue)",
                phase: phase,
                elapsedSeconds: snapshot.elapsedSeconds,
                distanceMeters: snapshot.distanceMeters,
                paceSecondsPerKm: snapshot.currentPaceSecsPerKm,
                heartRateBpm: snapshot.heartRate,
                elevationGainMeters: elevationGainMeters,
                gradePercent: gradePercent,
                signalConfidence: .init(
                    pace: paceConfidence,
                    heartRate: heartRateConfidence,
                    gps: gpsConfidence
                )
            ),
            plan: .init(
                title: sessionIntent?.title ?? "Freestyle \(sport.displayName)",
                segmentName: currentStep?.label,
                segmentGoal: currentStep?.detail ?? sessionIntent?.detail,
                targetDistanceMeters: sessionIntent?.resolvedTargetDistanceMeters,
                targetDurationSeconds: sessionIntent?.resolvedTargetDurationSeconds,
                targetPaceSecondsPerKm: profile?.athlete.preferredPaceSecs
            ),
            athlete: .init(
                fitnessLevel: profile?.athlete.fitnessLevel,
                weeklyVolumeKm: profile?.athlete.weeklyVolumeKm,
                preferredPaceSecondsPerKm: profile?.athlete.preferredPaceSecs,
                goal: profile?.goals.first(where: { !$0.achieved })?.description,
                recentPatterns: Array((athletePatterns + (companionBrief?.guidancePriorities ?? [])).prefix(8))
            ),
            guide: .init(
                persona: persona?.template.personality ?? "supportive, concise",
                style: persona?.template.guidanceStyle ?? "supportive live guidance",
                intensity: persona?.intensity.displayName ?? GuidanceIntensity.balanced.displayName,
                spokenLanguage: spokenLanguage.rawValue,
                maxWords: 18
            ),
            decision: .init(
                shouldNudge: momentType != nil,
                reason: reason,
                intent: intent,
                urgency: derivedUrgency.rawValue
            ),
            history: .init(
                lastNudges: Array(recentNudges.suffix(3))
            )
        )
    }

    var spokenLanguage: AppLanguage {
        persona.map { AppLanguage.language(matching: $0.voice.locale) } ?? AppLanguage.current
    }

    private var sessionPhase: String {
        switch snapshot.elapsedSeconds {
        case ..<45:
            "startup"
        case ..<180:
            "settling"
        case ..<900:
            "steady"
        default:
            "working"
        }
    }

    private var nudgeReason: String {
        if let momentType { return momentType.rawValue }
        if let heartRate = snapshot.heartRate, heartRate > 185 {
            return "heart_rate_high"
        }
        if snapshot.currentPaceSecsPerKm == nil {
            return "startup_settling"
        }
        if let target = profile?.athlete.preferredPaceSecs,
           let pace = snapshot.currentPaceSecsPerKm {
            if pace - target > 15 {
                return "below_target_pace"
            }
            if target - pace > 15 {
                return "above_target_pace"
            }
        }
        if paceTrendIsSlowing {
            return "pace_drift"
        }
        if finishingSoon {
            return "finish_window"
        }
        if activeStep != nil {
            return "segment_check_in"
        }
        return "steady_check_in"
    }

    private var nudgeIntent: String {
        switch nudgeReason {
        case LiveGuidanceMomentType.fastStart.rawValue:
            return "settle_early_effort"
        case LiveGuidanceMomentType.paceDrift.rawValue:
            return "restore_rhythm"
        case LiveGuidanceMomentType.rhythmRecovery.rawValue:
            return "recognize_recovery"
        case LiveGuidanceMomentType.segmentTransition.rawValue:
            return "enter_next_segment"
        case LiveGuidanceMomentType.finishOpportunity.rawValue:
            return "finish_composed"
        case "heart_rate_high":
            return "settle_breathing"
        case "startup_settling":
            return "reassure_without_precision"
        case "below_target_pace":
            return "build_effort"
        case "above_target_pace":
            return "ease_back"
        case "pace_drift":
            return "restore_rhythm"
        case "finish_window":
            return "finish_composed"
        case "segment_check_in":
            return "hold_segment_goal"
        default:
            return "steady_reassurance"
        }
    }

    private var derivedUrgency: SessionAnalysisUrgency {
        if momentType == .fastStart || momentType == .paceDrift || momentType == .finishOpportunity {
            return .opportunity
        }
        if let heartRate = snapshot.heartRate, heartRate > 185 {
            return .caution
        }

        guard let pace = snapshot.currentPaceSecsPerKm,
              let target = profile?.athlete.preferredPaceSecs
        else {
            return .steady
        }

        return abs(pace - target) > 15 ? .opportunity : .steady
    }

    private var paceTrendIsSlowing: Bool {
        let paces = recentSnapshots.compactMap(\.currentPaceSecsPerKm)
        guard paces.count >= 4 else { return false }
        let midpoint = paces.count / 2
        let firstAverage = paces[..<midpoint].reduce(0, +) / Double(midpoint)
        let secondAverage = paces[midpoint...].reduce(0, +) / Double(paces.count - midpoint)
        return secondAverage - firstAverage > 20
    }

    private var finishingSoon: Bool {
        if let targetDistance = sessionIntent?.resolvedTargetDistanceMeters, targetDistance > 0 {
            return targetDistance - snapshot.distanceMeters <= 400
        }
        if let targetDuration = sessionIntent?.resolvedTargetDurationSeconds, targetDuration > 0 {
            return targetDuration - snapshot.elapsedSeconds <= 120
        }
        return false
    }

    private var activeStep: SessionIntentStep? {
        guard let intent = sessionIntent else { return nil }
        let steps = intent.workoutSteps.filter { $0.durationSeconds > 0 }
        guard !steps.isEmpty else { return nil }

        var remainingElapsed = snapshot.elapsedSeconds
        for step in steps {
            if remainingElapsed < step.durationSeconds {
                return step
            }
            remainingElapsed -= step.durationSeconds
        }

        return steps.last
    }

    private var elevationGainMeters: Double? {
        let altitudes = recentSnapshots.compactMap(\.location?.altitudeMeters)
        guard altitudes.count >= 2 else { return nil }
        let gain = zip(altitudes, altitudes.dropFirst()).reduce(0.0) { total, pair in
            total + max(0, pair.1 - pair.0)
        }
        return gain > 0 ? gain : nil
    }

    private var gradePercent: Double? {
        let locations = recentSnapshots.compactMap(\.location)
        guard let first = locations.first,
              let last = locations.last
        else {
            return nil
        }

        let horizontalMeters = max(0, snapshot.distanceMeters - (recentSnapshots.dropLast().last?.distanceMeters ?? 0))
        guard horizontalMeters > 0 else { return nil }
        let grade = ((last.altitudeMeters - first.altitudeMeters) / horizontalMeters) * 100
        return grade.isFinite ? grade : nil
    }

    private var paceConfidence: String {
        if snapshot.currentPaceSecsPerKm == nil {
            return "low"
        }
        return snapshot.elapsedSeconds < 60 ? "medium" : "high"
    }

    private var heartRateConfidence: String {
        snapshot.heartRate == nil ? "missing" : "high"
    }

    private var gpsConfidence: String {
        guard let accuracy = snapshot.location?.horizontalAccuracyMeters else { return "missing" }
        switch accuracy {
        case ..<12:
            return "high"
        case ..<30:
            return "medium"
        default:
            return "low"
        }
    }

    private var athletePatterns: [String] {
        guard let profile else { return [] }

        var patterns = profile.athlete.weaknesses
        if !profile.memorySnapshot.recentInsight.isEmpty {
            patterns.append(profile.memorySnapshot.recentInsight)
        }
        return Array(patterns.prefix(3))
    }
}

struct SessionAnalysisResult: Equatable {
    let message: String
    let urgency: SessionAnalysisUrgency
    let shouldSpeak: Bool
    let generatedAt: Date
    let providerID: String
}

@MainActor
protocol SessionAnalysisProvider: AnyObject {
    var identifier: String { get }
    var displayName: String { get }

    func beginSession(profile: GuideProfile?, persona: GuidePersona?)
    func analyze(_ request: SessionAnalysisRequest) async throws -> SessionAnalysisResult
    func endSession()
}

extension SessionAnalysisProvider {
    func beginSession(profile: GuideProfile?, persona: GuidePersona?) {}
    func endSession() {}
}

enum SessionAnalysisProviderFactory {
    @MainActor
    static func makePreferredProvider() -> any SessionAnalysisProvider {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return AppleFoundationModelSessionAnalysisProvider()
        }
        #endif

        return RuleBasedSessionAnalysisProvider()
    }
}

@MainActor
final class RuleBasedSessionAnalysisProvider: SessionAnalysisProvider {
    let identifier = "rule-based-session-analyzer"
    let displayName = "Rule-Based Session Analyzer"
    private var messageCounter = 0

    func beginSession(profile: GuideProfile?, persona: GuidePersona?) {
        messageCounter = 0
    }

    func endSession() {
        messageCounter = 0
    }

    func analyze(_ request: SessionAnalysisRequest) async throws -> SessionAnalysisResult {
        messageCounter += 1
        guard let momentType = request.momentType else {
            return SessionAnalysisResult(
                message: "",
                urgency: .steady,
                shouldSpeak: false,
                generatedAt: Date(),
                providerID: identifier
            )
        }
        return SessionAnalysisResult(
            message: momentMessage(for: momentType, request: request),
            urgency: urgency(for: request),
            shouldSpeak: true,
            generatedAt: Date(),
            providerID: identifier
        )
    }

    private func momentMessage(
        for momentType: LiveGuidanceMomentType,
        request: SessionAnalysisRequest
    ) -> String {
        switch request.spokenLanguage {
        case .english:
            switch momentType {
            case .fastStart:
                return request.persona?.intensity == .driven
                    ? "Strong start. Control it now so you still own the finish."
                    : "The start is a little quick. Ease back and make the effort sustainable."
            case .paceDrift:
                return request.persona?.intensity == .calm
                    ? "The pace is drifting. Relax the shoulders and gently find your earlier rhythm."
                    : "Pace is drifting. Reset your form and bring the rhythm back under you."
            case .rhythmRecovery:
                return "That adjustment worked. You found the rhythm again."
            case .segmentTransition:
                return "New segment. Settle into its target before you press."
            case .finishOpportunity:
                return request.persona?.intensity == .driven
                    ? "You have enough left. Build the finish with control."
                    : "The finish is close. Stay composed and let the effort rise gradually."
            case .challengeStart:
                return "Challenge starts now. Build the pace smoothly."
            case .challengeComplete:
                return "Challenge complete. Settle back into your run."
            }
        case .spanish:
            switch momentType {
            case .fastStart: return "Has empezado un poco rápido. Baja el ritmo y haz que el esfuerzo sea sostenible."
            case .paceDrift: return "El ritmo está bajando. Relaja los hombros y recupera tu paso anterior."
            case .rhythmRecovery: return "Ese ajuste funcionó. Recuperaste el ritmo."
            case .segmentTransition: return "Nuevo segmento. Encuentra primero el objetivo y luego aprieta."
            case .finishOpportunity: return "El final está cerca. Mantén el control y aumenta el esfuerzo poco a poco."
            case .challengeStart: return "El reto empieza ahora. Aumenta el ritmo con control."
            case .challengeComplete: return "Reto completado. Vuelve a tu ritmo normal."
            }
        case .simplifiedChinese:
            switch momentType {
            case .fastStart: return "开局有点快。稍微放松，让体力能够持续到最后。"
            case .paceDrift: return "配速开始下降。放松肩膀，重新找回之前的节奏。"
            case .rhythmRecovery: return "刚才的调整有效。你重新找回节奏了。"
            case .segmentTransition: return "进入新阶段。先稳住目标，再逐渐发力。"
            case .finishOpportunity: return "终点快到了。保持稳定，再逐步加强。"
            case .challengeStart: return "挑战现在开始。平稳提高配速。"
            case .challengeComplete: return "挑战完成。回到正常跑步节奏。"
            }
        }
    }

    private func buildMessage(for request: SessionAnalysisRequest) -> String {
        if request.spokenLanguage != .english {
            return localizedMessage(for: request)
        }

        let snapshot = request.snapshot
        let sport = request.persona?.template.sport ?? .run
        let urgency = urgency(for: request)
        var parts: [String] = []

        if let opener = openingLine(for: request, urgency: urgency) {
            parts.append(opener)
        }

        if let pace = snapshot.currentPaceSecsPerKm {
            if let target = request.profile?.athlete.preferredPaceSecs {
                let delta = pace - target
                if delta > 15 {
                    parts.append(slowerThanTargetCue(for: request))
                } else if delta < -15 {
                    parts.append(fasterThanTargetCue(for: request))
                } else {
                    parts.append(alignedTargetCue(for: request))
                }
            } else if paceTrendIsSlowing(request.recentSnapshots) {
                parts.append(
                    sport == .bike
                        ? variant([
                            "Cadence is drifting a little. Smooth the pedal stroke and settle the breath.",
                            "The spin is getting choppy. Round it out and breathe deeper.",
                            "Bring the cadence back under you and make the effort smoother."
                        ])
                        : variant([
                            "Cadence is drifting. Reset the form and breathe low.",
                            "Your rhythm is getting a little loose. Quiet the upper body and reset.",
                            "Bring the stride back under control and let the breath settle."
                        ])
                )
            } else {
                parts.append(defaultSteadyCue(for: request))
            }
        } else {
            parts.append(
                sport == .bike
                    ? variant([
                        "Settle in first. Let the ride data stabilize before you chase speed.",
                        "Give the sensors a second and keep the opening smooth.",
                        "No rush. Let the ride settle before you push the pace."
                    ])
                    : variant([
                        "Settle in first. Let the GPS lock before you chase pace.",
                        "No rush. Let the opening minute smooth itself out.",
                        "Stay patient for a beat while the pace settles."
                    ])
            )
        }

        if let heartRate = snapshot.heartRate, heartRate > 185 {
            parts.append(variant([
                "Heart rate is high. Ease the effort and get the breathing back under you.",
                "That effort looks hot. Back off a touch and regain control.",
                "Bring it down slightly here and let the breath catch up."
            ]))
        } else if let insight = request.profile?.memorySnapshot.recentInsight, !insight.isEmpty {
            parts.append(insight)
        } else if let cue = personaStyleCue(for: request) {
            parts.append(cue)
        }

        return parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func localizedMessage(for request: SessionAnalysisRequest) -> String {
        let heartRateIsHigh = (request.snapshot.heartRate ?? 0) > 185
        let paceDelta = request.snapshot.currentPaceSecsPerKm.flatMap { pace in
            request.profile?.athlete.preferredPaceSecs.map { pace - $0 }
        }

        switch request.spokenLanguage {
        case .simplifiedChinese:
            if heartRateIsHigh { return "心率偏高。稍微放慢一点，调整呼吸，确认身体感觉良好。" }
            if let paceDelta, paceDelta > 15 { return "稍微加快脚步，平稳地回到目标节奏。" }
            if let paceDelta, paceDelta < -15 { return "现在有点快。稍微放松，保持后程体力。" }
            switch request.persona?.intensity ?? .balanced {
            case .calm: return "保持放松，呼吸平稳，让脚步自然流畅。"
            case .balanced: return "节奏不错。保持轻快脚步，继续稳稳向前。"
            case .driven: return "保持挺拔，脚步有力，继续推进。"
            }
        case .spanish:
            if heartRateIsHigh { return "El pulso está alto. Baja un poco el esfuerzo, recupera la respiración y comprueba cómo te sientes." }
            if let paceDelta, paceDelta > 15 { return "Aumenta el ritmo poco a poco hasta volver al objetivo." }
            if let paceDelta, paceDelta < -15 { return "Vas un poco rápido. Suelta el esfuerzo y guarda energía para después." }
            switch request.persona?.intensity ?? .balanced {
            case .calm: return "Mantente relajado, respira con calma y deja que fluya la zancada."
            case .balanced: return "Buen ritmo. Mantén los pasos ligeros y sigue avanzando con control."
            case .driven: return "Mantente erguido, pisa con fuerza y sigue empujando."
            }
        case .english:
            return defaultSteadyCue(for: request)
        }
    }

    private func urgency(for request: SessionAnalysisRequest) -> SessionAnalysisUrgency {
        if let heartRate = request.snapshot.heartRate, heartRate > 185 {
            return .caution
        }

        guard let pace = request.snapshot.currentPaceSecsPerKm,
              let target = request.profile?.athlete.preferredPaceSecs
        else {
            return .steady
        }

        return abs(pace - target) > 15 ? .opportunity : .steady
    }

    private func paceTrendIsSlowing(_ snapshots: [ActiveSessionSnapshot]) -> Bool {
        let paces = snapshots.compactMap(\.currentPaceSecsPerKm)
        guard paces.count >= 4 else { return false }

        let midpoint = paces.count / 2
        let firstAverage = paces[..<midpoint].reduce(0, +) / Double(midpoint)
        let secondAverage = paces[midpoint...].reduce(0, +) / Double(paces.count - midpoint)
        return secondAverage - firstAverage > 20
    }

    private func slowerThanTargetCue(for request: SessionAnalysisRequest) -> String {
        switch request.persona?.intensity ?? .balanced {
        case .calm:
            return variant([
                "Ease toward target gradually over the next minute.",
                "Nudge the effort up a little, not all at once.",
                "Gently build from here and let the pace come to you."
            ])
        case .balanced:
            return variant([
                "Ease into a stronger rhythm over the next minute.",
                "Bring the effort up a notch and reconnect with the pace.",
                "There is room to press a little here. Build into it."
            ])
        case .driven:
            return variant([
                "Close the gap with control. Lift cadence now.",
                "You can give this more. Sharpen the rhythm and go get it.",
                "Bring the pace up with purpose. Quicken the turnover now."
            ])
        }
    }

    private func fasterThanTargetCue(for request: SessionAnalysisRequest) -> String {
        switch request.persona?.intensity ?? .balanced {
        case .calm:
            return variant([
                "Back off a touch and keep the effort sustainable.",
                "Soften this slightly and make it feel easier again.",
                "Take half a step back and keep the effort smooth."
            ])
        case .balanced:
            return variant([
                "Back off slightly so you have enough left late.",
                "Dial it back a fraction and save the stronger effort for later.",
                "Control the pace here so the back half stays strong."
            ])
        case .driven:
            return variant([
                "Do not burn the match early. Control this pace.",
                "Strong is fine. Wasteful is not. Bring it under control.",
                "Too hot right now. Settle it before it costs you later."
            ])
        }
    }

    private func defaultSteadyCue(for request: SessionAnalysisRequest) -> String {
        let sport = request.persona?.template.sport ?? .run
        switch request.persona?.intensity ?? .balanced {
        case .calm:
            return sport == .bike
                ? variant([
                    "Keep the pedals smooth.",
                    "Nice and even through the pedal stroke.",
                    "Stay relaxed and keep the spin tidy."
                ])
                : variant([
                    "Keep the effort relaxed and smooth.",
                    "Stay easy and let the stride stay quiet.",
                    "This is good. Keep it loose and steady."
                ])
        case .balanced:
            return variant([
                "Keep the effort smooth.",
                "This rhythm works. Stay right here.",
                "Settle into this pace and keep it clean."
            ])
        case .driven:
            return sport == .bike
                ? variant([
                    "Hold pressure through the pedals.",
                    "Stay loaded and keep the power clean.",
                    "Keep driving, but keep it smooth."
                ])
                : variant([
                    "Stay sharp and keep moving well.",
                    "Hold the rhythm and keep the stride snappy.",
                    "You are in a good place. Stay switched on."
                ])
        }
    }

    private func personaStyleCue(for request: SessionAnalysisRequest) -> String? {
        guard let persona = request.persona else { return nil }

        switch (persona.template.sport, persona.intensity) {
        case (.run, .calm):
            return variant(["Light feet, quiet shoulders.", "Easy shoulders. Light steps.", "Keep the feet quick and the shoulders soft."])
        case (.run, .driven):
            return variant(["Stay tall and commit to the stride.", "Tall posture. Strong stride.", "Stand up into the stride and keep it decisive."])
        case (.bike, .calm):
            return variant(["Quiet upper body, even pedal stroke.", "Keep the torso calm and the cadence even.", "Relax the upper body and make the spin smooth."])
        case (.bike, .driven):
            return variant(["Stay loaded and drive clean power.", "Strong legs, quiet upper body.", "Keep the pressure on without getting ragged."])
        default:
            return nil
        }
    }

    private func alignedTargetCue(for request: SessionAnalysisRequest) -> String {
        let sport = request.persona?.template.sport ?? .run
        return sport == .bike
            ? variant([
                "That is right where you want it. Keep the ride flowing.",
                "Good line. Hold this effort.",
                "You are right on it. Keep the pressure smooth."
            ])
            : variant([
                "You are right where you want to be. Stay with it.",
                "That pace is landing well. Hold the rhythm.",
                "Good line. Keep this effort smooth."
            ])
    }

    private func openingLine(for request: SessionAnalysisRequest, urgency: SessionAnalysisUrgency) -> String? {
        let minutes = max(1, request.snapshot.elapsedSeconds / 60)
        let distance = String(format: "%.1f", request.snapshot.distanceKilometers)
        let sport = request.persona?.template.sport ?? .run

        if request.snapshot.elapsedSeconds <= 90 {
            if let sessionStartLine = sessionStartLine(for: request, sport: sport) {
                return sessionStartLine
            }

            return sport == .bike
                ? variant([
                    "Nice easy start.",
                    "Good, you are rolling now.",
                    "Settle into the ride."
                ])
                : variant([
                    "Good, you are underway.",
                    "Nice easy start.",
                    "You are in it now."
                ])
        }

        if let finishingLine = finishingGoalLine(for: request) {
            return finishingLine
        }

        guard messageCounter.isMultiple(of: 3) else { return nil }

        if let plannedProgressLine = plannedProgressLine(for: request) {
            return plannedProgressLine
        }

        switch urgency {
        case .steady:
            return variant([
                "\(minutes) minutes in. Stay with the rhythm.",
                "\(distance) k done. Keep it smooth.",
                "This is a good point to reset and stay tidy."
            ])
        case .opportunity:
            return variant([
                "\(minutes) minutes in. There is room to move here.",
                "\(distance) k in. This is your chance to sharpen it.",
                "You are far enough in now to work a little more."
            ])
        case .caution:
            return variant([
                "Check in with the effort here.",
                "This is a good time to steady things down.",
                "Settle first, then rebuild."
            ])
        }
    }

    private func sessionStartLine(for request: SessionAnalysisRequest, sport: SportType) -> String? {
        guard let intent = request.sessionIntent else { return nil }
        let fallback = sport == .bike ? "Settle into the ride." : "Keep the start smooth."

        if let goal = spokenGoalSummary(for: intent) {
            return "\(intent.title) is underway. \(goal)"
        }

        return "\(intent.title) is underway. \(fallback)"
    }

    private func plannedProgressLine(for request: SessionAnalysisRequest) -> String? {
        guard let intent = request.sessionIntent else { return nil }

        if let activeStep = activeStep(for: intent, elapsedSeconds: request.snapshot.elapsedSeconds),
           intent.workoutSteps.count > 1 {
            return "Step \(activeStep.index + 1) of \(activeStep.count): \(activeStep.step.label). Keep it controlled."
        }

        if let targetDistance = intent.resolvedTargetDistanceMeters, targetDistance > 0 {
            let progress = request.snapshot.distanceMeters / targetDistance
            if progress >= 0.72 {
                return "\(spokenDistance(max(0, targetDistance - request.snapshot.distanceMeters))) left in \(intent.title). Hold this rhythm."
            }
            if progress >= 0.48 {
                return "Halfway through \(intent.title). Stay smooth and patient."
            }
            if progress >= 0.22 {
                return "\(spokenDistance(request.snapshot.distanceMeters)) into \(spokenDistance(targetDistance)). Keep the effort tidy."
            }
        }

        if let targetDuration = intent.resolvedTargetDurationSeconds, targetDuration > 0 {
            let progress = Double(request.snapshot.elapsedSeconds) / Double(targetDuration)
            let remaining = max(0, targetDuration - request.snapshot.elapsedSeconds)
            if progress >= 0.72 {
                return "\(spokenDuration(remaining)) left in \(intent.title). Keep the rhythm calm."
            }
            if progress >= 0.48 {
                return "Halfway through \(intent.title). Keep the effort even."
            }
        }

        if let routeName = intent.routeName, !routeName.isEmpty {
            return "Stay with \(routeName). Keep the effort smooth."
        }

        return nil
    }

    private func finishingGoalLine(for request: SessionAnalysisRequest) -> String? {
        guard let intent = request.sessionIntent else { return nil }

        if let targetDistance = intent.resolvedTargetDistanceMeters, targetDistance > 0 {
            let remaining = targetDistance - request.snapshot.distanceMeters
            if remaining <= 0 {
                return "\(intent.title) distance is covered. Ease through the finish."
            }
            if remaining <= 400 {
                return "\(spokenDistance(remaining)) left in \(intent.title). Stay tall and finish clean."
            }
        }

        if let targetDuration = intent.resolvedTargetDurationSeconds, targetDuration > 0 {
            let remaining = targetDuration - request.snapshot.elapsedSeconds
            if remaining <= 0 {
                return "\(intent.title) time is covered. Bring it down smoothly."
            }
            if remaining <= 120 {
                return "\(spokenDuration(remaining)) left in \(intent.title). Stay composed."
            }
        }

        return nil
    }

    private func activeStep(
        for intent: SessionIntent,
        elapsedSeconds: Int
    ) -> (index: Int, count: Int, step: SessionIntentStep)? {
        let steps = intent.workoutSteps.filter { $0.durationSeconds > 0 }
        guard !steps.isEmpty else { return nil }

        var remainingElapsed = elapsedSeconds
        for (index, step) in steps.enumerated() {
            if remainingElapsed < step.durationSeconds {
                return (index, steps.count, step)
            }
            remainingElapsed -= step.durationSeconds
        }

        guard let finalStep = steps.last else { return nil }
        return (steps.count - 1, steps.count, finalStep)
    }

    private func spokenGoalSummary(for intent: SessionIntent) -> String? {
        let distance = intent.resolvedTargetDistanceMeters.map(spokenDistance)
        let duration = intent.resolvedTargetDurationSeconds.map(spokenDuration)

        if let routeName = intent.routeName, !routeName.isEmpty, let distance {
            return "Follow \(routeName) for \(distance)."
        }
        if let routeName = intent.routeName, !routeName.isEmpty {
            return "Follow \(routeName)."
        }
        if let distance, let duration {
            return "Goal is \(distance) over \(duration)."
        }
        if let distance {
            return "Goal is \(distance)."
        }
        if let duration {
            return "Goal is \(duration)."
        }
        if intent.workoutSteps.count > 1 {
            return "Planned workout has \(intent.workoutSteps.count) steps."
        }

        return nil
    }

    private func spokenDistance(_ meters: Double) -> String {
        meters.spokenDistanceString
    }

    private func spokenDuration(_ seconds: Int) -> String {
        guard seconds > 0 else { return "0 minutes" }

        if seconds >= 3600 {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            return minutes > 0 ? "\(hours) hours \(minutes) minutes" : "\(hours) hours"
        }

        let minutes = max(1, Int((Double(seconds) / 60.0).rounded()))
        return "\(minutes) minutes"
    }

    private func variant(_ options: [String]) -> String {
        guard !options.isEmpty else { return "" }
        return options[(max(messageCounter, 1) - 1) % options.count]
    }
}
