import Foundation

@MainActor
final class ServerLiveCoachProvider: SessionAnalysisProvider {
    let identifier = "plainstride-server-live-coach"
    let displayName = "Plainstride Live Coach"

    private let controller = LiveCoachSessionController()

    func beginSession(
        profile: GuideProfile?,
        persona: GuidePersona?,
        sessionIntent: SessionIntent?,
        companionBrief: CompanionSessionBriefDTO?,
        unitSystem: MeasurementUnitSystem
    ) {
        controller.begin(
            persona: persona,
            intent: sessionIntent,
            companionBrief: companionBrief,
            unitSystem: unitSystem
        )
    }

    func analyze(_ request: SessionAnalysisRequest) async throws -> SessionAnalysisResult {
        guard let moment = request.momentType else {
            return silentResult(source: .cachedFallback, result: .invalid, latency: .underOneSecond)
        }

        let segment = workoutSegment(request.sessionIntent, elapsedSeconds: request.snapshot.elapsedSeconds)
        let cueRequest = LiveCoachCueRequest(
            cueRequestId: UUID(),
            moment: moment.rawValue,
            detectedAtElapsedSeconds: request.snapshot.elapsedSeconds,
            validForMilliseconds: 5_000,
            liveState: .init(
                elapsedSeconds: request.snapshot.elapsedSeconds,
                distanceMeters: request.snapshot.distanceMeters,
                currentPaceSecondsPerKilometer: validPace(request.snapshot.currentPaceSecsPerKm),
                rollingPaceSecondsPerKilometer: rollingPace(request.recentSnapshots),
                targetPaceSecondsPerKilometer: validPace(request.profile?.athlete.preferredPaceSecs),
                workoutSegmentIndex: segment?.index,
                workoutSegmentPhase: segment?.phase,
                routeGuidanceActive: request.routeGuidanceActive
            )
        )

        let startedAt = Date()
        do {
            let response = try await controller.requestCue(cueRequest)
            let latency = LiveCoachLatencyBucket(seconds: Date().timeIntervalSince(startedAt))
            guard response.expiresAt > Date() else {
                return silentResult(source: response.source, result: .stale, latency: latency)
            }
            let audioData: Data?
            if let audio = response.audio,
               audio.contentType == "audio/wav",
               let decoded = Data(base64Encoded: audio.base64),
               Self.looksLikeBoundedWAV(decoded) {
                audioData = decoded
            } else if let fixedCueKey = response.fixedCueKey {
                audioData = await GuideAudioPackStore.shared.audioData(
                    for: fixedCueKey,
                    transcript: response.transcript
                )
            } else {
                audioData = nil
            }
            guard response.expiresAt > Date() else {
                return silentResult(source: response.source, result: .stale, latency: latency)
            }
            return SessionAnalysisResult(
                message: response.transcript,
                urgency: SessionAnalysisUrgency(rawValue: response.urgency) ?? .steady,
                shouldSpeak: audioData != nil,
                generatedAt: response.generatedAt,
                expiresAt: response.expiresAt,
                providerID: identifier,
                source: response.source,
                result: response.result,
                effectiveMode: controller.effectiveMode,
                accessReason: controller.accessReason,
                latencyBucket: latency,
                fixedCueKey: response.fixedCueKey,
                audioData: audioData
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled { throw CancellationError() }
            return await cachedFallback(
                for: moment,
                result: .unavailable,
                latency: LiveCoachLatencyBucket(seconds: Date().timeIntervalSince(startedAt))
            )
        }
    }

    func endSession(report: LiveGuidanceSessionReport?) {
        controller.end(report: report)
    }

    private func cachedFallback(
        for moment: LiveGuidanceMomentType,
        result: LiveCoachCueResult,
        latency: LiveCoachLatencyBucket
    ) async -> SessionAnalysisResult {
        let fallback = Self.fallback(for: moment, language: AppLanguage.current)
        let audioData = await GuideAudioPackStore.shared.audioData(for: fallback.key, transcript: fallback.text)
        return SessionAnalysisResult(
            message: fallback.text,
            urgency: Self.urgency(for: moment),
            shouldSpeak: audioData != nil,
            generatedAt: Date(),
            expiresAt: Date().addingTimeInterval(5),
            providerID: identifier,
            source: .cachedFallback,
            result: result,
            effectiveMode: controller.effectiveMode,
            accessReason: controller.accessReason,
            latencyBucket: latency,
            fixedCueKey: fallback.key,
            audioData: audioData
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
            audioData: nil
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

    private func workoutSegment(
        _ intent: SessionIntent?,
        elapsedSeconds: Int
    ) -> (index: Int, phase: String)? {
        let steps = intent?.workoutSteps.filter { $0.durationSeconds > 0 } ?? []
        guard !steps.isEmpty else { return nil }
        var boundary = 0
        for (index, step) in steps.enumerated() {
            boundary += step.durationSeconds
            guard elapsedSeconds < boundary else { continue }
            let label = "\(step.label) \(step.detail ?? "")".lowercased()
            let phase: String
            if label.contains("warm") { phase = "warmup" }
            else if label.contains("recover") || label.contains("rest") || label.contains("easy") { phase = "recovery" }
            else if label.contains("cool") { phase = "cooldown" }
            else { phase = "work" }
            return (index, phase)
        }
        return (steps.count - 1, "cooldown")
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
        return formatIsValid && audioByteCount > 0 && durationMilliseconds <= 4_500
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
        case .progress:
            .steady
        case .fastStart, .paceDrift, .segmentTransition, .finishOpportunity, .challengeStart:
            .opportunity
        case .rhythmRecovery, .challengeComplete:
            .steady
        }
    }

    private static func fallback(
        for moment: LiveGuidanceMomentType,
        language: AppLanguage
    ) -> (key: String, text: String) {
        let key: String
        switch moment {
        case .progress: key = "progress.steady"
        case .fastStart: key = "coach.settle"
        case .paceDrift: key = "coach.restore_rhythm"
        case .rhythmRecovery: key = "coach.rhythm_recovered"
        case .segmentTransition: key = "workout.segment_start"
        case .finishOpportunity: key = "coach.strong_finish"
        case .challengeStart: key = "challenge.start"
        case .challengeComplete: key = "challenge.complete"
        }
        let texts: [String: [String: String]] = [
            AppLanguage.english.rawValue: [
                "progress.steady": "Keep the effort smooth and steady.",
                "coach.settle": "Settle the effort and find a sustainable rhythm.",
                "coach.restore_rhythm": "Relax your shoulders and gently find your rhythm again.",
                "coach.rhythm_recovered": "That adjustment worked. You found the rhythm again.",
                "workout.segment_start": "New segment. Settle into the target before you press.",
                "coach.strong_finish": "Stay composed and let the effort rise gradually.",
                "challenge.start": "Challenge starts now. Build the pace smoothly.",
                "challenge.complete": "Challenge complete. Settle back into your run."
            ],
            AppLanguage.spanish.rawValue: [
                "progress.steady": "Mantén un esfuerzo fluido y constante.",
                "coach.settle": "Baja un poco el esfuerzo y encuentra un ritmo sostenible.",
                "coach.restore_rhythm": "Relaja los hombros y recupera el ritmo poco a poco.",
                "coach.rhythm_recovered": "Ese ajuste funcionó. Recuperaste el ritmo.",
                "workout.segment_start": "Nuevo segmento. Encuentra el objetivo antes de apretar.",
                "coach.strong_finish": "Mantén la calma y aumenta el esfuerzo gradualmente.",
                "challenge.start": "Empieza el reto. Aumenta el ritmo con suavidad.",
                "challenge.complete": "Reto completado. Vuelve a tu ritmo de carrera."
            ],
            AppLanguage.simplifiedChinese.rawValue: [
                "progress.steady": "保持顺畅稳定的强度。",
                "coach.settle": "稍微收住强度，找到可持续的节奏。",
                "coach.restore_rhythm": "放松肩膀，慢慢找回刚才的节奏。",
                "coach.rhythm_recovered": "刚才的调整有效，你已经找回节奏了。",
                "workout.segment_start": "进入新阶段，先稳定到目标强度，再逐步发力。",
                "coach.strong_finish": "保持从容，让强度逐步提升。",
                "challenge.start": "挑战开始，平稳地提起速度。",
                "challenge.complete": "挑战完成，回到原来的跑步节奏。"
            ]
        ]
        return (key, texts[language.rawValue]?[key] ?? texts[AppLanguage.english.rawValue]![key]!)
    }
}
