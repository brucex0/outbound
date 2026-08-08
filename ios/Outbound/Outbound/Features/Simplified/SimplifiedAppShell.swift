import SwiftUI

enum SimplifiedAppTab: Hashable {
    case together
    case today
    case me
}

struct SimplifiedAppShell: View {
    @EnvironmentObject private var activityStore: ActivityStore
    @EnvironmentObject private var dailyCheckInStore: DailyCheckInStore
    @EnvironmentObject private var trainingPlanStore: TrainingPlanStore
    let onStartRun: (SessionIntent?) -> Void
    @State private var selection: SimplifiedAppTab = .today

    var body: some View {
        TabView(selection: $selection) {
            SimplifiedTogetherView()
                .tag(SimplifiedAppTab.together)
                .tabItem { Label("Together", systemImage: "person.2") }

            SimplifiedTodayView(onStartRun: onStartRun)
                .tag(SimplifiedAppTab.today)
                .tabItem { Label("Today", systemImage: "sparkles") }

            SimplifiedMeView()
                .tag(SimplifiedAppTab.me)
                .tabItem { Label("Me", systemImage: "person.crop.circle") }
        }
        .tint(OutboundPalette.companion)
        .onAppear {
            trainingPlanStore.refresh(
                activities: activityStore.activities,
                readiness: dailyCheckInStore.readiness,
                phase: DailyMotivationEngine.phase(for: activityStore.activities)
            )
        }
    }
}

