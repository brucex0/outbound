import SwiftUI
import PhotosUI
import CoreLocation
import MapKit

extension ActivityFlowCoordinator {
    var effectiveCoachingProfile: GuideProfile? {
        self.dependencies.guideStore.coachingProfile(activities: self.dependencies.activityStore.activities, persona: self.dependencies.guideCatalog.selectedPersona)
    }

    var coachingPreparationKey: Int? {
        guard self.host.isVisible, self.recorder.state == .idle, self.voiceGuideSpeechEnabled,
              self.setup.plannedIntent?.sport == .run, self.dependencies.guideCatalog.selectedPersona.coachingContract != .quiet else { return nil }
        // Hash selection state here; build route summaries only when the task
        // changes, rather than calculating route distances on every view render.
        var key = Hasher()
        key.combine(self.setup.plannedIntent)
        key.combine(AuthStore.currentUserId)
        key.combine(AppLanguage.currentIdentifier)
        key.combine(self.dependencies.guideCatalog.selection.coachPersonaId)
        key.combine(self.dependencies.guideCatalog.selection.voiceProfileId)
        key.combine(self.dependencies.guideCatalog.selection.coachingContract.rawValue)
        key.combine(self.dependencies.measurementPreferences.unitSystem.rawValue)
        let coachingProfile = self.effectiveCoachingProfile
        key.combine(coachingProfile?.version)
        key.combine(coachingProfile?.athlete.preferredPaceSecs)
        key.combine(self.dependencies.personalizationStore.snapshot.modelVersion)
        key.combine(self.dependencies.weatherStore.snapshot?.fetchedAt)
        key.combine(self.setup.isIndoorSession)
        return key.finalize()
    }

    var coachingPreparationRequest: CreateLiveCoachSessionRequest? {
        guard self.host.isVisible, self.recorder.state == .idle, self.voiceGuideSpeechEnabled,
              self.setup.plannedIntent?.sport == .run, self.dependencies.guideCatalog.selectedPersona.coachingContract != .quiet else { return nil }
        return LiveCoachSessionController.makeRequest(
            profile: self.effectiveCoachingProfile, persona: self.dependencies.guideCatalog.selectedPersona, intent: self.setup.plannedIntent, companionBrief: nil,
            unitSystem: self.dependencies.measurementPreferences.unitSystem, weatherSnapshot: self.dependencies.weatherStore.snapshot, isIndoor: self.setup.isIndoorSession
        )
    }

    var showsLiveLocationPermissionWarning: Bool {
        let type = self.activeIntent?.resolvedActivityType ?? self.recorder.activityType
        return self.recorder.state != .idle && !self.setup.isIndoorSession && !self.isLocationPermissionGranted
            && type != .strengthTraining && type != .mobility
    }

    var showsEmbeddedLiveSurface: Bool {
        guard self.host.isEmbeddedInToday, self.host.isVisible else { return false }
        switch self.sessionController.phase {
        case .preflighting, .countdown, .recording, .review, .saving, .postSave:
            return true
        case .setup:
            return false
        }
    }

    var activityCompletionAnimation: Animation {
        .easeOut(duration: self.reduceMotion ? 0.16 : 0.3)
    }

    var isSharingRecordingEventLiveMap: Bool {
        self.dependencies.liveGroupStore.isSharing
            && self.dependencies.liveGroupStore.activeSession?.activityEventId == (self.activeIntent ?? self.setup.plannedIntent)?.activityEvent?.id
    }

    func toggleRecordingEventLiveMap() {
        if self.isSharingRecordingEventLiveMap {
            self.dependencies.liveGroupStore.stopFromManagementControl()
        } else if let event = (self.activeIntent ?? self.setup.plannedIntent)?.activityEvent {
            Task {
                self.track(.init(.groupRunJoinAttempted))
                await self.dependencies.liveGroupStore.joinActivityEvent(event.id)
                if self.isSharingRecordingEventLiveMap {
                    self.track(.init(.groupRunJoined, properties: [
                        .participantCountBucket: .string(ProductAnalyticsBucket.count(self.dependencies.liveGroupStore.participants.count))
                    ]))
                }
            }
        }
    }

