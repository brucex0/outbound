import Foundation

enum GoalProgressEngine {
    static func makeProgress(
        goal: GoalDefinition,
        activities: [SavedActivity],
        addingSummary summary: ActivitySummary? = nil,
        calendar: Calendar = .current
    ) -> GoalProgressSnapshot {
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: goal.weekStart) ?? goal.weekStart
        let inRangeActivities = activities.filter { activity in
            activity.startedAt >= goal.weekStart && activity.startedAt < weekEnd
        }

        let baseValue: Int
        switch goal.kind {
        case .weeklySessions:
            baseValue = inRangeActivities.count
        case .weeklyMinutes:
            let totalSeconds = inRangeActivities.reduce(0) { $0 + $1.durationSecs }
            baseValue = Int(ceil(Double(totalSeconds) / 60.0))
        }

        let extraValue: Int
        switch goal.kind {
        case .weeklySessions:
            extraValue = summary == nil ? 0 : 1
        case .weeklyMinutes:
            if let summary {
                extraValue = Int(ceil(Double(summary.durationSecs) / 60.0))
            } else {
                extraValue = 0
            }
        }

        let currentValue = baseValue + extraValue
        let remainingValue = max(0, goal.targetValue - currentValue)
        let isComplete = currentValue >= goal.targetValue
        let percentComplete = min(1, goal.targetValue > 0 ? Double(currentValue) / Double(goal.targetValue) : 1)

        return GoalProgressSnapshot(
            goal: goal,
            currentValue: currentValue,
            targetValue: goal.targetValue,
            percentComplete: percentComplete,
            isComplete: isComplete,
            remainingValue: remainingValue,
            summaryLine: summaryLine(kind: goal.kind, currentValue: currentValue, targetValue: goal.targetValue),
            coachLine: coachLine(kind: goal.kind, remainingValue: remainingValue, isComplete: isComplete)
        )
    }

    static func suggestedTarget(
        theme: GoalFocusTheme,
        activities: [SavedActivity],
        phase: MotivationPhase,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> Int {
        let recentWeekCount = activitiesThisWeek(activities: activities, calendar: calendar, now: now)

        switch theme {
        case .lightMovement:
            if recentWeekCount >= 3 || phase == .momentum { return 45 }
            return 20
        case .comeback:
            return recentWeekCount >= 2 ? 3 : 2
        case .consistency:
            if phase == .momentum { return 4 }
            if recentWeekCount >= 2 { return 3 }
            return 2
        }
    }

    private static func activitiesThisWeek(
        activities: [SavedActivity],
        calendar: Calendar,
        now: Date
    ) -> Int {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        return activities.filter { week.contains($0.startedAt) }.count
    }

    private static func summaryLine(kind: GoalKind, currentValue: Int, targetValue: Int) -> String {
        switch kind {
        case .weeklySessions:
            return "\(currentValue) of \(targetValue) sessions this week"
        case .weeklyMinutes:
            return "\(currentValue) of \(targetValue) min this week"
        }
    }

    private static func coachLine(kind: GoalKind, remainingValue: Int, isComplete: Bool) -> String {
        if isComplete {
            return "You completed this week's focus."
        }

        switch kind {
        case .weeklySessions:
            if remainingValue == 1 {
                return "One more session would finish this week's focus."
            }
            return "\(remainingValue) more sessions would finish this week's focus."
        case .weeklyMinutes:
            return "\(remainingValue) more minutes would finish this week's focus."
        }
    }
}
