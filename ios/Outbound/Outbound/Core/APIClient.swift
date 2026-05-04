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

    func fetchTrainingPlanState(readiness: DailyReadiness?) async throws -> TrainingPlanStateResponse {
        try await get(
            "/coach/plans/state",
            queryItems: readiness.map { [URLQueryItem(name: "readiness", value: $0.rawValue)] } ?? []
        )
    }

    func createTrainingPlan(
        from recommendation: TrainingPlanRecommendation,
        readiness: DailyReadiness?
    ) async throws -> TrainingPlanStateResponse {
        try await post(
            "/coach/plans",
            body: TrainingPlanSelectionRequest(
                candidateID: recommendation.id,
                templateID: recommendation.template.id,
                durationWeeks: recommendation.durationWeeks,
                sessionsPerWeek: recommendation.sessionsPerWeek,
                targetWeeklyMinutes: recommendation.targetWeeklyMinutes,
                longSessionMinutes: recommendation.longSessionMinutes,
                readiness: readiness?.rawValue
            )
        )
    }

    func clearActiveTrainingPlan(readiness: DailyReadiness?) async throws -> TrainingPlanStateResponse {
        try await delete(
            "/coach/plans/active",
            queryItems: readiness.map { [URLQueryItem(name: "readiness", value: $0.rawValue)] } ?? []
        )
    }

    // MARK: - Helpers

    private func get<T: Decodable>(
        _ path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        var req = URLRequest(url: url(for: path, queryItems: queryItems))
        if let token = try await resolvedAuthToken() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    private func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        var req = URLRequest(url: url(for: path))
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

    private func delete<T: Decodable>(
        _ path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        var req = URLRequest(url: url(for: path, queryItems: queryItems))
        req.httpMethod = "DELETE"
        if let token = try await resolvedAuthToken() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(response: response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    private func url(for path: String, queryItems: [URLQueryItem] = []) -> URL {
        let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var url = base
        for component in trimmedPath.split(separator: "/") {
            url.appendPathComponent(String(component))
        }

        guard !queryItems.isEmpty else { return url }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        return components?.url ?? url
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

struct TrainingPlanStateResponse: Codable {
    let activePlan: ActiveTrainingPlan?
    let recommendations: [TrainingPlanRecommendation]
    let currentWeek: TrainingPlanWeekSnapshot?
    let todaySuggestion: TodayTrainingSuggestion?
}

private struct TrainingPlanSelectionRequest: Encodable {
    let candidateID: String
    let templateID: String
    let durationWeeks: Int
    let sessionsPerWeek: Int
    let targetWeeklyMinutes: Int
    let longSessionMinutes: Int
    let readiness: String?
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
    let elevationM: Double?
    let avgPace: Double?
    let avgHeartRate: Int?
    let route: SavedRoute?
}

struct ActivityUploadResponse: Decodable {
    let id: String
    let clientActivityId: String?
    let status: String
    let uploadedAt: Date
}