    func startRecording() {
        guard self.recorder.state == .idle, !self.isCountingDown else { return }
        guard !self.isStartingActivity else { return }
#if DEBUG
        if self.isRunSimulationEnabled {
            self.beginStartRecording()
            return
        }
#endif
        let type = self.setup.plannedIntent?.resolvedActivityType ?? .running
        if type == .running || type == .walking {
            let requested = self.recorder.locationManager.requestStepMotionPermissionIfNeeded { result in
                self.track(.init(.motionAuthorizationCompleted, properties: [.result: .string(result.rawValue)]))
                self.isStartingActivity = false
                guard self.host.isVisible else { return }
                self.beginStartRecording()
            }
            if requested {
                self.isStartingActivity = true
                self.track(.init(.motionAuthorizationRequested))
                return
            }
        }
        self.beginStartRecording()
    }

    func ensureLocationReadyThenStart(isUserInitiated: Bool = true) {
        guard self.recorder.state == .idle, !self.isCountingDown else { return }
#if DEBUG
        if self.isRunSimulationEnabled {
            self.startRecording()
            return
        }
#endif
        let locationManager = self.recorder.locationManager
        switch ActivityLaunchPreflight.decision(
            isIndoor: self.setup.isIndoorSession,
            permissionGranted: locationManager.isLocationPermissionGranted,
            hasRecentValidLocation: locationManager.hasRecentValidLocation
        ) {
        case .requestPermission:
            self.handleMissingLocationPermissionForStart(isUserInitiated: isUserInitiated)
        case .startImmediately:
            self.isWaitingForLocation = false
            self.startRecording()
        case .waitForLocation:
            self.beginLocationWait()
        }
    }

    func beginLocationWait() {
        let isFirstEntry = !self.isWaitingForLocation
        self.isWaitingForLocation = true
        self.launchCoordinator.beginPreflight()
        self.sessionController.beginPreflight()
        // Move to the activity map/camera surface as soon as the runner starts
        // waiting. Keeping the setup page visible here makes a planned start
        // look like it failed while GPS is acquiring a fix.
        self.presentLiveSurface()
        self.recorder.locationManager.prepareForRecording(
            activityType: self.activeIntent?.resolvedActivityType ?? self.setup.plannedIntent?.resolvedActivityType ?? .running
        )
        guard isFirstEntry else { return }
        self.showSetupToast(String(
            localized: "record.location.waiting",
            defaultValue: "Waiting for GPS signal…"
        ))
    }

    func cancelLocationWait() {
        guard self.isWaitingForLocation else { return }
        self.isWaitingForLocation = false
        self.launchCoordinator.cancel()
        if self.recorder.state == .idle {
            self.recorder.locationManager.cancelPreparation()
        }
    }

    func handleMissingLocationPermissionForStart(isUserInitiated: Bool) {
        guard isUserInitiated else { return }
        self.cancelLocationWait()
        self.isWaitingForLocation = true
        if let onLocationPermissionRequired = self.host.onLocationPermissionRequired {
            onLocationPermissionRequired()
        } else {
            self.isLocationPermissionModalPresented = true
        }
    }

    func enableLocationFromPermissionModal() {
        self.isLocationPermissionModalPresented = false
        let locationManager = self.recorder.locationManager
        if locationManager.authorizationStatus == .notDetermined {
            // The system prompt is the only surface iOS offers to grant
            // access directly.
            self.isWaitingForLocation = true
            locationManager.requestPermission()
        } else {
            self.openSystemLocationSettings()
        }
    }

