import SwiftUI
import PhotosUI
import CoreLocation
import MapKit

extension ActivityFlowCoordinator {
    func finishRecording() {
        self.finishRecording(recoveredAfterFinish: false, initiatedByWatch: false)
    }

    func finishRecording(
        recoveredAfterFinish: Bool,
        initiatedByWatch: Bool = false
    ) {
        guard !self.live.isCapturingSessionPhoto else { return }
        self.cancelStartCountdown(returnToSetup: true)
        if !initiatedByWatch {
            self.dependencies.phoneWorkoutCoordinator.requestFinish()
        }
        let summary = self.recorder.finish()
        self.sessionController.beginReview()
        let eligibility = ActivitySaveEligibility.evaluate(
            durationSecs: summary.durationSecs,
            distanceM: summary.distanceM
        )
        let isSaveEligible = eligibility == .eligible
        let guidanceReport = self.guide.finalizedSessionReport()
        if !recoveredAfterFinish {
            if isSaveEligible {
                self.dependencies.guideCatalog.recordGuidanceReport(guidanceReport)
            }
            let finishProperties: [ProductPropertyKey: AnalyticsValue] = [
                .motivationComeback: .boolean(DailyMotivationEngine.wasComeback(
                    priorActivities: self.dependencies.activityStore.activities,
                    now: summary.endedAt
                )),
                .movingTimeMethod: .string("gps_observations_v2"),
                .elapsedDurationBucket: .string(ProductAnalyticsBucket.duration(
                    seconds: max(summary.durationSecs, Int(summary.endedAt.timeIntervalSince(summary.startedAt)))
                ))
            ]
            self.track(.init(.activityFinished, properties: self.outcomeProperties(for: summary).merging(finishProperties) { _, new in new }))
            let locationDiagnostics = self.recorder.locationManager.recordingDiagnostics
            self.track(.init(.activityRecordingQuality, properties: [
                .sourceType: .string(locationDiagnostics.deliveryMode),
                .countBucket: .string(ProductAnalyticsBucket.locationPointCount(
                    locationDiagnostics.acceptedTrackPointCount
                )),
                .result: .string(locationDiagnostics.result),
                .locationQuality: .string(locationDiagnostics.signalQuality.rawValue),
                .precisionMode: .string(locationDiagnostics.precisionMode),
                .filterRatioBucket: .string(ProductAnalyticsBucket.locationFilterRatio(
                    accepted: locationDiagnostics.acceptedTrackPointCount,
                    rejected: locationDiagnostics.rejectedLocationCount,
                    stationary: locationDiagnostics.stationaryLocationCount
                )),
                .distanceCorrectionBucket: .string(ProductAnalyticsBucket.distanceCorrection(
                    percent: locationDiagnostics.finalDistanceCorrectionPercent
                )),
                .segmentCountBucket: .string(ProductAnalyticsBucket.count(
                    locationDiagnostics.segmentCount
                )),
                .motionBridgeUsed: .boolean(locationDiagnostics.motionAssistedDistanceMeters > 0),
                .routeMatchResult: .string(locationDiagnostics.routeMatchResult),
                .walkingStepsAvailable: .boolean(summary.walkingStepCount != nil),
                .runningCadenceAvailable: .boolean(summary.cadence != nil)
            ]))
        }
        self.liveActivityManager.end(using: self.recorder.liveSnapshot, unitSystem: self.dependencies.measurementPreferences.unitSystem)
        self.dependencies.liveShareStore.end(finalSnapshot: self.recorder.liveSnapshot)
        self.dependencies.liveGroupStore.finishActivity()
        self.guide.deactivate()
        Task { await self.dependencies.musicStore.endWorkoutPlaybackIfNeeded() }
        let reflection = DailyMotivationEngine.finishReflection(
            summary: summary,
            priorActivities: self.dependencies.activityStore.activities,
            readiness: self.dependencies.checkInStore.readiness,
            intent: self.activeIntent,
            goalProgress: isSaveEligible
                ? self.dependencies.goalStore.previewProgress(with: summary, activities: self.dependencies.activityStore.activities)
                : nil,
            now: summary.endedAt
        )
        let recognitionPreviews = isSaveEligible
            ? self.dependencies.recognitionStore.previewPostRunRecognition(
                summary: summary,
                activityType: self.activeIntent?.resolvedActivityType ?? .running,
                priorActivities: self.dependencies.activityStore.activities,
                goalProgress: self.dependencies.goalStore.previewProgress(with: summary, activities: self.dependencies.activityStore.activities)
            )
            : []
        let finishedActivity = PendingFinishedActivity(
            summary: summary,
            photos: self.live.capturedPhotos,
            reflection: reflection,
            recognitionPreviews: recognitionPreviews,
            guidanceReport: guidanceReport
        )
        withAnimation(self.activityCompletionAnimation) {
            self.review.pendingActivity = finishedActivity
            self.showCamera = false
        }
        self.beginElevationCorrection(for: finishedActivity, isEligible: isSaveEligible)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func beginElevationCorrection(
        for activity: PendingFinishedActivity,
        isEligible: Bool
    ) {
        self.review.elevationCorrectionTask?.cancel()
        guard isEligible,
              !self.setup.isIndoorSession,
              AuthStore.currentUserId != nil,
              activity.summary.trackPoints.count >= 2
        else {
            self.review.elevationCorrectionTask = nil
            return
        }

        let startedAt = Date()
        let originalSummary = activity.summary
        let activityID = activity.id
        self.review.elevationCorrectionTask = Task {
            do {
                let corrected = try await TerrainElevationCorrector.correct(originalSummary)
                guard !Task.isCancelled else { return originalSummary }
                self.track(.init(.activityElevationCorrectionCompleted, properties: [
                    .result: .string("success"),
                    .sourceType: .string("mapzen_terrain_v2"),
                    .latencyBucket: .string(ProductAnalyticsBucket.latency(milliseconds: Date().timeIntervalSince(startedAt) * 1_000))
                ]))
                if let current = self.review.pendingActivity, current.id == activityID {
                    self.review.pendingActivity = PendingFinishedActivity(
                        id: current.id,
                        summary: corrected,
                        photos: current.photos,
                        reflection: current.reflection,
                        recognitionPreviews: current.recognitionPreviews,
                        guidanceReport: current.guidanceReport
                    )
                }
                return corrected
            } catch {
                guard !Task.isCancelled else { return originalSummary }
                ActivityDiagnosticLog.error(.persistence,
                    "Post-run terrain correction failed error=\(ActivityDiagnosticLog.errorCategory(error))")
                self.track(.init(.activityElevationCorrectionCompleted, properties: [
                    .result: .string("fallback"),
                    .sourceType: .string("on_device"),
                    .latencyBucket: .string(ProductAnalyticsBucket.latency(milliseconds: Date().timeIntervalSince(startedAt) * 1_000)),
                    .errorCategory: .string(self.elevationCorrectionErrorCategory(error))
                ]))
                return originalSummary
            }
        }
    }

    func resumeRecording() {
        let shouldRecoverWorkoutMusic = self.recorder.recoveredSession
        if self.dependencies.phoneWorkoutCoordinator.watchOwnsHealthKitPersistence {
            self.dependencies.phoneWorkoutCoordinator.requestResume()
        } else {
            self.recorder.resume()
        }
        self.sessionController.resume()
        guard shouldRecoverWorkoutMusic else { return }

        Task {
            guard let outcome = await self.dependencies.musicStore.resumeRecoveredWorkoutPlaybackIfNeeded() else { return }
            let properties: [ProductPropertyKey: AnalyticsValue]
            switch outcome {
            case .alreadyPlaying:
                properties = [.result: .string("success"), .sourceType: .string("already_playing")]
            case .resumedExistingQueue:
                properties = [.result: .string("success"), .sourceType: .string("existing_queue")]
            case .rebuiltSelection:
                properties = [.result: .string("success"), .sourceType: .string("rebuilt_selection")]
            case .failed:
                properties = [.result: .string("failure"), .sourceType: .string("unavailable")]
            }
            self.track(.init(.musicPlaybackRecoveryCompleted, properties: properties))
        }
    }

    func pauseRecording() {
        self.pauseRecording(distanceGoalMeters: nil)
    }

    func pauseRecording(distanceGoalMeters: Double?) {
        if self.dependencies.phoneWorkoutCoordinator.watchOwnsHealthKitPersistence {
            self.dependencies.phoneWorkoutCoordinator.requestPause(
                autoTriggered: self.recorder.autoPaused,
                distanceGoalMeters: distanceGoalMeters
            )
        } else {
            self.recorder.pause(distanceGoalMeters: distanceGoalMeters)
        }
        self.sessionController.pause()
    }

    func adoptWatchInitiatedSessionIfNeeded() {
        guard self.recorder.state != .idle else { return }
        self.activeIntent = self.setup.plannedIntent ?? .freestyleRun
        self.live.activePage = self.preferredSessionPage
        self.live.isLiveWorkoutPanelExpanded = false
        self.presentLiveSurface()
        self.guide.setSpeechEnabled(self.voiceGuideSpeechEnabled)
        self.guide.activate(
            with: self.effectiveCoachingProfile,
            persona: self.dependencies.guideCatalog.selectedPersona,
            sessionIntent: self.activeIntent,
            unitSystem: self.dependencies.measurementPreferences.unitSystem,
            weatherSnapshot: self.dependencies.weatherStore.snapshot,
            isIndoor: self.setup.isIndoorSession,
            challenge: .off,
            suppressedMomentTypes: self.dependencies.guideCatalog.suppressedMomentTypes(
                for: self.dependencies.guideCatalog.selection.coachingContract
            )
        )
        self.updateLiveActivity(snapshot: self.recorder.liveSnapshot, state: self.recorder.state, intent: self.activeIntent)
    }

    var preferredSessionPage: SessionPage {
        SessionPage(rawValue: self.preferredSessionPageRawValue) ?? .map
    }

    var activityCloseSystemImage: String {
        "xmark"
    }

    var activityCloseAccessibilityLabel: String {
        self.isCountingDown
            ? String(localized: "Cancel activity start")
            : String(localized: "Close activity setup")
    }
}
