import SwiftUI
import PhotosUI
import CoreLocation
import MapKit

import Combine

/// The app owns one flow for its entire lifetime; views only observe it.
@MainActor
final class ActivityFlowStore: ObservableObject {
    static let shared = ActivityFlowStore()
    private(set) var coordinator: ActivityFlowCoordinator?
    private init() {}

    var hasUnfinishedSession: Bool { coordinator?.hasUnfinishedSession == true }

    private var selectionKey: String { "group.recording.selection.\(AuthStore.currentUserId ?? "signed-out")" }
    private var completedKey: String { "group.recording.completed.\(AuthStore.currentUserId ?? "signed-out")" }
    var selectedEvent: ActivityEventLaunchContext? {
        guard let data = UserDefaults.standard.data(forKey: selectionKey) else { return nil }
        do { return try JSONDecoder().decode(ActivityEventLaunchContext.self, from: data) }
        catch {
            ActivityDiagnosticLog.error(.persistence, "Group recording selection decode failed error=\(ActivityDiagnosticLog.errorCategory(error))")
            UserDefaults.standard.removeObject(forKey: selectionKey)
            return nil
        }
    }
    func selectedEventForStart(in events: [ActivityEventDTO]) -> ActivityEventLaunchContext? {
        guard let selected = selectedEvent, !hasCompletedEvent(selected.id),
              events.contains(where: { event in
                  event.id == selected.id && event.currentUserOutcome == nil
                    && ["scheduled", "active"].contains(event.status ?? "scheduled")
                    && (event.currentUserGoing == true || event.canParticipate == true)
                    && (Calendar.current.isDateInToday(event.startsAt) || event.status == "active")
              }) else { return nil }
        return selected
    }
    func hasCompletedEvent(_ id: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: completedKey) ?? []).contains(id)
    }
    func completeEvent(_ id: String?) {
        guard let id else { return }
        objectWillChange.send()
        var completed = Set(UserDefaults.standard.stringArray(forKey: completedKey) ?? [])
        completed.insert(id)
        UserDefaults.standard.set(Array(completed), forKey: completedKey)
        if selectedEvent?.id == id { UserDefaults.standard.removeObject(forKey: selectionKey) }
    }
    private func joinChoiceKey(_ id: String) -> String { "\(selectionKey).join_choice.\(id)" }
    private func shareDefaultKey(_ id: String) -> String { "\(selectionKey).share_default_applied.\(id)" }

    func applyParticipationDefault(_ event: ActivityEventDTO) {
        guard !hasUnfinishedSession, event.currentUserGoing == true, selectedEvent == nil,
              UserDefaults.standard.object(forKey: joinChoiceKey(event.id)) == nil else { return }
        setJoined(event, joined: true, entrySource: "today_rsvp_default")
    }

    func rememberLocationSharingChoice(for eventID: String) {
        UserDefaults.standard.set(true, forKey: shareDefaultKey(eventID))
    }

    func consumeLocationSharingDefault(_ event: ActivityEventDTO) -> Bool {
        guard !hasUnfinishedSession, selectedEvent?.id == event.id,
              !UserDefaults.standard.bool(forKey: shareDefaultKey(event.id)) else { return false }
        // Consume before the request so refreshes and later opt-outs cannot re-enable sharing.
        UserDefaults.standard.set(true, forKey: shareDefaultKey(event.id))
        return true
    }

    func setJoined(_ event: ActivityEventDTO, joined: Bool, entrySource: String = "today") {
        guard !hasUnfinishedSession else { return }
        objectWillChange.send()
        UserDefaults.standard.set(joined, forKey: joinChoiceKey(event.id))
        let context = ActivityEventLaunchContext(id: event.id, title: event.title,
            role: event.currentUserRole ?? "participant", attendanceMode: event.currentUserAttendanceMode, organizerName: event.creator.displayName)
        if joined {
            do { UserDefaults.standard.set(try JSONEncoder().encode(context), forKey: selectionKey) }
            catch {
                ActivityDiagnosticLog.error(.persistence, "Group recording selection encode failed error=\(ActivityDiagnosticLog.errorCategory(error))")
                return
            }
        } else {
            UserDefaults.standard.removeObject(forKey: selectionKey)
            if coordinator?.dependencies.liveGroupStore.activeSession?.activityEventId == event.id {
                coordinator?.dependencies.liveGroupStore.leave()
            }
        }
        if var intent = coordinator?.setup.plannedIntent {
            // A cancelled countdown may already have copied the selection into setup.
            // Clear that copy so unchecking really starts solo; start reapplies a checked event.
            intent.activityEvent = nil
            coordinator?.setup.plannedIntent = intent
        }
        coordinator?.track(.init(.groupActivityRecordingSelectionChanged, properties: [
            .selectionType: .string(joined ? "joined" : "solo"), .entrySource: .string(entrySource)
        ]))
    }

    func resolve(initialIntent: SessionIntent?, dependencies: ActivityFlowDependencies, preferences: ActivityFlowPreferences, host: ActivityFlowHost, reduceMotion: Bool, analyticsManager: AnalyticsManager?) -> ActivityFlowCoordinator {
        if let coordinator { return coordinator }
        let coordinator = ActivityFlowCoordinator(initialIntent: initialIntent, dependencies: dependencies, preferences: preferences, host: host, reduceMotion: reduceMotion, analyticsManager: analyticsManager)
        self.coordinator = coordinator
        return coordinator
    }
}

