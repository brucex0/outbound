import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: AppTab = .today
    @State private var activeLaunch: RecordLaunch?

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView(
                onStartSuggestion: { suggestion in
                    activeLaunch = RecordLaunch(intent: suggestion.intent)
                },
                onStartFreestyle: {
                    activeLaunch = RecordLaunch(intent: .freestyleRun)
                }
            )
            .fullScreenCover(item: $activeLaunch, onDismiss: {
                activeLaunch = nil
            }) { launch in
                RecordView(initialIntent: launch.intent) {
                    activeLaunch = nil
                }
            }
            .tabItem { Label("Today", systemImage: "sun.max.fill") }
            .tag(AppTab.today)

            ActivityFeedView()
                .tabItem { Label("Social", systemImage: "person.2.fill") }
                .tag(AppTab.social)

            ProfileView()
                .tabItem { Label("Me", systemImage: "person.fill") }
                .tag(AppTab.me)
        }
        .tint(.orange)
    }
}

private enum AppTab {
    case today
    case social
    case me
}

private struct RecordLaunch: Identifiable {
    let id = UUID()
    let intent: SessionIntent
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

struct SuggestedSession: Identifiable, Hashable {
    let id: String
    let title: String
    let durationLabel: String
    let activityLabel: String
    let framing: String
    let coachLine: String
    let startLabel: String

    var intent: SessionIntent {
        SessionIntent(
            id: id,
            title: title,
            detail: "\(durationLabel) • \(activityLabel)",
            coachLine: coachLine,
            startLabel: startLabel
        )
    }
}

struct SessionIntent: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let coachLine: String
    let startLabel: String

    static let freestyleRun = SessionIntent(
        id: "freestyle-run",
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
}

struct DailyMotivationSnapshot {
    let phase: MotivationPhase
    let spark: CoachSpark
    let suggestions: [SuggestedSession]
    let momentumNotes: [MomentumNote]
}

struct TodayView: View {
    @EnvironmentObject private var activityStore: ActivityStore
    @EnvironmentObject private var coachCatalog: CoachCatalogStore
    @EnvironmentObject private var checkInStore: DailyCheckInStore

    let onStartSuggestion: (SuggestedSession) -> Void
    let onStartFreestyle: () -> Void

    private let recentPreviewLimit = 3

    private var snapshot: DailyMotivationSnapshot {
        DailyMotivationEngine.makeSnapshot(
            activities: activityStore.activities,
            readiness: checkInStore.readiness,
            persona: coachCatalog.selectedPersona
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sparkCard
                    readinessCard
                    suggestedActionsSection
                    momentumStrip
                    recentActivitySection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today")
            .onAppear {
                checkInStore.refresh()
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
                }
            }

            if let primarySuggestion = snapshot.suggestions.first {
                Button {
                    onStartSuggestion(primarySuggestion)
                } label: {
                    HStack {
                        Text(snapshot.spark.primaryCTA)
                            .font(.headline)
                        Spacer()
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title3)
                    }
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(.white.opacity(0.18), in: Capsule())
                }
                .foregroundStyle(.white)
            }

            Button(action: onStartFreestyle) {
                HStack {
                    Text("Start freestyle")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "figure.run")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(.white.opacity(0.10), in: Capsule())
            }
            .foregroundStyle(.white.opacity(0.92))
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