    func openSystemLocationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func retryBlockedStartIfNeeded() {
        guard self.isWaitingForLocation, self.recorder.state == .idle else { return }
        self.isWaitingForLocation = false
        if self.activeIntent != nil {
            // A countdown completed while waiting on location; finish that
            // start directly instead of replaying the countdown.
            self.completeStartCountdown()
        } else {
            self.ensureLocationReadyThenStart(isUserInitiated: false)
        }
    }

    func refreshLocationForForeground() {
        self.recorder.locationManager.refreshForForeground()
        guard self.recorder.state == .idle else { return }
        self.recorder.locationManager.requestForegroundLocationRefresh()
    }

    func applyTrustedContactDefault() {
        guard self.recorder.state == .idle,
              self.dependencies.safetyContactStore.sharesWithTrustedContactsByDefault
        else { return }
        let trusted = self.dependencies.socialStore.connections.filter {
            $0.status == "accepted" && self.dependencies.safetyContactStore.isTrusted($0.person.id)
        }
        self.dependencies.liveShareStore.applyDefaultConnections(trusted.sorted(by: SocialConnectionDTO.previewOrder))
    }

    func beginStartRecording() {
        guard self.recorder.state == .idle, !self.isCountingDown, !self.isStartingActivity else { return }
        self.guide.setSpeechEnabled(self.voiceGuideSpeechEnabled)
        self.isStartingActivity = true
        let intent = self.setup.plannedIntent
        if let activityEventID = intent?.activityEvent?.id {
            self.dependencies.socialStore.prepareToRecord(activityEventID: activityEventID)
        }
        self.beginRecordingAfterLiveShareSetup()
        self.isStartingActivity = false

        guard !self.dependencies.connectivityStore.isOffline else { return }
        Task { @MainActor in
            async let brief = try? APIClient.shared.fetchCompanionSessionBrief(workoutID: intent?.id)
            async let liveShare: Void = self.dependencies.liveShareStore.beginIfArmed(intent: intent)
            if let companionBrief = await brief {
                self.guide.updateCompanionBrief(companionBrief)
            }
            await liveShare
        }
    }

