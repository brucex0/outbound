import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var assistantStore: AssistantStore
    @EnvironmentObject private var appNavigationStore: AppNavigationStore
    @EnvironmentObject private var coachCatalog: CoachCatalogStore
    @State private var selectedTab: AppTab = .me
    @State private var activeLaunch: RecordLaunch?
    @State private var isActivityVisible = false
    @State private var activitySessionState: ActivitySessionPortalState = .idle
    @State private var activityElapsedSeconds = 0
    @State private var assistantChromeState: AssistantChromeState = .normal
    @State private var isAssistantPresented = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            currentContent
        }
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .bottomTrailing) {
            if shouldShowActivityFAB {
                ActivityPortalButton(
                    state: activitySessionState,
                    elapsedSeconds: activityElapsedSeconds,
                    sport: activeLaunch?.intent?.sport
                ) {
                    presentActivity()
                }
                .padding(.trailing, 18)
                .padding(.bottom, activityButtonBottomPadding)
            }
        }
        .overlay(alignment: .bottom) {
            if !isActivityVisible {
                CompactTabSwitcher(
                    selectedTab: $selectedTab,
                    accentColor: assistantAccentColor
                )
                .offset(y: 10)
            }
        }
        .overlay(alignment: .bottom) {
            if shouldShowAssistantBar {
                AssistantBar(
                    hint: assistantHint,
                    accentColor: assistantAccentColor
                ) {
                    isAssistantPresented = true
                } onMinimize: {
                    withAnimation(.easeOut(duration: 0.18)) {
                        assistantChromeState = .minimized
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 52)
                .zIndex(2)
            }
        }
        .overlay(alignment: .bottom) {
            if shouldShowAssistantButton {
                AssistantMinimizedButton(accentColor: assistantAccentColor) {
                    withAnimation(.easeOut(duration: 0.18)) {
                        assistantChromeState = .normal
                    }
                }
                .padding(.bottom, 46)
                .zIndex(2)
            }
        }
        .overlay {
            if let launch = activeLaunch {
                RecordView(
                    initialIntent: launch.intent,
                    isVisible: isActivityVisible,
                    onCloseRequest: handleActivityClose,
                    onSessionStateChange: { activitySessionState = $0 },
                    onElapsedTimeChange: { activityElapsedSeconds = $0 }
                )
                .offset(y: isActivityVisible ? 0 : 1200)
                .allowsHitTesting(isActivityVisible)
                .animation(.spring(response: 0.34, dampingFraction: 0.92), value: isActivityVisible)
                .zIndex(1)
            }
        }
        .sheet(isPresented: $isAssistantPresented) {
            AssistantView(
                screenName: selectedTab == .me ? "Me" : "Social",
                isRecordingActive: false
            )
            .presentationDetents([.fraction(0.58), .large])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: appNavigationStore.pendingAssistantTarget) { _, target in
            guard target != nil else { return }
            selectedTab = .me
            assistantChromeState = .normal
            if isActivityVisible {
                isActivityVisible = false
            }
        }
    }

    @ViewBuilder
    private var currentContent: some View {
        Group {
            switch selectedTab {
            case .me:
                ProfileView(
                    onStartSuggestion: { suggestion in
                        presentActivity(intent: suggestion.intent)
                    }
                )
            case .social:
                ActivityFeedView()
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height),
                          abs(value.translation.width) > 60 else { return }

                    withAnimation(.easeOut(duration: 0.2)) {
                        if value.translation.width < 0 {
                            selectedTab = selectedTab.next
                        } else {
                            selectedTab = selectedTab.previous
                        }
                    }
                }
        )
    }

    private var shouldShowActivityFAB: Bool {
        !isActivityVisible
    }

    private var shouldShowAssistantBar: Bool {
        !isActivityVisible && assistantChromeState == .normal
    }

    private var shouldShowAssistantButton: Bool {
        !isActivityVisible && assistantChromeState == .minimized
    }

    private var activityButtonBottomPadding: CGFloat {
        if shouldShowAssistantBar { return 154 }
        if shouldShowAssistantButton { return 112 }
        return 82
    }

    private var assistantHint: String {
        if activitySessionState != .idle {
            return "Your session is still live. Need help deciding what to do next?"
        }

        switch selectedTab {
        case .me:
            return "Want a simple plan for today?"
        case .social:
            return "Find the right social loop."
        }
    }

    private var assistantAccentColor: Color {
        switch coachCatalog.selectedPersona.face.colorName {
        case "orange": .orange
        case "pink": .pink
        case "green": .green
        case "blue": .blue
        case "cyan": .cyan
        case "yellow": .yellow
        case "red": .red
        case "gray": .gray
        default: .orange
        }
    }

    private func presentActivity(intent: SessionIntent? = nil) {
        if let activeLaunch, activitySessionState != .idle {
            self.activeLaunch = activeLaunch
            isActivityVisible = true
            return
        }

        activeLaunch = RecordLaunch(intent: intent)
        activitySessionState = .idle
        activityElapsedSeconds = 0
        isActivityVisible = true
    }

    private func handleActivityClose(shouldKeepAlive: Bool) {
        if shouldKeepAlive {
            isActivityVisible = false
        } else {
            activeLaunch = nil
            activitySessionState = .idle
            activityElapsedSeconds = 0
            isActivityVisible = false
        }
    }
}

private enum AssistantChromeState {
    case minimized
    case normal
}

private enum AppTab {
    case me
    case social

    var title: String {
        switch self {
        case .me: return "Me"
        case .social: return "Social"
        }
    }