    private var coachBadge: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.18))
                .frame(width: 68, height: 68)
            Image(systemName: coachCatalog.selectedPersona.face.symbolName)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private var readinessCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How are you feeling today?")
                .font(.headline)

            if let entry = checkInStore.todayEntry {
                Label(entry.readiness.summaryLabel, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(coachCatalog.selectedPersona.face.accentColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground), in: Capsule())
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                    ForEach(DailyReadiness.allCases) { readiness in
                        Button {
                            checkInStore.select(readiness)
                        } label: {
                            Text(readiness.rawValue)
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var suggestedActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Suggested actions")
                .font(.headline)

            ForEach(snapshot.suggestions) { suggestion in
                Button {
                    onStartSuggestion(suggestion)
                } label: {
                    SuggestedActionCard(suggestion: suggestion)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var momentumStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Momentum")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(snapshot.momentumNotes) { note in
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

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent activity")
                .font(.headline)

            if activityStore.activities.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No activity yet.")
                        .font(.subheadline.weight(.semibold))
                    Text("Your coach will start reflecting on momentum here once you log a session.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                ForEach(Array(activityStore.activities.prefix(recentPreviewLimit))) { activity in
                    RecentActivityRow(activity: activity)
                }
            }
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
                Text("\(String(format: "%.2f km", activity.distanceM / 1000)) • \(activity.durationSecs.formatted())")
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
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> FinishReflection {
        let weekCount = activitiesThisWeek(activities: priorActivities, now: now, calendar: calendar) + 1
        let highlight = "\(summary.durationSecs.formatted()) completed"

        if wasComeback(priorActivities: priorActivities, now: now, calendar: calendar) {
            return FinishReflection(
                title: "Fresh start secured.",
                body: "You came back without making it dramatic. That is how rhythm returns.",
                highlight: highlight
            )
        }

        switch readiness {
        case .lowEnergy:
            return FinishReflection(
                title: "Nice work.",
                body: "You showed up on a low-energy day. That matters more than making it perfect.",
                highlight: highlight
            )
        case .stressed:
            return FinishReflection(
                title: "Good reset.",
                body: "You gave a busy day somewhere to land. That still counts as real work.",
                highlight: highlight
            )
        default:
            break
        }

        if let intent, intent.id.contains("reset") || summary.durationSecs <= 10 * 60 {
            return FinishReflection(
                title: "Promise kept.",
                body: "You kept the session small and still followed through. Short sessions still count.",
                highlight: highlight
            )
        }

        if weekCount >= 2 {
            return FinishReflection(
                title: "Session logged.",
                body: "That is \(weekCount) activities this week. You are building consistency.",
                highlight: highlight
            )
        }

        return FinishReflection(
            title: "Nice work.",
            body: "You showed up and made the day real. Keep that feeling simple.",
            highlight: highlight
        )
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
                    title: "5 min reset",
                    durationLabel: "5 min",
                    activityLabel: "recovery \(sportLabel)",
                    framing: "Keep it tiny. Stay loose.",
                    coachLine: "This one is only about easing back into yourself.",
                    startLabel: "Start reset"
                ),
                SuggestedSession(
                    id: "fresh-air-loop",
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
                    title: "Fresh start",
                    durationLabel: "5 min",
                    activityLabel: "walk or jog",
                    framing: "No pressure. Just get outside.",
                    coachLine: "Today is not about catching up. Just reconnect.",
                    startLabel: "Start fresh"
                ),
                SuggestedSession(
                    id: "easy-return",
                    title: "10 min easy session",
                    durationLabel: "10 min",
                    activityLabel: sportLabel,
                    framing: "Keep it friendly from the first minute.",
                    coachLine: "Keep this one light. Today is about showing up.",
                    startLabel: "Start easy session"
                ),
                SuggestedSession(
                    id: "photo-shakeout",
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
                    title: "15 min easy build",
                    durationLabel: "15 min",
                    activityLabel: sportLabel,
                    framing: "Stay smooth, then lift a touch late.",
                    coachLine: "You have rhythm right now. Keep it relaxed and connected.",
                    startLabel: "Start easy build"
                ),
                SuggestedSession(
                    id: "repeat-vibe",
                    title: "Repeat yesterday's vibe",
                    durationLabel: "12 min",
                    activityLabel: sportLabel,
                    framing: "Keep the same low-drama consistency.",
                    coachLine: "No need to impress yourself today. Just keep the pattern alive.",
                    startLabel: "Start repeat session"
                ),
                SuggestedSession(
                    id: "confidence-lap",
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
                    title: firstTitle,
                    durationLabel: firstDuration,
                    activityLabel: sportLabel,
                    framing: "Just loosen up and move.",
                    coachLine: "This only needs to be simple. Begin, then let the session become itself.",
                    startLabel: "Start now"
                ),
                SuggestedSession(
                    id: "fresh-air",
                    title: "Fresh air walk",
                    durationLabel: "10 min",
                    activityLabel: "walk",
                    framing: "Take the pressure off and get outside.",
                    coachLine: "If today feels crowded, make space with an easy walk first.",
                    startLabel: "Start walk"
                ),
                SuggestedSession(
                    id: "photo-reset",
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