@MainActor
final class ActivityFlowCoordinator: ObservableObject {
    let dependencies: ActivityFlowDependencies
    let curatedWorkoutPresenter = StandaloneWorkoutPresenter()
    let preferences: ActivityFlowPreferences
    var host: ActivityFlowHost
    var analyticsManager: AnalyticsManager?
    var reduceMotion: Bool

    @Published private(set) var setup: ActivitySetupViewModel
    let live = LiveActivityViewModel()
    let review = ActivityReviewViewModel()
    let countdown = ActivityCountdownViewModel()
    let recorder: ActivityRecorder
    let launchCoordinator = ActivityLaunchCoordinator()
    let sessionController = ActivitySessionController()
    let guide = VirtualGuide()
    let liveActivityManager = SessionLiveActivityManager()
    let workoutPresence = WorkoutPresenceController()
    private(set) var launchPreferenceStore: ActivityLaunchPreferenceStore
    @Published var showCamera = false
    @Published var activeIntent: SessionIntent? = nil
    @Published var isAssistantPresented = false
    @Published var isStartingActivity = false
    @Published var didSeedLiveRunForUITest = false
    @Published var didRestoreSession = false
    @Published var didAutoStopAtGoal = false
    @Published var setupToastMessage: String? = nil
    @Published var setupToastTask: Task<Void, Never>? = nil
    @Published var didTrackSetupView = false
    @Published var exposedFeatures: Set<String> = []
    @Published var reachedGoalThresholds: Set<Int> = []
    @Published var previousRecorderState: RecordingState = .idle
    @Published var activityStartedWithGroupRun = false
    @Published var didTrackRecoveryPresentation = false
    @Published var didRestoreSessionPhotos = false
    @Published var isWaitingForLocation = false
    @Published var isLocationPermissionGranted = false
    @Published var isLocationPermissionModalPresented = false
#if DEBUG
    @Published var isRunSimulationEnabled = false
#endif
#if DEBUG
    @Published var didConfigureRequestedGroupRecoveryTest = false
#endif
#if DEBUG
    @Published var didConfigureRequestedRunSimulation = false
#endif

    private var observations = Set<AnyCancellable>()
    private var setupObservation: AnyCancellable?
    private var launchPreferenceObservation: AnyCancellable?
    private var lastLaunchID: UUID?

    var hasUnfinishedSession: Bool {
        sessionController.phase != .setup || recorder.state != .idle
            || isStartingActivity || isWaitingForLocation || isCountingDown
            || review.pendingActivity != nil || review.postSaveCelebrationActivity != nil
            || review.postSaveStretchContext != nil
    }

    func attachActivityEventIfRecording(_ event: ActivityEventLaunchContext?) {
        guard let event, recorder.state != .idle, review.pendingActivity == nil,
              activeIntent?.activityEvent == nil else { return }
        var intent = activeIntent ?? setup.plannedIntent ?? .freestyleRun
        intent.activityEvent = event
        activeIntent = intent
        recorder.attachActivityEvent(event)
        dependencies.socialStore.prepareToRecord(activityEventID: event.id)
        activityStartedWithGroupRun = true
        ActivityEventParticipationSync.shared.enqueueStart(eventID: event.id)
        Task { await ActivityEventParticipationSync.shared.flush() }
        track(.init(.groupActivityRecordingSelectionChanged, properties: [
            .selectionType: .string("joined"), .entrySource: .string("group_activity")
        ]))
    }

