import SwiftUI
import PhotosUI
import CoreLocation
import MapKit

extension ActivityFlowCoordinator {
    func prepareSetupSurface() {
        self.dependencies.guideCatalog.refreshInstalledVoices()
        self.launchCoordinator.prepare(intent: self.setup.plannedIntent)
        self.sessionController.prepare(intent: self.setup.plannedIntent)
        self.applyLearnedGoalModeIfNeeded()
        self.applySmartGoalDefaultIfNeeded()
        self.setup.applyDefaultSessionShoeIfNeeded()
        self.trackSetupAndFeatureExposureIfNeeded()
    }

    var usesEmbeddedPlannedContent: Bool {
        self.host.isEmbeddedInToday && self.setup.selectedWorkoutChoice == .planned
    }

    var showsEnableLocationChip: Bool {
#if DEBUG
        if self.isRunSimulationEnabled { return false }
#endif
        return !self.isLocationPermissionGranted && !self.setup.isIndoorSession
    }

    var showsLaunchGoalCard: Bool {
        !self.usesEmbeddedPlannedContent && self.setup.selectedGoalMode != .freestyle
    }

    func autoPauseEnabled(for activityType: ActivityType) -> Bool {
        switch activityType {
        case .running: self.autoPauseRunningEnabled
        case .cycling: self.autoPauseCyclingEnabled
        case .walking: self.autoPauseWalkingEnabled
        case .hiking: self.autoPauseHikingEnabled
        case .swimming, .strengthTraining, .mobility: AutoPauseDefaults.isEnabled(for: activityType)
        }
    }

    func setAutoPauseEnabled(_ enabled: Bool, for activityType: ActivityType) {
        switch activityType {
        case .running: self.autoPauseRunningEnabled = enabled
        case .cycling: self.autoPauseCyclingEnabled = enabled
        case .walking: self.autoPauseWalkingEnabled = enabled
        case .hiking: self.autoPauseHikingEnabled = enabled
        case .swimming, .strengthTraining, .mobility: break
        }
    }

    func savedActivityTitle(for savedActivityType: ActivityType) -> String? {
        // Event titles must win over the generic running fallback. The
        // fallback used to turn a run whose live title was correct into e.g.
        // “Monday evening run” when it was saved.
        if let eventTitle = (self.activeIntent?.activityEvent ?? self.setup.plannedIntent?.activityEvent)?.title {
            return eventTitle
        }
        if self.isCompanionContextEligible, self.isFreestyleSession {
            return self.setup.companionType?.defaultFreestyleTitle(for: savedActivityType)
        }
        return self.activeIntent?.preparedRoute == nil && savedActivityType == .running
            ? nil
            : self.activeIntent?.title
    }

    var isFreestyleSession: Bool {
        guard let intent = self.activeIntent ?? self.setup.plannedIntent else { return true }
        return intent.preparedRoute == nil
            && intent.workoutSteps.isEmpty
            && intent.raceIntent == nil
            && intent.workoutReference == nil
            && intent.activityEvent == nil
    }

    var isCompanionContextEligible: Bool {
        guard self.setup.companionType != nil else { return false }
        let resolvedType = (self.activeIntent ?? self.setup.plannedIntent ?? .freestyleRun).resolvedActivityType
        return ActivityCompanionType.isEligible(for: resolvedType)
    }

    func toggleCompanionContext() {
        let willEnable = self.setup.companionType == nil
        self.setup.companionType = willEnable ? .dog : nil
        self.track(.init(.activityConfigurationChanged, properties: [
            .changeType: .string("companion"),
            .selectionType: .string(willEnable ? "dog" : "off")
        ]))
        if willEnable {
            self.trackFeatureExposure("dog_companion")
        }
    }

    func reconcileCompanionContextAfterSportChange(previousType: ActivityType?, newType: ActivityType) {
        guard self.setup.companionType != nil, ActivityCompanionType.isEligible(for: newType) == false else { return }
        self.setup.companionType = nil
        self.showSetupToast(String(
            localized: "recording.companion.cleared.message", defaultValue: "With dog is only available for runs, walks, hikes, and rides."
        ))
        self.track(.init(.activityConfigurationChanged, properties: [
            .changeType: .string("companion"),
            .selectionType: .string("cleared")
        ]))
    }