private struct SimplifiedTodayView: View {
    @EnvironmentObject private var personalizationStore: PersonalizationStore
    @EnvironmentObject private var trainingPlanStore: TrainingPlanStore
    let onStartRun: (SessionIntent?) -> Void
    @State private var showsReadinessCheckIn = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: OutboundSpacing.standard) {
                    OutboundCard(style: .companion) {
                        VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                            Text("“You don’t need a perfect run. You need a beginning.”")
                                .font(.title3.weight(.semibold))
                            Text("One relaxed run completes your week.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.78))
                        }
                    }

                    OutboundCard {
                        VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                            Text("TODAY · AI ADJUSTED")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(todayTitle)
                                .font(.title3.weight(.semibold))
                            Text(todayDetail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            WorkoutPhaseSummary(phases: todayPhases)
                            OutboundPrimaryButton(title: "Start run", systemImage: "figure.run") {
                                showsReadinessCheckIn = true
                            }
                            HStack {
                                quickAction("15 min", image: "clock")
                                quickAction("Tired", image: "moon.zzz")
                                quickAction("Ask", image: "sparkles")
                            }
                            AIExplanationView(text: todayExplanation)
                        }
                    }

                    OutboundCard {
                        CalibrationProgressBanner(summary: personalizationStore.snapshot.calibration)
                    }

                    if let adjustment = personalizationStore.snapshot.pendingAdjustment {
                        OutboundCard(style: .companion) {
                            VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                                Text("A BETTER FIT FOR TODAY")
                                    .font(.caption.weight(.semibold))
                                Text(adjustment.explanation)
                                    .font(.subheadline)
                                ForEach(adjustment.changes, id: \.workoutId) { change in
                                    Text("\(change.beforeTitle) → \(change.afterTitle)")
                                        .font(.subheadline.weight(.semibold))
                                }
                                HStack {
                                    Button("Keep original") {
                                        Task { await personalizationStore.decideAdjustment(accept: false) }
                                    }
                                    .buttonStyle(.bordered)
                                    Button("Use change") {
                                        Task { await personalizationStore.decideAdjustment(accept: true) }
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                                .tint(OutboundPalette.companion)
                            }
                        }
                    }

                    OutboundCard {
                        VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                            Text("QUICK RUN")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("Run without today’s workout")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            HStack {
                                quickRunAction("Open", image: "infinity")
                                quickRunAction("Distance", image: "ruler")
                                quickRunAction("Time", image: "timer")
                            }
                        }
                    }

                    OutboundCard {
                        HStack(spacing: OutboundSpacing.standard) {
                            Image(systemName: "heart.circle.fill")
                                .font(.title2)
                                .foregroundStyle(OutboundPalette.companion)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Better together")
                                    .font(.headline)
                                Text("A family member has a compatible easy run.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Invite") {}
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
                .padding(.horizontal, OutboundSpacing.screen)
                .padding(.vertical, OutboundSpacing.standard)
            }
            .background(OutboundPalette.background)
            .navigationTitle("Today")
        }
        .sheet(isPresented: $showsReadinessCheckIn) {
            ReadinessCheckInView(workoutTitle: todayTitle) { choice in
                if let choice {
                    Task { await personalizationStore.submitReadiness(choice, workoutID: todayWorkoutID) }
                }
                showsReadinessCheckIn = false
                onStartRun(plannedRunIntent)
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func quickAction(_ title: String, image: String) -> some View {
        Button {} label: {
            Label(title, systemImage: image)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 38)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: OutboundRadius.control))
    }

    private func quickRunAction(_ title: String, image: String) -> some View {
        Button {
            onStartRun(quickRunIntent(for: title))
        } label: {
            Label(title, systemImage: image)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: OutboundRadius.control))
    }

    private var plannedRunIntent: SessionIntent {
        if let workout = currentCalibrationWorkout {
            return SessionIntent(
                id: workout.id,
                sport: .run,
                title: workout.title,
                detail: "Run · \(durationLabel(workout.durationSeconds)) · conversational effort",
                coachLine: workout.purpose,
                startLabel: "Start workout",
                targetDurationSeconds: workout.durationSeconds,
                workoutSteps: workout.steps.map {
                    SessionIntentStep(id: $0.id, label: $0.label, durationSeconds: $0.durationSeconds, detail: $0.detail)
                }
            )
        }
        if let suggestion = trainingPlanStore.todaySuggestion {
            return suggestion.suggestedSession.intent
        }
        return SessionIntent(
            id: "today-comfortable-run",
            sport: .run,
            title: "Easy run",
            detail: "Run · 30 min · conversational effort",
            coachLine: "Settle into a conversational effort and keep this one comfortable.",
            startLabel: "Start workout",
            targetDurationSeconds: 30 * 60,
            workoutSteps: [
                SessionIntentStep(id: "warmup", label: "Warm-up", durationSeconds: 5 * 60, detail: "Very easy"),
                SessionIntentStep(id: "relaxed", label: "Relaxed", durationSeconds: 20 * 60, detail: "Conversational effort"),
                SessionIntentStep(id: "cooldown", label: "Cool-down", durationSeconds: 5 * 60, detail: "Ease down"),
            ]
        )
    }

    private var todayWorkoutID: String {
        currentCalibrationWorkout?.id ?? trainingPlanStore.todaySuggestion?.workout.id ?? plannedRunIntent.id
    }

    private var todayTitle: String {
        if let workout = currentCalibrationWorkout {
            return "\(workout.title) · \(durationLabel(workout.durationSeconds))"
        }
        guard let suggestion = trainingPlanStore.todaySuggestion else { return "Easy run · 30 min" }
        return "\(suggestion.workout.title) · \(suggestion.workout.durationLabel)"
    }

    private var todayDetail: String {
        if currentCalibrationWorkout != nil { return "Run naturally at a conversational effort" }
        return trainingPlanStore.todaySuggestion?.workout.effortLabel ?? "Conversational effort"
    }

    private var todayExplanation: String {
        if let workout = currentCalibrationWorkout { return workout.purpose }
        return trainingPlanStore.todaySuggestion?.adjustmentLine
            ?? trainingPlanStore.todaySuggestion?.coachLine
            ?? "This approachable run builds consistency while Outbound learns your natural easy effort."
    }

    private var todayPhases: [WorkoutPhaseItem] {
        if let workout = currentCalibrationWorkout {
            return workout.steps.map {
                WorkoutPhaseItem(
                    id: $0.id,
                    duration: durationLabel($0.durationSeconds).replacingOccurrences(of: " min", with: "m"),
                    title: $0.label,
                    weight: max(1, CGFloat($0.durationSeconds) / 300)
                )
            }
        }
        let steps = trainingPlanStore.todaySuggestion?.workout.steps ?? []
        guard !steps.isEmpty else {
            return [
                WorkoutPhaseItem(id: "warmup", duration: "5m", title: "Warm-up", weight: 1),
                WorkoutPhaseItem(id: "relaxed", duration: "20m", title: "Relaxed", weight: 3),
                WorkoutPhaseItem(id: "cooldown", duration: "5m", title: "Cool-down", weight: 1),
            ]
        }
        return steps.map {
            WorkoutPhaseItem(
                id: $0.id,
                duration: $0.durationLabel.replacingOccurrences(of: " min", with: "m"),
                title: $0.label,
                weight: max(1, CGFloat($0.durationSeconds) / 300)
            )
        }
    }

    private var currentCalibrationWorkout: CalibrationWorkoutDTO? {
        guard personalizationStore.snapshot.calibration.status == .inProgress,
              let kind = personalizationStore.snapshot.calibration.currentSession else { return nil }
        return personalizationStore.snapshot.calibrationWorkouts.first { $0.kind == kind }
    }

    private func durationLabel(_ seconds: Int) -> String {
        seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds / 60)m \(seconds % 60)s"
    }

    private func quickRunIntent(for title: String) -> SessionIntent {
        switch title {
        case "Distance":
            return SessionIntent(
                id: "quick-distance-5k",
                sport: .run,
                title: "5 km run",
                detail: "Run · 5 km distance goal",
                coachLine: "Run by feel and let the distance goal mark the finish.",
                startLabel: "Start 5 km run",
                targetDistanceMeters: 5_000
            )
        case "Time":
            return SessionIntent(
                id: "quick-time-30",
                sport: .run,
                title: "30 min run",
                detail: "Run · 30 min time goal",
                coachLine: "Choose an effort you can sustain for the full thirty minutes.",
                startLabel: "Start 30 min run",
                targetDurationSeconds: 30 * 60
            )
        default:
            return .freestyleRun
        }
    }
}

