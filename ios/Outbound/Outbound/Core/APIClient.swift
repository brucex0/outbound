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
        let state: PlanningAPIStateResponse = try await get("/planning/state")
        let activitySuggestion = try? await fetchActivitySuggestion()
        return state.trainingPlanState(readiness: readiness, activitySuggestion: activitySuggestion)
    }

    func createTrainingPlan(
        from recommendation: TrainingPlanRecommendation,
        readiness: DailyReadiness?
    ) async throws -> TrainingPlanStateResponse {
        let state: PlanningAPIStateResponse = try await post(
            "/planning/goals",
            body: PlanningGoalRequest(recommendation: recommendation)
        )
        let activitySuggestion = try? await fetchActivitySuggestion()
        return state.trainingPlanState(
            readiness: readiness,
            fallbackRecommendation: recommendation,
            activitySuggestion: activitySuggestion
        )
    }

    func submitTrainingReadiness(_ readiness: DailyReadiness) async throws -> TrainingPlanStateResponse {
        let state: PlanningAPIStateResponse = try await post(
            "/planning/readiness",
            body: PlanningReadinessRequest(readiness: readiness)
        )
        let activitySuggestion = try? await fetchActivitySuggestion()
        return state.trainingPlanState(readiness: readiness, activitySuggestion: activitySuggestion)
    }

    func clearActiveTrainingPlan(readiness: DailyReadiness?) async throws -> TrainingPlanStateResponse {
        let state: PlanningAPIStateResponse = try await delete("/planning/plan")
        let activitySuggestion = try? await fetchActivitySuggestion()
        return state.trainingPlanState(readiness: readiness, activitySuggestion: activitySuggestion)
    }

    func fetchActivitySuggestion() async throws -> ActivitySuggestionResponse {
        try await get("/planning/activity-suggestion")
    }

    func fetchPlanRecommendations() async throws -> PlanRecommendationsResponse {
        try await get("/planning/recommendations")
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

private extension PlanningAPIStateResponse {
    func trainingPlanState(
        readiness: DailyReadiness?,
        fallbackRecommendation: TrainingPlanRecommendation? = nil,
        activitySuggestion: ActivitySuggestionResponse? = nil
    ) -> TrainingPlanStateResponse {
        guard let goal, let plan else {
            return TrainingPlanStateResponse(
                activePlan: nil,
                recommendations: recommendations ?? [],
                currentWeek: nil,
                todaySuggestion: activitySuggestion?.todayTrainingSuggestion(),
                activitySuggestion: activitySuggestion
            )
        }

        let calendar = Calendar.current
        let createdAt = APIDateParser.date(from: plan.createdAt)
            ?? APIDateParser.date(from: goal.createdAt)
            ?? Date()
        let focus = TrainingPlanFocus.apiFocus(from: goal, fallbackRecommendation: fallbackRecommendation)
        let sport = TrainingPlanSport.apiSport(from: goal.primaryModality)
        let weekWorkouts = currentWeekWorkouts(calendar: calendar)
        let plannedThisWeek = weekWorkouts.isEmpty
            ? Array(upcoming.prefix(goal.daysPerWeekTarget ?? fallbackRecommendation?.sessionsPerWeek ?? 3))
            : weekWorkouts
        let scheduledWorkouts = plannedThisWeek.map { $0.trainingPlanWorkout() }
        let durationWeeks = fallbackRecommendation?.durationWeeks
            ?? Self.estimatedDurationWeeks(createdAt: createdAt, workouts: upcoming, calendar: calendar)
        let sessionsPerWeek = goal.daysPerWeekTarget
            ?? fallbackRecommendation?.sessionsPerWeek
            ?? max(1, scheduledWorkouts.count)
        let targetWeeklyMinutes = fallbackRecommendation?.targetWeeklyMinutes
            ?? max(20, scheduledWorkouts.reduce(0) { $0 + $1.durationMinutesRounded })
        let longSessionMinutes = goal.maxSessionMinutes
            ?? fallbackRecommendation?.longSessionMinutes
            ?? max(20, upcoming.map { Int(ceil(Double($0.durationSeconds) / 60.0)) }.max() ?? 30)

        let activePlan = ActiveTrainingPlan(
            id: plan.id,
            templateID: fallbackRecommendation?.template.id ?? "adaptive-\(goal.id)",
            focus: focus,
            sport: sport,
            title: fallbackRecommendation?.template.title ?? focus.adaptiveTitle,
            subtitle: currentVersion?.summary ?? "Adaptive plan generated from your recent training.",
            durationWeeks: durationWeeks,
            sessionsPerWeek: sessionsPerWeek,
            targetWeeklyMinutes: targetWeeklyMinutes,
            longSessionMinutes: longSessionMinutes,
            createdAt: createdAt
        )

        let completedWorkouts = scheduledWorkoutsForCurrentWeek(calendar: calendar, status: "completed")
        let completedSessions = completedWorkouts.count
        let completedMinutes = completedWorkouts.reduce(0) { $0 + Int(ceil(Double($1.durationSeconds) / 60.0)) }
        let targetMinutes = max(1, scheduledWorkouts.reduce(0) { $0 + $1.durationMinutesRounded })
        let targetSessions = max(1, scheduledWorkouts.filter { !$0.isOptional }.count)
        let currentWeekIndex = Self.currentWeekIndex(createdAt: createdAt, calendar: calendar)
        let progressPercent = min(
            1,
            max(
                Double(completedSessions) / Double(targetSessions),
                Double(completedMinutes) / Double(targetMinutes)
            )
        )
        let weekSnapshot = TrainingPlanWeekSnapshot(
            currentWeekIndex: min(currentWeekIndex, durationWeeks),
            totalWeeks: durationWeeks,
            completedSessions: completedSessions,
            targetSessions: targetSessions,
            completedMinutes: completedMinutes,
            targetMinutes: targetMinutes,
            progressPercent: progressPercent,
            summaryLine: "\(completedSessions) of \(targetSessions) sessions, \(completedMinutes) of \(targetMinutes) min this week",
            coachLine: coachLine(fallbackFocus: focus),
            focus: plan.currentPhase.capitalized,
            weekSummary: currentVersion?.summary ?? "This week is being generated from your current training data.",
            scheduledWorkouts: scheduledWorkouts,
            notes: latestAdjustment.map { [$0.message] } ?? []
        )

        let apiWorkout = today ?? upcoming.first
        let todaySuggestion: TodayTrainingSuggestion?
        if let activityTodaySuggestion = activitySuggestion?.todayTrainingSuggestion() {
            todaySuggestion = activityTodaySuggestion
        } else if let apiWorkout {
            todaySuggestion = makeTodaySuggestion(
                for: apiWorkout.trainingPlanWorkout(dayLabel: "Today"),
                apiWorkout: apiWorkout,
                readiness: readiness
            )
        } else {
            todaySuggestion = nil
        }

        return TrainingPlanStateResponse(
            activePlan: activePlan,
            recommendations: [],
            currentWeek: weekSnapshot,
            todaySuggestion: todaySuggestion,
            activitySuggestion: activitySuggestion
        )
    }

    private func currentWeekWorkouts(calendar: Calendar) -> [PlanningAPIWorkout] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: Date()) else {
            return upcoming
        }
        return upcoming.filter { workout in
            guard let scheduledDate = APIDateParser.date(from: workout.scheduledDate) else { return false }
            return scheduledDate >= week.start && scheduledDate < week.end
        }
    }

    private func scheduledWorkoutsForCurrentWeek(calendar: Calendar, status: String) -> [PlanningAPIWorkout] {
        currentWeekWorkouts(calendar: calendar).filter { $0.status == status }
    }

    private func coachLine(fallbackFocus: TrainingPlanFocus) -> String {
        if let latestAdjustment {
            return latestAdjustment.message
        }

        if planningStatus == "reassessing" {
            return "I am checking the latest training data before locking in the next adjustment."
        }

        switch athleteState?.fatigueRisk {
        case "high":
            return "The plan is watching fatigue today, so keep this one controlled."
        case "medium":
            return "There is useful work here, but the win is staying smooth."
        default:
            return "This session is matched to the current \(fallbackFocus.shortTitle.lowercased()) plan."
        }
    }

    private func makeTodaySuggestion(
        for workout: TrainingPlanWorkout,
        apiWorkout: PlanningAPIWorkout,
        readiness: DailyReadiness?
    ) -> TodayTrainingSuggestion {
        let lowReadiness = readiness == .lowEnergy || readiness == .stressed
        let adjustmentLine = latestAdjustment?.message
            ?? (lowReadiness ? "Dialed in around today's readiness." : nil)
        let coachLine = latestAdjustment?.message ?? workout.coachCue
        let suggestion = SuggestedSession(
            id: "plan-\(apiWorkout.id)",
            sport: SportType.apiSport(from: apiWorkout.modality),
            title: workout.title,
            durationLabel: workout.durationLabel,
            activityLabel: workout.kind.displayName,
            framing: workout.purpose,
            coachLine: coachLine,
            startLabel: "Start now",
            targetDistanceMeters: workout.targetDistanceMeters,
            targetDurationSeconds: workout.durationSeconds,
            routeName: nil,
            workoutSteps: workout.sessionIntentSteps
        )

        return TodayTrainingSuggestion(
            title: workout.title,
            detail: "Adaptive session • \(workout.durationLabel) • \(workout.effortLabel)",
            coachLine: coachLine,
            adjustmentLine: adjustmentLine,
            suggestedSession: suggestion,
            workout: workout,
            stepSummary: workout.stepSummary
        )
    }

    private static func currentWeekIndex(createdAt: Date, calendar: Calendar) -> Int {
        let planWeekStart = calendar.dateInterval(of: .weekOfYear, for: createdAt)?.start ?? createdAt
        return max(1, (calendar.dateComponents([.weekOfYear], from: planWeekStart, to: Date()).weekOfYear ?? 0) + 1)
    }

    private static func estimatedDurationWeeks(
        createdAt: Date,
        workouts: [PlanningAPIWorkout],
        calendar: Calendar
    ) -> Int {
        let lastWorkoutDate = workouts
            .compactMap { APIDateParser.date(from: $0.scheduledDate) }
            .max()
        guard let lastWorkoutDate else { return 4 }
        let planWeekStart = calendar.dateInterval(of: .weekOfYear, for: createdAt)?.start ?? createdAt
        let workoutWeekStart = calendar.dateInterval(of: .weekOfYear, for: lastWorkoutDate)?.start ?? lastWorkoutDate
        return max(1, (calendar.dateComponents([.weekOfYear], from: planWeekStart, to: workoutWeekStart).weekOfYear ?? 0) + 1)
    }
}