    var systemImage: String {
        switch self {
        case .me: return "person.fill"
        case .social: return "person.2.fill"
        }
    }

    var next: AppTab {
        switch self {
        case .me: return .social
        case .social: return .social
        }
    }

    var previous: AppTab {
        switch self {
        case .me: return .me
        case .social: return .me
        }
    }
}

private struct AssistantBar: View {
    let hint: String
    let accentColor: Color
    let onExpand: () -> Void
    let onMinimize: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onExpand) {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(accentColor)
                        .frame(width: 24, height: 24)

                    Text(hint)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            Button(action: onMinimize) {
                Image(systemName: "minus.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }
}

private struct AssistantMinimizedButton: View {
    let accentColor: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "sparkles")
                .font(.headline.weight(.bold))
                .foregroundStyle(accentColor)
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }
}

private struct CompactTabSwitcher: View {
    @Binding var selectedTab: AppTab
    let accentColor: Color

    var body: some View {
        HStack(spacing: 8) {
            tabButton(.me)
            tabButton(.social)
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.systemImage)
                    .font(.caption.weight(.semibold))
                Text(tab.title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(selectedTab == tab ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                Capsule()
                    .fill(selectedTab == tab ? AnyShapeStyle(accentColor) : AnyShapeStyle(Color.clear))
            }
        }
        .buttonStyle(.plain)
    }
}

private struct RecordLaunch: Identifiable {
    let id = UUID()
    let intent: SessionIntent?
}

enum ActivitySessionPortalState {
    case idle
    case active
    case paused

    init(recordingState: RecordingState) {
        switch recordingState {
        case .idle:
            self = .idle
        case .active:
            self = .active
        case .paused:
            self = .paused
        }
    }
}

enum MotivationPhase {
    case firstSession
    case steady
    case comeback
    case momentum
    case completedToday
}

struct CoachSpark: Equatable {
    let headline: String
    let message: String
    let primaryCTA: String
    let secondaryCTA: String?
}

struct SuggestedSession: Identifiable, Codable, Hashable {
    let id: String
    let sport: SportType
    let title: String
    let durationLabel: String
    let activityLabel: String
    let framing: String
    let coachLine: String
    let startLabel: String

    var intent: SessionIntent {
        SessionIntent(
            id: id,
            sport: sport,
            title: title,
            detail: "\(durationLabel) • \(activityLabel)",
            coachLine: coachLine,
            startLabel: startLabel
        )
    }
}

struct SessionIntent: Identifiable, Hashable {
    let id: String
    let sport: SportType
    let title: String
    let detail: String
    let coachLine: String
    let startLabel: String

    var systemImage: String { sport.systemImage }

    static let freestyleRun = SessionIntent(
        id: "freestyle-run",
        sport: .run,
        title: "Freestyle run",
        detail: "Run • no preset target",
        coachLine: "No pressure. Just start where you are.",
        startLabel: "Start now"
    )
}

struct MomentumNote: Identifiable, Hashable {
    let id: String
    let text: String
    let symbol: String
}

struct FinishReflection: Equatable {
    let title: String
    let body: String
    let highlight: String
    let progressNote: String?
}

struct DailyMotivationSnapshot {
    let phase: MotivationPhase
    let spark: CoachSpark
    let suggestions: [SuggestedSession]
    let momentumNotes: [MomentumNote]
}

struct MotivationDashboardView: View {
    @EnvironmentObject private var activityStore: ActivityStore
    @EnvironmentObject private var coachCatalog: CoachCatalogStore
    @EnvironmentObject private var checkInStore: DailyCheckInStore
    @EnvironmentObject private var trainingPlanStore: TrainingPlanStore
    @EnvironmentObject private var recognitionStore: RecognitionStore

    let onStartSuggestion: (SuggestedSession) -> Void
    @State private var isPlanDetailsPresented = false
    @State private var isPlanPickerPresented = false
    @State private var selectedRecommendation: TrainingPlanRecommendation?

    private var snapshot: DailyMotivationSnapshot {
        DailyMotivationEngine.makeSnapshot(
            activities: activityStore.activities,
            readiness: checkInStore.readiness,
            persona: coachCatalog.selectedPersona
        )
    }

