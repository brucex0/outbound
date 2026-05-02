import SwiftUI

@main
struct OutboundApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var authStore = AuthStore()
    @StateObject private var coachStore = CoachStore()
    @StateObject private var coachCatalogStore = CoachCatalogStore()
    @StateObject private var activityStore = ActivityStore()
    @StateObject private var goalStore = GoalStore()
    @StateObject private var assistantStore = AssistantStore()
    @StateObject private var healthAuthorizationStore = HealthAuthorizationStore()
    @StateObject private var healthImportStore = HealthImportStore()
    @StateObject private var dailyCheckInStore = DailyCheckInStore()
    @StateObject private var musicStore = MusicStore()

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
                    .environmentObject(assistantStore)
                    .environmentObject(healthAuthorizationStore)
                    .environmentObject(healthImportStore)
                    .environmentObject(dailyCheckInStore)
                    .environmentObject(musicStore)
                    .task {
                        await coachStore.syncIfNeeded()
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

    init(
        id: UUID = UUID(),
        author: AssistantAuthor,
        text: String,
        createdAt: Date = Date(),
        capability: AssistantCapability? = nil
    ) {
        self.id = id
        self.author = author
        self.text = text
        self.createdAt = createdAt
        self.capability = capability
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

    func sendCurrentDraft(context: AssistantContext) async {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        draft = ""
        await send(trimmed, capability: nil, context: context)
    }

    func sendSuggestion(_ suggestion: AssistantSuggestion, context: AssistantContext) async {
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
    ) async {
        ensureSeedMessage(context: context)
        let inferredCapability = capability ?? Self.inferCapability(from: prompt)
        messages.append(
            AssistantMessage(
                author: .user,
                text: prompt,
                capability: inferredCapability
            )
        )
        persistMessages()

        isResponding = true
        let replyText = await makeReply(
            for: prompt,
            capability: inferredCapability,
            context: context
        )
        isResponding = false

        messages.append(
            AssistantMessage(
                author: .assistant,
                text: replyText,
                capability: inferredCapability
            )
        )
        persistMessages()
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