private extension PlanningAPIWorkout {
    func trainingPlanWorkout(dayLabel overrideDayLabel: String? = nil) -> TrainingPlanWorkout {
        let mappedSteps = blocks.flatMap { $0.trainingPlanSteps(workoutID: id) }
        let steps = mappedSteps.isEmpty
            ? [
                TrainingPlanWorkoutStep(
                    id: "\(id)-main",
                    kind: stimulus.stepKind,
                    label: title,
                    durationSeconds: durationSeconds,
                    detail: stimulus.stepDetail
                )
            ]
            : mappedSteps

        return TrainingPlanWorkout(
            id: id,
            title: title,
            kind: stimulus.workoutKind,
            dayLabel: overrideDayLabel ?? APIDateParser.weekdayLabel(from: scheduledDate),
            summary: stimulus.summaryLabel,
            purpose: stimulus.purposeLabel,
            coachCue: stimulus.coachCue,
            effortLabel: stimulus.effortLabel,
            durationSeconds: durationSeconds,
            distanceLabel: distanceMeters.map { APIDateParser.distanceLabel(meters: $0) },
            steps: steps,
            isOptional: !isKeyWorkout
        )
    }
}

private extension PlanningAPIWorkoutBlock {
    func trainingPlanSteps(workoutID: String) -> [TrainingPlanWorkoutStep] {
        if steps.isEmpty, let durationSeconds {
            return [
                TrainingPlanWorkoutStep(
                    id: "\(workoutID)-\(blockType)",
                    kind: stimulus.stepKind,
                    label: blockType.capitalized,
                    durationSeconds: durationSeconds,
                    detail: stimulus.stepDetail
                )
            ]
        }

        return steps.map { step in
            TrainingPlanWorkoutStep(
                id: step.id,
                kind: step.kind.stepKind,
                label: step.label,
                durationSeconds: step.durationSeconds ?? durationSeconds ?? 0,
                detail: step.detail ?? step.kind.stepDetail
            )
        }
    }
}