    func restoreInterruptedSessionIfNeeded() {
        guard self.recorder.recoveredSession, !self.didRestoreSession else { return }
        self.didRestoreSession = true
        ActivityDiagnosticLog.notice(
            .recovery,
            "Recovery presentation requested stage=\(self.recorder.recoveredAwaitingSave ? "awaiting_save" : "recording") route_selected=\(self.recorder.recoveredRouteGuidance != nil)"
        )
        if let recovered = self.recorder.recoveredRouteGuidance {
            let route = recovered.route
            let recoveredActivityType = route.activityType ?? self.recorder.recoveredActivityType
            let sport = SportType(activityType: recoveredActivityType)
            self.setup.plannedIntent = SessionIntent(
                id: "route-\(route.id)",
                sport: sport,
                title: route.name,
                detail: String(localized: "route.guidance.setup.detail", defaultValue: "Follow the selected route with on-device guidance"),
                guideLine: String(localized: "route.guidance.setup.companion", defaultValue: "Keep the route visible and follow it at your own pace."),
                startLabel: String(localized: "route.guidance.resume", defaultValue: "Resume Route Guidance"),
                routeName: route.name,
                preparedRoute: route,
                activityTypeOverride: recoveredActivityType,
                activityEvent: self.recorder.recordingActivityEvent
            )
            self.setup.selectedRouteDistanceMeters = Self.calculatePreparedRouteDistance(route)
        } else if let recoveredActivityType = self.recorder.recoveredActivityType,
                  recoveredActivityType != .running || self.recorder.recordingActivityEvent != nil {
            let sport = SportType(activityType: recoveredActivityType)
            self.setup.plannedIntent = SessionIntent(
                id: "recovered-\(sport.rawValue)",
                sport: sport,
                title: self.recorder.recordingActivityEvent?.title ?? String(format: String(localized: "activity.recovered.title.format", defaultValue: "Recovered %@"), locale: .autoupdatingCurrent, sport.displayName.lowercased()),
                detail: String(localized: "activity.recovered.detail", defaultValue: "Paused activity recovered on this device"),
                guideLine: String(localized: "activity.recovered.companion", defaultValue: "Resume when you are ready."),
                startLabel: String(localized: "common.resume", defaultValue: "Resume"),
                activityTypeOverride: recoveredActivityType,
                activityEvent: self.recorder.recordingActivityEvent
            )
        }
        self.activeIntent = self.setup.plannedIntent
        if let eventID = self.recorder.recordingActivityEvent?.id {
            self.dependencies.socialStore.prepareToRecord(activityEventID: eventID)
            self.trackFeatureExposure("group_activity_recovery")
        }
        if !self.recorder.recoveredAwaitingSave, let sessionID = self.recorder.recordingLiveGroupSessionID {
#if DEBUG
            if sessionID == "debug-test-group-run" {
                self.trackFeatureExposure("test_group_recovery")
            }
#endif
            Task {
                await self.dependencies.liveGroupStore.restoreSession(
                    sessionID: sessionID, intent: self.activeIntent, snapshot: self.recorder.liveSnapshot
                )
            }
        }
        if self.recorder.recoveredAwaitingSave {
            self.didTrackRecoveryPresentation = true
            self.track(.init(.activityRecoveryPresentation, properties: [
                .result: .string("success"),
                .sourceType: .string("awaiting_save"),
                .countBucket: .string(ProductAnalyticsBucket.count(1))
            ]))
            ActivityDiagnosticLog.notice(.recovery, "Recovery presentation rendered stage=awaiting_save")
            self.finishRecording(recoveredAfterFinish: true)
            return
        }
        self.live.activePage = self.preferredSessionPage
        self.live.isLiveWorkoutPanelExpanded = false
        self.presentLiveSurface()
        ActivityDiagnosticLog.notice(.recovery, "Recovery presentation rendered stage=recording")
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
        self.trackFeatureExposure("live_guidance")
        if let route = self.activeIntent?.preparedRoute,
           let snapshot = self.recorder.routeGuidanceSnapshot {
            self.track(.init(.routeGuidanceRecovered, properties: [
                .sourceType: .string(route.source.rawValue),
                .direction: .string(route.direction.rawValue),
                .progressPercent: .integer(self.coarseRouteProgressPercent(snapshot.progressFraction))
            ]))
        }
    }

