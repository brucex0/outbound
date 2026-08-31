import CoreLocation
import Foundation

@MainActor
final class LiveCoachSessionController {
    private var createTask: Task<CreateLiveCoachSessionResponse, Error>?
    private var session: CreateLiveCoachSessionResponse?
    private var phraseUseCounts: [String: Int] = [:]
    private var prewarmTask: Task<Void, Never>?
    private var voiceProfileID = ""

    var effectiveMode: LiveCoachAudioMode {
        session?.effectiveMode ?? LiveCoachFeatureState.shared.configuration?.mode ?? .disabled
    }

    var accessReason: LiveCoachAccessReason {
        session?.access.reason ?? LiveCoachFeatureState.shared.configuration?.access.reason ?? .featureDisabled
    }

    var progressPolicy: LiveCoachProgressPolicyDTO? { session?.guidancePlan.progressPolicy }

    func begin(
        profile: GuideProfile?,
        persona: GuidePersona?,
        intent: SessionIntent?,
        companionBrief: CompanionSessionBriefDTO?,
        unitSystem: MeasurementUnitSystem,
        weatherSnapshot: RunningWeatherSnapshot?,
        isIndoor: Bool
    ) {
        end(report: nil)
        phraseUseCounts = [:]
        guard let persona else { return }
        voiceProfileID = persona.voice.id
        let request = CreateLiveCoachSessionRequest(
            clientSessionId: UUID(),
            workoutId: companionBrief?.workout?.id,
            locale: AppLanguage.currentIdentifier,
            coachPersonaId: persona.template.id,
            voiceProfileId: persona.voice.id,
            coachingContract: persona.coachingContract.rawValue,
            measurementUnitSystem: unitSystem.rawValue,
            sessionIntent: .init(
                activityType: activityType(for: intent?.sport ?? persona.template.sport),
                goalType: goalType(for: intent)
            ),
            clientWorkout: clientWorkout(for: intent, profile: profile),
            environment: environment(weatherSnapshot: weatherSnapshot, isIndoor: isIndoor)
        )
        createTask = Task {
            let response = try await APIClient.shared.createLiveCoachSession(request)
            guard !Task.isCancelled else { throw CancellationError() }
            session = response
            await GuideAudioPackStore.shared.refresh(
                from: response.audioPack.manifestUrl,
                expectedCatalogVersion: response.audioPack.manifestVersion
            )
            prewarmTask = Task { [weak self] in
                await self?.prewarmPlan(response)
            }
            return response
        }
    }

    func requestCueStream(_ request: LiveCoachCueRequest) async throws -> LiveCoachCueStreamResponse {
        let active = if let session { session } else if let createTask { try await createTask.value } else {
            throw LiveCoachSessionError.notStarted
        }
        guard active.expiresAt > Date() else { throw LiveCoachSessionError.expired }
        let selectedPhraseID = request.moment == "progress"
            ? nil
            : selectedPhraseID(
                in: active.guidancePlan,
                moment: request.moment,
                phase: request.liveState.workoutSegmentPhase
            )
        if let selectedPhraseID,
           let cached = await GuidePlannedAudioCache.shared.audioData(
                planHash: active.guidancePlanHash,
                voiceProfileID: voiceProfileID,
                phraseID: selectedPhraseID
           ),
           let phrase = phrase(in: active.guidancePlan, id: selectedPhraseID) {
            let now = Date()
            let cachedRequest = LiveCoachCueRequest(
                cueRequestId: request.cueRequestId,
                moment: request.moment,
                detectedAtElapsedSeconds: request.detectedAtElapsedSeconds,
                validForMilliseconds: min(request.validForMilliseconds, active.limits.cueValidityMilliseconds),
                selectedPhraseId: selectedPhraseID,
                liveState: request.liveState
            )
            Task {
                try? await APIClient.shared.recordLiveCoachCachedCue(
                    sessionID: active.sessionId,
                    request: cachedRequest
                )
            }
            return LiveCoachCueStreamResponse(
                metadata: .init(
                    contractVersion: 1,
                    cueRequestId: request.cueRequestId,
                    source: .plannedCache,
                    result: .success,
                    moment: request.moment,
                    urgency: urgency(for: request.moment),
                    transcript: phrase.text,
                    fixedCueKey: nil,
                    audio: nil,
                    generatedAt: now,
                    expiresAt: now.addingTimeInterval(Double(request.validForMilliseconds) / 1_000),
                    timing: .init(serverReceivedAtUnixMilliseconds: now.timeIntervalSince1970 * 1_000, providerStartedAtUnixMilliseconds: nil)
                ),
                audioStream: nil,
                cachedAudioData: cached
            )
        }
        let boundedRequest = LiveCoachCueRequest(
            cueRequestId: request.cueRequestId,
            moment: request.moment,
            detectedAtElapsedSeconds: request.detectedAtElapsedSeconds,
            validForMilliseconds: min(request.validForMilliseconds, active.limits.cueValidityMilliseconds),
            selectedPhraseId: selectedPhraseID,
            liveState: request.liveState
        )
        let response = try await APIClient.shared.streamLiveCoachCue(sessionID: active.sessionId, request: boundedRequest)
        return response
    }

