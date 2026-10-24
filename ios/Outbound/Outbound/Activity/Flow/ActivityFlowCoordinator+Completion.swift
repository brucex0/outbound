import SwiftUI
import PhotosUI
import CoreLocation
import MapKit

extension ActivityFlowCoordinator {
    func savePendingActivity(
        _ activity: PendingFinishedActivity,
        photos: [(UIImage, PhotoMetadata)],
        reflection: FinishReflection
    ) async -> Bool {
        guard self.sessionController.beginSaving() else { return false }
        // Persist the best result already available; never wait for the network.
        let correctedSummary = self.review.pendingActivity.flatMap {
            $0.id == activity.id ? $0.summary : nil
        } ?? activity.summary
        let resolvedActivity = PendingFinishedActivity(
            id: activity.id,
            summary: correctedSummary,
            photos: activity.photos,
            reflection: activity.reflection,
            recognitionPreviews: activity.recognitionPreviews,
            guidanceReport: activity.guidanceReport
        )
        let eligibility = ActivitySaveEligibility.evaluate(
            durationSecs: resolvedActivity.summary.durationSecs,
            distanceM: resolvedActivity.summary.distanceM
        )
        guard eligibility == .eligible else {
            ActivityDiagnosticLog.notice(
                .persistence,
                "Post-run save blocked eligibility=too_short duration=\(ActivityDiagnosticLog.durationBucket(seconds: resolvedActivity.summary.durationSecs)) distance=\(ActivityDiagnosticLog.distanceBucket(meters: resolvedActivity.summary.distanceM))"
            )
            self.sessionController.saveFailed()
            return false
        }

        let priorActivities = self.dependencies.activityStore.activities
        let previewProgress = self.dependencies.goalStore.previewProgress(with: resolvedActivity.summary, activities: priorActivities)
        let savedActivityType = self.activeIntent?.resolvedActivityType ?? .running
        let savedSport = SportType(activityType: savedActivityType)
        let energyKilocalories = WorkoutCalorieEstimator.estimate(
            for: resolvedActivity.summary,
            activityType: savedActivityType,
            weightKilograms: self.dependencies.onboardingStore.latestWeightKilograms
        ).kilocalories
        let followedRoute = self.activeIntent?.preparedRoute.map { route in
            FollowedRouteMetadata(
                route: route,
                finalProgress: resolvedActivity.summary.routeGuidance?.progressFraction ?? 0,
                arrived: resolvedActivity.summary.routeGuidance?.hasArrived ?? false
            )
        }

        ActivityDiagnosticLog.notice(
            .persistence,
            "Post-run save requested type=\(savedActivityType.rawValue) duration=\(ActivityDiagnosticLog.durationBucket(seconds: resolvedActivity.summary.durationSecs)) distance=\(ActivityDiagnosticLog.distanceBucket(meters: resolvedActivity.summary.distanceM)) photos=\(ActivityDiagnosticLog.countBucket(photos.count)) recovered=\(self.didRestoreSession)"
        )
        let savedActivity: SavedActivity
        do {
            savedActivity = try await self.dependencies.activityStore.save(
                summary: resolvedActivity.summary,
                photos: photos,
                activityType: savedActivityType,
                reflection: reflection,
                goal: self.activeIntent?.activityGoal,
                energyKilocalories: energyKilocalories,
                title: self.savedActivityTitle(for: savedActivityType),
                source: .outboundRecorded,
                gear: savedActivityType == .running ? self.dependencies.gearStore.attachment(for: self.setup.selectedSessionShoe) : nil,
                indoor: self.setup.isIndoorSession ? ActivityIndoorMetadata(isIndoor: true, mode: "treadmill") : nil,
                heartRateZones: resolvedActivity.summary.heartRateZones,
                recordingSession: self.resolvedRecordingSession(for: resolvedActivity.summary),
                // The recording session owns attribution; unrelated Social state may change.
                activityEventID: self.activeIntent?.activityEvent?.id,
                followedRoute: followedRoute,
                recognitionBadgeIDs: resolvedActivity.recognitionPreviews.map(\.badgeID),
                companionType: self.isCompanionContextEligible ? self.setup.companionType : nil
            )
        } catch {
            ActivityDiagnosticLog.error(
                .persistence,
                "Post-run save failed error=\(ActivityDiagnosticLog.errorCategory(error))"
            )
            self.sessionController.saveFailed()
            return false
        }
        AppReviewRequestPolicy.recordSuccessfulSave(id: savedActivity.id)
        ActivityDiagnosticLog.notice(.persistence, "Post-run save completed local_state=durable")
        var savedProperties = self.outcomeProperties(for: resolvedActivity.summary)
        savedProperties[.movingTimeMethod] = .string("gps_observations_v2")
        savedProperties[.elapsedDurationBucket] = .string(ProductAnalyticsBucket.duration(seconds: max(resolvedActivity.summary.durationSecs, Int(resolvedActivity.summary.endedAt.timeIntervalSince(resolvedActivity.summary.startedAt)))))
        savedProperties[.activityType] = .string(savedActivityType.rawValue)
        savedProperties[.goalType] = .string(self.analyticsGoalType)
        savedProperties[.photoCountBucket] = .string(ProductAnalyticsBucket.count(photos.count))
        savedProperties[.musicEnabled] = .boolean(self.musicWasConfigured)
        savedProperties[.routeSelected] = .boolean(self.activeIntent?.preparedRoute != nil)
        savedProperties[.shoeSelected] = .boolean(self.setup.selectedSessionShoe != nil)
        savedProperties[.groupRunEnabled] = .boolean(self.activityStartedWithGroupRun)
        savedProperties[.indoor] = .boolean(self.setup.isIndoorSession)
        savedProperties[.dogCompanionEnabled] = .boolean(self.activeIntent?.resolvedActivityType.ineligibleForCompanion != true && self.setup.companionType != nil)
        self.track(.init(.activitySaved, properties: savedProperties))
        if let followedRoute {
            self.track(.init(.routeGuidanceCompleted, properties: [
                .sourceType: .string(followedRoute.source.rawValue),
                .direction: .string(followedRoute.direction.rawValue),
                .progressPercent: .integer(self.coarseRouteProgressPercent(followedRoute.finalProgress)),
                .result: .string(followedRoute.arrived ? "arrived" : "partial")
            ]))
        }
        _ = self.dependencies.socialStore.consumeRecordingActivityEventID()

        // Snapshot confirmation before clearing the completed coordinator below.
        // Ownership alone is not proof of a successful same-session Watch save.
        let watchSaveConfirmed = self.dependencies.phoneWorkoutCoordinator.hasConfirmedWatchHealthSave(for: savedActivity.recordingSession)
        Task {
            if watchSaveConfirmed {
                ActivityDiagnosticLog.notice(.healthKit, "Health workout write-back skipped result=watch_save_confirmed")
                self.track(.init(.healthWorkoutWriteBack, properties: [
                    .sourceType: .string("apple_watch"), .result: .string("skipped_confirmed_save")
                ]))
                return
            }
            do {
                try await HealthKitService().saveWorkout(
                    savedActivity,
                    sport: savedSport,
                    energyKilocalories: energyKilocalories.map(Double.init)
                )
                self.track(.init(.healthWorkoutWriteBack, properties: [
                    .sourceType: .string("iphone"), .result: .string("success")
                ]))
            } catch {
                let category = ActivityDiagnosticLog.errorCategory(error)
                ActivityDiagnosticLog.error(.healthKit, "Post-run Health workout write-back failed error=\(category)")
                self.track(.init(.healthWorkoutWriteBack, properties: [
                    .sourceType: .string("iphone"), .result: .string("failure"),
                    .errorCategory: .string(category)
                ]))
            }
        }

        if let workoutReference = self.activeIntent?.workoutReference,
           workoutReference.source == "planned_workout" {
            let completionRequest = PlannedWorkoutCompletionRequest(
                activityId: nil,
                completedAt: resolvedActivity.summary.endedAt,
                durationSeconds: resolvedActivity.summary.durationSecs,
                distanceMeters: resolvedActivity.summary.distanceM,
                targetCalories: self.activeIntent?.targetCalories,
                energyKilocalories: energyKilocalories,
                avgPace: resolvedActivity.summary.avgPace,
                avgHeartRate: resolvedActivity.summary.healthMetrics?.averageHeartRateBPM,
                completionQuality: "completed"
            )
            Task {
                do {
                    _ = try await APIClient.shared.completePlannedWorkout(
                        id: workoutReference.id, request: completionRequest
                    )
                } catch is CancellationError {
                    // A canceled background completion does not undo a local save.
                } catch {
                    ActivityDiagnosticLog.error(.sync,
                        "Planned workout completion failed error=\(ActivityDiagnosticLog.errorCategory(error))")
                }
            }
        }

        _ = self.dependencies.recognitionStore.recordSavedActivity(
            savedActivity,
            priorActivities: priorActivities,
            goalProgress: previewProgress
        )
        self.dependencies.goalStore.refresh(
            activities: self.dependencies.activityStore.activities,
            phase: DailyMotivationEngine.phase(for: self.dependencies.activityStore.activities)
        )
        if let routines = PostWorkoutStretchCatalog.routines(for: savedActivity.activityType), savedActivity.source.kind == .outbound {
            self.review.postSaveStretchContext = PostSavedStretchContext(activityType: savedActivity.activityType, routines: routines)
        }
        self.review.postSaveCelebrationActivity = savedActivity
        // The store owns enrichment after review is dismissed or the app is offline.
        Task { await self.dependencies.activityStore.correctElevationIfNeeded(for: savedActivity.id) }
        self.clearPending(recoveryReason: .saved)
        self.sessionController.completeSave(withPostSaveFlow: true)
        return true
    }

