import SwiftUI
import PhotosUI
import CoreLocation
import MapKit

struct RecordView: View {
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
    @EnvironmentObject var personalizationStore: PersonalizationStore
    @EnvironmentObject var trainingPlanStore: TrainingPlanStore
    @EnvironmentObject var socialStore: TogetherStore
    @EnvironmentObject var connectivityStore: ConnectivityStore
    @EnvironmentObject var communityRouteStore: CommunityRouteStore
    @EnvironmentObject var weatherStore: SituationalWeatherStore
    @EnvironmentObject var tooltipCoordinator: TooltipCoordinator
    @EnvironmentObject var phoneWorkoutCoordinator: PhoneWorkoutSessionCoordinator
    @AppStorage("preferred_session_page_v1") private var preferredSessionPageRawValue = SessionPage.map.rawValue
    @AppStorage("voice_guide_enabled_v1") private var isVoiceGuideEnabled = true
    @AppStorage("auto_pause_running_enabled_v1") private var autoPauseRunningEnabled = true
    @AppStorage("auto_pause_cycling_enabled_v1") private var autoPauseCyclingEnabled = true
    @AppStorage("auto_pause_walking_enabled_v1") private var autoPauseWalkingEnabled = false
    @AppStorage("auto_pause_hiking_enabled_v1") private var autoPauseHikingEnabled = false
    @AppStorage("auto_stop_at_goal_enabled_v1") private var autoStopAtGoalEnabled = false
    @AppStorage("watch.startWatchApp") private var startWatchApp = true
#if DEBUG
    @AppStorage("debug_route_test_mode") private var routeTestMode = false
#endif
    private let initialIntent: SessionIntent?
    let isVisible: Bool
    private let isEmbeddedInToday: Bool
    private let startRequest: Int
    private let preActivityPhotoRequest: Int
    private let routeSelectionRequest: Int
    private let routeRemovalRequest: Int
    private let groupRunRequest: Int
    private let startImmediately: Bool
    private let onLocationPermissionRequired: (() -> Void)?
    private let shouldApplySmartGoalDefault: Bool
    private let onGoalModeChange: ((SessionGoalMode) -> Void)?
    private let onPlanBuilderRequested: (() -> Void)?
    private let onPreActivityPhotoChange: ((UIImage?) -> Void)?
    private let onPreActivityRouteChange: ((PreparedRoute?) -> Void)?
    private let onPostSaveCompleted: (() -> Void)?
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
        groupRunRequest: Int = 0,
        startImmediately: Bool = false,
        onLocationPermissionRequired: (() -> Void)? = nil,
        onGoalModeChange: ((SessionGoalMode) -> Void)? = nil,
        onPlanBuilderRequested: (() -> Void)? = nil,
        onPreActivityPhotoChange: ((UIImage?) -> Void)? = nil,
        onPreActivityRouteChange: ((PreparedRoute?) -> Void)? = nil,
        onPostSaveCompleted: (() -> Void)? = nil,
        onCloseRequest: ((Bool) -> Void)? = nil,
        onSessionStateChange: ((ActivitySessionPortalState) -> Void)? = nil,
        onElapsedTimeChange: ((Int) -> Void)? = nil,
        onLiveSurfaceVisibilityChange: ((Bool) -> Void)? = nil
    ) {
        self.initialIntent = initialIntent
        self.shouldApplySmartGoalDefault = initialIntent == nil
        self.isVisible = isVisible
        self.isEmbeddedInToday = isEmbeddedInToday
        self.startRequest = startRequest
        self.preActivityPhotoRequest = preActivityPhotoRequest
        self.routeSelectionRequest = routeSelectionRequest
        self.routeRemovalRequest = routeRemovalRequest
        self.groupRunRequest = groupRunRequest
        self.startImmediately = startImmediately
        self.onLocationPermissionRequired = onLocationPermissionRequired
        self.onGoalModeChange = onGoalModeChange
        self.onPlanBuilderRequested = onPlanBuilderRequested
        self.onPreActivityPhotoChange = onPreActivityPhotoChange
        self.onPreActivityRouteChange = onPreActivityRouteChange
        self.onPostSaveCompleted = onPostSaveCompleted
        self.onCloseRequest = onCloseRequest
        self.onSessionStateChange = onSessionStateChange
        self.onElapsedTimeChange = onElapsedTimeChange
        self.onLiveSurfaceVisibilityChange = onLiveSurfaceVisibilityChange
    }

    var body: some View {
        ActivityFlowView(
            initialIntent: initialIntent,
            dependencies: ActivityFlowDependencies(
                activityStore: activityStore,
                guideStore: guideStore,
                guideCatalog: guideCatalog,
                assistantStore: assistantStore,
                checkInStore: checkInStore,
                goalStore: goalStore,
                musicStore: musicStore,
                recognitionStore: recognitionStore,
                measurementPreferences: measurementPreferences,
                gearStore: gearStore,
                liveShareStore: liveShareStore,
                liveGroupStore: liveGroupStore,
                safetyContactStore: safetyContactStore,
                onboardingStore: onboardingStore,
                personalizationStore: personalizationStore,
                trainingPlanStore: trainingPlanStore,
                socialStore: socialStore,
                connectivityStore: connectivityStore,
                communityRouteStore: communityRouteStore,
                weatherStore: weatherStore,
                tooltipCoordinator: tooltipCoordinator,
                phoneWorkoutCoordinator: phoneWorkoutCoordinator
            ),
            preferences: flowPreferences,
            host: ActivityFlowHost(
                isVisible: isVisible,
                isEmbeddedInToday: isEmbeddedInToday,
                startRequest: startRequest,
                preActivityPhotoRequest: preActivityPhotoRequest,
                routeSelectionRequest: routeSelectionRequest,
                routeRemovalRequest: routeRemovalRequest,
                groupRunRequest: groupRunRequest,
                startImmediately: startImmediately,
                onLocationPermissionRequired: onLocationPermissionRequired,
                shouldApplySmartGoalDefault: shouldApplySmartGoalDefault,
                onGoalModeChange: onGoalModeChange,
                onPlanBuilderRequested: onPlanBuilderRequested,
                onPreActivityPhotoChange: onPreActivityPhotoChange,
                onPreActivityRouteChange: onPreActivityRouteChange,
                onPostSaveCompleted: onPostSaveCompleted,
                onCloseRequest: onCloseRequest,
                onSessionStateChange: onSessionStateChange,
                onElapsedTimeChange: onElapsedTimeChange,
                onLiveSurfaceVisibilityChange: onLiveSurfaceVisibilityChange
            ),
            reduceMotion: reduceMotion,
            analyticsManager: analyticsManager
        )
    }

    private var flowPreferences: ActivityFlowPreferences {
        var preferences = ActivityFlowPreferences(
            preferredSessionPageRawValue: $preferredSessionPageRawValue,
            isVoiceGuideEnabled: $isVoiceGuideEnabled,
            autoPauseRunningEnabled: $autoPauseRunningEnabled,
            autoPauseCyclingEnabled: $autoPauseCyclingEnabled,
            autoPauseWalkingEnabled: $autoPauseWalkingEnabled,
            autoPauseHikingEnabled: $autoPauseHikingEnabled,
            autoStopAtGoalEnabled: $autoStopAtGoalEnabled,
            startWatchApp: $startWatchApp
        )
#if DEBUG
        preferences.routeTestMode = $routeTestMode
#endif
        return preferences
    }
}
