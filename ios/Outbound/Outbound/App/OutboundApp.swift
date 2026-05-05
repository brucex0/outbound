import SwiftUI

@main
struct OutboundApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var authStore = AuthStore()
    @StateObject private var coachStore = CoachStore()
    @StateObject private var coachCatalogStore = CoachCatalogStore()
    @StateObject private var activityStore = ActivityStore()
    @StateObject private var goalStore = GoalStore()
    @StateObject private var trainingPlanStore = TrainingPlanStore()
    @StateObject private var assistantStore = AssistantStore()
    @StateObject private var appNavigationStore = AppNavigationStore()
    @StateObject private var healthAuthorizationStore = HealthAuthorizationStore()
    @StateObject private var healthImportStore = HealthImportStore()
    @StateObject private var dailyCheckInStore = DailyCheckInStore()
    @StateObject private var musicStore = MusicStore()
    @StateObject private var recognitionStore = RecognitionStore()
    @StateObject private var measurementPreferences = MeasurementPreferences()
    @StateObject private var onboardingStore = OnboardingStore()

    init() {
        FirebaseBootstrap.configureIfAvailable()
    }

    var body: some Scene {
        WindowGroup {
            if authStore.isAuthenticated {
                MainTabView()
                    .environmentObject(authStore)
                    .environmentObject(coachStore)
                    .environmentObject(coachCatalogStore)
                    .environmentObject(activityStore)
                    .environmentObject(goalStore)
                    .environmentObject(trainingPlanStore)
                    .environmentObject(assistantStore)
                    .environmentObject(appNavigationStore)
                    .environmentObject(healthAuthorizationStore)
                    .environmentObject(healthImportStore)
                    .environmentObject(dailyCheckInStore)
                    .environmentObject(musicStore)
                    .environmentObject(recognitionStore)
                    .environmentObject(measurementPreferences)
                    .environmentObject(onboardingStore)
                    .task {
                        await coachStore.syncIfNeeded()
                        await activityStore.syncPendingActivitiesIfNeeded()
                        await healthAuthorizationStore.refresh()
                        await healthImportStore.refreshRecentWorkouts()
                        await musicStore.refresh()
                    }
                    .onOpenURL { url in
                        _ = authStore.handleOpenURL(url)
                    }
            } else {
                AuthView()
                    .environmentObject(authStore)
                    .onOpenURL { url in
                        _ = authStore.handleOpenURL(url)
                    }
            }
        }
    }
}

@MainActor
final class MeasurementPreferences: ObservableObject {
    @Published var unitSystem: MeasurementUnitSystem {
        didSet {
            defaults.set(unitSystem.rawValue, forKey: unitSystemKey)
        }
    }

    private let defaults: UserDefaults
    private let unitSystemKey = "measurement_unit_system_v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedValue = defaults.string(forKey: unitSystemKey)
        unitSystem = storedValue.flatMap(MeasurementUnitSystem.init(rawValue:)) ?? .metric
    }
}

enum DailyReadiness: String, Codable, CaseIterable, Identifiable {
    case lowEnergy = "Low energy"
    case okay = "Okay"
    case ready = "Ready"
    case stressed = "Stressed"

    var id: String { rawValue }

    var summaryLabel: String { "Today: \(rawValue)" }
}

struct DailyCheckInEntry: Codable, Equatable {
    let dayStamp: Date
    let readiness: DailyReadiness
}

@MainActor
final class DailyCheckInStore: ObservableObject {
    @Published private(set) var todayEntry: DailyCheckInEntry?

    private let defaults: UserDefaults
    private let entryKey = "daily_check_in_entry_v1"
    private let calendar: Calendar

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) {
        self.defaults = defaults
        self.calendar = calendar

        if let data = defaults.data(forKey: entryKey),
           let decoded = try? JSONDecoder().decode(DailyCheckInEntry.self, from: data),
           calendar.isDateInToday(decoded.dayStamp) {
            todayEntry = decoded
        } else {
            todayEntry = nil
        }
    }

    var readiness: DailyReadiness? {
        todayEntry?.readiness
    }

    func select(_ readiness: DailyReadiness, now: Date = Date()) {
        let entry = DailyCheckInEntry(
            dayStamp: calendar.startOfDay(for: now),
            readiness: readiness
        )
        todayEntry = entry

        guard let data = try? JSONEncoder().encode(entry) else { return }
        defaults.set(data, forKey: entryKey)
    }

    func refresh(now: Date = Date()) {
        guard let entry = todayEntry else { return }
        if !calendar.isDate(entry.dayStamp, inSameDayAs: now) {
            todayEntry = nil
            defaults.removeObject(forKey: entryKey)
        }
    }
}

enum TrainingPlanSport: String, Codable, CaseIterable, Identifiable {
    case run
    case walk
    case bike
    case mixed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .run: return "Run"
        case .walk: return "Walk"
        case .bike: return "Bike"
        case .mixed: return "Mixed"
        }
    }

    var systemImage: String {
        switch self {
        case .run: return "figure.run"
        case .walk: return "figure.walk"
        case .bike: return "bicycle"
        case .mixed: return "square.grid.2x2.fill"
        }
    }
}

enum TrainingPlanFocus: String, Codable, CaseIterable, Identifiable {
    case consistency
    case comeback
    case fiveK
    case tenK
    case tenMile
    case halfMarathon

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .consistency: return "Consistency"
        case .comeback: return "Comeback"
        case .fiveK: return "5K"
        case .tenK: return "10K"
        case .tenMile: return "10 mile"
        case .halfMarathon: return "Half marathon"
        }
    }
}

struct TrainingPlanSource: Codable, Hashable {
    let name: String
    let license: String
    let attribution: String
    let url: String
    let importNotes: String
}

enum TrainingPlanWorkoutKind: String, Codable, Hashable {
    case easy
    case recovery
    case walkRun
    case tempo
    case interval
    case fartlek
    case hill
    case longRun
    case crossTrain
    case racePrep
    case race