    func finishPostSaveCelebration() {
        self.review.postSaveCelebrationActivity = nil
        self.review.postSaveStretchContext = nil
        self.sessionController.completeSave(withPostSaveFlow: false)
        self.host.onPostSaveCompleted?()
        self.host.onCloseRequest?(false)
    }

    func finishPostSaveStretch() {
        self.review.postSaveStretchContext = nil
        self.review.postSaveCelebrationActivity = nil
        self.sessionController.completeSave(withPostSaveFlow: false)
        self.host.onPostSaveCompleted?()
        self.host.onCloseRequest?(false)
    }

    func discardPendingActivity() {
        if let pendingActivity = self.review.pendingActivity {
            WatchWorkoutImportSuppression.remember(self.resolvedRecordingSession(for: pendingActivity.summary))
            var properties = self.outcomeProperties(for: pendingActivity.summary)
            properties[.photoCountBucket] = .string(ProductAnalyticsBucket.count(pendingActivity.photos.count))
            self.track(.init(.activityDiscarded, properties: properties))
            ActivityDiagnosticLog.notice(
                .lifecycle,
                "Post-run activity discarded duration=\(ActivityDiagnosticLog.durationBucket(seconds: pendingActivity.summary.durationSecs)) distance=\(ActivityDiagnosticLog.distanceBucket(meters: pendingActivity.summary.distanceM))"
            )
        }
        let resolvesRecordingEvent = self.activeIntent?.activityEvent?.id == self.dependencies.socialStore.recordingActivityEventID
        let consumedActivityEventID = self.dependencies.socialStore.consumeRecordingActivityEventID()
        let activityEventID = resolvesRecordingEvent ? consumedActivityEventID : nil
        self.liveActivityManager.end()
        self.dependencies.liveShareStore.end()
        self.dependencies.liveGroupStore.finishActivity()
        self.clearPending(recoveryReason: .discarded)
        self.sessionController.reset()
        self.host.onCloseRequest?(false)
        if let activityEventID {
            Task {
                _ = await self.dependencies.socialStore.markActivityEventWithoutRecording(id: activityEventID)
            }
        }
    }