    private var momentumNotes: [MomentumNote] {
        var notes: [MomentumNote] = []
        if let week = trainingPlanStore.currentWeek {
            notes.append(
                MomentumNote(
                    id: "plan-week-progress",
                    text: week.summaryLine,
                    symbol: "calendar.badge.clock"
                )
            )
        }
        notes.append(contentsOf: snapshot.momentumNotes)
        return Array(notes.prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            sparkCard
            nowCard
            if !momentumNotes.isEmpty {
                momentumStrip
            }
        }
        .onAppear {
            checkInStore.refresh()
            trainingPlanStore.refresh(
                activities: activityStore.activities,
                readiness: checkInStore.readiness,
                phase: snapshot.phase
            )
        }
        .onChange(of: activityStore.activities) { _, activities in
            trainingPlanStore.refresh(
                activities: activities,
                readiness: checkInStore.readiness,
                phase: snapshot.phase
            )
        }
        .onChange(of: checkInStore.readiness) { _, readiness in
            trainingPlanStore.refresh(
                activities: activityStore.activities,
                readiness: readiness,
                phase: snapshot.phase
            )
        }
        .sheet(isPresented: $isPlanDetailsPresented) {
            if let activePlan = trainingPlanStore.activePlan,
               let week = trainingPlanStore.currentWeek,
               let todaySuggestion = trainingPlanStore.todaySuggestion {
                NavigationStack {
                    ActiveTrainingPlanDetailView(
                        activePlan: activePlan,
                        week: week,
                        todaySuggestion: todaySuggestion,
                        accentColor: coachCatalog.selectedPersona.face.accentColor
                    )
                }
            }
        }
        .sheet(item: $selectedRecommendation) { recommendation in
            NavigationStack {
                TrainingPlanRecommendationDetailView(
                    recommendation: recommendation,
                    accentColor: coachCatalog.selectedPersona.face.accentColor
                ) {
                    trainingPlanStore.acceptRecommendation(recommendation)
                    selectedRecommendation = nil
                } onMorePlans: {
                    selectedRecommendation = nil
                    isPlanPickerPresented = true
                }
            }
        }
        .sheet(isPresented: $isPlanPickerPresented) {
            NavigationStack {
                TrainingPlanPickerView(
                    recommendations: trainingPlanStore.recommendations,
                    accentColor: coachCatalog.selectedPersona.face.accentColor,
                    onSelectPlan: { recommendation in
                        selectedRecommendation = recommendation
                    },
                    onUsePlan: { recommendation in
                        trainingPlanStore.acceptRecommendation(recommendation)
                        isPlanPickerPresented = false
                    }
                )
            }
        }
    }

    private var sparkCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                coachBadge

                VStack(alignment: .leading, spacing: 8) {
                    Text(snapshot.spark.headline)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(snapshot.spark.message)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)