    func seedLiveRunForUITestIfRequested() {
#if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-OutboundUITestLive10K"),
              self.host.isVisible,
              !self.didSeedLiveRunForUITest
        else { return }

#if targetEnvironment(simulator)
        guard WatchWorkoutFlowUITestControls.claimRecordingSeed() else { return }
#endif
        self.didSeedLiveRunForUITest = true
        let intent = SessionIntent(
            id: "ui-test-live-10k",
            sport: .run,
            title: String(localized: "session.seed.live_10k.title", defaultValue: "Morning 10K"),
            detail: String(localized: "session.seed.live_10k.detail", defaultValue: "Run • 10 km target"),
            guideLine: String(localized: "session.seed.live_10k.guide", defaultValue: "Stay relaxed now, then build through the final 2 km."),
            startLabel: "Start now",
            targetDistanceMeters: 10_000
        )
        self.setup.plannedIntent = intent
        self.activeIntent = intent
        self.setup.selectedRouteDistanceMeters = nil
        self.live.activePage = .map
        self.live.isLiveWorkoutPanelExpanded = false
        self.live.capturedPhotos = []
        self.review.pendingActivity = nil
        self.presentLiveSurface()
        self.recorder.seedLiveRunForUITest()
#if targetEnvironment(simulator)
        self.dependencies.phoneWorkoutCoordinator.configureWatchFlowUITest(recorder: self.recorder)
#endif
#endif
    }

#if DEBUG
    func configureRequestedGroupRecoveryTestIfNeeded() {
        guard self.host.isVisible, self.recorder.state == .idle, !self.didConfigureRequestedGroupRecoveryTest,
              ProcessInfo.processInfo.arguments.contains("-OutboundGroupRecoveryUITestSetup") else { return }
        self.didConfigureRequestedGroupRecoveryTest = true
        self.setup.isIndoorSession = true
        Task {
            await self.dependencies.liveGroupStore.joinActivityEvent("ui-recovery-event")
            self.setup.plannedIntent = SessionIntent(
                id: "ui-recovery-event", sport: .run, title: "Recovery group run",
                detail: "Synthetic UI recovery fixture", guideLine: "", startLabel: "Start recovery run",
                activityEvent: ActivityEventLaunchContext(
                    id: "ui-recovery-event", title: "Recovery group run", role: "organizer",
                    attendanceMode: "remote", organizerName: "Fixture runner"
                )
            )
        }
    }
#endif

#if DEBUG
    func configureRequestedRunSimulationIfNeeded() {
        guard self.host.isVisible,
              !self.didConfigureRequestedRunSimulation,
              !ProcessInfo.processInfo.arguments.contains("-OutboundUITestLive10K"),
              ProcessInfo.processInfo.arguments.contains(HarvestHalfMarathonSimulation.launchArgument)
        else { return }

        self.didConfigureRequestedRunSimulation = true
        self.configureHarvestRunSimulation(enabled: true, tracksChange: false)
    }
#endif

#if DEBUG
    func configureHarvestRunSimulation(
        enabled: Bool,
        tracksChange: Bool = true
    ) {
        guard self.recorder.state == .idle else { return }
        self.routeTestMode = enabled
        self.isRunSimulationEnabled = enabled

        if enabled {
            self.setup.selectedWorkoutChoice = .sport(.run)
            self.setup.selectedGoalMode = .freestyle
            self.setup.manualActivityGoal = .freestyle
            self.setup.plannedWorkoutIntent = nil
            self.setup.curatedWorkoutIntent = nil
            self.setup.plannedIntent = .freestyleRun
            self.setup.intentBeforeSelectedRoute = nil
            self.setup.isIndoorSession = false
            self.applyRoute(HarvestHalfMarathonSimulation.route)
            self.isRunSimulationEnabled = true
        } else if self.setup.plannedIntent?.preparedRoute?.id == HarvestHalfMarathonSimulation.routeID {
            self.applyRoute(nil)
        }

        guard tracksChange else { return }
        self.track(.init(.activityConfigurationChanged, properties: [
            .changeType: .string("run_simulation"),
            .selectionType: .string(enabled ? "enabled" : "disabled")
        ]))
    }
#endif

    func presentLiveSurface() {
        // Tell Today to release its setup map before the workout map appears.
        self.host.onLiveSurfaceVisibilityChange?(true)
        self.showCamera = true
    }