    func clearPending(recoveryReason: ActiveSessionClearReason) {
        self.cancelStartCountdown(returnToSetup: true)
        self.review.elevationCorrectionTask?.cancel()
        self.review.elevationCorrectionTask = nil
        self.review.pendingActivity = nil
        self.live.isLiveWorkoutPanelExpanded = false
        self.live.capturedPhotos = []
        self.live.isCapturingSessionPhoto = false
        self.clearSessionRecoveryArtifacts(reason: recoveryReason)
        self.host.onPreActivityPhotoChange?(nil)
        self.activeIntent = nil
        self.sessionController.reset()
        self.setup.plannedIntent = nil
        self.setup.curatedWorkoutIntent = nil
        self.setup.selectedWorkoutChoice = .sport(.run)
        self.setup.manualActivityGoal = .freestyle
        self.didAutoStopAtGoal = false
        self.setup.manualSetupDrafts = [:]
        self.setup.selectedGoalMode = .freestyle
        self.setup.selectedSessionShoeID = nil
        self.setup.didApplyDefaultSessionShoe = false
        self.setup.isIndoorSession = false
        self.setup.companionType = nil
        self.activityStartedWithGroupRun = false
        self.setup.intentBeforeSelectedRoute = nil
        self.setup.selectedRouteDistanceMeters = nil
        self.setup.selectedGuidanceChallenge = .off
        self.dependencies.phoneWorkoutCoordinator.clearCompletedSession()
#if DEBUG
        self.isRunSimulationEnabled = false
#endif
    }

    func clearSessionRecoveryArtifacts(reason: ActiveSessionClearReason) {
        ActiveSessionJournal.clear(reason: reason)
        let photosCleared = ActiveSessionPhotoJournal.clear()
        ActivityDiagnosticLog.notice(
            .recovery,
            "Recovery photo artifacts cleared reason=\(reason.rawValue) result=\(photosCleared ? "success" : "failure")"
        )
    }

    func resolvedRecordingSession(for summary: ActivitySummary) -> ActivityRecordingSessionMetadata? {
        let currentMetadata = self.dependencies.phoneWorkoutCoordinator.recordingMetadata()
        guard let metadata = summary.sessionMetadata else { return nil }
        // A newer Watch session must never supply ownership or save confirmation
        // for a previously completed phone recording.
        guard let currentMetadata, currentMetadata.sessionUUID == metadata.sessionUUID else {
            return metadata
        }
        return ActivityRecordingSessionMetadata(
            sessionUUID: metadata.sessionUUID,
            origin: currentMetadata.origin,
            recordingDevice: currentMetadata.recordingDevice,
            healthKitOwnership: currentMetadata.healthKitOwnership,
            healthKitWorkoutExternalReference: currentMetadata.healthKitWorkoutExternalReference
                ?? metadata.healthKitWorkoutExternalReference
        )
    }
}
