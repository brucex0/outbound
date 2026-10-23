import Foundation

@MainActor
final class ServerLiveCoachProvider: SessionAnalysisProvider {
    let identifier = "plainstride-server-live-coach"
    let displayName = "Plainstride Live Coach"

    private let controller = LiveCoachSessionController()
    var progressPolicy: LiveCoachProgressPolicyDTO? { controller.progressPolicy }
    var scheduledInstructions: [ScheduledGuideInstruction] { controller.scheduledInstructions }
    var pacerIntroduction: PacerIntroduction? { controller.pacerIntroduction }

    func beginSession(
        profile: GuideProfile?,
        persona: GuidePersona?,
        sessionIntent: SessionIntent?,
        companionBrief: CompanionSessionBriefDTO?,
        unitSystem: MeasurementUnitSystem,
        weatherSnapshot: RunningWeatherSnapshot?,
        isIndoor: Bool
    ) {
        controller.begin(
            profile: profile,
            persona: persona,
            intent: sessionIntent,
            companionBrief: companionBrief,
            unitSystem: unitSystem,
            weatherSnapshot: weatherSnapshot,
            isIndoor: isIndoor
        )
    }

    func analyze(_ request: SessionAnalysisRequest) async throws -> SessionAnalysisResult {
        guard let moment = request.momentType else {
            return silentResult(source: .cachedFallback, result: .invalid, latency: .underOneSecond)
        }
        guard request.sessionIntent?.resolvedActivityType == .running else {
            return await immediateFallback(
                for: moment,
                preferredMessage: request.preferredMessage,
                result: .success,
                latency: .underOneSecond
            )
        }

        let startedAt = Date()
        return try await LiveCoachAnalysisRace().run(
            deadlineNanoseconds: LiveCoachAudioTiming.cloudAudioDeadlineNanoseconds,
            operation: { @MainActor [weak self] in
                guard let self else { throw CancellationError() }
                return try await self.analyzeServer(request, moment: moment, startedAt: startedAt)
            },
            fallback: { @MainActor [weak self] in
                guard let self else { throw CancellationError() }
                return await self.immediateFallback(
                    for: moment,
                    preferredMessage: request.preferredMessage,
                    result: .timeout,
                    latency: LiveCoachLatencyBucket(seconds: Date().timeIntervalSince(startedAt))
                )
            }
        )
    }