private extension TrainingPlanFocus {
    static func apiFocus(
        from goal: PlanningAPIGoal,
        fallbackRecommendation: TrainingPlanRecommendation?
    ) -> TrainingPlanFocus {
        if let focus = TrainingPlanFocus(rawValue: goal.type) {
            return focus
        }

        if let targetDistanceMeters = goal.targetDistanceMeters {
            if targetDistanceMeters >= 20_000 { return .halfMarathon }
            if targetDistanceMeters >= 15_000 { return .tenMile }
            if targetDistanceMeters >= 9_000 { return .tenK }
            if targetDistanceMeters >= 4_000 { return .fiveK }
        }

        let loweredType = goal.type.lowercased()
        if loweredType.contains("comeback") { return .comeback }
        if loweredType.contains("half") { return .halfMarathon }
        if loweredType.contains("10k") { return .tenK }
        if loweredType.contains("5k") { return .fiveK }
        return fallbackRecommendation?.template.focus ?? .consistency
    }

    var targetDistanceMeters: Double? {
        switch self {
        case .fiveK: return 5_000
        case .tenK: return 10_000
        case .tenMile: return 16_093.4
        case .halfMarathon: return 21_097.5
        case .consistency, .comeback: return nil
        }
    }

    var adaptiveTitle: String {
        switch self {
        case .consistency: return "Adaptive consistency builder"
        case .comeback: return "Adaptive comeback plan"
        case .fiveK: return "Adaptive 5K plan"
        case .tenK: return "Adaptive 10K plan"
        case .tenMile: return "Adaptive 10 mile plan"
        case .halfMarathon: return "Adaptive half marathon plan"
        }
    }
}

