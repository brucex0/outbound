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
    let onStartRun: (SessionIntent?) -> Void
    let onOpenTogether: () -> Void
    @State private var showsCompanionExplanation = false
    @State private var showsChangeSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: OutboundSpacing.standard) {
                    OutboundCard(style: .companion) {
                        VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                            Text("“You don’t need a perfect run. You need a beginning.”")
                                .font(.title3.weight(.semibold))
                        }
                    }

                    OutboundCard {
                        VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(todayWorkoutName).font(.title3.weight(.semibold))
                                Spacer()
                                Text(todayTotalDuration).font(.headline.monospacedDigit())
                                Button { showsChangeSheet = true } label: {
                                    Image(systemName: "slider.horizontal.3")
                                        .frame(width: 30, height: 30)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Change today’s run")
                                Button { showsCompanionExplanation = true } label: {
                                    Image(systemName: "info.circle")
                                        .frame(width: 30, height: 30)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Why this workout")
                            }
                            CompactIntervalPreview(phases: todayPhases)
                            OutboundPrimaryButton(title: "Start run", systemImage: "figure.run") {
                                onStartRun(plannedRunIntent)
                            }
                        }
                    }

                    Button {
                        onStartRun(.freestyleRun)
                    } label: {
                        Label("Quick start", systemImage: "bolt.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: OutboundRadius.control))

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
        .sheet(isPresented: $showsChangeSheet) {
            TodayChangeSheet(originalTitle: "\(todayWorkoutName) · \(todayTotalDuration)") { reason, note, minutes, startsRun in
                Task { await personalizationStore.submitReadiness(reason, workoutID: todayWorkoutID, note: note) }
                showsChangeSheet = false
                if startsRun { onStartRun(changedRunIntent(minutes: minutes, reason: reason)) }
            }
            .presentationDetents([.medium, .large])
        }
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

    private var todayWorkoutName: String {
        let rawName = currentCalibrationWorkout?.title ?? trainingPlanStore.todaySuggestion?.workout.title ?? "Easy run"
        return rawName.components(separatedBy: " · ").first ?? rawName
    }

    private var todayTotalDuration: String {
        let stepSeconds = plannedRunIntent.workoutSteps.reduce(0) { $0 + $1.durationSeconds }
        return durationLabel(stepSeconds > 0 ? stepSeconds : plannedRunIntent.targetDurationSeconds ?? 30 * 60)
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

    private func changedRunIntent(minutes: Int, reason: ReadinessChoice) -> SessionIntent {
        SessionIntent(
            id: "changed-\(reason.rawValue)-\(minutes)",
            sport: .run,
            title: "\(minutes) min easy run",
            detail: "Run · \(minutes) min · very easy",
            coachLine: reason == .sore
                ? "Keep this very easy and stop if discomfort becomes pain."
                : "Keep the effort easy. A shorter run still protects the habit.",
            startLabel: "Start changed run",
            targetDurationSeconds: minutes * 60
        )
    }
}

private struct CompactIntervalPreview: View {
    let phases: [WorkoutPhaseItem]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(phases.prefix(3).enumerated()), id: \.element.id) { index, phase in
                VStack(spacing: 3) {
                    Text(expandedDuration(phase.duration))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                    Text(phase.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                if index < min(phases.count, 3) - 1 {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
            }
            if phases.count > 3 {
                Text("+\(phases.count - 3)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func expandedDuration(_ value: String) -> String {
        value.replacingOccurrences(of: "m", with: " min")
    }
}

private struct TodayChangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let originalTitle: String
    let onApply: (ReadinessChoice, String?, Int, Bool) -> Void
    @State private var reason: ReadinessChoice?
    @State private var note = ""
    @State private var availableMinutes = 15

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                if let reason {
                    Text(reasonHeading(reason)).font(.title2.weight(.semibold))
                    Text(recommendationText(reason)).font(.subheadline).foregroundStyle(.secondary)

                    if reason == .shortOnTime {
                        Picker("Available time", selection: $availableMinutes) {
                            ForEach([10, 15, 20], id: \.self) { Text("\($0) min").tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }

                    TextField("Anything else? (optional)", text: $note, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...3)

                    Spacer()

                    OutboundPrimaryButton(title: primaryTitle(reason), systemImage: primaryIcon(reason)) {
                        onApply(reason, cleanedNote, recommendedMinutes(reason), reason != .sore)
                    }
                    Button("Keep original") { dismiss() }
                        .frame(maxWidth: .infinity)
                } else {
                    Text("What needs to change?").font(.title2.weight(.semibold))
                    Text(originalTitle).font(.subheadline).foregroundStyle(.secondary)
                    changeReasonButton("Less time", icon: "clock", reason: .shortOnTime)
                    changeReasonButton("Low energy", icon: "battery.25percent", reason: .tired)
                    changeReasonButton("Sore or uncomfortable", icon: "bandage", reason: .sore)
                    Spacer()
                }
            }
            .padding(OutboundSpacing.screen)
            .navigationTitle("Change today’s run")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private func changeReasonButton(_ title: String, icon: String, reason: ReadinessChoice) -> some View {
        Button { self.reason = reason } label: {
            HStack { Label(title, systemImage: icon); Spacer(); Image(systemName: "chevron.right") }
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.bordered)
    }

    private var cleanedNote: String? {
        let value = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func recommendedMinutes(_ reason: ReadinessChoice) -> Int { reason == .shortOnTime ? availableMinutes : 15 }
    private func reasonHeading(_ reason: ReadinessChoice) -> String {
        switch reason { case .tired: "Try 15 minutes easy"; case .sore: "Rest today"; case .shortOnTime: "Fit the time you have"; case .good: "Keep today’s run" }
    }
    private func recommendationText(_ reason: ReadinessChoice) -> String {
        switch reason {
        case .tired: "A short easy run keeps the rhythm without forcing the full workout."
        case .sore: "Skipping one run is better than turning discomfort into an injury."
        case .shortOnTime: "Outbound will keep this easy and end it at your selected time."
        case .good: "The original workout still fits."
        }
    }
    private func primaryTitle(_ reason: ReadinessChoice) -> String { reason == .sore ? "Use rest day" : "Start changed run" }
    private func primaryIcon(_ reason: ReadinessChoice) -> String { reason == .sore ? "bed.double" : "figure.run" }
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
    @EnvironmentObject private var authStore: AuthStore
    @State private var confirmsSignOut = false

    var body: some View {
        Form {
            Section("Account") {
                if let label = authStore.currentLoginLabel {
                    LabeledContent("Signed in as", value: label)
                }
                Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    confirmsSignOut = true
                }
            }
            Section("Profile") {
                NavigationLink {
                    SimplifiedProfileEditorView()
                } label: {
                    Label("Name and running bio", systemImage: "person.crop.circle")
                }
            }
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
        .confirmationDialog("Sign out of Outbound?", isPresented: $confirmsSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { authStore.signOut() }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct SimplifiedProfileEditorView: View {
    @EnvironmentObject private var authStore: AuthStore
    @State private var displayName = ""
    @State private var bio = ""
    @State private var username = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Circle()
                        .fill(OutboundPalette.companion.opacity(0.16))
                        .frame(width: 58, height: 58)
                        .overlay {
                            Text(initials).font(.headline.weight(.bold)).foregroundStyle(OutboundPalette.companion)
                        }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(displayName.isEmpty ? "Your profile" : displayName).font(.headline)
                        if !username.isEmpty { Text("@\(username)").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            Section {
                TextField("Display name", text: $displayName)
                    .textInputAutocapitalization(.words)
                TextField("Running bio", text: $bio, axis: .vertical)
                    .lineLimit(2...4)
            } header: {
                Text("About you")
            } footer: {
                Text("Your name and bio may appear to people you connect with in Together.")
            }
            if let message {
                Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                    .disabled(isSaving || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .overlay { if isLoading { ProgressView() } }
        .task { await load() }
    }

    private var initials: String {
        let source = displayName.isEmpty ? authStore.currentLoginLabel ?? "Me" : displayName
        return source.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    private func load() async {
        defer { isLoading = false }
        do {
            let profile = try await APIClient.shared.fetchMyProfile()
            displayName = profile.displayName
            bio = profile.bio ?? ""
            username = profile.username
        } catch {
            displayName = authStore.currentLoginLabel ?? ""
            message = "Profile could not be loaded."
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let profile = try await APIClient.shared.updateMyProfile(
                AppUserProfileUpdateDTO(
                    displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                    bio: bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : bio.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
            displayName = profile.displayName
            bio = profile.bio ?? ""
            message = "Profile saved."
        } catch {
            message = "Could not save profile. Try again."
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
        .environmentObject(TogetherStore())
        .environmentObject(MeasurementPreferences())
        .environmentObject(CycleAwareStore())
}
