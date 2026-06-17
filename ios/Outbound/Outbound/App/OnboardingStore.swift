import Combine
import Foundation

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case goal
    case body
    case baseline
    case review
    case setup

    var id: Int { rawValue }
}

enum OnboardingBodySex: String, Codable, CaseIterable, Identifiable {
    case notSpecified
    case female
    case male

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notSpecified: return "Skip"
        case .female: return "Female"
        case .male: return "Male"
        }
    }
}

enum OnboardingPlanFocus: String, Codable {
    case first5K
    case race
    case runFarther
    case runFaster
    case fitness
    case comeback
    case general

    var title: String {
        switch self {
        case .first5K: return "First 5K"
        case .race: return "Race preparation"
        case .runFarther: return "Run farther"
        case .runFaster: return "Run faster"
        case .fitness: return "Fitness and weight support"
        case .comeback: return "Safe return"
        case .general: return "Steady fitness"
        }
    }
}

enum OnboardingEffortPreference: String, Codable, CaseIterable, Identifiable {
    case easier
    case balanced
    case harder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .easier: return "Easier"
        case .balanced: return "Balanced"
        case .harder: return "Harder"
        }
    }

    var detail: String {
        switch self {
        case .easier: return "More cushion"
        case .balanced: return "Recommended"
        case .harder: return "More challenge"
        }
    }
}

enum OnboardingSessionLength: Int, Codable, CaseIterable, Identifiable {
    case fifteen = 15
    case twentyFive = 25
    case thirtyFive = 35

    var id: Int { rawValue }

    var title: String { "\(rawValue) min" }
}

enum OnboardingWeeklyRhythm: Int, Codable, CaseIterable, Identifiable {
    case two = 2
    case three = 3
    case four = 4
    case five = 5

    var id: Int { rawValue }

    var title: String {
        rawValue == 1 ? "1x / week" : "\(rawValue)x / week"
    }
}

struct OnboardingBodyProfile: Codable, Equatable {
    var ageYears: Int?
    var heightCentimeters: Double?
    var weightKilograms: Double?
    var sex: OnboardingBodySex
    var unitSystem: MeasurementUnitSystem

    var hasRequiredBasics: Bool {
        ageYears != nil && heightCentimeters != nil && weightKilograms != nil
    }

    var calorieEstimateLine: String {
        guard hasRequiredBasics else {
            return "Add age, height, and weight to personalize calorie estimates."
        }
        if sex == .notSpecified {
            return "Calories will use age, height, and weight. Add body profile later for a tighter estimate."
        }
        return "Calories will use age, height, weight, and body profile."
    }
}

struct OnboardingIntakeSummary: Codable, Equatable {
    var focus: OnboardingPlanFocus
    var sport: SportType
    var comfortableDurationMinutes: Int?
    var recentSessionsPerWeek: Int?
    var weeklyRhythm: OnboardingWeeklyRhythm
    var firstSessionLength: OnboardingSessionLength
    var effortPreference: OnboardingEffortPreference
    var cautionLine: String?

    var baselineLine: String {
        var parts: [String] = []
        if let recentSessionsPerWeek {
            parts.append("\(recentSessionsPerWeek)x/week lately")
        }
        if let comfortableDurationMinutes {
            parts.append("comfortable around \(comfortableDurationMinutes) min")
        }
        if parts.isEmpty {
            return "Starting conservatively until Outbound learns from your first sessions."
        }
        return parts.joined(separator: " · ")
    }
}

struct OnboardingDraft: Equatable {
    var goalText: String
    var ageText: String
    var heightText: String
    var weightText: String
    var sex: OnboardingBodySex
    var unitSystem: MeasurementUnitSystem
    var baselineText: String
    var scheduleText: String
    var effortPreference: OnboardingEffortPreference?