    func selectLaunchMode(_ mode: SessionGoalMode) {
        setup.hasEditedLaunchConfiguration = true
        guard self.setup.selectedWorkoutChoice != .planned else {
            if mode == .planned {
                self.selectWorkoutChoice(.planned)
            }
            return
        }
        if mode == .calories, !self.setup.hasWeightForCalories {
            self.presentCaloriesWeightPrompt(for: .selectMode(reopenGoalEditor: false))
            return
        }
        if mode == .curated {
            self.openCuratedWorkoutPicker()
            return
        }
        if mode == .race {
            guard self.setup.selectedManualSport == .run else { return }
            self.setup.showsRacePlanner = true
            self.track(.init(.planningSurfaceOpened, properties: [
                .sourceType: .string("race"),
                .entrySource: .string("manual_mode_row"),
            ]))
            return
        }
        guard let sport = self.setup.selectedManualSport else { return }
        self.setup.resetCuratedStructureForManualGoalIfNeeded()
        let draft = self.setup.resolvedManualSetupDraft(for: sport)
        self.applyGoal(self.setup.resolvedGoal(for: draft, mode: mode), trackChange: false)
    }

    func selectWorkoutChoice(_ choice: LaunchWorkoutChoice, trackChange: Bool = true) {
        if trackChange { setup.hasEditedLaunchConfiguration = true }
        if trackChange, choice == .sport(.walk) {
            let didRequestPermission = self.recorder.locationManager.requestStepMotionPermissionIfNeeded { result in
                self.track(.init(.motionAuthorizationCompleted, properties: [
                    .result: .string(result.rawValue)
                ]))
            }
            if didRequestPermission {
                self.track(.init(.motionAuthorizationRequested))
            }
        }
        let selectedRoute = self.setup.plannedIntent?.preparedRoute
        let previousResolvedType = self.setup.plannedIntent?.resolvedActivityType
        let nextBaseIntent: SessionIntent
        var restoredManualGoal: ActivityGoal?

        switch choice {
        case .planned:
            let workoutIntent: SessionIntent
            if let plannedWorkoutIntent = self.setup.plannedWorkoutIntent {
                workoutIntent = plannedWorkoutIntent
            } else if self.dependencies.trainingPlanStore.activePlan != nil {
                workoutIntent = self.dependencies.trainingPlanStore.todaySuggestion?.suggestedSession.intent ?? .freestyleRun
                self.setup.plannedWorkoutIntent = workoutIntent
            } else {
                self.host.onPlanBuilderRequested?()
                return
            }
            self.setup.selectedWorkoutChoice = .planned
            self.setup.selectedGoalMode = .planned
            nextBaseIntent = self.setup.routeFreeIntent(from: workoutIntent)
        case .sport(let sport):
            let draft = self.setup.resolvedManualSetupDraft(for: sport)
            let goal = self.setup.resolvedGoal(for: draft, mode: draft.selectedMode)
            self.setup.manualSetupDrafts[sport] = draft
            self.setup.selectedWorkoutChoice = choice
            self.setup.selectedGoalMode = draft.selectedMode
            self.setup.manualActivityGoal = goal
            nextBaseIntent = self.setup.freestyleFallback(for: sport)
            restoredManualGoal = goal
        }
        self.reconcileCompanionContextAfterSportChange(
            previousType: previousResolvedType,
            newType: nextBaseIntent.resolvedActivityType
        )

        if let selectedRoute {
            self.setup.intentBeforeSelectedRoute = nextBaseIntent
            self.setup.plannedIntent = self.setup.routeIntent(selectedRoute, appliedTo: nextBaseIntent)
            if self.setup.selectedRouteDistanceMeters == nil {
                self.setup.selectedRouteDistanceMeters = Self.calculatePreparedRouteDistance(selectedRoute)
            }
        } else {
            self.setup.plannedIntent = nextBaseIntent
            self.setup.intentBeforeSelectedRoute = nil
            self.setup.selectedRouteDistanceMeters = nil
        }

        if let restoredManualGoal,
           !self.applyGoal(restoredManualGoal, trackChange: false) {
            self.setup.selectedGoalMode = .freestyle
            self.setup.manualActivityGoal = .freestyle
        }

        if trackChange {
            self.track(.init(.activityConfigurationChanged, properties: [
                .changeType: .string("workout_type"),
                .selectionType: .string(choice.analyticsValue)
            ]))
        }
    }

