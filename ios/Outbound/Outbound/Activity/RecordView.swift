import SwiftUI
import PhotosUI
import CoreLocation
import MapKit

enum SessionPage: String {
    case camera
    case map
}

private enum ActivitySetupSheet: String, Identifiable {
    case goal
    case music
    case more

    var id: String { rawValue }

    var title: String {
        switch self {
        case .goal: String(localized: "record.goal.edit", defaultValue: "Edit Goal")
        case .music: String(localized: "record.setup.music", defaultValue: "Music")
        case .more: String(localized: "record.setup.more", defaultValue: "More")
        }
    }
}

enum ActivityLaunchLayout {
    static let dockHeight: CGFloat = 168
    static let peerCardGap: CGFloat = 12
    static let controlWidth: CGFloat = 112
    static let controlHeight: CGFloat = 64
}

struct MapAttributionOcclusionHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    func reportsMapAttributionOcclusionHeight() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: MapAttributionOcclusionHeightPreferenceKey.self,
                    value: proxy.size.height
                )
            }
        }
    }
}

struct RecordView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.analyticsManager) private var analyticsManager
    @Environment(\.outboundTheme) private var theme
    @EnvironmentObject var activityStore: ActivityStore
    @EnvironmentObject var guideStore: GuideStore
    @EnvironmentObject var guideCatalog: GuideCatalogStore
    @EnvironmentObject var assistantStore: AssistantStore
    @EnvironmentObject var checkInStore: DailyCheckInStore
    @EnvironmentObject var goalStore: GoalStore
    @EnvironmentObject var musicStore: MusicStore
    @EnvironmentObject var recognitionStore: RecognitionStore
    @EnvironmentObject var measurementPreferences: MeasurementPreferences
    @EnvironmentObject var gearStore: GearStore
    @EnvironmentObject var liveShareStore: LiveShareStore
    @EnvironmentObject var liveGroupStore: LiveGroupStore
    @EnvironmentObject var safetyContactStore: SafetyContactStore
    @EnvironmentObject var onboardingStore: OnboardingStore
    @EnvironmentObject var socialStore: TogetherStore
    @EnvironmentObject var connectivityStore: ConnectivityStore
    @EnvironmentObject var communityRouteStore: CommunityRouteStore
    @StateObject private var recorder: ActivityRecorder
    @StateObject private var guide = VirtualGuide()
    @StateObject private var liveActivityManager = SessionLiveActivityManager()
    @StateObject private var workoutPresence = WorkoutPresenceController()
    @AppStorage("preferred_session_page_v1") private var preferredSessionPageRawValue = SessionPage.map.rawValue
    @AppStorage("voice_guide_enabled_v1") private var isVoiceGuideEnabled = true
    @AppStorage("preferred_launch_goal_mode_v1") private var preferredLaunchGoalModeRawValue = ""
    @AppStorage("launch_goal_mode_start_history_v1") private var launchGoalModeStartHistoryData = Data()
    @State private var showCamera = false
    @State private var activePage: SessionPage = .map
    @State private var capturedPhotos: [(UIImage, PhotoMetadata)] = []
    @State private var isPreActivityCameraPresented = false
    @State private var isPreActivityPhotoPreviewPresented = false
    @State private var selectedPreActivityPhotoItem: PhotosPickerItem?
    @State private var pendingActivity: PendingFinishedActivity?
    @State private var plannedIntent: SessionIntent?
    @State private var activeIntent: SessionIntent?
    @State private var isAssistantPresented = false
    @State private var selectedGoalMode: SessionGoalMode = .freestyle
    @State private var selectedWorkoutChoice: LaunchWorkoutChoice = .sport(.run)
    @State private var manualActivityGoal: ActivityGoal = .freestyle
    @State private var customDistanceText = ""
    @State private var customTimeText = ""
    @State private var customCaloriesText = ""
    @State private var customGoalKind: CustomGoalKind?
    @State private var isCustomGoalAlertPresented = false
    @State private var isGoalChooserPresented = false
    @State private var plannedWorkoutIntent: SessionIntent?
    @State private var countdownStep: ActivityStartCountdownStep?
    @State private var countdownTask: Task<Void, Never>?
    @State private var didApplySmartGoalDefault = false
    @State private var didApplyDefaultSessionShoe = false
    @State private var isIndoorSession = false
    @State private var isStartingActivity = false
    @State private var selectedSessionShoeID: UUID?
    @State private var isGroupJoinAlertPresented = false
    @State private var groupInviteText = ""
    @State private var isGroupParticipantsExpanded = false
    @State private var isMusicSetupExpanded = false
    @State private var isSessionOptionsExpanded = false
    @State private var setupSheet: ActivitySetupSheet?
    @State private var musicSearchText = ""
    @State private var musicSearchCategory: MusicSearchCategory = .songs
    @State private var isAddShoePresented = false
    @State private var showsTrustedContacts = false
    @State private var showsStandaloneWorkouts = false
    @State private var didSeedLiveRunForUITest = false
    @State private var didRestoreSession = false
    @State private var showsRouteLibrary = false
    @State private var setupToastMessage: String?
    @State private var setupToastTask: Task<Void, Never>?
    @State private var didTrackSetupView = false
    @State private var exposedFeatures: Set<String> = []
    @State private var reachedGoalThresholds: Set<Int> = []
    @State private var previousRecorderState: RecordingState = .idle
    @State private var activityStartedWithGroupRun = false
    @State private var intentBeforeSelectedRoute: SessionIntent?
    @State private var selectedRouteDistanceMeters: Double?
    @State private var selectedGuidanceChallenge: LiveGuidanceChallenge = .off
    @State private var showsMusicDiscoveryTip = false
    @State private var didPresentMusicDiscoveryTip = false
    @State private var didTrackRecoveryPresentation = false
    @State private var didRestoreSessionPhotos = false
    @State private var isCapturingSessionPhoto = false
#if DEBUG
    @State private var isRunSimulationEnabled = false
    @State private var didConfigureRequestedRunSimulation = false