    static let fresh = OnboardingDraft(
        goalText: "",
        ageText: "",
        heightText: "",
        weightText: "",
        sex: .notSpecified,
        unitSystem: .imperial,
        baselineText: "",
        scheduleText: "",
        effortPreference: nil
    )
}

struct OnboardingProfile: Codable, Equatable {
    let goalText: String
    let baselineText: String
    let scheduleText: String
    let bodyProfile: OnboardingBodyProfile
    let intakeSummary: OnboardingIntakeSummary
    let completedAt: Date

    var suggestedReadiness: DailyReadiness {
        switch intakeSummary.effortPreference {
        case .easier:
            return .okay
        case .harder:
            return .ready
        case .balanced:
            return intakeSummary.cautionLine == nil ? .ready : .okay
        }
    }

    var weeklySetupLine: String {
        let sessionWord = intakeSummary.weeklyRhythm.rawValue == 1 ? "session" : "sessions"
        return "\(intakeSummary.weeklyRhythm.rawValue) \(sessionWord) this week, starting with \(intakeSummary.firstSessionLength.title.lowercased())."
    }

    var suggestedSession: SuggestedSession {
        SuggestedSession(
            id: "onboarding-\(intakeSummary.focus.rawValue)-\(intakeSummary.sport.rawValue)-\(intakeSummary.firstSessionLength.rawValue)",
            sport: intakeSummary.sport,
            title: sessionTitle,
            durationLabel: intakeSummary.firstSessionLength.title,
            activityLabel: activityLabel,
            framing: sessionFraming,
            coachLine: coachLine,
            startLabel: "Start first session",
            targetDurationSeconds: intakeSummary.firstSessionLength.rawValue * 60
        )
    }

    var planTitle: String {
        switch intakeSummary.focus {
        case .first5K: return "First 5K foundation"
        case .race: return "Race-ready foundation"
        case .runFarther: return "Endurance builder"
        case .runFaster: return "Speed foundation"
        case .fitness: return "Fitness base builder"
        case .comeback: return "Gentle return plan"
        case .general: return "Steady base plan"
        }
    }

    var recommendationRationale: String {
        var reasons = ["your stated goal"]
        if bodyProfile.hasRequiredBasics {
            reasons.append("body basics for calorie estimates")
        }
        if intakeSummary.comfortableDurationMinutes != nil || intakeSummary.recentSessionsPerWeek != nil {
            reasons.append("your current baseline")
        }
        reasons.append("\(intakeSummary.weeklyRhythm.title.lowercased()) availability")
        return "Matched from \(reasons.joined(separator: ", "))."
    }

    private var sessionTitle: String {
        switch (intakeSummary.focus, intakeSummary.sport) {
        case (.first5K, .run), (.comeback, .run):
            return "\(intakeSummary.firstSessionLength.rawValue) min walk-run"
        case (.runFaster, .run):
            return "\(intakeSummary.firstSessionLength.rawValue) min controlled run"
        case (_, .run):
            return "\(intakeSummary.firstSessionLength.rawValue) min easy run"
        case (.comeback, .bike):
            return "\(intakeSummary.firstSessionLength.rawValue) min gentle ride"
        case (_, .bike):
            return "\(intakeSummary.firstSessionLength.rawValue) min easy ride"
        }
    }

    private var activityLabel: String {
        switch intakeSummary.sport {
        case .run:
            return (intakeSummary.focus == .first5K || intakeSummary.focus == .comeback) ? "Walk-run" : "Run"
        case .bike:
            return "Ride"
        }
    }

    private var sessionFraming: String {
        switch intakeSummary.effortPreference {
        case .easier:
            return "A gentle first marker with room to finish feeling good."
        case .balanced:
            return "A useful first marker without forcing the week."
        case .harder:
            return "A controlled first challenge so the coach can tune what comes next."
        }
    }