    func beginRecordingAfterLiveShareSetup(companionBrief: CompanionSessionBriefDTO? = nil) {
        ActiveSessionPhotoJournal.replace(with: self.live.capturedPhotos)
        self.review.pendingActivity = nil
        self.live.activePage = self.preferredSessionPage
        self.live.isLiveWorkoutPanelExpanded = false
        self.activeIntent = self.setup.plannedIntent
#if DEBUG
        if !self.isRunSimulationEnabled {
            self.recorder.locationManager.prepareForRecording(
                activityType: self.activeIntent?.resolvedActivityType ?? .running
            )
        }
#else
        self.recorder.locationManager.prepareForRecording(
            activityType: self.activeIntent?.resolvedActivityType ?? .running
        )
#endif
        self.guide.setSpeechEnabled(self.voiceGuideSpeechEnabled)
        self.guide.activate(
            with: self.effectiveCoachingProfile,
            persona: self.dependencies.guideCatalog.selectedPersona,
            sessionIntent: self.activeIntent,
            companionBrief: companionBrief,
            unitSystem: self.dependencies.measurementPreferences.unitSystem,
            weatherSnapshot: self.dependencies.weatherStore.snapshot,
            isIndoor: self.setup.isIndoorSession,
            challenge: self.setup.selectedGuidanceChallenge,
            suppressedMomentTypes: self.dependencies.guideCatalog.suppressedMomentTypes(
                for: self.dependencies.guideCatalog.selection.coachingContract
            )
        )
        self.trackFeatureExposure("live_guidance")
        self.presentLiveSurface()
#if DEBUG
        if !ProcessInfo.processInfo.arguments.contains("-OutboundDemoCapture") {
            self.dependencies.phoneWorkoutCoordinator.preparePhoneFirst(
                activityType: self.activeIntent?.resolvedActivityType ?? .running,
                isIndoor: self.setup.isIndoorSession,
                companionType: self.isCompanionContextEligible ? self.setup.companionType : nil,
                startWatchApp: self.startWatchApp
            )
        }
#else
        self.dependencies.phoneWorkoutCoordinator.preparePhoneFirst(
            activityType: self.activeIntent?.resolvedActivityType ?? .running,
            isIndoor: self.setup.isIndoorSession,
            companionType: self.isCompanionContextEligible ? self.setup.companionType : nil,
            startWatchApp: self.startWatchApp
        )
#endif
        self.beginStartCountdown()
    }

    func beginStartCountdown() {
        self.countdown.countdownTask?.cancel()
        self.launchCoordinator.beginCountdown()
        self.sessionController.beginCountdown()
        guard !ActivityLaunchPreflight.skipsCountdown(for: self.activeIntent?.sport) else {
            self.completeStartCountdown()
            return
        }
        self.guide.announceStartCountdown()
        self.countdown.begin(
            reduceMotion: { [weak self] in self?.reduceMotion ?? false },
            onStep: self.announceCountdownFeedback,
            onComplete: self.completeStartCountdown
        )
    }

