import SwiftUI
import PhotosUI
import CoreLocation
import MapKit

import Combine

@MainActor
final class ActivityFlowCoordinator: ObservableObject {
    let dependencies: ActivityFlowDependencies
    let preferences: ActivityFlowPreferences
    var host: ActivityFlowHost
    var analyticsManager: AnalyticsManager?
    var reduceMotion: Bool

    let setup: ActivitySetupViewModel
    let live = LiveActivityViewModel()
    let review = ActivityReviewViewModel()
    let countdown = ActivityCountdownViewModel()
    let recorder: ActivityRecorder
    let launchCoordinator = ActivityLaunchCoordinator()
    let sessionController = ActivitySessionController()
    let guide = VirtualGuide()
    let liveActivityManager = SessionLiveActivityManager()
    let workoutPresence = WorkoutPresenceController()
    let launchPreferenceStore: ActivityLaunchPreferenceStore
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

    init(initialIntent: SessionIntent?, dependencies: ActivityFlowDependencies, preferences: ActivityFlowPreferences, host: ActivityFlowHost, reduceMotion: Bool, analyticsManager: AnalyticsManager?) {
        self.dependencies = dependencies
        self.preferences = preferences
        self.host = host
        self.reduceMotion = reduceMotion
        self.analyticsManager = analyticsManager
        recorder = ActivityRecorder(locationManager: LocationManager())
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
        observe(setup)
        observe(live)
        observe(review)
        observe(countdown)
        observe(launchPreferenceStore)
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

    var preferredSessionPageRawValue: String {
        get { preferences.preferredSessionPageRawValue.wrappedValue }
        set { preferences.preferredSessionPageRawValue.wrappedValue = newValue }
    }

    var isVoiceGuideEnabled: Bool {
        get { preferences.isVoiceGuideEnabled.wrappedValue }
        set { preferences.isVoiceGuideEnabled.wrappedValue = newValue }
    }

    var autoPauseRunningEnabled: Bool {
        get { preferences.autoPauseRunningEnabled.wrappedValue }
        set { preferences.autoPauseRunningEnabled.wrappedValue = newValue }
    }

    var autoPauseCyclingEnabled: Bool {
        get { preferences.autoPauseCyclingEnabled.wrappedValue }
        set { preferences.autoPauseCyclingEnabled.wrappedValue = newValue }
    }

    var autoPauseWalkingEnabled: Bool {
        get { preferences.autoPauseWalkingEnabled.wrappedValue }
        set { preferences.autoPauseWalkingEnabled.wrappedValue = newValue }
    }

    var autoPauseHikingEnabled: Bool {
        get { preferences.autoPauseHikingEnabled.wrappedValue }
        set { preferences.autoPauseHikingEnabled.wrappedValue = newValue }
    }

    var autoStopAtGoalEnabled: Bool {
        get { preferences.autoStopAtGoalEnabled.wrappedValue }
        set { preferences.autoStopAtGoalEnabled.wrappedValue = newValue }
    }

    var startWatchApp: Bool {
        get { preferences.startWatchApp.wrappedValue }
        set { preferences.startWatchApp.wrappedValue = newValue }
    }
#if DEBUG

    var routeTestMode: Bool {
        get { preferences.routeTestMode.wrappedValue }
        set { preferences.routeTestMode.wrappedValue = newValue }
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
