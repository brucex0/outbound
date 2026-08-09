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
    @EnvironmentObject private var cycleAwareStore: CycleAwareStore
    let onStartRun: (SessionIntent?) -> Void
    @State private var selection: SimplifiedAppTab = .today

    var body: some View {
        TabView(selection: $selection) {
            SimplifiedTogetherView()
                .tag(SimplifiedAppTab.together)
                .tabItem { Label("Together", systemImage: "person.2") }

            SimplifiedTodayView(onStartRun: onStartRun) {
                selection = .together
            }
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
    @EnvironmentObject private var cycleAwareStore: CycleAwareStore
    let onStartRun: (SessionIntent?) -> Void
    let onOpenTogether: () -> Void
    @State private var showsCompanionExplanation = false
    @State private var showsTiredOption = false

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
                                onStartRun(plannedRunIntent)
                            }
                            HStack {
                                quickAction("15 min", image: "clock") {
                                    onStartRun(shortRunIntent)
                                }
                                quickAction("Tired", image: "moon.zzz") {
                                    showsTiredOption = true
                                    Task { await personalizationStore.submitReadiness(.tired, workoutID: todayWorkoutID) }
                                }
                                quickAction("Why?", image: "sparkles") {
                                    showsCompanionExplanation = true
                                }
                            }
                            AIExplanationView(text: todayExplanation)
                        }
                    }

                    if showsTiredOption {
                        OutboundCard(style: .companion) {
                            VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                                Text("LOW-ENERGY OPTION").font(.caption.weight(.semibold))
                                Text("Make today 15 minutes easy?").font(.headline)
                                Text("You’ll protect the habit without forcing the full workout.")
                                    .font(.subheadline).foregroundStyle(.white.opacity(0.8))
                                HStack {
                                    Button("Keep original") { showsTiredOption = false }.buttonStyle(.bordered)
                                    Button("Use 15 min") { onStartRun(shortRunIntent) }.buttonStyle(.borderedProminent)
                                }
                            }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if cycleAwareStore.isEnabled, cycleAwareStore.currentSignal != .noAdjustment {
                        OutboundCard(style: .companion) {
                            VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                                Text("A FLEXIBLE OPTION").font(.caption.weight(.semibold))
                                Text(cycleAwareStore.currentSignal.title).font(.headline)
                                Text("Choose what feels right; this does not change your long-term plan unless you accept it.")
                                    .font(.subheadline).foregroundStyle(.white.opacity(0.8))
                                HStack {
                                    Button("Keep workout") { onStartRun(plannedRunIntent) }.buttonStyle(.bordered)
                                    Button("Choose gentler") { onStartRun(shortRunIntent) }.buttonStyle(.borderedProminent)
                                }
                            }
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
                            Button("Invite", action: onOpenTogether)
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
        .alert("Why this workout?", isPresented: $showsCompanionExplanation) {
            Button("Got it", role: .cancel) {}
        } message: {
            Text(todayExplanation)
        }
    }

    private func quickAction(_ title: String, image: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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

    private var shortRunIntent: SessionIntent {
        SessionIntent(
            id: "quick-time-15",
            sport: .run,
            title: "15 min easy run",
            detail: "Run · 15 min time goal",
            coachLine: "Keep the effort easy. A short run still protects the habit.",
            startLabel: "Start 15 min run",
            targetDurationSeconds: 15 * 60
        )
    }
}

private struct SimplifiedTogetherView: View {
    @EnvironmentObject private var togetherStore: TogetherStore
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                    if let message = togetherStore.errorMessage {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }

                    if togetherStore.state.upcomingRuns.isEmpty && togetherStore.state.posts.isEmpty {
                        OutboundCard(style: .companion) {
                            VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                                Text("Running is better together")
                                    .font(.headline)
                                Text("Invite family or friends, or join a club run that fits your plan.")
                                    .font(.subheadline)
                                ShareLink(
                                    item: URL(string: "https://outbound.run")!,
                                    subject: Text("Run with me on Outbound"),
                                    message: Text("Join me for a run on Outbound."),
                                    preview: SharePreview("Run with me on Outbound", image: Image(systemName: "figure.run"))
                                ) {
                                    Label("Invite someone", systemImage: "person.badge.plus")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    } else {
                        if !togetherStore.state.upcomingRuns.isEmpty {
                            Text("UP NEXT").sectionLabel()
                        }
                        ForEach(togetherStore.state.upcomingRuns.prefix(2)) { run in
                            OutboundCard {
                                VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                                    Text(run.club?.name ?? run.creator.displayName)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(run.title).font(.headline)
                                    Text(run.startsAt.formatted(date: .abbreviated, time: .shortened) + locationSuffix(run.locationName))
                                        .font(.subheadline).foregroundStyle(.secondary)
                                    if let compatibility = run.compatibility {
                                        AIExplanationView(text: compatibility.explanation)
                                    }
                                    HStack {
                                        if let invitationURL = togetherStore.latestInvitationURL {
                                            ShareLink(item: invitationURL) { Label("Share invite", systemImage: "square.and.arrow.up") }
                                                .buttonStyle(.borderedProminent)
                                        } else {
                                            Button("Invite", systemImage: "person.badge.plus") {
                                                Task { await togetherStore.invite(to: run) }
                                            }
                                            .buttonStyle(.bordered)
                                        }
                                    }
                                }
                            }
                        }

                        if !togetherStore.state.clubs.isEmpty {
                            Text("YOUR CLUBS").sectionLabel()
                            ForEach(togetherStore.state.clubs.prefix(3)) { club in
                                OutboundCard {
                                    HStack {
                                        Image(systemName: "flag.fill").foregroundStyle(OutboundPalette.companion)
                                        VStack(alignment: .leading) {
                                            Text(club.name).font(.headline)
                                            Text([club.city, club.role?.capitalized].compactMap { $0 }.joined(separator: " · "))
                                                .font(.subheadline).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }

                        if !togetherStore.state.posts.isEmpty {
                            Text("RECENT").sectionLabel()
                            ForEach(togetherStore.state.posts.prefix(5)) { post in
                                OutboundCard {
                                    VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                                        HStack {
                                            Image(systemName: "person.crop.circle.fill").font(.title2)
                                            VStack(alignment: .leading) {
                                                Text(post.user.displayName).font(.headline)
                                                Text(post.createdAt.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                        Text(post.activity?.title ?? "Run").font(.headline)
                                        if let activity = post.activity {
                                            HStack {
                                                socialStat(activity.distanceM.map { measurementPreferences.unitSystem.distanceString(meters: $0, fractionDigits: 1) } ?? "—", "Distance")
                                                socialStat(activity.durationSecs.map { $0.formatted() } ?? "—", "Time")
                                                socialStat(activity.avgPace.map { $0.paceString(for: measurementPreferences.unitSystem) } ?? "—", "Pace")
                                            }
                                        }
                                        if let caption = post.caption, !caption.isEmpty { Text(caption).font(.subheadline) }
                                        Button("Cheer · \(post.reactions.count)", systemImage: "heart") {
                                            Task { await togetherStore.react(to: post) }
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(OutboundSpacing.screen)
            }
            .background(OutboundPalette.background)
            .navigationTitle("Together")
            .refreshable { await togetherStore.refresh() }
        }
    }

    private func locationSuffix(_ location: String?) -> String { location.map { " · \($0)" } ?? "" }

    private func socialStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(value).font(.subheadline.monospacedDigit().weight(.semibold)); Text(label).font(.caption).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension Text {
    func sectionLabel() -> some View {
        font(.caption.weight(.semibold)).foregroundStyle(.secondary)
    }
}

private struct SimplifiedMeView: View {
    @EnvironmentObject private var personalizationStore: PersonalizationStore
    @EnvironmentObject private var activityStore: ActivityStore
    @EnvironmentObject private var trainingPlanStore: TrainingPlanStore
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    @EnvironmentObject private var cycleAwareStore: CycleAwareStore

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: OutboundSpacing.standard) {
                    OutboundCard {
                        VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                            Text("CURRENT FOCUS")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(planTitle)
                                .font(.headline)
                            Text(planDetail)
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
                                Text("\(weekRuns) of \(weekTarget)")
                                    .font(.headline)
                            }
                            ProgressView(value: Double(weekRuns), total: Double(max(1, weekTarget)))
                                .tint(OutboundPalette.companion)
                            HStack {
                                meStat(measurementPreferences.unitSystem.distanceString(meters: weekDistance, fractionDigits: 1), "Distance")
                                meStat(weekDuration.formatted(), "Time")
                            }
                            AIExplanationView(text: weekCoachLine)
                        }
                    }
                    OutboundCard {
                        VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                            Text("PRIVATE TRAINING CONTEXT").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            NavigationLink {
                                CycleAwareView()
                            } label: {
                                Label(cycleAwareStore.summary, systemImage: "heart.text.square")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    OutboundCard {
                        VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                            HStack {
                                Text("RECENT RUNS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Spacer()
                                NavigationLink("See all") { ActivityHistoryView() }.font(.subheadline)
                            }
                            if activityStore.activities.isEmpty {
                                Text("Your completed runs will appear here.").font(.subheadline).foregroundStyle(.secondary)
                            } else {
                                ForEach(activityStore.activities.prefix(3)) { activity in
                                    NavigationLink(value: activity) {
                                        HStack {
                                            VStack(alignment: .leading) {
                                                Text(activity.title).font(.subheadline.weight(.semibold))
                                                Text(activity.startedAt.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Text(measurementPreferences.unitSystem.distanceString(meters: activity.distanceM, fractionDigits: 1)).font(.subheadline.monospacedDigit())
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(OutboundSpacing.screen)
            }
            .background(OutboundPalette.background)
            .navigationTitle("Me")
            .navigationDestination(for: SavedActivity.self) { ActivityDetailView(activity: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SimplifiedSettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
    }

    private var planTitle: String {
        guard let plan = trainingPlanStore.activePlan else { return "Building your running rhythm" }
        let week = trainingPlanStore.currentWeek?.currentWeekIndex ?? 1
        return "\(plan.title) · Week \(week) of \(plan.durationWeeks)"
    }

    private var planDetail: String { "\(weekTarget) runs per week" }
    private var weekTarget: Int { trainingPlanStore.currentWeek?.targetSessions ?? trainingPlanStore.activePlan?.sessionsPerWeek ?? 3 }
    private var weekRuns: Int { trainingPlanStore.currentWeek?.completedSessions ?? currentWeekActivities.count }
    private var weekDistance: Double { currentWeekActivities.reduce(0) { $0 + $1.distanceM } }
    private var weekDuration: Int { currentWeekActivities.reduce(0) { $0 + $1.durationSecs } }
    private var weekCoachLine: String {
        trainingPlanStore.currentWeek?.coachLine ?? (weekRuns >= weekTarget ? "You completed this week’s rhythm." : "\(max(0, weekTarget - weekRuns)) comfortable run\(weekTarget - weekRuns == 1 ? "" : "s") complete the week.")
    }
    private var currentWeekActivities: [SavedActivity] {
        guard let interval = Calendar.current.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        return activityStore.activities.filter { interval.contains($0.startedAt) }
    }
    private func meStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading) { Text(value).font(.headline.monospacedDigit()); Text(label).font(.caption).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SimplifiedSettingsView: View {
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences

    var body: some View {
        Form {
            Section("Units") {
                Picker("Measurement", selection: $measurementPreferences.unitSystem) {
                    ForEach(MeasurementUnitSystem.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            Section("Health & body") {
                NavigationLink("Cycle-aware coaching") { CycleAwareView() }
            }
            Section("Gear") {
                GearSettingsCard()
            }
            Section {
                Text("Outbound keeps private health details on this device and never shows them in Together.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
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
        .environmentObject(TogetherStore())
        .environmentObject(MeasurementPreferences())
        .environmentObject(CycleAwareStore())
}
