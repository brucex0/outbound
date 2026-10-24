import SwiftUI
import PhotosUI
import CoreLocation
import MapKit

extension ActivityFlowCoordinator {
    func trackRecoveryPresentationIfNeeded(result: String) {
        guard self.recorder.recoveredSession, !self.didTrackRecoveryPresentation else { return }
        self.didTrackRecoveryPresentation = true
#if DEBUG
        let sourceType = self.recorder.isSimulatingRun ? "run_simulation" : "recording"
#else
        let sourceType = "recording"
#endif
        self.track(.init(.activityRecoveryPresentation, properties: [
            .result: .string(result),
            .sourceType: .string(sourceType),
            .countBucket: .string(ProductAnalyticsBucket.count(1))
        ]))
    }

#if DEBUG
    func trackRunSimulationControl(_ control: String, _ selection: String) {
        self.track(.init(.activitySimulationControlUsed, properties: [
            .control: .string(control),
            .selectionType: .string(selection)
        ]))
    }
#endif

    func track(_ event: ProductAnalyticsEvent) {
        guard let analyticsManager else { return }
        Task { await analyticsManager.track(event) }
    }

    func elevationCorrectionErrorCategory(_ error: Error) -> String {
        if case let APIError.http(statusCode, _, _) = error {
            return "http_\(statusCode)"
        }
        if error is DecodingError { return "decoding" }
        if let urlError = error as? URLError {
            return urlError.code == .notConnectedToInternet ? "offline" : "network"
        }
        return "invalid_response"
    }

    var isVoiceGuideExplicitlyUnavailable: Bool {
        self.dependencies.guideCatalog.liveCoachAudioMode == .disabled
    }

    var voiceGuideSpeechEnabled: Bool {
        self.isVoiceGuideEnabled && !self.isVoiceGuideExplicitlyUnavailable
    }

    func trackGuidanceEvent(_ event: LiveGuidanceTelemetryEvent) {
        switch event {
        case .eligibilityResolved(let activityType, let result):
            self.track(.init(.liveGuidanceEligibilityResolved, properties: [
                .activityType: .string(activityType),
                .result: .string(result),
                .sourceType: .string(self.dependencies.guideStore.coachingReferenceSource)
            ]))
        case .speedChange(let direction, let result):
            self.track(.init(.liveGuidanceSpeedChange, properties: [.sourceType: .string(direction), .result: .string(result)]))
        case .momentSuppressed(let reason):
            self.track(.init(.liveGuidanceMomentSuppressed, properties: [.result: .string(reason)]))
        case .momentDetected(let type, let contract):
            self.track(.init(.liveGuidanceMomentDetected, properties: [
                .momentType: .string(type.rawValue),
                .coachingContract: .string(contract.rawValue)
            ]))
        case .cueSpoken(let type, let contract):
            self.track(.init(.liveGuidanceCueSpoken, properties: [
                .momentType: .string(type.rawValue),
                .coachingContract: .string(contract.rawValue)
            ]))
        case .cueEvaluated(let type, let outcome):
            self.track(.init(.liveGuidanceCueEvaluated, properties: [
                .momentType: .string(type.rawValue),
                .result: .string(outcome.rawValue)
            ]))
        case .providerResult(let source, let result, let mode, let accessReason, let latency):
            self.track(.init(.liveGuidanceProviderResult, properties: [
                .sourceType: .string(source.rawValue),
                .result: .string(result.rawValue),
                .audioMode: .string(mode.rawValue),
                .accessReason: .string(accessReason.rawValue),
                .latencyBucket: .string(latency.rawValue)
            ]))
        case .audioFirstByte(let source, let latency):
            self.track(.init(.liveGuidanceAudioFirstByte, properties: [
                .sourceType: .string(source.rawValue),
                .latencyBucket: .string(latency.rawValue)
            ]))
        case .audioPlaybackRoute(let route):
            self.track(.init(.liveGuidanceAudioPlaybackRoute, properties: [
                .sourceType: .string(route.rawValue)
            ]))
        case .executionCoaching(let result):
            self.track(.init(.liveGuidanceExecutionCoaching, properties: [.result: .string(result)]))
        case .pacerPlayback(let result):
            self.track(.init(.liveGuidancePacerPlayback, properties: [.result: .string(result)]))
        case .fixedAudioUnavailable(let cueGroup, let reason):
            self.track(.init(.liveGuidanceFixedAudioUnavailable, properties: [
                .selectionType: .string(cueGroup),
                .result: .string(reason)
            ]))
        }
    }

    func handleGuidanceFeedback(_ feedback: LiveGuidanceFeedback) {
        self.dependencies.guideCatalog.recordGuidanceFeedback(feedback)
        self.track(.init(.liveGuidanceFeedbackSubmitted, properties: [
            .selectionType: .string(feedback.rawValue),
            .cueCountBucket: .string(ProductAnalyticsBucket.count(self.review.pendingActivity?.guidanceReport.spokenCueCount ?? 0))
        ]))
    }