private extension TrainingPlanSport {
    var apiPlanningModality: String {
        switch self {
        case .run: return "run"
        case .walk: return "walk"
        case .bike, .mixed: return "run"
        }
    }

    static func apiSport(from modality: String) -> TrainingPlanSport {
        switch modality {
        case "walk": return .walk
        case "bike": return .bike
        case "run": return .run
        default: return .mixed
        }
    }
}

private extension SportType {
    static func apiSport(from modality: String) -> SportType {
        modality == "bike" ? .bike : .run
    }
}

private extension String {
    var workoutKind: TrainingPlanWorkoutKind {
        switch self {
        case "longEndurance": return .longRun
        case "threshold": return .tempo
        case "speed": return .interval
        case "recovery": return .recovery
        case "mobility", "strength", "hypertrophy": return .crossTrain
        default: return .easy
        }
    }

    var stepKind: TrainingPlanWorkoutStepKind {
        switch self {
        case "warmup": return .warmup
        case "cooldown": return .cooldown
        case "walk": return .walk
        case "threshold": return .tempo
        case "speed": return .interval
        case "longEndurance": return .steady
        case "recovery": return .recovery
        case "mobility", "strength", "hypertrophy", "crossTrain": return .crossTrain
        case "race": return .race
        default: return .run
        }
    }

    var effortLabel: String {
        switch self {
        case "threshold", "speed": return "Moderate"
        case "longEndurance": return "Easy endurance"
        case "recovery", "mobility": return "Very easy"
        default: return "Easy"
        }
    }

    var summaryLabel: String {
        switch self {
        case "longEndurance": return "A longer aerobic session."
        case "threshold": return "Controlled faster running with easy support."
        case "speed": return "Shorter quality work with full control."
        case "recovery": return "A lighter session to absorb the week."
        case "mobility": return "Mobility and easy movement."
        case "strength", "hypertrophy": return "Strength support for the plan."
        default: return "A steady aerobic session."
        }
    }

    var purposeLabel: String {
        switch self {
        case "longEndurance": return "Build durable aerobic capacity."
        case "threshold": return "Raise sustainable effort without overreaching."
        case "speed": return "Touch faster mechanics while keeping the dose small."
        case "recovery", "mobility": return "Protect consistency while lowering strain."
        case "strength", "hypertrophy": return "Support resilience for future sessions."
        default: return "Keep the plan moving with manageable aerobic work."
        }
    }

    var coachCue: String {
        switch self {
        case "threshold", "speed": return "Smooth and controlled beats forcing it today."
        case "longEndurance": return "Stay patient early so the finish still feels composed."
        case "recovery", "mobility": return "Let this feel restorative from the first minute."
        default: return "Keep it conversational and leave a little in reserve."
        }
    }

    var stepDetail: String {
        switch self {
        case "threshold": return "Comfortably hard, never strained."
        case "speed": return "Fast but relaxed."
        case "longEndurance": return "Easy enough to repeat next week."
        case "recovery", "mobility": return "Light and restorative."
        default: return "Conversational effort."
        }
    }
}

