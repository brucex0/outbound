import SwiftUI

struct ActivityFlowHost {
    let isVisible: Bool
    let isEmbeddedInToday: Bool
    let startRequest: Int
    let preActivityPhotoRequest: Int
    let routeSelectionRequest: Int
    let routeRemovalRequest: Int
    let groupRunRequest: Int
    let startImmediately: Bool
    let onLocationPermissionRequired: (() -> Void)?
    let shouldApplySmartGoalDefault: Bool
    let onGoalModeChange: ((SessionGoalMode) -> Void)?
    let onPlanBuilderRequested: (() -> Void)?
    let onPreActivityPhotoChange: ((UIImage?) -> Void)?
    let onPreActivityRouteChange: ((PreparedRoute?) -> Void)?
    let onPostSaveCompleted: (() -> Void)?
    let onCloseRequest: ((Bool) -> Void)?
    let onSessionStateChange: ((ActivitySessionPortalState) -> Void)?
    let onElapsedTimeChange: ((Int) -> Void)?
    let onLiveSurfaceVisibilityChange: ((Bool) -> Void)?
}