    func trackSetupAndFeatureExposureIfNeeded() {
        guard !self.didTrackSetupView else { return }
        self.didTrackSetupView = true
        self.track(.init(.activitySetupViewed, properties: [.entrySource: .string(self.analyticsEntrySource)]))
        self.track(.init(.watchFeatureExposed, properties: [.sourceType: .string("iphone")]))
        ["music", "routes", "shoes", "photos", "group_run", "dog_companion"].forEach(self.trackFeatureExposure)
    }

    func trackFeatureExposure(_ feature: String) {
        guard self.exposedFeatures.insert(feature).inserted else { return }
        self.track(.init(.featureExposed, properties: [.feature: .string(feature)]))
    }

    func trackRecordingStateTransition(to state: RecordingState) {
        defer { self.previousRecorderState = state }
        guard state != self.previousRecorderState else { return }
        switch (self.previousRecorderState, state) {
        case (.active, .paused):
            self.track(.init(.activityPaused, properties: [
                .sourceType: .string(self.recorder.autoPaused ? "automatic" : "manual")
            ]))
        case (.paused, .active):
            self.track(.init(.activityResumed, properties: [
                .sourceType: .string(self.recorder.autoPaused ? "automatic" : "manual"),
                .durationBucket: .string(ProductAnalyticsBucket.duration(
                    seconds: self.recorder.lastAutoPauseRecoveredDurationSeconds
                ))
            ]))
        default:
            break
        }
    }

    func trackGoalProgressIfNeeded(_ snapshot: ActiveSessionSnapshot) {
        guard self.recorder.state != .idle, let ratio = self.goalCompletionRatio(
            distanceMeters: snapshot.distanceMeters,
            durationSeconds: snapshot.elapsedSeconds
        ), ActivitySaveEligibility.evaluate(
            durationSecs: snapshot.elapsedSeconds,
            distanceM: snapshot.distanceMeters
        ) == .eligible else { return }

        for threshold in [25, 50, 75, 100]
        where ratio * 100 >= Double(threshold) && self.reachedGoalThresholds.insert(threshold).inserted {
            self.track(.init(.goalProgressReached, properties: [
                .activityType: .string((self.activeIntent ?? self.setup.plannedIntent ?? .freestyleRun).resolvedActivityType.rawValue),
                .goalType: .string(self.analyticsGoalType),
                .progressPercent: .integer(threshold)
            ]))
        }
    }

    func handleRouteGuidanceEvent(_ event: RouteGuidanceEvent) {
        guard let route = (self.activeIntent ?? self.setup.plannedIntent)?.preparedRoute else { return }
        switch event {
        case .progressReached(let percent):
            self.track(.init(.routeGuidanceProgressReached, properties: [
                .sourceType: .string(route.source.rawValue),
                .direction: .string(route.direction.rawValue),
                .progressPercent: .integer(percent)
            ]))
        case .deviated(let distanceMeters):
            let message = String(localized: "route.guidance.off_route", defaultValue: "You are off the selected route. Return toward the highlighted line when safe.")
            self.guide.announceRouteGuidance(message, priority: .caution, semanticCueKey: "route.off_route")
            self.track(.init(.routeDeviationDetected, properties: [
                .distanceBucket: .string(ProductAnalyticsBucket.distance(meters: distanceMeters))
            ]))
        case .rejoined:
            let message = String(localized: "route.guidance.rejoined", defaultValue: "You are back on the selected route.")
            self.guide.announceRouteGuidance(message, priority: .advisory, semanticCueKey: "route.rejoin")
            self.track(.init(.routeRejoined))
        case .wrongWay:
            let message = String(localized: "route.guidance.wrong_way", defaultValue: "You may be going the wrong way. Check the map before turning back.")
            self.guide.announceRouteGuidance(message, priority: .caution, semanticCueKey: "route.wrong_way")
            self.track(.init(.routeWrongWayDetected, properties: [
                .sourceType: .string(route.source.rawValue),
                .direction: .string(route.direction.rawValue)
            ]))
        case .arrival:
            let message = String(localized: "route.guidance.arrival", defaultValue: "You have reached the end of the route.")
            self.guide.announceRouteGuidance(message, priority: .arrival, semanticCueKey: "route.arrival")
            self.track(.init(.routeGuidanceArrived, properties: [
                .sourceType: .string(route.source.rawValue),
                .direction: .string(route.direction.rawValue)
            ]))
        }
    }

    func coarseRouteProgressPercent(_ fraction: Double) -> Int {
        let percent = max(0, min(100, fraction.isFinite ? fraction * 100 : 0))
        return [0, 25, 50, 75, 100].last(where: { Double($0) <= percent }) ?? 0
    }