    func end(report: LiveGuidanceSessionReport?) {
        prewarmTask?.cancel()
        prewarmTask = nil
        createTask?.cancel()
        createTask = nil
        guard let session else {
            self.session = nil
            return
        }
        self.session = nil
        Task {
            _ = try? await APIClient.shared.endLiveCoachSession(
                sessionID: session.sessionId,
                request: .init(
                    spokenCueCount: report?.spokenCueCount ?? 0,
                    helpfulCueCount: report?.helpfulCueCount ?? 0,
                    outcome: report == nil ? "interrupted" : "completed"
                )
            )
        }
    }

    private func prewarmPlan(_ response: CreateLiveCoachSessionResponse) async {
        guard response.effectiveMode == .dynamic, response.planner.status == "generated" else { return }
        let preferredMoments = [
            "early_overpace", "pace_above_target", "pace_below_target", "pace_drift",
            "recovery_too_hard", "climb_start", "segment_transition", "finish_opportunity"
        ]
        let phrases = preferredMoments.compactMap { moment in
            response.guidancePlan.cues.first(where: { $0.moment == moment })?.phrases.first
        }.prefix(8)
        for phrase in phrases {
            guard !Task.isCancelled else { return }
            if await GuidePlannedAudioCache.shared.audioData(
                planHash: response.guidancePlanHash,
                voiceProfileID: voiceProfileID,
                phraseID: phrase.id
            ) != nil { continue }
            guard let audio = try? await APIClient.shared.fetchLiveCoachPhraseAudio(
                sessionID: response.sessionId,
                phraseID: phrase.id
            ) else { continue }
            await GuidePlannedAudioCache.shared.store(
                audio,
                planHash: response.guidancePlanHash,
                voiceProfileID: voiceProfileID,
                phraseID: phrase.id
            )
        }
    }

    private func phrase(in plan: LiveCoachGuidancePlanDTO, id: String) -> LiveCoachGuidancePlanDTO.Phrase? {
        plan.cues.lazy.flatMap(\.phrases).first(where: { $0.id == id })
    }

    private func urgency(for moment: String) -> String {
        moment == "unexpected_stop" ? "caution"
            : ["progress", "target_locked", "rhythm_recovery", "resume_after_break", "crest_recovery", "challenge_complete"].contains(moment)
                ? "steady"
                : "opportunity"
    }

    private func activityType(for sport: SportType) -> String {
        switch sport {
        case .run: "running"
        case .bike: "cycling"
        case .walk: "walking"
        case .hike: "hiking"
        case .swim: "swimming"
        }
    }

    private func goalType(for intent: SessionIntent?) -> String {
        guard let intent else { return "freestyle" }
        if !intent.workoutSteps.isEmpty { return "workout" }
        if intent.resolvedTargetDistanceMeters != nil { return "distance" }
        if intent.resolvedTargetDurationSeconds != nil { return "time" }
        return "freestyle"
    }

