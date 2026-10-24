import Combine
import SwiftUI
import PhotosUI

/// Presentation state for one retained activity flow; domain data stays in its existing stores.
@MainActor
final class ActivityCountdownViewModel: ObservableObject {
    @Published var countdownStep: ActivityStartCountdownStep? = nil
    @Published var countdownTask: Task<Void, Never>? = nil

    func begin(
        reduceMotion: @escaping () -> Bool,
        onStep: @escaping (ActivityStartCountdownStep) -> Void,
        onComplete: @escaping () -> Void
    ) {
        countdownTask = Task { @MainActor in
            for step in ActivityStartCountdownStep.sequence {
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: reduceMotion() ? 0.12 : 0.22)) {
                    self.countdownStep = step
                }
                onStep(step)
                do {
                    try await Task.sleep(nanoseconds: step.durationNanoseconds)
                } catch {
                    return // Countdown cancellation is normal control flow.
                }
            }
            guard !Task.isCancelled else { return }
            onComplete()
        }
    }
}
