import SwiftUI
import PhotosUI
import UIKit
import Combine

enum SimplifiedAppTab: Hashable {
    case social
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
            SocialHomeView()
                .tag(SimplifiedAppTab.social)
                .tabItem { Label("Social", systemImage: "person.2") }

            SimplifiedTodayView(onStartRun: onStartRun) {
                selection = .social
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
    @EnvironmentObject private var activityStore: ActivityStore
    @EnvironmentObject private var coachCatalog: CoachCatalogStore
    @EnvironmentObject private var dailyCheckInStore: DailyCheckInStore
    @EnvironmentObject private var personalizationStore: PersonalizationStore
    @EnvironmentObject private var trainingPlanStore: TrainingPlanStore
    @EnvironmentObject private var weatherStore: SituationalWeatherStore
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    let onStartRun: (SessionIntent?) -> Void
    let onOpenTogether: () -> Void
    @State private var showsCompanionExplanation = false
    @State private var showsActivityCompanion = false
    @State private var showsChangeSheet = false
    @State private var showsWeatherSheet = false
    @State private var companionTodayMessage: String?
    @State private var companionWeatherFetchDate: Date?
    @State private var companionActivityID: UUID?
    @State private var isCompanionInsightLoading = false
    @State private var companionRequestID: UUID?
    @State private var customizedRunIntent: SessionIntent?

    private var dailySpark: CoachSpark {
        DailyMotivationEngine.makeSnapshot(
            activities: activityStore.activities,
            readiness: dailyCheckInStore.readiness,
            persona: coachCatalog.selectedPersona
        ).spark
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: OutboundSpacing.standard) {
                    OutboundCard(style: .companion) {
                        VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                            Text(dailySpark.headline)
                                .font(.title3.weight(.semibold))
                            Text(dailySpark.message)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let completedActivityToday {
                        completedTodayCard(completedActivityToday)
                    } else {
                        plannedWorkoutCard
                    }

                    if completedActivityToday != nil {
                        Button {
                            onStartRun(activeRunIntent)
                        } label: {
                            Label("Run again", systemImage: "arrow.clockwise")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 46)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.roundedRectangle(radius: OutboundRadius.control))
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
            .navigationDestination(for: SavedActivity.self) { ActivityDetailView(activity: $0) }
            .task {
                weatherStore.refreshForToday()
                await loadCompanionTodayMessage()
            }
            .onChange(of: weatherStore.snapshot) { _, _ in
                Task { await loadCompanionTodayMessage() }
            }
            .onChange(of: completedActivityToday?.id) { _, _ in
                Task { await loadCompanionTodayMessage(force: true) }
            }
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
        .sheet(isPresented: $showsWeatherSheet) {
            WeatherDetailSheet(
                snapshot: weatherStore.snapshot,
                errorMessage: weatherStore.errorMessage,
                unitSystem: measurementPreferences.unitSystem,
                onRefresh: { weatherStore.refresh(force: true) }
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showsActivityCompanion) {
            TodayActivityCompanionSheet(
                message: companionInsightMessage,
                isLoading: isCompanionInsightLoading,
                activity: activeRunIntent,
                onApply: { customizedRunIntent = $0 }
            )
            .presentationDetents([.medium, .large])
        }
    }

    private var plannedWorkoutCard: some View {
        OutboundCard {
            VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                HStack(alignment: .firstTextBaseline) {
                    Text(todayWorkoutName).font(.title3.weight(.semibold))
                    Spacer()
                    Text(todayTotalDuration).font(.headline.monospacedDigit())
                    companionButton
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
                TodayWeatherRow(
                    snapshot: weatherStore.snapshot,
                    errorMessage: weatherStore.errorMessage,
                    isLoading: weatherStore.isLoading,
                    unitSystem: measurementPreferences.unitSystem,
                    onOpen: { showsWeatherSheet = true }
                )
                CompactIntervalPreview(phases: todayPhases)
                OutboundPrimaryButton(title: "Start run", systemImage: "figure.run") {
                    onStartRun(activeRunIntent)
                }
            }
        }
    }

    private func completedTodayCard(_ activity: SavedActivity) -> some View {
        OutboundCard(style: .companion) {
            VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                Label("Today’s run is done", systemImage: "checkmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(OutboundPalette.companion)
                HStack {
                    Text("Nice work. Recover well and let this one count.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    companionButton
                }
                HStack {
                    todayStat(measurementPreferences.unitSystem.distanceString(meters: activity.distanceM, fractionDigits: 1), "Distance")
                    todayStat(durationLabel(activity.durationSecs), "Time")
                }
                NavigationLink(value: activity) {
                    Label("View today’s activity", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(OutboundPalette.companion)
            }
        }
    }

    private var companionButton: some View {
        Button {
            showsActivityCompanion = true
            Task { await loadCompanionTodayMessage(force: true) }
        } label: {
            Image(systemName: "sparkles")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(OutboundPalette.companion.gradient, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ask companion about this activity")
        .accessibilityHint("Get guidance or customize the activity conversationally")
    }

    private func todayStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var completedActivityToday: SavedActivity? {
        activityStore.activities.first { Calendar.current.isDateInToday($0.startedAt) }
    }

    private func loadCompanionTodayMessage(force: Bool = false) async {
        let weatherFetchDate = weatherStore.snapshot?.fetchedAt
        let activity = completedActivityToday
        let didActivityChange = companionActivityID != activity?.id
        guard force
                || companionTodayMessage == nil
                || companionWeatherFetchDate != weatherFetchDate
                || didActivityChange
        else { return }

        if didActivityChange {
            companionTodayMessage = nil
        }
        companionWeatherFetchDate = weatherFetchDate
        companionActivityID = activity?.id
        let requestID = UUID()
        companionRequestID = requestID
        isCompanionInsightLoading = true

        var signals = weatherStore.snapshot.map { [$0.companionSignal] } ?? []
        if let activity {
            signals.append(completedActivitySignal(activity))
        }

        let response = try? await APIClient.shared.sendCompanionTurn(CompanionTurnRequestDTO(
            task: .adaptToday,
            surface: .today,
            prompt: companionTodayPrompt(activity: activity),
            conversationKey: "ios-today",
            recentMessages: [],
            currentEntityIds: [todayWorkoutID] + (activity.map { [$0.id.uuidString] } ?? []),
            clientCapabilities: ["read-only-intervention", "context-receipt"],
            isOffline: false,
            timeZoneIdentifier: TimeZone.current.identifier,
            signals: signals
        ))
        guard companionRequestID == requestID else { return }
        isCompanionInsightLoading = false
        if let message = response?.message {
            companionTodayMessage = message
        }
    }

    private func companionTodayPrompt(activity: SavedActivity?) -> String {
        let base = "What is the one most useful thing for me to know about today's training? If a situational signal matters, recommend the smallest safe adjustment, but do not mutate the plan."
        guard let activity else { return base }
        let distance = measurementPreferences.unitSystem.distanceString(meters: activity.distanceM, fractionDigits: 1)
        return """
        \(base)
        The local activity store confirms that today's workout is complete: \(activity.title), \(durationLabel(activity.durationSecs)), \(distance). Do not describe today as a rest day or recommend another workout as though the planned activity is still pending. Focus on recovery, reflection, or the next useful step.
        """
    }

    private func completedActivitySignal(_ activity: SavedActivity) -> CompanionSituationalSignalDTO {
        let tomorrow = Calendar.current.date(
            byAdding: .day,
            value: 1,
            to: Calendar.current.startOfDay(for: activity.endedAt)
        ) ?? activity.endedAt.addingTimeInterval(24 * 60 * 60)
        return CompanionSituationalSignalDTO(
            idempotencyKey: "ios-activity-completed-\(activity.id.uuidString)",
            type: "activity_completed",
            value: "title=\(activity.title);duration_seconds=\(activity.durationSecs);distance_meters=\(Int(activity.distanceM.rounded()))",
            source: "ios_local_activity_store",
            confidence: 1,
            privacy: "standard",
            consequenceLevel: "low",
            possibleEffects: ["update_today_status", "shift_to_recovery_guidance"],
            scope: ["activity_id": activity.id.uuidString],
            observedAt: activity.endedAt,
            freshUntil: tomorrow
        )
    }

    private var companionInsightMessage: String {
        if let companionTodayMessage { return companionTodayMessage }
        if let activity = completedActivityToday {
            return "You completed today’s \(durationLabel(activity.durationSecs)) activity. Let that work count and prioritize recovery now."
        }
        return todayExplanation
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

    private var activeRunIntent: SessionIntent {
        customizedRunIntent ?? plannedRunIntent
    }

    private var todayWorkoutID: String {
        currentCalibrationWorkout?.id ?? trainingPlanStore.todaySuggestion?.workout.id ?? plannedRunIntent.id
    }

    private var todayWorkoutName: String {
        if let customizedRunIntent { return customizedRunIntent.title }
        let rawName = currentCalibrationWorkout?.title ?? trainingPlanStore.todaySuggestion?.workout.title ?? "Easy run"
        return rawName.components(separatedBy: " · ").first ?? rawName
    }

    private var todayTotalDuration: String {
        let stepSeconds = activeRunIntent.workoutSteps.reduce(0) { $0 + $1.durationSeconds }
        return durationLabel(stepSeconds > 0 ? stepSeconds : activeRunIntent.targetDurationSeconds ?? 30 * 60)
    }

    private var todayExplanation: String {
        if let workout = currentCalibrationWorkout { return workout.purpose }
        return trainingPlanStore.todaySuggestion?.adjustmentLine
            ?? trainingPlanStore.todaySuggestion?.coachLine
            ?? "This approachable run builds consistency while Plainstride learns your natural easy effort."
    }

    private var todayPhases: [WorkoutPhaseItem] {
        if let customizedRunIntent {
            let seconds = customizedRunIntent.targetDurationSeconds ?? 0
            return [WorkoutPhaseItem(
                id: customizedRunIntent.id,
                duration: durationLabel(seconds).replacingOccurrences(of: " min", with: "m"),
                title: customizedRunIntent.title,
                weight: max(1, CGFloat(seconds) / 300)
            )]
        }
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

private struct TodayActivityCompanionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let message: String
    let isLoading: Bool
    let activity: SessionIntent
    let onApply: (SessionIntent) -> Void
    @State private var draft = ""
    @State private var conversation: [TodayCompanionLine] = []
    @State private var currentActivity: SessionIntent
    @State private var isResponding = false

    init(message: String, isLoading: Bool, activity: SessionIntent, onApply: @escaping (SessionIntent) -> Void) {
        self.message = message
        self.isLoading = isLoading
        self.activity = activity
        self.onApply = onApply
        _currentActivity = State(initialValue: activity)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                    activitySummary
                    if isLoading {
                        HStack(spacing: OutboundSpacing.compact) {
                            ProgressView()
                            Text("Looking at today’s activity…")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(message)
                            .padding(12)
                            .background(OutboundPalette.companion.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                    }

                    ForEach(conversation) { line in
                        Text(line.text)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: line.isUser ? .trailing : .leading)
                            .background(
                                line.isUser ? OutboundPalette.companion.opacity(0.18) : Color(.secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 14)
                            )
                    }
                    if isResponding {
                        ProgressView().controlSize(.small)
                    }
                }
                .padding(OutboundSpacing.screen)
            }
            .safeAreaInset(edge: .bottom) {
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Try “Make it 20 minutes and easy”", text: $draft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isResponding)
                }
                .padding()
                .background(.thinMaterial)
            }
            .navigationTitle("Adjust with companion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var activitySummary: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(OutboundPalette.companion.gradient, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(currentActivity.title).font(.headline)
                Text(currentActivity.detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: currentActivity.id)
    }

    private func send() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        draft = ""
        conversation.append(TodayCompanionLine(text: prompt, isUser: true))

        if let adjusted = adjustedActivity(for: prompt) {
            currentActivity = adjusted
            onApply(adjusted)
            conversation.append(TodayCompanionLine(
                text: "Done — I updated the activity card to \(adjusted.title). You can keep refining it here or start when ready.",
                isUser: false
            ))
        }

        isResponding = true
        Task {
            let response = try? await APIClient.shared.sendCompanionTurn(CompanionTurnRequestDTO(
                task: .adaptToday,
                surface: .today,
                prompt: "The user is customizing today's activity conversationally. Current activity: \(currentActivity.title), \(currentActivity.detail). Request: \(prompt). Give a concise, useful response.",
                conversationKey: "ios-today-activity-customization",
                recentMessages: conversation.suffix(6).map {
                    CompanionPriorMessageDTO(role: $0.isUser ? "user" : "assistant", text: $0.text)
                },
                currentEntityIds: [currentActivity.id],
                clientCapabilities: ["activity-ui-customization", "plan-adjustment-confirmation", "context-receipt"],
                isOffline: false,
                timeZoneIdentifier: TimeZone.current.identifier,
                signals: []
            ))
            if adjustedActivity(for: prompt) == nil {
                conversation.append(TodayCompanionLine(
                    text: response?.message ?? "Tell me a duration or effort—like “25 minutes,” “easy,” or “tempo”—and I’ll update the card.",
                    isUser: false
                ))
            }
            isResponding = false
        }
    }

    private func adjustedActivity(for prompt: String) -> SessionIntent? {
        let normalized = prompt.lowercased()
        let minutes = firstNumber(in: normalized).flatMap { (5...240).contains($0) ? $0 : nil }
        let effort: (title: String, detail: String, coach: String)? = {
            if normalized.contains("recovery") || normalized.contains("very easy") {
                return ("Recovery run", "very easy", "Keep this restorative and finish feeling better than you started.")
            }
            if normalized.contains("easy") || normalized.contains("easier") {
                return ("Easy run", "conversational effort", "Relax the pace and keep the effort conversational.")
            }
            if normalized.contains("tempo") || normalized.contains("harder") {
                return ("Tempo run", "comfortably hard", "Stay controlled; this should feel strong, not all-out.")
            }
            return nil
        }()
        guard minutes != nil || effort != nil else { return nil }

        let totalSeconds = (minutes ?? currentMinutes) * 60
        let title = effort?.title ?? currentActivity.title
        return SessionIntent(
            id: "companion-\(UUID().uuidString)",
            sport: currentActivity.sport,
            title: title,
            detail: "\(currentActivity.sport.displayName) · \(totalSeconds / 60) min · \(effort?.detail ?? "customized")",
            coachLine: effort?.coach ?? currentActivity.coachLine,
            startLabel: "Start activity",
            targetDistanceMeters: currentActivity.targetDistanceMeters,
            targetDurationSeconds: totalSeconds,
            routeName: currentActivity.routeName,
            workoutSteps: []
        )
    }

    private var currentMinutes: Int {
        let seconds = currentActivity.targetDurationSeconds
            ?? currentActivity.workoutSteps.reduce(0) { $0 + $1.durationSeconds }
        return max(5, seconds / 60)
    }

    private func firstNumber(in text: String) -> Int? {
        text.split { !$0.isNumber }.compactMap { Int($0) }.first
    }
}

private struct TodayCompanionLine: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
}

private struct TodayWeatherRow: View {
    let snapshot: RunningWeatherSnapshot?
    let errorMessage: String?
    let isLoading: Bool
    let unitSystem: MeasurementUnitSystem
    let onOpen: () -> Void

    var body: some View {
        if isLoading && snapshot == nil {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking local conditions…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        } else if let snapshot {
            Button(action: onOpen) {
                HStack(spacing: 8) {
                    Image(systemName: snapshot.symbolName)
                        .foregroundStyle(weatherColor(snapshot.impact))
                    Text(snapshot.temperatureLabel(unitSystem: unitSystem))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                    Text(snapshot.headline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Local conditions, \(snapshot.temperatureLabel(unitSystem: unitSystem)), \(snapshot.headline)")
        } else if let errorMessage {
            Button(action: onOpen) {
                HStack(spacing: 8) {
                    Image(systemName: "location.slash")
                    Text(errorMessage)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking local conditions…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func weatherColor(_ impact: RunningWeatherSnapshot.Impact) -> Color {
        switch impact {
        case .none: OutboundPalette.companion
        case .advisory: .orange
        case .caution, .unsafe: .red
        }
    }
}

private struct WeatherDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let snapshot: RunningWeatherSnapshot?
    let errorMessage: String?
    let unitSystem: MeasurementUnitSystem
    let onRefresh: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                if let snapshot {
                    HStack(spacing: 12) {
                        Image(systemName: snapshot.symbolName)
                            .font(.largeTitle)
                            .foregroundStyle(OutboundPalette.companion)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(snapshot.headline).font(.headline)
                            Text(conditionLine(snapshot))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let guidance = snapshot.guidance {
                        Label(guidance, systemImage: "figure.run")
                            .font(.subheadline)
                    } else {
                        Label("No workout change is suggested.", systemImage: "checkmark.circle")
                            .font(.subheadline)
                    }

                    if let bestWindow = snapshot.bestWindow {
                        Label(bestWindow, systemImage: "clock")
                            .font(.subheadline)
                    }

                    Text("Plainstride uses approximate location for this forecast. Weather advice does not automatically change your plan.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Link("Weather data by Apple Weather", destination: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!)
                        .font(.caption)

                    Spacer()
                    Button("Refresh conditions", action: onRefresh)
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.bordered)
                } else {
                    ContentUnavailableView(
                        "Conditions unavailable",
                        systemImage: "cloud.slash",
                        description: Text(errorMessage ?? "Try again in a moment. Your workout is unchanged.")
                    )
                    Button("Try again", action: onRefresh)
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(OutboundSpacing.screen)
            .navigationTitle(snapshot?.placeName ?? "Local conditions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func conditionLine(_ snapshot: RunningWeatherSnapshot) -> String {
        let precipitation = Int((snapshot.precipitationChance * 100).rounded())
        return "\(snapshot.temperatureLabel(unitSystem: unitSystem)) · Wind \(snapshot.windLabel(unitSystem: unitSystem)) · \(precipitation)% rain"
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
        case .shortOnTime: "Plainstride will keep this easy and end it at your selected time."
        case .good: "The original workout still fits."
        }
    }
    private func primaryTitle(_ reason: ReadinessChoice) -> String { reason == .sore ? "Use rest day" : "Start changed run" }
    private func primaryIcon(_ reason: ReadinessChoice) -> String { reason == .sore ? "bed.double" : "figure.run" }
}

private struct SimplifiedMeView: View {
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var personalizationStore: PersonalizationStore
    @EnvironmentObject private var activityStore: ActivityStore
    @EnvironmentObject private var trainingPlanStore: TrainingPlanStore
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    @EnvironmentObject private var cycleAwareStore: CycleAwareStore
    @State private var profile: AppUserProfileDTO?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: OutboundSpacing.standard) {
                    NavigationLink {
                        SimplifiedProfileEditorView { profile = $0 }
                    } label: {
                        OutboundCard {
                            HStack(spacing: 14) {
                                UserAvatarView(
                                    url: profile?.avatarUrl,
                                    name: profile?.displayName ?? authStore.currentLoginLabel ?? "Me",
                                    size: 58
                                )
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(profile?.displayName ?? authStore.currentLoginLabel ?? "Your profile")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    if let username = profile?.username {
                                        Text("@\(username)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
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
            .task { await loadProfile() }
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

    private func loadProfile() async {
        profile = try? await APIClient.shared.fetchMyProfile()
        UserAvatarPersistence.save(profile?.avatarUrl, for: AuthStore.currentUserId)
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
                NavigationLink {
                    CompanionMemoryView()
                } label: {
                    Label("What Plainstride knows", systemImage: "brain.head.profile")
                }
            }
            Section("Units") {
                Picker("Measurement", selection: $measurementPreferences.unitSystem) {
                    ForEach(MeasurementUnitSystem.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            Section("Health & body") {
                NavigationLink("Cycle-aware guidance") { CycleAwareView() }
            }
            Section {
                Button {
                    FeedbackTrigger.present()
                } label: {
                    Label("Send feedback", systemImage: "ladybug")
                }
            } header: {
                Text("Help")
            } footer: {
                Text("You can also shake your iPhone anywhere in the app to report a bug or share a suggestion.")
            }
            Section("Gear") {
                GearSettingsCard()
            }
            Section {
                Text("Plainstride keeps private health details on this device and never shows them in Together.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Sign out of Plainstride?", isPresented: $confirmsSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { authStore.signOut() }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct SimplifiedProfileEditorView: View {
    @EnvironmentObject private var authStore: AuthStore
    var onProfileUpdated: ((AppUserProfileDTO) -> Void)? = nil
    @State private var displayName = ""
    @State private var bio = ""
    @State private var username = ""
    @State private var avatarUrl = UserAvatarPersistence.url(for: AuthStore.currentUserId)
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var isUploadingAvatar = false
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var toast: ProfileToast?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    UserAvatarView(
                        url: avatarUrl,
                        name: displayName.isEmpty ? authStore.currentLoginLabel ?? "Me" : displayName,
                        size: 58,
                        isProfileLoading: isLoading
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(displayName.isEmpty ? "Your profile" : displayName).font(.headline)
                        if !username.isEmpty { Text("@\(username)").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                        Text(isUploadingAvatar ? "Uploading…" : "Change photo")
                            .font(.subheadline.weight(.semibold))
                    }
                    .disabled(isUploadingAvatar)
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
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                    .disabled(isSaving || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .overlay {
            if isLoading { ProgressView() }
        }
        .overlay(alignment: .top) {
            if let toast {
                ProfileToastView(toast: toast)
                    .padding(.horizontal, OutboundSpacing.screen)
                    .padding(.top, OutboundSpacing.compact)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: toast)
        .task(id: toast?.id) {
            guard toast != nil else { return }
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            toast = nil
        }
        .task { await load() }
        .onChange(of: selectedAvatarItem) { _, item in
            guard let item else { return }
            Task { await uploadAvatar(from: item) }
        }
    }

    private func load() async {
        defer { isLoading = false }
        do {
            let profile = try await APIClient.shared.fetchMyProfile()
            displayName = profile.displayName
            bio = profile.bio ?? ""
            username = profile.username
            avatarUrl = profile.avatarUrl
            UserAvatarPersistence.save(profile.avatarUrl, for: AuthStore.currentUserId)
        } catch {
            displayName = authStore.currentLoginLabel ?? ""
            showToast("Profile could not be loaded.", style: .error)
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
            avatarUrl = profile.avatarUrl
            UserAvatarPersistence.save(profile.avatarUrl, for: AuthStore.currentUserId)
            onProfileUpdated?(profile)
            showToast("Profile saved", style: .success)
        } catch {
            showToast("Could not save profile. Try again.", style: .error)
        }
    }

    private func uploadAvatar(from item: PhotosPickerItem) async {
        isUploadingAvatar = true
        defer {
            isUploadingAvatar = false
            selectedAvatarItem = nil
        }
        do {
            guard let sourceData = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: sourceData),
                  let jpegData = resizedAvatarData(from: image) else {
                showToast("That photo could not be used.", style: .error)
                return
            }
            let profile = try await APIClient.shared.uploadMyAvatar(jpegData: jpegData)
            avatarUrl = profile.avatarUrl
            UserAvatarPersistence.save(profile.avatarUrl, for: AuthStore.currentUserId)
            if let avatarUrl = profile.avatarUrl, let uploadedImage = UIImage(data: jpegData) {
                UserAvatarImageLoader.store(uploadedImage, for: avatarUrl)
            }
            onProfileUpdated?(profile)
            showToast("Profile photo updated", style: .success)
        } catch {
            showToast("Could not upload photo. Try again.", style: .error)
        }
    }

    private func showToast(_ text: String, style: ProfileToast.Style) {
        toast = ProfileToast(text: text, style: style)
    }

    private func resizedAvatarData(from image: UIImage) -> Data? {
        let maximumDimension: CGFloat = 1_024
        let scale = min(1, maximumDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.82)
    }
}

private struct ProfileToast: Identifiable, Equatable {
    enum Style: Equatable {
        case success
        case error
    }

    let id = UUID()
    let text: String
    let style: Style
}

private struct ProfileToastView: View {
    let toast: ProfileToast

    var body: some View {
        Label(toast.text, systemImage: toast.style == .success ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule().strokeBorder(Color.primary.opacity(0.08))
            }
            .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
            .accessibilityElement(children: .combine)
    }
}

private struct UserAvatarView: View {
    let url: String?
    let name: String
    let size: CGFloat
    let isProfileLoading: Bool
    @StateObject private var loader: UserAvatarImageLoader

    init(url: String?, name: String, size: CGFloat, isProfileLoading: Bool = false) {
        self.url = url
        self.name = name
        self.size = size
        self.isProfileLoading = isProfileLoading
        _loader = StateObject(wrappedValue: UserAvatarImageLoader(url: url))
    }

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if isProfileLoading || url != nil {
                Circle()
                    .fill(OutboundPalette.companion.opacity(0.1))
                    .overlay { ProgressView().controlSize(.small) }
            } else {
                Circle()
                    .fill(OutboundPalette.companion.opacity(0.16))
                    .overlay {
                        Text(initials)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(OutboundPalette.companion)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityLabel("\(name) profile photo")
        .task(id: url) { loader.load(url: url) }
    }

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}

@MainActor
private final class UserAvatarImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    private var currentURL: String?
    private static let cache = NSCache<NSString, UIImage>()

    init(url: String?) {
        currentURL = url
        image = url.flatMap { Self.cache.object(forKey: $0 as NSString) }
    }

    static func store(_ image: UIImage, for url: String) {
        cache.setObject(image, forKey: url as NSString)
    }

    func load(url: String?) {
        guard currentURL != url || image == nil else { return }
        currentURL = url
        guard let url, let remoteURL = URL(string: url) else {
            image = nil
            return
        }
        if let cached = Self.cache.object(forKey: url as NSString) {
            image = cached
            return
        }

        Task {
            var request = URLRequest(url: remoteURL)
            request.cachePolicy = .returnCacheDataElseLoad
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let downloadedImage = UIImage(data: data),
                  currentURL == url else { return }
            Self.store(downloadedImage, for: url)
            image = downloadedImage
        }
    }
}

private enum UserAvatarPersistence {
    private static let keyPrefix = "cached_user_avatar_url_v1_"

    static func url(for userID: String?) -> String? {
        guard let userID else { return nil }
        return UserDefaults.standard.string(forKey: keyPrefix + userID)
    }

    static func save(_ url: String?, for userID: String?) {
        guard let userID else { return }
        UserDefaults.standard.set(url, forKey: keyPrefix + userID)
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