    func announceCountdownFeedback(_ step: ActivityStartCountdownStep) {
        #if os(iOS)
        UIAccessibility.post(notification: .announcement, argument: step.accessibilityText)
        switch step {
        case .go:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .three, .two, .one:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        #endif
    }

    func completeStartCountdown() {
        guard self.recorder.state == .idle else {
            self.countdown.countdownStep = nil
            self.countdown.countdownTask = nil
            return
        }

        self.countdown.countdownStep = nil
        self.countdown.countdownTask = nil
#if DEBUG
        let isSimulatedStart = self.isRunSimulationEnabled
#else
        let isSimulatedStart = false
#endif
        if !self.setup.isIndoorSession,
           !isSimulatedStart,
           !self.recorder.locationManager.hasRecentValidLocation {
            // Never begin recording without valid location data: park the
            // start and release it automatically once a fix arrives.
            self.dependencies.phoneWorkoutCoordinator.cancelPreparation()
            if self.recorder.locationManager.isLocationPermissionGranted {
                self.beginLocationWait()
            } else {
                // Permission vanished mid-countdown: park behind the explicit
                // permission modal instead of a doomed GPS wait.
                self.handleMissingLocationPermissionForStart(isUserInitiated: true)
            }
            return
        }
        self.isWaitingForLocation = false
        let routeGuidance = self.activeIntent?.preparedRoute.map {
            ActiveRouteGuidanceJournal(route: $0, recoverySeed: nil)
        }
        self.startRecorder(routeGuidance: routeGuidance)
        self.sessionController.beginRecording()
        if let eventID = self.activeIntent?.activityEvent?.id {
            ActivityEventParticipationSync.shared.enqueueStart(eventID: eventID)
            Task { await ActivityEventParticipationSync.shared.flush() }
        }

        self.recordStartedGoalMode()
        if let route = self.activeIntent?.preparedRoute {
            self.track(.init(.routeNavigationStarted, properties: [
                .sourceType: .string(route.source.rawValue),
                .distanceBucket: .string(ProductAnalyticsBucket.distance(meters: self.preparedRouteDistance(route))),
                .direction: .string(route.direction.rawValue)
            ]))
        }
        self.reachedGoalThresholds = []
        self.activityStartedWithGroupRun = self.dependencies.liveGroupStore.isSharing || self.activeIntent?.activityEvent != nil
        self.track(.init(.activityStarted, properties: self.activityConfigurationProperties))
        if self.activeIntent?.startedFromWorkoutReminder == true {
            self.track(.init(.workoutStartedFromReminder, properties: [
                .sourceType: .string("local_notification")
            ]))
        }
        self.updateLiveActivity(
            snapshot: self.recorder.liveSnapshot,
            state: self.recorder.state,
            intent: self.activeIntent
        )
        Task {
            await self.dependencies.musicStore.beginWorkoutPlaybackIfNeeded()
        }
    }

    func startRecorder(routeGuidance: ActiveRouteGuidanceJournal?) {
#if DEBUG
        if self.isRunSimulationEnabled,
           let routeGuidance {
            self.recorder.startRunSimulation(
                activityType: self.activeIntent?.resolvedActivityType ?? .running,
                routeGuidance: routeGuidance,
                route: routeGuidance.route,
                activityEvent: self.activeIntent?.activityEvent,
                liveGroupSessionID: self.dependencies.liveGroupStore.isSharing ? self.dependencies.liveGroupStore.activeSession?.id : nil
            )
            self.track(.init(.activitySimulationStarted, properties: [
                .sourceType: .string("selected_route"),
                .distanceBucket: .string(ProductAnalyticsBucket.distance(
                    meters: self.recorder.runSimulationState?.routeDistanceMeters ?? 0
                )),
                .selectionType: .string(self.recorder.runSimulationSpeedBucket)
            ]))
            return
        }
#endif
        self.recorder.start(
            activityType: self.activeIntent?.resolvedActivityType ?? .running,
            movingTimeDetectionEnabled: !self.setup.isIndoorSession,
            autoPauseEnabled: self.autoPauseEnabled(for: self.activeIntent?.resolvedActivityType ?? .running),
            routeGuidance: routeGuidance,
            canonicalStartDate: self.dependencies.phoneWorkoutCoordinator.canonicalStartDate,
            sessionMetadata: self.dependencies.phoneWorkoutCoordinator.recordingMetadata(),
            companionType: self.isCompanionContextEligible ? self.setup.companionType : nil,
            activityEvent: self.activeIntent?.activityEvent,
            liveGroupSessionID: self.dependencies.liveGroupStore.isSharing ? self.dependencies.liveGroupStore.activeSession?.id : nil
        )
        self.dependencies.phoneWorkoutCoordinator.markPhoneRecorderStarted()
    }

    func updateLiveActivity(
        snapshot: ActiveSessionSnapshot,
        state: RecordingState,
        intent: SessionIntent?
    ) {
        guard let result = self.liveActivityManager.update(
            snapshot: snapshot,
            state: state,
            intent: intent,
            unitSystem: self.dependencies.measurementPreferences.unitSystem
        ) else { return }

        self.track(.init(.liveActivityReconciled, properties: [
            .result: .string(result.rawValue)
        ]))
    }

    func cancelStartCountdown(returnToSetup: Bool) {
        guard self.isCountingDown else { return }
        self.countdown.countdownTask?.cancel()
        self.countdown.countdownTask = nil
        self.countdown.countdownStep = nil
        self.launchCoordinator.cancel()
        if self.recorder.state == .idle {
            self.recorder.locationManager.cancelPreparation()
            self.dependencies.phoneWorkoutCoordinator.cancelPreparation()
        }
        self.guide.deactivate()
        self.activeIntent = nil
        if returnToSetup {
            self.showCamera = false
        }
        // The companion choice belongs to the retained setup, not the canceled
        // countdown, so the next start keeps it when the sport stays eligible.
    }

    var isCountingDown: Bool {
        self.countdown.countdownStep != nil || self.countdown.countdownTask != nil
    }
}