    private func selectedPhraseID(
        in plan: LiveCoachGuidancePlanDTO,
        moment: String,
        phase: String?
    ) -> String? {
        let eligible = plan.cues.filter { cue in
            cue.moment == moment
                && (phase == nil || cue.phases.contains("any") || cue.phases.contains(phase!))
        }.flatMap(\.phrases)
        guard !eligible.isEmpty else { return nil }
        let selected = eligible.min { left, right in
            let leftCount = phraseUseCounts[left.id, default: 0]
            let rightCount = phraseUseCounts[right.id, default: 0]
            return leftCount == rightCount ? left.id < right.id : leftCount < rightCount
        }!
        phraseUseCounts[selected.id, default: 0] += 1
        return selected.id
    }

    private func clientWorkout(
        for intent: SessionIntent?,
        profile: GuideProfile?
    ) -> CreateLiveCoachSessionRequest.ClientWorkoutDTO? {
        guard let intent else { return nil }
        let athletePace = profile?.athlete.preferredPaceSecs
        let steps = intent.workoutSteps.map { step in
            CreateLiveCoachSessionRequest.ClientWorkoutDTO.StepDTO(
                label: step.label,
                durationSeconds: step.durationSeconds,
                detail: step.detail,
                phase: step.coachingTarget?.phase.rawValue,
                targetPaceSecondsPerKilometer: step.coachingTarget?.pace?.resolvedTarget(
                    athleteReferencePace: athletePace
                )
            )
        }
        return .init(
            title: intent.title,
            detail: intent.detail,
            guideLine: intent.guideLine,
            targetDistanceMeters: intent.resolvedTargetDistanceMeters,
            targetDurationSeconds: intent.resolvedTargetDurationSeconds,
            steps: steps,
            route: routeDTO(intent.preparedRoute)
        )
    }

    private func routeDTO(
        _ route: PreparedRoute?
    ) -> CreateLiveCoachSessionRequest.ClientWorkoutDTO.RouteDTO? {
        guard let route, let first = route.directedPoints.first else { return nil }
        let points = route.directedPoints
        var distance = 0.0
        var elevationGain = 0.0
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            distance += CLLocation(
                latitude: previous.latitude,
                longitude: previous.longitude
            ).distance(from: CLLocation(latitude: current.latitude, longitude: current.longitude))
            if let previousAltitude = previous.altitude,
               let currentAltitude = current.altitude,
               currentAltitude > previousAltitude {
                elevationGain += currentAltitude - previousAltitude
            }
        }
        return .init(
            name: route.name,
            shape: route.routeShape,
            direction: route.direction.rawValue,
            distanceMeters: distance,
            elevationGainMeters: elevationGain,
            approximateStartLatitude: first.latitude,
            approximateStartLongitude: first.longitude,
            approximateStartAltitudeMeters: first.altitude
        )
    }

    private func environment(
        weatherSnapshot: RunningWeatherSnapshot?,
        isIndoor: Bool
    ) -> CreateLiveCoachSessionRequest.EnvironmentDTO {
        .init(
            timeZoneIdentifier: TimeZone.current.identifier,
            indoor: isIndoor,
            approximateLocation: weatherSnapshot.map {
                .init(
                    placeName: $0.placeName,
                    latitude: $0.approximateLatitude,
                    longitude: $0.approximateLongitude,
                    altitudeMeters: $0.approximateAltitudeMeters
                )
            },
            weather: weatherSnapshot.map {
                .init(
                    observedAt: $0.fetchedAt,
                    condition: $0.condition,
                    temperatureCelsius: $0.temperatureCelsius,
                    apparentTemperatureCelsius: $0.apparentTemperatureCelsius,
                    windKilometersPerHour: $0.windKilometersPerHour,
                    precipitationChance: $0.precipitationChance,
                    impact: $0.impact.rawValue,
                    headline: $0.headline,
                    guidance: $0.guidance,
                    bestWindow: $0.bestWindow
                )
            }
        )
    }
}

private enum LiveCoachSessionError: Error {
    case notStarted
    case expired
}
