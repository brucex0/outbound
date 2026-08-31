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
            targetPace = athleteReferencePace
        }
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
                targetPaceSecondsPerKilometer: targetPace,
                gradePercent: rollingGrade(request.recentSnapshots),
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
        let locations = snapshots
            .filter { $0.elapsedSeconds >= endElapsed - 45 }
            .compactMap(\.location)
            .filter {
                $0.horizontalAccuracyMeters >= 0
                    && $0.horizontalAccuracyMeters <= 25
                    && $0.verticalAccuracyMeters >= 0
                    && $0.verticalAccuracyMeters <= 10
            }
        guard locations.count >= 6 else { return nil }
        let count = min(3, locations.count / 2)
        let start = averagedLocation(Array(locations.prefix(count)))
        let end = averagedLocation(Array(locations.suffix(count)))
        let distance = haversineDistance(
            latitudeA: start.latitude,
            longitudeA: start.longitude,
            latitudeB: end.latitude,
            longitudeB: end.longitude
        )
        guard distance >= 45 else { return nil }
        let grade = (end.altitude - start.altitude) / distance * 100
        return grade.isFinite && abs(grade) <= 40 ? grade : nil
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

    private func haversineDistance(
        latitudeA: Double,
        longitudeA: Double,
        latitudeB: Double,
        longitudeB: Double
    ) -> Double {
        let radians = Double.pi / 180
        let latitudeDelta = (latitudeB - latitudeA) * radians
        let longitudeDelta = (longitudeB - longitudeA) * radians
        let firstLatitude = latitudeA * radians
        let secondLatitude = latitudeB * radians
        let value = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(firstLatitude) * cos(secondLatitude)
            * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        return 6_371_000 * 2 * atan2(sqrt(value), sqrt(max(0, 1 - value)))
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
             .crestRecovery, .challengeComplete:
            .steady
        case .earlyOverpace, .paceAboveTarget, .paceBelowTarget, .paceInstability,
             .paceDrift, .recoveryTooHard, .climbStart, .segmentTransition,
             .finishOpportunity, .challengeStart:
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
        case .earlyOverpace, .paceAboveTarget, .recoveryTooHard, .climbStart: key = "coach.settle"
        case .paceBelowTarget, .paceInstability, .paceDrift: key = "coach.restore_rhythm"
        case .targetLocked: key = "progress.steady"
        case .rhythmRecovery, .crestRecovery: key = "coach.rhythm_recovered"
        case .unexpectedStop: key = "workout.pause"
        case .resumeAfterBreak: key = "workout.resume"
        case .segmentTransition: key = "workout.segment_start"
        case .finishOpportunity: key = "coach.strong_finish"
        case .challengeStart: key = "challenge.start"
        case .challengeComplete: key = "challenge.complete"
        }
        let texts: [String: [String: String]] = [
            AppLanguage.english.rawValue: [
                "progress.steady": "Keep this steady rhythm.",
                "coach.settle": "Settle the effort and find a sustainable rhythm.",
                "coach.restore_rhythm": "Relax your shoulders and gently find your rhythm again.",
                "coach.rhythm_recovered": "That adjustment worked. You found the rhythm again.",
                "workout.pause": "Workout paused.",
                "workout.resume": "Workout resumed.",
                "workout.segment_start": "New segment. Settle into the target before you press.",
                "coach.strong_finish": "Stay composed and let the effort rise gradually.",
                "challenge.start": "Challenge starts now. Build the pace smoothly.",
                "challenge.complete": "Challenge complete. Settle back into your run."
            ],
            AppLanguage.spanish.rawValue: [
                "progress.steady": "Mantén este ritmo estable.",
                "coach.settle": "Baja un poco el esfuerzo y encuentra un ritmo sostenible.",
                "coach.restore_rhythm": "Relaja los hombros y recupera el ritmo poco a poco.",
                "coach.rhythm_recovered": "Ese ajuste funcionó. Recuperaste el ritmo.",
                "workout.pause": "Entrenamiento en pausa.",
                "workout.resume": "Entrenamiento reanudado.",
                "workout.segment_start": "Nuevo segmento. Encuentra el objetivo antes de apretar.",
                "coach.strong_finish": "Mantén la calma y aumenta el esfuerzo gradualmente.",
                "challenge.start": "Empieza el reto. Aumenta el ritmo con suavidad.",
                "challenge.complete": "Reto completado. Vuelve a tu ritmo de carrera."
            ],
            AppLanguage.simplifiedChinese.rawValue: [
                "progress.steady": "保持现在的稳定节奏。",
                "coach.settle": "稍微收住强度，找到可持续的节奏。",
                "coach.restore_rhythm": "放松肩膀，慢慢找回刚才的节奏。",
                "coach.rhythm_recovered": "调整有效，你已经找回节奏了。",
                "workout.pause": "训练已暂停。",
                "workout.resume": "重启训练。",
                "workout.segment_start": "进入新阶段，先稳定到目标强度，再逐步发力。",
                "coach.strong_finish": "保持从容，逐步提升强度。",
                "challenge.start": "挑战开始，平稳加速。",
                "challenge.complete": "挑战完成，回到原来的跑步节奏。"
            ]
        ]
        return (key, texts[language.rawValue]?[key] ?? texts[AppLanguage.english.rawValue]![key]!)
    }
}