private enum APIDateParser {
    static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        if let date = fractionalFormatter.date(from: value) {
            return date
        }
        return plainFormatter.date(from: value)
    }

    static func weekdayLabel(from value: String) -> String {
        guard let date = date(from: value) else { return "Planned" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    static func distanceLabel(meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return "\(Int(meters.rounded())) m"
    }

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
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
    let activitySuggestion: ActivitySuggestionResponse?
}

struct ActivitySuggestionResponse: Codable, Equatable {
    let status: String
    let source: String
    let relationship: String
    let primary: ActivitySuggestionPayload?
    let alternates: [ActivitySuggestionPayload]
    let coachLine: String
    let planningStatus: String
    let generatedAt: String
    let validForDate: String
    let validUntil: String
    let planVersionId: String?
    let planContext: ActivitySuggestionPlanContext?
    let activityWatermark: ActivitySuggestionWatermark
    let decision: ActivitySuggestionDecision
}

struct PlanRecommendationsResponse: Codable, Equatable {
    let recommendations: [TrainingPlanRecommendation]
    let source: String
    let generatedAt: Date
    let activePlanId: String?
    let catalogVersion: String?
}

struct ActivitySuggestionPlanContext: Codable, Equatable {
    let planId: String
    let planVersionId: String?
    let title: String?
}

struct ActivitySuggestionPayload: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let modality: String
    let stimulus: String
    let durationMinutes: Int
    let effortLabel: String
    let intensityModel: String
    let why: String
    let steps: [String]
    let startLabel: String
    let plannedWorkoutId: String?
    let archetypeId: String?
    let optional: Bool
}

struct ActivitySuggestionWatermark: Codable, Equatable {
    let lastActivityId: String?
    let lastActivityStartedAt: String?
}

struct ActivitySuggestionDecision: Codable, Equatable {
    let algorithmVersion: String
    let reasons: [String]
    let safetyFlags: [String]
}

extension ActivitySuggestionResponse {
    var isPlanLinkedToPlan: Bool {
        planVersionId != nil
            || planContext != nil
            || source == "plan"
            || ["todayPlannedWorkout", "adjustedFromPlan", "planFallback"].contains(relationship)
            || decision.reasons.contains("active_plan_present")
            || primary?.plannedWorkoutId != nil
            || alternates.contains { $0.plannedWorkoutId != nil }
    }

    var shouldSuppressLocalSuggestion: Bool {
        status == "restRecommended" || status == "noSuggestion" || primary != nil
    }

    func isValid(now: Date = Date()) -> Bool {
        guard let validUntilDate = APIDateParser.date(from: validUntil) else {
            return false
        }
        return now < validUntilDate
    }

    func todayTrainingSuggestion() -> TodayTrainingSuggestion? {
        primary?.todayTrainingSuggestion(coachLine: coachLine)
    }
}

extension ActivitySuggestionPayload {
    func todayTrainingSuggestion(coachLine: String) -> TodayTrainingSuggestion {
        let durationSeconds = durationMinutes * 60
        let stepDuration = max(60, durationSeconds / max(1, steps.count))
        let workoutSteps = steps.enumerated().map { index, step in
            TrainingPlanWorkoutStep(
                id: "\(id)-step-\(index)",
                kind: stimulus.stepKind,
                label: step,
                durationSeconds: stepDuration,
                detail: effortLabel
            )
        }
        let workout = TrainingPlanWorkout(
            id: plannedWorkoutId ?? id,
            title: title,
            kind: stimulus.workoutKind,
            dayLabel: "Today",
            summary: why,
            purpose: why,
            coachCue: coachLine,
            effortLabel: effortLabel,
            durationSeconds: durationSeconds,
            distanceLabel: nil,
            steps: workoutSteps.isEmpty
                ? [
                    TrainingPlanWorkoutStep(
                        id: "\(id)-main",
                        kind: stimulus.stepKind,
                        label: title,
                        durationSeconds: durationSeconds,
                        detail: effortLabel
                    )
                ]
                : workoutSteps,
            isOptional: optional
        )
        let suggestion = SuggestedSession(
            id: plannedWorkoutId ?? archetypeId ?? id,
            sport: SportType.apiSport(from: modality),
            title: title,
            durationLabel: "\(durationMinutes) min",
            activityLabel: effortLabel.lowercased(),
            framing: why,
            coachLine: coachLine,
            startLabel: startLabel
        )

        return TodayTrainingSuggestion(
            title: title,
            detail: "\(durationMinutes) min • \(effortLabel)",
            coachLine: coachLine,
            adjustmentLine: optional ? "Optional" : nil,
            suggestedSession: suggestion,
            workout: workout,
            stepSummary: steps
        )
    }
}

