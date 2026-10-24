import SwiftUI
import PhotosUI
import CoreLocation
import MapKit

extension ActivityFlowView {
    var recordStateSurface: some View {
        Group {
            if host.isEmbeddedInToday {
                ZStack {
                    embeddedReadyView
                        .opacity(host.isVisible && !model.showsEmbeddedLiveSurface ? 1 : 0)
                        .allowsHitTesting(host.isVisible && !model.showsEmbeddedLiveSurface)

                    if model.showsEmbeddedLiveSurface {
                        activityFullscreenSurface
                            .zIndex(1)
                            .onAppear {
                                model.trackRecoveryPresentationIfNeeded(result: "success")
                            }
                    }
                }
            } else if model.showCamera || model.review.pendingActivity != nil || model.review.postSaveStretchContext != nil || model.review.postSaveCelebrationActivity != nil {
                activityFullscreenSurface
            } else {
                readyView
            }
        }
        .background { recordBackground }
#if DEBUG && targetEnvironment(simulator)
        .overlay(alignment: .top) {
            if host.isVisible, ProcessInfo.processInfo.arguments.contains("-OutboundUITestWatchScenario") {
                WatchWorkoutFlowUITestControls(coordinator: model.dependencies.phoneWorkoutCoordinator,
                    allowsControls: model.recorder.state != .idle, phase: String(describing: model.sessionController.phase))
            }
        }
#endif
        .onReceive(model.recorder.$liveSnapshot) { snapshot in
            model.handleLiveSnapshot(snapshot)
        }
        .onReceive(model.recorder.routeGuidanceEvents) { event in
            model.handleRouteGuidanceEvent(event)
        }
        .onReceive(model.recorder.$state) { state in
            model.handleRecorderState(state)
        }
        .onChange(of: model.dependencies.phoneWorkoutCoordinator.finishRequestToken) { _, _ in
            model.handleWatchFinishRequest()
        }
        .onChange(of: model.dependencies.phoneWorkoutCoordinator.finalMetrics) { _, metrics in
            model.handleWatchFinalMetrics(metrics)
        }
        .onChange(of: model.dependencies.phoneWorkoutCoordinator.toastMessage) { _, message in
            model.showSetupToast(message)
        }
        .onReceive(model.dependencies.socialStore.$connections) { _ in model.applyTrustedContactDefault() }
        .onReceive(model.recorder.$elapsedSeconds) { elapsedSeconds in
            host.onElapsedTimeChange?(elapsedSeconds)
        }
        .onChange(of: host.isVisible, initial: true) { wasVisible, isNowVisible in
            model.seedLiveRunForUITestIfRequested()
#if DEBUG
            model.configureRequestedRunSimulationIfNeeded()
#endif
            if wasVisible, !isNowVisible {
                model.dependencies.tooltipCoordinator.withdraw(.musicDiscovery)
                return
            }
            guard !wasVisible, isNowVisible else { return }
        }
        .onChange(of: host.startRequest) { _, _ in
            guard host.isEmbeddedInToday, host.isVisible, !model.showCamera else { return }
            model.ensureLocationReadyThenStart()
        }
        .onChange(of: host.preActivityPhotoRequest) { _, _ in
            model.handlePreActivityPhotoRequest()
        }
        .onChange(of: host.routeSelectionRequest) { _, _ in
            model.handleRouteSelectionRequest()
        }
        .onChange(of: host.routeRemovalRequest) { _, _ in
            model.handleRouteRemovalRequest()
        }
        .onChange(of: host.groupRunRequest) { _, _ in
            model.handleGroupRunRequest()
        }
        .onChange(of: model.setup.selectedGoalMode, initial: true) { _, mode in
            host.onGoalModeChange?(mode)
        }
        .onChange(of: model.setup.plannedIntent?.preparedRoute, initial: true) { _, route in
            host.onPreActivityRouteChange?(route)
        }
#if DEBUG
        .onChange(of: model.routeTestMode) { _, enabled in
            guard model.recorder.state == .idle else { return }
            model.isRunSimulationEnabled = enabled && model.setup.plannedIntent?.preparedRoute != nil
        }
        .onChange(of: model.setup.plannedIntent?.preparedRoute?.id, initial: true) { _, routeID in
            model.isRunSimulationEnabled = routeID != nil && model.routeTestMode
                && model.recorder.state == .idle
        }
#endif
        .onChange(of: model.showsEmbeddedLiveSurface, initial: true) { _, liveSurfaceVisible in
            host.onLiveSurfaceVisibilityChange?(liveSurfaceVisible)
        }
        .onAppear {
            model.handleAppearance()
        }
    }

