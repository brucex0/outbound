import SwiftUI

struct MainTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var assistantStore: AssistantStore
    @EnvironmentObject private var appNavigationStore: AppNavigationStore
    @EnvironmentObject private var guideCatalog: GuideCatalogStore
    @EnvironmentObject private var dailyCheckInStore: DailyCheckInStore
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    @EnvironmentObject private var personalizationStore: PersonalizationStore
    @EnvironmentObject private var trainingPlanStore: TrainingPlanStore
    @EnvironmentObject private var healthAuthorizationStore: HealthAuthorizationStore
    @EnvironmentObject private var healthImportStore: HealthImportStore
    @EnvironmentObject private var activityStore: ActivityStore
    @EnvironmentObject private var connectivityStore: ConnectivityStore
    @State private var activeLaunch: RecordLaunch?
    @State private var isActivityVisible = false
    @State private var activitySessionState: ActivitySessionPortalState = .idle
    @State private var activityElapsedSeconds = 0
    @State private var feedbackPage = "Today"
    @State private var selectedAppTab: SimplifiedAppTab = .today
    @State private var activityStartRequest = 0
    @State private var preActivityPhotoRequest = 0
    @State private var preActivityPhoto: UIImage?
    @State private var launchGoalMode: SessionGoalMode = .planned
    @State private var customizedTodayIntent: SessionIntent?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            currentContent
        }
        .background(Color(.systemGroupedBackground))
        .feedbackReporter(isShakeDisabled: activitySessionState != .idle, currentPage: feedbackPage)
        .overlay(alignment: .top) {
            if selectedAppTab != .today || !isActivityVisible {
                GlobalConnectivityBanner()
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: connectivityStore.isOffline)
        .animation(.easeInOut(duration: 0.22), value: activityStore.isSyncing)
        .fullScreenCover(isPresented: onboardingPresentation) {
            SimplifiedOnboardingFlow { profile in
                applyOnboardingProfile(profile)
            }
            .environmentObject(onboardingStore)
            .environmentObject(personalizationStore)
            .environmentObject(trainingPlanStore)
            .environmentObject(healthAuthorizationStore)
            .environmentObject(healthImportStore)
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $healthImportStore.isReviewPresented) {
            HealthWorkoutImportView()
                .environmentObject(activityStore)
                .environmentObject(healthImportStore)
                .environmentObject(measurementPreferences)
        }
        .onAppear {
            restoreInterruptedActivityIfNeeded()
            prepareOnboarding()
            consumeStoredPreparedActivityIfNeeded()
            prepareTodayLaunchIfNeeded()
        }
        .onChange(of: selectedAppTab) { _, tab in
            guard tab == .today, activitySessionState == .idle else { return }
            prepareTodayLaunchIfNeeded()
            isActivityVisible = true
        }
        .onChange(of: defaultTodayIntent) { previousIntent, intent in
            guard selectedAppTab == .today,
                  activitySessionState == .idle,
                  activeLaunch?.intent == nil || activeLaunch?.intent == previousIntent,
                  activeLaunch?.intent != intent
            else { return }
            activeLaunch = RecordLaunch(intent: intent)
            isActivityVisible = true
        }
        .onChange(of: onboardingIdentity) { _, _ in
            prepareOnboarding()
        }
        .onChange(of: onboardingStore.isPresented) { wasPresented, isPresented in
            guard wasPresented, !isPresented else { return }
            checkForHealthWorkouts(presentWhenFound: true)
        }
        .onChange(of: activityStore.hasLoadedActivities) { _, hasLoaded in
            guard hasLoaded, !onboardingStore.isPresented else { return }
            checkForHealthWorkouts(presentWhenFound: true)
        }
        .onChange(of: appNavigationStore.pendingAssistantTarget) { _, target in
            guard target != nil, activitySessionState == .idle else { return }
            if isActivityVisible {
                isActivityVisible = false
            }
        }
        .onChange(of: appNavigationStore.pendingActivityIntent) { _, intent in
            guard let intent else { return }
            presentActivity(intent: intent)
            appNavigationStore.consumePreparedActivity()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            consumeStoredPreparedActivityIfNeeded()
            if activityStore.hasLoadedActivities, !onboardingStore.isPresented {
                checkForHealthWorkouts(presentWhenFound: true)
            }
        }
        .onChange(of: connectivityStore.isOffline) { wasOffline, isOffline in
            guard wasOffline, !isOffline else { return }
            Task { await activityStore.syncPendingActivitiesIfNeeded() }
        }
    }

    private func checkForHealthWorkouts(presentWhenFound: Bool) {
        Task {
            await healthImportStore.checkForNewWorkouts(
                existingExternalIDs: activityStore.importedHealthExternalIDs,
                presentWhenFound: presentWhenFound
            )
        }
    }

    private var onboardingIdentity: String {
        authStore.user?.id ?? authStore.localSessionLabel ?? "local"
    }

    private var onboardingPresentation: Binding<Bool> {
        Binding(
            get: {
                let isAppTestMode = (Bundle.main.object(forInfoDictionaryKey: "OutboundAppTestMode") as? String) == "YES"
                return onboardingStore.isPresented && !isAppTestMode
            },
            set: { onboardingStore.isPresented = $0 }
        )
    }

    @ViewBuilder
    private var currentContent: some View {
        SimplifiedAppShell(
            selection: $selectedAppTab,
            activitySessionState: activitySessionState,
            activityElapsedSeconds: activityElapsedSeconds,
            activeSport: activeLaunch?.intent?.sport,
            feedbackPage: $feedbackPage,
            customizedTodayIntent: $customizedTodayIntent,
            activityLaunchSurface: activityLaunchSurface,
            launchGoalMode: launchGoalMode,
            showsPreActivityPhotoAction: isActivityVisible,
            preActivityPhoto: preActivityPhoto,
            onContextualStart: {
                activityStartRequest += 1
            },
            onPreActivityPhotoAction: {
                preActivityPhotoRequest += 1
            }
        ) { intent in
            presentActivity(intent: intent)
        }
    }

    private var activityLaunchSurface: AnyView {
        if let launch = activeLaunch {
            return AnyView(RecordView(
                initialIntent: launch.intent,
                isVisible: isActivityVisible && selectedAppTab == .today,
                isEmbeddedInToday: true,
                startRequest: activityStartRequest,
                preActivityPhotoRequest: preActivityPhotoRequest,
                onGoalModeChange: { launchGoalMode = $0 },
                onPreActivityPhotoChange: { preActivityPhoto = $0 },
                onCloseRequest: handleActivityClose,
                onSessionStateChange: { activitySessionState = $0 },
                onElapsedTimeChange: { activityElapsedSeconds = $0 }
            )
            .id(launch.id))
        }
        return AnyView(EmptyView())
    }

    private func presentActivity(intent: SessionIntent? = nil) {
        if let activeLaunch, activitySessionState != .idle {
            self.activeLaunch = activeLaunch
            isActivityVisible = true
            return
        }

        selectedAppTab = .today
        activeLaunch = RecordLaunch(intent: intent)
        activitySessionState = .idle
        activityElapsedSeconds = 0
        isActivityVisible = true
    }

    private func handleActivityClose(shouldKeepAlive: Bool) {
        guard !shouldKeepAlive else { return }
        activitySessionState = .idle
        activityElapsedSeconds = 0
        if selectedAppTab == .today {
            activeLaunch = RecordLaunch(intent: defaultTodayIntent)
            isActivityVisible = true
        } else {
            activeLaunch = nil
            isActivityVisible = false
        }
    }

    private var defaultTodayIntent: SessionIntent? {
        customizedTodayIntent
            ?? personalizationStore.snapshot.currentCalibrationWorkout?.sessionIntent
            ?? trainingPlanStore.todaySuggestion?.suggestedSession.intent
    }

    private func prepareTodayLaunchIfNeeded() {
        guard selectedAppTab == .today, activeLaunch == nil else { return }
        activeLaunch = RecordLaunch(intent: defaultTodayIntent)
        isActivityVisible = true
    }

    private func prepareOnboarding() {
        onboardingStore.prepareForAuthenticatedUser(identity: onboardingIdentity)
    }

    private func applyOnboardingProfile(_ profile: OnboardingProfile) {
        measurementPreferences.unitSystem = profile.bodyProfile.unitSystem
        dailyCheckInStore.select(profile.suggestedReadiness)
    }

    private func consumeStoredPreparedActivityIfNeeded() {
        guard activeLaunch == nil, activitySessionState == .idle else { return }
        appNavigationStore.consumeStoredPreparedActivity(unitSystem: measurementPreferences.unitSystem)
    }

    private func restoreInterruptedActivityIfNeeded() {
        guard activeLaunch == nil, let journal = ActiveSessionJournal.load() else { return }
        activeLaunch = RecordLaunch(intent: recoveredIntent(from: journal))
        isActivityVisible = true
    }

    private func recoveredIntent(from journal: ActiveSessionJournal) -> SessionIntent? {
        if let recoveredRoute = ActiveRouteGuidanceJournal.load(
            recoverySeed: journal.routeGuidanceRecoverySeed
        )?.route {
            let activityType = recoveredRoute.activityType ?? journal.activityType
            let sport = SportType(activityType: activityType)
            return SessionIntent(
                id: "route-\(recoveredRoute.id)",
                sport: sport,
                title: recoveredRoute.name,
                detail: String(localized: "route.guidance.setup.detail", defaultValue: "Follow the selected route with on-device guidance"),
                guideLine: String(localized: "route.guidance.setup.companion", defaultValue: "Keep the route visible and follow it at your own pace."),
                startLabel: String(localized: "route.guidance.resume", defaultValue: "Resume Route Guidance"),
                routeName: recoveredRoute.name,
                preparedRoute: recoveredRoute,
                activityTypeOverride: activityType
            )
        }

        guard let activityType = journal.activityType, activityType != .running else { return nil }
        let sport = SportType(activityType: activityType)
        return SessionIntent(
            id: "recovered-\(sport.rawValue)",
            sport: sport,
            title: String(
                format: String(localized: "activity.recovered.title.format", defaultValue: "Recovered %@"),
                locale: .autoupdatingCurrent,
                sport.displayName.lowercased()
            ),
            detail: String(localized: "activity.recovered.detail", defaultValue: "Paused activity recovered on this device"),
            guideLine: String(localized: "activity.recovered.companion", defaultValue: "Resume when you are ready."),
            startLabel: String(localized: "common.resume", defaultValue: "Resume"),
            activityTypeOverride: activityType
        )
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

struct SuggestedSession: Identifiable, Codable, Hashable {
    let id: String
    let sport: SportType
    let title: String
    let durationLabel: String
    let activityLabel: String
    let framing: String
    let guideLine: String
    let startLabel: String
    let targetDistanceMeters: Double?
    let targetDurationSeconds: Int?
    let routeName: String?
    let workoutSteps: [SessionIntentStep]?

    init(
        id: String,
        sport: SportType,
        title: String,
        durationLabel: String,
        activityLabel: String,
        framing: String,
        guideLine: String,
        startLabel: String,
        targetDistanceMeters: Double? = nil,
        targetDurationSeconds: Int? = nil,
        routeName: String? = nil,
        workoutSteps: [SessionIntentStep]? = nil
    ) {
        self.id = id
        self.sport = sport
        self.title = title
        self.durationLabel = durationLabel
        self.activityLabel = activityLabel
        self.framing = framing
        self.guideLine = guideLine
        self.startLabel = startLabel
        self.targetDistanceMeters = targetDistanceMeters
        self.targetDurationSeconds = targetDurationSeconds
        self.routeName = routeName
        self.workoutSteps = workoutSteps
    }

    var intent: SessionIntent {
        SessionIntent(
            id: id,
            sport: sport,
            title: title,
            detail: "\(durationLabel) • \(activityLabel)",
            guideLine: guideLine,
            startLabel: startLabel,
            targetDistanceMeters: targetDistanceMeters,
            targetDurationSeconds: targetDurationSeconds ?? SessionIntentGoalParser.durationSeconds(from: durationLabel),
            routeName: routeName,
            workoutSteps: workoutSteps ?? []
        )
    }
}

struct FinishReflection: Equatable, Codable {
    let title: String
    let body: String
    let highlight: String
    let progressNote: String?
}

enum DailyMotivationEngine {
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
        let progressNote = goalProgress?.guideLine

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
}
