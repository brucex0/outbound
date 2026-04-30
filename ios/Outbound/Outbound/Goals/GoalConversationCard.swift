import SwiftUI

struct GoalConversationCard: View {
    @EnvironmentObject private var goalStore: GoalStore

    let phase: MotivationPhase
    let activities: [SavedActivity]
    let accentColor: Color

    var body: some View {
        Group {
            if let progress = goalStore.progress, goalStore.conversation.step == .idle {
                activeGoalCard(progress: progress)
            } else {
                switch goalStore.conversation.step {
                case .idle:
                    EmptyView()
                case .chooseFocus:
                    chooseFocusCard
                case .chooseTarget:
                    chooseTargetCard
                case .confirmDraft:
                    confirmDraftCard
                }
            }
        }
    }

    private func activeGoalCard(progress: GoalProgressSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(progress.isComplete ? "Weekly focus complete" : "This week's focus")
                .font(.headline)

            Text(progress.summaryLine)
                .font(.title3.weight(.bold))

            Text(progress.coachLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            GoalProgressBar(progress: progress.percentComplete, accentColor: accentColor)

            HStack(spacing: 10) {
                Button(progress.isComplete ? "Set next focus" : "Adjust") {
                    goalStore.reopenAdjustFlow()
                }
                .buttonStyle(.borderedProminent)
                .tint(accentColor)

                Button("Clear") {
                    goalStore.clearGoal()
                }
                .buttonStyle(.bordered)
                .tint(accentColor)
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var chooseFocusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Coach wants to help with this week.")
                .font(.headline)

            Text(promptForPhase)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            chipGrid(items: GoalFocusTheme.allCases.map(\.title)) { title in
                guard let theme = GoalFocusTheme.allCases.first(where: { $0.title == title }) else { return }
                goalStore.chooseFocus(theme, activities: activities, phase: phase)
            }

            Button("Not now") {
                goalStore.dismissConversation()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var chooseTargetCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(goalStore.conversation.draft?.theme.coachPrompt ?? "Let's keep it realistic.")
                .font(.headline)

            Text(targetPrompt)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            chipGrid(items: targetOptions.map(targetLabel)) { label in
                guard let value = targetOptions.first(where: { targetLabel($0) == label }) else { return }
                goalStore.chooseTarget(value)
            }

            Button("Help me choose") {
                goalStore.chooseSuggestedTarget()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(accentColor)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var confirmDraftCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Let's make it simple.")
                .font(.headline)

            Text(confirmCopy)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Lock it in") {
                    goalStore.confirmDraft(activities: activities)
                }
                .buttonStyle(.borderedProminent)
                .tint(accentColor)

                Button("Make it easier") {
                    goalStore.easeDraftGoal()
                }
                .buttonStyle(.bordered)
                .tint(accentColor)
            }
            .font(.subheadline.weight(.semibold))

            Button("Change it") {
                goalStore.reopenAdjustFlow()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var promptForPhase: String {
        switch phase {
        case .comeback:
            return "Want a gentle focus for the rest of the week?"
        case .momentum:
            return "You already have some rhythm. Want to turn it into a simple focus?"
        case .completedToday:
            return "You showed up today. Want to give the rest of the week a shape?"
        default:
            return "Want a simple focus for this week?"
        }
    }

    private var targetPrompt: String {
        switch goalStore.conversation.draft?.kind {
        case .weeklyMinutes:
            return "How much movement feels doable this week?"
        default:
            return "What feels realistic right now?"
        }
    }

    private var targetOptions: [Int] {
        switch goalStore.conversation.draft?.kind {
        case .weeklyMinutes:
            return [20, 45, 60]
        default:
            return [2, 3, 4]
        }
    }

    private func targetLabel(_ value: Int) -> String {
        switch goalStore.conversation.draft?.kind {
        case .weeklyMinutes:
            return "\(value) min"
        default:
            return value == 1 ? "1 session" : "\(value) sessions"
        }
    }

    private var confirmCopy: String {
        guard let draft = goalStore.conversation.draft else {
            return "Short sessions still count."
        }

        switch draft.kind {
        case .weeklySessions:
            let sessionWord = draft.targetValue == 1 ? "session" : "sessions"
            return "\(draft.targetValue) \(sessionWord) this week. Short sessions still count. Want to lock that in?"
        case .weeklyMinutes:
            return "\(draft.targetValue) minutes this week. Keep it light and honest. Want to lock that in?"
        }
    }

    private func chipGrid(items: [String], action: @escaping (String) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
            ForEach(items, id: \.self) { item in
                Button(item) {
                    action(item)
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(.primary)
            }
        }
    }
}

private struct GoalProgressBar: View {
    let progress: Double
    let accentColor: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.systemBackground))
                Capsule()
                    .fill(accentColor)
                    .frame(width: geometry.size.width * progress)
            }
        }
        .frame(height: 10)
    }
}
