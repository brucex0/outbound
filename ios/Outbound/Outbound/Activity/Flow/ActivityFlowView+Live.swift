import SwiftUI
import PhotosUI
import CoreLocation
import MapKit

extension ActivityFlowView {
    var liveRecordingSurface: some View {
        ZStack {
            TabView(selection: binding(\.live.activePage)) {
                CameraHUDView(
                    recorder: model.recorder,
                    guide: model.guide,
                    musicStore: model.dependencies.musicStore,
                    intent: model.activeIntent ?? model.setup.plannedIntent,
                    locationPermissionUnavailable: model.showsLiveLocationPermissionWarning,
                    capturedPhotoCount: model.live.capturedPhotos.count,
                    lastCapturedPhoto: model.live.capturedPhotos.last?.0,
                    activePage: binding(\.live.activePage),
                    isWorkoutPanelExpanded: liveWorkoutPanelBinding(source: .camera),
                    onStart: { model.ensureLocationReadyThenStart() },
                    onPause: model.pauseRecording,
                    onResume: model.resumeRecording,
                    onFinish: model.finishRecording,
                    onCaptureStateChange: { model.live.isCapturingSessionPhoto = $0 }
                ) { image, meta in
                    let photo = (image, meta)
                    model.live.capturedPhotos.append(photo)
                    ActiveSessionPhotoJournal.append(photo)
                    model.track(.init(.photoCaptured, properties: [
                        .sourceType: .string("in_activity"),
                        .locationAttached: .boolean(meta.coordinate != nil)
                    ]))
                }
                .tag(SessionPage.camera)
                .ignoresSafeArea()

                LiveMapView(
                    recorder: model.recorder,
                    locationManager: model.recorder.locationManager,
                    guide: model.guide,
                    musicStore: model.dependencies.musicStore,
                    intent: model.activeIntent ?? model.setup.plannedIntent,
                    locationPermissionUnavailable: model.showsLiveLocationPermissionWarning,
                    capturedPhotoCount: model.live.capturedPhotos.count,
                    lastCapturedPhoto: model.live.capturedPhotos.last?.0,
                    activePage: binding(\.live.activePage),
                    isWorkoutPanelExpanded: liveWorkoutPanelBinding(source: .map),
                    onStart: { model.ensureLocationReadyThenStart() },
                    onPause: model.pauseRecording,
                    onResume: model.resumeRecording,
                    onFinish: model.finishRecording,
                    isFinishEnabled: !model.live.isCapturingSessionPhoto,
                    reservesAssistantSpace: host.isEmbeddedInToday
                )
                .tag(SessionPage.map)
                .ignoresSafeArea()
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            if let countdownStep = model.countdown.countdownStep {
                ActivityStartCountdownOverlay(
                    step: countdownStep,
                    reduceMotion: reduceMotion,
                    signalQuality: model.recorder.locationManager.signalQuality,
                    companionType: model.isCompanionContextEligible ? model.setup.companionType : nil
                )
                    .transition(.opacity)
            }

#if DEBUG
            if model.recorder.isSimulatingRun, model.countdown.countdownStep == nil, !model.live.isLiveWorkoutPanelExpanded {
                VStack {
                    RunSimulationControls(
                        recorder: model.recorder,
                        onControlUsed: model.trackRunSimulationControl
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, 62 + (model.live.liveGroupTopControlsHeight > 0 ? model.live.liveGroupTopControlsHeight + 8 : 0))

                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
#endif
        }
#if DEBUG
        .onPreferenceChange(LiveGroupTopControlsHeightPreferenceKey.self) { model.live.liveGroupTopControlsHeight = $0 }
#endif
        .environment(\.liveWorkoutOptionsContent, AnyView(liveWorkoutOptionsSection))
        .background(Color(.systemBackground))
        .toolbar(.hidden, for: .tabBar)
        .overlay(alignment: .topLeading) {
            if host.isEmbeddedInToday, model.isCountingDown {
                embeddedCountdownCancelButton
            }
        }
        .overlay(alignment: .topTrailing) {
            if host.isVisible, !model.live.isLiveWorkoutPanelExpanded {
                embeddedActivityAssistantButton
            }
        }
        .overlay(alignment: .top) {
            if model.countdown.countdownStep == nil, model.live.activePage == .camera,
               let event = (model.activeIntent ?? model.setup.plannedIntent)?.activityEvent {
                GroupActivityPresenceView(
                    eventID: event.id, title: event.title,
                    isSharingLiveMap: model.isSharingRecordingEventLiveMap,
                    isLiveMapBusy: model.dependencies.liveGroupStore.isJoining || (model.dependencies.liveGroupStore.isSharing && !model.isSharingRecordingEventLiveMap),
                    onToggleLiveMap: model.toggleRecordingEventLiveMap
                )
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 16)
                    .padding(.top, 62)
                    .opacity(model.live.isLiveWorkoutPanelExpanded || model.dependencies.liveShareStore.mostRecentlyHeardCheer != nil ? 0 : 1)
                    .allowsHitTesting(!model.live.isLiveWorkoutPanelExpanded && model.dependencies.liveShareStore.mostRecentlyHeardCheer == nil)
                    .accessibilityHidden(model.live.isLiveWorkoutPanelExpanded || model.dependencies.liveShareStore.mostRecentlyHeardCheer != nil)
            }
        }
        .overlay(alignment: .top) {
            if model.countdown.countdownStep == nil, let cheer = model.dependencies.liveShareStore.mostRecentlyHeardCheer {
                HeardVoiceCheerBanner(
                    senderDisplayName: cheer.senderDisplayName,
                    onAcknowledge: {
                        Task { @MainActor in
                            let acknowledged = await model.dependencies.liveShareStore.acknowledgeMostRecentlyHeardCheer()
                            model.track(.init(.liveVoiceCheerAcknowledged, properties: [
                                .result: .string(acknowledged ? "success" : "failure")
                            ]))
                        }
                    },
                    onDismiss: model.dependencies.liveShareStore.dismissMostRecentlyHeardCheer
                )
                .padding(.horizontal, 16)
                .padding(.top, 54)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    var liveWorkoutOptionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "session.options.title", defaultValue: "Workout options"))
                .font(.headline)
            Toggle(String(localized: "record.setup.voice_guide", defaultValue: "Voice Guide"), isOn: Binding(
                get: { model.voiceGuideSpeechEnabled },
                set: { enabled in
                    guard !enabled || !model.isVoiceGuideExplicitlyUnavailable else { return }
                    model.recorder.updateLiveWorkoutOptions(voice: enabled)
                    model.guide.setSpeechEnabled(model.voiceGuideSpeechEnabled)
                    model.trackLiveOption("voice_guide", enabled: enabled)
                }
            ))
            .frame(minHeight: 44)
            .accessibilityIdentifier("LiveVoiceGuide")
            .disabled(model.isVoiceGuideExplicitlyUnavailable)
            Toggle(String(localized: "session.options.auto_pause", defaultValue: "Auto-pause when stopped"), isOn: Binding(
                get: { model.recorder.autoPauseEnabled },
                set: { enabled in
                    model.recorder.setLiveAutoPauseEnabled(enabled)
                    model.trackLiveOption("auto_pause", enabled: enabled)
                }
            ))
            .frame(minHeight: 44)
            .accessibilityIdentifier("LiveAutoPause")
            if [.distance, .time, .calories].contains(model.liveGoalMode) {
                Toggle(String(localized: "today.stop.at.goal", defaultValue: "Pause at goal"), isOn: Binding(
                    get: { model.recorder.liveWorkoutOptions?.pauseAtGoalEnabled ?? model.autoStopAtGoalEnabled },
                    set: { enabled in
                        let reached = (model.goalCompletionRatio(distanceMeters: model.recorder.distanceMeters, durationSeconds: model.recorder.elapsedSeconds) ?? 0) >= 1
                        model.recorder.updateLiveWorkoutOptions(pauseAtGoal: enabled, goalHandled: enabled && reached ? true : nil)
                        model.trackLiveOption("auto_stop_at_goal", enabled: enabled)
                    }
                ))
                .frame(minHeight: 44)
                .accessibilityIdentifier("LivePauseAtGoal")
            }
            Button { model.setup.showsTrustedContacts = true } label: {
                HStack {
                    Text(String(localized: "record.setup.cheer_me_on", defaultValue: "Cheer me on"))
                    Spacer()
                    Text(model.dependencies.liveShareStore.isSharing ? String(localized: "common.on", defaultValue: "On") : String(localized: "common.off", defaultValue: "Off"))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                }
                .frame(minHeight: 44)
            }
            .accessibilityIdentifier("LiveCheerMeOn")
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    var embeddedCountdownCancelButton: some View {
        Button {
            model.cancelStartCountdown(returnToSetup: true)
        } label: {
            Image(systemName: "xmark")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
        }
        .padding(.top, 18)
        .padding(.leading, 16)
        .accessibilityLabel(String(localized: "Cancel activity start"))
    }

    var embeddedActivityAssistantButton: some View {
        AssistantLauncherButton(
            accentColor: model.dependencies.guideCatalog.selectedTheme.accentColor,
            analyticsDestination: "live_activity",
            analyticsEntrySource: "live_activity"
        ) {
            model.isAssistantPresented = true
        }
        .padding(.top, 18)
        .padding(.trailing, 16)
    }

    func liveWorkoutPanelBinding(source: SessionPage) -> Binding<Bool> {
        Binding(
            get: { model.live.isLiveWorkoutPanelExpanded },
            set: { isExpanded in
                guard isExpanded != model.live.isLiveWorkoutPanelExpanded else { return }
                model.live.isLiveWorkoutPanelExpanded = isExpanded
                model.track(.init(.liveWorkoutPanelDisplayChanged, properties: [
                    .selectionType: .string(isExpanded ? "expanded" : "collapsed"),
                    .sourceType: .string(source.rawValue),
                ]))
            }
        )
    }
}
