import SwiftUI
import PhotosUI
import CoreLocation

/// Lifecycle adapters keep side effects out of the SwiftUI presentation host.
extension ActivityFlowCoordinator {
    func handleLiveSnapshot(_ snapshot: ActiveSessionSnapshot) {
        self.guide.ingest(snapshot)
        self.dependencies.liveShareStore.ingest(snapshot)
        if self.dependencies.liveShareStore.isSharing, self.guide.canPlayVoiceCheers {
            Task { @MainActor in
                guard let cheer = await self.dependencies.liveShareStore.takePendingVoiceCheer(),
                      let audio = cheer.audioData
                else { return }
                self.guide.playVoiceCheer(audio) {
                    Task { @MainActor in
                        guard await self.dependencies.liveShareStore.markVoiceCheerPlayed(cheer) else { return }
                        self.track(.init(.liveVoiceCheerPlayed, properties: [
                            .countBucket: .string(ProductAnalyticsBucket.count(1))
                        ]))
                    }
                }
            }
        }
        self.dependencies.liveGroupStore.ingest(snapshot)
        self.updateLiveActivity(
            snapshot: snapshot,
            state: self.recorder.state,
            intent: self.activeIntent ?? self.setup.plannedIntent
        )
        self.finishAtGoalIfNeeded(snapshot)
        self.trackGoalProgressIfNeeded(snapshot)
    }

    func handleRecorderState(_ state: RecordingState) {
        switch state {
        case .active:
            self.sessionController.beginRecording()
        case .paused:
            self.sessionController.pause()
        case .idle:
            if self.review.pendingActivity != nil {
                self.sessionController.beginReview()
            } else if !self.isCountingDown {
                switch self.sessionController.phase {
                case .review, .saving, .postSave:
                    break
                default:
                    self.sessionController.prepare(intent: self.setup.plannedIntent)
                }
            }
        }
        self.host.onSessionStateChange?(self.sessionController.phase.portalState)
        if self.dependencies.phoneWorkoutCoordinator.watchOwnsHealthKitPersistence {
            if self.previousRecorderState == .active, state == .paused {
                self.dependencies.phoneWorkoutCoordinator.requestPause(autoTriggered: self.recorder.autoPaused)
            } else if self.previousRecorderState == .paused, state == .active {
                self.dependencies.phoneWorkoutCoordinator.requestResume()
            }
        }
        self.guide.handleRecordingStateTransition(
            from: self.previousRecorderState,
            to: state,
            autoPaused: self.recorder.autoPaused,
            snapshot: self.recorder.liveSnapshot
        )
        self.trackRecordingStateTransition(to: state)
        self.workoutPresence.sync(with: state)
        if state == .idle { self.applyTrustedContactDefault() }
    }

    func handleWatchFinishRequest() {
        guard self.recorder.state != .idle, self.review.pendingActivity == nil else { return }
        self.finishRecording(recoveredAfterFinish: false, initiatedByWatch: true)
    }

    func handleWatchFinalMetrics(_ metrics: PlainstrideFinalWorkoutMetrics?) {
        guard let metrics, let current = self.review.pendingActivity else { return }
        self.review.pendingActivity = PendingFinishedActivity(
            id: current.id,
            summary: self.recorder.reconcilingFinalHeartRateMetrics(metrics, into: current.summary),
            photos: current.photos,
            reflection: current.reflection,
            recognitionPreviews: current.recognitionPreviews,
            guidanceReport: current.guidanceReport
        )
    }

    func handleAppearance() {
        self.dependencies.phoneWorkoutCoordinator.bind(recorder: self.recorder)
        self.restoreInterruptedPhotosIfNeeded()
        self.host.onPreActivityPhotoChange?(self.preActivityPhoto)
        self.restoreInterruptedSessionIfNeeded()
#if DEBUG
        self.configureRequestedGroupRecoveryTestIfNeeded()
        self.configureRequestedRunSimulationIfNeeded()
#endif
        switch self.recorder.state {
        case .active:
            self.sessionController.beginRecording()
        case .paused:
            self.sessionController.beginRecording()
            self.sessionController.pause()
        case .idle:
            if self.review.pendingActivity != nil { self.sessionController.beginReview() }
        }
        self.workoutPresence.sync(with: self.recorder.state)
        if self.recorder.state == .idle {
            self.applyTrustedContactDefault()
            // Warm the GPS fix and refresh the cached authorization
            // snapshot for the next outdoor start.
            self.recorder.locationManager.requestCurrentLocation()
            self.recorder.locationManager.refreshForForeground()
            if self.host.startImmediately {
                // Event launches use the same location gate as every other
                // start surface. This keeps permission/GPS prompts before
                // the countdown instead of interrupting it afterward.
                self.ensureLocationReadyThenStart()
            }
        } else if self.dependencies.phoneWorkoutCoordinator.origin == .appleWatch {
            self.adoptWatchInitiatedSessionIfNeeded()
        }
    }