    func openCuratedWorkoutPicker() {
        guard self.setup.selectedManualSport != nil else { return }
        self.track(.init(.planningSurfaceOpened, properties: [
            .sourceType: .string("curated_workouts"),
            .entrySource: .string("manual_mode_row"),
        ]))
        self.setup.showsCuratedWorkouts = true
    }

    func setVoiceGuideEnabled(_ isEnabled: Bool) {
        if isEnabled, self.isVoiceGuideExplicitlyUnavailable {
            self.track(.init(.activityConfigurationChanged, properties: [
                .changeType: .string("voice_guide"),
                .selectionType: .string("unavailable")
            ]))
            self.showSetupToast(String(
                localized: "record.voice_guide.unavailable.message",
                defaultValue: "Voice Guide audio is temporarily unavailable."
            ))
            return
        }
        self.isVoiceGuideEnabled = isEnabled
        self.guide.setSpeechEnabled(self.voiceGuideSpeechEnabled)
        self.track(.init(.activityConfigurationChanged, properties: [
            .changeType: .string("voice_guide"),
            .selectionType: .string(isEnabled ? "enabled" : "disabled")
        ]))
        guard isEnabled else { return }
        Task { await self.dependencies.guideCatalog.refreshServerCatalog() }
    }

    func handlePreActivityPhotoAction() {
        if self.preActivityPhoto == nil {
            self.track(.init(.photoCaptureAttempted, properties: [.sourceType: .string("pre_activity_camera")]))
            self.setup.isPreActivityCameraPresented = true
        } else {
            self.track(.init(.photoPreviewed, properties: [.sourceType: .string("pre_activity")]))
            self.setup.isPreActivityPhotoPreviewPresented = true
        }
    }

    func handlePreActivityPhotoRequest() {
        guard self.host.isEmbeddedInToday,
              self.host.isVisible,
              self.review.pendingActivity == nil,
              self.recorder.state == .idle,
              !self.showCamera
        else { return }
        self.handlePreActivityPhotoAction()
    }

    func handleRouteSelectionRequest() {
        guard self.host.isEmbeddedInToday,
              self.host.isVisible,
              self.review.pendingActivity == nil,
              self.recorder.state == .idle,
              !self.showCamera
        else { return }
        self.openRouteLibrary()
    }

    func handleGroupRunRequest() {
        guard self.host.isEmbeddedInToday,
              self.host.isVisible,
              self.review.pendingActivity == nil,
              self.recorder.state == .idle,
              !self.showCamera
        else { return }
        self.trackFeatureExposure("group_run")
        self.setup.setupSheet = .groupRun
    }

    func handleRouteRemovalRequest() {
        guard self.host.isEmbeddedInToday,
              self.host.isVisible,
              self.review.pendingActivity == nil,
              self.recorder.state == .idle,
              !self.showCamera,
              let route = self.setup.plannedIntent?.preparedRoute
        else { return }
        self.removeSelectedRoute(route)
    }

    var canRequestMusicDiscoveryTip: Bool {
        self.host.isVisible
            && !self.showCamera
            && (self.dependencies.musicStore.snapshot.connectionState == .notConnected
                || self.dependencies.musicStore.snapshot.connectionState == .denied
                || self.dependencies.musicStore.needsPlaybackSetup)
    }

    var photoAccessibilityValue: String { self.preActivityPhoto == nil ? String(localized: "record.photo.not_added", defaultValue: "No photo added") : String(localized: "record.photo.added", defaultValue: "Photo added") }