private struct SimplifiedTogetherView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                    Text("UP NEXT")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    OutboundCard {
                        VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                            Text("Run with family")
                                .font(.headline)
                            Text("Today after 6:30 · Easy 30 min")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            AIExplanationView(text: "Your workouts are compatible.")
                        }
                    }

                    Text("CLUBS")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    OutboundCard {
                        VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                            Text("Saturday long run")
                                .font(.headline)
                            Text("8:00 AM · Three distance groups")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            AIExplanationView(text: "The middle-distance group matches your plan.")
                        }
                    }
                }
                .padding(OutboundSpacing.screen)
            }
            .background(OutboundPalette.background)
            .navigationTitle("Together")
        }
    }
}

private struct SimplifiedMeView: View {
    @EnvironmentObject private var personalizationStore: PersonalizationStore

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: OutboundSpacing.standard) {
                    OutboundCard {
                        VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                            Text("CURRENT FOCUS")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("Run consistently · Week 3 of 8")
                                .font(.headline)
                            Text("3 runs per week")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !personalizationStore.snapshot.insights.isEmpty {
                        OutboundCard {
                            VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                                Text("WHAT I’VE LEARNED")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                ForEach(personalizationStore.snapshot.insights.prefix(3)) { insight in
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text(insight.label).font(.subheadline.weight(.semibold))
                                            Spacer()
                                            Text(insight.confidence.title)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(insight.value)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    if insight.id != personalizationStore.snapshot.insights.prefix(3).last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                    OutboundCard {
                        VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                            HStack {
                                Text("This week")
                                    .font(.headline)
                                Spacer()
                                Text("2 of 3")
                                    .font(.headline)
                            }
                            ProgressView(value: 2, total: 3)
                                .tint(OutboundPalette.companion)
                            AIExplanationView(text: "One easy run completes the week.")
                        }
                    }
                }
                .padding(OutboundSpacing.screen)
            }
            .background(OutboundPalette.background)
            .navigationTitle("Me")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") {}
                }
            }
        }
    }
}

private extension RunnerConfidence {
    var title: String {
        switch self {
        case .low: "Learning"
        case .medium: "Some confidence"
        case .high: "High confidence"
        }
    }
}

#Preview {
    SimplifiedAppShell(onStartRun: { _ in })
        .environmentObject(ActivityStore())
        .environmentObject(DailyCheckInStore())
        .environmentObject(PersonalizationStore())
        .environmentObject(TrainingPlanStore())
}