    private var coachLine: String {
        if let cautionLine = intakeSummary.cautionLine {
            return "\(cautionLine) Keep this first session smooth and leave energy in the tank."
        }

        switch intakeSummary.focus {
        case .first5K:
            return "Alternate easy running and walking whenever you need. The first win is consistency, not pace."
        case .race:
            return "Stay patient early. Today gives the plan a clean starting signal."
        case .runFarther:
            return "Keep the effort conversational. Endurance starts with repeatable work."
        case .runFaster:
            return "Controlled is faster than forced today. Give me a baseline we can build from."
        case .fitness:
            return "No pressure on pace. Save one clean session and we will tune calories and load over time."
        case .comeback:
            return "Smooth and comfortable is the goal. You are rebuilding trust with the routine."
        case .general:
            return "Run at a pace you would gladly repeat. That is the best first signal."
        }
    }
}

@MainActor
final class OnboardingStore: ObservableObject {
    @Published var isPresented = false
    @Published private(set) var step: OnboardingStep = .welcome
    @Published private(set) var draft: OnboardingDraft = .fresh
    @Published private(set) var completedProfile: OnboardingProfile?

    private let defaults: UserDefaults
    private let completedKeyPrefix = "new_user_onboarding_completed_v2"
    private let profileKeyPrefix = "new_user_onboarding_profile_v2"
    private var activeIdentity = "local"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        completedProfile = Self.decode(OnboardingProfile.self, from: defaults.data(forKey: profileKey(for: activeIdentity)))
    }

    var progressText: String {
        "\(step.rawValue + 1) of \(OnboardingStep.allCases.count)"
    }

    var canAdvance: Bool {
        switch step {
        case .welcome, .review, .setup:
            return true
        case .goal:
            return draft.goalText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8
        case .body:
            return bodyProfile.hasRequiredBasics
        case .baseline:
            return draft.baselineText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8
        }
    }

    var bodyProfile: OnboardingBodyProfile {
        OnboardingBodyProfile(
            ageYears: Self.integer(from: draft.ageText),
            heightCentimeters: Self.heightCentimeters(from: draft.heightText, unitSystem: draft.unitSystem),
            weightKilograms: Self.weightKilograms(from: draft.weightText, unitSystem: draft.unitSystem),
            sex: draft.sex,
            unitSystem: draft.unitSystem
        )
    }

    var intakeSummary: OnboardingIntakeSummary {
        OnboardingIntakeAnalyzer.summarize(
            goalText: draft.goalText,
            baselineText: draft.baselineText,
            scheduleText: draft.scheduleText,
            effortOverride: draft.effortPreference
        )
    }

    var previewProfile: OnboardingProfile {
        makeProfile(completedAt: Date())
    }

    func prepareForAuthenticatedUser(identity: String?) {
        let resolvedIdentity = identity?.isEmpty == false ? identity! : "local"
        if resolvedIdentity != activeIdentity {
            activeIdentity = resolvedIdentity
            completedProfile = Self.decode(OnboardingProfile.self, from: defaults.data(forKey: profileKey(for: resolvedIdentity)))
            draft = .fresh
            step = .welcome
        }

        if !hasCompletedOnboarding(for: resolvedIdentity), !isPresented {
            begin()
        }
    }

    func restartForDebug() {
        begin()
    }

    func updateGoalText(_ text: String) {
        draft.goalText = text
    }

    func updateAgeText(_ text: String) {
        draft.ageText = text
    }

    func updateHeightText(_ text: String) {
        draft.heightText = text
    }

    func updateWeightText(_ text: String) {
        draft.weightText = text
    }

    func selectSex(_ sex: OnboardingBodySex) {
        draft.sex = sex
    }

    func selectUnitSystem(_ unitSystem: MeasurementUnitSystem) {
        draft.unitSystem = unitSystem
    }

    func updateBaselineText(_ text: String) {
        draft.baselineText = text
    }

    func updateScheduleText(_ text: String) {
        draft.scheduleText = text
    }

    func selectEffortPreference(_ effortPreference: OnboardingEffortPreference) {
        draft.effortPreference = effortPreference
    }

    func advance() {
        guard canAdvance else { return }
        guard let nextStep = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        step = nextStep
    }

    func goBack() {
        guard let previousStep = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previousStep
    }

    @discardableResult
    func complete(now: Date = Date()) -> OnboardingProfile {
        let profile = makeProfile(completedAt: now)
        completedProfile = profile
        persist(profile: profile)
        defaults.set(true, forKey: completedKey(for: activeIdentity))
        isPresented = false
        return profile
    }

    private func begin() {
        draft = .fresh
        step = .welcome
        isPresented = true
    }

    private func makeProfile(completedAt: Date) -> OnboardingProfile {
        OnboardingProfile(
            goalText: draft.goalText.trimmingCharacters(in: .whitespacesAndNewlines),
            baselineText: draft.baselineText.trimmingCharacters(in: .whitespacesAndNewlines),
            scheduleText: draft.scheduleText.trimmingCharacters(in: .whitespacesAndNewlines),
            bodyProfile: bodyProfile,
            intakeSummary: intakeSummary,
            completedAt: completedAt
        )
    }

    private func hasCompletedOnboarding(for identity: String) -> Bool {
        defaults.bool(forKey: completedKey(for: identity))
    }

    private func persist(profile: OnboardingProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: profileKey(for: activeIdentity))
    }

    private func completedKey(for identity: String) -> String {
        "\(completedKeyPrefix).\(identity)"
    }

    private func profileKey(for identity: String) -> String {
        "\(profileKeyPrefix).\(identity)"
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func integer(from text: String) -> Int? {
        Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func heightCentimeters(from text: String, unitSystem: MeasurementUnitSystem) -> Double? {
        guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        switch unitSystem {
        case .metric:
            return value
        case .imperial:
            return value * 2.54
        }
    }

    private static func weightKilograms(from text: String, unitSystem: MeasurementUnitSystem) -> Double? {
        guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        switch unitSystem {
        case .metric:
            return value
        case .imperial:
            return value * 0.45359237
        }
    }
}

private enum OnboardingIntakeAnalyzer {
    static func summarize(
        goalText: String,
        baselineText: String,
        scheduleText: String,
        effortOverride: OnboardingEffortPreference?
    ) -> OnboardingIntakeSummary {
        let combined = [goalText, baselineText, scheduleText].joined(separator: " ").lowercased()
        let focus = inferFocus(from: combined)
        let sport = combined.containsAny(["bike", "biking", "cycle", "cycling", "ride"]) ? SportType.bike : .run
        let comfortableDuration = inferDurationMinutes(from: baselineText)
        let recentSessions = inferSessionsPerWeek(from: [baselineText, scheduleText].joined(separator: " "))
        let cautionLine = inferCautionLine(from: combined)
        let effort = effortOverride ?? inferEffortPreference(from: combined, cautionLine: cautionLine)
        let weeklyRhythm = inferWeeklyRhythm(from: scheduleText, recentSessions: recentSessions, focus: focus, cautionLine: cautionLine)
        let firstSessionLength = inferFirstSessionLength(
            focus: focus,
            comfortableDuration: comfortableDuration,
            effort: effort,
            cautionLine: cautionLine
        )

        return OnboardingIntakeSummary(
            focus: focus,
            sport: sport,
            comfortableDurationMinutes: comfortableDuration,
            recentSessionsPerWeek: recentSessions,
            weeklyRhythm: weeklyRhythm,
            firstSessionLength: firstSessionLength,
            effortPreference: effort,
            cautionLine: cautionLine
        )
    }

    private static func inferFocus(from text: String) -> OnboardingPlanFocus {
        if text.containsAny(["injury", "injured", "pain", "ache", "back to", "return", "restart", "again"]) {
            return .comeback
        }
        if text.containsAny(["first 5k", "first 5 k", "couch to 5k", "couch to 5 k"]) {
            return .first5K
        }
        if text.containsAny(["race", "marathon", "half", "10k", "10 k", "5k", "5 k", "event"]) {
            return .race
        }
        if text.containsAny(["faster", "speed", "pace", "pr", "personal record"]) {
            return .runFaster
        }
        if text.containsAny(["farther", "further", "longer", "distance", "endurance"]) {
            return .runFarther
        }
        if text.containsAny(["weight", "lose", "fat", "fitness", "health", "cardio"]) {
            return .fitness
        }
        return .general
    }

    private static func inferDurationMinutes(from text: String) -> Int? {
        let lowercased = text.lowercased()
        guard lowercased.containsAny(["min", "minute", "minutes"]) else { return nil }
        return numbers(in: lowercased).filter { $0 >= 5 && $0 <= 180 }.max()
    }

    private static func inferSessionsPerWeek(from text: String) -> Int? {
        let lowercased = text.lowercased()
        if lowercased.containsAny(["twice", "two times"]) { return 2 }
        if lowercased.containsAny(["three times"]) { return 3 }
        if lowercased.containsAny(["four times"]) { return 4 }
        if lowercased.containsAny(["five times"]) { return 5 }

        let candidates = numbers(in: lowercased).filter { $0 >= 1 && $0 <= 7 }
        guard let first = candidates.first else { return nil }
        return min(max(first, 1), 7)
    }

    private static func inferCautionLine(from text: String) -> String? {
        if text.containsAny(["knee", "knees"]) {
            return "You mentioned knee caution."
        }
        if text.containsAny(["achilles"]) {
            return "You mentioned Achilles caution."
        }
        if text.containsAny(["shin", "splint"]) {
            return "You mentioned shin caution."
        }
        if text.containsAny(["injury", "injured", "pain", "ache"]) {
            return "You mentioned an injury or discomfort."
        }
        if text.containsAny(["postpartum", "post natal", "postnatal"]) {
            return "You mentioned a return-after-birth context."
        }
        return nil
    }

    private static func inferEffortPreference(from text: String, cautionLine: String?) -> OnboardingEffortPreference {
        if cautionLine != nil || text.containsAny(["gentle", "easy", "careful", "slow", "safely", "safe"]) {
            return .easier
        }
        if text.containsAny(["push", "hard", "aggressive", "challenge", "ambitious"]) {
            return .harder
        }
        return .balanced
    }

    private static func inferWeeklyRhythm(
        from scheduleText: String,
        recentSessions: Int?,
        focus: OnboardingPlanFocus,
        cautionLine: String?
    ) -> OnboardingWeeklyRhythm {
        let requested = inferSessionsPerWeek(from: scheduleText) ?? recentSessions ?? 3
        let cautiousCap = (focus == .first5K || focus == .comeback || cautionLine != nil) ? 3 : 5
        let capped = min(max(requested, 2), cautiousCap)
        switch capped {
        case 2: return .two
        case 3: return .three
        case 4: return .four
        default: return .five
        }
    }

    private static func inferFirstSessionLength(
        focus: OnboardingPlanFocus,
        comfortableDuration: Int?,
        effort: OnboardingEffortPreference,
        cautionLine: String?
    ) -> OnboardingSessionLength {
        if focus == .first5K || focus == .comeback || cautionLine != nil || effort == .easier {
            return .fifteen
        }
        guard let comfortableDuration else {
            return effort == .harder ? .thirtyFive : .twentyFive
        }
        if comfortableDuration >= 40 || effort == .harder {
            return .thirtyFive
        }
        if comfortableDuration >= 20 {
            return .twentyFive
        }
        return .fifteen
    }

    private static func numbers(in text: String) -> [Int] {
        let matches = text.matches(of: /\d+/)
        return matches.compactMap { Int(String($0.output)) }
    }
}

private extension String {
    func containsAny(_ needles: [String]) -> Bool {
        needles.contains { contains($0) }
    }
}
