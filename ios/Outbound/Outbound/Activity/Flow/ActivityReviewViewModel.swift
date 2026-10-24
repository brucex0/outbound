import Combine
import SwiftUI
import PhotosUI

/// Presentation state for one retained activity flow; domain data stays in its existing stores.
@MainActor
final class ActivityReviewViewModel: ObservableObject {
    @Published var pendingActivity: PendingFinishedActivity? = nil
    @Published var postSaveStretchContext: PostSavedStretchContext? = nil
    @Published var postSaveCelebrationActivity: SavedActivity? = nil
    @Published var lastPostSaveCelebrationExposureID: UUID? = nil
    @Published var elevationCorrectionTask: Task<ActivitySummary, Never>? = nil
}