private struct PlanningGoalRequest: Encodable {
    let type: String
    let primaryModality: String
    let targetDistanceMeters: Double?
    let priority: String
    let daysPerWeekTarget: Int
    let maxSessionMinutes: Int
    let riskTolerance: String
    let constraints: PlanningGoalConstraints

    init(recommendation: TrainingPlanRecommendation) {
        type = recommendation.template.focus.rawValue
        primaryModality = recommendation.template.sport.apiPlanningModality
        targetDistanceMeters = recommendation.template.focus.targetDistanceMeters
        priority = recommendation.template.focus == .comeback ? "rebuild" : "fitness"
        daysPerWeekTarget = recommendation.sessionsPerWeek
        maxSessionMinutes = recommendation.longSessionMinutes
        riskTolerance = "balanced"
        constraints = PlanningGoalConstraints(
            candidateID: recommendation.id,
            templateID: recommendation.template.id,
            targetWeeklyMinutes: recommendation.targetWeeklyMinutes,
            durationWeeks: recommendation.durationWeeks
        )
    }
}

private struct PlanningGoalConstraints: Encodable {
    let candidateID: String
    let templateID: String
    let targetWeeklyMinutes: Int
    let durationWeeks: Int
}

private struct PlanningReadinessRequest: Encodable {
    let energy: Int
    let soreness: Int
    let sleepQuality: Int
    let stress: Int
    let motivation: Int
    let illnessOrPain: Bool

    init(readiness: DailyReadiness) {
        switch readiness {
        case .lowEnergy:
            energy = 2
            soreness = 2
            sleepQuality = 2
            stress = 3
            motivation = 2
            illnessOrPain = false
        case .okay:
            energy = 3
            soreness = 2
            sleepQuality = 3
            stress = 2
            motivation = 3
            illnessOrPain = false
        case .ready:
            energy = 5
            soreness = 1
            sleepQuality = 4
            stress = 1
            motivation = 5
            illnessOrPain = false
        case .stressed:
            energy = 2
            soreness = 3
            sleepQuality = 2
            stress = 5
            motivation = 2
            illnessOrPain = false
        }
    }
}

private struct PlanningAPIStateResponse: Decodable {
    let goal: PlanningAPIGoal?
    let plan: PlanningAPIPlan?
    let currentVersion: PlanningAPIVersion?
    let today: PlanningAPIWorkout?
    let upcoming: [PlanningAPIWorkout]
    let recommendations: [TrainingPlanRecommendation]?
    let athleteState: PlanningAPIAthleteState?
    let latestAdjustment: PlanningAPIAdjustment?
    let planningStatus: String
}

private struct PlanningAPIGoal: Decodable {
    let id: String
    let type: String
    let primaryModality: String
    let targetDistanceMeters: Double?
    let daysPerWeekTarget: Int?
    let maxSessionMinutes: Int?
    let createdAt: String?
}

private struct PlanningAPIPlan: Decodable {
    let id: String
    let currentPhase: String
    let createdAt: String?
}

private struct PlanningAPIVersion: Decodable {
    let versionNumber: Int
    let reason: String
    let summary: String
}

private struct PlanningAPIWorkout: Decodable {
    let id: String
    let scheduledDate: String
    let modality: String
    let stimulus: String
    let title: String
    let durationSeconds: Int
    let distanceMeters: Double?
    let isKeyWorkout: Bool
    let status: String
    let blocks: [PlanningAPIWorkoutBlock]
}

private struct PlanningAPIWorkoutBlock: Decodable {
    let blockType: String
    let modality: String
    let stimulus: String
    let durationSeconds: Int?
    let distanceMeters: Double?
    let steps: [PlanningAPIWorkoutStep]
}

private struct PlanningAPIWorkoutStep: Decodable {
    let id: String
    let label: String
    let kind: String
    let durationSeconds: Int?
    let distanceMeters: Double?
    let detail: String?
}

private struct PlanningAPIAthleteState: Decodable {
    let fatigueRisk: String
    let adherenceRate: Double
    let consistencyScore: Double
    let weeklyMinutes: Int
    let weeklyDistanceMeters: Double
}

private struct PlanningAPIAdjustment: Decodable {
    let message: String
    let eventType: String
    let createdAt: String?
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
    let reflection: FinishReflection?
}

struct ActivityUploadResponse: Decodable {
    let id: String
    let clientActivityId: String?
    let status: String
    let uploadedAt: Date
}
