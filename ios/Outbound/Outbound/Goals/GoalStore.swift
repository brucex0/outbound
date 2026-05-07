import Combine
import Foundation

@MainActor
final class GoalStore: ObservableObject {
    @Published private(set) var activeGoal: GoalDefinition?
    @Published private(set) var conversation: GoalConversationState
    @Published private(set) var progress: GoalProgressSnapshot?

    private let defaults: UserDefaults
    private let calendar: Calendar
    private let goalKey = "goal_store_active_goal_v1"
    private let conversationKey = "goal_store_conversation_v1"

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
        self.activeGoal = Self.decode(GoalDefinition.self, from: defaults.data(forKey: goalKey))
        self.conversation = Self.decode(GoalConversationState.self, from: defaults.data(forKey: conversationKey)) ?? .idle
    }

    func refresh(
        activities: [SavedActivity],
        phase: MotivationPhase,
        now: Date = Date()
    ) {
        let weekStart = startOfWeek(for: now)

        if let activeGoal, activeGoal.weekStart != weekStart {
            self.activeGoal = nil
            persistActiveGoal()
        }

        if let dismissedWeekStart = conversation.dismissedWeekStart, dismissedWeekStart != weekStart {
            conversation.dismissedWeekStart = nil
        }

        if let activeGoal {
            let newProgress = GoalProgressEngine.makeProgress(goal: activeGoal, activities: activities, calendar: calendar)
            progress = newProgress
            if activeGoal.status != (newProgress.isComplete ? .completed : .active) {
                var updatedGoal = activeGoal
                updatedGoal.status = newProgress.isComplete ? .completed : .active
                self.activeGoal = updatedGoal
                persistActiveGoal()
            }
        } else {
            progress = nil
            if shouldPromptForGoal(activities: activities, phase: phase, weekStart: weekStart), conversation.step == .idle {
                conversation.step = .chooseFocus
            }
        }

        persistConversation()
    }

    func chooseFocus(
        _ theme: GoalFocusTheme,
        activities: [SavedActivity],
        phase: MotivationPhase,
        now: Date = Date()
    ) {
        let kind: GoalKind = theme == .lightMovement ? .weeklyMinutes : .weeklySessions
        let suggested = GoalProgressEngine.suggestedTarget(
            theme: theme,
            activities: activities,
            phase: phase,
            calendar: calendar,
            now: now
        )
        conversation.step = .chooseTarget
        conversation.draft = GoalDraft(kind: kind, theme: theme, targetValue: suggested)
        persistConversation()
    }

    func chooseTarget(_ value: Int) {
        guard var draft = conversation.draft else { return }
        draft.targetValue = value
        conversation.draft = draft
        conversation.step = .confirmDraft
        persistConversation()
    }

    func chooseSuggestedTarget() {
        guard conversation.draft != nil else { return }
        conversation.step = .confirmDraft
        persistConversation()
    }

    func easeDraftGoal() {
        guard var draft = conversation.draft else { return }
        switch draft.kind {
        case .weeklySessions:
            draft.targetValue = max(1, draft.targetValue - 1)
        case .weeklyMinutes:
            draft.targetValue = max(10, draft.targetValue - 15)
        }
        conversation.draft = draft
        conversation.step = .confirmDraft
        persistConversation()
    }

    func confirmDraft(
        activities: [SavedActivity],
        now: Date = Date()
    ) {
        guard let draft = conversation.draft else { return }
        activeGoal = GoalDefinition(
            id: UUID(),
            kind: draft.kind,
            theme: draft.theme,
            targetValue: draft.targetValue,
            weekStart: startOfWeek(for: now),
            createdAt: now,
            status: .active
        )
        conversation.step = .idle
        conversation.draft = nil
        if let activeGoal {
            progress = GoalProgressEngine.makeProgress(goal: activeGoal, activities: activities, calendar: calendar)
        }
        persistActiveGoal()
        persistConversation()
    }

    func reopenAdjustFlow() {
        if let activeGoal {
            conversation.draft = GoalDraft(
                kind: activeGoal.kind,
                theme: activeGoal.theme,
                targetValue: activeGoal.targetValue
            )
            conversation.step = .chooseTarget
            persistConversation()
        } else {
            conversation.step = .chooseFocus
            persistConversation()
        }
    }

    func dismissConversation(now: Date = Date()) {
        conversation.step = .idle
        conversation.draft = nil
        conversation.dismissedWeekStart = startOfWeek(for: now)
        persistConversation()
    }

    func clearGoal() {
        activeGoal = nil
        progress = nil
        persistActiveGoal()
    }

    func previewProgress(
        with summary: ActivitySummary,
        activities: [SavedActivity]
    ) -> GoalProgressSnapshot? {
        guard let activeGoal else { return nil }
        return GoalProgressEngine.makeProgress(goal: activeGoal, activities: activities, addingSummary: summary, calendar: calendar)
    }

    private func shouldPromptForGoal(
        activities: [SavedActivity],
        phase: MotivationPhase,
        weekStart: Date
    ) -> Bool {
        if conversation.dismissedWeekStart == weekStart {
            return false
        }
        if activities.isEmpty {
            return false
        }
        switch phase {
        case .steady, .comeback, .momentum, .completedToday:
            return true
        case .firstSession:
            return false
        }
    }

    private func startOfWeek(for date: Date) -> Date {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else {
            return calendar.startOfDay(for: date)
        }
        return interval.start
    }

    private func persistActiveGoal() {
        if let activeGoal, let data = try? JSONEncoder().encode(activeGoal) {
            defaults.set(data, forKey: goalKey)
        } else {
            defaults.removeObject(forKey: goalKey)
        }
    }

    private func persistConversation() {
        guard let data = try? JSONEncoder().encode(conversation) else { return }
        defaults.set(data, forKey: conversationKey)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