    var displayName: String {
        switch self {
        case .easy: return "Easy run"
        case .recovery: return "Recovery run"
        case .walkRun: return "Walk-run"
        case .tempo: return "Tempo"
        case .interval: return "Intervals"
        case .fartlek: return "Fartlek"
        case .hill: return "Hills"
        case .longRun: return "Long run"
        case .crossTrain: return "Cross-train"
        case .racePrep: return "Race prep"
        case .race: return "Race day"
        }
    }
}

enum TrainingPlanWorkoutStepKind: String, Codable, Hashable {
    case warmup
    case run
    case walk
    case tempo
    case interval
    case steady
    case recovery
    case crossTrain
    case cooldown
    case race
}

struct TrainingPlanWorkoutStep: Identifiable, Codable, Hashable {
    let id: String
    let kind: TrainingPlanWorkoutStepKind
    let label: String
    let durationSeconds: Int
    let detail: String?

    var durationLabel: String {
        Self.formatDuration(durationSeconds)
    }

    private static func formatDuration(_ seconds: Int) -> String {
        if seconds % 60 == 0 {
            return "\(seconds / 60) min"
        }
        return "\(seconds / 60)m \(seconds % 60)s"
    }
}

struct TrainingPlanWorkout: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let kind: TrainingPlanWorkoutKind
    let dayLabel: String
    let summary: String
    let purpose: String
    let coachCue: String
    let effortLabel: String
    let durationSeconds: Int
    let distanceLabel: String?
    let steps: [TrainingPlanWorkoutStep]
    let isOptional: Bool

    var durationMinutesRounded: Int {
        Int(ceil(Double(durationSeconds) / 60.0))
    }

    var durationLabel: String {
        if durationSeconds % 60 == 0 {
            return "\(durationSeconds / 60) min"
        }
        return "\(durationSeconds / 60)m \(durationSeconds % 60)s"
    }

    var stepSummary: [String] {
        steps.map { step in
            if let detail = step.detail, !detail.isEmpty {
                return "\(step.label) • \(step.durationLabel) • \(detail)"
            }
            return "\(step.label) • \(step.durationLabel)"
        }
    }
}

struct TrainingPlanWeek: Identifiable, Codable, Hashable {
    let id: String
    let index: Int
    let focus: String
    let summary: String
    let workouts: [TrainingPlanWorkout]
    let notes: [String]

    var targetMinutes: Int {
        Int(ceil(Double(workouts.reduce(0) { $0 + $1.durationSeconds }) / 60.0))
    }
}

struct TrainingPlanTemplate: Identifiable, Codable, Hashable {
    let id: String
    let focus: TrainingPlanFocus
    let sport: TrainingPlanSport
    let title: String
    let subtitle: String
    let defaultWeeks: Int
    let minSessionsPerWeek: Int
    let maxSessionsPerWeek: Int
    let baseWeeklyMinutes: Int
    let baseLongSessionMinutes: Int
    let summary: String
    let highlights: [String]
    let source: TrainingPlanSource?
    let weeks: [TrainingPlanWeek]
}

struct TrainingPlanRecommendation: Identifiable, Codable, Hashable {
    let id: String
    let template: TrainingPlanTemplate
    let durationWeeks: Int
    let sessionsPerWeek: Int
    let targetWeeklyMinutes: Int
    let longSessionMinutes: Int
    let rationale: String
    let tradeoff: String
}

struct ActiveTrainingPlan: Codable, Identifiable, Equatable {
    let id: String
    let templateID: String
    let focus: TrainingPlanFocus
    let sport: TrainingPlanSport
    let title: String
    let subtitle: String
    let durationWeeks: Int
    let sessionsPerWeek: Int
    let targetWeeklyMinutes: Int
    let longSessionMinutes: Int
    let createdAt: Date
}

struct TrainingPlanWeekSnapshot: Codable, Equatable {
    let currentWeekIndex: Int
    let totalWeeks: Int
    let completedSessions: Int
    let targetSessions: Int
    let completedMinutes: Int
    let targetMinutes: Int
    let progressPercent: Double
    let summaryLine: String
    let coachLine: String
    let focus: String
    let weekSummary: String
    let scheduledWorkouts: [TrainingPlanWorkout]
    let notes: [String]
}

struct TodayTrainingSuggestion: Codable, Equatable {
    let title: String
    let detail: String
    let coachLine: String
    let adjustmentLine: String?
    let suggestedSession: SuggestedSession
    let workout: TrainingPlanWorkout
    let stepSummary: [String]
}

@MainActor
final class TrainingPlanStore: ObservableObject {
    @Published private(set) var activePlan: ActiveTrainingPlan?
    @Published private(set) var recommendations: [TrainingPlanRecommendation] = []
    @Published private(set) var currentWeek: TrainingPlanWeekSnapshot?
    @Published private(set) var todaySuggestion: TodayTrainingSuggestion?