    var canStartRecording: Bool {
        (sessionController.phase == .setup || sessionController.phase == .preflighting)
            && recorder.state == .idle && review.pendingActivity == nil
            && review.postSaveCelebrationActivity == nil && review.postSaveStretchContext == nil
    }

    func receiveLaunch(id: UUID, intent: SessionIntent?, startImmediately: Bool) {
        guard lastLaunchID != id else { return }
        let isFirstLaunch = lastLaunchID == nil
        lastLaunchID = id
        // Only this app-owned recorder may restore the journal, once per process.
        restoreInterruptedPhotosIfNeeded()
        restoreInterruptedSessionIfNeeded()
        let entrySource = startImmediately ? "group_activity" : "app"
        guard !hasUnfinishedSession else {
            track(.init(.activityRecordingEntry, properties: [
                .entrySource: .string(entrySource), .result: .string("reused_existing")
            ]))
            ActivityDiagnosticLog.notice(.lifecycle, "Recording entry reused existing app session")
            return
        }
        if !isFirstLaunch {
            cancelStartCountdown(returnToSetup: true)
            cancelLocationWait()
            launchPreferenceStore = ActivityLaunchPreferenceStore(userID: AuthStore.currentUserId)
            setup = ActivitySetupViewModel(dependencies: dependencies, preferences: preferences, launchPreferenceStore: launchPreferenceStore)
            observeSetup()
            observeLaunchPreferences()
            setup.plannedIntent = intent ?? .freestyleRun
            setup.plannedWorkoutIntent = intent
            setup.selectedGoalMode = intent == nil ? .freestyle : .planned
            setup.selectedWorkoutChoice = intent == nil ? .sport(.run) : .planned
            setup.selectedRouteDistanceMeters = intent?.preparedRoute.map(Self.calculatePreparedRouteDistance)
            activeIntent = nil
            showCamera = false
            live.capturedPhotos = []
            live.isCapturingSessionPhoto = false
            live.isLiveWorkoutPanelExpanded = false
            didTrackSetupView = false
            exposedFeatures = []
            reachedGoalThresholds = []
            didAutoStopAtGoal = false
            sessionController.prepare(intent: setup.plannedIntent)
            launchCoordinator.prepare(intent: setup.plannedIntent)
            host.onPreActivityPhotoChange?(nil)
        }
        track(.init(.activityRecordingEntry, properties: [
            .entrySource: .string(entrySource), .result: .string("prepared")
        ]))
        prepareSetupSurface()
        if startImmediately { ensureLocationReadyThenStart() }
    }