                    if let highlight = recognitionStore.todayHighlight {
                        HStack(spacing: 8) {
                            Image(systemName: highlight.symbolName)
                                .font(.caption.weight(.bold))
                            Text("Coach noticed: \(highlight.title)")
                                .font(.caption.weight(.semibold))
                                .lineLimit(2)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.16), in: Capsule())
                    }
                }
            }

        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    coachCatalog.selectedPersona.face.accentColor.opacity(0.95),
                    .black.opacity(0.85)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    @ViewBuilder
    private var nowCard: some View {
        if let activePlan = trainingPlanStore.activePlan,
           let week = trainingPlanStore.currentWeek,
           let todaySuggestion = trainingPlanStore.todaySuggestion {
            activePlanNowCard(activePlan: activePlan, week: week, todaySuggestion: todaySuggestion)
        } else if let primarySuggestion = snapshot.suggestions.first {
            coachNowCard(primarySuggestion: primarySuggestion)
        }
    }

    private var coachBadge: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.18))
                .frame(width: 68, height: 68)
            Image(systemName: coachCatalog.selectedPersona.face.symbolName)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
        }
        .overlay(alignment: .bottomTrailing) {
            if let milestone = recognitionStore.importantMilestoneHighlight {
                RecognitionOrb(preview: milestone, size: 24)
                    .offset(x: 4, y: 4)
            }
        }
    }

    private func activePlanNowCard(
        activePlan: ActiveTrainingPlan,
        week: TrainingPlanWeekSnapshot,
        todaySuggestion: TodayTrainingSuggestion
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Now")
                        .font(.headline)
                    Text(todaySuggestion.title)
                        .font(.title3.weight(.bold))
                    Text(activePlan.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(coachCatalog.selectedPersona.face.accentColor)
                }

                Spacer()

                Text("Week \(week.currentWeekIndex)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(.systemBackground), in: Capsule())
            }

            Text(todaySuggestion.detail)
                .font(.subheadline.weight(.semibold))

            Text(todaySuggestion.coachLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let adjustmentLine = todaySuggestion.adjustmentLine {
                Label(adjustmentLine, systemImage: "heart.text.square.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(coachCatalog.selectedPersona.face.accentColor)
            } else if let entry = checkInStore.todayEntry {
                Label(entry.readiness.summaryLabel, systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(coachCatalog.selectedPersona.face.accentColor)
            }

            HStack(spacing: 10) {
                Button("Start now") {
                    onStartSuggestion(todaySuggestion.suggestedSession)
                }
                .buttonStyle(.borderedProminent)
                .tint(coachCatalog.selectedPersona.face.accentColor)

                Menu {
                    Button("Details") {
                        isPlanDetailsPresented = true
                    }

                    if !trainingPlanStore.recommendations.isEmpty {
                        Button("Change") {
                            isPlanPickerPresented = true
                        }
                    }

                    Button("End", role: .destructive) {
                        trainingPlanStore.clearActivePlan()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .foregroundStyle(coachCatalog.selectedPersona.face.accentColor)
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func coachNowCard(primarySuggestion: SuggestedSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Now")
                .font(.headline)

            Text(primarySuggestion.title)
                .font(.title3.weight(.bold))

            Text(nowReason(for: primarySuggestion))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(coachCatalog.selectedPersona.face.accentColor)

            Text(primarySuggestion.coachLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            readinessRow

            HStack(spacing: 10) {
                Button(primarySuggestion.startLabel) {
                    onStartSuggestion(primarySuggestion)
                }
                .buttonStyle(.borderedProminent)
                .tint(coachCatalog.selectedPersona.face.accentColor)

                if let alternateSuggestion = snapshot.suggestions.dropFirst().first {
                    Button(alternateSuggestion.title) {
                        onStartSuggestion(alternateSuggestion)
                    }
                    .buttonStyle(.bordered)
                    .tint(coachCatalog.selectedPersona.face.accentColor)
                } else if let recommendation = trainingPlanStore.recommendations.first {
                    Button("Build a plan") {
                        trainingPlanStore.acceptRecommendation(recommendation)
                    }
                    .buttonStyle(.bordered)
                    .tint(coachCatalog.selectedPersona.face.accentColor)
                }
            }
            .font(.subheadline.weight(.semibold))

            if let recommendation = trainingPlanStore.recommendations.first {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Want more structure?")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(recommendation.template.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(recommendation.rationale)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 0)

                        HStack(spacing: 8) {
                            Button("View") {
                                selectedRecommendation = recommendation
                            }
                            .buttonStyle(.bordered)
                            .tint(coachCatalog.selectedPersona.face.accentColor)
                            .font(.caption.weight(.semibold))

                            Button("More plans") {
                                isPlanPickerPresented = true
                            }
                            .buttonStyle(.bordered)
                            .tint(coachCatalog.selectedPersona.face.accentColor)
                            .font(.caption.weight(.semibold))
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private var readinessRow: some View {
        if let entry = checkInStore.todayEntry {
            Label(entry.readiness.summaryLabel, systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(coachCatalog.selectedPersona.face.accentColor)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                ForEach(DailyReadiness.allCases) { readiness in
                    Button {
                        checkInStore.select(readiness)
                    } label: {
                        Text(readiness.rawValue)
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                }
            }
        }
    }

    private func nowReason(for suggestion: SuggestedSession) -> String {
        if let entry = checkInStore.todayEntry {
            return "\(suggestion.durationLabel) • tuned for \(entry.readiness.summaryLabel.lowercased())"
        }

        return "\(suggestion.durationLabel) • \(suggestion.activityLabel)"
    }

    private var momentumStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Momentum")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(momentumNotes) { note in
                        HStack(spacing: 8) {
                            Image(systemName: note.symbol)
                                .foregroundStyle(coachCatalog.selectedPersona.face.accentColor)
                            Text(note.text)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(2)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(Capsule())
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct ActivityPortalButton: View {
    let state: ActivitySessionPortalState
    let elapsedSeconds: Int
    let sport: SportType?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: iconName)
                        .font(.headline.weight(.bold))

                    if state != .idle {
                        Circle()
                            .fill(state == .paused ? Color.yellow : Color.red)
                            .frame(width: 10, height: 10)
                            .offset(x: 2, y: -2)
                    }
                }

                Text(title)
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 56)
            .background(backgroundStyle, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var title: String {
        switch state {
        case .idle:
            return "Start"
        case .active:
            return elapsedSeconds.formatted()
        case .paused:
            return elapsedSeconds > 0 ? elapsedSeconds.formatted() : "Paused"
        }
    }

    private var iconName: String {
        sport?.systemImage ?? "figure.run"
    }

    private var backgroundStyle: LinearGradient {
        switch state {
        case .idle:
            return LinearGradient(colors: [Color.orange, Color(red: 0.93, green: 0.43, blue: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .active:
            return LinearGradient(colors: [Color(red: 1.0, green: 0.39, blue: 0.26), Color(red: 0.89, green: 0.18, blue: 0.23)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .paused:
            return LinearGradient(colors: [Color(red: 0.98, green: 0.74, blue: 0.20), Color(red: 0.88, green: 0.57, blue: 0.14)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .idle:
            return "Start freestyle"
        case .active:
            return "Return to live \(sport?.displayName.lowercased() ?? "activity"), \(elapsedSeconds.formatted()) elapsed"
        case .paused:
            return "Return to paused \(sport?.displayName.lowercased() ?? "activity"), \(elapsedSeconds.formatted()) elapsed"
        }
    }
}

private struct SuggestedActionCard: View {
    let suggestion: SuggestedSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestion.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("\(suggestion.durationLabel) • \(suggestion.activityLabel)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
            }

            Text("“\(suggestion.framing)”")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct RecentActivityRow: View {
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    let activity: SavedActivity

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.orange.opacity(0.12))
                .frame(width: 54, height: 54)
                .overlay {
                    Image(systemName: "figure.run")
                        .foregroundStyle(.orange)
                }

            VStack(alignment: .leading, spacing: 5) {
                Text(activity.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(activity.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(measurementPreferences.unitSystem.distanceString(meters: activity.distanceM)) • \(activity.durationSecs.formatted())")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

enum DailyMotivationEngine {
    static func makeSnapshot(
        activities: [SavedActivity],
        readiness: DailyReadiness?,
        persona: CoachPersona,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DailyMotivationSnapshot {
        let phase = determinePhase(activities: activities, now: now, calendar: calendar)
        return DailyMotivationSnapshot(
            phase: phase,
            spark: makeSpark(phase: phase, readiness: readiness, persona: persona),
            suggestions: makeSuggestions(phase: phase, readiness: readiness, persona: persona),
            momentumNotes: makeMomentumNotes(activities: activities, phase: phase, now: now, calendar: calendar)
        )
    }

    static func finishReflection(
        summary: ActivitySummary,
        priorActivities: [SavedActivity],
        readiness: DailyReadiness?,
        intent: SessionIntent?,
        goalProgress: GoalProgressSnapshot?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> FinishReflection {
        let weekCount = activitiesThisWeek(activities: priorActivities, now: now, calendar: calendar) + 1
        let highlight = "\(summary.durationSecs.formatted()) completed"
        let progressNote = goalProgress?.coachLine

        if wasComeback(priorActivities: priorActivities, now: now, calendar: calendar) {
            return FinishReflection(
                title: "Fresh start secured.",
                body: "You came back without making it dramatic. That is how rhythm returns.",
                highlight: highlight,
                progressNote: progressNote
            )
        }

        switch readiness {
        case .lowEnergy:
            return FinishReflection(
                title: "Nice work.",
                body: "You showed up on a low-energy day. That matters more than making it perfect.",
                highlight: highlight,
                progressNote: progressNote
            )
        case .stressed:
            return FinishReflection(
                title: "Good reset.",
                body: "You gave a busy day somewhere to land. That still counts as real work.",
                highlight: highlight,
                progressNote: progressNote
            )
        default:
            break
        }

        if let intent, intent.id.contains("reset") || summary.durationSecs <= 10 * 60 {
            return FinishReflection(
                title: "Promise kept.",
                body: "You kept the session small and still followed through. Short sessions still count.",
                highlight: highlight,
                progressNote: progressNote
            )
        }

        if weekCount >= 2 {
            return FinishReflection(
                title: "Session logged.",
                body: "That is \(weekCount) activities this week. You are building consistency.",
                highlight: highlight,
                progressNote: progressNote
            )
        }

        return FinishReflection(
            title: "Nice work.",
            body: "You showed up and made the day real. Keep that feeling simple.",
            highlight: highlight,
            progressNote: progressNote
        )
    }

    static func phase(
        for activities: [SavedActivity],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> MotivationPhase {
        determinePhase(activities: activities, now: now, calendar: calendar)
    }

    private static func determinePhase(
        activities: [SavedActivity],
        now: Date,
        calendar: Calendar
    ) -> MotivationPhase {
        guard let latest = activities.first else { return .firstSession }
        if calendar.isDateInToday(latest.startedAt) {
            return .completedToday
        }
        if daysSince(date: latest.startedAt, now: now, calendar: calendar) >= 2 {
            return .comeback
        }
        if activitiesThisWeek(activities: activities, now: now, calendar: calendar) >= 3 {
            return .momentum
        }
        return .steady
    }

    private static func makeSpark(
        phase: MotivationPhase,
        readiness: DailyReadiness?,
        persona: CoachPersona
    ) -> CoachSpark {
        switch phase {
        case .completedToday:
            return CoachSpark(
                headline: "Session logged.",
                message: "Coach \(coachFirstName(from: persona)) sees the follow-through. Let that win be enough for today.",
                primaryCTA: "Start another light session",
                secondaryCTA: "Review today"
            )
        case .comeback:
            return CoachSpark(
                headline: "Fresh start today?",
                message: "No catching up. Just reconnect with something small and real.",
                primaryCTA: "Start easy",
                secondaryCTA: "Other ideas"
            )
        case .momentum:
            return CoachSpark(
                headline: "You are building something steady.",
                message: readiness == .ready
                    ? "Energy is there today. Keep the rhythm going without forcing it."
                    : "Protect the rhythm with a session you can actually enjoy.",
                primaryCTA: "Keep the rhythm going",
                secondaryCTA: "Other ideas"
            )
        case .firstSession:
            return CoachSpark(
                headline: "You do not need a perfect session.",
                message: "You need a beginning. Coach \(coachFirstName(from: persona)) can take it from there.",
                primaryCTA: "Start a first session",
                secondaryCTA: "Other ideas"
            )
        case .steady:
            return CoachSpark(
                headline: defaultHeadline(for: readiness),
                message: defaultMessage(for: readiness),
                primaryCTA: "Pick a simple session",
                secondaryCTA: "Other ideas"
            )
        }
    }

    private static func makeSuggestions(
        phase: MotivationPhase,
        readiness: DailyReadiness?,
        persona: CoachPersona
    ) -> [SuggestedSession] {
        let sportLabel = persona.template.sport == .bike ? "ride" : "session"

        switch phase {
        case .completedToday:
            return [
                SuggestedSession(
                    id: "recovery-reset",
                    sport: persona.template.sport,
                    title: "5 min reset",
                    durationLabel: "5 min",
                    activityLabel: "recovery \(sportLabel)",
                    framing: "Keep it tiny. Stay loose.",
                    coachLine: "This one is only about easing back into yourself.",
                    startLabel: "Start reset"
                ),
                SuggestedSession(
                    id: "fresh-air-loop",
                    sport: persona.template.sport,
                    title: "Fresh air loop",
                    durationLabel: "10 min",
                    activityLabel: "easy \(sportLabel)",
                    framing: "Move lightly and clear the head.",
                    coachLine: "No pressure here. Just a clean little reset if you want one.",
                    startLabel: "Start easy loop"
                )
            ]
        case .comeback:
            return [
                SuggestedSession(
                    id: "comeback-walk",
                    sport: .run,
                    title: "Fresh start",
                    durationLabel: "5 min",
                    activityLabel: "walk or jog",
                    framing: "No pressure. Just get outside.",
                    coachLine: "Today is not about catching up. Just reconnect.",
                    startLabel: "Start fresh"
                ),
                SuggestedSession(
                    id: "easy-return",
                    sport: persona.template.sport,
                    title: "10 min easy session",
                    durationLabel: "10 min",
                    activityLabel: sportLabel,
                    framing: "Keep it friendly from the first minute.",
                    coachLine: "Keep this one light. Today is about showing up.",
                    startLabel: "Start easy session"
                ),
                SuggestedSession(
                    id: "photo-shakeout",
                    sport: persona.template.sport,
                    title: "Shakeout + photo",
                    durationLabel: "12 min",
                    activityLabel: sportLabel,
                    framing: "Move a little and notice something worth capturing.",
                    coachLine: "Let the session stay playful. Motion first, photos second.",
                    startLabel: "Start shakeout"
                )
            ]
        case .momentum:
            return [
                SuggestedSession(
                    id: "steady-build",
                    sport: persona.template.sport,
                    title: "15 min easy build",
                    durationLabel: "15 min",
                    activityLabel: sportLabel,
                    framing: "Stay smooth, then lift a touch late.",
                    coachLine: "You have rhythm right now. Keep it relaxed and connected.",
                    startLabel: "Start easy build"
                ),
                SuggestedSession(
                    id: "repeat-vibe",
                    sport: persona.template.sport,
                    title: "Repeat yesterday's vibe",
                    durationLabel: "12 min",
                    activityLabel: sportLabel,
                    framing: "Keep the same low-drama consistency.",
                    coachLine: "No need to impress yourself today. Just keep the pattern alive.",
                    startLabel: "Start repeat session"
                ),
                SuggestedSession(
                    id: "confidence-lap",
                    sport: persona.template.sport,
                    title: "Confidence lap",
                    durationLabel: "8 min",
                    activityLabel: "smooth \(sportLabel)",
                    framing: "A short win keeps momentum honest.",
                    coachLine: "This is just enough to remind your body what steady feels like.",
                    startLabel: "Start confidence lap"
                )
            ]
        case .firstSession, .steady:
            let firstTitle = readiness == .lowEnergy || readiness == .stressed ? "5 min reset" : "10 min easy session"
            let firstDuration = readiness == .lowEnergy || readiness == .stressed ? "5 min" : "10 min"
            return [
                SuggestedSession(
                    id: "daily-reset",
                    sport: persona.template.sport,
                    title: firstTitle,
                    durationLabel: firstDuration,
                    activityLabel: sportLabel,
                    framing: "Just loosen up and move.",
                    coachLine: "This only needs to be simple. Begin, then let the session become itself.",
                    startLabel: "Start now"
                ),
                SuggestedSession(
                    id: "fresh-air",
                    sport: .run,
                    title: "Fresh air walk",
                    durationLabel: "10 min",
                    activityLabel: "walk",
                    framing: "Take the pressure off and get outside.",
                    coachLine: "If today feels crowded, make space with an easy walk first.",
                    startLabel: "Start walk"
                ),
                SuggestedSession(
                    id: "photo-reset",
                    sport: persona.template.sport,
                    title: "Shakeout + photo",
                    durationLabel: "12 min",
                    activityLabel: sportLabel,
                    framing: "Move lightly and catch one good moment.",
                    coachLine: "Stay easy and curious. Let this one feel alive, not optimized.",
                    startLabel: "Start shakeout"
                )
            ]
        }
    }

    private static func makeMomentumNotes(
        activities: [SavedActivity],
        phase: MotivationPhase,
        now: Date,
        calendar: Calendar
    ) -> [MomentumNote] {
        var notes: [MomentumNote] = []
        let weekCount = activitiesThisWeek(activities: activities, now: now, calendar: calendar)

        switch phase {
        case .momentum:
            notes.append(MomentumNote(id: "rhythm", text: "You are building rhythm", symbol: "waveform.path.ecg"))
        case .comeback:
            notes.append(MomentumNote(id: "return", text: "Back after a rest window", symbol: "arrow.clockwise"))
        case .completedToday:
            notes.append(MomentumNote(id: "today", text: "You showed up today", symbol: "checkmark.circle.fill"))
        default:
            break
        }

        if weekCount > 0 {
            notes.append(MomentumNote(
                id: "week-count",
                text: "\(weekCount) activit\(weekCount == 1 ? "y" : "ies") this week",
                symbol: "calendar"
            ))
        }

        if let latest = activities.first, latest.durationSecs <= 15 * 60 {
            notes.append(MomentumNote(id: "short-counts", text: "Short sessions still count", symbol: "bolt.heart"))
        }

        if notes.isEmpty {
            notes.append(MomentumNote(id: "steady", text: "Keep the day simple", symbol: "sun.max"))
        }

        return Array(notes.prefix(3))
    }

    private static func defaultHeadline(for readiness: DailyReadiness?) -> String {
        switch readiness {
        case .lowEnergy:
            "Keep it light today."
        case .ready:
            "Good day to get in motion."
        case .stressed:
            "A short reset is enough."
        default:
            "You do not need a big day."
        }
    }

    private static func defaultMessage(for readiness: DailyReadiness?) -> String {
        switch readiness {
        case .lowEnergy:
            "A small session still moves the day forward."
        case .ready:
            "Use the energy, but keep the effort clean."
        case .stressed:
            "No heroics. Just give your head and body somewhere to settle."
        default:
            "You need a real one. Something small still counts."
        }
    }

    private static func activitiesThisWeek(
        activities: [SavedActivity],
        now: Date,
        calendar: Calendar
    ) -> Int {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        return activities.filter { week.contains($0.startedAt) }.count
    }

    private static func daysSince(
        date: Date,
        now: Date,
        calendar: Calendar
    ) -> Int {
        let start = calendar.startOfDay(for: date)
        let end = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    private static func wasComeback(
        priorActivities: [SavedActivity],
        now: Date,
        calendar: Calendar
    ) -> Bool {
        guard let latest = priorActivities.first else { return false }
        return daysSince(date: latest.startedAt, now: now, calendar: calendar) >= 2
    }

    private static func coachFirstName(from persona: CoachPersona) -> String {
        persona.template.displayName.split(separator: " ").first.map(String.init) ?? "your coach"
    }
}

private extension CoachFace {
    var accentColor: Color {
        switch colorName {
        case "orange": .orange
        case "pink": .pink
        case "green": .green
        case "blue": .blue
        case "cyan": .cyan
        case "yellow": .yellow
        case "red": .red
        case "gray": .gray
        default: .orange
        }
    }
}

struct TrainingPlanCard: View {
    @EnvironmentObject private var trainingPlanStore: TrainingPlanStore
    @State private var selectedRecommendation: TrainingPlanRecommendation?
    @State private var isMorePlansPresented = false
    @State private var isActivePlanDetailsPresented = false

    let accentColor: Color
    let onStartSuggestion: (SuggestedSession) -> Void

    var body: some View {
        Group {
            if let activePlan = trainingPlanStore.activePlan,
               let week = trainingPlanStore.currentWeek,
               let todaySuggestion = trainingPlanStore.todaySuggestion {
                activePlanCard(activePlan: activePlan, week: week, todaySuggestion: todaySuggestion)
            } else if trainingPlanStore.shouldShowRecommendations {
                recommendationCard
            }
        }
        .sheet(item: $selectedRecommendation) { recommendation in
            NavigationStack {
                TrainingPlanRecommendationDetailView(
                    recommendation: recommendation,
                    accentColor: accentColor
                ) {
                    trainingPlanStore.acceptRecommendation(recommendation)
                    selectedRecommendation = nil
                } onMorePlans: {
                    selectedRecommendation = nil
                    isMorePlansPresented = true
                }
            }
        }
        .sheet(isPresented: $isMorePlansPresented) {
            NavigationStack {
                TrainingPlanPickerView(
                    recommendations: trainingPlanStore.recommendations,
                    accentColor: accentColor,
                    onSelectPlan: { recommendation in
                        selectedRecommendation = recommendation
                    },
                    onUsePlan: { recommendation in
                        trainingPlanStore.acceptRecommendation(recommendation)
                        isMorePlansPresented = false
                    }
                )
            }
        }
        .sheet(isPresented: $isActivePlanDetailsPresented) {
            if let activePlan = trainingPlanStore.activePlan,
               let week = trainingPlanStore.currentWeek,
               let todaySuggestion = trainingPlanStore.todaySuggestion {
                NavigationStack {
                    ActiveTrainingPlanDetailView(
                        activePlan: activePlan,
                        week: week,
                        todaySuggestion: todaySuggestion,
                        accentColor: accentColor
                    )
                }
            }
        }
    }

    private func activePlanCard(
        activePlan: ActiveTrainingPlan,
        week: TrainingPlanWeekSnapshot,
        todaySuggestion: TodayTrainingSuggestion
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Active plan")
                        .font(.headline)
                    Text(activePlan.title)
                        .font(.title3.weight(.bold))
                    Text("Week \(week.currentWeekIndex) of \(week.totalWeeks)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(accentColor)
                }

                Spacer()

                Image(systemName: activePlan.sport.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(accentColor)
            }

            Text(activePlan.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                Text(week.focus)
                    .font(.headline)
                Text(week.summaryLine)
                    .font(.subheadline.weight(.semibold))
                Text(week.weekSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TrainingPlanProgressBar(progress: week.progressPercent, accentColor: accentColor)
                Text(week.coachLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Today's plan")
                    .font(.subheadline.weight(.semibold))
                Text(todaySuggestion.title)
                    .font(.headline)
                Text(todaySuggestion.detail)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor)
                Text(todaySuggestion.coachLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let adjustmentLine = todaySuggestion.adjustmentLine {
                    Label(adjustmentLine, systemImage: "heart.text.square.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accentColor)
                }

                if let firstStep = todaySuggestion.stepSummary.first {
                    Text(firstStep)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                Button("Start today's session") {
                    onStartSuggestion(todaySuggestion.suggestedSession)
                }
                .buttonStyle(.borderedProminent)
                .tint(accentColor)

                Button("Details") {
                    isActivePlanDetailsPresented = true
                }
                .buttonStyle(.bordered)
                .tint(accentColor)

                Button("End plan") {
                    trainingPlanStore.clearActivePlan()
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

    private var recommendationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Coach plan picks")
                .font(.headline)

            if let lead = trainingPlanStore.recommendations.first {
                VStack(alignment: .leading, spacing: 10) {
                    Text(lead.template.title)
                        .font(.title3.weight(.bold))
                    Text(lead.template.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        planPill("\(lead.durationWeeks) weeks")
                        planPill("\(lead.sessionsPerWeek)x / week")
                        planPill("\(lead.targetWeeklyMinutes) min")
                    }

                    if let source = lead.template.source {
                        Text("Imported cues: \(source.name)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(accentColor)
                    }

                    Text(lead.rationale)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let openingWeek = lead.template.weeks.first {
                        Text("Starts with: \(openingWeek.summary)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(lead.tradeoff)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    Button("Use this plan") {
                        trainingPlanStore.acceptRecommendation(lead)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accentColor)

                    Button("More plans") {
                        isMorePlansPresented = true
                    }
                    .buttonStyle(.bordered)
                    .tint(accentColor)
                }
                .font(.subheadline.weight(.semibold))

                HStack(spacing: 10) {
                    Button("See details") {
                        selectedRecommendation = lead
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accentColor)

                    Spacer()

                    Button("Not now") {
                        trainingPlanStore.dismissRecommendations()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func planPill(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemBackground), in: Capsule())
    }
}

private struct TrainingPlanPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let recommendations: [TrainingPlanRecommendation]
    let accentColor: Color
    let onSelectPlan: (TrainingPlanRecommendation) -> Void
    let onUsePlan: (TrainingPlanRecommendation) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(recommendations) { recommendation in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(recommendation.template.title)
                            .font(.headline)

                        Text(recommendation.template.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 8) {
                            pill("\(recommendation.durationWeeks) weeks")
                            pill("\(recommendation.sessionsPerWeek)x / week")
                            pill("\(recommendation.targetWeeklyMinutes) min")
                        }

                        if let openingWeek = recommendation.template.weeks.first {
                            Text(openingWeek.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Text(recommendation.rationale)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 10) {
                            Button("Details") {
                                onSelectPlan(recommendation)
                            }
                            .buttonStyle(.bordered)
                            .tint(accentColor)

                            Button("Use plan") {
                                onUsePlan(recommendation)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(accentColor)
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            .padding()
        }
        .navigationTitle("More Plans")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemBackground), in: Capsule())
    }
}

private struct TrainingPlanRecommendationDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let recommendation: TrainingPlanRecommendation
    let accentColor: Color
    let onUsePlan: () -> Void
    let onMorePlans: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                statGrid
                if let source = recommendation.template.source {
                    section("Imported source", text: "\(source.attribution) • \(source.license)")
                    section("Import notes", text: source.importNotes)
                }
                section("Why this fits", text: recommendation.rationale)
                section("What to expect", text: recommendation.template.summary)
                section("Tradeoff", text: recommendation.tradeoff)
                highlightsSection
                weekPreviewSection
            }
            .padding()
        }
        .navigationTitle("Plan Details")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Button("More plans") {
                    dismiss()
                    onMorePlans()
                }
                .buttonStyle(.bordered)
                .tint(accentColor)

                Button("Use this plan") {
                    onUsePlan()
                }
                .buttonStyle(.borderedProminent)
                .tint(accentColor)
            }
            .font(.headline)
            .padding(.horizontal)
            .padding(.top, 10)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(recommendation.template.title)
                .font(.system(.title2, design: .rounded).weight(.bold))
            Text(recommendation.template.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            detailStat("Length", value: "\(recommendation.durationWeeks) weeks")
            detailStat("Weekly rhythm", value: "\(recommendation.sessionsPerWeek)x sessions")
            detailStat("Target time", value: "\(recommendation.targetWeeklyMinutes) min")
            detailStat("Long day", value: "\(recommendation.longSessionMinutes) min")
        }
    }

    private func detailStat(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func section(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var highlightsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Plan shape")
                .font(.headline)
            ForEach(recommendation.template.highlights, id: \.self) { highlight in
                Label(highlight, systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var weekPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Week Preview")
                .font(.headline)
            ForEach(recommendation.template.weeks.prefix(2)) { week in
                VStack(alignment: .leading, spacing: 8) {
                    Text("Week \(week.index): \(week.focus)")
                        .font(.subheadline.weight(.semibold))
                    Text(week.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(week.workouts.prefix(3)) { workout in
                        workoutPreviewRow(workout)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private func workoutPreviewRow(_ workout: TrainingPlanWorkout) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(workout.dayLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(accentColor)
                .frame(width: 32, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(workout.title)
                    .font(.subheadline.weight(.semibold))
                Text("\(workout.durationLabel) • \(workout.effortLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

private struct ActiveTrainingPlanDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let activePlan: ActiveTrainingPlan
    let week: TrainingPlanWeekSnapshot
    let todaySuggestion: TodayTrainingSuggestion
    let accentColor: Color

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(activePlan.title)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                    Text(activePlan.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    activeStat("Plan length", value: "\(activePlan.durationWeeks) weeks")
                    activeStat("Current week", value: "\(week.currentWeekIndex) of \(week.totalWeeks)")
                    activeStat("Weekly rhythm", value: "\(activePlan.sessionsPerWeek)x sessions")
                    activeStat("Target time", value: "\(activePlan.targetWeeklyMinutes) min")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("This week")
                        .font(.headline)
                    Text(week.focus)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(accentColor)
                    Text(week.summaryLine)
                        .font(.subheadline.weight(.semibold))
                    Text(week.weekSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    TrainingPlanProgressBar(progress: week.progressPercent, accentColor: accentColor)
                    Text(week.coachLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Today's recommendation")
                        .font(.headline)
                    Text(todaySuggestion.title)
                        .font(.title3.weight(.bold))
                    Text(todaySuggestion.detail)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accentColor)
                    Text(todaySuggestion.coachLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let adjustmentLine = todaySuggestion.adjustmentLine {
                        Label(adjustmentLine, systemImage: "heart.text.square.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(accentColor)
                    }

                    ForEach(todaySuggestion.stepSummary.prefix(4), id: \.self) { step in
                        Text(step)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(18)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Week schedule")
                        .font(.headline)
                    ForEach(week.scheduledWorkouts) { workout in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("\(workout.dayLabel) • \(workout.title)")
                                    .font(.subheadline.weight(.semibold))
                                if workout.isOptional {
                                    Spacer()
                                    Text("Optional")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text("\(workout.durationLabel) • \(workout.effortLabel)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(accentColor)
                            Text(workout.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 4)
                    }

                    ForEach(week.notes, id: \.self) { note in
                        Label(note, systemImage: "info.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(18)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .padding()
        }
        .navigationTitle("Plan Details")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }

    private func activeStat(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct TrainingPlanProgressBar: View {
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
