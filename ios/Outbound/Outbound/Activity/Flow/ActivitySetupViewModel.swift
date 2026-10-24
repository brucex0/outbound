import Combine
import SwiftUI
import PhotosUI

/// Presentation state for one retained activity flow; domain data stays in its existing stores.
@MainActor
final class ActivitySetupViewModel: ObservableObject {
    @Published var isPreActivityCameraPresented = false
    @Published var isPreActivityPhotoPreviewPresented = false
    @Published var selectedPreActivityPhotoItem: PhotosPickerItem? = nil
    @Published var plannedIntent: SessionIntent? = nil
    @Published var selectedGoalMode: SessionGoalMode = .freestyle
    @Published var selectedWorkoutChoice: LaunchWorkoutChoice = .sport(.run)
    @Published var manualActivityGoal: ActivityGoal = .freestyle
    @Published var manualSetupDrafts: [SportType: ActivityManualSetupDraft] = [:]
    @Published var customDistanceText = ""
    @Published var customTimeText = ""
    @Published var customCaloriesText = ""
    @Published var goalEditorSelection: ActivityGoal? = nil
    @Published var isCaloriesWeightPromptPresented = false
    @Published var caloriesWeightText = ""
    @Published var pendingCaloriesWeightAction: PendingCaloriesWeightAction? = nil
    @Published var plannedWorkoutIntent: SessionIntent? = nil
    @Published var curatedWorkoutIntent: SessionIntent? = nil
    @Published var didApplySmartGoalDefault = false
    @Published var didApplyDefaultSessionShoe = false
    @Published var isIndoorSession = false
    @Published var companionType: ActivityCompanionType? = nil
    @Published var selectedSessionShoeID: UUID? = nil
    @Published var isGroupJoinAlertPresented = false
    @Published var groupInviteText = ""
    @Published var isGroupParticipantsExpanded = false
    @Published var isMusicSetupExpanded = false
    @Published var isSessionOptionsExpanded = false
    @Published var setupSheet: ActivitySetupSheet? = nil
    @Published var musicSearchText = ""
    @Published var musicSearchCategory: MusicSearchCategory = .songs
    @Published var isAddShoePresented = false
    @Published var showsTrustedContacts = false
    @Published var showsCuratedWorkouts = false
    @Published var showsRacePlanner = false
    @Published var showsRouteLibrary = false
    @Published var intentBeforeSelectedRoute: SessionIntent? = nil
    @Published var selectedRouteDistanceMeters: Double? = nil
    @Published var selectedGuidanceChallenge: LiveGuidanceChallenge = .off

    let dependencies: ActivityFlowDependencies
    let preferences: ActivityFlowPreferences
    let launchPreferenceStore: ActivityLaunchPreferenceStore

    init(dependencies: ActivityFlowDependencies, preferences: ActivityFlowPreferences, launchPreferenceStore: ActivityLaunchPreferenceStore) {
        self.dependencies = dependencies
        self.preferences = preferences
        self.launchPreferenceStore = launchPreferenceStore
    }
}