    private let defaults: UserDefaults
    private let calendar: Calendar
    private let api: APIClient
    private let activePlanKey = "training_plan_store_active_plan_v1"
    private let stateCacheKey = "training_plan_store_state_v2"
    private let dismissedWeekKey = "training_plan_store_dismissed_week_v1"
    private let readinessSyncKey = "training_plan_store_readiness_sync_v1"
    private var dismissedRecommendationWeekStart: Date?
    private var lastSubmittedReadinessSignature: String?
    private var lastActivities: [SavedActivity] = []
    private var lastReadiness: DailyReadiness?
    private var lastPhase: MotivationPhase = .firstSession
    private var refreshTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        api: APIClient = .shared
    ) {
        self.defaults = defaults
        self.calendar = calendar
        self.api = api
        self.dismissedRecommendationWeekStart = Self.decode(Date.self, from: defaults.data(forKey: dismissedWeekKey))
        self.lastSubmittedReadinessSignature = defaults.string(forKey: readinessSyncKey)

        if let cachedState = Self.decode(TrainingPlanStateResponse.self, from: defaults.data(forKey: stateCacheKey)) {
            activePlan = cachedState.activePlan
            recommendations = cachedState.recommendations
            currentWeek = cachedState.currentWeek
            todaySuggestion = cachedState.todaySuggestion
        } else {
            activePlan = Self.decode(ActiveTrainingPlan.self, from: defaults.data(forKey: activePlanKey))
        }
    }

    var shouldShowRecommendations: Bool {
        activePlan == nil && !recommendations.isEmpty
    }

    func refresh(
        activities: [SavedActivity],
        readiness: DailyReadiness?,
        phase: MotivationPhase,
        now: Date = Date()
    ) {
        lastActivities = activities
        lastReadiness = readiness
        lastPhase = phase

        resetDismissedRecommendationIfNeeded(now: now)

        refreshTask?.cancel()
        refreshTask = Task {
            do {
                let readinessSignature = readiness.map {
                    Self.readinessSignature(for: $0, calendar: calendar, now: now)
                }
                let shouldSubmitReadiness = readinessSignature != nil
                    && readinessSignature != lastSubmittedReadinessSignature
                let state: TrainingPlanStateResponse
                if let readiness, shouldSubmitReadiness {
                    state = try await api.submitTrainingReadiness(readiness)
                    lastSubmittedReadinessSignature = readinessSignature
                    persistReadinessSignature()
                } else {
                    state = try await api.fetchTrainingPlanState(readiness: readiness)
                }
                guard !Task.isCancelled else { return }
                applyServerState(state, now: now)
            } catch {
                guard !Task.isCancelled else { return }
                print("[TrainingPlanStore] server refresh failed: \(error.localizedDescription)")
                applyLocalFallback(activities: activities, readiness: readiness, phase: phase, now: now)
            }
        }
    }

    func acceptRecommendation(_ recommendation: TrainingPlanRecommendation, now: Date = Date()) {
        refreshTask?.cancel()
        activePlan = ActiveTrainingPlan(
            id: UUID().uuidString,
            templateID: recommendation.template.id,
            focus: recommendation.template.focus,
            sport: recommendation.template.sport,
            title: recommendation.template.title,
            subtitle: recommendation.template.subtitle,
            durationWeeks: recommendation.durationWeeks,
            sessionsPerWeek: recommendation.sessionsPerWeek,
            targetWeeklyMinutes: recommendation.targetWeeklyMinutes,
            longSessionMinutes: recommendation.longSessionMinutes,
            createdAt: now
        )
        applyLocalFallback(activities: lastActivities, readiness: lastReadiness, phase: lastPhase, now: now)

        refreshTask = Task {
            do {
                let state = try await api.createTrainingPlan(from: recommendation, readiness: lastReadiness)
                guard !Task.isCancelled else { return }
                applyServerState(state, now: now)
            } catch {
                guard !Task.isCancelled else { return }
                print("[TrainingPlanStore] active plan sync failed: \(error.localizedDescription)")
                persistState()
            }
        }
    }

    func clearActivePlan(now: Date = Date()) {
        refreshTask?.cancel()
        activePlan = nil
        currentWeek = nil
        todaySuggestion = nil
        applyLocalFallback(activities: lastActivities, readiness: lastReadiness, phase: lastPhase, now: now)

        refreshTask = Task {
            do {
                let state = try await api.clearActiveTrainingPlan(readiness: lastReadiness)
                guard !Task.isCancelled else { return }
                applyServerState(state, now: now)
            } catch {
                guard !Task.isCancelled else { return }
                print("[TrainingPlanStore] clear active plan sync failed: \(error.localizedDescription)")
                persistState()
            }
        }
    }

    func dismissRecommendations(now: Date = Date()) {
        dismissedRecommendationWeekStart = startOfWeek(for: now)
        recommendations = []
        persistDismissedWeek()
        persistState()
    }

    private func startOfWeek(for date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    private func resetDismissedRecommendationIfNeeded(now: Date) {
        let weekStart = startOfWeek(for: now)
        if let dismissedRecommendationWeekStart, dismissedRecommendationWeekStart != weekStart {
            self.dismissedRecommendationWeekStart = nil
            persistDismissedWeek()
        }
    }

    private func applyServerState(_ state: TrainingPlanStateResponse, now: Date) {
        resetDismissedRecommendationIfNeeded(now: now)

        activePlan = state.activePlan
        if state.activePlan == nil, state.recommendations.isEmpty {
            recommendations = Self.makeRecommendations(
                activities: lastActivities,
                phase: lastPhase,
                calendar: calendar,
                now: now
            )
        } else {
            recommendations = state.recommendations
        }
        if activePlan == nil, dismissedRecommendationWeekStart == startOfWeek(for: now) {
            recommendations = []
        }
        currentWeek = state.currentWeek
        todaySuggestion = state.todaySuggestion
        persistState()
    }

    private func applyLocalFallback(
        activities: [SavedActivity],
        readiness: DailyReadiness?,
        phase: MotivationPhase,
        now: Date
    ) {
        resetDismissedRecommendationIfNeeded(now: now)

        recommendations = Self.makeRecommendations(
            activities: activities,
            phase: phase,
            calendar: calendar,
            now: now
        )
        if activePlan == nil, dismissedRecommendationWeekStart == startOfWeek(for: now) {
            recommendations = []
        }

        guard let activePlan else {
            currentWeek = nil
            todaySuggestion = nil
            persistState()
            return
        }

        currentWeek = Self.makeWeekSnapshot(plan: activePlan, activities: activities, calendar: calendar, now: now)
        todaySuggestion = Self.makeTodaySuggestion(
            plan: activePlan,
            week: currentWeek,
            readiness: readiness,
            calendar: calendar,
            now: now
        )
        persistState()
    }

    private func persistState() {
        let state = TrainingPlanStateResponse(
            activePlan: activePlan,
            recommendations: activePlan == nil ? [] : recommendations,
            currentWeek: currentWeek,
            todaySuggestion: todaySuggestion
        )

        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: stateCacheKey)
        }

        if let activePlan, let data = try? JSONEncoder().encode(activePlan) {
            defaults.set(data, forKey: activePlanKey)
        } else {
            defaults.removeObject(forKey: activePlanKey)
        }
    }

    private func persistDismissedWeek() {
        if let dismissedRecommendationWeekStart,
           let data = try? JSONEncoder().encode(dismissedRecommendationWeekStart) {
            defaults.set(data, forKey: dismissedWeekKey)
        } else {
            defaults.removeObject(forKey: dismissedWeekKey)
        }
    }

    private func persistReadinessSignature() {
        if let lastSubmittedReadinessSignature {
            defaults.set(lastSubmittedReadinessSignature, forKey: readinessSyncKey)
        } else {
            defaults.removeObject(forKey: readinessSyncKey)
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func readinessSignature(
        for readiness: DailyReadiness,
        calendar: Calendar,
        now: Date
    ) -> String {
        let components = calendar.dateComponents([.era, .year, .month, .day], from: now)
        return "\(components.era ?? 0)-\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)-\(readiness.rawValue)"
    }
}

private extension TrainingPlanStore {
    struct RecentTrainingStats {
        let recentSessionCount: Int
        let recentDistanceKilometers: Double
        let weeklySessionAverage: Double
        let weeklyMinutesAverage: Double
        let longestSessionMinutes: Int
    }

    static let templates: [TrainingPlanTemplate] = TrainingPlanLibrary.templates
    static let templateLookup: [String: TrainingPlanTemplate] = Dictionary(
        uniqueKeysWithValues: templates.map { ($0.id, $0) }
    )

    static func makeRecommendations(activities: [SavedActivity], phase: MotivationPhase, calendar: Calendar, now: Date) -> [TrainingPlanRecommendation] {
        let stats = recentTrainingStats(activities: activities, calendar: calendar, now: now)
        return recommendedTemplateIDs(stats: stats, phase: phase).compactMap { templateID in
            guard let template = templateLookup[templateID] else { return nil }
            return makeRecommendation(template: template, stats: stats, phase: phase)
        }
    }

    static func recommendedTemplateIDs(stats: RecentTrainingStats, phase: MotivationPhase) -> [String] {
        switch phase {
        case .firstSession:
            return [
                "run-comeback-v1",
                "run-5k-v1",
                "run-consistency-v1",
                "run-base-30-v1"
            ]
        case .comeback:
            return [
                "run-comeback-v1",
                "run-consistency-v1",
                "run-5k-v1",
                "run-base-30-v1"
            ]
        case .momentum:
            if stats.recentDistanceKilometers >= 65 || stats.longestSessionMinutes >= 85 || stats.weeklySessionAverage >= 4.5 {
                return [
                    "run-half-hansons-advanced-v1",
                    "run-half-v1",
                    "run-10mile-v1",
                    "run-half-hansons-beginner-v1",
                    "run-10k-v1",
                    "run-base-30-v1"
                ]
            } else if stats.recentDistanceKilometers >= 35 || stats.longestSessionMinutes >= 55 || stats.weeklySessionAverage >= 3 {
                return [
                    "run-10k-v1",
                    "run-half-hansons-beginner-v1",
                    "run-10mile-v1",
                    "run-half-v1",
                    "run-base-30-v1",
                    "run-5k-v1"
                ]
            } else {
                return [
                    "run-5k-v1",
                    "run-consistency-v1",
                    "run-base-30-v1",
                    "run-comeback-v1",
                    "run-10k-v1"
                ]
            }
        case .steady, .completedToday:
            if stats.recentDistanceKilometers >= 60 || stats.longestSessionMinutes >= 80 || stats.weeklySessionAverage >= 4 {
                return [
                    "run-half-hansons-advanced-v1",
                    "run-10mile-v1",
                    "run-half-v1",
                    "run-half-hansons-beginner-v1",
                    "run-10k-v1",
                    "run-base-30-v1"
                ]
            } else if stats.recentDistanceKilometers >= 28 || stats.longestSessionMinutes >= 45 || stats.weeklySessionAverage >= 2.5 {
                return [
                    "run-10k-v1",
                    "run-base-30-v1",
                    "run-half-hansons-beginner-v1",
                    "run-half-v1",
                    "run-5k-v1",
                    "run-consistency-v1"
                ]
            } else {
                return [
                    "run-5k-v1",
                    "run-consistency-v1",
                    "run-base-30-v1",
                    "run-comeback-v1"
                ]
            }
        }
    }

    static func makeRecommendation(template: TrainingPlanTemplate, stats: RecentTrainingStats, phase: MotivationPhase) -> TrainingPlanRecommendation {
        let baselineSessions = max(1, Int(stats.weeklySessionAverage.rounded()))
        let baselineMinutes = max(20, Int(stats.weeklyMinutesAverage.rounded()))
        let suggestedSessions: Int

        switch template.focus {
        case .comeback:
            suggestedSessions = min(template.maxSessionsPerWeek, max(template.minSessionsPerWeek, baselineSessions <= 1 ? 2 : baselineSessions))
        case .consistency:
            suggestedSessions = min(template.maxSessionsPerWeek, max(template.minSessionsPerWeek, baselineSessions + (phase == .momentum ? 1 : 0)))
        case .fiveK, .tenK, .tenMile, .halfMarathon:
            suggestedSessions = min(template.maxSessionsPerWeek, max(template.minSessionsPerWeek, baselineSessions))
        }

        let targetWeeklyMinutes = max(
            template.baseWeeklyMinutes,
            baselineMinutes + weeklyMinuteLift(for: template.focus, phase: phase)
        )
        let longSessionMinutes = min(
            max(template.baseLongSessionMinutes, stats.longestSessionMinutes + longMinuteLift(for: template.focus)),
            max(15, targetWeeklyMinutes - 10)
        )

        return TrainingPlanRecommendation(
            id: "\(template.id)-\(suggestedSessions)-\(targetWeeklyMinutes)",
            template: template,
            durationWeeks: template.defaultWeeks,
            sessionsPerWeek: suggestedSessions,
            targetWeeklyMinutes: targetWeeklyMinutes,
            longSessionMinutes: longSessionMinutes,
            rationale: rationale(for: template.focus, stats: stats, phase: phase, suggestedSessions: suggestedSessions),
            tradeoff: tradeoff(for: template.focus, sessionsPerWeek: suggestedSessions)
        )
    }

    static func makeWeekSnapshot(plan: ActiveTrainingPlan, activities: [SavedActivity], calendar: Calendar, now: Date) -> TrainingPlanWeekSnapshot {
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let planWeekStart = calendar.dateInterval(of: .weekOfYear, for: plan.createdAt)?.start ?? plan.createdAt
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? now
        let weekActivities = activities.filter { $0.startedAt >= weekStart && $0.startedAt < weekEnd }
        let completedSessions = weekActivities.count
        let completedMinutes = Int(ceil(Double(weekActivities.reduce(0) { $0 + $1.durationSecs }) / 60.0))
        let weekIndex = max(1, min(plan.durationWeeks, (calendar.dateComponents([.weekOfYear], from: planWeekStart, to: now).weekOfYear ?? 0) + 1))
        let scheduledWeek = templateLookup[plan.templateID]?.weeks[safe: weekIndex - 1]
        let targetSessions = scheduledWeek?.workouts.filter { !$0.isOptional }.count ?? plan.sessionsPerWeek
        let targetMinutes = scheduledWeek?.targetMinutes ?? plan.targetWeeklyMinutes
        let progressPercent = min(
            1,
            max(
                Double(completedSessions) / Double(max(1, targetSessions)),
                Double(completedMinutes) / Double(max(1, targetMinutes))
            )
        )

        return TrainingPlanWeekSnapshot(
            currentWeekIndex: weekIndex,
            totalWeeks: plan.durationWeeks,
            completedSessions: completedSessions,
            targetSessions: targetSessions,
            completedMinutes: completedMinutes,
            targetMinutes: targetMinutes,
            progressPercent: progressPercent,
            summaryLine: "\(completedSessions) of \(targetSessions) sessions, \(completedMinutes) of \(targetMinutes) min this week",
            coachLine: coachLine(for: plan, completedSessions: completedSessions, completedMinutes: completedMinutes),
            focus: scheduledWeek?.focus ?? "Settle into the week",
            weekSummary: scheduledWeek?.summary ?? plan.subtitle,
            scheduledWorkouts: scheduledWeek?.workouts ?? [],
            notes: scheduledWeek?.notes ?? []
        )
    }

    static func makeTodaySuggestion(plan: ActiveTrainingPlan, week: TrainingPlanWeekSnapshot?, readiness: DailyReadiness?, calendar: Calendar, now: Date) -> TodayTrainingSuggestion {
        let baseWorkout = nextWorkout(for: plan, week: week)
        let lowReadiness = readiness == .lowEnergy || readiness == .stressed
        let workout = lowReadiness ? adjustedWorkout(from: baseWorkout) : baseWorkout
        let detailPrefix = lowReadiness ? "Adjusted session" : "Planned session"
        let coachLine = lowReadiness
            ? "We kept the shape of the workout, but softened the stress so the plan stays usable."
            : workout.coachCue

        let suggestion = SuggestedSession(
            id: "plan-\(plan.templateID)-\(workout.id)",
            sport: .run,
            title: workout.title,
            durationLabel: workout.durationLabel,
            activityLabel: workout.kind.displayName,
            framing: workout.purpose,
            coachLine: coachLine,
            startLabel: "Start now"
        )

        return TodayTrainingSuggestion(
            title: workout.title,
            detail: "\(detailPrefix) • \(workout.durationLabel) • \(workout.effortLabel)",
            coachLine: coachLine,
            adjustmentLine: lowReadiness ? "Dialed back for today's readiness." : nil,
            suggestedSession: suggestion,
            workout: workout,
            stepSummary: workout.stepSummary
        )
    }

    static func recentTrainingStats(activities: [SavedActivity], calendar: Calendar, now: Date) -> RecentTrainingStats {
        let start = calendar.date(byAdding: .day, value: -28, to: now) ?? now
        let recentActivities = activities.filter { $0.startedAt >= start }
        let distanceKilometers = recentActivities.reduce(0.0) { $0 + $1.distanceM } / 1000
        let weeklyMinutesAverage = (Double(recentActivities.reduce(0) { $0 + $1.durationSecs }) / 60.0) / 4.0
        return RecentTrainingStats(
            recentSessionCount: recentActivities.count,
            recentDistanceKilometers: distanceKilometers,
            weeklySessionAverage: Double(recentActivities.count) / 4.0,
            weeklyMinutesAverage: weeklyMinutesAverage,
            longestSessionMinutes: recentActivities.map { Int(ceil(Double($0.durationSecs) / 60.0)) }.max() ?? 0
        )
    }

    static func weeklyMinuteLift(for focus: TrainingPlanFocus, phase: MotivationPhase) -> Int {
        switch focus {
        case .comeback: return 10
        case .consistency: return phase == .momentum ? 25 : 15
        case .fiveK: return 20
        case .tenK: return 30
        case .tenMile: return 40
        case .halfMarathon: return 50
        }
    }

    static func longMinuteLift(for focus: TrainingPlanFocus) -> Int {
        switch focus {
        case .comeback: return 0
        case .consistency: return 5
        case .fiveK: return 8
        case .tenK: return 10
        case .tenMile: return 12
        case .halfMarathon: return 15
        }
    }

    static func rationale(for focus: TrainingPlanFocus, stats: RecentTrainingStats, phase: MotivationPhase, suggestedSessions: Int) -> String {
        switch focus {
        case .comeback:
            return "You've had enough gap or variability that a softer re-entry will stick better than a harder block."
        case .consistency:
            return "You've shown enough movement to support a simple weekly rhythm of \(suggestedSessions) runs without adding too much pressure."
        case .fiveK:
            return stats.recentSessionCount < 6 ? "A 5K block is specific enough to feel motivating, but still realistic for your current base." : "You already have a base. A 5K block can sharpen it without needing a heavy schedule."
        case .tenK:
            return "Your recent volume suggests you can handle a steadier endurance block that points toward a 10K."
        case .tenMile:
            return "You've built enough baseline work that a longer endurance focus can be realistic if the week stays controlled."
        case .halfMarathon:
            return phase == .momentum ? "Your recent rhythm supports a half build, so long as the week keeps adapting around fatigue." : "You have enough baseline to start a half build, but the plan still needs to stay grounded in your current routine."
        }
    }

    static func tradeoff(for focus: TrainingPlanFocus, sessionsPerWeek: Int) -> String {
        switch focus {
        case .comeback: return "Best for re-entry, but slower if you want fast progression."
        case .consistency: return "Best for habit, not race specificity."
        case .fiveK: return "\(sessionsPerWeek)x per week with one slightly more focused day."
        case .tenK: return "More steady work each week, but still manageable for a normal schedule."
        case .tenMile: return "Needs honest recovery and a real long-run slot."
        case .halfMarathon: return "Most demanding of the current options, with bigger long-run expectations."
        }
    }

    static func coachLine(for plan: ActiveTrainingPlan, completedSessions: Int, completedMinutes: Int) -> String {
        if completedSessions >= plan.sessionsPerWeek || completedMinutes >= plan.targetWeeklyMinutes {
            return "You covered this week's core work. Anything extra can stay easy."
        }

        let remainingSessions = max(0, plan.sessionsPerWeek - completedSessions)
        return remainingSessions <= 1
            ? "One more honest session would round out this week well."
            : "\(remainingSessions) more sessions would give this week the shape this plan is aiming for."
    }

    static func nextWorkout(for plan: ActiveTrainingPlan, week: TrainingPlanWeekSnapshot?) -> TrainingPlanWorkout {
        guard let week, !week.scheduledWorkouts.isEmpty else {
            return TrainingPlanLibrary.fallbackWorkout(for: plan.focus)
        }
        if week.completedSessions >= week.targetSessions {
            return TrainingPlanLibrary.completionWorkout(for: plan.focus)
        }
        let nextIndex = min(week.completedSessions, week.scheduledWorkouts.count - 1)
        return week.scheduledWorkouts[nextIndex]
    }

    static func adjustedWorkout(from workout: TrainingPlanWorkout) -> TrainingPlanWorkout {
        let shortenedDuration = max(12 * 60, Int(Double(workout.durationSeconds) * 0.7))
        let easyBlock = max(4 * 60, shortenedDuration - (8 * 60))
        let steps = [
            TrainingPlanWorkoutStep(
                id: "\(workout.id)-adjusted-warmup",
                kind: .warmup,
                label: "Warm up walk",
                durationSeconds: 4 * 60,
                detail: "Start easy and settle your breathing."
            ),
            TrainingPlanWorkoutStep(
                id: "\(workout.id)-adjusted-run",
                kind: .run,
                label: workout.kind == .walkRun ? "Easy walk-run" : "Easy running",
                durationSeconds: easyBlock,
                detail: "Keep the effort conversational."
            ),
            TrainingPlanWorkoutStep(
                id: "\(workout.id)-adjusted-cooldown",
                kind: .cooldown,
                label: "Cooldown walk",
                durationSeconds: 4 * 60,
                detail: "Finish still feeling in control."
            )
        ]

        return TrainingPlanWorkout(
            id: "\(workout.id)-adjusted",
            title: "Lighter \(workout.title)",
            kind: workout.kind == .walkRun ? .walkRun : .recovery,
            dayLabel: workout.dayLabel,
            summary: "A softer version of the scheduled workout.",
            purpose: "Protect consistency without turning today into a grind.",
            coachCue: "Today still counts. Keep it easy and bank the routine.",
            effortLabel: "Easy",
            durationSeconds: shortenedDuration,
            distanceLabel: nil,
            steps: steps,
            isOptional: workout.isOptional
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

enum AssistantCapability: String, CaseIterable, Codable, Identifiable {
    case discover
    case navigate
    case support
    case brainstorm
    case plan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .discover:
            "Discover"
        case .navigate:
            "Navigate"
        case .support:
            "Support"
        case .brainstorm:
            "Brainstorm"
        case .plan:
            "Plan"
        }
    }

    var subtitle: String {
        switch self {
        case .discover:
            "Learn what Outbound can do for you."
        case .navigate:
            "Find the right tab, flow, or setting fast."
        case .support:
            "Get help with setup and stuck moments."
        case .brainstorm:
            "Shape ideas for training and social loops."
        case .plan:
            "Turn loose goals into a doable week."
        }
    }

    var symbolName: String {
        switch self {
        case .discover:
            "sparkles"
        case .navigate:
            "location.north.line.fill"
        case .support:
            "lifepreserver.fill"
        case .brainstorm:
            "lightbulb.fill"
        case .plan:
            "calendar.badge.clock"
        }
    }
}

struct AssistantSuggestion: Identifiable, Hashable {
    let id: String
    let capability: AssistantCapability
    let title: String
    let prompt: String
}

enum AssistantNavigationTarget: String, Codable, Hashable, Identifiable {
    case settingsAppleMusic
    case settingsAppleHealth
    case coachSettings
    case activityHistory

    var id: String { rawValue }
}

enum AssistantAuthor: String, Codable {
    case assistant
    case user
}

struct AssistantMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let author: AssistantAuthor
    let text: String
    let createdAt: Date
    let capability: AssistantCapability?
    let navigationTarget: AssistantNavigationTarget?

    init(
        id: UUID = UUID(),
        author: AssistantAuthor,
        text: String,
        createdAt: Date = Date(),
        capability: AssistantCapability? = nil,
        navigationTarget: AssistantNavigationTarget? = nil
    ) {
        self.id = id
        self.author = author
        self.text = text
        self.createdAt = createdAt
        self.capability = capability
        self.navigationTarget = navigationTarget
    }
}

struct AssistantContext {
    let coachName: String
    let activityCount: Int
    let weeklyDistanceKilometers: Double
    let currentGoalSummary: String?
    let currentScreen: String?
    let isRecordingActive: Bool
}

@MainActor
final class AppNavigationStore: ObservableObject {
    @Published var pendingAssistantTarget: AssistantNavigationTarget?

    func open(_ target: AssistantNavigationTarget) {
        pendingAssistantTarget = target
    }

    func consume() {
        pendingAssistantTarget = nil
    }
}

@MainActor
final class AssistantStore: ObservableObject {
    @Published var draft = ""
    @Published private(set) var messages: [AssistantMessage]
    @Published private(set) var isResponding = false

    let suggestions: [AssistantSuggestion] = [
        AssistantSuggestion(
            id: "discover-best-parts",
            capability: .discover,
            title: "What should I try first?",
            prompt: "I’m new here. What should I try first in Outbound?"
        ),
        AssistantSuggestion(
            id: "navigate-where-to-go",
            capability: .navigate,
            title: "Where do I go?",
            prompt: "Where do I go for activities, coach settings, and social?"
        ),
        AssistantSuggestion(
            id: "support-setup",
            capability: .support,
            title: "Help me set up",
            prompt: "Help me understand the main setup steps and where to fix things if something feels off."
        ),
        AssistantSuggestion(
            id: "brainstorm-features",
            capability: .brainstorm,
            title: "Brainstorm ideas",
            prompt: "Brainstorm a few ways this app could better support motivation, exploration, and sharing."
        ),
        AssistantSuggestion(
            id: "plan-week",
            capability: .plan,
            title: "Plan my week",
            prompt: "Use what you know about my activity and help me make a simple plan for this week."
        )
    ]

    private let defaults: UserDefaults
    private let messagesKey = "assistant_store_messages_v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.messages = Self.decode([AssistantMessage].self, from: defaults.data(forKey: messagesKey)) ?? []
    }

    func ensureSeedMessage(context: AssistantContext) {
        guard messages.isEmpty else { return }
        messages = [
            AssistantMessage(
                author: .assistant,
                text: """
                I can help with discovery, navigation, support, brainstorming, and simple planning.

                I already know your current coach is \(context.coachName), you have \(context.activityCount) saved activit\(context.activityCount == 1 ? "y" : "ies"), and your week is at \(String(format: "%.1f", context.weeklyDistanceKilometers)) km.
                """,
                capability: .discover
            )
        ]
        persistMessages()
    }

    func sendCurrentDraft(context: AssistantContext) async -> AssistantNavigationTarget? {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        draft = ""
        return await send(trimmed, capability: nil, context: context)
    }

    func sendSuggestion(_ suggestion: AssistantSuggestion, context: AssistantContext) async -> AssistantNavigationTarget? {
        await send(suggestion.prompt, capability: suggestion.capability, context: context)
    }

    func reset(context: AssistantContext) {
        messages = []
        persistMessages()
        ensureSeedMessage(context: context)
    }

    private func send(
        _ prompt: String,
        capability: AssistantCapability?,
        context: AssistantContext
    ) async -> AssistantNavigationTarget? {
        ensureSeedMessage(context: context)
        let inferredCapability = capability ?? Self.inferCapability(from: prompt)
        let navigationTarget = Self.inferNavigationTarget(from: prompt)
        messages.append(
            AssistantMessage(
                author: .user,
                text: prompt,
                capability: inferredCapability
            )
        )
        persistMessages()

        let replyText: String
        if let navigationTarget {
            replyText = Self.navigationReply(for: navigationTarget)
        } else {
            isResponding = true
            replyText = await makeReply(
                for: prompt,
                capability: inferredCapability,
                context: context
            )
            isResponding = false
        }

        messages.append(
            AssistantMessage(
                author: .assistant,
                text: replyText,
                capability: inferredCapability,
                navigationTarget: navigationTarget
            )
        )
        persistMessages()
        return navigationTarget
    }

    private func makeReply(
        for prompt: String,
        capability: AssistantCapability,
        context: AssistantContext
    ) async -> String {
        if let remote = try? await APIClient.shared.chatWithAssistant(AssistantChatRequest(
            prompt: prompt,
            capability: capability.rawValue,
            context: AssistantChatAPIContext(
                coachName: context.coachName,
                activityCount: context.activityCount,
                weeklyDistanceKilometers: context.weeklyDistanceKilometers,
                currentGoalSummary: context.currentGoalSummary,
                currentScreen: context.currentScreen,
                isRecordingActive: context.isRecordingActive
            ),
            messages: recentMessagesForAPI(),
            firebaseUid: AuthStore.currentUserId
        )), !remote.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return remote.message
        }

        if let generated = await AssistantFoundationModelResponder.generateReply(
            prompt: prompt,
            capability: capability,
            context: context
        ) {
            return generated
        }

        return fallbackReply(for: capability, context: context)
    }

    private func fallbackReply(
        for capability: AssistantCapability,
        context: AssistantContext
    ) -> String {
        switch capability {
        case .discover:
            return """
            Start with three loops: the motivation dashboard on Me, the orange activity button for a quick session, and Social for squad energy.

            If you want the best first experience, check your coach style, try one suggested session, and save one activity so the app has momentum to build on.
            """
        case .navigate:
            return """
            Here’s the fastest map:
            Me is where you check motivation, tune your coach, review activities, and open Settings.
            Social is for squad, clubs, rivals, and lightweight community loops.
            The floating orange activity button starts or resumes a live session from either tab.

            If you tell me what you want to do, I can point to the exact screen.
            """
        case .support:
            return """
            The main support checkpoints are account setup, coach preferences, Apple Health or Music permissions, and making sure the start flow feels clear.

            If something feels broken, tell me the exact step and what you expected to happen. I’ll turn it into a short troubleshooting path instead of generic advice.
            """
        case .brainstorm:
            return """
            A strong direction would be to make the assistant feel like a concierge, not just a chatbot.

            Good ideas to explore:
            Give it guided prompts for finding features, choosing a coach vibe, and building a comeback plan.
            Let it turn vague intent like “I only have 20 minutes” into a suggested session.
            Use it in Social to suggest clubs, challenges, or rivalry nudges based on recent activity.
            """
        case .plan:
            let goalLine = context.currentGoalSummary ?? "No active weekly goal yet."
            let activityLine: String
            if context.activityCount == 0 {
                activityLine = "You do not have saved activity yet, so the best plan is to create an easy first win."
            } else {
                activityLine = "You already have \(context.activityCount) saved activities, so the plan can build on real momentum."
            }

            return """
            Here’s a simple starting plan.
            \(activityLine)
            Current goal: \(goalLine)

            Try one light session, one slightly more intentional session, and one open-ended session you can start quickly from the orange activity button. Keep the week realistic enough that repeating it still feels possible.
            """
        }
    }

    private func persistMessages() {
        guard let data = try? JSONEncoder().encode(messages) else { return }
        defaults.set(data, forKey: messagesKey)
    }

    private static func inferNavigationTarget(from prompt: String) -> AssistantNavigationTarget? {
        let lowercased = prompt.lowercased()

        if (lowercased.contains("music") || lowercased.contains("apple music")) &&
            (lowercased.contains("setting") || lowercased.contains("connect") || lowercased.contains("permission") || lowercased.contains("show me")) {
            return .settingsAppleMusic
        }

        if (lowercased.contains("health") || lowercased.contains("apple health")) &&
            (lowercased.contains("setting") || lowercased.contains("permission") || lowercased.contains("show me")) {
            return .settingsAppleHealth
        }

        if lowercased.contains("coach") && (lowercased.contains("setting") || lowercased.contains("change") || lowercased.contains("pick")) {
            return .coachSettings
        }

        if lowercased.contains("activity history") || lowercased.contains("my activities") || lowercased.contains("past activities") {
            return .activityHistory
        }

        return nil
    }

    private static func navigationReply(for target: AssistantNavigationTarget) -> String {
        switch target {
        case .settingsAppleMusic:
            return "Opening Apple Music settings."
        case .settingsAppleHealth:
            return "Opening Apple Health settings."
        case .coachSettings:
            return "Opening coach settings."
        case .activityHistory:
            return "Opening your activity history."
        }
    }

    private func recentMessagesForAPI() -> [AssistantChatAPIPriorMessage] {
        messages.suffix(10).map {
            AssistantChatAPIPriorMessage(
                role: $0.author == .user ? "user" : "assistant",
                text: $0.text,
                capability: $0.capability?.rawValue
            )
        }
    }

    private static func inferCapability(from prompt: String) -> AssistantCapability {
        let lowercased = prompt.lowercased()

        if lowercased.contains("where") || lowercased.contains("find") || lowercased.contains("go to") || lowercased.contains("navigate") {
            return .navigate
        }
        if lowercased.contains("help") || lowercased.contains("issue") || lowercased.contains("stuck") || lowercased.contains("support") || lowercased.contains("setup") {
            return .support
        }
        if lowercased.contains("idea") || lowercased.contains("brainstorm") || lowercased.contains("could") || lowercased.contains("should we") {
            return .brainstorm
        }
        if lowercased.contains("plan") || lowercased.contains("week") || lowercased.contains("schedule") || lowercased.contains("goal") {
            return .plan
        }
        return .discover
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

enum AssistantFoundationModelResponder {
    @MainActor
    static func generateReply(
        prompt: String,
        capability: AssistantCapability,
        context: AssistantContext
    ) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let session = AssistantFoundationModelSession.shared
            guard session.isAvailable else { return nil }
            return try? await session.reply(to: prompt, capability: capability, context: context)
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macOS 26.0, *)
@MainActor
private final class AssistantFoundationModelSession {
    static let shared = AssistantFoundationModelSession()

    private let model = SystemLanguageModel.default

    var isAvailable: Bool {
        guard case .available = model.availability else { return false }
        return true
    }

    func reply(
        to prompt: String,
        capability: AssistantCapability,
        context: AssistantContext
    ) async throws -> String {
        let session = LanguageModelSession(model: model) {
            """
            You are Outbound's in-app assistant.
            Help with product discovery, app navigation, user support, brainstorming, and planning.
            Be concise, specific to the app, and action-oriented.
            Avoid mentioning internal implementation details.
            """
        }

        let response = try await session.respond(
            to: """
            Capability: \(capability.title)
            Coach: \(context.coachName)
            Saved activities: \(context.activityCount)
            Weekly distance: \(String(format: "%.1f", context.weeklyDistanceKilometers)) km
            Goal summary: \(context.currentGoalSummary ?? "No active goal.")

            App map:
            - Me: motivation, coach settings, highlights, activity history, settings
            - Social: squad, clubs, rivals
            - Floating orange button: start or resume a live session

            User request: \(prompt)

            Answer in 2 to 4 short paragraphs. Offer a next step when useful.
            """,
            generating: AssistantGeneratedReply.self,
            options: GenerationOptions(
                sampling: .greedy,
                temperature: 0.2,
                maximumResponseTokens: 220
            )
        )

        return response.content.text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
private struct AssistantGeneratedReply {
    @Guide(description: "A concise assistant reply in 2 to 4 short paragraphs.")
    let text: String
}
#endif