    private func observeLaunchPreferences() {
        launchPreferenceObservation = launchPreferenceStore.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    private func observeSetup() {
        setupObservation = setup.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    fileprivate init(initialIntent: SessionIntent?, dependencies: ActivityFlowDependencies, preferences: ActivityFlowPreferences, host: ActivityFlowHost, reduceMotion: Bool, analyticsManager: AnalyticsManager?) {
        self.dependencies = dependencies
        self.preferences = preferences
        self.host = host
        self.reduceMotion = reduceMotion
        self.analyticsManager = analyticsManager
        recorder = ActivityRecorder.shared
        launchPreferenceStore = ActivityLaunchPreferenceStore(userID: AuthStore.currentUserId)
        setup = ActivitySetupViewModel(dependencies: dependencies, preferences: preferences, launchPreferenceStore: launchPreferenceStore)
        setup.plannedIntent = initialIntent ?? .freestyleRun
        setup.plannedWorkoutIntent = initialIntent
        setup.selectedGoalMode = initialIntent == nil ? .freestyle : .planned
        setup.selectedWorkoutChoice = initialIntent == nil ? .sport(.run) : .planned
        setup.selectedRouteDistanceMeters = initialIntent?.preparedRoute.map(Self.calculatePreparedRouteDistance)
        NotificationCenter.default.publisher(for: AccountConfigurationStore.changed)
            .sink { [weak self] _ in
                guard let self, self.recorder.state == .idle,
                      self.countdown.countdownStep == nil, !self.isStartingActivity,
                      !self.setup.hasEditedLaunchConfiguration else { return }
                self.setup.manualSetupDrafts = [:]
                self.applyLearnedGoalModeIfNeeded()
            }
            .store(in: &observations)
        observeSetup()
        observe(live)
        observe(review)
        observe(countdown)
        observeLaunchPreferences()
        observe(recorder)
        observe(guide)
        observe(launchCoordinator)
        observe(workoutPresence)
        observe(sessionController)
        observe(liveActivityManager)
        observe(dependencies.activityStore)
        observe(dependencies.guideStore)
        observe(dependencies.guideCatalog)
        observe(dependencies.assistantStore)
        observe(dependencies.checkInStore)
        observe(dependencies.goalStore)
        observe(dependencies.musicStore)
        observe(dependencies.recognitionStore)
        observe(dependencies.measurementPreferences)
        observe(dependencies.gearStore)
        observe(dependencies.liveShareStore)
        observe(dependencies.liveGroupStore)
        observe(dependencies.safetyContactStore)
        observe(dependencies.onboardingStore)
        observe(dependencies.personalizationStore)
        observe(dependencies.trainingPlanStore)
        observe(dependencies.socialStore)
        observe(dependencies.connectivityStore)
        observe(dependencies.communityRouteStore)
        observe(dependencies.weatherStore)
        observe(dependencies.tooltipCoordinator)
        observe(dependencies.phoneWorkoutCoordinator)
    }

    private func observe<Object: ObservableObject>(_ object: Object) {
        object.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &observations)
    }

    private func setPreference<Value: Equatable>(_ preference: ActivityFlowPreference<Value>, to value: Value) {
        guard preference.wrappedValue != value else { return }
        objectWillChange.send()
        preference.wrappedValue = value
    }

    var preferredSessionPageRawValue: String {
        get { preferences.preferredSessionPageRawValue.wrappedValue }
        set { setPreference(preferences.preferredSessionPageRawValue, to: newValue) }
    }

    var isVoiceGuideEnabled: Bool {
        get { preferences.isVoiceGuideEnabled.wrappedValue }
        set { setPreference(preferences.isVoiceGuideEnabled, to: newValue) }
    }

    var isAICoachEnabled: Bool {
        get { preferences.isAICoachEnabled.wrappedValue }
        set { setPreference(preferences.isAICoachEnabled, to: newValue) }
    }

    var aiCoachEnabled: Bool {
        if recorder.state == .active || recorder.state == .paused {
            return recorder.liveWorkoutOptions?.aiCoachEnabled ?? isAICoachEnabled
        }
        return isAICoachEnabled
    }

    var autoPauseRunningEnabled: Bool {
        get { preferences.autoPauseRunningEnabled.wrappedValue }
        set { setPreference(preferences.autoPauseRunningEnabled, to: newValue) }
    }

    var autoPauseCyclingEnabled: Bool {
        get { preferences.autoPauseCyclingEnabled.wrappedValue }
        set { setPreference(preferences.autoPauseCyclingEnabled, to: newValue) }
    }

    var autoPauseWalkingEnabled: Bool {
        get { preferences.autoPauseWalkingEnabled.wrappedValue }
        set { setPreference(preferences.autoPauseWalkingEnabled, to: newValue) }
    }

    var autoPauseHikingEnabled: Bool {
        get { preferences.autoPauseHikingEnabled.wrappedValue }
        set { setPreference(preferences.autoPauseHikingEnabled, to: newValue) }
    }

    var autoStopAtGoalEnabled: Bool {
        get { preferences.autoStopAtGoalEnabled.wrappedValue }
        set { setPreference(preferences.autoStopAtGoalEnabled, to: newValue) }
    }

    var startWatchApp: Bool {
        get { preferences.startWatchApp.wrappedValue }
        set { setPreference(preferences.startWatchApp, to: newValue) }
    }
#if DEBUG

    var routeTestMode: Bool {
        get { preferences.routeTestMode.wrappedValue }
        set { setPreference(preferences.routeTestMode, to: newValue) }
    }
#endif

    func setCustomGoalText(_ value: String, for kind: CustomGoalKind) {
        switch kind {
        case .distance: setup.customDistanceText = value
        case .time: setup.customTimeText = value
        case .calories: setup.customCaloriesText = value
        }
    }
}
