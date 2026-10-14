import Foundation

@MainActor
final class ServerLiveCoachProvider: SessionAnalysisProvider {
    let identifier = "plainstride-server-live-coach"
    let displayName = "Plainstride Live Coach"

    private let controller = LiveCoachSessionController()
    var progressPolicy: LiveCoachProgressPolicyDTO? { controller.progressPolicy }

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
        let fixedCueKey = preferredMessage == nil ? fallback.key : nil
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

    private static func fallback(
        for moment: LiveGuidanceMomentType,
        language: AppLanguage
    ) -> (key: String, text: String) {
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
        case .raceStartRestraint: key = "coach.early_settle"
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
                "progress.steady": "Keep this pace and effort comfortable.",
                "coach.early_settle": "Start a little slower; give yourself time to warm up.",
                "coach.ease_to_target": "Slow down gradually toward your target pace.",
                "coach.lift_to_target": "Speed up gradually toward your target pace.",
                "coach.smooth_pace": "Adjust gradually toward your target pace, then hold it.",
                "coach.rebuild_rhythm": "If it feels manageable, gradually return to your target pace.",
                "coach.recovery_easy": "Slow to an easy jog; you should be able to speak a full sentence.",
                "coach.climb_by_effort": "Take shorter steps uphill and let your pace slow.",
                "coach.crest_reset": "The hill is easing; keep the effort easy before speeding up.",
                "coach.settle": "Slow down until you can speak a full sentence.",
                "coach.restore_rhythm": "Keep the effort easy; there is no need to make up lost time.",
                "coach.rhythm_recovered": "Your pace is closer to the target now; keep the effort controlled.",
                "workout.pause": "Workout paused.",
                "workout.resume": "Workout resumed.",
                "workout.segment_start": "New segment. Settle into the target before you press.",
                "coach.strong_finish": "If you still feel comfortable, speed up gradually toward the finish.",
                "challenge.start": "Challenge starts now. Build the pace smoothly.",
                "challenge.complete": "Challenge complete. Settle back into your run."
            ],
            AppLanguage.spanish.rawValue: [
                "progress.steady": "Mantén este ritmo con un esfuerzo cómodo.",
                "coach.early_settle": "Empieza un poco más despacio y date tiempo para calentar.",
                "coach.ease_to_target": "Baja poco a poco hasta el ritmo objetivo.",
                "coach.lift_to_target": "Acelera poco a poco hasta el ritmo objetivo.",
                "coach.smooth_pace": "Acércate poco a poco al ritmo objetivo y mantenlo.",
                "coach.rebuild_rhythm": "Si te resulta cómodo, vuelve poco a poco al ritmo objetivo.",
                "coach.recovery_easy": "Baja a un trote suave; deberías poder decir una frase completa.",
                "coach.climb_by_effort": "Da pasos más cortos al subir y deja que baje el ritmo.",
                "coach.crest_reset": "La cuesta afloja; mantén un esfuerzo suave antes de acelerar.",
                "coach.settle": "Baja el ritmo hasta poder decir una frase completa.",
                "coach.restore_rhythm": "Mantén un esfuerzo suave; no hace falta recuperar el tiempo perdido.",
                "coach.rhythm_recovered": "Ahora estás más cerca del ritmo objetivo; mantén el esfuerzo controlado.",
                "workout.pause": "Entrenamiento en pausa.",
                "workout.resume": "Entrenamiento reanudado.",
                "workout.segment_start": "Nuevo segmento. Encuentra el objetivo antes de apretar.",
                "coach.strong_finish": "Si aún te sientes cómodo, acelera poco a poco hasta el final.",
                "challenge.start": "Empieza el reto. Aumenta el ritmo con suavidad.",
                "challenge.complete": "Reto completado. Vuelve a tu ritmo de carrera."
            ],
            AppLanguage.simplifiedChinese.rawValue: [
                "progress.steady": "保持这个配速，强度以舒服为准。",
                "coach.early_settle": "起步稍慢一点，给身体时间热身。",
                "coach.ease_to_target": "逐步放慢，回到目标配速。",
                "coach.lift_to_target": "逐步加速，回到目标配速。",
                "coach.smooth_pace": "逐步调整到目标配速，然后保持。",
                "coach.rebuild_rhythm": "如果感觉还能轻松应对，就逐步回到目标配速。",
                "coach.recovery_easy": "放慢到轻松慢跑，应该能说出一句完整的话。",
                "coach.climb_by_effort": "上坡时步子小一点，允许配速慢下来。",
                "coach.crest_reset": "坡度缓下来了，先轻松跑一会儿，再考虑加速。",
                "coach.settle": "放慢到能说出一句完整的话。",
                "coach.restore_rhythm": "保持轻松，不用追回刚才的时间。",
                "coach.rhythm_recovered": "现在更接近目标配速了，继续控制强度。",
                "workout.pause": "训练已暂停。",
                "workout.resume": "重启训练。",
                "workout.segment_start": "进入新阶段，先稳定到目标强度，再逐步发力。",
                "coach.strong_finish": "如果仍然感觉轻松，就逐步加速跑向终点。",
                "challenge.start": "挑战开始，平稳加速。",
                "challenge.complete": "挑战完成，回到原来的跑步节奏。"
            ]
        ]
        return (key, texts[language.rawValue]?[key] ?? texts[AppLanguage.english.rawValue]![key]!)
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