    var activityConfigurationProperties: [ProductPropertyKey: AnalyticsValue] {
        let intent = self.activeIntent ?? self.setup.plannedIntent ?? .freestyleRun
        return [
            .entrySource: .string(self.analyticsEntrySource),
            .activityType: .string(intent.resolvedActivityType.rawValue),
            .goalType: .string(self.analyticsGoalType),
            .targetBucket: .string(self.analyticsTargetBucket(for: intent.activityGoal)),
            .musicEnabled: .boolean(self.musicWasConfigured),
            .routeSelected: .boolean(self.activeIntent?.preparedRoute != nil),
            .shoeSelected: .boolean(self.setup.selectedSessionShoe != nil),
            .preRunPhotoAdded: .boolean(self.preActivityPhoto != nil),
            .groupRunEnabled: .boolean(self.dependencies.liveGroupStore.isSharing || self.activeIntent?.activityEvent != nil),
            .liveShareEnabled: .boolean(self.dependencies.liveShareStore.isArmedForNextActivity),
            .indoor: .boolean(self.setup.isIndoorSession),
            .voiceGuideEnabled: .boolean(self.voiceGuideSpeechEnabled),
            .autoPauseEnabled: .boolean(self.recorder.autoPauseEnabled),
            .autoStopAtGoal: .boolean(
                self.autoStopAtGoalEnabled && [.distance, .time, .calories].contains(self.setup.selectedGoalMode)
            ),
            .participantCountBucket: .string(ProductAnalyticsBucket.count(self.dependencies.liveGroupStore.participants.count)),
            .dogCompanionEnabled: .boolean(intent.resolvedActivityType.ineligibleForCompanion != true && self.setup.companionType != nil)
        ]
    }

    func outcomeProperties(for summary: ActivitySummary) -> [ProductPropertyKey: AnalyticsValue] {
        [
            .durationBucket: .string(ProductAnalyticsBucket.duration(seconds: summary.durationSecs)),
            .distanceBucket: .string(ProductAnalyticsBucket.distance(meters: summary.distanceM)),
            .goalCompletionBucket: .string(ProductAnalyticsBucket.completion(self.goalCompletionRatio(
                distanceMeters: summary.distanceM,
                durationSeconds: summary.durationSecs
            )))
        ]
    }

    var analyticsEntrySource: String {
        let intent = self.activeIntent ?? self.setup.plannedIntent ?? .freestyleRun
        if intent.activityEvent != nil { return "activity_event" }
        if intent.preparedRoute != nil { return "route" }
        if self.host.isEmbeddedInToday { return "today" }
        if !intent.workoutSteps.isEmpty { return "planned_workout" }
        if intent.id == SessionIntent.freestyleRun.id { return "quick_run" }
        return "prepared_activity"
    }

    var analyticsGoalType: String {
        let intent = self.activeIntent ?? self.setup.plannedIntent ?? .freestyleRun
        if intent.raceIntent != nil { return "race" }
        if !intent.workoutSteps.isEmpty { return "workout" }
        switch intent.activityGoal {
        case .freestyle: return "freestyle"
        case .distanceMeters: return "distance"
        case .timeSeconds: return "time"
        case .calories: return "calories"
        }
    }

    var musicWasConfigured: Bool {
        self.dependencies.musicStore.isConnected && (self.dependencies.musicStore.selectedQuickPick != nil || !self.dependencies.musicStore.selectedCustomItems.isEmpty)
    }

    func analyticsTargetBucket(for goal: ActivityGoal) -> String {
        switch goal {
        case .freestyle:
            return "none"
        case .distanceMeters(let meters):
            return ProductAnalyticsBucket.distance(meters: meters)
        case .timeSeconds(let seconds):
            return ProductAnalyticsBucket.duration(seconds: seconds)
        case .calories(let calories):
            if calories < 250 { return "under_250" }
            if calories < 400 { return "250_399" }
            if calories < 600 { return "400_599" }
            return "600_plus"
        }
    }

    func goalCompletionRatio(distanceMeters: Double, durationSeconds: Int) -> Double? {
        let goal = (self.activeIntent ?? self.setup.plannedIntent ?? .freestyleRun).activityGoal
        if let target = goal.targetDistanceMeters, target > 0 { return distanceMeters / target }
        if let target = goal.targetDurationSeconds, target > 0 { return Double(durationSeconds) / Double(target) }
        if let target = goal.targetCalories, target > 0,
           let calories = self.estimatedLiveEnergyKilocalories(distanceMeters: distanceMeters, durationSeconds: durationSeconds) {
            return calories / Double(target)
        }
        return nil
    }

    func estimatedLiveEnergyKilocalories(distanceMeters: Double, durationSeconds: Int) -> Double? {
        WorkoutCalorieEstimator.liveEnergyKilocalories(
            activityType: (self.activeIntent ?? self.setup.plannedIntent ?? .freestyleRun).resolvedActivityType,
            distanceMeters: distanceMeters,
            durationSeconds: durationSeconds,
            elevationGainMeters: self.recorder.elevationGainMeters,
            weightKilograms: self.dependencies.onboardingStore.latestWeightKilograms
        )
    }

    func trackCaloriesWeightPrompt(selection: String) {
        self.track(.init(.activityConfigurationChanged, properties: [
            .changeType: .string("calorie_weight_prompt"),
            .selectionType: .string(selection),
            .goalType: .string("calories")
        ]))
    }
}
