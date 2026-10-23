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
            do {
                _ = try await APIClient.shared.endWorkoutPresence(clientSessionID: clientSessionID)
            } catch {
                Self.logFailure(error, operation: "end")
            }
        }
    }

    private static func logFailure(_ error: Error, operation: String) {
        guard !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
        ActivityDiagnosticLog.error(.sync, "Workout presence \(operation) failed error=\(ActivityDiagnosticLog.errorCategory(error)) code=\((error as NSError).code)")
    }

    private func beginIfNeeded() {
        guard clientSessionID == nil else { return }
        let clientSessionID = UUID()
        self.clientSessionID = clientSessionID
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.clientSessionID == clientSessionID else { return }
                do {
                    _ = try await APIClient.shared.refreshWorkoutPresence(clientSessionID: clientSessionID)
                } catch {
                    Self.logFailure(error, operation: "heartbeat")
                }
                do {
                    try await Task.sleep(for: self.heartbeatInterval)
                } catch {
                    return
                }
            }
        }
    }
}
