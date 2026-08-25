import Foundation

@MainActor
final class RemoteSessionAnalysisProvider: SessionAnalysisProvider {
    let identifier: String
    let displayName: String
    private let model: String

    init(model: String) {
        self.model = model
        identifier = "remote-live-coach-\(model)"
        displayName = "Remote Live Coach (\(model))"
    }

    func analyze(_ request: SessionAnalysisRequest) async throws -> SessionAnalysisResult {
        let response = try await APIClient.shared.analyzeLiveCoach(.init(model: model, packet: request.nudgePacket))
        return SessionAnalysisResult(
            message: response.message,
            urgency: SessionAnalysisUrgency(rawValue: response.urgency) ?? .steady,
            shouldSpeak: response.shouldSpeak,
            generatedAt: Date(),
            providerID: identifier
        )
    }
}
