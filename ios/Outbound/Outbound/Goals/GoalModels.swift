import Foundation

enum GoalKind: String, Codable {
    case weeklySessions
    case weeklyMinutes
}

enum GoalStatus: String, Codable {
    case active
    case completed
    case expired
}

enum GoalFocusTheme: String, Codable, CaseIterable, Identifiable {
    case consistency
    case comeback
    case lightMovement

    var id: String { rawValue }

    var title: String {
        switch self {
        case .consistency:
            return "Build consistency"
        case .comeback:
            return "Get back into rhythm"
        case .lightMovement:
            return "Move by time"
        }
    }

    var coachPrompt: String {
        switch self {
        case .consistency:
            return "Let's build something you can repeat."
        case .comeback:
            return "Let's make the return feel low-pressure and real."
        case .lightMovement:
            return "Let's keep the week about time on your feet, not pressure."
        }
    }
}

struct GoalDefinition: Codable, Identifiable, Equatable {
    let id: UUID
    let kind: GoalKind
    let theme: GoalFocusTheme
    let targetValue: Int
    let weekStart: Date
    let createdAt: Date
    var status: GoalStatus
}

enum GoalConversationStep: String, Codable {
    case idle
    case chooseFocus
    case chooseTarget
    case confirmDraft
}

struct GoalDraft: Codable, Equatable {
    var kind: GoalKind
    var theme: GoalFocusTheme
    var targetValue: Int
}

struct GoalConversationState: Codable, Equatable {
    var step: GoalConversationStep
    var draft: GoalDraft?
    var dismissedWeekStart: Date?

    static let idle = GoalConversationState(step: .idle, draft: nil, dismissedWeekStart: nil)
}

struct GoalProgressSnapshot: Equatable {
    let goal: GoalDefinition
    let currentValue: Int
    let targetValue: Int
    let percentComplete: Double
    let isComplete: Bool
    let remainingValue: Int
    let summaryLine: String
    let coachLine: String
}
