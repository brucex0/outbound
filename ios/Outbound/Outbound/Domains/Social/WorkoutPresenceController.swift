import Combine
import Foundation

@MainActor
final class WorkoutPresenceController: ObservableObject {
    private let heartbeatInterval: Duration = .seconds(60)
    private var clientSessionID: UUID?
    private var heartbeatTask: Task<Void, Never>?

    func sync(with recordingState: RecordingState) {
        switch recordingState {
        case .active, .paused:
            beginIfNeeded()
        case .idle:
            end()
        }
    }

    func end() {
        guard let clientSessionID else { return }
        self.clientSessionID = nil
        let previousTask = heartbeatTask
        previousTask?.cancel()
        heartbeatTask = nil

        Task {
            if let previousTask {
                await previousTask.value
            }
            _ = try? await APIClient.shared.endWorkoutPresence(clientSessionID: clientSessionID)
        }
    }

    private func beginIfNeeded() {
        guard clientSessionID == nil else { return }
        let clientSessionID = UUID()
        self.clientSessionID = clientSessionID
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.clientSessionID == clientSessionID else { return }
                _ = try? await APIClient.shared.refreshWorkoutPresence(clientSessionID: clientSessionID)
                do {
                    try await Task.sleep(for: self.heartbeatInterval)
                } catch {
                    return
                }
            }
        }
    }
}
