import Foundation
import FirebaseAuth

final class APIClient {
    static let shared = APIClient()
    private let base: URL
    private var authToken: String?

    private init() {
        let configuredBaseURL =
            Bundle.main.object(forInfoDictionaryKey: "OutboundAPIBaseURL") as? String
        let baseURLString = configuredBaseURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBaseURL = (baseURLString?.isEmpty == false ? baseURLString : nil)
            ?? "https://api.outbound.run/v1"
        guard let url = URL(string: resolvedBaseURL) else {
            fatalError("Invalid OutboundAPIBaseURL: \(resolvedBaseURL)")
        }
        self.base = url
    }

    func setToken(_ token: String?) { authToken = token }

    func fetchCoachProfile(userId: String) async throws -> CoachProfile {
        try await get("/coach/\(userId)/profile")
    }

    func rebuildCoachProfile(userId: String) async throws -> CoachProfile {
        try await post("/coach/\(userId)/rebuild", body: EmptyBody())
    }

    func uploadActivity(_ request: ActivityUploadRequest) async throws -> ActivityUploadResponse {
        try await post("/activities", body: request)
    }

    func chatWithAssistant(_ request: AssistantChatRequest) async throws -> AssistantChatResponse {
        try await post("/assistant/chat", body: request)
    }

    // MARK: - Helpers

    private func get<T: Decodable>(_ path: String) async throws -> T {
        var req = URLRequest(url: base.appendingPathComponent(path))
        if let token = try await resolvedAuthToken() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    private func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = try await resolvedAuthToken() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try encoder.encode(body)
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    private func resolvedAuthToken() async throws -> String? {
        if FirebaseBootstrap.isConfigured, let user = Auth.auth().currentUser {
            let refreshedToken = try await user.getIDToken()
            authToken = refreshedToken
            return refreshedToken
        }

        return authToken
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = decodeErrorMessage(from: data) ?? "Request failed."
            throw APIError.http(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1, message: message)
        }
    }

    private func decodeErrorMessage(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        return (try? decoder.decode(APIErrorPayload.self, from: data).error)
            ?? String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private struct EmptyBody: Encodable {}
}

enum APIError: LocalizedError {
    case http(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case let .http(statusCode, message):
            return "HTTP \(statusCode): \(message)"
        }
    }
}

private struct APIErrorPayload: Decodable {
    let error: String
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

struct ActivityUploadRequest: Encodable {
    let clientActivityId: String
    let syncSource: String
    let type: String
    let title: String
    let startedAt: Date
    let endedAt: Date
    let durationSecs: Int
    let distanceM: Double
    let avgPace: Double?
    let route: SavedRoute?
}

struct ActivityUploadResponse: Decodable {
    let id: String
    let clientActivityId: String?
    let status: String
    let uploadedAt: Date
}
