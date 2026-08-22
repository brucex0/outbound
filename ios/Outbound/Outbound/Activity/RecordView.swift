import SwiftUI
import PhotosUI
import CoreLocation

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

struct RecordView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.analyticsManager) private var analyticsManager
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
    @AppStorage("preferred_session_page_v1") private var preferredSessionPageRawValue = SessionPage.map.rawValue
    @AppStorage("dismissed_apple_voice_download_tip_v1") private var dismissedAppleVoiceDownloadTip = false
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
    @State private var customDistanceText = ""
    @State private var customTimeText = ""
    @State private var customGoalKind: CustomGoalKind?
    @State private var isCustomGoalAlertPresented = false
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
    @State private var showsVoiceDownloadHelp = false
    @State private var showsRouteLibrary = false
    @State private var setupToastMessage: String?
    @State private var setupToastTask: Task<Void, Never>?
    @State private var didTrackSetupView = false
    @State private var exposedFeatures: Set<String> = []
    @State private var reachedGoalThresholds: Set<Int> = []
    @State private var previousRecorderState: RecordingState = .idle
    @State private var activityStartedWithGroupRun = false

    let isVisible: Bool
    private let shouldApplySmartGoalDefault: Bool
    private let onCloseRequest: ((Bool) -> Void)?
    private let onSessionStateChange: ((ActivitySessionPortalState) -> Void)?
    private let onElapsedTimeChange: ((Int) -> Void)?

    init(
        initialIntent: SessionIntent? = nil,
        isVisible: Bool = true,
        onCloseRequest: ((Bool) -> Void)? = nil,
        onSessionStateChange: ((ActivitySessionPortalState) -> Void)? = nil,
        onElapsedTimeChange: ((Int) -> Void)? = nil
    ) {
        _plannedIntent = State(initialValue: initialIntent ?? .freestyleRun)
        self.shouldApplySmartGoalDefault = initialIntent == nil
        self.isVisible = isVisible
        self.onCloseRequest = onCloseRequest
        self.onSessionStateChange = onSessionStateChange
        self.onElapsedTimeChange = onElapsedTimeChange
        let loc = LocationManager()
        _recorder = StateObject(wrappedValue: ActivityRecorder(locationManager: loc))
    }

    var body: some View {
        ZStack {
            if showCamera {
                if isVisible {
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
                            onFinish: finishRecording
                        ) { image, meta in
                            capturedPhotos.append((image, meta))
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
                            onFinish: finishRecording
                        )
                        .tag(SessionPage.map)
                        .ignoresSafeArea()
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .ignoresSafeArea()
                } else {
                    Color.clear
                        .ignoresSafeArea()
                }
            } else {
                readyView
            }
        }
        .background(Color(.systemBackground))
        .ignoresSafeArea()
        .toolbar(showCamera && isVisible ? .hidden : .visible, for: .tabBar)
        .overlay {
            if let countdownStep {
                ActivityStartCountdownOverlay(step: countdownStep, reduceMotion: reduceMotion)
                    .transition(.opacity)
            }
        }
        .onReceive(recorder.$liveSnapshot) { snapshot in
            guide.ingest(snapshot)
            liveShareStore.ingest(snapshot)
            liveGroupStore.ingest(snapshot)
            liveActivityManager.update(
                snapshot: snapshot,
                state: recorder.state,
                intent: activeIntent ?? plannedIntent,
                unitSystem: measurementPreferences.unitSystem
            )
            trackGoalProgressIfNeeded(snapshot)
        }
        .onReceive(recorder.$state) { state in
            onSessionStateChange?(ActivitySessionPortalState(recordingState: state))
            trackRecordingStateTransition(to: state)
        }
        .onReceive(recorder.$elapsedSeconds) { elapsedSeconds in
            onElapsedTimeChange?(elapsedSeconds)
        }
        .onChange(of: isVisible, initial: true) { _, _ in
            seedLiveRunForUITestIfRequested()
        }
        .onAppear {
            restoreInterruptedSessionIfNeeded()
            if recorder.state == .idle {
                recorder.locationManager.requestCurrentLocation()
            }
        }
        .task {
            await musicStore.refresh()
            await musicStore.loadQuickPicks()
            applyWorkoutMusicSuggestion()
            guide.speechEventHandler = { event in
                Task { await musicStore.handleGuideSpeechEvent(event) }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                guideCatalog.refreshInstalledVoices()
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
            if isVisible, let onCloseRequest {
                Button {
                    if isCountingDown {
                        cancelStartCountdown(returnToSetup: true)
                    } else {
                        onCloseRequest(recorder.state != .idle || pendingActivity != nil)
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
            if isVisible {
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
        .fullScreenCover(item: $pendingActivity) { activity in
            PostRunSummaryView(
                summary: activity.summary,
                photos: activity.photos,
                reflection: activity.reflection,
                recognitionPreviews: activity.recognitionPreviews,
                workoutID: (activeIntent ?? plannedIntent)?.id ?? "freestyle-run",
                onSave: { selectedPhotos, reflection in
                    await savePendingActivity(activity, photos: selectedPhotos, reflection: reflection)
                },
                onDiscard: discardPendingActivity
            )
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
                plannedIntent = workout.intent
                selectedGoalMode = SessionGoalMode(goal: workout.intent.activityGoal)
                showsStandaloneWorkouts = false
            }
        }
        .sheet(isPresented: $showsVoiceDownloadHelp) {
            AppleVoiceDownloadHelpView()
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
            } else {
                TextField(String(localized: "record.goal.time_minutes", defaultValue: "Time in minutes"), text: $customTimeText)
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

    private func startRecording() {
        guard recorder.state == .idle, !isCountingDown else { return }
        guard !isStartingActivity else { return }
        guideCatalog.refreshInstalledVoices()
        guard !guideCatalog.requiresVoiceSelection else {
            guideCatalog.requestVoiceSelection()
            return
        }
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
        activeIntent = plannedIntent
        activePage = preferredSessionPage
        showCamera = true
        guide.activate(
            with: guideStore.profile,
            persona: guideCatalog.selectedPersona,
            sessionIntent: activeIntent
        )
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
        activePage = .map
        capturedPhotos = []
        pendingActivity = nil
        showCamera = true
        recorder.seedLiveRunForUITest()
#endif
    }

    private func beginRecordingAfterLiveShareSetup(companionBrief: CompanionSessionBriefDTO? = nil) {
        pendingActivity = nil
        activePage = preferredSessionPage
        activeIntent = plannedIntent
        recorder.locationManager.requestPermission()
        guide.activate(
            with: guideStore.profile,
            persona: guideCatalog.selectedPersona,
            sessionIntent: activeIntent,
            companionBrief: companionBrief
        )
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
        recorder.start()
        reachedGoalThresholds = []
        activityStartedWithGroupRun = liveGroupStore.isSharing
        track(.init(.activityStarted, properties: activityConfigurationProperties))
        liveActivityManager.update(
            snapshot: recorder.liveSnapshot,
            state: recorder.state,
            intent: activeIntent,
            unitSystem: measurementPreferences.unitSystem
        )
        Task {
            await musicStore.beginWorkoutPlaybackIfNeeded()
        }
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
        cancelStartCountdown(returnToSetup: true)
        let summary = recorder.finish()
        track(.init(.activityFinished, properties: outcomeProperties(for: summary)))
        liveActivityManager.end(using: recorder.liveSnapshot, unitSystem: measurementPreferences.unitSystem)
        liveShareStore.end()
        liveGroupStore.finishActivity()
        guide.deactivate()
        Task { await musicStore.endWorkoutPlaybackIfNeeded() }
        showCamera = false
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
        pendingActivity = PendingFinishedActivity(
            summary: summary,
            photos: capturedPhotos,
            reflection: reflection,
            recognitionPreviews: recognitionPreviews
        )
    }

    private func savePendingActivity(
        _ activity: PendingFinishedActivity,
        photos: [(UIImage, PhotoMetadata)],
        reflection: FinishReflection
    ) async -> Bool {
        let priorActivities = activityStore.activities
        let previewProgress = goalStore.previewProgress(with: activity.summary, activities: priorActivities)
        let savedSport = activeIntent?.sport ?? .run

        guard let savedActivity = try? await activityStore.save(
            summary: activity.summary,
            photos: photos,
            activityType: savedSport.activityType,
            reflection: reflection,
            goal: activeIntent?.activityGoal,
            source: .outboundRecorded,
            gear: gearStore.attachment(for: selectedSessionShoe),
            indoor: isIndoorSession ? ActivityIndoorMetadata(isIndoor: true, mode: "treadmill") : nil,
            heartRateZones: heartRateZones(from: activity.summary),
            activityEventID: socialStore.recordingActivityEventID
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
        }
    }

    private func discardPendingActivity() {
        if let pendingActivity {
            var properties = outcomeProperties(for: pendingActivity.summary)
            properties[.photoCountBucket] = .string(ProductAnalyticsBucket.count(pendingActivity.photos.count))
            track(.init(.activityDiscarded, properties: properties))
        }
        let activityEventID = socialStore.consumeRecordingActivityEventID()
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
        activeIntent = nil
        plannedIntent = nil
        selectedGoalMode = .freestyle
        selectedSessionShoeID = nil
        didApplyDefaultSessionShoe = false
        isIndoorSession = false
        activityStartedWithGroupRun = false
    }

    private var preferredSessionPage: SessionPage {
        SessionPage(rawValue: preferredSessionPageRawValue) ?? .map
    }

    private var activityCloseSystemImage: String {
        recorder.state == .idle && pendingActivity == nil ? "xmark" : "chevron.down"
    }

    private var activityCloseAccessibilityLabel: String {
        if isCountingDown { return "Cancel activity start" }
        if recorder.state == .idle && pendingActivity == nil { return "Close activity setup" }
        return "Hide activity"
    }

    private var readyView: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 14) {
                    Spacer(minLength: 68)
                    if connectivityStore.isOffline {
                        OfflineStatusBanner()
                    }
                    if !guideCatalog.hasDownloadedAppleVoices, !dismissedAppleVoiceDownloadTip {
                        appleVoiceDownloadTip
                    }
                    confirmationView(for: plannedIntent ?? .freestyleRun)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 190)
            }

            VStack(spacing: 10) {
                launchControls
            }
            .padding(.horizontal, 20)
        }
        .onAppear {
            guideCatalog.refreshInstalledVoices()
            applySmartGoalDefaultIfNeeded()
            applyDefaultSessionShoeIfNeeded()
            trackSetupAndFeatureExposureIfNeeded()
        }
    }

    private var appleVoiceDownloadTip: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "waveform.circle")
                .font(.title3)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 5) {
                Text(String(localized: "record.voice_tip.title", defaultValue: "Make spoken coaching sound even better"))
                    .font(.subheadline.weight(.semibold))
                Text(String(localized: "record.voice_tip.detail", defaultValue: "Add a free Apple Enhanced or Premium voice. Your current voice works in the meantime."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(String(localized: "record.voice_tip.action", defaultValue: "See how")) {
                    showsVoiceDownloadHelp = true
                }
                .font(.footnote.weight(.semibold))
            }

            Spacer(minLength: 0)

            Button {
                dismissedAppleVoiceDownloadTip = true
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
            .accessibilityLabel(String(localized: "record.voice_tip.dismiss", defaultValue: "Dismiss voice download suggestion"))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: startSetupCardCornerRadius, style: .continuous))
    }

    private var launchControls: some View {
        ZStack {
            HStack(spacing: 8) {
                photoLaunchControl
                launchUtilityButton(
                    title: String(localized: "record.setup.music", defaultValue: "Music"),
                    systemImage: "music.note.list",
                    isConfigured: musicIsConfigured,
                    accessibilityValue: musicSetupValue
                ) {
                    trackFeatureExposure("music")
                    setupSheet = .music
                }

                Spacer(minLength: 76)

                shoeLaunchControl
                launchUtilityButton(
                    title: String(localized: "record.setup.live_track", defaultValue: "Live Track"),
                    systemImage: "location.fill",
                    isConfigured: liveShareStore.isArmedForNextActivity,
                    accessibilityValue: liveTrackValue
                ) {
                    if safetyContactStore.defaultContact == nil {
                        showsTrustedContacts = true
                    } else {
                        liveShareStore.armForNextActivity(!liveShareStore.isArmedForNextActivity)
                    }
                }
            }

            Button(action: startRecording) {
                Group {
                    if isStartingActivity {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.title2.weight(.black))
                            .offset(x: 2)
                    }
                }
                .frame(width: 69, height: 69)
                .foregroundStyle(.white)
                .background(Color.orange, in: Circle())
                .shadow(color: Color.orange.opacity(0.28), radius: 10, y: 5)
            }
            .buttonStyle(.plain)
            .disabled(isStartingActivity)
            .accessibilityLabel(isStartingActivity ? String(localized: "record.start.preparing", defaultValue: "Preparing activity") : (plannedIntent ?? .freestyleRun).startLabel)
            .accessibilityHint(String(localized: "record.start.accessibility_hint", defaultValue: "Starts the prepared activity"))
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 12)
    }

    private var photoLaunchControl: some View {
        Button {
            if preActivityPhoto == nil {
                track(.init(.photoCaptureAttempted, properties: [.sourceType: .string("pre_activity_camera")]))
                isPreActivityCameraPresented = true
            } else {
                track(.init(.photoPreviewed, properties: [.sourceType: .string("pre_activity")]))
                isPreActivityPhotoPreviewPresented = true
            }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                if let photo = preActivityPhoto {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.orange, lineWidth: 2))
                    configuredBadge
                } else {
                    launchUtilityIcon(systemImage: "camera.fill", isConfigured: false)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "record.photo.control", defaultValue: "Photo"))
        .accessibilityValue(photoAccessibilityValue)
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
            Section {
                VStack(alignment: .leading, spacing: 12) { liveGroupSetup }
                    .padding(.vertical, 6)
            }
            Section(String(localized: "record.environment.title", defaultValue: "Environment")) {
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

    private func applyWorkoutMusicSuggestion() {
        let intent = plannedIntent ?? .freestyleRun
        musicStore.applyWorkoutSuggestion(title: intent.title, detail: intent.detail, sport: intent.sport)
    }
    private var liveTrackValue: String { liveShareStore.isArmedForNextActivity ? (safetyContactStore.defaultContact?.name ?? String(localized: "record.live_track.on", defaultValue: "On")) : String(localized: "common.off", defaultValue: "Off") }
    private var photoAccessibilityValue: String { preActivityPhoto == nil ? String(localized: "record.photo.not_added", defaultValue: "No photo added") : String(localized: "record.photo.added", defaultValue: "Photo added") }

    private func track(_ event: ProductAnalyticsEvent) {
        guard let analyticsManager else { return }
        Task { await analyticsManager.track(event) }
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
        }
    }

    private func goalCompletionRatio(distanceMeters: Double, durationSeconds: Int) -> Double? {
        let goal = (activeIntent ?? plannedIntent ?? .freestyleRun).activityGoal
        if let target = goal.targetDistanceMeters, target > 0 { return distanceMeters / target }
        if let target = goal.targetDurationSeconds, target > 0 { return Double(durationSeconds) / Double(target) }
        return nil
    }

    private func preparedRouteDistance(_ route: PreparedRoute) -> Double {
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

    private func replacePreActivityPhoto(with image: UIImage) {
        removePreActivityPhoto()
        let coordinate = recorder.locationManager.location?.coordinate
        capturedPhotos.append((
            image,
            PhotoMetadata(
                takenAt: Date(),
                paceAtShot: nil,
                hrAtShot: nil,
                distAtShot: 0,
                coordinate: coordinate,
                captureContext: .preActivity
            )
        ))
        track(.init(.photoCaptured, properties: [
            .sourceType: .string("pre_activity"),
            .locationAttached: .boolean(coordinate != nil)
        ]))
    }

    private func removePreActivityPhoto() {
        capturedPhotos.removeAll { $0.1.captureContext == .preActivity }
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
            }

            switch selectedGoalMode {
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
                RoutePreviewMap(points: route.points)
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

    private func applyGoal(_ goal: ActivityGoal) {
        let currentIntent = plannedIntent ?? .freestyleRun
        plannedIntent = currentIntent.replacingGoal(goal, unitSystem: measurementPreferences.unitSystem)
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
            routeName: route?.name,
            preparedRoute: route,
            workoutSteps: currentIntent.workoutSteps,
            activityEvent: currentIntent.activityEvent
        )
        guard let route else { return }
        track(.init(.routeSelected, properties: [
            .sourceType: .string(route.source.rawValue),
            .distanceBucket: .string(ProductAnalyticsBucket.distance(meters: preparedRouteDistance(route)))
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

    private func presentCustomGoal(_ kind: CustomGoalKind) {
        customGoalKind = kind
        switch kind {
        case .distance:
            customDistanceText = ""
        case .time:
            customTimeText = ""
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
        case .none:
            return
        }
        customGoalKind = nil
    }

    private var customGoalAlertTitle: String {
        customGoalKind == .distance ? "Custom distance" : "Custom time"
    }

    private var customGoalAlertMessage: String {
        customGoalKind == .distance ? "Enter kilometers for this activity." : "Enter minutes for this activity."
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

private struct PendingFinishedActivity: Identifiable {
    let id = UUID()
    let summary: ActivitySummary
    let photos: [(UIImage, PhotoMetadata)]
    let reflection: FinishReflection
    let recognitionPreviews: [RecognitionPreview]
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

private enum SessionGoalMode: Equatable {
    case freestyle
    case distance
    case time

    init(goal: ActivityGoal) {
        switch goal {
        case .freestyle:
            self = .freestyle
        case .distanceMeters:
            self = .distance
        case .timeSeconds:
            self = .time
        }
    }

    var title: String {
        switch self {
        case .freestyle:
            return String(localized: "activity.goal.freestyle", defaultValue: "Freestyle")
        case .distance:
            return String(localized: "Distance")
        case .time:
            return String(localized: "Time")
        }
    }
}

private enum CustomGoalKind: Equatable {
    case distance
    case time
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
