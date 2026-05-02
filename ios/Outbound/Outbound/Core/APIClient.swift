import Foundation

final class APIClient {
    static let shared = APIClient()
    private let base = URL(string: "https://api.outbound.run/v1")!
    private var authToken: String?

    func setToken(_ token: String?) { authToken = token }

    func fetchCoachProfile(userId: String) async throws -> CoachProfile {
        try await get("/coach/\(userId)/profile")
    }

    func rebuildCoachProfile(userId: String) async throws -> CoachProfile {
        try await post("/coach/\(userId)/rebuild", body: EmptyBody())
    }

    func uploadActivity(_ payload: [String: Any]) async throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try await postRaw("/activities", body: data)
    }

    func chatWithAssistant(_ request: AssistantChatRequest) async throws -> AssistantChatResponse {
        try await post("/assistant/chat", body: request)
    }

    // MARK: - Helpers

    private func get<T: Decodable>(_ path: String) async throws -> T {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.setValue("Bearer \(authToken ?? "")", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        return try decoder.decode(T.self, from: data)
    }

    private func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(authToken ?? "")", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONEncoder().encode(body)
        let (data, _) = try await URLSession.shared.data(for: req)
        return try decoder.decode(T.self, from: data)
    }

    private func postRaw(_ path: String, body: Data) async throws -> [String: Any] {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(authToken ?? "")", forHTTPHeaderField: "Authorization")
        req.httpBody = body
        let (data, _) = try await URLSession.shared.data(for: req)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private struct EmptyBody: Encodable {}
}

struct AssistantChatRequest: Encodable {
    let prompt: String
    let capability: String
    let context: AssistantChatAPIContext
    let messages: [AssistantChatAPIPriorMessage]
    let firebaseUid: String?
}

struct AssistantChatAPIContext: Encodable {
    let coachName: String
    let activityCount: Int
    let weeklyDistanceKilometers: Double
    let currentGoalSummary: String?
    let currentScreen: String?
    let isRecordingActive: Bool
}

struct AssistantChatAPIPriorMessage: Encodable {
    let role: String
    let text: String
    let capability: String?
}

struct AssistantChatResponse: Decodable {
    let message: String
}