    func prepareServices() async {
        if self.dependencies.safetyContactStore.sharesWithTrustedContactsByDefault, !self.dependencies.socialStore.hasLoadedConnections {
            await self.dependencies.socialStore.refreshConnections()
            self.applyTrustedContactDefault()
        }
        await self.dependencies.musicStore.refresh()
        await self.dependencies.musicStore.loadQuickPicks()
        await self.dependencies.guideCatalog.refreshServerCatalog()
        self.guide.setSpeechEnabled(self.voiceGuideSpeechEnabled)
        self.setup.applyWorkoutMusicSuggestion()
        self.guide.speechEventHandler = { [musicStore = self.dependencies.musicStore] event in
            Task { await musicStore.handleGuideSpeechEvent(event) }
        }
        self.guide.guidanceEventHandler = { [weak self] event in
            self?.trackGuidanceEvent(event)
        }
    }

    func prepareCoaching() {
        LiveCoachPreparationStore.shared.eventHandler = { [weak self] source, result in
            self?.track(.init(.liveGuidancePreparationResult, properties: [.sourceType: .string(source), .result: .string(result)]))
        }
        if let request = self.coachingPreparationRequest {
            LiveCoachPreparationStore.shared.prepare(request, contextVersion: self.dependencies.personalizationStore.snapshot.modelVersion)
        }
    }

    func handleScenePhase(_ newPhase: ScenePhase) {
        if newPhase == .active {
            self.dependencies.guideCatalog.refreshInstalledVoices()
            self.workoutPresence.sync(with: self.recorder.state)
            self.refreshLocationForForeground()
            Task { await ActivityEventParticipationSync.shared.flush() }
            if self.recorder.recoveredSession, self.recorder.state != .idle,
               self.dependencies.liveGroupStore.activeSession == nil, let sessionID = self.recorder.recordingLiveGroupSessionID {
                Task {
                    await self.dependencies.liveGroupStore.restoreSession(
                        sessionID: sessionID, intent: self.activeIntent, snapshot: self.recorder.liveSnapshot
                    )
                }
            }
        }
        guard newPhase == .active, self.recorder.state == .active else { return }
        Task { await self.dependencies.musicStore.retryPendingWorkoutPlaybackIfNeeded() }
    }

    func handleLivePageChange(_ newPage: SessionPage) {
        guard self.showCamera else { return }
        self.preferredSessionPageRawValue = newPage.rawValue
        self.track(.init(.liveWorkoutPageSelected, properties: [
            .selectionType: .string(newPage.rawValue),
            .sourceType: .string("page_selection")
        ]))
    }

    func handlePlannedIntentChange(_ intent: SessionIntent?) {
        self.setup.applyWorkoutMusicSuggestion()
        self.launchCoordinator.prepare(intent: intent)
        self.sessionController.prepare(intent: intent)
    }

    func handleMusicConnectionChange(from oldState: MusicConnectionState, to newState: MusicConnectionState) {
        guard oldState == .connecting, newState != .connecting else { return }
        self.track(.init(.musicAuthorizationCompleted, properties: [
            .result: .string(newState == .connected ? "granted" : "not_granted")
        ]))
    }

    func handleLocationAuthorization(_ status: CLAuthorizationStatus) {
        let granted = status == .authorizedAlways || status == .authorizedWhenInUse
        if self.recorder.state != .idle, granted != self.isLocationPermissionGranted, !self.setup.isIndoorSession {
            self.track(.init(.activityLocationPermissionChanged, properties: [
                .result: .string(granted ? "restored" : "unavailable")
            ]))
        }
        self.isLocationPermissionGranted = granted
        if self.isLocationPermissionGranted, self.isLocationPermissionModalPresented {
            self.isLocationPermissionModalPresented = false
        }
        self.retryBlockedStartIfNeeded()
    }

    func importPreActivityPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)
            else { return }
            await MainActor.run {
                self.replacePreActivityPhoto(with: image)
                self.setup.selectedPreActivityPhotoItem = nil
            }
        }
    }

    func selectCuratedWorkout(_ workout: StandaloneWorkout) {
        let selectedRoute = self.setup.plannedIntent?.preparedRoute
        self.setup.curatedWorkoutIntent = workout.intent
        if let selectedRoute {
            self.setup.intentBeforeSelectedRoute = workout.intent
            self.setup.plannedIntent = self.setup.routeIntent(selectedRoute, appliedTo: workout.intent)
        } else {
            self.setup.plannedIntent = workout.intent
            self.setup.intentBeforeSelectedRoute = nil
            self.setup.selectedRouteDistanceMeters = nil
        }
        self.setup.selectedWorkoutChoice = .sport(workout.sport)
        self.setup.selectedGoalMode = .curated
        self.setup.showsCuratedWorkouts = false
        self.track(.init(.activityConfigurationChanged, properties: [
            .changeType: .string("curated_workout"),
            .selectionType: .string(workout.sport.rawValue),
        ]))
    }

    func joinGroupFromInvite() {
        let invite = self.setup.groupInviteText
        self.setup.groupInviteText = ""
        self.track(.init(.groupRunJoinAttempted))
        Task {
            await self.dependencies.liveGroupStore.joinGroup(invite: invite)
            if self.dependencies.liveGroupStore.isSharing {
                self.track(.init(.groupRunJoined, properties: [
                    .participantCountBucket: .string(ProductAnalyticsBucket.count(self.dependencies.liveGroupStore.participants.count))
                ]))
            }
        }
    }
}