    var recordLifecycleSurface: some View {
        recordStateSurface
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .task {
            await model.prepareServices()
        }
        .task(id: model.coachingPreparationKey) {
            model.prepareCoaching()
        }
        .onChange(of: scenePhase) { _, newPhase in
            model.handleScenePhase(newPhase)
        }
        .onChange(of: model.live.activePage) { _, newPage in
            model.handleLivePageChange(newPage)
        }
        .onChange(of: model.dependencies.liveGroupStore.activeSession?.id) { _, sessionID in
            model.recorder.updateLiveGroupRecoveryContext(sessionID: sessionID)
        }
        .onChange(of: model.setup.plannedIntent) { _, intent in
            model.handlePlannedIntentChange(intent)
        }
        .onChange(of: model.setup.setupSheet) { _, sheet in
            if sheet == .music {
                model.setup.prepareMusicPicker()
            } else if sheet == .goal {
                model.prepareGoalEditor()
            }
        }
        .onChange(of: model.dependencies.musicStore.snapshot.connectionState) { oldState, newState in
            model.handleMusicConnectionChange(from: oldState, to: newState)
        }
        .onChange(of: model.dependencies.musicStore.playback.isPlaying) { wasPlaying, isPlaying in
            guard !wasPlaying, isPlaying else { return }
            model.track(.init(.musicPlaybackStarted, properties: [.result: .string("success")]))
        }
        .onDisappear {
            model.cancelStartCountdown(returnToSetup: model.recorder.state == .idle)
            model.cancelLocationWait()
        }
    }