    func finishAtGoalIfNeeded(_ snapshot: ActiveSessionSnapshot) {
        guard self.autoStopAtGoalEnabled,
              !self.didAutoStopAtGoal,
              self.recorder.state == .active,
              [.distance, .time, .calories].contains(self.setup.selectedGoalMode),
              let ratio = self.goalCompletionRatio(
                distanceMeters: snapshot.distanceMeters,
                durationSeconds: snapshot.elapsedSeconds
              ),
              ratio >= 1
        else { return }

        self.didAutoStopAtGoal = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let distanceGoal = self.setup.selectedGoalMode == .distance ? self.setup.currentActivityGoal.targetDistanceMeters : nil
        self.pauseRecording(distanceGoalMeters: distanceGoal)
    }

    func preparedRouteDistance(_ route: PreparedRoute) -> Double {
        if let selectedRoute = self.setup.plannedIntent?.preparedRoute,
           selectedRoute.id == route.id,
           selectedRoute.source == route.source,
           let selectedRouteDistanceMeters = self.setup.selectedRouteDistanceMeters {
            return selectedRouteDistanceMeters
        }
        return Self.calculatePreparedRouteDistance(route)
    }

    nonisolated static func calculatePreparedRouteDistance(_ route: PreparedRoute) -> Double {
        zip(route.points, route.points.dropFirst()).reduce(0) { total, pair in
            let start = CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
            let end = CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude)
            return total + start.distance(from: end)
        }
    }

    func showSetupToast(_ message: String?) {
        guard let message, !message.isEmpty else { return }
        self.setupToastTask?.cancel()
        withAnimation { self.setupToastMessage = message }
        self.setupToastTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run { withAnimation { self.setupToastMessage = nil } }
        }
    }

    var preActivityPhoto: UIImage? {
        self.live.capturedPhotos.last(where: { $0.1.captureContext == .preActivity })?.0
    }

    func restoreInterruptedPhotosIfNeeded() {
        guard self.recorder.recoveredSession, !self.didRestoreSessionPhotos else { return }
        self.didRestoreSessionPhotos = true
        let restoredPhotos = ActiveSessionPhotoJournal.load()
        guard !restoredPhotos.isEmpty else { return }
        self.live.capturedPhotos = restoredPhotos
        self.track(.init(.activityPhotoRecovery, properties: [
            .countBucket: .string(ProductAnalyticsBucket.count(restoredPhotos.count)),
            .preRunPhotoAdded: .boolean(
                restoredPhotos.contains { $0.1.captureContext == .preActivity }
            )
        ]))
    }

    func replacePreActivityPhoto(with image: UIImage) {
        self.removePreActivityPhoto()
        let coordinate = self.recorder.locationManager.location?.coordinate
        let photo = (
            image,
            PhotoMetadata(
                takenAt: Date(),
                paceAtShot: nil,
                hrAtShot: nil,
                distAtShot: 0,
                coordinate: coordinate,
                captureContext: .preActivity
            )
        )
        self.live.capturedPhotos.append(photo)
        ActiveSessionPhotoJournal.append(photo)
        self.track(.init(.photoCaptured, properties: [
            .sourceType: .string("pre_activity"),
            .locationAttached: .boolean(coordinate != nil)
        ]))
        self.host.onPreActivityPhotoChange?(image)
    }

    func removePreActivityPhoto() {
        self.live.capturedPhotos.removeAll { $0.1.captureContext == .preActivity }
        ActiveSessionPhotoJournal.removePreActivityPhotos()
        self.host.onPreActivityPhotoChange?(nil)
    }

    func openAddShoe() {
        self.track(.init(.shoeSelected, properties: [.selectionType: .string("add_new")]))
        self.setup.isAddShoePresented = true
    }

    func prepareGoalEditor() {
        self.setup.goalEditorSelection = nil
        guard let kind = self.setup.goalEditorKind else { return }
        let currentGoal = self.setup.currentActivityGoal
        if self.setup.goalEditorPresetGoals(for: kind).contains(currentGoal) {
            self.setup.goalEditorSelection = currentGoal
            self.setCustomGoalText("", for: kind)
            return
        }
        switch kind {
        case .distance:
            if let meters = currentGoal.targetDistanceMeters {
                self.setup.customDistanceText = self.dependencies.measurementPreferences.unitSystem.distanceValue(meters: meters)
                    .formatted(.number.locale(.autoupdatingCurrent).precision(.fractionLength(0...2)).grouping(.never))
            } else { self.setup.customDistanceText = "" }
        case .time:
            self.setup.customTimeText = currentGoal.targetDurationSeconds.map { String(max(1, $0 / 60)) } ?? ""
        case .calories:
            self.setup.customCaloriesText = currentGoal.targetCalories.map(String.init) ?? ""
        }
    }

    func presentCaloriesWeightPrompt(
        for action: PendingCaloriesWeightAction,
        afterCurrentPresentation: Bool = false
    ) {
        self.setup.pendingCaloriesWeightAction = action
        self.setup.caloriesWeightText = ""
        self.trackCaloriesWeightPrompt(selection: "presented")
        if afterCurrentPresentation {
            Task { @MainActor in
                await Task.yield()
                self.setup.isCaloriesWeightPromptPresented = true
            }
        } else {
            self.setup.isCaloriesWeightPromptPresented = true
        }
    }

    func savePromptedWeightAndContinue() {
        guard let weightKilograms = self.setup.promptedWeightKilograms else { return }
        self.showSetupToast(String(
            localized: "record.goal.calories.weight_prompt.saving",
            defaultValue: "Saving weight…"
        ))
        Task { @MainActor in
            do {
                let currentProfile = try await APIClient.shared.fetchTrainingProfile()
                let updatedProfile = try await APIClient.shared.updateTrainingProfile(
                    TrainingProfileUpdateDTO(
                        sexAtBirth: currentProfile.sexAtBirth,
                        birthDate: currentProfile.birthDate,
                        heightCentimeters: currentProfile.heightCentimeters,
                        weightKilograms: weightKilograms,
                        primaryMotivation: currentProfile.primaryMotivation,
                        preferredRunGoalType: currentProfile.preferredRunGoalType
                    )
                )
                self.dependencies.onboardingStore.applyTrainingProfile(updatedProfile)
                self.trackCaloriesWeightPrompt(selection: "saved")
                self.resumePendingCaloriesWeightAction()
            } catch {
                self.setup.pendingCaloriesWeightAction = nil
                self.trackCaloriesWeightPrompt(selection: "save_failed")
                self.showSetupToast(String(
                    localized: "record.goal.calories.weight_prompt.save_failed",
                    defaultValue: "Couldn’t save your weight. Try again."
                ))
            }
        }
    }

    func resumePendingCaloriesWeightAction() {
        guard let action = self.setup.pendingCaloriesWeightAction else { return }
        self.setup.pendingCaloriesWeightAction = nil
        switch action {
        case .selectMode(let reopenGoalEditor):
            if self.setup.selectedWorkoutChoice == .planned {
                self.setup.selectedGoalMode = .calories
            } else {
                self.selectLaunchMode(.calories)
            }
            if reopenGoalEditor {
                self.setup.setupSheet = .goal
            }
        }
    }

    func applyRacePlan(_ race: RaceExecutionIntent) {
        let intent = SessionIntent(
            id: "race-\(Int(race.distanceMeters.rounded()))",
            sport: .run,
            title: String(localized: "race.planner.race_day", defaultValue: "Race day"),
            detail: self.setup.racePlanSummary(race),
            guideLine: RacePlanGuidance.execution(for: race, unitSystem: self.dependencies.measurementPreferences.unitSystem),
            startLabel: String(localized: "race.planner.start_race", defaultValue: "Start race"),
            targetDistanceMeters: race.distanceMeters,
            coachingTarget: race.targetPaceSecondsPerKilometer.map {
                SessionCoachingTarget(
                    phase: .work,
                    pace: SessionPaceTarget(
                        reference: .absolute,
                        targetSecondsPerKilometer: $0,
                        fasterToleranceSeconds: 15,
                        slowerToleranceSeconds: 20
                    ),
                    recognizesTargetLock: true
                )
            } ?? .work,
            raceIntent: race
        )
        if let route = self.setup.plannedIntent?.preparedRoute {
            self.setup.plannedIntent = self.setup.routeIntent(route, appliedTo: intent)
        } else {
            self.setup.plannedIntent = intent
        }
        self.setup.selectedWorkoutChoice = .sport(.run)
        self.didAutoStopAtGoal = false
        self.setup.selectedGoalMode = .race
        self.setup.selectedGuidanceChallenge = .off
        self.setup.manualActivityGoal = .distanceMeters(race.distanceMeters)
        self.track(.init(.activityConfigurationChanged, properties: [
            .changeType: .string("race_plan"),
            .goalType: .string("race"),
            .sourceType: .string(race.recommendationSource),
            .pacingStrategy: .string(race.pacingStrategy.rawValue),
            .targetBucket: .string(ProductAnalyticsBucket.distance(meters: race.distanceMeters)),
        ]))
    }

    @discardableResult
    func applyGoal(
        _ goal: ActivityGoal,
        trackChange: Bool = true,
        selectionType: String? = nil
    ) -> Bool {
        if trackChange { setup.hasEditedLaunchConfiguration = true }
        let currentIntent = self.setup.plannedIntent ?? .freestyleRun
        if case .calories(let targetCalories) = goal {
            let isEligibleManualSport = self.setup.selectedWorkoutChoice != .planned
                && (currentIntent.sport == .run || currentIntent.sport == .walk)
            guard currentIntent.allowsCalorieGoal || isEligibleManualSport else {
                self.showSetupToast(String(
                    localized: "record.goal.calories.activity_unavailable",
                    defaultValue: "Calorie targets are available for manual runs and walks, plus easy or recovery planned runs."
                ))
                return false
            }
            guard let weightKilograms = self.dependencies.onboardingStore.latestWeightKilograms, weightKilograms > 0 else {
                self.showSetupToast(String(
                    localized: "record.goal.calories.weight_required",
                    defaultValue: "Add your weight in Body Profile to use a calorie target."
                ))
                return false
            }
            let estimate: PlannedCalorieEstimate?
            switch currentIntent.sport {
            case .run:
                let learnedPace = WorkoutCalorieEstimator.resolveLearnedRunPace(
                    activities: self.dependencies.activityStore.activities,
                    calibrationCompleted: self.dependencies.personalizationStore.snapshot.calibration.status == .completed
                )
                estimate = WorkoutCalorieEstimator.plannedRun(
                    targetCalories: targetCalories,
                    weightKilograms: weightKilograms,
                    paceSecondsPerKilometer: learnedPace.secondsPerKilometer
                )
                if estimate == nil {
                    self.showSetupToast(String(
                        localized: "record.goal.calories.pace_required",
                        defaultValue: "Complete calibration or save three runs before using a calorie target."
                    ))
                    return false
                }
            case .walk:
                estimate = WorkoutCalorieEstimator.plannedWalk(
                    targetCalories: targetCalories,
                    weightKilograms: weightKilograms
                )
            case .bike, .hike, .swim, .strength, .mobility:
                estimate = nil
            }
            guard let estimate else { return false }
            self.setup.plannedIntent = currentIntent.replacingCalorieGoal(
                estimate,
                unitSystem: self.dependencies.measurementPreferences.unitSystem
            )
        } else {
            self.setup.plannedIntent = currentIntent.replacingGoal(goal, unitSystem: self.dependencies.measurementPreferences.unitSystem)
        }
        if let sport = self.setup.selectedManualSport {
            var draft = self.setup.resolvedManualSetupDraft(for: sport)
            draft.remember(goal)
            self.setup.manualSetupDrafts[sport] = draft
            self.setup.manualActivityGoal = goal
        }
        self.setup.selectedGoalMode = SessionGoalMode(goal: goal)
        if trackChange {
            var properties: [ProductPropertyKey: AnalyticsValue] = [
                .changeType: .string("goal"),
                .activityType: .string((self.setup.plannedIntent ?? currentIntent).resolvedActivityType.rawValue),
                .goalType: .string(self.analyticsGoalType),
                .targetBucket: .string(self.analyticsTargetBucket(for: goal)),
                .sourceType: .string(self.setup.selectedWorkoutChoice == .planned ? "planned_override" : "manual")
            ]
            if let selectionType {
                properties[.selectionType] = .string(selectionType)
            }
            self.track(.init(.activityConfigurationChanged, properties: properties))
        }
        return true
    }

    func openRouteLibrary() {
        self.trackFeatureExposure("routes")
        self.setup.showsRouteLibrary = true
        self.track(.init(.routeLibraryOpened))
    }

    func removeSelectedRoute(_ route: PreparedRoute) {
#if DEBUG
        self.isRunSimulationEnabled = false
#endif
        self.applyRoute(nil)
        self.track(.init(.routeRemoved, properties: [.sourceType: .string(route.source.rawValue)]))
    }

    func removeNamedRoute() {
        self.applyRoute(nil)
        self.track(.init(.routeRemoved, properties: [.sourceType: .string("named")]))
    }

    func routeDistanceLabel(_ route: PreparedRoute) -> String {
        let meters = self.preparedRouteDistance(route)
        return self.dependencies.measurementPreferences.unitSystem.distanceString(
            meters: meters,
            fractionDigits: 1
        )
    }

    func routeGoalAdvisory(_ route: PreparedRoute) -> String? {
        guard case .distanceMeters(let goalMeters) = self.setup.currentActivityGoal else { return nil }
        let routeMeters = self.preparedRouteDistance(route)
        guard routeMeters > 0,
              abs(routeMeters - goalMeters) > max(500, routeMeters * 0.1)
        else { return nil }
        return String(
            format: String(localized: "record.route.goal_difference", defaultValue: "Your %@ goal and %@ route are different. You can keep both."),
            locale: .autoupdatingCurrent,
            self.setup.currentActivityGoal.label(unitSystem: self.dependencies.measurementPreferences.unitSystem),
            self.routeDistanceLabel(route)
        )
    }

    func applyRoute(_ route: PreparedRoute?) {
#if DEBUG
        self.isRunSimulationEnabled = route != nil && self.routeTestMode
#endif
        let currentIntent = self.setup.plannedIntent ?? .freestyleRun
        if let route {
            if currentIntent.preparedRoute == nil {
                self.setup.intentBeforeSelectedRoute = currentIntent
            }
            let baseIntent = self.setup.intentBeforeSelectedRoute ?? currentIntent
            let nextIntent = self.setup.routeIntent(route, appliedTo: baseIntent)
            self.setup.plannedIntent = nextIntent
            self.setup.selectedRouteDistanceMeters = Self.calculatePreparedRouteDistance(route)
            self.reconcileCompanionContextAfterSportChange(
                previousType: currentIntent.resolvedActivityType,
                newType: nextIntent.resolvedActivityType
            )
        } else {
            let baseIntent = self.setup.intentBeforeSelectedRoute ?? self.setup.freestyleFallback(for: currentIntent.sport)
            let restoredBase = currentIntent.activityGoal == baseIntent.activityGoal
                ? baseIntent
                : baseIntent.replacingGoal(
                    currentIntent.activityGoal,
                    unitSystem: self.dependencies.measurementPreferences.unitSystem
                )
            self.setup.plannedIntent = SessionIntent(
                id: restoredBase.id,
                sport: restoredBase.sport,
                title: restoredBase.title,
                detail: restoredBase.detail,
                guideLine: restoredBase.guideLine,
                startLabel: restoredBase.startLabel,
                targetDistanceMeters: restoredBase.targetDistanceMeters,
                targetDurationSeconds: restoredBase.targetDurationSeconds,
                targetCalories: restoredBase.targetCalories,
                estimatedDistanceMeters: restoredBase.estimatedDistanceMeters,
                estimatedDurationSeconds: restoredBase.estimatedDurationSeconds,
                allowsCalorieGoal: restoredBase.allowsCalorieGoal,
                routeName: restoredBase.routeName,
                preparedRoute: restoredBase.preparedRoute,
                activityTypeOverride: restoredBase.activityTypeOverride,
                workoutSteps: restoredBase.workoutSteps,
                coachingTarget: restoredBase.coachingTarget,
                workoutReference: restoredBase.workoutReference,
                workoutCues: restoredBase.workoutCues,
                raceIntent: restoredBase.raceIntent,
                activityEvent: restoredBase.activityEvent
            )
            self.setup.intentBeforeSelectedRoute = nil
            self.setup.selectedRouteDistanceMeters = nil
            return
        }
        guard let route else { return }
        self.track(.init(.routeSelected, properties: [
            .sourceType: .string(route.source.rawValue),
            .distanceBucket: .string(ProductAnalyticsBucket.distance(meters: self.preparedRouteDistance(route)))
        ]))
    }

    func updateRouteDirection(_ direction: RouteDirection, for route: PreparedRoute) {
        guard direction != route.direction else { return }
        let directedRoute = route.withDirection(direction)
        let currentIntent = self.setup.plannedIntent ?? .freestyleRun
        self.setup.plannedIntent = SessionIntent(
            id: currentIntent.id,
            sport: currentIntent.sport,
            title: currentIntent.title,
            detail: currentIntent.detail,
            guideLine: currentIntent.guideLine,
            startLabel: currentIntent.startLabel,
            targetDistanceMeters: currentIntent.targetDistanceMeters,
            targetDurationSeconds: currentIntent.targetDurationSeconds,
            targetCalories: currentIntent.targetCalories,
            estimatedDistanceMeters: currentIntent.estimatedDistanceMeters,
            estimatedDurationSeconds: currentIntent.estimatedDurationSeconds,
            allowsCalorieGoal: currentIntent.allowsCalorieGoal,
            routeName: directedRoute.name,
            preparedRoute: directedRoute,
            activityTypeOverride: directedRoute.activityType ?? currentIntent.activityTypeOverride,
            workoutSteps: currentIntent.workoutSteps,
            coachingTarget: currentIntent.coachingTarget,
            workoutReference: currentIntent.workoutReference,
            workoutCues: currentIntent.workoutCues,
            raceIntent: currentIntent.raceIntent,
            activityEvent: currentIntent.activityEvent
        )
        self.track(.init(.activityConfigurationChanged, properties: [
            .changeType: .string("route_direction"),
            .selectionType: .string(direction.rawValue)
        ]))
    }

    func applySmartGoalDefaultIfNeeded() {
        guard self.host.shouldApplySmartGoalDefault, !self.setup.didApplySmartGoalDefault else { return }
        self.setup.didApplySmartGoalDefault = true
        guard let sport = self.setup.selectedManualSport,
              self.launchPreferenceStore.preferredGoalMode(for: sport) == nil,
              self.setup.currentActivityGoal.isFreestyle,
              let preferredGoal = SmartGoalPreference.preferredFrequentCustomGoal(from: self.dependencies.activityStore.activities) else {
            return
        }
        self.applyGoal(preferredGoal, trackChange: false)
    }

    func applyLearnedGoalModeIfNeeded() {
        guard self.host.shouldApplySmartGoalDefault else { return }
        let sport = self.launchPreferenceStore.lastManualSport ?? self.setup.selectedManualSport ?? .run
        self.selectWorkoutChoice(.sport(sport), trackChange: false)
    }

    func recordStartedGoalMode() {
        guard let sport = self.setup.selectedManualSport, self.setup.selectedGoalMode.isLearnableManualMode else { return }
        let changes = self.launchPreferenceStore.recordStarted(
            sport: sport,
            mode: self.setup.selectedGoalMode,
            goal: self.setup.manualActivityGoal
        )

        if changes.didChangeSport {
            self.track(.init(.preferenceChanged, properties: [
                .changeType: .string("activity_sport_default"),
                .selectionType: .string(sport.rawValue)
            ]))
        }
        if changes.didChangeTarget {
            self.track(.init(.preferenceChanged, properties: [
                .changeType: .string("activity_target_default"),
                .selectionType: .string(self.setup.selectedGoalMode.rawValue)
            ]))
        }
        if changes.didLearnGoalMode {
            self.track(.init(.preferenceChanged, properties: [
                .changeType: .string("activity_goal_mode_default"),
                .selectionType: .string(self.setup.selectedGoalMode.rawValue)
            ]))
            self.showSetupToast(
                String(
                    format: String(localized: "record.goal.default_learned.format", defaultValue: "%@ is now your default"),
                    locale: .autoupdatingCurrent,
                    self.setup.selectedGoalMode.title
                )
            )
        }
    }

    var startSetupCardCornerRadius: CGFloat { 20 }
}
