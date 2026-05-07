import Combine
import Foundation

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case intent
    case context
    case setup

    var id: Int { rawValue }
}

enum OnboardingIntent: String, Codable, CaseIterable, Identifiable {
    case moveToday
    case buildConsistency
    case restartGently
    case trainForGoal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .moveToday: return "Move today"
        case .buildConsistency: return "Build rhythm"
        case .restartGently: return "Restart gently"
        case .trainForGoal: return "Train for a goal"
        }
    }

    var detail: String {
        switch self {
        case .moveToday: return "Get one clean first session."
        case .buildConsistency: return "Make showing up feel repeatable."
        case .restartGently: return "Come back without overreaching."
        case .trainForGoal: return "Point the week toward progress."
        }
    }

    var systemImage: String {
        switch self {
        case .moveToday: return "bolt.fill"
        case .buildConsistency: return "calendar.badge.checkmark"
        case .restartGently: return "arrow.counterclockwise"
        case .trainForGoal: return "flag.checkered"
        }
    }
}

enum OnboardingExperience: String, Codable, CaseIterable, Identifiable {
    case new
    case returning
    case steady

    var id: String { rawValue }

    var title: String {
        switch self {
        case .new: return "New"
        case .returning: return "Returning"
        case .steady: return "Steady"
        }
    }

    var detail: String {
        switch self {
        case .new: return "Keep the first win tiny."
        case .returning: return "Ease back into rhythm."
        case .steady: return "Give today a clear shape."
        }
    }
}

enum OnboardingSessionLength: Int, Codable, CaseIterable, Identifiable {
    case ten = 10
    case twenty = 20
    case thirtyFive = 35

    var id: Int { rawValue }

    var title: String { "\(rawValue) min" }

    var detail: String {
        switch self {
        case .ten: return "Tiny win"
        case .twenty: return "Useful reset"
        case .thirtyFive: return "Fuller session"
        }
    }
}

enum OnboardingWeeklyRhythm: Int, Codable, CaseIterable, Identifiable {
    case two = 2
    case three = 3
    case four = 4

    var id: Int { rawValue }

    var title: String {
        rawValue == 1 ? "1x / week" : "\(rawValue)x / week"
    }
}

struct OnboardingDraft: Equatable {
    var intent: OnboardingIntent?
    var sport: SportType
    var experience: OnboardingExperience
    var sessionLength: OnboardingSessionLength
    var weeklyRhythm: OnboardingWeeklyRhythm

    static let fresh = OnboardingDraft(
        intent: nil,
        sport: .run,
        experience: .returning,
        sessionLength: .ten,
        weeklyRhythm: .two
    )
}

struct OnboardingProfile: Codable, Equatable {
    let intent: OnboardingIntent
    let sport: SportType
    let experience: OnboardingExperience
    let sessionLength: OnboardingSessionLength
    let weeklyRhythm: OnboardingWeeklyRhythm
    let completedAt: Date

    var suggestedReadiness: DailyReadiness {
        switch (intent, experience) {
        case (.restartGently, _), (_, .new):
            return .okay
        case (.trainForGoal, .steady), (.buildConsistency, .steady):
            return .ready
        default:
            return .okay
        }
    }

    var weeklySetupLine: String {
        let sessionWord = weeklyRhythm.rawValue == 1 ? "session" : "sessions"
        return "\(weeklyRhythm.rawValue) \(sessionWord) this week, starting with \(sessionLength.title.lowercased())."
    }

    var suggestedSession: SuggestedSession {
        SuggestedSession(
            id: "onboarding-\(intent.rawValue)-\(sport.rawValue)-\(sessionLength.rawValue)",
            sport: sport,
            title: sessionTitle,
            durationLabel: sessionLength.title,
            activityLabel: activityLabel,
            framing: sessionFraming,
            coachLine: coachLine,
            startLabel: "Start first session"
        )
    }

    private var sessionTitle: String {
        switch (intent, sport) {
        case (.moveToday, .run): return "\(sessionLength.rawValue) min easy run"
        case (.moveToday, .bike): return "\(sessionLength.rawValue) min easy ride"
        case (.buildConsistency, .run): return "\(sessionLength.rawValue) min rhythm run"
        case (.buildConsistency, .bike): return "\(sessionLength.rawValue) min rhythm ride"
        case (.restartGently, .run): return "\(sessionLength.rawValue) min walk-run"
        case (.restartGently, .bike): return "\(sessionLength.rawValue) min gentle ride"
        case (.trainForGoal, .run): return "\(sessionLength.rawValue) min steady run"
        case (.trainForGoal, .bike): return "\(sessionLength.rawValue) min steady ride"
        }
    }

    private var activityLabel: String {
        switch sport {
        case .run: return intent == .restartGently ? "Walk-run" : "Run"
        case .bike: return "Ride"
        }
    }

    private var sessionFraming: String {
        switch intent {
        case .moveToday:
            return "One real session is enough to teach Outbound your baseline."
        case .buildConsistency:
            return "Keep it repeatable so tomorrow still feels possible."
        case .restartGently:
            return "The win is finishing with energy left."
        case .trainForGoal:
            return "Start controlled so the rest of the week has room."
        }
    }

    private var coachLine: String {
        switch (intent, sport) {
        case (.restartGently, .run):
            return "Alternate easy running and walking whenever you need. Smooth is the goal."
        case (.restartGently, .bike):
            return "Spin lightly and keep the first ride friendly. You are rebuilding the habit."
        case (.trainForGoal, .run):
            return "Stay patient early. A steady first effort gives the plan better signal."
        case (.trainForGoal, .bike):
            return "Hold an easy gear and finish in control. Today is a starting marker."
        case (.buildConsistency, .run):
            return "Run at a pace you would gladly repeat. Consistency starts there."
        case (.buildConsistency, .bike):
            return "Ride easy enough that this can become part of the week."
        case (.moveToday, .run):
            return "No pressure on pace. Just get the first clean session saved."
        case (.moveToday, .bike):
            return "No pressure on speed. Just get the first clean ride saved."
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
    private let completedKeyPrefix = "new_user_onboarding_completed_v1"
    private let profileKeyPrefix = "new_user_onboarding_profile_v1"
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
        case .welcome, .context, .setup:
            return true
        case .intent:
            return draft.intent != nil
        }
    }

    var selectedIntent: OnboardingIntent {
        draft.intent ?? .moveToday
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

    func selectIntent(_ intent: OnboardingIntent) {
        draft.intent = intent
    }

    func selectSport(_ sport: SportType) {
        draft.sport = sport
    }

    func selectExperience(_ experience: OnboardingExperience) {
        draft.experience = experience
        if experience == .steady, draft.sessionLength == .ten {
            draft.sessionLength = .twenty
        }
    }

    func selectSessionLength(_ sessionLength: OnboardingSessionLength) {
        draft.sessionLength = sessionLength
    }

    func selectWeeklyRhythm(_ weeklyRhythm: OnboardingWeeklyRhythm) {
        draft.weeklyRhythm = weeklyRhythm
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
            intent: draft.intent ?? .moveToday,
            sport: draft.sport,
            experience: draft.experience,
            sessionLength: draft.sessionLength,
            weeklyRhythm: draft.weeklyRhythm,
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
}
