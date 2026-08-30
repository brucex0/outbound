import Foundation

@MainActor
final class LiveCoachSessionController {
    private var createTask: Task<CreateLiveCoachSessionResponse, Error>?
    private var session: CreateLiveCoachSessionResponse?

    var effectiveMode: LiveCoachAudioMode {
        session?.effectiveMode ?? LiveCoachFeatureState.shared.configuration?.mode ?? .disabled
    }

    var accessReason: LiveCoachAccessReason {
        session?.access.reason ?? LiveCoachFeatureState.shared.configuration?.access.reason ?? .featureDisabled
    }

    func begin(
        persona: GuidePersona?,
        intent: SessionIntent?,
        companionBrief: CompanionSessionBriefDTO?,
        unitSystem: MeasurementUnitSystem
    ) {
        end(report: nil)
        guard let persona else { return }
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
            )
        )
        createTask = Task {
            let response = try await APIClient.shared.createLiveCoachSession(request)
            guard !Task.isCancelled else { throw CancellationError() }
            session = response
            await GuideAudioPackStore.shared.refresh(
                from: response.audioPack.manifestUrl,
                expectedCatalogVersion: response.audioPack.manifestVersion
            )
            return response
        }
    }

    func requestCue(_ request: LiveCoachCueRequest) async throws -> LiveCoachCueResponse {
        let active = if let session { session } else if let createTask { try await createTask.value } else {
            throw LiveCoachSessionError.notStarted
        }
        guard active.expiresAt > Date() else { throw LiveCoachSessionError.expired }
        let boundedRequest = LiveCoachCueRequest(
            cueRequestId: request.cueRequestId,
            moment: request.moment,
            detectedAtElapsedSeconds: request.detectedAtElapsedSeconds,
            validForMilliseconds: min(request.validForMilliseconds, active.limits.cueValidityMilliseconds),
            liveState: request.liveState
        )
        return try await APIClient.shared.requestLiveCoachCue(sessionID: active.sessionId, request: boundedRequest)
    }

    func end(report: LiveGuidanceSessionReport?) {
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
}

private enum LiveCoachSessionError: Error {
    case notStarted
    case expired
}
