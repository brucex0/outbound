import Combine
import SwiftUI
import PhotosUI

/// Presentation state for one retained activity flow; domain data stays in its existing stores.
@MainActor
final class LiveActivityViewModel: ObservableObject {
    @Published var activePage: SessionPage = .map
    @Published var isLiveWorkoutPanelExpanded = false
    @Published var capturedPhotos: [(UIImage, PhotoMetadata)] = []
    @Published var isCapturingSessionPhoto = false
#if DEBUG
    @Published var liveGroupTopControlsHeight: CGFloat = 0
#endif
}