    private func analyzeServer(
        _ request: SessionAnalysisRequest,
        moment: LiveGuidanceMomentType,
        startedAt: Date
    ) async throws -> SessionAnalysisResult {

        let segment = workoutSegment(request.sessionIntent, elapsedSeconds: request.snapshot.elapsedSeconds)
        let athleteReferencePace = athleteReferencePace(request.profile)
        let activeCoachingSegment = request.sessionIntent?.activeCoachingSegment(
            at: request.snapshot.elapsedSeconds
        )
        let targetPace: Double?
        if let activeCoachingSegment {
            targetPace = activeCoachingSegment.target.pace?.resolvedTarget(
                athleteReferencePace: athleteReferencePace
            )
        } else {
            targetPace = request.sessionIntent?.raceIntent?.targetPaceSecondsPerKilometer ?? athleteReferencePace
        }
        let cueRequest = LiveCoachCueRequest(
            cueRequestId: UUID(),
            moment: moment.rawValue,
            detectedAtElapsedSeconds: request.snapshot.elapsedSeconds,
            validForMilliseconds: 5_000,
            selectedPhraseId: nil,
            liveState: .init(
                elapsedSeconds: request.snapshot.elapsedSeconds,
                distanceMeters: request.snapshot.distanceMeters,
                remainingDistanceMeters: request.remainingDistanceMeters,
                currentPaceSecondsPerKilometer: validPace(request.snapshot.currentPaceSecsPerKm),
                rollingPaceSecondsPerKilometer: rollingPace(request.recentSnapshots),
                targetPaceSecondsPerKilometer: targetPace,
                gradePercent: rollingGrade(request.recentSnapshots),
                workoutSegmentIndex: segment?.index,
                workoutSegmentPhase: segment?.phase,
                routeGuidanceActive: request.routeGuidanceActive
            )
        )

        do {
            let response = try await controller.requestCueStream(
                cueRequest,
                instructionID: request.instructionID
            )
            let metadata = response.metadata
            let latency = LiveCoachLatencyBucket(seconds: Date().timeIntervalSince(startedAt))
            guard metadata.expiresAt > Date() else {
                return silentResult(source: metadata.source, result: .stale, latency: latency)
            }
            let fallback = Self.fallback(for: moment, language: AppLanguage.current)
            let localPreferredText = (moment == .progress || moment == .workoutInstruction)
                ? request.preferredMessage
                : nil
            let fixedSource = metadata.source == .fixedPack || metadata.source == .cachedFallback
            let message = fixedSource ? localPreferredText ?? fallback.text : metadata.transcript
            let audioMatchesMessage = metadata.transcript == message
            let fallbackKey = localPreferredText == nil ? metadata.fixedCueKey ?? fallback.key : nil
            let fallbackAudio: Data? = if audioMatchesMessage, let cached = response.cachedAudioData {
                cached
            } else if let fallbackKey {
                await GuideAudioPackStore.shared.cachedOrBundledAudioData(for: fallbackKey, transcript: message)
            } else {
                nil
            }
            guard metadata.expiresAt > Date() else {
                return silentResult(source: metadata.source, result: .stale, latency: latency)
            }
            return SessionAnalysisResult(
                message: message,
                urgency: SessionAnalysisUrgency(rawValue: metadata.urgency) ?? .steady,
                shouldSpeak: !message.isEmpty,
                generatedAt: metadata.generatedAt,
                expiresAt: metadata.expiresAt,
                providerID: identifier,
                source: metadata.source,
                result: metadata.result,
                effectiveMode: controller.effectiveMode,
                accessReason: controller.accessReason,
                latencyBucket: latency,
                fixedCueKey: fallbackKey,
                audioData: fallbackAudio,
                audioStream: audioMatchesMessage ? response.audioStream : nil
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled { throw CancellationError() }
            ActivityDiagnosticLog.error(.lifecycle, "Coach cue request failed error=\(ActivityDiagnosticLog.errorCategory(error))")
            return await immediateFallback(
                for: moment,
                preferredMessage: request.preferredMessage,
                result: .unavailable,
                latency: LiveCoachLatencyBucket(seconds: Date().timeIntervalSince(startedAt))
            )
        }
    }

    func endSession(report: LiveGuidanceSessionReport?) {
        controller.end(report: report)
    }

    private func immediateFallback(
        for moment: LiveGuidanceMomentType,
        preferredMessage: String?,
        result: LiveCoachCueResult,
        latency: LiveCoachLatencyBucket
    ) async -> SessionAnalysisResult {
        let fallback = Self.fallback(for: moment, language: AppLanguage.current)
        let message = preferredMessage ?? fallback.text
        let fixedCueKey = preferredMessage == nil && !message.isEmpty ? fallback.key : nil
        let audioData: Data?
        if let fixedCueKey {
            audioData = await GuideAudioPackStore.shared.cachedOrBundledAudioData(for: fixedCueKey, transcript: message)
        } else {
            audioData = nil
        }
        return SessionAnalysisResult(
            message: message,
            urgency: Self.urgency(for: moment),
            shouldSpeak: !message.isEmpty,
            generatedAt: Date(),
            expiresAt: Date().addingTimeInterval(5),
            providerID: identifier,
            source: .cachedFallback,
            result: result,
            effectiveMode: controller.effectiveMode,
            accessReason: controller.accessReason,
            latencyBucket: latency,
            fixedCueKey: fixedCueKey,
            audioData: audioData,
            audioStream: nil
        )
    }

    private func silentResult(
        source: LiveCoachCueSource,
        result: LiveCoachCueResult,
        latency: LiveCoachLatencyBucket
    ) -> SessionAnalysisResult {
        SessionAnalysisResult(
            message: "",
            urgency: .steady,
            shouldSpeak: false,
            generatedAt: Date(),
            expiresAt: Date(),
            providerID: identifier,
            source: source,
            result: result,
            effectiveMode: controller.effectiveMode,
            accessReason: controller.accessReason,
            latencyBucket: latency,
            fixedCueKey: nil,
            audioData: nil,
            audioStream: nil
        )
    }

    private func validPace(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (60...3_600).contains(value) else { return nil }
        return value
    }

    private func rollingPace(_ snapshots: [ActiveSessionSnapshot]) -> Double? {
        let values = snapshots.suffix(6).compactMap(\.currentPaceSecsPerKm).filter {
            $0.isFinite && (60...3_600).contains($0)
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func athleteReferencePace(_ profile: GuideProfile?) -> Double? {
        if let preferred = validPace(profile?.athlete.preferredPaceSecs) {
            return preferred
        }
        let values = profile?.memorySnapshot.recentActivities
            .compactMap { validPace($0.avgPaceSecs) }
            .sorted() ?? []
        guard !values.isEmpty else { return nil }
        let middle = values.count / 2
        return values.count.isMultiple(of: 2)
            ? (values[middle - 1] + values[middle]) / 2
            : values[middle]
    }

    private func rollingGrade(_ snapshots: [ActiveSessionSnapshot]) -> Double? {
        guard let endElapsed = snapshots.last?.elapsedSeconds else { return nil }
        return LiveTerrainGradeEstimator.grade(
            from: snapshots.filter { $0.elapsedSeconds >= endElapsed - 45 }
        )
    }

    private func workoutSegment(
        _ intent: SessionIntent?,
        elapsedSeconds: Int
    ) -> (index: Int?, phase: String)? {
        let steps = intent?.workoutSteps.filter { $0.durationSeconds > 0 } ?? []
        guard !steps.isEmpty else {
            return intent?.coachingTarget.map { (nil, $0.phase.rawValue) }
        }
        var boundary = 0
        for (index, step) in steps.enumerated() {
            boundary += step.durationSeconds
            guard elapsedSeconds < boundary else { continue }
            return step.coachingTarget.map { (index, $0.phase.rawValue) }
        }
        return steps.last?.coachingTarget.map { (steps.count - 1, $0.phase.rawValue) }
    }

    private static func looksLikeBoundedWAV(_ data: Data) -> Bool {
        guard (44...512 * 1_024).contains(data.count) else { return false }
        guard String(data: data.prefix(4), encoding: .ascii) == "RIFF",
              String(data: data.dropFirst(8).prefix(4), encoding: .ascii) == "WAVE"
        else { return false }
        var offset = 12
        var formatIsValid = false
        var audioByteCount = 0
        while offset + 8 <= data.count {
            let chunkID = String(data: data[offset..<(offset + 4)], encoding: .ascii)
            let chunkSize = littleEndian32(data, offset + 4)
            let payloadOffset = offset + 8
            guard chunkSize >= 0, payloadOffset + chunkSize <= data.count else { return false }
            if chunkID == "fmt ", chunkSize >= 16 {
                formatIsValid = littleEndian16(data, payloadOffset) == 1
                    && littleEndian16(data, payloadOffset + 2) == 1
                    && littleEndian32(data, payloadOffset + 4) == 24_000
                    && littleEndian16(data, payloadOffset + 14) == 16
            } else if chunkID == "data" {
                audioByteCount += chunkSize
            }
            offset = payloadOffset + chunkSize + chunkSize % 2
        }
        let durationMilliseconds = Double(audioByteCount) / 48_000 * 1_000
        return formatIsValid && audioByteCount > 0 && durationMilliseconds <= 8_000
    }

    private static func littleEndian16(_ data: Data, _ offset: Int) -> Int {
        Int(data[offset]) | Int(data[offset + 1]) << 8
    }

    private static func littleEndian32(_ data: Data, _ offset: Int) -> Int {
        Int(data[offset])
            | Int(data[offset + 1]) << 8
            | Int(data[offset + 2]) << 16
            | Int(data[offset + 3]) << 24
    }

    private static func urgency(for moment: LiveGuidanceMomentType) -> SessionAnalysisUrgency {
        switch moment {
        case .progress, .targetLocked, .rhythmRecovery, .resumeAfterBreak,
             .crestRecovery, .challengeComplete, .racePaceLocked, .raceHalfwayAssessment:
            .steady
        case .earlyOverpace, .paceAboveTarget, .paceBelowTarget, .paceInstability,
             .paceDrift, .recoveryTooHard, .climbStart, .segmentTransition,
             .finishOpportunity, .challengeStart, .workoutInstruction, .raceStartRestraint,
             .raceLateFade, .raceLateStrength, .raceFinalKilometer:
            .opportunity
        case .unexpectedStop:
            .caution
        }
    }

    static func fallback(
        for moment: LiveGuidanceMomentType,
        language: AppLanguage
    ) -> (key: String, text: String) {
        if moment == .progress { return ("", "") }
        let key: String
        switch moment {
        case .progress: key = "progress.steady"
        case .earlyOverpace: key = "coach.early_settle"
        case .paceAboveTarget: key = "coach.ease_to_target"
        case .paceBelowTarget: key = "coach.lift_to_target"
        case .paceInstability: key = "coach.smooth_pace"
        case .targetLocked: key = "progress.steady"
        case .paceDrift: key = "coach.rebuild_rhythm"
        case .rhythmRecovery: key = "coach.rhythm_recovered"
        case .recoveryTooHard: key = "coach.recovery_easy"
        case .unexpectedStop: key = "workout.pause"
        case .resumeAfterBreak: key = "workout.resume"
        case .climbStart: key = "coach.climb_by_effort"
        case .crestRecovery: key = "coach.crest_reset"
        case .segmentTransition: key = "workout.segment_start"
        case .finishOpportunity: key = "coach.strong_finish"
        case .raceStartRestraint: key = "race.start_restraint"
        case .racePaceLocked: key = "progress.steady"
        case .raceHalfwayAssessment: key = "progress.halfway"
        case .raceLateFade: key = "coach.rebuild_rhythm"
        case .raceLateStrength, .raceFinalKilometer: key = "coach.strong_finish"
        case .challengeStart: key = "challenge.start"
        case .challengeComplete: key = "challenge.complete"
        case .workoutInstruction: key = "workout.segment_start"
        }
        let texts: [String: [String: String]] = [
            AppLanguage.english.rawValue: [
                "progress.halfway": "You are halfway to your goal.",
                "race.start_restraint": "Start the race at a controlled pace. Save a speed increase for later.",
                "progress.steady": "You are holding your target pace. Keep it steady.",
                "coach.early_settle": "You are starting faster than your target. Slow down gradually to avoid an opening surge.",
                "coach.ease_to_target": "You are above your target pace. Slow down gradually to return to it.",
                "coach.lift_to_target": "You are below your target pace. Speed up gradually without an abrupt surge.",
                "coach.smooth_pace": "Your pace shifted outside the target range. Adjust gradually back to target.",
                "coach.rebuild_rhythm": "You have slowed below your target pace. If comfortable, return to it gradually.",
                "coach.recovery_easy": "You are moving faster than this easy segment calls for. Slow to a conversational effort.",
                "coach.climb_by_effort": "You are on a climb. Shorten your steps and let your pace slow.",
                "coach.crest_reset": "The climb is easing. Keep effort easy before gradually increasing speed.",
                "coach.settle": "You sped up too fast. Keep a steady pace and speed up gradually.",
                "coach.restore_rhythm": "Your speed dropped sharply. If you meant to keep running, return to your pace gradually.",
                "coach.rhythm_recovered": "You are closer to your target pace now. Hold it before adjusting again.",
                "workout.pause": "Workout paused.",
                "workout.resume": "Workout resumed.",
                "workout.segment_start": "The next workout segment starts now. Adjust gradually to its prescribed effort.",
                "coach.strong_finish": "The finish is near. If comfortable, build speed gradually and avoid sprinting.",
                "challenge.start": "Your challenge starts now. Increase pace gradually and keep the effort controlled.",
                "challenge.complete": "Your challenge is complete. Ease back to the pace you held before it."
            ],
            AppLanguage.spanish.rawValue: [
                "progress.halfway": "Has llegado a la mitad de tu objetivo.",
                "race.start_restraint": "Empieza la carrera a un ritmo controlado. Deja los aumentos de velocidad para más adelante.",
                "progress.steady": "Estás manteniendo el ritmo objetivo. Sigue a ese ritmo.",
                "coach.early_settle": "Has empezado por encima del ritmo objetivo. Baja la velocidad poco a poco, sin cambios bruscos.",
                "coach.ease_to_target": "Vas por encima del ritmo objetivo. Baja la velocidad poco a poco hasta recuperarlo.",
                "coach.lift_to_target": "Vas por debajo del ritmo objetivo. Acelera poco a poco, sin un cambio brusco.",
                "coach.smooth_pace": "Tu ritmo ha cambiado y está fuera del objetivo. Vuelve a él poco a poco.",
                "coach.rebuild_rhythm": "Has bajado del ritmo objetivo. Si te sientes cómodo, vuelve a él poco a poco.",
                "coach.recovery_easy": "Vas más rápido de lo indicado para este tramo suave. Baja a un esfuerzo que te permita conversar.",
                "coach.climb_by_effort": "Estás en una subida. Acorta los pasos y deja que baje la velocidad.",
                "coach.crest_reset": "La subida está aflojando. Mantén un esfuerzo suave antes de acelerar poco a poco.",
                "coach.settle": "Has acelerado demasiado rápido. Mantén un ritmo constante y aumenta la velocidad poco a poco.",
                "coach.restore_rhythm": "Tu velocidad ha bajado de golpe. Si querías seguir corriendo, recupera tu ritmo poco a poco.",
                "coach.rhythm_recovered": "Ahora estás más cerca del ritmo objetivo. Mantenlo antes de volver a ajustar.",
                "workout.pause": "Entrenamiento en pausa.",
                "workout.resume": "Entrenamiento reanudado.",
                "workout.segment_start": "Empieza el siguiente tramo. Ajusta el esfuerzo poco a poco según lo indicado.",
                "coach.strong_finish": "La meta está cerca. Si te sientes cómodo, acelera poco a poco, sin esprintar.",
                "challenge.start": "Tu reto empieza ahora. Acelera poco a poco y mantén el esfuerzo bajo control.",
                "challenge.complete": "Has completado el reto. Vuelve poco a poco al ritmo que llevabas antes."
            ],
            AppLanguage.simplifiedChinese.rawValue: [
                "progress.halfway": "目标已完成一半。",
                "race.start_restraint": "比赛刚开始，先控制好配速，留到后面再考虑提速。",
                "progress.steady": "你正保持在目标配速，继续稳住这个速度。",
                "coach.early_settle": "起步已快于目标配速，逐步放慢，不要在开头猛冲。",
                "coach.ease_to_target": "当前速度高于目标配速，逐步放慢，回到目标范围。",
                "coach.lift_to_target": "当前速度低于目标配速，慢慢提速，不要突然加速。",
                "coach.smooth_pace": "配速变化后已偏离目标范围，逐步调整回目标配速。",
                "coach.rebuild_rhythm": "速度已降到目标配速以下，如果感觉轻松，就逐步恢复到目标配速。",
                "coach.recovery_easy": "这一段快于目标配速，请放慢到能轻松交谈的强度。",
                "coach.climb_by_effort": "现在正在上坡，步子小一点，允许速度慢下来。",
                "coach.crest_reset": "坡度缓下来了，先保持轻松，再考虑逐步提速。",
                "coach.settle": "刚才加速太急了。保持配速稳定，提速时慢慢来。",
                "coach.restore_rhythm": "刚才速度明显下降了。如果不是打算休息，就慢慢恢复到之前的配速。",
                "coach.rhythm_recovered": "现在更接近目标配速了，先保持住，不要急着再次调整。",
                "workout.pause": "训练已暂停。",
                "workout.resume": "训练已恢复。",
                "workout.segment_start": "下一训练阶段开始了，按这一段的要求逐步调整强度。",
                "coach.strong_finish": "终点就在前面，如果感觉轻松，可以逐步加速，不要突然冲刺。",
                "challenge.start": "挑战现在开始，逐步提速，保持强度可控。",
                "challenge.complete": "挑战已完成，逐步回到挑战前的配速。"
            ]
        ]
        guard let text = texts[language.rawValue]?[key] else {
            ActivityDiagnosticLog.error(.lifecycle,
                "Coach fallback script unavailable moment=\(moment.rawValue) locale=\(language.rawValue) cue=\(key)")
            return (key, "")
        }
        return (key, text)
    }
}

@MainActor
private final class LiveCoachAnalysisRace {
    private var continuation: CheckedContinuation<SessionAnalysisResult, Error>?
    private var operationTask: Task<Void, Never>?
    private var deadlineTask: Task<Void, Never>?
    private var deadlineExpired = false

    func run(
        deadlineNanoseconds: UInt64,
        operation: @escaping @MainActor () async throws -> SessionAnalysisResult,
        fallback: @escaping @MainActor () async throws -> SessionAnalysisResult
    ) async throws -> SessionAnalysisResult {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                guard !Task.isCancelled else {
                    self.resolve(.failure(CancellationError()))
                    return
                }
                operationTask = Task { @MainActor [weak self] in
                    guard let self else { return }
                    do {
                        let result = try await operation()
                        guard !self.deadlineExpired, !Task.isCancelled else { return }
                        self.resolve(.success(result))
                    } catch {
                        guard !self.deadlineExpired, !Task.isCancelled else { return }
                        self.resolve(.failure(error))
                    }
                }
                deadlineTask = Task { @MainActor [weak self] in
                    do {
                        try await Task.sleep(nanoseconds: deadlineNanoseconds)
                        guard let self else { return }
                        self.deadlineExpired = true
                        self.operationTask?.cancel()
                        self.resolve(.success(try await fallback()))
                    } catch is CancellationError {
                        return
                    } catch {
                        self?.resolve(.failure(error))
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.resolve(.failure(CancellationError()))
            }
        }
    }

    private func resolve(_ result: Result<SessionAnalysisResult, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        operationTask?.cancel()
        deadlineTask?.cancel()
        operationTask = nil
        deadlineTask = nil
        continuation.resume(with: result)
    }
}