#endif

    let isVisible: Bool
    private let isEmbeddedInToday: Bool
    private let startRequest: Int
    private let preActivityPhotoRequest: Int
    private let routeSelectionRequest: Int
    private let routeRemovalRequest: Int
    private let shouldApplySmartGoalDefault: Bool
    private let onGoalModeChange: ((SessionGoalMode) -> Void)?
    private let onPreActivityPhotoChange: ((UIImage?) -> Void)?
    private let onPreActivityRouteChange: ((PreparedRoute?) -> Void)?
    private let onCloseRequest: ((Bool) -> Void)?
    private let onSessionStateChange: ((ActivitySessionPortalState) -> Void)?
    private let onElapsedTimeChange: ((Int) -> Void)?
    private let onLiveSurfaceVisibilityChange: ((Bool) -> Void)?

    init(
        initialIntent: SessionIntent? = nil,
        isVisible: Bool = true,
        isEmbeddedInToday: Bool = false,
        startRequest: Int = 0,
        preActivityPhotoRequest: Int = 0,
        routeSelectionRequest: Int = 0,
        routeRemovalRequest: Int = 0,
        onGoalModeChange: ((SessionGoalMode) -> Void)? = nil,
        onPreActivityPhotoChange: ((UIImage?) -> Void)? = nil,
        onPreActivityRouteChange: ((PreparedRoute?) -> Void)? = nil,
        onCloseRequest: ((Bool) -> Void)? = nil,
        onSessionStateChange: ((ActivitySessionPortalState) -> Void)? = nil,
        onElapsedTimeChange: ((Int) -> Void)? = nil,
        onLiveSurfaceVisibilityChange: ((Bool) -> Void)? = nil
    ) {
        _plannedIntent = State(initialValue: initialIntent ?? .freestyleRun)
        _plannedWorkoutIntent = State(initialValue: initialIntent)
        _selectedGoalMode = State(initialValue: initialIntent == nil ? .freestyle : .planned)
        _selectedWorkoutChoice = State(initialValue: initialIntent == nil ? .sport(.run) : .planned)
        _manualActivityGoal = State(initialValue: .freestyle)
        _intentBeforeSelectedRoute = State(initialValue: nil)
        _selectedRouteDistanceMeters = State(
            initialValue: initialIntent?.preparedRoute.map(Self.calculatePreparedRouteDistance)
        )
        self.shouldApplySmartGoalDefault = initialIntent == nil
        self.isVisible = isVisible
        self.isEmbeddedInToday = isEmbeddedInToday
        self.startRequest = startRequest
        self.preActivityPhotoRequest = preActivityPhotoRequest
        self.routeSelectionRequest = routeSelectionRequest
        self.routeRemovalRequest = routeRemovalRequest
        self.onGoalModeChange = onGoalModeChange
        self.onPreActivityPhotoChange = onPreActivityPhotoChange
        self.onPreActivityRouteChange = onPreActivityRouteChange
        self.onCloseRequest = onCloseRequest
        self.onSessionStateChange = onSessionStateChange
        self.onElapsedTimeChange = onElapsedTimeChange
        self.onLiveSurfaceVisibilityChange = onLiveSurfaceVisibilityChange
        let loc = LocationManager()
        _recorder = StateObject(wrappedValue: ActivityRecorder(locationManager: loc))
    }

    private var recordStateSurface: some View {
        Group {
            if isEmbeddedInToday {
                ZStack {
                    embeddedReadyView
                        .opacity(isVisible && !showsEmbeddedLiveSurface ? 1 : 0)
                        .allowsHitTesting(isVisible && !showsEmbeddedLiveSurface)

                    if showsEmbeddedLiveSurface {
                        activityFullscreenSurface
                            .zIndex(1)
                            .onAppear {
                                trackRecoveryPresentationIfNeeded(result: "success")
                            }
                    }
                }
            } else if showCamera || pendingActivity != nil {
                activityFullscreenSurface
            } else {
                readyView
            }
        }
        .background { recordBackground }
        .onReceive(recorder.$liveSnapshot) { snapshot in
            guide.ingest(snapshot)
            liveShareStore.ingest(snapshot)
            liveGroupStore.ingest(snapshot)
            updateLiveActivity(
                snapshot: snapshot,
                state: recorder.state,
                intent: activeIntent ?? plannedIntent
            )
            trackGoalProgressIfNeeded(snapshot)
        }
        .onReceive(recorder.routeGuidanceEvents) { event in
            handleRouteGuidanceEvent(event)
        }
        .onReceive(recorder.$state) { state in
            onSessionStateChange?(ActivitySessionPortalState(recordingState: state))
            trackRecordingStateTransition(to: state)
            workoutPresence.sync(with: state)
        }
        .onReceive(recorder.$elapsedSeconds) { elapsedSeconds in
            onElapsedTimeChange?(elapsedSeconds)
        }
        .onChange(of: isVisible, initial: true) { wasVisible, isNowVisible in
            seedLiveRunForUITestIfRequested()
#if DEBUG
            configureRequestedRunSimulationIfNeeded()
#endif
            guard !wasVisible, isNowVisible else { return }
            presentMusicDiscoveryTipIfNeeded()
        }
        .onChange(of: startRequest) { _, _ in
            guard isEmbeddedInToday, isVisible, !showCamera else { return }
            startRecording()
        }
        .onChange(of: preActivityPhotoRequest) { _, _ in
            handlePreActivityPhotoRequest()
        }
        .onChange(of: routeSelectionRequest) { _, _ in
            handleRouteSelectionRequest()
        }
        .onChange(of: routeRemovalRequest) { _, _ in
            handleRouteRemovalRequest()
        }
        .onChange(of: selectedGoalMode, initial: true) { _, mode in
            onGoalModeChange?(mode)
        }
        .onChange(of: plannedIntent?.preparedRoute, initial: true) { _, route in
            onPreActivityRouteChange?(route)
        }
        .onChange(of: showsEmbeddedLiveSurface, initial: true) { _, isVisible in
            onLiveSurfaceVisibilityChange?(isVisible)
        }
        .onAppear {
            restoreInterruptedPhotosIfNeeded()
            onPreActivityPhotoChange?(preActivityPhoto)
            restoreInterruptedSessionIfNeeded()
#if DEBUG
            configureRequestedRunSimulationIfNeeded()
#endif
            workoutPresence.sync(with: recorder.state)
            if recorder.state == .idle {
                recorder.locationManager.requestCurrentLocation()
            }
        }
    }

    var body: some View {
        recordStateSurface
        .task {
            await musicStore.refresh()
            await musicStore.loadQuickPicks()
            await guideCatalog.refreshServerCatalog()
            guide.setSpeechEnabled(voiceGuideSpeechEnabled)
            applyWorkoutMusicSuggestion()
            presentMusicDiscoveryTipIfNeeded()
            guide.speechEventHandler = { event in
                Task { await musicStore.handleGuideSpeechEvent(event) }
            }
            guide.guidanceEventHandler = { event in
                trackGuidanceEvent(event)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                guideCatalog.refreshInstalledVoices()
                workoutPresence.sync(with: recorder.state)
            }
            guard newPhase == .active, recorder.state == .active else { return }
            Task { await musicStore.retryPendingWorkoutPlaybackIfNeeded() }
        }
        .onChange(of: activePage) { _, newPage in
            guard showCamera else { return }
            preferredSessionPageRawValue = newPage.rawValue
        }
        .onChange(of: plannedIntent) { _, _ in applyWorkoutMusicSuggestion() }
        .onChange(of: setupSheet) { _, sheet in
            guard sheet == .music else { return }
            prepareMusicPicker()
        }
        .onChange(of: musicStore.snapshot.connectionState) { oldState, newState in
            guard oldState == .connecting, newState != .connecting else { return }
            track(.init(.musicAuthorizationCompleted, properties: [
                .result: .string(newState == .connected ? "granted" : "not_granted")
            ]))
        }
        .onChange(of: musicStore.playback.isPlaying) { wasPlaying, isPlaying in
            guard !wasPlaying, isPlaying else { return }
            track(.init(.musicPlaybackStarted, properties: [.result: .string("success")]))
        }
        .onDisappear {
            cancelStartCountdown(returnToSetup: recorder.state == .idle)
        }
        .overlay(alignment: .topLeading) {
            if isVisible,
               pendingActivity == nil,
               let onCloseRequest,
               recorder.state == .idle,
               !isEmbeddedInToday {
                Button {
                    if isCountingDown {
                        cancelStartCountdown(returnToSetup: true)
                    } else {
                        onCloseRequest(false)
                    }
                } label: {
                    Image(systemName: activityCloseSystemImage)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(showCamera ? .white : .primary)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding(.top, showCamera ? 18 : 14)
                .padding(.leading, 16)
                .accessibilityLabel(activityCloseAccessibilityLabel)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isVisible,
               pendingActivity == nil,
               !isEmbeddedInToday || showCamera || recorder.state != .idle {
                Button {
                    isAssistantPresented = true
                } label: {
                    Image(systemName: "sparkles")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(showCamera ? .white : .primary)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding(.top, showCamera ? 18 : 14)
                .padding(.trailing, 16)
                .accessibilityLabel(String(localized: "record.accessibility.open_assistant", defaultValue: "Open assistant"))
            }
        }
        .sheet(isPresented: $showsRouteLibrary) {
            NavigationStack {
                CommunityRouteLibraryView(selection: plannedIntent?.preparedRoute) { route in
                    applyRoute(route)
                    showsRouteLibrary = false
                }
            }
        }
        .sheet(item: $setupSheet) { sheet in
            setupSheetView(sheet)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isAssistantPresented) {
            AssistantView(
                screenName: showCamera ? "Live Recording" : "Record Setup",
                isRecordingActive: recorder.state == .active || recorder.state == .paused
            )
            .presentationDetents([.fraction(0.58), .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isAddShoePresented) {
            AddShoeView()
                .environmentObject(gearStore)
                .environmentObject(measurementPreferences)
        }
        .sheet(isPresented: $showsTrustedContacts) {
            NavigationStack { SafetyContactsSettingsView() }
                .environmentObject(safetyContactStore)
        }
        .sheet(isPresented: $showsStandaloneWorkouts) {
            StandaloneWorkoutPickerView { workout in
                let selectedRoute = plannedIntent?.preparedRoute
                plannedWorkoutIntent = workout.intent
                if let selectedRoute {
                    intentBeforeSelectedRoute = workout.intent
                    plannedIntent = routeIntent(selectedRoute, appliedTo: workout.intent)
                } else {
                    plannedIntent = workout.intent
                    intentBeforeSelectedRoute = nil
                    selectedRouteDistanceMeters = nil
                }
                selectedWorkoutChoice = .planned
                selectedGoalMode = .planned
                showsStandaloneWorkouts = false
            }
        }
        .fullScreenCover(isPresented: $isPreActivityCameraPresented) {
            PostRunCameraView { image in
                replacePreActivityPhoto(with: image)
            }
        }
        .sheet(isPresented: $isPreActivityPhotoPreviewPresented) {
            preActivityPhotoPreview
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: selectedPreActivityPhotoItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data)
                else { return }
                await MainActor.run {
                    replacePreActivityPhoto(with: image)
                    selectedPreActivityPhotoItem = nil
                }
            }
        }
        .onChange(of: liveShareStore.lastErrorMessage) { _, message in
            showSetupToast(message)
        }
        .onChange(of: liveGroupStore.lastErrorMessage) { _, message in
            showSetupToast(message)
        }
        .onChange(of: musicStore.lastErrorMessage) { _, message in
            guard let message else { return }
            track(.init(.musicOperationFailed, properties: [
                .errorCategory: .string(musicStore.hasDeveloperTokenError ? "configuration" : "provider")
            ]))
            showSetupToast(message)
        }
        .overlay(alignment: .top) {
            if let setupToastMessage {
                Text(setupToastMessage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(radius: 8, y: 3)
                    .padding(.top, 62)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .alert(customGoalAlertTitle, isPresented: $isCustomGoalAlertPresented) {
            if customGoalKind == .distance {
                TextField(String(localized: "record.goal.distance_km", defaultValue: "Distance in km"), text: $customDistanceText)
                    .keyboardType(.decimalPad)
            } else if customGoalKind == .time {
                TextField(String(localized: "record.goal.time_minutes", defaultValue: "Time in minutes"), text: $customTimeText)
                    .keyboardType(.numberPad)
            } else {
                TextField(String(localized: "record.goal.calories_kcal", defaultValue: "Calories in kcal"), text: $customCaloriesText)
                    .keyboardType(.numberPad)
            }

            Button(String(localized: "common.set", defaultValue: "Set")) {
                applyCustomGoal()
            }

            Button(String(localized: "common.cancel", defaultValue: "Cancel"), role: .cancel) {
                customGoalKind = nil
            }
        } message: {
            Text(customGoalAlertMessage)
        }
        .alert(String(localized: "record.group.join.title", defaultValue: "Join group run"), isPresented: $isGroupJoinAlertPresented) {
            TextField(String(localized: "record.group.invite.placeholder", defaultValue: "Invite link or token"), text: $groupInviteText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button(String(localized: "record.group.join.action", defaultValue: "Join")) {
                let invite = groupInviteText
                groupInviteText = ""
                track(.init(.groupRunJoinAttempted))
                Task {
                    await liveGroupStore.joinGroup(invite: invite)
                    if liveGroupStore.isSharing {
                        track(.init(.groupRunJoined, properties: [
                            .participantCountBucket: .string(ProductAnalyticsBucket.count(liveGroupStore.participants.count))
                        ]))
                    }
                }
            }

            Button(String(localized: "common.cancel", defaultValue: "Cancel"), role: .cancel) {
                groupInviteText = ""
            }
        } message: {
            Text(String(localized: "record.group.join.help", defaultValue: "Paste the Plainstride group run invite from another runner."))
        }
    }

    private var showsEmbeddedLiveSurface: Bool {
        isEmbeddedInToday && isVisible && (showCamera || pendingActivity != nil)
    }

    private func trackRecoveryPresentationIfNeeded(result: String) {
        guard recorder.recoveredSession, !didTrackRecoveryPresentation else { return }
        didTrackRecoveryPresentation = true
        track(.init(.activityRecoveryPresentation, properties: [
            .result: .string(result),
            .countBucket: .string(ProductAnalyticsBucket.count(1))
        ]))
    }

    private var activityFullscreenSurface: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            if let pendingActivity {
                postRunSummarySurface(pendingActivity)
                    .transition(postRunSummaryTransition)
                    .zIndex(1)
            } else {
                liveRecordingSurface
                    .transition(liveRunCompletionTransition)
                    .zIndex(0)
            }
        }
        .animation(activityCompletionAnimation, value: pendingActivity?.id)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
    }

    private func postRunSummarySurface(_ activity: PendingFinishedActivity) -> some View {
        PostRunSummaryView(
            summary: activity.summary,
            photos: activity.photos,
            reflection: activity.reflection,
            recognitionPreviews: activity.recognitionPreviews,
            guidanceReport: activity.guidanceReport,
            workoutID: (activeIntent ?? plannedIntent)?.id ?? "freestyle-run",
            onGuidanceFeedback: handleGuidanceFeedback,
            onSave: { selectedPhotos, reflection in
                await savePendingActivity(activity, photos: selectedPhotos, reflection: reflection)
            },
            onDiscard: discardPendingActivity
        )
    }

    private var activityCompletionAnimation: Animation {
        .easeOut(duration: reduceMotion ? 0.16 : 0.3)
    }

    private var liveRunCompletionTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .scale(scale: 0.98).combined(with: .opacity)
    }

    private var postRunSummaryTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .scale(scale: 1.02).combined(with: .opacity)
    }

    @ViewBuilder
    private var recordBackground: some View {
        if isEmbeddedInToday {
            Color.clear
        } else {
            Color(.systemBackground)
                .ignoresSafeArea()
        }
    }

    private var liveRecordingSurface: some View {
        ZStack {
            TabView(selection: $activePage) {
                CameraHUDView(
                    recorder: recorder,
                    guide: guide,
                    musicStore: musicStore,
                    intent: activeIntent ?? plannedIntent,
                    capturedPhotoCount: capturedPhotos.count,
                    lastCapturedPhoto: capturedPhotos.last?.0,
                    activePage: $activePage,
                    onStart: startRecording,
                    onResume: resumeRecording,
                    onFinish: finishRecording,
                    onCaptureStateChange: { isCapturingSessionPhoto = $0 }
                ) { image, meta in
                    let photo = (image, meta)
                    capturedPhotos.append(photo)
                    ActiveSessionPhotoJournal.append(photo)
                    track(.init(.photoCaptured, properties: [
                        .sourceType: .string("in_activity"),
                        .locationAttached: .boolean(meta.coordinate != nil)
                    ]))
                }
                .tag(SessionPage.camera)
                .ignoresSafeArea()

                LiveMapView(
                    recorder: recorder,
                    locationManager: recorder.locationManager,
                    guide: guide,
                    musicStore: musicStore,
                    intent: activeIntent ?? plannedIntent,
                    capturedPhotoCount: capturedPhotos.count,
                    lastCapturedPhoto: capturedPhotos.last?.0,
                    activePage: $activePage,
                    onStart: startRecording,
                    onResume: resumeRecording,
                    onFinish: finishRecording,
                    isFinishEnabled: !isCapturingSessionPhoto
                )
                .tag(SessionPage.map)
                .ignoresSafeArea()
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            if let countdownStep {
                ActivityStartCountdownOverlay(step: countdownStep, reduceMotion: reduceMotion)
                    .transition(.opacity)
            }

#if DEBUG
            if recorder.isSimulatingRun, countdownStep == nil {
                VStack {
                    RunSimulationControls(
                        recorder: recorder,
                        onControlUsed: trackRunSimulationControl
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, 62)

                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
#endif
        }
        .background(Color(.systemBackground))
        .toolbar(.hidden, for: .tabBar)
        .overlay(alignment: .topLeading) {
            if isEmbeddedInToday, isCountingDown {
                embeddedCountdownCancelButton
            }
        }
        .overlay(alignment: .topTrailing) {
            if isEmbeddedInToday {
                embeddedActivityAssistantButton
            }
        }
    }

    private var embeddedCountdownCancelButton: some View {
        Button {
            cancelStartCountdown(returnToSetup: true)
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

    private var embeddedActivityAssistantButton: some View {
        Button {
            isAssistantPresented = true
        } label: {
            Image(systemName: "sparkles")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
        }
        .padding(.top, 18)
        .padding(.trailing, 16)
        .accessibilityLabel(String(localized: "record.accessibility.open_assistant", defaultValue: "Open assistant"))
    }

    private func startRecording() {
        guard recorder.state == .idle, !isCountingDown else { return }
        guard !isStartingActivity else { return }
        beginStartRecording()
    }

    private func beginStartRecording() {
        guard recorder.state == .idle, !isCountingDown, !isStartingActivity else { return }
        guide.setSpeechEnabled(voiceGuideSpeechEnabled)
        isStartingActivity = true
        let intent = plannedIntent
        beginRecordingAfterLiveShareSetup()
        isStartingActivity = false

        guard !connectivityStore.isOffline else { return }
        Task { @MainActor in
            async let brief = try? APIClient.shared.fetchCompanionSessionBrief(workoutID: intent?.id)
            async let presentation = liveShareStore.beginIfArmed(
                intent: intent,
                contact: safetyContactStore.defaultContact
            )
            if let companionBrief = await brief {
                guide.updateCompanionBrief(companionBrief)
            }
            if let liveSharePresentation = await presentation {
                await SystemSharePresenter.present(activityItems: liveSharePresentation.activityItems)
            }
        }
    }

    private func restoreInterruptedSessionIfNeeded() {
        guard recorder.recoveredSession, !didRestoreSession else { return }
        didRestoreSession = true
        if let recovered = recorder.recoveredRouteGuidance {
            let route = recovered.route
            let recoveredActivityType = route.activityType ?? recorder.recoveredActivityType
            let sport = SportType(activityType: recoveredActivityType)
            plannedIntent = SessionIntent(
                id: "route-\(route.id)",
                sport: sport,
                title: route.name,
                detail: String(localized: "route.guidance.setup.detail", defaultValue: "Follow the selected route with on-device guidance"),
                guideLine: String(localized: "route.guidance.setup.companion", defaultValue: "Keep the route visible and follow it at your own pace."),
                startLabel: String(localized: "route.guidance.resume", defaultValue: "Resume Route Guidance"),
                routeName: route.name,
                preparedRoute: route,
                activityTypeOverride: recoveredActivityType
            )
            selectedRouteDistanceMeters = Self.calculatePreparedRouteDistance(route)
        } else if let recoveredActivityType = recorder.recoveredActivityType,
                  recoveredActivityType != .running {
            let sport = SportType(activityType: recoveredActivityType)
            plannedIntent = SessionIntent(
                id: "recovered-\(sport.rawValue)",
                sport: sport,
                title: String(format: String(localized: "activity.recovered.title.format", defaultValue: "Recovered %@"), locale: .autoupdatingCurrent, sport.displayName.lowercased()),
                detail: String(localized: "activity.recovered.detail", defaultValue: "Paused activity recovered on this device"),
                guideLine: String(localized: "activity.recovered.companion", defaultValue: "Resume when you are ready."),
                startLabel: String(localized: "common.resume", defaultValue: "Resume"),
                activityTypeOverride: recoveredActivityType
            )
        }
        activeIntent = plannedIntent
        activePage = preferredSessionPage
        showCamera = true
        guide.setSpeechEnabled(voiceGuideSpeechEnabled)
        guide.activate(
            with: guideStore.profile,
            persona: guideCatalog.selectedPersona,
            sessionIntent: activeIntent,
            unitSystem: measurementPreferences.unitSystem,
            challenge: .off,
            suppressedMomentTypes: guideCatalog.suppressedMomentTypes(
                for: guideCatalog.selection.coachingContract
            )
        )
        trackFeatureExposure("live_guidance")
        if let route = activeIntent?.preparedRoute,
           let snapshot = recorder.routeGuidanceSnapshot {
            track(.init(.routeGuidanceRecovered, properties: [
                .sourceType: .string(route.source.rawValue),
                .direction: .string(route.direction.rawValue),
                .progressPercent: .integer(coarseRouteProgressPercent(snapshot.progressFraction))
            ]))
        }
    }

    private func seedLiveRunForUITestIfRequested() {
#if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-OutboundUITestLive10K"),
              isVisible,
              !didSeedLiveRunForUITest
        else { return }

        didSeedLiveRunForUITest = true
        let intent = SessionIntent(
            id: "ui-test-live-10k",
            sport: .run,
            title: String(localized: "session.seed.live_10k.title", defaultValue: "Morning 10K"),
            detail: String(localized: "session.seed.live_10k.detail", defaultValue: "Run • 10 km target"),
            guideLine: String(localized: "session.seed.live_10k.guide", defaultValue: "Stay relaxed now, then build through the final 2 km."),
            startLabel: "Start now",
            targetDistanceMeters: 10_000
        )
        plannedIntent = intent
        activeIntent = intent
        selectedRouteDistanceMeters = nil
        activePage = .map
        capturedPhotos = []
        pendingActivity = nil
        showCamera = true
        recorder.seedLiveRunForUITest()
#endif
    }

#if DEBUG
    private func configureRequestedRunSimulationIfNeeded() {
        guard isVisible,
              !didConfigureRequestedRunSimulation,
              !ProcessInfo.processInfo.arguments.contains("-OutboundUITestLive10K"),
              ProcessInfo.processInfo.arguments.contains(HarvestHalfMarathonSimulation.launchArgument)
        else { return }

        didConfigureRequestedRunSimulation = true
        configureHarvestRunSimulation(enabled: true, tracksChange: false)
    }

    private func configureHarvestRunSimulation(
        enabled: Bool,
        tracksChange: Bool = true
    ) {
        guard recorder.state == .idle else { return }
        isRunSimulationEnabled = enabled

        if enabled {
            selectedWorkoutChoice = .sport(.run)
            selectedGoalMode = .freestyle
            manualActivityGoal = .freestyle
            plannedWorkoutIntent = nil
            plannedIntent = .freestyleRun
            intentBeforeSelectedRoute = nil
            isIndoorSession = false
            applyRoute(HarvestHalfMarathonSimulation.route)
        } else if plannedIntent?.preparedRoute?.id == HarvestHalfMarathonSimulation.routeID {
            applyRoute(nil)
        }

        guard tracksChange else { return }
        track(.init(.activityConfigurationChanged, properties: [
            .changeType: .string("run_simulation"),
            .selectionType: .string(enabled ? "enabled" : "disabled")
        ]))
    }

    private func trackRunSimulationControl(_ control: String, _ selection: String) {
        track(.init(.activitySimulationControlUsed, properties: [
            .control: .string(control),
            .selectionType: .string(selection)
        ]))
    }
#endif

    private func beginRecordingAfterLiveShareSetup(companionBrief: CompanionSessionBriefDTO? = nil) {
        ActiveSessionPhotoJournal.replace(with: capturedPhotos)
        pendingActivity = nil
        activePage = preferredSessionPage
        activeIntent = plannedIntent
#if DEBUG
        if !isRunSimulationEnabled {
            recorder.locationManager.requestPermission()
        }
#else
        recorder.locationManager.requestPermission()
#endif
        guide.setSpeechEnabled(voiceGuideSpeechEnabled)
        guide.activate(
            with: guideStore.profile,
            persona: guideCatalog.selectedPersona,
            sessionIntent: activeIntent,
            companionBrief: companionBrief,
            unitSystem: measurementPreferences.unitSystem,
            challenge: selectedGuidanceChallenge,
            suppressedMomentTypes: guideCatalog.suppressedMomentTypes(
                for: guideCatalog.selection.coachingContract
            )
        )
        trackFeatureExposure("live_guidance")
        showCamera = true
        beginStartCountdown()
    }

    private func beginStartCountdown() {
        countdownTask?.cancel()
        guide.announceStartCountdown(ActivityStartCountdownStep.sequence.map(\.spokenText))
        countdownTask = Task { @MainActor in
            for step in ActivityStartCountdownStep.sequence {
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: reduceMotion ? 0.12 : 0.22)) {
                    countdownStep = step
                }
                announceCountdownFeedback(step)

                do {
                    try await Task.sleep(nanoseconds: step.durationNanoseconds)
                } catch {
                    return
                }
            }

            guard !Task.isCancelled else { return }
            completeStartCountdown()
        }
    }

    private func announceCountdownFeedback(_ step: ActivityStartCountdownStep) {
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

    private func completeStartCountdown() {
        guard recorder.state == .idle else {
            countdownStep = nil
            countdownTask = nil
            return
        }

        countdownStep = nil
        countdownTask = nil
        let routeGuidance = activeIntent?.preparedRoute.map {
            ActiveRouteGuidanceJournal(route: $0, recoverySeed: nil)
        }
        startRecorder(routeGuidance: routeGuidance)
        recordStartedGoalMode()
        if let route = activeIntent?.preparedRoute {
            track(.init(.routeNavigationStarted, properties: [
                .sourceType: .string(route.source.rawValue),
                .distanceBucket: .string(ProductAnalyticsBucket.distance(meters: preparedRouteDistance(route))),
                .direction: .string(route.direction.rawValue)
            ]))
        }
        reachedGoalThresholds = []
        activityStartedWithGroupRun = liveGroupStore.isSharing
        track(.init(.activityStarted, properties: activityConfigurationProperties))
        updateLiveActivity(
            snapshot: recorder.liveSnapshot,
            state: recorder.state,
            intent: activeIntent
        )
        Task {
            await musicStore.beginWorkoutPlaybackIfNeeded()
        }
    }

    private func startRecorder(routeGuidance: ActiveRouteGuidanceJournal?) {
#if DEBUG
        if isRunSimulationEnabled,
           let routeGuidance,
           routeGuidance.route.id == HarvestHalfMarathonSimulation.routeID {
            recorder.startRunSimulation(
                activityType: .running,
                routeGuidance: routeGuidance,
                route: routeGuidance.route
            )
            track(.init(.activitySimulationStarted, properties: [
                .sourceType: .string("harvest_half"),
                .distanceBucket: .string(ProductAnalyticsBucket.distance(
                    meters: recorder.runSimulationState?.routeDistanceMeters ?? 0
                )),
                .selectionType: .string(recorder.runSimulationSpeedBucket)
            ]))
            return
        }
#endif
        recorder.start(
            activityType: activeIntent?.resolvedActivityType ?? .running,
            routeGuidance: routeGuidance
        )
    }

    private func updateLiveActivity(
        snapshot: ActiveSessionSnapshot,
        state: RecordingState,
        intent: SessionIntent?
    ) {
        guard let result = liveActivityManager.update(
            snapshot: snapshot,
            state: state,
            intent: intent,
            unitSystem: measurementPreferences.unitSystem
        ) else { return }

        track(.init(.liveActivityReconciled, properties: [
            .result: .string(result.rawValue)
        ]))
    }

    private func cancelStartCountdown(returnToSetup: Bool) {
        guard isCountingDown else { return }
        countdownTask?.cancel()
        countdownTask = nil
        countdownStep = nil
        guide.deactivate()
        activeIntent = nil
        if returnToSetup {
            showCamera = false
        }
    }

    private var isCountingDown: Bool {
        countdownStep != nil || countdownTask != nil
    }

    private func finishRecording() {
        guard !isCapturingSessionPhoto else { return }
        cancelStartCountdown(returnToSetup: true)
        let summary = recorder.finish()
        let guidanceReport = guide.finalizedSessionReport()
        guideCatalog.recordGuidanceReport(guidanceReport)
        track(.init(.activityFinished, properties: outcomeProperties(for: summary)))
        let locationDiagnostics = recorder.locationManager.recordingDiagnostics
        track(.init(.activityRecordingQuality, properties: [
            .sourceType: .string(locationDiagnostics.deliveryMode),
            .countBucket: .string(ProductAnalyticsBucket.locationPointCount(
                locationDiagnostics.acceptedTrackPointCount
            )),
            .result: .string(locationDiagnostics.result)
        ]))
        liveActivityManager.end(using: recorder.liveSnapshot, unitSystem: measurementPreferences.unitSystem)
        liveShareStore.end()
        liveGroupStore.finishActivity()
        guide.deactivate()
        Task { await musicStore.endWorkoutPlaybackIfNeeded() }
        let reflection = DailyMotivationEngine.finishReflection(
            summary: summary,
            priorActivities: activityStore.activities,
            readiness: checkInStore.readiness,
            intent: activeIntent,
            goalProgress: goalStore.previewProgress(with: summary, activities: activityStore.activities)
        )
        let recognitionPreviews = recognitionStore.previewPostRunRecognition(
            summary: summary,
            priorActivities: activityStore.activities,
            readiness: checkInStore.readiness,
            intent: activeIntent,
            goalProgress: goalStore.previewProgress(with: summary, activities: activityStore.activities),
            photoCount: capturedPhotos.count
        )
        let finishedActivity = PendingFinishedActivity(
            summary: summary,
            photos: capturedPhotos,
            reflection: reflection,
            recognitionPreviews: recognitionPreviews,
            guidanceReport: guidanceReport
        )
        withAnimation(activityCompletionAnimation) {
            pendingActivity = finishedActivity
            showCamera = false
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func resumeRecording() {
        let shouldRecoverWorkoutMusic = recorder.recoveredSession
        recorder.resume()
        guard shouldRecoverWorkoutMusic else { return }

        Task {
            guard let outcome = await musicStore.resumeRecoveredWorkoutPlaybackIfNeeded() else { return }
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
            track(.init(.musicPlaybackRecoveryCompleted, properties: properties))
        }
    }

    private func savePendingActivity(
        _ activity: PendingFinishedActivity,
        photos: [(UIImage, PhotoMetadata)],
        reflection: FinishReflection
    ) async -> Bool {
        let priorActivities = activityStore.activities
        let previewProgress = goalStore.previewProgress(with: activity.summary, activities: priorActivities)
        let savedActivityType = activeIntent?.resolvedActivityType ?? .running
        let savedSport = SportType(activityType: savedActivityType)
        let followedRoute = activeIntent?.preparedRoute.map { route in
            FollowedRouteMetadata(
                route: route,
                finalProgress: activity.summary.routeGuidance?.progressFraction ?? 0,
                arrived: activity.summary.routeGuidance?.hasArrived ?? false
            )
        }

        guard let savedActivity = try? await activityStore.save(
            summary: activity.summary,
            photos: photos,
            activityType: savedActivityType,
            reflection: reflection,
            goal: activeIntent?.activityGoal,
            title: activeIntent?.preparedRoute == nil && savedActivityType == .running
                ? nil
                : activeIntent?.title,
            source: .outboundRecorded,
            gear: savedActivityType == .running ? gearStore.attachment(for: selectedSessionShoe) : nil,
            indoor: isIndoorSession ? ActivityIndoorMetadata(isIndoor: true, mode: "treadmill") : nil,
            heartRateZones: heartRateZones(from: activity.summary),
            activityEventID: activeIntent?.activityEvent?.id == socialStore.recordingActivityEventID
                ? socialStore.recordingActivityEventID
                : nil,
            followedRoute: followedRoute
        ) else {
            return false
        }
        var savedProperties = outcomeProperties(for: activity.summary)
        savedProperties[.goalType] = .string(analyticsGoalType)
        savedProperties[.photoCountBucket] = .string(ProductAnalyticsBucket.count(photos.count))
        savedProperties[.musicEnabled] = .boolean(musicWasConfigured)
        savedProperties[.routeSelected] = .boolean(activeIntent?.preparedRoute != nil)
        savedProperties[.shoeSelected] = .boolean(selectedSessionShoe != nil)
        savedProperties[.groupRunEnabled] = .boolean(activityStartedWithGroupRun)
        savedProperties[.indoor] = .boolean(isIndoorSession)
        track(.init(.activitySaved, properties: savedProperties))
        if let followedRoute {
            track(.init(.routeGuidanceCompleted, properties: [
                .sourceType: .string(followedRoute.source.rawValue),
                .direction: .string(followedRoute.direction.rawValue),
                .progressPercent: .integer(coarseRouteProgressPercent(followedRoute.finalProgress)),
                .result: .string(followedRoute.arrived ? "arrived" : "partial")
            ]))
        }
        _ = socialStore.consumeRecordingActivityEventID()

        let estimatedEnergy = estimatedEnergyKilocalories(
            for: savedActivity,
            sport: savedSport,
            weightKilograms: onboardingStore.bodyProfile.weightKilograms
        )
        Task {
            try? await HealthKitService().saveWorkout(
                savedActivity,
                sport: savedSport,
                energyKilocalories: estimatedEnergy
            )
        }

        _ = recognitionStore.recordSavedActivity(
            savedActivity,
            priorActivities: priorActivities,
            readiness: checkInStore.readiness,
            intent: activeIntent,
            goalProgress: previewProgress
        )
        goalStore.refresh(
            activities: activityStore.activities,
            phase: DailyMotivationEngine.phase(for: activityStore.activities)
        )
        clearPending()
        onCloseRequest?(false)
        return true
    }

    private func estimatedEnergyKilocalories(
        for activity: SavedActivity,
        sport: SportType,
        weightKilograms: Double?
    ) -> Double? {
        guard let weightKilograms, weightKilograms > 0, activity.durationSecs > 0 else { return nil }

        switch sport {
        case .run:
            guard activity.distanceM > 0 else { return nil }
            return weightKilograms * (activity.distanceM / 1_000)
        case .bike:
            let moderateCyclingMET = 8.0
            return moderateCyclingMET * weightKilograms * (Double(activity.durationSecs) / 3_600)
        case .walk, .hike:
            let walkingMET = sport == .hike ? 6.0 : 3.5
            return walkingMET * weightKilograms * (Double(activity.durationSecs) / 3_600)
        case .swim:
            let moderateSwimmingMET = 6.0
            return moderateSwimmingMET * weightKilograms * (Double(activity.durationSecs) / 3_600)
        }
    }

    private func discardPendingActivity() {
        if let pendingActivity {
            var properties = outcomeProperties(for: pendingActivity.summary)
            properties[.photoCountBucket] = .string(ProductAnalyticsBucket.count(pendingActivity.photos.count))
            track(.init(.activityDiscarded, properties: properties))
        }
        let resolvesRecordingEvent = activeIntent?.activityEvent?.id == socialStore.recordingActivityEventID
        let consumedActivityEventID = socialStore.consumeRecordingActivityEventID()
        let activityEventID = resolvesRecordingEvent ? consumedActivityEventID : nil
        liveActivityManager.end()
        liveShareStore.end()
        liveGroupStore.finishActivity()
        clearPending()
        onCloseRequest?(false)
        if let activityEventID {
            Task {
                _ = await socialStore.markActivityEventWithoutRecording(id: activityEventID)
            }
        }
    }

    private func clearPending() {
        cancelStartCountdown(returnToSetup: true)
        pendingActivity = nil
        capturedPhotos = []
        isCapturingSessionPhoto = false
        ActiveSessionPhotoJournal.clear()
        onPreActivityPhotoChange?(nil)
        activeIntent = nil
        plannedIntent = nil
        selectedWorkoutChoice = .sport(.run)
        manualActivityGoal = .freestyle
        selectedGoalMode = .freestyle
        selectedSessionShoeID = nil
        didApplyDefaultSessionShoe = false
        isIndoorSession = false
        activityStartedWithGroupRun = false
        intentBeforeSelectedRoute = nil
        selectedRouteDistanceMeters = nil
        selectedGuidanceChallenge = .off
#if DEBUG
        isRunSimulationEnabled = false
#endif
    }

    private var preferredSessionPage: SessionPage {
        SessionPage(rawValue: preferredSessionPageRawValue) ?? .map
    }

    private var activityCloseSystemImage: String {
        "xmark"
    }

    private var activityCloseAccessibilityLabel: String {
        isCountingDown
            ? String(localized: "Cancel activity start")
            : String(localized: "Close activity setup")
    }

    private var readyView: some View {
        ZStack(alignment: .bottom) {
            if !usesEmbeddedPlannedContent {
                launchMap
            }

            VStack(spacing: 10) {
                if connectivityStore.isOffline {
                    OfflineStatusBanner(compact: true)
                        .padding(.horizontal, 16)
                }

                Spacer(minLength: 96)

                if showsLaunchGoalCard {
                    launchGoalCard
                        .padding(.horizontal, 18)
                }

                if showsManualGoalPills {
                    launchGoalPillRow
                        .padding(.bottom, 2)
                }

                launchDock
            }
            .padding(.bottom, isEmbeddedInToday ? 8 : 70)

            if !isEmbeddedInToday {
                contextualStartControl
                    .padding(.bottom, 3)
            }
        }
        .onAppear {
            guideCatalog.refreshInstalledVoices()
            applySmartGoalDefaultIfNeeded()
            applyLearnedGoalModeIfNeeded()
            applyDefaultSessionShoeIfNeeded()
            trackSetupAndFeatureExposureIfNeeded()
        }
    }

    private var embeddedReadyView: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                Color.clear
                    .allowsHitTesting(false)

                if showsLaunchGoalCard || plannedIntent?.preparedRoute != nil {
                    VStack(spacing: 10) {
                        if connectivityStore.isOffline {
                            OfflineStatusBanner(compact: true)
                                .padding(.horizontal, 16)
                        }

                        Spacer(minLength: 72)

                        VStack(spacing: 10) {
                            if let route = plannedIntent?.preparedRoute {
                                launchRoutePreviewCard(route)
                            }

                            if showsLaunchGoalCard {
                                launchGoalCard
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 12)
                        .reportsMapAttributionOcclusionHeight()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            if showsManualGoalPills {
                launchGoalPillRow
                    .padding(.vertical, 10)
            }

            launchDock
        }
        .onAppear {
            guideCatalog.refreshInstalledVoices()
            applySmartGoalDefaultIfNeeded()
            applyLearnedGoalModeIfNeeded()
            applyDefaultSessionShoeIfNeeded()
            trackSetupAndFeatureExposureIfNeeded()
        }
    }

    private var usesEmbeddedPlannedContent: Bool {
        isEmbeddedInToday && selectedWorkoutChoice == .planned
    }

    private var showsLaunchGoalCard: Bool {
        !usesEmbeddedPlannedContent && selectedGoalMode != .freestyle
    }

    private var showsManualGoalPills: Bool {
        selectedWorkoutChoice != .planned
    }

    @ViewBuilder
    private var launchMap: some View {
        let map = ActivityLaunchMap(
            locationManager: recorder.locationManager,
            route: plannedIntent?.preparedRoute
        )
        if isEmbeddedInToday {
            map
        } else {
            map.ignoresSafeArea()
        }
    }

    private var launchGoalCard: some View {
        Button {
            track(.init(.goalEditorOpened, properties: [.goalType: .string(analyticsGoalType)]))
            if selectedGoalMode == .planned {
                showsStandaloneWorkouts = true
            } else if selectedGoalMode != .freestyle {
                isGoalChooserPresented.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedGoalMode.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(launchGoalValue)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text(launchGoalHint)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: selectedGoalMode == .freestyle ? "checkmark" : "chevron.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(theme.accentColor)
                    .frame(width: 38, height: 38)
                    .background(theme.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.1), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .disabled(selectedGoalMode == .freestyle)
        .popover(isPresented: $isGoalChooserPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            compactGoalChooser
                .presentationCompactAdaptation(.popover)
        }
    }

    private func launchRoutePreviewCard(_ route: PreparedRoute) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "map.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(theme.actionColor.gradient, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(route.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(routeDistanceLabel(route))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            Button(String(localized: "common.change", defaultValue: "Change")) {
                openRouteLibrary()
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.borderless)

            Button(role: .destructive) {
                removeSelectedRoute(route)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 32, height: 32)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "record.route.remove", defaultValue: "Remove route"))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(theme.actionColor.opacity(0.2), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.1), radius: 12, y: 5)
    }

    private var launchDock: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(LaunchWorkoutChoice.allCases) { choice in
                        launchWorkoutButton(choice)
                    }
                }
                .padding(.horizontal, 16)
            }

            HStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        setupUtilityButton(
                            title: String(localized: "record.setup.music", defaultValue: "Music"),
                            value: musicSetupValue,
                            systemImage: "music.note.list",
                            isConfigured: musicIsConfigured
                        ) {
                            trackFeatureExposure("music")
                            dismissMusicDiscoveryTip(result: "opened")
                            setupSheet = .music
                        }
                        .popover(isPresented: $showsMusicDiscoveryTip, arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(String(localized: "record.music.discovery.title", defaultValue: "Bring music on your activity"))
                                    .font(.headline)
                                Text(String(localized: "record.music.discovery.detail", defaultValue: "Tap the Music button to connect Apple Music or choose what to play."))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Button(String(localized: "record.music.discovery.dismiss", defaultValue: "Not now")) {
                                    dismissMusicDiscoveryTip(result: "dismissed")
                                }
                                .font(.subheadline.weight(.semibold))
                            }
                            .padding()
                            .frame(idealWidth: 280, alignment: .leading)
                            .presentationCompactAdaptation(.popover)
                        }

                        setupUtilityButton(
                            title: String(localized: "record.setup.live_track", defaultValue: "Live Track"),
                            value: liveTrackValue,
                            systemImage: "location.fill",
                            isConfigured: liveShareStore.isArmedForNextActivity
                        ) {
                            if safetyContactStore.defaultContact == nil {
                                showsTrustedContacts = true
                            } else {
                                liveShareStore.armForNextActivity(!liveShareStore.isArmedForNextActivity)
                            }
                        }

                        launchShoeControl

                        setupUtilityButton(
                            title: indoorOutdoorLabel,
                            value: indoorOutdoorLabel,
                            systemImage: isIndoorSession ? "building.2.fill" : "sun.max.fill",
                            isConfigured: true
                        ) {
                            isIndoorSession.toggle()
                            track(.init(.activityConfigurationChanged, properties: [
                                .changeType: .string("environment"),
                                .selectionType: .string(isIndoorSession ? "indoor" : "outdoor")
                            ]))
                        }

                        setupUtilityButton(
                            title: String(localized: "record.voice_guide.title", defaultValue: "Voice Guide"),
                            value: isVoiceGuideExplicitlyUnavailable
                                ? String(localized: "record.voice_guide.unavailable.short", defaultValue: "Unavailable")
                                : (isVoiceGuideEnabled
                                    ? String(localized: "common.on", defaultValue: "On")
                                    : String(localized: "common.off", defaultValue: "Off")),
                            systemImage: voiceGuideSpeechEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                            isConfigured: voiceGuideSpeechEnabled
                        ) {
                            setVoiceGuideEnabled(
                                isVoiceGuideExplicitlyUnavailable ? true : !isVoiceGuideEnabled
                            )
                        }
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, isEmbeddedInToday ? 16 : 0)
                }
                .frame(maxWidth: .infinity)

                if !isEmbeddedInToday {
                    Divider()
                        .frame(height: 44)

                    photoLaunchControl
                        .padding(.trailing, 16)
                }
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 16)
        .frame(height: ActivityLaunchLayout.dockHeight)
        .background(.ultraThickMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private var launchGoalPillRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SessionGoalMode.manualCases, id: \.self) { mode in
                    launchGoalPill(mode)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var contextualStartControl: some View {
        Button(action: startRecording) {
            VStack(spacing: 1) {
                Group {
                    if isStartingActivity {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.title3.weight(.black))
                            .offset(x: 1)
                    }
                }
                .frame(width: 54, height: 54)
                .foregroundStyle(.white)
                .background(theme.actionColor, in: Circle())
                .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 5))
                .shadow(color: theme.actionColor.opacity(0.28), radius: 10, y: 5)

                Text(String(localized: "record.start.short", defaultValue: "Start"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(theme.actionColor)
                    .textCase(.uppercase)
            }
        }
        .buttonStyle(.plain)
        .disabled(isStartingActivity)
        .accessibilityLabel(isStartingActivity ? String(localized: "record.start.preparing", defaultValue: "Preparing activity") : (plannedIntent ?? .freestyleRun).startLabel)
        .accessibilityHint(String(localized: "record.start.accessibility_hint", defaultValue: "Starts the prepared activity"))
    }

    private func launchWorkoutButton(_ choice: LaunchWorkoutChoice) -> some View {
        Button {
            selectWorkoutChoice(choice)
        } label: {
            VStack(spacing: 5) {
                Image(systemName: choice.systemImage)
                    .font(.body.weight(.semibold))
                Text(choice.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(choice == selectedWorkoutChoice ? Color.white : Color.primary)
            .frame(width: ActivityLaunchLayout.controlWidth, height: ActivityLaunchLayout.controlHeight)
            .background(
                choice == selectedWorkoutChoice ? theme.accentColor : Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(choice == selectedWorkoutChoice ? Color.clear : Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.title)
        .accessibilityValue(choice.accessibilityValue(
            plannedIntent: plannedWorkoutIntent,
            manualGoal: manualActivityGoal,
            unitSystem: measurementPreferences.unitSystem
        ))
        .accessibilityAddTraits(choice == selectedWorkoutChoice ? .isSelected : [])
    }

    private func launchGoalPill(_ mode: SessionGoalMode) -> some View {
        let isSelected = mode == selectedGoalMode
        return Button {
            selectLaunchMode(mode)
        } label: {
            Text(mode.pillTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .background(isSelected ? theme.accentColor : Color(.systemBackground).opacity(0.88), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(isSelected ? Color.clear : Color.primary.opacity(0.1), lineWidth: 1)
                }
                .shadow(color: .black.opacity(isSelected ? 0.12 : 0.07), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.pillTitle)
        .accessibilityValue(mode.compactValue(goal: isSelected ? manualActivityGoal : nil))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func setupUtilityButton(
        title: String,
        value: String,
        systemImage: String,
        isConfigured: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isConfigured ? Color.white : theme.accentColor)
                    .frame(width: 30, height: 30)
                    .background(isConfigured ? theme.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(width: ActivityLaunchLayout.controlWidth, height: ActivityLaunchLayout.controlHeight)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    @ViewBuilder
    private var launchShoeControl: some View {
        if gearStore.activeShoes.isEmpty {
            setupUtilityButton(
                title: String(localized: "record.setup.shoes", defaultValue: "Shoes"),
                value: String(localized: "common.none", defaultValue: "None"),
                systemImage: "shoeprints.fill",
                isConfigured: false
            ) { isAddShoePresented = true }
        } else {
            Menu {
                ForEach(gearStore.activeShoes) { shoe in
                    Button(shoe.displayName) {
                        selectedSessionShoeID = shoe.id
                        track(.init(.shoeSelected, properties: [.selectionType: .string("active_shoe")]))
                    }
                }
                Button(String(localized: "common.none", defaultValue: "None")) {
                    selectedSessionShoeID = nil
                    track(.init(.shoeSelected, properties: [.selectionType: .string("none")]))
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "shoeprints.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selectedSessionShoe == nil ? theme.accentColor : Color.white)
                        .frame(width: 30, height: 30)
                        .background(selectedSessionShoe == nil ? Color.clear : theme.accentColor, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    Text(String(localized: "record.setup.shoes", defaultValue: "Shoes"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .frame(width: ActivityLaunchLayout.controlWidth, height: ActivityLaunchLayout.controlHeight)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .accessibilityLabel(String(localized: "record.setup.shoes", defaultValue: "Shoes"))
            .accessibilityValue(selectedSessionShoe?.displayName ?? String(localized: "common.none", defaultValue: "None"))
        }
    }

    private var compactGoalChooser: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selectedGoalMode.editorTitle)
                .font(.headline)

            GoalPresetFlow(horizontalSpacing: 7, verticalSpacing: 7) {
                switch selectedGoalMode {
                case .distance:
                    ForEach(distanceGoalPresets) { preset in
                        goalPresetButton(title: preset.title, isSelected: isSelectedDistancePreset(preset.meters)) {
                            applyGoal(.distanceMeters(preset.meters))
                            isGoalChooserPresented = false
                        }
                    }
                case .time:
                    ForEach(timeGoalPresets) { preset in
                        goalPresetButton(title: preset.title, isSelected: isSelectedTimePreset(preset.seconds)) {
                            applyGoal(.timeSeconds(preset.seconds))
                            isGoalChooserPresented = false
                        }
                    }
                case .calories:
                    ForEach(calorieGoalPresets, id: \.self) { calories in
                        goalPresetButton(title: calorieGoalLabel(calories), isSelected: currentActivityGoal.targetCalories == calories) {
                            applyGoal(.calories(calories))
                            isGoalChooserPresented = false
                        }
                    }
                case .planned, .freestyle:
                    EmptyView()
                }
            }

            Button {
                let kind = selectedGoalMode.customGoalKind
                isGoalChooserPresented = false
                Task { @MainActor in
                    await Task.yield()
                    if let kind { presentCustomGoal(kind) }
                }
            } label: {
                Label(String(localized: "record.goal.custom", defaultValue: "Custom"), systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 38)
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .frame(idealWidth: 330)
    }

    private var launchGoalValue: String {
        if selectedGoalMode == .planned {
            return plannedWorkoutIntent?.title ?? String(localized: "record.goal.choose_workout", defaultValue: "Choose a workout")
        }
        if selectedGoalMode == .freestyle {
            return String(localized: "record.goal.no_target", defaultValue: "No target")
        }
        return currentActivityGoal.label(unitSystem: measurementPreferences.unitSystem)
    }

    private var launchGoalHint: String {
        switch selectedGoalMode {
        case .planned:
            return String(localized: "record.goal.tap_change_workout", defaultValue: "Tap to change workout")
        case .freestyle:
            return String(localized: "record.goal.freestyle.short_hint", defaultValue: "Start and move by feel")
        case .distance, .time, .calories:
            return String(localized: "record.goal.tap_change", defaultValue: "Tap to change")
        }
    }

    private func selectLaunchMode(_ mode: SessionGoalMode) {
        guard selectedWorkoutChoice != .planned else {
            if mode == .planned {
                selectWorkoutChoice(.planned)
            }
            return
        }
        isGoalChooserPresented = false
        selectedGoalMode = mode
        switch mode {
        case .planned:
            selectWorkoutChoice(.planned)
        case .freestyle:
            applyGoal(.freestyle)
        case .distance:
            if currentActivityGoal.targetDistanceMeters == nil {
                applyGoal(.distanceMeters(distanceGoalPresets.first?.meters ?? 5_000))
            }
        case .time:
            if currentActivityGoal.targetDurationSeconds == nil {
                applyGoal(.timeSeconds(timeGoalPresets.first?.seconds ?? 30 * 60))
            }
        case .calories:
            if currentActivityGoal.targetCalories == nil {
                applyGoal(.calories(calorieGoalPresets.first ?? 300))
            }
        }
    }

    private func selectWorkoutChoice(_ choice: LaunchWorkoutChoice) {
        isGoalChooserPresented = false
        let selectedRoute = plannedIntent?.preparedRoute
        let nextBaseIntent: SessionIntent

        switch choice {
        case .planned:
            guard let plannedWorkoutIntent else {
                showsStandaloneWorkouts = true
                return
            }
            selectedWorkoutChoice = .planned
            selectedGoalMode = .planned
            nextBaseIntent = routeFreeIntent(from: plannedWorkoutIntent)
        case .sport(let sport):
            selectedWorkoutChoice = choice
            selectedGoalMode = SessionGoalMode(goal: manualActivityGoal)
            nextBaseIntent = freestyleFallback(for: sport)
                .replacingGoal(manualActivityGoal, unitSystem: measurementPreferences.unitSystem)
        }

        if let selectedRoute {
            intentBeforeSelectedRoute = nextBaseIntent
            plannedIntent = routeIntent(selectedRoute, appliedTo: nextBaseIntent)
            if selectedRouteDistanceMeters == nil {
                selectedRouteDistanceMeters = Self.calculatePreparedRouteDistance(selectedRoute)
            }
        } else {
            plannedIntent = nextBaseIntent
            intentBeforeSelectedRoute = nil
            selectedRouteDistanceMeters = nil
        }

        track(.init(.activityConfigurationChanged, properties: [
            .changeType: .string("workout_type"),
            .selectionType: .string(choice.analyticsValue)
        ]))
    }

    private func setVoiceGuideEnabled(_ isEnabled: Bool) {
        if isEnabled, isVoiceGuideExplicitlyUnavailable {
            track(.init(.activityConfigurationChanged, properties: [
                .changeType: .string("voice_guide"),
                .selectionType: .string("unavailable")
            ]))
            showSetupToast(String(
                localized: "record.voice_guide.unavailable.message",
                defaultValue: "Voice Guide audio is temporarily unavailable."
            ))
            return
        }
        isVoiceGuideEnabled = isEnabled
        guide.setSpeechEnabled(voiceGuideSpeechEnabled)
        track(.init(.activityConfigurationChanged, properties: [
            .changeType: .string("voice_guide"),
            .selectionType: .string(isEnabled ? "enabled" : "disabled")
        ]))
        guard isEnabled else { return }
        Task { await guideCatalog.refreshServerCatalog() }
    }

    private var photoLaunchControl: some View {
        Button(action: handlePreActivityPhotoAction) {
            ZStack(alignment: .bottomTrailing) {
                if let photo = preActivityPhoto {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(theme.actionColor, lineWidth: 2))

                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 17, height: 17)
                        .background(Color.green, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .offset(x: 2, y: 2)
                } else {
                    Circle()
                        .fill(theme.actionColor)
                        .frame(width: 52, height: 52)
                        .overlay {
                            Image(systemName: "camera.fill")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                }
            }
            .frame(width: 56, height: ActivityLaunchLayout.controlHeight)
            .contentShape(Rectangle())
            .shadow(color: theme.actionColor.opacity(0.24), radius: 7, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "record.photo.control", defaultValue: "Photo"))
        .accessibilityValue(photoAccessibilityValue)
    }

    private func handlePreActivityPhotoAction() {
        if preActivityPhoto == nil {
            track(.init(.photoCaptureAttempted, properties: [.sourceType: .string("pre_activity_camera")]))
            isPreActivityCameraPresented = true
        } else {
            track(.init(.photoPreviewed, properties: [.sourceType: .string("pre_activity")]))
            isPreActivityPhotoPreviewPresented = true
        }
    }

    private func handlePreActivityPhotoRequest() {
        guard isEmbeddedInToday,
              isVisible,
              pendingActivity == nil,
              recorder.state == .idle,
              !showCamera
        else { return }
        handlePreActivityPhotoAction()
    }

    private func handleRouteSelectionRequest() {
        guard isEmbeddedInToday,
              isVisible,
              pendingActivity == nil,
              recorder.state == .idle,
              !showCamera
        else { return }
        openRouteLibrary()
    }

    private func handleRouteRemovalRequest() {
        guard isEmbeddedInToday,
              isVisible,
              pendingActivity == nil,
              recorder.state == .idle,
              !showCamera,
              let route = plannedIntent?.preparedRoute
        else { return }
        removeSelectedRoute(route)
    }

    private func launchUtilityButton(
        title: String,
        systemImage: String,
        isConfigured: Bool,
        accessibilityValue: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                launchUtilityIcon(systemImage: systemImage, isConfigured: isConfigured)
                if isConfigured { configuredBadge }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
    }

    private func launchUtilityIcon(systemImage: String, isConfigured: Bool) -> some View {
        Image(systemName: systemImage)
            .font(.headline.weight(.bold))
            .foregroundStyle(isConfigured ? Color.white : Color.orange)
            .frame(width: 52, height: 52)
            .background(isConfigured ? Color.orange : Color(.secondarySystemBackground), in: Circle())
    }

    private var configuredBadge: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 8, weight: .black))
            .foregroundStyle(.white)
            .frame(width: 17, height: 17)
            .background(Color.green, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
    }

    @ViewBuilder
    private var shoeLaunchControl: some View {
        if gearStore.activeShoes.isEmpty {
            launchUtilityButton(
                title: String(localized: "record.setup.shoes", defaultValue: "Shoes"),
                systemImage: "shoeprints.fill",
                isConfigured: false,
                accessibilityValue: String(localized: "record.shoes.none_accessibility", defaultValue: "No shoes configured")
            ) { isAddShoePresented = true }
        } else {
            Menu {
                ForEach(gearStore.activeShoes) { shoe in
                    Button {
                        selectedSessionShoeID = shoe.id
                        track(.init(.shoeSelected, properties: [.selectionType: .string("active_shoe")]))
                    } label: {
                        Text(shoe.displayName)
                    }
                }
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    launchUtilityIcon(systemImage: "shoeprints.fill", isConfigured: selectedSessionShoe != nil)
                    if selectedSessionShoe != nil { configuredBadge }
                }
            }
            .accessibilityLabel(String(localized: "record.setup.shoes", defaultValue: "Shoes"))
            .accessibilityValue(selectedSessionShoe?.displayName ?? String(localized: "common.none", defaultValue: "None"))
        }
    }

    private func confirmationView(for intent: SessionIntent) -> some View {
        VStack(spacing: 14) {
            VStack(spacing: 8) {
                Text(intent.title)
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)
                Text(intent.detail)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 48)

            VStack(alignment: .leading) {
                Text(intent.guideLine)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: startSetupCardCornerRadius, style: .continuous))

            VStack(spacing: 14) {
                voiceGuideCard

                if intent.workoutSteps.isEmpty {
                    sessionGoalCard(for: intent)
                } else {
                    plannedWorkoutCard(for: intent)
                }

                routeSetupCard

                Button {
                    setupSheet = .more
                } label: {
                    Label(String(localized: "record.setup.more_options", defaultValue: "More options"), systemImage: "ellipsis.circle")
                        .font(.subheadline.weight(.semibold))
                }

                Button(intent.workoutSteps.isEmpty ? "Change activity" : "Choose a different activity") {
                    onCloseRequest?(false)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            }

        }
    }

    private var voiceGuideCard: some View {
        Toggle(isOn: Binding(
            get: { voiceGuideSpeechEnabled },
            set: { isVoiceGuideEnabled = $0 }
        )) {
            VStack(alignment: .leading, spacing: 3) {
                Label(String(localized: "record.voice_guide.title", defaultValue: "Voice Guide"), systemImage: "waveform.circle")
                    .font(.subheadline.weight(.semibold))
                Text(isVoiceGuideExplicitlyUnavailable
                    ? String(
                        localized: "record.voice_guide.unavailable.message",
                        defaultValue: "Voice Guide audio is temporarily unavailable."
                    )
                    : String(localized: "record.voice_guide.detail", defaultValue: "Hear countdowns, progress updates, and live coaching."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(isVoiceGuideExplicitlyUnavailable)
        .tint(.orange)
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: startSetupCardCornerRadius, style: .continuous))
        .onChange(of: isVoiceGuideEnabled) { _, isEnabled in
            guide.setSpeechEnabled(voiceGuideSpeechEnabled)
            track(.init(.activityConfigurationChanged, properties: [
                .changeType: .string("voice_guide"),
                .selectionType: .string(isEnabled ? "enabled" : "disabled")
            ]))
            guard isEnabled else { return }
            Task { await guideCatalog.refreshServerCatalog() }
        }
    }

    @ViewBuilder
    private func setupSheetView(_ sheet: ActivitySetupSheet) -> some View {
        NavigationStack {
            Group {
                switch sheet {
                case .goal:
                    ScrollView { goalSetupChoices.padding() }
                case .music:
                    ScrollView { musicSetupChoices.padding() }
                case .more:
                    moreSetupSheet
                }
            }
            .navigationTitle(sheet.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.done", defaultValue: "Done")) { setupSheet = nil }
                }
            }
        }
    }

    private var musicSetupChoices: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                musicStore.disableMusic()
                track(.init(.musicQuickPickSelected, properties: [.selectionType: .string("no_music")]))
            } label: {
                setupChoiceRow(
                    title: String(localized: "record.music.none", defaultValue: "No music"),
                    detail: String(localized: "record.music.none.detail", defaultValue: "Start without a soundtrack"),
                    systemImage: "music.note.slash",
                    isSelected: musicStore.isMusicDisabled
                )
            }
            .buttonStyle(.plain)

            Divider().padding(.vertical, 4)

            if musicStore.hasDeveloperTokenError {
                Label(String(localized: "session.music.unavailable", defaultValue: "Music unavailable"), systemImage: "music.note.slash")
                    .foregroundStyle(.secondary)
            } else if let lastErrorMessage = musicStore.lastErrorMessage {
                Text(lastErrorMessage).font(.caption).foregroundStyle(.orange)
            }
            if let troubleshootingLine = musicStore.troubleshootingLine {
                Text(troubleshootingLine).font(.caption).foregroundStyle(.secondary)
            }
            if musicStore.canShowQuickPicks, !musicStore.quickPicks.isEmpty {
                Text(String(localized: "record.music.suggested", defaultValue: "Suggested for this workout"))
                    .font(.headline)
                ForEach(musicStore.quickPicks) { quickPick in
                    Button {
                        musicStore.selectQuickPick(quickPick)
                        track(.init(.musicQuickPickSelected, properties: [.selectionType: .string("quick_pick")]))
                    } label: {
                        setupChoiceRow(title: quickPick.title, detail: quickPick.subtitle, systemImage: quickPick.symbolName, isSelected: musicStore.selectedQuickPickID == quickPick.id)
                    }
                    .buttonStyle(.plain)
                }

                Divider().padding(.vertical, 4)
                Text(String(localized: "record.music.choose", defaultValue: "Choose your music"))
                    .font(.headline)
                Picker(String(localized: "record.music.category", defaultValue: "Music category"), selection: $musicSearchCategory) {
                    Text(String(localized: "record.music.songs", defaultValue: "Songs")).tag(MusicSearchCategory.songs)
                    Text(String(localized: "record.music.albums", defaultValue: "Albums")).tag(MusicSearchCategory.albums)
                    Text(String(localized: "record.music.playlists", defaultValue: "Playlists")).tag(MusicSearchCategory.playlists)
                }
                .pickerStyle(.segmented)
                .onChange(of: musicSearchCategory) { _, category in
                    guard musicStore.searchResults(for: category).isEmpty,
                          !musicStore.isSearching(category)
                    else { return }
                    searchMusic()
                }
                HStack {
                    TextField(String(localized: "record.music.search", defaultValue: "Search Apple Music"), text: $musicSearchText)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.search)
                        .onSubmit { searchMusic() }
                    Button { searchMusic() } label: {
                        if musicStore.isSearching { ProgressView() } else { Image(systemName: "magnifyingglass") }
                    }
                    .buttonStyle(.bordered)
                    .disabled(musicSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || musicStore.isSearching)
                    .accessibilityLabel(String(localized: "record.music.search.action", defaultValue: "Search music"))
                }
                musicPlaybackOptions
                ForEach(musicStore.searchResults(for: musicSearchCategory)) { item in
                    Button { musicStore.toggleCustomSelection(item) } label: {
                        setupChoiceRow(
                            title: item.title,
                            detail: item.subtitle,
                            systemImage: musicSearchSymbol(for: item.category),
                            isSelected: musicStore.selectedCustomItems.contains(item)
                        )
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button {
                    if !musicStore.isConnected { track(.init(.musicAuthorizationRequested)) }
                    Task { await musicStore.performPrimaryAction() }
                } label: {
                    setupChoiceRow(title: musicStore.primaryActionTitle, detail: musicStore.musicSummaryLine, systemImage: "music.note.list", isSelected: musicIsConfigured)
                }
                .buttonStyle(.plain)
                .disabled(!musicStore.isPrimaryActionEnabled)
            }
        }
    }

    private var moreSetupSheet: some View {
        List {
#if DEBUG
            Section(String(localized: "run.simulation.testing.section", defaultValue: "Testing")) {
                Toggle(isOn: Binding(
                    get: { isRunSimulationEnabled },
                    set: { configureHarvestRunSimulation(enabled: $0) }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label(
                            String(localized: "run.simulation.setup.title", defaultValue: "Simulated Harvest Run"),
                            systemImage: "figure.run.circle"
                        )
                        Text(String(
                            localized: "run.simulation.setup.detail",
                            defaultValue: "Use the Redmond route with adjustable speed and time. No GPS movement is required."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .tint(.orange)
                .disabled(recorder.state != .idle)
            }
#endif
            Section(String(localized: "guide.challenge.section.title", defaultValue: "Optional live challenge")) {
                ForEach(LiveGuidanceChallenge.allCases) { challenge in
                    Button {
                        selectedGuidanceChallenge = challenge
                        track(.init(.liveGuidanceChallengeSelected, properties: [
                            .selectionType: .string(challenge.rawValue)
                        ]))
                    } label: {
                        setupChoiceRow(
                            title: challenge.displayName,
                            detail: challenge.detail,
                            systemImage: challenge == .off ? "minus.circle" : "bolt.fill",
                            isSelected: selectedGuidanceChallenge == challenge
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            Section {
                VStack(alignment: .leading, spacing: 12) { liveGroupSetup }
                    .padding(.vertical, 6)
            }
            Section(String(localized: "record.environment.title", defaultValue: "Indoor / Outdoor")) {
                Button { isIndoorSession = false } label: {
                    setupChoiceRow(title: String(localized: "record.environment.outdoor", defaultValue: "Outdoor"), detail: "", systemImage: "sun.max.fill", isSelected: !isIndoorSession)
                }
                Button { isIndoorSession = true } label: {
                    setupChoiceRow(title: String(localized: "record.environment.indoor", defaultValue: "Indoor"), detail: "", systemImage: "figure.run.treadmill", isSelected: isIndoorSession)
                }
            }
        }
    }

    private func setupChoiceRow(title: String, detail: String, systemImage: String, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage).foregroundStyle(.orange).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if isSelected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.orange) }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private var musicSetupValue: String {
        if musicStore.playback.isPlaying { return musicStore.playback.title }
        if let first = musicStore.selectedCustomItems.first {
            return musicStore.selectedCustomItems.count > 1
                ? String(localized: "record.music.song_count", defaultValue: "\(musicStore.selectedCustomItems.count) songs")
                : first.title
        }
        return musicStore.selectedQuickPick?.title ?? String(localized: "common.off", defaultValue: "Off")
    }
    private var musicIsConfigured: Bool { musicStore.selectedQuickPick != nil || !musicStore.selectedCustomItems.isEmpty || musicStore.playback.isPlaying }

    private var musicSelectionSummary: String {
        guard let first = musicStore.selectedCustomItems.first else {
            return musicStore.selectedQuickPick?.title
                ?? String(localized: "record.music.choose_first", defaultValue: "Choose music to enable playback options")
        }
        if musicStore.selectedCustomItems.count == 1 { return first.title }
        return String(localized: "record.music.selected_count", defaultValue: "\(musicStore.selectedCustomItems.count) songs selected")
    }

    private var musicPlaybackOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "record.music.playback", defaultValue: "Playback"))
                    .font(.subheadline.weight(.semibold))
                Text(musicSelectionSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
            }
            HStack(spacing: 8) {
                Toggle(isOn: $musicStore.repeatsQueue) {
                    Label(String(localized: "record.music.repeat.short", defaultValue: "Repeat"), systemImage: "repeat")
                }
                .accessibilityLabel(String(localized: "record.music.repeat", defaultValue: "Repeat during workout"))
                Toggle(isOn: $musicStore.shufflesQueue) {
                    Label(String(localized: "record.music.shuffle.short", defaultValue: "Shuffle"), systemImage: "shuffle")
                }
                .accessibilityLabel(String(localized: "record.music.shuffle", defaultValue: "Shuffle songs"))
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)
            .tint(.orange)
            .font(.caption.weight(.semibold))
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .disabled(!musicIsConfigured)
    }

    private func musicSearchSymbol(for category: MusicSearchCategory) -> String {
        switch category {
        case .songs: "music.note"
        case .albums: "square.stack"
        case .playlists: "music.note.list"
        }
    }

    private func searchMusic() {
        Task { await musicStore.searchCatalog(musicSearchText, category: musicSearchCategory) }
    }

    private func prepareMusicPicker() {
        if musicSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let intent = plannedIntent ?? .freestyleRun
            let text = "\(intent.title) \(intent.detail)".lowercased()
            if text.contains("easy") || text.contains("recovery") || text.contains("walk") {
                musicSearchText = String(localized: "record.music.search.recovery", defaultValue: "chill recovery workout")
            } else if text.contains("tempo") || text.contains("threshold") || text.contains("interval") || text.contains("speed") {
                musicSearchText = String(localized: "record.music.search.speed", defaultValue: "electronic running workout")
            } else {
                musicSearchText = String(localized: "record.music.search.default", defaultValue: "upbeat workout")
            }
        }
        Task { await musicStore.preloadCatalog(musicSearchText) }
    }

    private func presentMusicDiscoveryTipIfNeeded() {
        guard !didPresentMusicDiscoveryTip,
              isVisible,
              !showCamera,
              musicStore.snapshot.connectionState == .notConnected
                || musicStore.snapshot.connectionState == .denied
                || musicStore.needsPlaybackSetup
        else { return }
        didPresentMusicDiscoveryTip = true
        showsMusicDiscoveryTip = true
        trackFeatureExposure("music_discovery_tip")
    }

    private func dismissMusicDiscoveryTip(result: String) {
        guard showsMusicDiscoveryTip else { return }
        showsMusicDiscoveryTip = false
        track(.init(.activityConfigurationChanged, properties: [
            .changeType: .string("music_discovery_tip"),
            .selectionType: .string(result)
        ]))
    }

    private func applyWorkoutMusicSuggestion() {
        let intent = plannedIntent ?? .freestyleRun
        musicStore.applyWorkoutSuggestion(title: intent.title, detail: intent.detail, sport: intent.sport)
    }
    private var liveTrackValue: String { liveShareStore.isArmedForNextActivity ? (safetyContactStore.defaultContact?.name ?? String(localized: "record.live_track.on", defaultValue: "On")) : String(localized: "common.off", defaultValue: "Off") }
    private var indoorOutdoorLabel: String {
        isIndoorSession
            ? String(localized: "record.setup.indoor", defaultValue: "Indoor")
            : String(localized: "record.setup.outdoor", defaultValue: "Outdoor")
    }
    private var photoAccessibilityValue: String { preActivityPhoto == nil ? String(localized: "record.photo.not_added", defaultValue: "No photo added") : String(localized: "record.photo.added", defaultValue: "Photo added") }

    private func track(_ event: ProductAnalyticsEvent) {
        guard let analyticsManager else { return }
        Task { await analyticsManager.track(event) }
    }

    private var isVoiceGuideExplicitlyUnavailable: Bool {
        guideCatalog.liveCoachAudioMode == .disabled
    }

    private var voiceGuideSpeechEnabled: Bool {
        isVoiceGuideEnabled && !isVoiceGuideExplicitlyUnavailable
    }

    private func trackGuidanceEvent(_ event: LiveGuidanceTelemetryEvent) {
        switch event {
        case .momentDetected(let type, let contract):
            track(.init(.liveGuidanceMomentDetected, properties: [
                .momentType: .string(type.rawValue),
                .coachingContract: .string(contract.rawValue)
            ]))
        case .cueSpoken(let type, let contract):
            track(.init(.liveGuidanceCueSpoken, properties: [
                .momentType: .string(type.rawValue),
                .coachingContract: .string(contract.rawValue)
            ]))
        case .cueEvaluated(let type, let outcome):
            track(.init(.liveGuidanceCueEvaluated, properties: [
                .momentType: .string(type.rawValue),
                .result: .string(outcome.rawValue)
            ]))
        case .providerResult(let source, let result, let mode, let accessReason, let latency):
            track(.init(.liveGuidanceProviderResult, properties: [
                .sourceType: .string(source.rawValue),
                .result: .string(result.rawValue),
                .audioMode: .string(mode.rawValue),
                .accessReason: .string(accessReason.rawValue),
                .latencyBucket: .string(latency.rawValue)
            ]))
        }
    }

    private func handleGuidanceFeedback(_ feedback: LiveGuidanceFeedback) {
        guideCatalog.recordGuidanceFeedback(feedback)
        track(.init(.liveGuidanceFeedbackSubmitted, properties: [
            .selectionType: .string(feedback.rawValue),
            .cueCountBucket: .string(ProductAnalyticsBucket.count(pendingActivity?.guidanceReport.spokenCueCount ?? 0))
        ]))
    }

    private func trackSetupAndFeatureExposureIfNeeded() {
        guard !didTrackSetupView else { return }
        didTrackSetupView = true
        track(.init(.activitySetupViewed, properties: [.entrySource: .string(analyticsEntrySource)]))
        ["music", "routes", "shoes", "photos", "group_run"].forEach(trackFeatureExposure)
    }

    private func trackFeatureExposure(_ feature: String) {
        guard exposedFeatures.insert(feature).inserted else { return }
        track(.init(.featureExposed, properties: [.feature: .string(feature)]))
    }

    private func trackRecordingStateTransition(to state: RecordingState) {
        defer { previousRecorderState = state }
        guard state != previousRecorderState else { return }
        switch (previousRecorderState, state) {
        case (.active, .paused):
            track(.init(.activityPaused))
        case (.paused, .active):
            track(.init(.activityResumed))
        default:
            break
        }
    }

    private func trackGoalProgressIfNeeded(_ snapshot: ActiveSessionSnapshot) {
        guard recorder.state != .idle, let ratio = goalCompletionRatio(
            distanceMeters: snapshot.distanceMeters,
            durationSeconds: snapshot.elapsedSeconds
        ) else { return }

        for threshold in [25, 50, 75, 100]
        where ratio * 100 >= Double(threshold) && reachedGoalThresholds.insert(threshold).inserted {
            track(.init(.goalProgressReached, properties: [
                .goalType: .string(analyticsGoalType),
                .progressPercent: .integer(threshold)
            ]))
        }
    }

    private func handleRouteGuidanceEvent(_ event: RouteGuidanceEvent) {
        guard let route = (activeIntent ?? plannedIntent)?.preparedRoute else { return }
        switch event {
        case .progressReached(let percent):
            track(.init(.routeGuidanceProgressReached, properties: [
                .sourceType: .string(route.source.rawValue),
                .direction: .string(route.direction.rawValue),
                .progressPercent: .integer(percent)
            ]))
        case .deviated(let distanceMeters):
            let message = String(localized: "route.guidance.off_route", defaultValue: "You’re off the selected route. Head back toward the highlighted line.")
            guide.announceRouteGuidance(message, priority: .caution, semanticCueKey: "route.caution")
            track(.init(.routeDeviationDetected, properties: [
                .distanceBucket: .string(ProductAnalyticsBucket.distance(meters: distanceMeters))
            ]))
        case .rejoined:
            let message = String(localized: "route.guidance.rejoined", defaultValue: "You’re back on the selected route.")
            guide.announceRouteGuidance(message, priority: .advisory, semanticCueKey: "route.rejoin")
            track(.init(.routeRejoined))
        case .wrongWay:
            let message = String(localized: "route.guidance.wrong_way", defaultValue: "You may be going the wrong way. Turn back toward the highlighted route.")
            guide.announceRouteGuidance(message, priority: .caution, semanticCueKey: "route.wrong_way")
            track(.init(.routeWrongWayDetected, properties: [
                .sourceType: .string(route.source.rawValue),
                .direction: .string(route.direction.rawValue)
            ]))
        case .arrival:
            let message = String(localized: "route.guidance.arrival", defaultValue: "Route complete. Nice work.")
            guide.announceRouteGuidance(message, priority: .arrival, semanticCueKey: "route.arrival")
            track(.init(.routeGuidanceArrived, properties: [
                .sourceType: .string(route.source.rawValue),
                .direction: .string(route.direction.rawValue)
            ]))
        }
    }

    private func coarseRouteProgressPercent(_ fraction: Double) -> Int {
        let percent = max(0, min(100, fraction.isFinite ? fraction * 100 : 0))
        return [0, 25, 50, 75, 100].last(where: { Double($0) <= percent }) ?? 0
    }

    private var activityConfigurationProperties: [ProductPropertyKey: AnalyticsValue] {
        [
            .entrySource: .string(analyticsEntrySource),
            .goalType: .string(analyticsGoalType),
            .targetBucket: .string(analyticsTargetBucket(for: (activeIntent ?? plannedIntent ?? .freestyleRun).activityGoal)),
            .musicEnabled: .boolean(musicWasConfigured),
            .routeSelected: .boolean(activeIntent?.preparedRoute != nil),
            .shoeSelected: .boolean(selectedSessionShoe != nil),
            .preRunPhotoAdded: .boolean(preActivityPhoto != nil),
            .groupRunEnabled: .boolean(liveGroupStore.isSharing),
            .liveShareEnabled: .boolean(liveShareStore.isArmedForNextActivity),
            .indoor: .boolean(isIndoorSession),
            .voiceGuideEnabled: .boolean(voiceGuideSpeechEnabled),
            .participantCountBucket: .string(ProductAnalyticsBucket.count(liveGroupStore.participants.count))
        ]
    }

    private func outcomeProperties(for summary: ActivitySummary) -> [ProductPropertyKey: AnalyticsValue] {
        [
            .durationBucket: .string(ProductAnalyticsBucket.duration(seconds: summary.durationSecs)),
            .distanceBucket: .string(ProductAnalyticsBucket.distance(meters: summary.distanceM)),
            .goalCompletionBucket: .string(ProductAnalyticsBucket.completion(goalCompletionRatio(
                distanceMeters: summary.distanceM,
                durationSeconds: summary.durationSecs
            )))
        ]
    }

    private var analyticsEntrySource: String {
        let intent = activeIntent ?? plannedIntent ?? .freestyleRun
        if intent.activityEvent != nil { return "activity_event" }
        if intent.preparedRoute != nil { return "route" }
        if isEmbeddedInToday { return "today" }
        if !intent.workoutSteps.isEmpty { return "planned_workout" }
        if intent.id == SessionIntent.freestyleRun.id { return "quick_run" }
        return "prepared_activity"
    }

    private var analyticsGoalType: String {
        let intent = activeIntent ?? plannedIntent ?? .freestyleRun
        if !intent.workoutSteps.isEmpty { return "workout" }
        switch intent.activityGoal {
        case .freestyle: return "freestyle"
        case .distanceMeters: return "distance"
        case .timeSeconds: return "time"
        case .calories: return "calories"
        }
    }

    private var musicWasConfigured: Bool {
        musicStore.isConnected && (musicStore.selectedQuickPick != nil || !musicStore.selectedCustomItems.isEmpty)
    }

    private func analyticsTargetBucket(for goal: ActivityGoal) -> String {
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

    private func goalCompletionRatio(distanceMeters: Double, durationSeconds: Int) -> Double? {
        let goal = (activeIntent ?? plannedIntent ?? .freestyleRun).activityGoal
        if let target = goal.targetDistanceMeters, target > 0 { return distanceMeters / target }
        if let target = goal.targetDurationSeconds, target > 0 { return Double(durationSeconds) / Double(target) }
        if let target = goal.targetCalories, target > 0,
           let calories = estimatedLiveEnergyKilocalories(distanceMeters: distanceMeters, durationSeconds: durationSeconds) {
            return calories / Double(target)
        }
        return nil
    }

    private func estimatedLiveEnergyKilocalories(distanceMeters: Double, durationSeconds: Int) -> Double? {
        guard let weight = onboardingStore.bodyProfile.weightKilograms, weight > 0, durationSeconds > 0 else { return nil }
        switch (activeIntent ?? plannedIntent ?? .freestyleRun).sport {
        case .run:
            guard distanceMeters > 0 else { return nil }
            return weight * (distanceMeters / 1_000)
        case .bike:
            return 8 * weight * (Double(durationSeconds) / 3_600)
        case .walk:
            return 3.5 * weight * (Double(durationSeconds) / 3_600)
        case .hike:
            return 6 * weight * (Double(durationSeconds) / 3_600)
        case .swim:
            return 6 * weight * (Double(durationSeconds) / 3_600)
        }
    }

    private func preparedRouteDistance(_ route: PreparedRoute) -> Double {
        if let selectedRoute = plannedIntent?.preparedRoute,
           selectedRoute.id == route.id,
           selectedRoute.source == route.source,
           let selectedRouteDistanceMeters {
            return selectedRouteDistanceMeters
        }
        return Self.calculatePreparedRouteDistance(route)
    }

    nonisolated private static func calculatePreparedRouteDistance(_ route: PreparedRoute) -> Double {
        zip(route.points, route.points.dropFirst()).reduce(0) { total, pair in
            let start = CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
            let end = CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude)
            return total + start.distance(from: end)
        }
    }

    private func showSetupToast(_ message: String?) {
        guard let message, !message.isEmpty else { return }
        setupToastTask?.cancel()
        withAnimation { setupToastMessage = message }
        setupToastTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run { withAnimation { setupToastMessage = nil } }
        }
    }

    private var preActivityPhotoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let photo = preActivityPhoto {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                HStack(spacing: 10) {
                    Button {
                        track(.init(.photoCaptureAttempted, properties: [.sourceType: .string("pre_activity_camera")]))
                        isPreActivityCameraPresented = true
                    } label: {
                        Label(String(localized: "record.photo.retake", defaultValue: "Retake"), systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                    }

                    Button(role: .destructive) {
                        track(.init(.photoRemoved, properties: [.sourceType: .string("pre_activity")]))
                        removePreActivityPhoto()
                    } label: {
                        Label(String(localized: "record.photo.remove", defaultValue: "Remove"), systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
            } else {
                HStack(spacing: 12) {
                    Button {
                        track(.init(.photoCaptureAttempted, properties: [.sourceType: .string("pre_activity_camera")]))
                        isPreActivityCameraPresented = true
                    } label: {
                        Label(preActivityPhotoActionTitle, systemImage: "camera.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)

                    PhotosPicker(selection: $selectedPreActivityPhotoItem, matching: .images) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.headline)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(String(localized: "record.photo.choose", defaultValue: "Choose a photo"))
                }

                Text(String(localized: "record.photo.optional_detail", defaultValue: "Optional — add a photo before you start."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: startSetupCardCornerRadius, style: .continuous))
    }

    private var preActivityPhotoPreview: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let photo = preActivityPhoto {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Label(
                        String(localized: "record.photo.added", defaultValue: "Photo added"),
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.headline)
                    .foregroundStyle(.green)

                    HStack(spacing: 12) {
                        Button {
                            isPreActivityPhotoPreviewPresented = false
                            track(.init(.photoCaptureAttempted, properties: [.sourceType: .string("pre_activity_camera")]))
                            DispatchQueue.main.async { isPreActivityCameraPresented = true }
                        } label: {
                            Label(String(localized: "record.photo.retake", defaultValue: "Retake"), systemImage: "camera.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)

                        Button(role: .destructive) {
                            track(.init(.photoRemoved, properties: [.sourceType: .string("pre_activity")]))
                            removePreActivityPhoto()
                            isPreActivityPhotoPreviewPresented = false
                        } label: {
                            Label(String(localized: "record.photo.remove", defaultValue: "Remove"), systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(20)
            .navigationTitle(String(localized: "record.photo.preview", defaultValue: "Activity photo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.done", defaultValue: "Done")) {
                        isPreActivityPhotoPreviewPresented = false
                    }
                }
            }
        }
    }

    private var preActivityPhotoActionTitle: String {
        if liveGroupStore.isSharing {
            return String(localized: "record.photo.take_group", defaultValue: "Take group photo")
        }
        return String(localized: "record.photo.take", defaultValue: "Take photo")
    }

    private var preActivityPhoto: UIImage? {
        capturedPhotos.last(where: { $0.1.captureContext == .preActivity })?.0
    }

    private func restoreInterruptedPhotosIfNeeded() {
        guard recorder.recoveredSession, !didRestoreSessionPhotos else { return }
        didRestoreSessionPhotos = true
        let restoredPhotos = ActiveSessionPhotoJournal.load()
        guard !restoredPhotos.isEmpty else { return }
        capturedPhotos = restoredPhotos
        track(.init(.activityPhotoRecovery, properties: [
            .countBucket: .string(ProductAnalyticsBucket.count(restoredPhotos.count)),
            .preRunPhotoAdded: .boolean(
                restoredPhotos.contains { $0.1.captureContext == .preActivity }
            )
        ]))
    }

    private func replacePreActivityPhoto(with image: UIImage) {
        removePreActivityPhoto()
        let coordinate = recorder.locationManager.location?.coordinate
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
        capturedPhotos.append(photo)
        ActiveSessionPhotoJournal.append(photo)
        track(.init(.photoCaptured, properties: [
            .sourceType: .string("pre_activity"),
            .locationAttached: .boolean(coordinate != nil)
        ]))
        onPreActivityPhotoChange?(image)
    }

    private func removePreActivityPhoto() {
        capturedPhotos.removeAll { $0.1.captureContext == .preActivity }
        ActiveSessionPhotoJournal.removePreActivityPhotos()
        onPreActivityPhotoChange?(nil)
    }

    private var sessionOptionsCard: some View {
        DisclosureGroup(isExpanded: $isSessionOptionsExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                setupOptionButton(
                    title: "Live",
                    subtitle: liveShareStore.isArmedForNextActivity ? "Sharing" : "Off",
                    systemImage: "location.circle.fill",
                    isSelected: liveShareStore.isArmedForNextActivity
                ) {
                    liveShareStore.armForNextActivity(!liveShareStore.isArmedForNextActivity)
                }
                .accessibilityLabel(liveShareStore.isArmedForNextActivity ? "Turn off live sharing" : "Turn on live sharing")

                setupOptionButton(
                    title: "Treadmill",
                    subtitle: isIndoorSession ? "Indoor" : "Outdoor",
                    systemImage: "figure.run.treadmill",
                    isSelected: isIndoorSession
                ) {
                    isIndoorSession.toggle()
                }
                .accessibilityLabel(isIndoorSession ? "Turn off treadmill mode" : "Turn on treadmill mode")
                }

                Divider()

                gearSetupMenu

            if liveShareStore.isArmedForNextActivity {
                Label(
                    safetyContactStore.defaultContact.map { "Recipient: \($0.name) (\($0.deliveryChannel.title) stub + Share Sheet)" } ?? "Recipient: choose in Share Sheet",
                    systemImage: "person.crop.circle.badge.checkmark"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            if let message = liveShareStore.lastErrorMessage {
                Text(message)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
                Divider()
                liveGroupSetup
                if let message = liveGroupStore.lastErrorMessage {
                    Text(message)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            .padding(.top, 12)
        } label: {
            compactSetupLabel(
                title: "Run options",
                value: sessionOptionsSummary,
                systemImage: "slider.horizontal.3"
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: startSetupCardCornerRadius, style: .continuous))
    }

    private var liveGroupSetup: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Label(String(localized: "record.group.title", defaultValue: "Group run"), systemImage: "person.2.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(liveGroupStore.isSharing ? liveGroupStore.displayTitle : "Create or join a group run")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                Spacer()
                Text(liveGroupStore.statusSummary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if liveGroupStore.isSharing {
                liveGroupParticipantDisclosure

                HStack(spacing: 10) {
                    Button {
                        Task {
                            track(.init(.groupRunInviteShared, properties: [
                                .participantCountBucket: .string(ProductAnalyticsBucket.count(liveGroupStore.participants.count))
                            ]))
                            guard let presentation = liveGroupStore.invitePresentation(intent: plannedIntent) else { return }
                            await SystemSharePresenter.present(activityItems: presentation.activityItems)
                        }
                    } label: {
                        Label(String(localized: "common.invite", defaultValue: "Invite"), systemImage: "square.and.arrow.up")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(Color(.tertiarySystemBackground), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(role: .destructive) {
                        liveGroupStore.stopFromManagementControl()
                    } label: {
                        Label(liveGroupStore.activeSession?.isCreatedByCurrentUser == true ? "End" : "Leave", systemImage: "xmark")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(Color(.tertiarySystemBackground), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            } else {
                HStack(spacing: 10) {
                    Button {
                        Task {
                            track(.init(.groupRunCreateAttempted))
                            if let presentation = await liveGroupStore.createGroup(intent: plannedIntent) {
                                track(.init(.groupRunCreated, properties: [
                                    .participantCountBucket: .string(ProductAnalyticsBucket.count(liveGroupStore.participants.count))
                                ]))
                                await SystemSharePresenter.present(activityItems: presentation.activityItems)
                            }
                        }
                    } label: {
                        Label(liveGroupStore.isCreating ? "Creating..." : "Create", systemImage: "plus")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(Color(.tertiarySystemBackground), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(liveGroupStore.isCreating)

                    Button {
                        groupInviteText = ""
                        trackFeatureExposure("group_run")
                        isGroupJoinAlertPresented = true
                    } label: {
                        Label(liveGroupStore.isJoining ? "Joining..." : "Join", systemImage: "link")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(Color(.tertiarySystemBackground), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(liveGroupStore.isJoining)
                }
            }
        }
    }

    private var liveGroupParticipantDisclosure: some View {
        DisclosureGroup(isExpanded: $isGroupParticipantsExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(liveGroupStore.participants) { participant in
                    HStack(spacing: 10) {
                        Text(participant.initials)
                            .font(.caption.weight(.black))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(participant.isCurrentUser ? Color.orange : Color.blue))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(participant.isCurrentUser ? "You" : participant.displayName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(groupParticipantStatus(participant))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            Text(liveGroupStore.participants.isEmpty ? "Participants" : "Participants (\(liveGroupStore.participants.count))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .tint(.secondary)
    }

    private func groupParticipantStatus(_ participant: LiveGroupParticipant) -> String {
        guard let lastLocationAt = participant.lastLocationAt else {
            return participant.statusLabel
        }
        let seconds = max(0, Int(Date().timeIntervalSince(lastLocationAt)))
        let age = seconds < 60 ? "\(seconds)s ago" : "\(seconds / 60)m ago"
        return participant.isFresh ? "Live - \(age)" : "\(participant.statusLabel) - \(age)"
    }

    private func setupOptionButton(
        title: String,
        subtitle: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(isSelected ? .white : .orange)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? .white : .primary)
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isSelected ? .white.opacity(0.82) : .secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 54)
            .background(isSelected ? Color.orange : Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var gearSetupMenu: some View {
        if gearStore.activeShoes.isEmpty {
            Button {
                isAddShoePresented = true
            } label: {
                compactSetupLabel(title: "Shoes", value: "Add shoes", systemImage: "shoeprints.fill")
            }
            .buttonStyle(.plain)
        } else {
            Menu {
                ForEach(gearStore.activeShoes) { shoe in
                    Button {
                        selectedSessionShoeID = shoe.id
                        track(.init(.shoeSelected, properties: [.selectionType: .string("active_shoe")]))
                    } label: {
                        Text(shoe.displayName)
                    }
                }
            } label: {
                compactSetupLabel(title: "Shoes", value: selectedSessionShoe?.displayName ?? "None", systemImage: "shoeprints.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "record.shoes.change", defaultValue: "Change shoes"))
        }
    }

    private var selectedSessionShoe: GearItem? {
        if let selectedSessionShoeID,
           let selectedShoe = gearStore.activeShoes.first(where: { $0.id == selectedSessionShoeID }) {
            return selectedShoe
        }
        return gearStore.defaultShoe
    }

    private func applyDefaultSessionShoeIfNeeded() {
        guard !didApplyDefaultSessionShoe else { return }
        selectedSessionShoeID = gearStore.defaultShoe?.id
        didApplyDefaultSessionShoe = true
    }

    private func heartRateZones(from summary: ActivitySummary) -> ActivityHeartRateZoneSummary? {
        guard let averageHeartRate = summary.healthMetrics?.averageHeartRateBPM else { return nil }
        let estimatedMax = 190
        let bounds = [
            (1, 0.50, 0.60),
            (2, 0.60, 0.70),
            (3, 0.70, 0.80),
            (4, 0.80, 0.90),
            (5, 0.90, 1.01)
        ]
        let zones = bounds.map { index, lower, upper in
            let lowerBPM = Int((Double(estimatedMax) * lower).rounded())
            let upperBPM = upper >= 1 ? nil : Int((Double(estimatedMax) * upper).rounded())
            let containsAverage = averageHeartRate >= lowerBPM && (upperBPM.map { averageHeartRate < $0 } ?? true)
            return ActivityHeartRateZone(
                index: index,
                lowerBoundBPM: lowerBPM,
                upperBoundBPM: upperBPM,
                seconds: containsAverage ? summary.durationSecs : 0
            )
        }
        return ActivityHeartRateZoneSummary(estimatedMaxHeartRate: estimatedMax, zones: zones)
    }

    private func sessionGoalCard(for intent: SessionIntent) -> some View {
        Button {
            selectedGoalMode = SessionGoalMode(goal: intent.activityGoal)
            track(.init(.goalEditorOpened, properties: [.goalType: .string(analyticsGoalType)]))
            setupSheet = .goal
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "flag.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                    .frame(width: 28)
                Text(String(localized: "record.goal.title", defaultValue: "Goal"))
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(intent.activityGoal.label(unitSystem: measurementPreferences.unitSystem))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: startSetupCardCornerRadius, style: .continuous))
        .onAppear {
            selectedGoalMode = SessionGoalMode(goal: intent.activityGoal)
        }
    }

    private var goalSetupChoices: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                goalModeButton(.freestyle)
                goalModeButton(.distance)
                goalModeButton(.time)
                goalModeButton(.calories)
            }

            switch selectedGoalMode {
            case .planned:
                Button {
                    setupSheet = nil
                    showsStandaloneWorkouts = true
                } label: {
                    Label(String(localized: "record.goal.workout", defaultValue: "Choose a workout"), systemImage: "list.bullet.clipboard")
                }
            case .freestyle:
                Text(String(localized: "record.goal.freestyle.detail", defaultValue: "No preset target. Tap Start and move by feel."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    applyGoalAndDismiss(.freestyle)
                } label: {
                    Text(String(localized: "record.goal.use_freestyle", defaultValue: "Use Freestyle"))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            case .distance:
                GoalPresetFlow(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(distanceGoalPresets) { preset in
                        goalPresetButton(title: preset.title, isSelected: isSelectedDistancePreset(preset.meters)) {
                            applyGoalAndDismiss(.distanceMeters(preset.meters))
                        }
                    }
                    goalPresetButton(title: String(localized: "record.goal.custom", defaultValue: "Custom"), isSelected: isCustomDistanceSelected) {
                        presentCustomGoalFromSheet(.distance)
                    }
                }
            case .time:
                GoalPresetFlow(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(timeGoalPresets) { preset in
                        goalPresetButton(title: preset.title, isSelected: isSelectedTimePreset(preset.seconds)) {
                            applyGoalAndDismiss(.timeSeconds(preset.seconds))
                        }
                    }
                    goalPresetButton(title: String(localized: "record.goal.custom", defaultValue: "Custom"), isSelected: isCustomTimeSelected) {
                        presentCustomGoalFromSheet(.time)
                    }
                }
            case .calories:
                GoalPresetFlow(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(calorieGoalPresets, id: \.self) { calories in
                        goalPresetButton(title: calorieGoalLabel(calories), isSelected: currentActivityGoal.targetCalories == calories) {
                            applyGoalAndDismiss(.calories(calories))
                        }
                    }
                    goalPresetButton(title: String(localized: "record.goal.custom", defaultValue: "Custom"), isSelected: isCustomCaloriesSelected) {
                        presentCustomGoalFromSheet(.calories)
                    }
                }
            }

            Divider()

            Button {
                setupSheet = nil
                showsStandaloneWorkouts = true
            } label: {
                Label(String(localized: "record.goal.workout", defaultValue: "Choose a workout"), systemImage: "list.bullet.clipboard")
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private var routeSetupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let route = plannedIntent?.preparedRoute {
                RoutePreviewMap(points: route.directedPoints, showsEndpoints: true)
                    .id("\(route.source.rawValue)-\(route.id)-\(route.direction.rawValue)")
                    .frame(height: 138)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(route.name)
                            .font(.headline)
                            .lineLimit(1)
                        Text(routeDistanceLabel(route))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button(String(localized: "common.change", defaultValue: "Change")) { openRouteLibrary() }
                        .font(.subheadline.weight(.semibold))
                    Button(role: .destructive) { removeSelectedRoute(route) } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .accessibilityLabel(String(localized: "record.route.remove", defaultValue: "Remove route"))
                }

                if let advisory = routeGoalAdvisory(route) {
                    Label(advisory, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker(
                    String(localized: "record.route.direction", defaultValue: "Direction"),
                    selection: Binding(
                        get: { route.direction },
                        set: { updateRouteDirection($0, for: route) }
                    )
                ) {
                    Text(String(localized: "record.route.direction.saved", defaultValue: "As saved"))
                        .tag(RouteDirection.forward)
                    Text(String(localized: "record.route.direction.reverse", defaultValue: "Reverse"))
                        .tag(RouteDirection.reverse)
                }
                .pickerStyle(.segmented)
                .accessibilityHint(String(localized: "record.route.direction.hint", defaultValue: "Choose which endpoint you intend to start from."))
            } else if let routeName = plannedIntent?.routeName {
                HStack(spacing: 12) {
                    Image(systemName: "map.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(routeName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(String(localized: "record.route.preview_unavailable", defaultValue: "Preview unavailable for this route"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button(String(localized: "common.change", defaultValue: "Change")) { openRouteLibrary() }
                        .font(.subheadline.weight(.semibold))
                    Button(role: .destructive) { removeNamedRoute() } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .accessibilityLabel(String(localized: "record.route.remove", defaultValue: "Remove route"))
                }
            } else {
                Button(action: openRouteLibrary) {
                    HStack(spacing: 12) {
                        Image(systemName: "map.fill")
                            .font(.headline)
                            .foregroundStyle(.orange)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "record.setup.route", defaultValue: "Route"))
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(String(localized: "record.route.choose", defaultValue: "Choose a route and preview it here"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: startSetupCardCornerRadius, style: .continuous))
    }

    private func plannedWorkoutCard(for intent: SessionIntent) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(String(localized: "record.workout_plan.title", defaultValue: "Workout plan"), systemImage: "list.bullet.clipboard")
                    .font(.headline)
                Spacer()
                Text(plannedWorkoutDurationLabel(for: intent))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(Array(intent.workoutSteps.enumerated()), id: \.element.id) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Color.orange, in: Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.label)
                                .font(.subheadline.weight(.semibold))
                            if let detail = step.detail, !detail.isEmpty {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        Spacer(minLength: 8)

                        Text(workoutStepDurationLabel(step.durationSeconds))
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 10)

                    if index < intent.workoutSteps.count - 1 {
                        Divider()
                            .padding(.leading, 36)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: startSetupCardCornerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func plannedWorkoutDurationLabel(for intent: SessionIntent) -> String {
        let stepDuration = intent.workoutSteps.reduce(0) { $0 + $1.durationSeconds }
        return workoutStepDurationLabel(stepDuration > 0 ? stepDuration : intent.resolvedTargetDurationSeconds ?? 0)
    }

    private func workoutStepDurationLabel(_ seconds: Int) -> String {
        guard seconds > 0 else { return "Open" }
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        if minutes == 0 { return "\(remainingSeconds)s" }
        if remainingSeconds == 0 { return "\(minutes) min" }
        return "\(minutes)m \(remainingSeconds)s"
    }

    private func goalModeButton(_ mode: SessionGoalMode) -> some View {
        Button {
            selectedGoalMode = mode
        } label: {
            Text(mode.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(selectedGoalMode == mode ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .background(
                    Capsule()
                        .fill(selectedGoalMode == mode ? Color.orange : Color(.tertiarySystemBackground))
                )
        }
        .buttonStyle(.plain)
    }

    private func goalPresetButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .padding(.horizontal, isSelected ? 18 : 20)
            .frame(height: 40)
            .foregroundStyle(isSelected ? .white : .primary)
            .background(isSelected ? Color.orange : Color(.tertiarySystemBackground), in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
    }

    private var currentActivityGoal: ActivityGoal {
        (plannedIntent ?? .freestyleRun).activityGoal
    }

    private var distanceGoalPresets: [DistanceGoalPreset] {
        DistanceGoalPreset.recommended(from: activityStore.activities)
    }

    private var timeGoalPresets: [TimeGoalPreset] {
        TimeGoalPreset.recommended(from: activityStore.activities)
    }

    private var calorieGoalPresets: [Int] {
        [150, 250, 300, 400, 500]
    }

    private func calorieGoalLabel(_ calories: Int) -> String {
        String(
            format: String(localized: "activity.goal.calories.format", defaultValue: "%d kcal"),
            locale: .autoupdatingCurrent,
            calories
        )
    }

    private func isSelectedDistancePreset(_ meters: Double) -> Bool {
        guard case .distanceMeters(let selectedMeters) = currentActivityGoal else { return false }
        return abs(selectedMeters - meters) < 1
    }

    private func isSelectedTimePreset(_ seconds: Int) -> Bool {
        guard case .timeSeconds(let selectedSeconds) = currentActivityGoal else { return false }
        return selectedSeconds == seconds
    }

    private var isCustomDistanceSelected: Bool {
        guard case .distanceMeters = currentActivityGoal else { return false }
        return !distanceGoalPresets.contains { isSelectedDistancePreset($0.meters) }
    }

    private var isCustomTimeSelected: Bool {
        guard case .timeSeconds = currentActivityGoal else { return false }
        return !timeGoalPresets.contains { isSelectedTimePreset($0.seconds) }
    }

    private var isCustomCaloriesSelected: Bool {
        guard let calories = currentActivityGoal.targetCalories else { return false }
        return !calorieGoalPresets.contains(calories)
    }

    private func applyGoal(_ goal: ActivityGoal) {
        let currentIntent = plannedIntent ?? .freestyleRun
        plannedIntent = currentIntent.replacingGoal(goal, unitSystem: measurementPreferences.unitSystem)
        if selectedWorkoutChoice != .planned {
            manualActivityGoal = goal
        }
        selectedGoalMode = SessionGoalMode(goal: goal)
        track(.init(.activityConfigurationChanged, properties: [
            .changeType: .string("goal"),
            .goalType: .string(analyticsGoalType),
            .targetBucket: .string(analyticsTargetBucket(for: goal))
        ]))
    }

    private func applyGoalAndDismiss(_ goal: ActivityGoal) {
        applyGoal(goal)
        setupSheet = nil
    }

    private func presentCustomGoalFromSheet(_ kind: CustomGoalKind) {
        setupSheet = nil
        Task { @MainActor in
            await Task.yield()
            presentCustomGoal(kind)
        }
    }

    private func openRouteLibrary() {
        trackFeatureExposure("routes")
        showsRouteLibrary = true
        track(.init(.routeLibraryOpened))
    }

    private func removeSelectedRoute(_ route: PreparedRoute) {
#if DEBUG
        if route.id == HarvestHalfMarathonSimulation.routeID {
            isRunSimulationEnabled = false
        }
#endif
        applyRoute(nil)
        track(.init(.routeRemoved, properties: [.sourceType: .string(route.source.rawValue)]))
    }

    private func removeNamedRoute() {
        applyRoute(nil)
        track(.init(.routeRemoved, properties: [.sourceType: .string("named")]))
    }

    private func routeDistanceLabel(_ route: PreparedRoute) -> String {
        let meters = preparedRouteDistance(route)
        return measurementPreferences.unitSystem.distanceString(
            meters: meters,
            fractionDigits: 1
        )
    }

    private func routeGoalAdvisory(_ route: PreparedRoute) -> String? {
        guard case .distanceMeters(let goalMeters) = currentActivityGoal else { return nil }
        let routeMeters = preparedRouteDistance(route)
        guard routeMeters > 0,
              abs(routeMeters - goalMeters) > max(500, routeMeters * 0.1)
        else { return nil }
        return String(
            format: String(localized: "record.route.goal_difference", defaultValue: "Your %@ goal and %@ route are different. You can keep both."),
            locale: .autoupdatingCurrent,
            currentActivityGoal.label(unitSystem: measurementPreferences.unitSystem),
            routeDistanceLabel(route)
        )
    }

    private func applyRoute(_ route: PreparedRoute?) {
#if DEBUG
        if route?.id != HarvestHalfMarathonSimulation.routeID {
            isRunSimulationEnabled = false
        }
#endif
        let currentIntent = plannedIntent ?? .freestyleRun
        if let route {
            if currentIntent.preparedRoute == nil {
                intentBeforeSelectedRoute = currentIntent
            }
            let baseIntent = intentBeforeSelectedRoute ?? currentIntent
            plannedIntent = routeIntent(route, appliedTo: baseIntent)
            selectedRouteDistanceMeters = Self.calculatePreparedRouteDistance(route)
        } else {
            let baseIntent = intentBeforeSelectedRoute ?? freestyleFallback(for: currentIntent.sport)
            let restoredBase = currentIntent.activityGoal == baseIntent.activityGoal
                ? baseIntent
                : baseIntent.replacingGoal(
                    currentIntent.activityGoal,
                    unitSystem: measurementPreferences.unitSystem
                )
            plannedIntent = SessionIntent(
                id: restoredBase.id,
                sport: restoredBase.sport,
                title: restoredBase.title,
                detail: restoredBase.detail,
                guideLine: restoredBase.guideLine,
                startLabel: restoredBase.startLabel,
                targetDistanceMeters: restoredBase.targetDistanceMeters,
                targetDurationSeconds: restoredBase.targetDurationSeconds,
                targetCalories: restoredBase.targetCalories,
                routeName: restoredBase.routeName,
                preparedRoute: restoredBase.preparedRoute,
                activityTypeOverride: restoredBase.activityTypeOverride,
                workoutSteps: restoredBase.workoutSteps,
                activityEvent: restoredBase.activityEvent
            )
            intentBeforeSelectedRoute = nil
            selectedRouteDistanceMeters = nil
            return
        }
        guard let route else { return }
        track(.init(.routeSelected, properties: [
            .sourceType: .string(route.source.rawValue),
            .distanceBucket: .string(ProductAnalyticsBucket.distance(meters: preparedRouteDistance(route)))
        ]))
    }

    private func routeIntent(_ route: PreparedRoute, appliedTo baseIntent: SessionIntent) -> SessionIntent {
        let resolvedSport = route.activityType.map { SportType(activityType: $0) }
            ?? baseIntent.sport
        let preservesBaseStructure = route.activityType == nil
            || route.activityType == baseIntent.resolvedActivityType
        return SessionIntent(
            id: baseIntent.id,
            sport: resolvedSport,
            title: route.name,
            detail: String(localized: "route.guidance.setup.detail", defaultValue: "Follow the selected route with on-device guidance"),
            guideLine: String(localized: "route.guidance.setup.companion", defaultValue: "Keep the route visible and follow it at your own pace."),
            startLabel: String(localized: "route.guidance.start", defaultValue: "Start Route Guidance"),
            targetDistanceMeters: baseIntent.targetDistanceMeters,
            targetDurationSeconds: baseIntent.targetDurationSeconds,
            targetCalories: baseIntent.targetCalories,
            routeName: route.name,
            preparedRoute: route,
            activityTypeOverride: route.activityType,
            workoutSteps: preservesBaseStructure ? baseIntent.workoutSteps : [],
            activityEvent: preservesBaseStructure ? baseIntent.activityEvent : nil
        )
    }

    private func routeFreeIntent(from intent: SessionIntent) -> SessionIntent {
        guard intent.preparedRoute != nil else { return intent }
        return freestyleFallback(for: intent.sport)
            .replacingGoal(intent.activityGoal, unitSystem: measurementPreferences.unitSystem)
    }

    private func freestyleFallback(for sport: SportType) -> SessionIntent {
        guard sport != .run else { return .freestyleRun }
        return SessionIntent(
            id: "freestyle-\(sport.rawValue)",
            sport: sport,
            title: String(
                format: String(localized: "activity.freestyle.title.format", defaultValue: "Freestyle %@"),
                locale: .autoupdatingCurrent,
                sport.displayName.lowercased()
            ),
            detail: String(
                format: String(localized: "activity.freestyle.detail.format", defaultValue: "%@ • no preset target"),
                locale: .autoupdatingCurrent,
                sport.displayName
            ),
            guideLine: String(localized: "activity.freestyle.companion", defaultValue: "Start easy and settle into a comfortable rhythm."),
            startLabel: String(
                format: String(localized: "activity.goal.start.freestyle.format", defaultValue: "Start %@"),
                locale: .autoupdatingCurrent,
                sport.displayName
            )
        )
    }

    private func updateRouteDirection(_ direction: RouteDirection, for route: PreparedRoute) {
        guard direction != route.direction else { return }
        let directedRoute = route.withDirection(direction)
        let currentIntent = plannedIntent ?? .freestyleRun
        plannedIntent = SessionIntent(
            id: currentIntent.id,
            sport: currentIntent.sport,
            title: currentIntent.title,
            detail: currentIntent.detail,
            guideLine: currentIntent.guideLine,
            startLabel: currentIntent.startLabel,
            targetDistanceMeters: currentIntent.targetDistanceMeters,
            targetDurationSeconds: currentIntent.targetDurationSeconds,
            targetCalories: currentIntent.targetCalories,
            routeName: directedRoute.name,
            preparedRoute: directedRoute,
            activityTypeOverride: directedRoute.activityType ?? currentIntent.activityTypeOverride,
            workoutSteps: currentIntent.workoutSteps,
            activityEvent: currentIntent.activityEvent
        )
        track(.init(.activityConfigurationChanged, properties: [
            .changeType: .string("route_direction"),
            .selectionType: .string(direction.rawValue)
        ]))
    }

    private func applySmartGoalDefaultIfNeeded() {
        guard shouldApplySmartGoalDefault, !didApplySmartGoalDefault else { return }
        didApplySmartGoalDefault = true
        guard currentActivityGoal.isFreestyle,
              let preferredGoal = SmartGoalPreference.preferredFrequentCustomGoal(from: activityStore.activities) else {
            return
        }
        applyGoal(preferredGoal)
    }

    private func applyLearnedGoalModeIfNeeded() {
        guard shouldApplySmartGoalDefault,
              let preferredMode = SessionGoalMode(rawValue: preferredLaunchGoalModeRawValue),
              preferredMode != .planned,
              preferredMode != selectedGoalMode
        else { return }
        selectLaunchMode(preferredMode)
    }

    private func recordStartedGoalMode() {
        var history = (try? JSONDecoder().decode([String].self, from: launchGoalModeStartHistoryData)) ?? []
        history.append(selectedGoalMode.rawValue)
        history = Array(history.suffix(3))
        launchGoalModeStartHistoryData = (try? JSONEncoder().encode(history)) ?? Data()

        guard history.count == 3,
              history.allSatisfy({ $0 == selectedGoalMode.rawValue }),
              preferredLaunchGoalModeRawValue != selectedGoalMode.rawValue
        else { return }

        preferredLaunchGoalModeRawValue = selectedGoalMode.rawValue
        showSetupToast(
            String(
                format: String(localized: "record.goal.default_learned.format", defaultValue: "%@ is now your default"),
                locale: .autoupdatingCurrent,
                selectedGoalMode.title
            )
        )
    }

    private func presentCustomGoal(_ kind: CustomGoalKind) {
        customGoalKind = kind
        switch kind {
        case .distance:
            customDistanceText = ""
        case .time:
            customTimeText = ""
        case .calories:
            customCaloriesText = ""
        }
        isCustomGoalAlertPresented = true
    }

    private func applyCustomGoal() {
        switch customGoalKind {
        case .distance:
            let value = Double(customDistanceText.replacingOccurrences(of: ",", with: ".")) ?? 0
            guard value > 0 else { return }
            applyGoal(.distanceMeters(value * 1000))
        case .time:
            let minutes = Int(customTimeText) ?? 0
            guard minutes > 0 else { return }
            applyGoal(.timeSeconds(minutes * 60))
        case .calories:
            let calories = Int(customCaloriesText) ?? 0
            guard calories > 0 else { return }
            applyGoal(.calories(calories))
        case .none:
            return
        }
        customGoalKind = nil
    }

    private var customGoalAlertTitle: String {
        switch customGoalKind {
        case .distance:
            return String(localized: "record.goal.custom_distance", defaultValue: "Custom distance")
        case .time:
            return String(localized: "record.goal.custom_time", defaultValue: "Custom time")
        case .calories:
            return String(localized: "record.goal.custom_calories", defaultValue: "Custom calories")
        case .none:
            return String(localized: "record.goal.custom", defaultValue: "Custom goal")
        }
    }

    private var customGoalAlertMessage: String {
        switch customGoalKind {
        case .distance:
            return String(localized: "record.goal.custom_distance.message", defaultValue: "Enter kilometers for this activity.")
        case .time:
            return String(localized: "record.goal.custom_time.message", defaultValue: "Enter minutes for this activity.")
        case .calories:
            return String(localized: "record.goal.custom_calories.message", defaultValue: "Enter a calorie target for this activity.")
        case .none:
            return ""
        }
    }

    @ViewBuilder
    private var musicSetupCard: some View {
        DisclosureGroup(isExpanded: $isMusicSetupExpanded) {
            VStack(alignment: .leading, spacing: 12) {

                if musicStore.hasDeveloperTokenError {
                HStack(spacing: 10) {
                    Image(systemName: "music.note.slash")
                        .foregroundStyle(.secondary)
                    Text(String(localized: "session.music.unavailable", defaultValue: "Music unavailable"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                } else if let lastErrorMessage = musicStore.lastErrorMessage {
                Text(lastErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

                if let troubleshootingLine = musicStore.troubleshootingLine {
                Text(troubleshootingLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

                if musicStore.canShowQuickPicks, !musicStore.quickPicks.isEmpty {
                VStack(spacing: 10) {
                    ForEach(musicStore.quickPicks) { quickPick in
                        Button {
                            musicStore.selectQuickPick(quickPick)
                            track(.init(.musicQuickPickSelected, properties: [.selectionType: .string("quick_pick")]))
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: quickPick.symbolName)
                                    .foregroundStyle(.orange)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(quickPick.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(quickPick.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: musicStore.selectedQuickPickID == quickPick.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(musicStore.selectedQuickPickID == quickPick.id ? Color.orange : Color.secondary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "Select \(quickPick.title)"))
                    }
                }
                } else {
                Button {
                    if !musicStore.isConnected { track(.init(.musicAuthorizationRequested)) }
                    Task { await musicStore.performPrimaryAction() }
                } label: {
                    HStack(spacing: 10) {
                        Text(musicStore.primaryActionTitle)
                            .font(.subheadline.bold())
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(musicStore.isPrimaryActionEnabled ? Color.orange : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                }
                .buttonStyle(.plain)
                .disabled(!musicStore.isPrimaryActionEnabled)
                }
            }
            .padding(.top, 12)
        } label: {
            compactSetupLabel(title: "Music", value: musicStore.musicSummaryLine, systemImage: "music.note.list")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: startSetupCardCornerRadius, style: .continuous))
    }

    private var startSetupCardCornerRadius: CGFloat { 20 }

    private var sessionOptionsSummary: String {
        let values = [
            selectedSessionShoe?.displayName,
            isIndoorSession ? "Treadmill" : nil,
            liveShareStore.isArmedForNextActivity ? "Live sharing" : nil,
            liveGroupStore.isSharing ? "Group run" : nil,
            selectedGuidanceChallenge == .off ? nil : selectedGuidanceChallenge.displayName,
        ].compactMap { $0 }.joined(separator: " · ")
        return values.isEmpty ? "Outdoor · No extras" : values
    }

    private func compactSetupLabel(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage).foregroundStyle(.orange).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Text(value).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
        }
        .contentShape(Rectangle())
    }
}

struct ActivityLaunchMap: View {
    @Environment(\.outboundTheme) private var theme
    @ObservedObject var locationManager: LocationManager
    let route: PreparedRoute?
    var attributionBottomInset: CGFloat = 0

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)

    private var routeCoordinates: [CLLocationCoordinate2D] {
        guard let route else { return [] }
        return RouteWorkingGeometry.displayPoints(route.directedPoints).map(\.locationCoordinate)
    }

    private var routeCameraKey: String? {
        route.map { "\($0.id):\($0.direction.rawValue)" }
    }

    private var routeEndpointsOverlap: Bool {
        guard let start = routeCoordinates.first, let finish = routeCoordinates.last else { return false }
        return CLLocation(latitude: start.latitude, longitude: start.longitude)
            .distance(from: CLLocation(latitude: finish.latitude, longitude: finish.longitude)) <= 20
    }

    var body: some View {
        Map(position: $position, interactionModes: [.pan, .zoom, .rotate]) {
            if routeCoordinates.count > 1 {
                MapPolyline(coordinates: routeCoordinates)
                    .stroke(.white.opacity(0.9), lineWidth: 8)
                MapPolyline(coordinates: routeCoordinates)
                    .stroke(theme.actionColor, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }

            if let start = routeCoordinates.first {
                Annotation(
                    routeEndpointsOverlap
                        ? String(localized: "route.guidance.map.start_finish", defaultValue: "Route start and finish")
                        : String(localized: "route.guidance.map.start", defaultValue: "Route start"),
                    coordinate: start
                ) {
                    Image(systemName: routeEndpointsOverlap ? "flag.checkered" : "figure.run")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(routeEndpointsOverlap ? theme.actionColor : Color.green, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .shadow(radius: 3)
                }
            }

            if let finish = routeCoordinates.last, !routeEndpointsOverlap {
                Annotation(String(localized: "route.guidance.map.finish", defaultValue: "Route finish"), coordinate: finish) {
                    Image(systemName: "flag.checkered")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(theme.actionColor, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .shadow(radius: 3)
                }
            }

            UserAnnotation()
        }
        .safeAreaPadding(.bottom, max(attributionBottomInset, 0))
        .onAppear { frameRouteIfNeeded() }
        .onChange(of: routeCameraKey) { _, _ in frameRouteIfNeeded() }
    }

    private func frameRouteIfNeeded() {
        guard routeCoordinates.count > 1 else {
            position = .userLocation(fallback: .automatic)
            return
        }

        let rect = routeCoordinates.reduce(MKMapRect.null) { partial, coordinate in
            partial.union(MKMapRect(origin: MKMapPoint(coordinate), size: MKMapSize(width: 1, height: 1)))
        }
        position = .rect(rect.insetBy(dx: -max(rect.width * 0.16, 400), dy: -max(rect.height * 0.16, 400)))
    }
}

private struct PendingFinishedActivity: Identifiable {
    let id = UUID()
    let summary: ActivitySummary
    let photos: [(UIImage, PhotoMetadata)]
    let reflection: FinishReflection
    let recognitionPreviews: [RecognitionPreview]
    let guidanceReport: LiveGuidanceSessionReport
}

struct StatBlock: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private enum LaunchWorkoutChoice: Hashable, Identifiable {
    case planned
    case sport(SportType)

    static let supportedManualSports: [SportType] = [.run, .walk, .hike, .bike]
    static var allCases: [LaunchWorkoutChoice] {
        [.planned] + supportedManualSports.map(LaunchWorkoutChoice.sport)
    }

    var id: String { analyticsValue }

    var title: String {
        switch self {
        case .planned:
            String(localized: "record.goal.planned", defaultValue: "Planned")
        case .sport(let sport):
            sport.displayName
        }
    }

    var systemImage: String {
        switch self {
        case .planned: "list.bullet.clipboard.fill"
        case .sport(let sport): sport.systemImage
        }
    }

    var analyticsValue: String {
        switch self {
        case .planned: "planned"
        case .sport(let sport): sport.rawValue
        }
    }

    func accessibilityValue(
        plannedIntent: SessionIntent?,
        manualGoal: ActivityGoal,
        unitSystem: MeasurementUnitSystem
    ) -> String {
        switch self {
        case .planned:
            plannedIntent?.title ?? String(localized: "record.goal.choose_workout", defaultValue: "Choose a workout")
        case .sport:
            manualGoal.label(unitSystem: unitSystem)
        }
    }
}

enum SessionGoalMode: String, CaseIterable, Equatable {
    case planned
    case freestyle
    case distance
    case time
    case calories

    init(goal: ActivityGoal) {
        switch goal {
        case .freestyle:
            self = .freestyle
        case .distanceMeters:
            self = .distance
        case .timeSeconds:
            self = .time
        case .calories:
            self = .calories
        }
    }

    var title: String {
        switch self {
        case .planned:
            return String(localized: "record.goal.planned", defaultValue: "Planned")
        case .freestyle:
            return String(localized: "activity.goal.freestyle", defaultValue: "Freestyle")
        case .distance:
            return String(localized: "record.goal.distance", defaultValue: "Distance")
        case .time:
            return String(localized: "record.goal.time", defaultValue: "Time")
        case .calories:
            return String(localized: "record.goal.calories", defaultValue: "Calories")
        }
    }

    static let manualCases: [SessionGoalMode] = [.freestyle, .distance, .time, .calories]

    var pillTitle: String {
        switch self {
        case .freestyle:
            String(localized: "record.goal.free", defaultValue: "Free")
        case .planned, .distance, .time, .calories:
            title
        }
    }

    var systemImage: String {
        switch self {
        case .planned: return "list.bullet.clipboard.fill"
        case .freestyle: return "figure.run"
        case .distance: return "point.topleft.down.to.point.bottomright.curvepath.fill"
        case .time: return "clock.fill"
        case .calories: return "flame.fill"
        }
    }

    var editorTitle: String {
        switch self {
        case .distance:
            return String(localized: "record.goal.distance_picker", defaultValue: "Choose distance")
        case .time:
            return String(localized: "record.goal.time_picker", defaultValue: "Choose time")
        case .calories:
            return String(localized: "record.goal.calories_picker", defaultValue: "Choose calories")
        case .planned:
            return String(localized: "record.goal.choose_workout", defaultValue: "Choose a workout")
        case .freestyle:
            return String(localized: "activity.goal.freestyle", defaultValue: "Freestyle")
        }
    }

    fileprivate var customGoalKind: CustomGoalKind? {
        switch self {
        case .distance: return .distance
        case .time: return .time
        case .calories: return .calories
        case .planned, .freestyle: return nil
        }
    }

    var analyticsValue: String { rawValue }

    func compactValue(goal: ActivityGoal?) -> String {
        switch self {
        case .planned:
            return String(localized: "record.goal.today", defaultValue: "Today")
        case .freestyle:
            return String(localized: "record.goal.just_run", defaultValue: "Just run")
        case .distance:
            return goal?.targetDistanceMeters.map { ActivityGoal.distanceMeters($0).label(unitSystem: .metric) }
                ?? String(localized: "record.goal.default_distance", defaultValue: "5 km")
        case .time:
            return goal?.targetDurationSeconds.map { ActivityGoal.timeSeconds($0).label(unitSystem: .metric) }
                ?? String(localized: "record.goal.default_time", defaultValue: "30 min")
        case .calories:
            return goal?.targetCalories.map { ActivityGoal.calories($0).label(unitSystem: .metric) }
                ?? String(localized: "record.goal.default_calories", defaultValue: "300 kcal")
        }
    }
}

private enum CustomGoalKind: Equatable {
    case distance
    case time
    case calories
}

private enum ActivityStartCountdownStep: CaseIterable, Equatable {
    case three
    case two
    case one
    case go

    static let sequence: [ActivityStartCountdownStep] = [.three, .two, .one, .go]

    var displayText: String {
        switch self {
        case .three:
            return "3"
        case .two:
            return "2"
        case .one:
            return "1"
        case .go:
            return "Go"
        }
    }

    var spokenText: String {
        switch self {
        case .three:
            return "3"
        case .two:
            return "2"
        case .one:
            return "1"
        case .go:
            return "Go"
        }
    }

    var accessibilityText: String {
        switch self {
        case .three:
            return "3"
        case .two:
            return "2"
        case .one:
            return "1"
        case .go:
            return "Go"
        }
    }

    var durationNanoseconds: UInt64 {
        switch self {
        case .three, .two, .one:
            return 1_000_000_000
        case .go:
            return 420_000_000
        }
    }

    var progress: CGFloat {
        guard let index = Self.sequence.firstIndex(of: self) else { return 0 }
        return CGFloat(index + 1) / CGFloat(Self.sequence.count)
    }
}

private struct ActivityStartCountdownOverlay: View {
    let step: ActivityStartCountdownStep
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.42))
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.2), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: step.progress)
                        .stroke(
                            Color.orange,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    Text(step.displayText)
                        .font(.system(size: step == .go ? 76 : 118, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.72)
                        .lineLimit(1)
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .id(step)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.86).combined(with: .opacity))
                }
                .frame(width: 188, height: 188)
                .shadow(color: .black.opacity(0.26), radius: 20, y: 8)

                Text("Plainstride")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)
            }
            .padding(.horizontal, 28)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(step.accessibilityText)
        }
        .allowsHitTesting(true)
        .animation(.easeInOut(duration: reduceMotion ? 0.12 : 0.24), value: step)
    }
}

private struct GoalPresetFlow: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = arrangedRows(in: maxWidth, subviews: subviews)
        let width = rows.reduce(0) { max($0, $1.width) }
        let height = rows.enumerated().reduce(CGFloat.zero) { total, item in
            total + item.element.height + (item.offset == 0 ? 0 : verticalSpacing)
        }
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var origin = bounds.origin
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let wouldOverflow = origin.x > bounds.minX && origin.x + size.width > bounds.maxX
            if wouldOverflow {
                origin.x = bounds.minX
                origin.y += rowHeight + verticalSpacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: origin.x, y: origin.y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            origin.x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }

    private func arrangedRows(in maxWidth: CGFloat, subviews: Subviews) -> [(width: CGFloat, height: CGFloat)] {
        var rows: [(width: CGFloat, height: CGFloat)] = []
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let spacing = rowWidth == 0 ? 0 : horizontalSpacing
            let wouldOverflow = rowWidth > 0 && rowWidth + spacing + size.width > maxWidth
            if wouldOverflow {
                rows.append((rowWidth, rowHeight))
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += spacing + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }

        if rowWidth > 0 {
            rows.append((rowWidth, rowHeight))
        }

        return rows
    }
}

private struct SmartGoalPreference {
    let goal: ActivityGoal
    let count: Int
    let firstSeenOrder: Int

    static func preferredFrequentCustomGoal(from activities: [SavedActivity]) -> ActivityGoal? {
        [
            DistanceGoalPreset.preferredFrequentCustom(from: activities),
            TimeGoalPreset.preferredFrequentCustom(from: activities)
        ]
        .compactMap { $0 }
        .sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.firstSeenOrder < rhs.firstSeenOrder
        }
        .first?
        .goal
    }
}

private struct DistanceGoalPreset: Identifiable, Hashable {
    let title: String
    let meters: Double

    var id: Int {
        Self.normalizedDistanceKey(meters)
    }

    static func recommended(from activities: [SavedActivity]) -> [DistanceGoalPreset] {
        let stats = distanceStats(from: activities)
        var presets = defaultPresets

        if stats.totalDistanceGoalCount >= matureHistoryCount {
            let usedDefaults = defaultPresets.filter { stats.usageCounts[$0.id, default: 0] > 0 }
            presets = usedDefaults.isEmpty ? Array(defaultPresets.prefix(2)) : usedDefaults
        }

        for custom in frequentCustomPresets(from: stats) where !presets.contains(where: { $0.id == custom.id }) {
            presets.insert(custom, at: 0)
        }

        if presets.count < minimumPresetCount {
            for preset in defaultPresets where !presets.contains(where: { $0.id == preset.id }) {
                presets.append(preset)
                if presets.count == minimumPresetCount { break }
            }
        }

        return Array(presets.prefix(maximumPresetCount))
    }

    static func preferredFrequentCustom(from activities: [SavedActivity]) -> SmartGoalPreference? {
        let stats = distanceStats(from: activities)
        guard let candidate = frequentCustomPresets(from: stats).first else { return nil }
        return SmartGoalPreference(
            goal: .distanceMeters(candidate.meters),
            count: stats.usageCounts[candidate.id, default: 0],
            firstSeenOrder: stats.firstSeenOrder[candidate.id, default: Int.max]
        )
    }

    private static let defaultPresets: [DistanceGoalPreset] = [
        DistanceGoalPreset(title: "5K", meters: 5_000),
        DistanceGoalPreset(title: "10K", meters: 10_000),
        DistanceGoalPreset(title: "Half marathon", meters: 21_097.5),
        DistanceGoalPreset(title: "Marathon", meters: 42_195)
    ]

    private static let frequentCustomUseThreshold = 3
    private static let recentActivityLimit = 30
    private static let matureHistoryCount = 8
    private static let minimumPresetCount = 4
    private static let maximumPresetCount = 6
    private static let distanceBucketMeters = 100.0

    private struct DistanceStats {
        var usageCounts: [Int: Int]
        var firstSeenOrder: [Int: Int]
        var totalDistanceGoalCount: Int
    }

    private static func frequentCustomPresets(from stats: DistanceStats) -> [DistanceGoalPreset] {
        stats.usageCounts
            .filter { key, count in
                count >= frequentCustomUseThreshold && !defaultPresets.contains { $0.id == key }
            }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return stats.firstSeenOrder[lhs.key, default: Int.max] < stats.firstSeenOrder[rhs.key, default: Int.max]
            }
            .map { key, _ in
                let meters = Double(key) * distanceBucketMeters
                return DistanceGoalPreset(title: label(forMeters: meters), meters: meters)
            }
    }

    private static func distanceStats(from activities: [SavedActivity]) -> DistanceStats {
        var usageCounts: [Int: Int] = [:]
        var firstSeenOrder: [Int: Int] = [:]
        var totalDistanceGoalCount = 0

        for (index, activity) in activities.prefix(recentActivityLimit).enumerated() {
            guard let meters = activity.goal?.targetDistanceMeters, meters >= 1_000 else { continue }
            let key = normalizedDistanceKey(meters)
            usageCounts[key, default: 0] += 1
            firstSeenOrder[key] = min(firstSeenOrder[key, default: index], index)
            totalDistanceGoalCount += 1
        }

        return DistanceStats(
            usageCounts: usageCounts,
            firstSeenOrder: firstSeenOrder,
            totalDistanceGoalCount: totalDistanceGoalCount
        )
    }

    private static func normalizedDistanceKey(_ meters: Double) -> Int {
        Int((meters / distanceBucketMeters).rounded())
    }

    private static func label(forMeters meters: Double) -> String {
        let kilometers = meters / 1000
        if abs(kilometers.rounded() - kilometers) < 0.05 {
            return "\(Int(kilometers.rounded()))K"
        }
        return String(format: "%.1fK", kilometers)
            .replacingOccurrences(of: #"\.0K$"#, with: "K", options: .regularExpression)
    }
}

private struct TimeGoalPreset: Identifiable, Hashable {
    let title: String
    let seconds: Int

    var id: Int {
        Self.normalizedTimeKey(seconds)
    }

    static func recommended(from activities: [SavedActivity]) -> [TimeGoalPreset] {
        let stats = timeStats(from: activities)
        var presets = defaultPresets

        if stats.totalTimeGoalCount >= matureHistoryCount {
            let usedDefaults = defaultPresets.filter { stats.usageCounts[$0.id, default: 0] > 0 }
            presets = usedDefaults.isEmpty ? Array(defaultPresets.prefix(3)) : usedDefaults
        }

        for custom in frequentCustomPresets(from: stats) where !presets.contains(where: { $0.id == custom.id }) {
            presets.insert(custom, at: 0)
        }

        if presets.count < minimumPresetCount {
            for preset in defaultPresets where !presets.contains(where: { $0.id == preset.id }) {
                presets.append(preset)
                if presets.count == minimumPresetCount { break }
            }
        }

        return Array(presets.prefix(maximumPresetCount))
    }

    static func preferredFrequentCustom(from activities: [SavedActivity]) -> SmartGoalPreference? {
        let stats = timeStats(from: activities)
        guard let candidate = frequentCustomPresets(from: stats).first else { return nil }
        return SmartGoalPreference(
            goal: .timeSeconds(candidate.seconds),
            count: stats.usageCounts[candidate.id, default: 0],
            firstSeenOrder: stats.firstSeenOrder[candidate.id, default: Int.max]
        )
    }

    private static let defaultPresets: [TimeGoalPreset] = [
        TimeGoalPreset(title: "20 min", seconds: 20 * 60),
        TimeGoalPreset(title: "30 min", seconds: 30 * 60),
        TimeGoalPreset(title: "45 min", seconds: 45 * 60),
        TimeGoalPreset(title: "1 hr", seconds: 60 * 60),
        TimeGoalPreset(title: "1.5 hr", seconds: 90 * 60)
    ]

    private static let frequentCustomUseThreshold = 3
    private static let recentActivityLimit = 30
    private static let matureHistoryCount = 8
    private static let minimumPresetCount = 4
    private static let maximumPresetCount = 6
    private static let timeBucketSeconds = 60

    private struct TimeStats {
        var usageCounts: [Int: Int]
        var firstSeenOrder: [Int: Int]
        var totalTimeGoalCount: Int
    }

    private static func frequentCustomPresets(from stats: TimeStats) -> [TimeGoalPreset] {
        stats.usageCounts
            .filter { key, count in
                count >= frequentCustomUseThreshold && !defaultPresets.contains { $0.id == key }
            }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return stats.firstSeenOrder[lhs.key, default: Int.max] < stats.firstSeenOrder[rhs.key, default: Int.max]
            }
            .map { key, _ in
                let seconds = key * timeBucketSeconds
                return TimeGoalPreset(title: label(forSeconds: seconds), seconds: seconds)
            }
    }

    private static func timeStats(from activities: [SavedActivity]) -> TimeStats {
        var usageCounts: [Int: Int] = [:]
        var firstSeenOrder: [Int: Int] = [:]
        var totalTimeGoalCount = 0

        for (index, activity) in activities.prefix(recentActivityLimit).enumerated() {
            guard let seconds = activity.goal?.targetDurationSeconds, seconds >= timeBucketSeconds else { continue }
            let key = normalizedTimeKey(seconds)
            usageCounts[key, default: 0] += 1
            firstSeenOrder[key] = min(firstSeenOrder[key, default: index], index)
            totalTimeGoalCount += 1
        }

        return TimeStats(
            usageCounts: usageCounts,
            firstSeenOrder: firstSeenOrder,
            totalTimeGoalCount: totalTimeGoalCount
        )
    }

    private static func normalizedTimeKey(_ seconds: Int) -> Int {
        Int((Double(seconds) / Double(timeBucketSeconds)).rounded())
    }

    private static func label(forSeconds seconds: Int) -> String {
        if seconds < 3600 {
            return "\(max(1, seconds / 60)) min"
        }

        let hours = Double(seconds) / 3600
        if abs(hours.rounded() - hours) < 0.01 {
            return "\(Int(hours.rounded())) hr"
        }
        return String(format: "%.1f hr", hours)
            .replacingOccurrences(of: #"\.0 hr$"#, with: " hr", options: .regularExpression)
    }
}