    var flowBody: some View {
        recordLifecycleSurface
        .onReceive(model.recorder.locationManager.$authorizationStatus) { status in
            model.handleLocationAuthorization(status)
        }
        .onReceive(model.recorder.locationManager.$location) { _ in
            model.retryBlockedStartIfNeeded()
        }
        .overlay(alignment: .topLeading) {
            if host.isVisible,
               model.review.pendingActivity == nil,
               let onCloseRequest = host.onCloseRequest,
               model.recorder.state == .idle,
               !host.isEmbeddedInToday {
                Button {
                    if model.isCountingDown {
                        model.cancelStartCountdown(returnToSetup: true)
                    } else if model.isWaitingForLocation {
                        model.cancelLocationWait()
                        onCloseRequest(false)
                    } else {
                        onCloseRequest(false)
                    }
                } label: {
                    Image(systemName: model.activityCloseSystemImage)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(model.showCamera ? .white : .primary)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding(.top, model.showCamera ? 18 : 14)
                .padding(.leading, 16)
                .accessibilityLabel(model.activityCloseAccessibilityLabel)
            }
        }
        .overlay(alignment: .topTrailing) {
            // The fullscreen surface owns its launcher; the outer overlay is setup-only.
            if host.isVisible, model.review.pendingActivity == nil, !model.showsEmbeddedLiveSurface, !model.showCamera,
               !host.isEmbeddedInToday {
                embeddedActivityAssistantButton
            }
        }
        .sheet(isPresented: binding(\.setup.showsRouteLibrary)) {
            NavigationStack {
                CommunityRouteLibraryView(selection: model.setup.plannedIntent?.preparedRoute) { route in
                    model.applyRoute(route)
                    model.setup.showsRouteLibrary = false
                }
            }
        }
        .sheet(item: binding(\.setup.setupSheet)) { sheet in
            setupSheetView(sheet)
                .presentationDetents(sheet == .goal ? [.height(310)] : [.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $model.isAssistantPresented) {
            AssistantView(
                screenName: model.showCamera ? "Live Recording" : "Record Setup",
                isRecordingActive: model.recorder.state == .active || model.recorder.state == .paused
            )
            .presentationDetents([.fraction(0.58), .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: binding(\.setup.isAddShoePresented)) {
            AddShoeView()
                .environmentObject(model.dependencies.gearStore)
                .environmentObject(model.dependencies.measurementPreferences)
        }
        .sheet(isPresented: binding(\.setup.showsTrustedContacts)) {
            CheerInvitationPickerView()
                .environmentObject(model.dependencies.socialStore)
                .environmentObject(model.dependencies.liveShareStore)
                .environmentObject(model.dependencies.safetyContactStore)
        }
        .sheet(isPresented: binding(\.setup.showsCuratedWorkouts)) {
            StandaloneWorkoutPickerView(sport: model.setup.selectedManualSport ?? .run) { workout in
                model.selectCuratedWorkout(workout)
            }
        }
        .sheet(isPresented: binding(\.setup.showsRacePlanner)) {
            RacePlannerView(
                activities: model.dependencies.activityStore.activities,
                unitSystem: model.dependencies.measurementPreferences.unitSystem,
                onUsePlan: model.applyRacePlan
            )
        }
        .fullScreenCover(isPresented: binding(\.setup.isPreActivityCameraPresented)) {
            PostRunCameraView { image in
                model.replacePreActivityPhoto(with: image)
            }
        }
        .sheet(isPresented: binding(\.setup.isPreActivityPhotoPreviewPresented)) {
            preActivityPhotoPreview
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: model.setup.selectedPreActivityPhotoItem) { _, item in
            model.importPreActivityPhoto(item)
        }
        .onChange(of: model.dependencies.liveShareStore.lastErrorMessage) { _, message in
            model.showSetupToast(message)
        }
        .onChange(of: model.dependencies.liveShareStore.lastSuccessMessage) { _, message in
            model.showSetupToast(message)
        }
        .onChange(of: model.dependencies.safetyContactStore.trustedConnectionIDs) { _, _ in model.applyTrustedContactDefault() }
        .onChange(of: model.dependencies.safetyContactStore.sharesWithTrustedContactsByDefault) { _, _ in model.applyTrustedContactDefault() }
        .onChange(of: model.dependencies.liveGroupStore.lastErrorMessage) { _, message in
            model.showSetupToast(message)
        }
        .onChange(of: model.dependencies.musicStore.lastErrorMessage) { _, message in
            guard let message else { return }
            model.track(.init(.musicOperationFailed, properties: [
                .errorCategory: .string(model.dependencies.musicStore.hasDeveloperTokenError ? "configuration" : "provider")
            ]))
            model.showSetupToast(message)
        }
        .overlay(alignment: .top) {
            if let setupToastMessage = model.setupToastMessage {
                Text(setupToastMessage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(radius: 8, y: 3)
                    .padding(.top, host.isEmbeddedInToday && model.recorder.state == .idle ? 112 : 62)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .alert(
            String(localized: "record.goal.calories.weight_prompt.title", defaultValue: "Add your weight"),
            isPresented: binding(\.setup.isCaloriesWeightPromptPresented)
        ) {
            TextField(model.setup.weightPromptFieldLabel, text: binding(\.setup.caloriesWeightText))
                .keyboardType(.decimalPad)

            Button(String(localized: "record.goal.calories.weight_prompt.continue", defaultValue: "Save and continue")) {
                model.savePromptedWeightAndContinue()
            }
            .disabled(model.setup.promptedWeightKilograms == nil)

            Button(String(localized: "common.cancel", defaultValue: "Cancel"), role: .cancel) {
                model.setup.pendingCaloriesWeightAction = nil
                model.trackCaloriesWeightPrompt(selection: "dismissed")
            }
        } message: {
            Text(String(
                localized: "record.goal.calories.weight_prompt.message",
                defaultValue: "Your weight is needed to estimate calories. It stays private and can be changed in your profile."
            ))
        }
        .alert(String(localized: "record.group.join.title", defaultValue: "Join group run"), isPresented: binding(\.setup.isGroupJoinAlertPresented)) {
            TextField(String(localized: "record.group.invite.placeholder", defaultValue: "Invite link or token"), text: binding(\.setup.groupInviteText))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button(String(localized: "record.group.join.action", defaultValue: "Join")) {
                model.joinGroupFromInvite()
            }

            Button(String(localized: "common.cancel", defaultValue: "Cancel"), role: .cancel) {
                model.setup.groupInviteText = ""
            }
        } message: {
            Text(String(localized: "record.group.join.help", defaultValue: "Paste the Plainstride group run invite from another runner."))
        }
        .alert(
            String(localized: "record.location.permission.title", defaultValue: "Enable location"),
            isPresented: $model.isLocationPermissionModalPresented
        ) {
            Button(String(localized: "record.location.permission.enable", defaultValue: "Enable location")) {
                model.enableLocationFromPermissionModal()
            }

            Button(String(localized: "record.location.permission.close", defaultValue: "Close"), role: .cancel) {
                model.cancelLocationWait()
            }
        } message: {
            Text(String(
                localized: "record.location.permission.message",
                defaultValue: "Outdoor activities need location to map your route and record pace. Grant access to start, or turn it on in Settings if it was denied before."
            ))
        }
    }

    @ViewBuilder
    var recordBackground: some View {
        if host.isEmbeddedInToday {
            Color.clear
        } else {
            Color(.systemBackground)
                .ignoresSafeArea()
        }
    }
}
