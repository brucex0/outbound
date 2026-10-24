import SwiftUI

/// References to existing domain owners, injected at the SwiftUI boundary.
struct ActivityFlowDependencies {
    let activityStore: ActivityStore
    let guideStore: GuideStore
    let guideCatalog: GuideCatalogStore
    let assistantStore: AssistantStore
    let checkInStore: DailyCheckInStore
    let goalStore: GoalStore
    let musicStore: MusicStore
    let recognitionStore: RecognitionStore
    let measurementPreferences: MeasurementPreferences
    let gearStore: GearStore
    let liveShareStore: LiveShareStore
    let liveGroupStore: LiveGroupStore
    let safetyContactStore: SafetyContactStore
    let onboardingStore: OnboardingStore
    let personalizationStore: PersonalizationStore
    let trainingPlanStore: TrainingPlanStore
    let socialStore: TogetherStore
    let connectivityStore: ConnectivityStore
    let communityRouteStore: CommunityRouteStore
    let weatherStore: SituationalWeatherStore
    let tooltipCoordinator: TooltipCoordinator
    let phoneWorkoutCoordinator: PhoneWorkoutSessionCoordinator
}
