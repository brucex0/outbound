import SwiftUI

struct SimplifiedOnboardingFlow: View {
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @EnvironmentObject private var personalizationStore: PersonalizationStore
    @EnvironmentObject private var trainingPlanStore: TrainingPlanStore
    let onComplete: (OnboardingProfile) -> Void

    @State private var step: Step = .goal
    @State private var goal = Goal.consistency
    @State private var frequency = Frequency.oneOrTwo
    @State private var comfortableMinutes = 30
    @State private var runsPerWeek = 3
    @State private var availableMinutes = 30

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step.rawValue + 1), total: Double(Step.allCases.count))
                    .tint(OutboundPalette.companion)
                    .padding(.horizontal, OutboundSpacing.screen)
                ScrollView {
                    VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                        content
                    }
                    .padding(OutboundSpacing.screen)
                }
                footer
                    .padding(OutboundSpacing.screen)
            }
            .background(OutboundPalette.background)
            .navigationTitle(step.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if step != .goal {
                        Button("Back", systemImage: "chevron.left") { step = step.previous }
                    }
                }
            }
        }
        .interactiveDismissDisabled()
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .goal:
            heading("What are you working toward?", "Your companion will turn this into a realistic first week.")
            choices(Goal.allCases, selection: $goal)
        case .baseline:
            heading("What does running look like lately?", "A starting estimate is enough. Your runs will make it more accurate.")
            Text("RECENT FREQUENCY").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            choices(Frequency.allCases, selection: $frequency)
            Stepper("Comfortable run · \(comfortableMinutes) min", value: $comfortableMinutes, in: 10...90, step: 5)
                .padding().background(.background, in: RoundedRectangle(cornerRadius: OutboundRadius.control))
        case .week:
            heading("What can most weeks support?", "Choose what feels realistic, not ideal.")
            Stepper("\(runsPerWeek) runs per week", value: $runsPerWeek, in: 2...6)
                .padding().background(.background, in: RoundedRectangle(cornerRadius: OutboundRadius.control))
            Stepper("About \(availableMinutes) min on weekdays", value: $availableMinutes, in: 15...90, step: 5)
                .padding().background(.background, in: RoundedRectangle(cornerRadius: OutboundRadius.control))
        case .understanding:
            heading("Here’s what I understand", "Correct anything by going back. Outbound will keep learning after setup.")
            summaryRow("Goal", goal.title)
            summaryRow("Starting point", "\(frequency.title) · \(comfortableMinutes) min comfortable")
            summaryRow("Realistic week", "\(runsPerWeek) runs · about \(availableMinutes) min")
            AIExplanationView(text: "Your first runs will tune effort, endurance, and recovery. These are starting estimates, not judgments.")
        case .calibration:
            heading("We’ll learn as you run", "No all-out test is required. These are normal training runs.")
            calibrationRow(1, "Comfortable run", "Learn your natural easy effort")
            calibrationRow(2, "Easy + pickups", "Observe controlled faster running")
            calibrationRow(3, "Longer relaxed run", "Learn endurance and recovery")
            AIExplanationView(text: "After each run, one optional tap tells Outbound what the numbers alone cannot.")
        }
    }

    private var footer: some View {
        OutboundPrimaryButton(
            title: step == .calibration ? "Build my first week" : "Continue",
            systemImage: step == .calibration ? "sparkles" : "arrow.right"
        ) {
            if step == .calibration { complete() } else { step = step.next }
        }
    }

    private func complete() {
        onboardingStore.updateGoalText(goal.intakeText)
        onboardingStore.updateBaselineText("I run \(frequency.intakeText) and feel comfortable for about \(comfortableMinutes) minutes.")
        onboardingStore.updateScheduleText("I can run \(runsPerWeek) times per week for about \(availableMinutes) minutes, with a longer run on Saturday.")
        onboardingStore.selectEffortPreference(.balanced)
        let profile = onboardingStore.complete()
        if let recommendation = trainingPlanStore.planOptions.first {
            trainingPlanStore.acceptRecommendation(recommendation)
        }
        Task {
            await personalizationStore.completeProfile(
                RunnerProfileRequestDTO(
                    goalSummary: goal.title,
                    scheduleSummary: "\(runsPerWeek) runs per week, Saturday longer",
                    comfortableDurationMinutes: comfortableMinutes,
                    recentSessionsPerWeek: frequency.sessions,
                    targetSessionsPerWeek: runsPerWeek,
                    preferredLongRunDay: "Saturday",
                    coachingDetail: "balanced",
                    constraints: [:],
                    complete: true
                )
            )
        }
        onComplete(profile)
    }

    private func heading(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title2.weight(.semibold))
            Text(subtitle).foregroundStyle(.secondary)
        }
    }

    private func choices<T: Identifiable & Hashable & Titled>(_ values: [T], selection: Binding<T>) -> some View {
        VStack(spacing: OutboundSpacing.compact) {
            ForEach(values) { value in
                Button { selection.wrappedValue = value } label: {
                    HStack { Text(value.title); Spacer(); Image(systemName: selection.wrappedValue == value ? "checkmark.circle.fill" : "circle") }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .tint(selection.wrappedValue == value ? OutboundPalette.companion : .secondary)
            }
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        OutboundCard { VStack(alignment: .leading, spacing: 4) { Text(label.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary); Text(value).font(.headline) } }
    }

    private func calibrationRow(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(spacing: OutboundSpacing.standard) {
            Text("\(number)").font(.headline).frame(width: 34, height: 34).background(OutboundPalette.companion.opacity(0.14), in: Circle())
            VStack(alignment: .leading) { Text(title).font(.headline); Text(detail).font(.subheadline).foregroundStyle(.secondary) }
        }
        .padding().background(.background, in: RoundedRectangle(cornerRadius: OutboundRadius.control))
    }
}

private protocol Titled { var title: String { get } }

private extension SimplifiedOnboardingFlow {
    enum Step: Int, CaseIterable {
        case goal, baseline, week, understanding, calibration
        var title: String { "\(rawValue + 1) of \(Self.allCases.count)" }
        var next: Self { Self(rawValue: rawValue + 1) ?? self }
        var previous: Self { Self(rawValue: rawValue - 1) ?? self }
    }

    enum Goal: String, CaseIterable, Identifiable, Titled {
        case consistency, start, comeback, race, faster
        var id: Self { self }
        var title: String {
            switch self { case .consistency: "Run consistently"; case .start: "Start running"; case .comeback: "Return after a break"; case .race: "Train for a race"; case .faster: "Run faster" }
        }
        var intakeText: String { "My running goal is to \(title.lowercased()) in a realistic, sustainable way." }
    }

    enum Frequency: String, CaseIterable, Identifiable, Titled {
        case none, occasional, oneOrTwo, threePlus
        var id: Self { self }
        var title: String { switch self { case .none: "Not running yet"; case .occasional: "Occasionally"; case .oneOrTwo: "1–2 times a week"; case .threePlus: "3+ times a week" } }
        var sessions: Int { switch self { case .none: 0; case .occasional: 1; case .oneOrTwo: 2; case .threePlus: 3 } }
        var intakeText: String { title.lowercased() }
    }
}
