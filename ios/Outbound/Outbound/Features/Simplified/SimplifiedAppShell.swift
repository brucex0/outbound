import SwiftUI
import PhotosUI
import UIKit
import Combine

enum SimplifiedAppTab: Hashable {
    case social
    case today
    case me

    var feedbackPageName: String {
        switch self {
        case .social: "Social"
        case .today: "Today"
        case .me: "Me"
        }
    }
}

struct SimplifiedAppShell: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.outboundTheme) private var theme
    @EnvironmentObject private var guideCatalog: GuideCatalogStore
    @EnvironmentObject private var activityStore: ActivityStore
    @EnvironmentObject private var dailyCheckInStore: DailyCheckInStore
    @EnvironmentObject private var trainingPlanStore: TrainingPlanStore
    @EnvironmentObject private var weatherStore: SituationalWeatherStore
    @EnvironmentObject private var appNavigationStore: AppNavigationStore
    @EnvironmentObject private var pushNotifications: PushNotificationCoordinator
    @EnvironmentObject private var communityRouteStore: CommunityRouteStore
    @Binding var selection: SimplifiedAppTab
    let activitySessionState: ActivitySessionPortalState
    let activityElapsedSeconds: Int
    let activeSport: SportType?
    @Binding var feedbackPage: String
    @Binding var customizedTodayIntent: SessionIntent?
    let activityLaunchSurface: AnyView
    let launchGoalMode: SessionGoalMode
    let onContextualStart: () -> Void
    let onStartRun: (SessionIntent?) -> Void
    @State private var showsAssistant = false
    @State private var selectedRouteName: String?

    var body: some View {
        TabView(selection: $selection) {
            SocialHomeView()
                .tag(SimplifiedAppTab.social)
                .tabItem { Label("Social", systemImage: "person.2") }

            SimplifiedTodayView(
                isSelected: selection == .today,
                activitySessionState: activitySessionState,
                activityElapsedSeconds: activityElapsedSeconds,
                activeSport: activeSport,
                customizedRunIntent: $customizedTodayIntent,
                selectedRouteName: $selectedRouteName,
                activityLaunchSurface: activityLaunchSurface,
                launchGoalMode: launchGoalMode,
                onOpenAssistant: { showsAssistant = true },
                onStartRun: onStartRun
            )
                .assistantHighlightAnchor("today.primary-action")
                .tag(SimplifiedAppTab.today)
                .tabItem { Label(String(localized: "Today"), systemImage: "sparkles") }

            SimplifiedMeView()
                .tag(SimplifiedAppTab.me)
                .tabItem { Label("Me", systemImage: "person.crop.circle") }
        }
        .tint(guideCatalog.selectedTheme.accentColor)
        .background {
            NativeContextualTabBarBridge(
                selectedTab: selection,
                showsStart: selection == .today && activitySessionState == .idle,
                actionColor: theme.actionColor,
                onSelect: selectTabWithoutAnimation,
                onStart: onContextualStart
            )
            .frame(width: 0, height: 0)
        }
        .onChange(of: selection, initial: true) { _, tab in
            feedbackPage = tab.feedbackPageName
        }
        .overlay(alignment: .bottomLeading) {
            if selection != .today {
                Button {
                    showsAssistant = true
                } label: {
                    Image(systemName: "sparkles")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(guideCatalog.selectedTheme.accentColor.gradient, in: Circle())
                        .overlay {
                            Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
                        }
                        .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Open assistant"))
                .accessibilityHint(String(localized: "Get help with this page or anywhere in Plainstride"))
                .padding(.leading, 18)
                .padding(.bottom, 58)
            }
        }
        .sheet(isPresented: $showsAssistant) {
            AssistantView(
                screenName: assistantScreenName,
                isRecordingActive: activitySessionState != .idle,
                focusedActivity: selection == .today ? customizedTodayIntent ?? trainingPlanStore.todaySuggestion?.suggestedSession.intent : nil,
                onApplyFocusedActivity: { customizedTodayIntent = $0 }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            weatherStore.refreshForToday()
            trainingPlanStore.refresh(
                activities: activityStore.activities,
                readiness: dailyCheckInStore.readiness,
                phase: DailyMotivationEngine.phase(for: activityStore.activities)
            )
        }
        .onChange(of: activityStore.activities) { _, activities in
            trainingPlanStore.refresh(
                activities: activities,
                readiness: dailyCheckInStore.readiness,
                phase: DailyMotivationEngine.phase(for: activities)
            )
        }
        .onChange(of: dailyCheckInStore.readiness) { _, readiness in
            trainingPlanStore.refresh(
                activities: activityStore.activities,
                readiness: readiness,
                phase: DailyMotivationEngine.phase(for: activityStore.activities)
            )
        }
        .onChange(of: appNavigationStore.pendingAssistantTarget) { _, target in
            guard let target else { return }
            switch target.destination {
            case .social:
                selection = .social
                appNavigationStore.consume()
            case .today:
                selection = .today
                appNavigationStore.consume()
            case .me:
                selection = .me
                appNavigationStore.consume()
            case .settings, .appearance, .settingsAppleMusic, .settingsAppleHealth, .guideSettings, .activityHistory:
                selection = .me
            }
        }
        .onChange(of: pushNotifications.pendingNotificationID) { _, notificationID in
            guard notificationID != nil else { return }
            selection = .social
        }
        .onChange(of: communityRouteStore.pendingLaunch) { _, route in
            guard let route else { return }
            selectedRouteName = route.name
            let sport = SportType(activityType: route.activityType)
            onStartRun(SessionIntent(
                id: "route-\(route.id)", sport: sport, title: route.name,
                detail: String(localized: "route.guidance.setup.detail", defaultValue: "Follow the selected route with on-device guidance"),
                guideLine: String(localized: "route.guidance.setup.companion", defaultValue: "Keep the route visible and follow it at your own pace."),
                startLabel: String(localized: "route.guidance.start", defaultValue: "Start Route Guidance"),
                routeName: route.name,
                preparedRoute: route,
                activityTypeOverride: route.activityType
            ))
            communityRouteStore.consumeLaunch()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                weatherStore.refreshForToday()
            }
        }
    }

    private var assistantScreenName: String {
        switch selection {
        case .social:
            return String(localized: "Social")
        case .today:
            if let activity = customizedTodayIntent ?? trainingPlanStore.todaySuggestion?.suggestedSession.intent {
                return String(localized: "Today · \(activity.title) · \(activity.detail)")
            }
            return String(localized: "Today")
        case .me:
            return String(localized: "Me")
        }
    }

    private func selectTabWithoutAnimation(_ tab: SimplifiedAppTab) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selection = tab
        }
    }

}

private struct NativeContextualTabBarBridge: UIViewControllerRepresentable {
    let selectedTab: SimplifiedAppTab
    let showsStart: Bool
    let actionColor: Color
    let onSelect: (SimplifiedAppTab) -> Void
    let onStart: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> TabBarAttachmentViewController {
        let controller = TabBarAttachmentViewController()
        controller.onResolveTabBarController = { tabBarController in
            context.coordinator.attach(to: tabBarController)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: TabBarAttachmentViewController, context: Context) {
        context.coordinator.update(
            selectedTab: selectedTab,
            showsStart: showsStart,
            actionColor: UIColor(actionColor),
            onSelect: onSelect,
            onStart: onStart
        )
    }

    static func dismantleUIViewController(
        _ uiViewController: TabBarAttachmentViewController,
        coordinator: Coordinator
    ) {
        coordinator.detach()
    }

    final class Coordinator {
        private struct VisualState {
            let showsStart: Bool
            let actionColor: UIColor

            func matches(_ other: VisualState) -> Bool {
                showsStart == other.showsStart && actionColor.isEqual(other.actionColor)
            }
        }

        private weak var tabBarController: UITabBarController?
        private weak var appliedItem: UITabBarItem?
        private var selectionPressRecognizer: UILongPressGestureRecognizer?
        private var selectedTab = SimplifiedAppTab.today
        private var showsStart = false
        private var actionColor = UIColor.systemOrange
        private var appliedVisualState: VisualState?
        private var isDeferredApplyScheduled = false
        private var onSelect: ((SimplifiedAppTab) -> Void)?
        private var onStart: (() -> Void)?

        func update(
            selectedTab: SimplifiedAppTab,
            showsStart: Bool,
            actionColor: UIColor,
            onSelect: @escaping (SimplifiedAppTab) -> Void,
            onStart: @escaping () -> Void
        ) {
            let previousState = VisualState(showsStart: self.showsStart, actionColor: self.actionColor)
            let nextState = VisualState(showsStart: showsStart, actionColor: actionColor)
            self.selectedTab = selectedTab
            self.showsStart = showsStart
            self.actionColor = actionColor
            self.onSelect = onSelect
            self.onStart = onStart
            if !nextState.matches(previousState) || appliedVisualState == nil {
                configureTabBar()
            }
        }

        func attach(to controller: UITabBarController?) {
            guard let controller else { return }
            if tabBarController !== controller {
                detach()
                tabBarController = controller
                appliedItem = nil
                appliedVisualState = nil
            }
            installSelectionPressRecognizer(on: controller)
            configureTabBar()
        }

        func detach() {
            if let selectionPressRecognizer {
                tabBarController?.tabBar.removeGestureRecognizer(selectionPressRecognizer)
            }
            tabBarController = nil
            appliedItem = nil
            appliedVisualState = nil
            isDeferredApplyScheduled = false
            selectionPressRecognizer = nil
        }

        private func installSelectionPressRecognizer(on controller: UITabBarController) {
            guard selectionPressRecognizer == nil else { return }
            let recognizer = UILongPressGestureRecognizer(
                target: self,
                action: #selector(handleTabBarPress(_:))
            )
            recognizer.minimumPressDuration = 0
            recognizer.allowableMovement = 12
            recognizer.cancelsTouchesInView = true
            recognizer.delaysTouchesBegan = false
            controller.tabBar.addGestureRecognizer(recognizer)
            selectionPressRecognizer = recognizer
        }

        @objc private func handleTabBarPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began,
                  let tabBarController,
                  let itemCount = tabBarController.tabBar.items?.count,
                  itemCount == 3
            else { return }

            let location = recognizer.location(in: tabBarController.tabBar)
            let itemWidth = tabBarController.tabBar.bounds.width / CGFloat(itemCount)
            guard itemWidth > 0 else { return }
            let targetIndex = min(max(Int(location.x / itemWidth), 0), itemCount - 1)

            if targetIndex == 1, selectedTab == .today, showsStart {
                onStart?()
                return
            }

            guard let targetTab = tab(for: targetIndex), targetTab != selectedTab else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            UIView.performWithoutAnimation {
                tabBarController.selectedIndex = targetIndex
                tabBarController.tabBar.layoutIfNeeded()
            }
            CATransaction.commit()
            onSelect?(targetTab)
        }

        private func tab(for index: Int) -> SimplifiedAppTab? {
            switch index {
            case 0: .social
            case 1: .today
            case 2: .me
            default: nil
            }
        }

        private func configureTabBar(allowsDeferredRetry: Bool = true) {
            guard let tabBarController else { return }
            guard applyCenterItem(to: tabBarController) else {
                if allowsDeferredRetry {
                    scheduleDeferredApply(on: tabBarController)
                }
                return
            }
        }

        private func scheduleDeferredApply(on controller: UITabBarController) {
            guard !isDeferredApplyScheduled else { return }
            isDeferredApplyScheduled = true
            DispatchQueue.main.async { [weak self, weak controller] in
                guard let self else { return }
                self.isDeferredApplyScheduled = false
                guard let controller, self.tabBarController === controller else { return }
                self.configureTabBar(allowsDeferredRetry: false)
            }
        }

        private func applyCenterItem(to controller: UITabBarController) -> Bool {
            guard let item = controller.tabBar.items?[safe: 1] else { return false }
            let visualState = VisualState(showsStart: showsStart, actionColor: actionColor)
            if appliedItem === item,
               let appliedVisualState,
               visualState.matches(appliedVisualState) {
                return true
            }

            UIView.performWithoutAnimation {
                if showsStart {
                    let configuration = UIImage.SymbolConfiguration(pointSize: 30, weight: .semibold)
                    let image = UIImage(systemName: "play.circle.fill", withConfiguration: configuration)?
                        .withTintColor(actionColor, renderingMode: .alwaysOriginal)
                    item.title = nil
                    item.image = image
                    item.selectedImage = image
                    item.imageInsets = .zero
                    item.accessibilityLabel = String(localized: "record.start.short", defaultValue: "Start")
                    item.accessibilityHint = String(localized: "record.start.accessibility_hint", defaultValue: "Starts the prepared activity")
                    item.accessibilityIdentifier = "tab.start"
                } else {
                    let image = UIImage(systemName: "sparkles")?.withRenderingMode(.alwaysTemplate)
                    item.title = String(localized: "Today")
                    item.image = image
                    item.selectedImage = image
                    item.imageInsets = .zero
                    item.accessibilityLabel = String(localized: "Today")
                    item.accessibilityHint = nil
                    item.accessibilityIdentifier = "tab.today"
                }
                controller.tabBar.setNeedsLayout()
                controller.tabBar.layoutIfNeeded()
            }
            appliedItem = item
            appliedVisualState = visualState
            return true
        }
    }
}

private final class TabBarAttachmentViewController: UIViewController {
    var onResolveTabBarController: ((UITabBarController?) -> Void)?

    override func loadView() {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        self.view = view
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        resolveTabBarController()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        resolveTabBarController()
    }

    private func resolveTabBarController() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let resolvedController = self.tabBarController
                ?? Self.findTabBarController(in: self.view.window?.rootViewController)
            self.onResolveTabBarController?(resolvedController)
        }
    }

    private static func findTabBarController(in controller: UIViewController?) -> UITabBarController? {
        guard let controller else { return nil }
        if let tabBarController = controller as? UITabBarController {
            return tabBarController
        }
        for child in controller.children {
            if let tabBarController = findTabBarController(in: child) {
                return tabBarController
            }
        }
        return findTabBarController(in: controller.presentedViewController)
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private struct SimplifiedTodayView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.outboundTheme) private var theme
    @EnvironmentObject private var activityStore: ActivityStore
    @EnvironmentObject private var dailyCheckInStore: DailyCheckInStore
    @EnvironmentObject private var personalizationStore: PersonalizationStore
    @EnvironmentObject private var trainingPlanStore: TrainingPlanStore
    @EnvironmentObject private var weatherStore: SituationalWeatherStore
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    @EnvironmentObject private var socialStore: TogetherStore
    @EnvironmentObject private var guideCatalog: GuideCatalogStore
    @AppStorage("theme_discovery_tip_dismissed_v1") private var hasDismissedThemeTip = false
    @AppStorage("theme_discovery_tip_presentation_count_v1") private var themeTipPresentationCount = 0
    let isSelected: Bool
    let activitySessionState: ActivitySessionPortalState
    let activityElapsedSeconds: Int
    let activeSport: SportType?
    @Binding var customizedRunIntent: SessionIntent?
    @Binding var selectedRouteName: String?
    let activityLaunchSurface: AnyView
    let launchGoalMode: SessionGoalMode
    let onOpenAssistant: () -> Void
    let onStartRun: (SessionIntent?) -> Void
    @StateObject private var launchLocationManager = LocationManager()
    @State private var showsCompanionExplanation = false
    @State private var showsChangeSheet = false
    @State private var companionTodayMessage: String?
    @State private var companionWeatherFetchDate: Date?
    @State private var companionActivityID: UUID?
    @State private var isCompanionInsightLoading = false
    @State private var companionRequestID: UUID?
    @State private var currentDay = Calendar.current.startOfDay(for: Date())
    @State private var showsThemeTip = false
    @State private var showsThemeChooser = false
    @State private var showsUpcomingWorkout = false
    @State private var showsPlanDetails = false
    @State private var showsPlanPicker = false
    @State private var showsStandaloneWorkouts = false
    @State private var selectedPlanRecommendation: TrainingPlanRecommendation?
    @State private var replacementPlanRecommendation: TrainingPlanRecommendation?

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    ZStack(alignment: .bottom) {
                        OutboundPalette.background
                        ActivityLaunchMap(
                            locationManager: launchLocationManager,
                            route: activeRunIntent.preparedRoute
                        )
                        .clipped()

                        if launchGoalMode == .planned || activitySessionState != .idle {
                            todayPeerCards
                                .padding(.horizontal, OutboundSpacing.screen)
                                .padding(.bottom, ActivityLaunchLayout.peerCardGap)
                        }
                    }

                    Color.clear
                        .frame(height: ActivityLaunchLayout.dockHeight)
                        .allowsHitTesting(false)
                }

                activityLaunchSurface
            }
            .overlay(alignment: .topLeading) {
                Button(action: onOpenAssistant) {
                    Image(systemName: "sparkles")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(guideCatalog.selectedTheme.accentColor.gradient, in: Circle())
                        .overlay {
                            Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
                        }
                        .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Open assistant"))
                .accessibilityHint(String(localized: "Get help with this page or anywhere in Plainstride"))
                .padding(16)
            }
            .background(OutboundPalette.background)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SavedActivity.self) { ActivityDetailView(activity: $0) }
            .toolbar {
                if canPresentThemeTip || showsThemeTip {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            if showsThemeTip {
                                showsThemeTip = false
                            } else {
                                presentThemeTip()
                            }
                        } label: {
                            Image(systemName: "paintpalette.fill")
                        }
                        .accessibilityLabel("Change appearance")
                        .popover(isPresented: $showsThemeTip, arrowEdge: .top) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Want a different look?")
                                    .font(.headline)
                                Text("Change the mode or pick a theme that feels like you.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Button("Change appearance") {
                                    hasDismissedThemeTip = true
                                    showsThemeTip = false
                                    Task { @MainActor in
                                        try? await Task.sleep(for: .milliseconds(250))
                                        showsThemeChooser = true
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .padding()
                            .presentationCompactAdaptation(.popover)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    GlobalConditionsButton()
                }
            }
            .onAppear {
                launchLocationManager.requestCurrentLocation()
            }
            .task {
                await loadCompanionTodayMessage()
            }
            .onChange(of: weatherStore.snapshot) { _, _ in
                Task { await loadCompanionTodayMessage() }
            }
            .onChange(of: completedActivityToday?.id) { _, _ in
                Task { await loadCompanionTodayMessage(force: true) }
            }
            .onChange(of: todayWorkoutID) { _, _ in
                Task { await loadCompanionTodayMessage(force: true) }
            }
            .onChange(of: trainingPlanStore.todaySuggestion?.workout.id) { _, _ in
                customizedRunIntent = nil
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refreshCurrentDayIfNeeded() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                refreshCurrentDayIfNeeded()
            }
            .task(id: isSelected) {
                guard isSelected, canPresentThemeTip else { return }
                do {
                    try await Task.sleep(for: .milliseconds(650))
                } catch {
                    return
                }
                guard isSelected, canPresentThemeTip else { return }
                presentThemeTip()
            }
            .onChange(of: isSelected) { _, isSelected in
                if !isSelected {
                    showsThemeTip = false
                }
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
        .sheet(isPresented: $showsThemeChooser) {
            ThemeChooserView()
                .environmentObject(guideCatalog)
        }
        .sheet(isPresented: $showsUpcomingWorkout) {
            upcomingWorkoutSheet
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showsPlanDetails) {
            NavigationStack {
                if let activePlan = trainingPlanStore.activePlan {
                    if let week = trainingPlanStore.currentWeek {
                        ActiveTrainingPlanDetailView(
                            activePlan: activePlan,
                            week: week,
                            todaySuggestion: trainingPlanStore.todaySuggestion,
                            accentColor: theme.accentColor,
                            onChangePlan: {
                                showsPlanDetails = false
                                Task { @MainActor in
                                    await Task.yield()
                                    presentPlanPicker()
                                }
                            },
                            onEndPlan: {
                                trainingPlanStore.clearActivePlan()
                                showsPlanDetails = false
                            }
                        )
                    } else {
                        ActiveTrainingPlanPendingDetailView(activePlan: activePlan, accentColor: theme.accentColor)
                    }
                } else {
                    ActiveTrainingPlanSyncingDetailView(accentColor: theme.accentColor)
                }
            }
        }
        .sheet(isPresented: $showsPlanPicker) {
            NavigationStack {
                TrainingPlanPickerView(
                    recommendations: trainingPlanStore.planOptions,
                    isRefreshing: trainingPlanStore.isRefreshingPlanRecommendations,
                    accentColor: theme.accentColor,
                    onSelectPlan: {
                        showsPlanPicker = false
                        selectedPlanRecommendation = $0
                    },
                    onUsePlan: { requestPlanActivation($0) }
                )
            }
        }
        .sheet(isPresented: $showsStandaloneWorkouts) {
            StandaloneWorkoutPickerView { workout in
                showsStandaloneWorkouts = false
                customizedRunIntent = workout.intent
                onStartRun(workout.intent)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $selectedPlanRecommendation) { recommendation in
            NavigationStack {
                TrainingPlanRecommendationDetailView(
                    recommendation: recommendation,
                    accentColor: theme.accentColor,
                    onUsePlan: { requestPlanActivation(recommendation) },
                    onMorePlans: { returnToPlanPicker() }
                )
            }
        }
        .confirmationDialog(
            "Replace your current training plan?",
            isPresented: Binding(
                get: { replacementPlanRecommendation != nil },
                set: { if !$0 { replacementPlanRecommendation = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Replace plan", role: .destructive) {
                guard let recommendation = replacementPlanRecommendation else { return }
                activatePlan(recommendation)
            }
            Button("Keep current plan", role: .cancel) { replacementPlanRecommendation = nil }
        } message: {
            Text("This replaces your current multi-week schedule with the selected plan. Completed activities stay in your history.")
        }
    }

    private func presentPlanPicker() {
        trainingPlanStore.prepareRecommendations(
            activities: activityStore.activities,
            readiness: dailyCheckInStore.readiness,
            phase: DailyMotivationEngine.phase(for: activityStore.activities)
        )
        showsPlanPicker = true
    }

    private func requestPlanActivation(_ recommendation: TrainingPlanRecommendation) {
        if trainingPlanStore.activePlan != nil {
            showsPlanPicker = false
            selectedPlanRecommendation = nil
            Task { @MainActor in
                await Task.yield()
                replacementPlanRecommendation = recommendation
            }
        } else {
            activatePlan(recommendation)
        }
    }

    private func returnToPlanPicker() {
        selectedPlanRecommendation = nil
        Task { @MainActor in
            await Task.yield()
            presentPlanPicker()
        }
    }

    private func activatePlan(_ recommendation: TrainingPlanRecommendation) {
        trainingPlanStore.acceptRecommendation(recommendation)
        replacementPlanRecommendation = nil
        selectedPlanRecommendation = nil
        showsPlanPicker = false
    }

    private var canPresentThemeTip: Bool {
        !hasDismissedThemeTip && themeTipPresentationCount < 3
    }

    private func presentThemeTip() {
        guard canPresentThemeTip else { return }
        themeTipPresentationCount += 1
        showsThemeTip = true
    }

    private var activityEventToday: ActivityEventDTO? {
        socialStore.state.upcomingRuns.first {
            $0.currentUserGoing == true && Calendar.current.isDateInToday($0.startsAt)
        }
    }

    @ViewBuilder
    private var todayPeerCards: some View {
        VStack(spacing: OutboundSpacing.standard) {
            if let completedActivityToday {
                completedTodayCard(completedActivityToday)
                upcomingWorkoutButton
            } else if let activityEventToday {
                activityEventCard(activityEventToday)
            } else {
                plannedWorkoutCard
            }

            if activitySessionState != .idle {
                inProgressActivityCard
            }
        }
    }

    private var activityLibraryButtons: some View {
        HStack(spacing: OutboundSpacing.compact) {
            activityLibraryButton(
                title: trainingPlanStore.activePlan?.localizedTitle ?? String(localized: "Plans"),
                systemImage: "calendar"
            ) {
                if trainingPlanStore.activePlan == nil {
                    presentPlanPicker()
                } else {
                    showsPlanDetails = true
                }
            }
            .accessibilityLabel("Plans")
            .accessibilityValue(trainingPlanStore.activePlan?.localizedTitle ?? String(localized: "No plan selected"))

            activityLibraryButton(
                title: customizedRunIntent.map { localizedAppCopy($0.title) } ?? String(localized: "library.workouts", defaultValue: "Workouts"),
                systemImage: "figure.run"
            ) {
                showsStandaloneWorkouts = true
            }
            .accessibilityLabel(String(localized: "library.workouts", defaultValue: "Workouts"))
            .accessibilityValue(customizedRunIntent.map { localizedAppCopy($0.title) } ?? String(localized: "No workout selected"))

            NavigationLink {
                CommunityRouteLibraryView()
            } label: {
                activityLibraryButtonLabel(
                    title: selectedRouteName ?? String(localized: "library.routes", defaultValue: "Routes"),
                    systemImage: "map"
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "library.routes", defaultValue: "Routes"))
            .accessibilityValue(selectedRouteName ?? String(localized: "No route selected"))
        }
    }

    private func activityLibraryButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            activityLibraryButtonLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }

    private func activityLibraryButtonLabel(title: String, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.accentColor)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 76)
        .padding(.horizontal, 6)
        .background(
            Color.primary.opacity(0.045),
            in: RoundedRectangle(cornerRadius: OutboundRadius.control, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: OutboundRadius.control, style: .continuous))
    }

    private func activityEventCard(_ event: ActivityEventDTO) -> some View {
        OutboundCard(style: .companion) {
            VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                Text("NEXT ACTIVITY").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ActivityEventSummaryContent(
                    title: event.title,
                    startsAt: event.startsAt,
                    locationName: event.locationName,
                    note: event.paceNote
                )
                Text(event.currentUserRole == "owner"
                     ? String(localized: "You’re organizing · Meet up or join from anywhere")
                     : String(localized: "You’re participating · Meet up or join from anywhere"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var plannedWorkoutCard: some View {
        OutboundCard {
            VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                HStack(alignment: .top, spacing: OutboundSpacing.standard) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(completedActivityToday == nil ? "Today’s workout" : "Up next")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.accentColor)
                            .textCase(.uppercase)
                        Text(todayWorkoutName)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(OutboundPalette.primaryText)
                    }
                    Spacer()
                    Menu {
                        Button("Change workout", systemImage: "slider.horizontal.3") {
                            showsChangeSheet = true
                        }
                        Button("Why this workout?", systemImage: "info.circle") {
                            showsCompanionExplanation = true
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.headline)
                            .frame(width: 36, height: 36)
                            .background(Color.primary.opacity(0.06), in: Circle())
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Workout options")
                }
                Text(todayTotalDuration)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
                WorkoutWeatherGuidance(snapshot: weatherStore.snapshot)
                CompactIntervalPreview(phases: todayPhases)
            }
        }
    }

    private var inProgressActivityCard: some View {
        Button {
            onStartRun(nil)
        } label: {
            OutboundCard {
                HStack(spacing: OutboundSpacing.standard) {
                    ZStack {
                        Circle()
                            .fill((activitySessionState == .paused ? Color.yellow : Color.red).opacity(0.14))
                            .frame(width: 38, height: 38)
                        Image(systemName: activitySessionState == .paused ? "pause.fill" : "waveform.path.ecg")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(activitySessionState == .paused ? Color.orange : Color.red)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(activitySessionState == .paused ? "Activity paused" : "Activity in progress")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(activeSport?.displayName ?? String(localized: "Activity"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(activityElapsedSeconds.formatted())
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(activitySessionState == .paused ? "Activity paused" : "Activity in progress"), "
            + "\(activeSport?.displayName ?? String(localized: "Activity")), "
            + "\(activityElapsedSeconds.formatted()) elapsed"
        )
        .accessibilityHint("Returns to the activity recording screen")
    }

    private var upcomingWorkoutButton: some View {
        Button { showsUpcomingWorkout = true } label: {
            HStack(spacing: OutboundSpacing.compact) {
                Image(systemName: "calendar")
                    .foregroundStyle(theme.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(upcomingScheduleLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text("\(todayWorkoutName) · \(todayTotalDuration)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: OutboundRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(upcomingScheduleLabel), \(todayWorkoutName), \(todayTotalDuration)")
        .accessibilityHint("Shows the upcoming workout")
    }

    private var upcomingWorkoutSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OutboundSpacing.section) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(upcomingScheduleLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.accentColor)
                        Text(todayWorkoutName)
                            .font(.title2.weight(.bold))
                        Text(todayTotalDuration)
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    CompactIntervalPreview(phases: todayPhases)
                    Text(todayExplanation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(OutboundSpacing.screen)
            }
            .background(OutboundPalette.background)
            .navigationTitle("Up next")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showsUpcomingWorkout = false }
                }
            }
        }
    }

    private var upcomingScheduleLabel: String {
        guard let dayLabel = trainingPlanStore.todaySuggestion?.workout.dayLabel,
              !dayLabel.isEmpty,
              dayLabel.localizedCaseInsensitiveCompare("Today") != .orderedSame
        else { return String(localized: "Up next") }

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: currentDay) ?? currentDay
        let tomorrowLabels = [
            String(localized: "Tomorrow"),
            tomorrow.formatted(.dateTime.weekday(.abbreviated)),
            tomorrow.formatted(.dateTime.weekday(.wide))
        ]
        return tomorrowLabels.contains {
            dayLabel.localizedCaseInsensitiveCompare($0) == .orderedSame
        }
            ? String(localized: "Tomorrow")
            : dayLabel
    }

    private func completedTodayCard(_ activity: SavedActivity) -> some View {
        NavigationLink(value: activity) {
            OutboundCard(style: .companion) {
                VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                    HStack {
                        Label("Today’s run is done", systemImage: "checkmark.circle.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    Text("Nice work. Recover well and let this one count.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.82))
                    HStack {
                        todayStat(measurementPreferences.unitSystem.distanceString(meters: activity.distanceM, fractionDigits: 1), "Distance")
                        todayStat(durationLabel(activity.durationSecs), "Time")
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens today’s completed activity")
    }

    private var lastActivityCard: some View {
        OutboundCard {
            VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                HStack {
                    Text("LAST ACTIVITY")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    NavigationLink("See all") { ActivityHistoryView() }
                        .font(.subheadline.weight(.semibold))
                }

                if let activity = activityStore.activities.first {
                    NavigationLink(value: activity) {
                        HStack(spacing: OutboundSpacing.standard) {
                            Image(systemName: "figure.run.circle.fill")
                                .font(.title2)
                                .foregroundStyle(theme.accentColor)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(activity.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(activity.startedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(measurementPreferences.unitSystem.distanceString(meters: activity.distanceM, fractionDigits: 1))
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(.primary)
                                Text(durationLabel(activity.durationSecs))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Your completed runs will appear here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func todayStat(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var completedActivityToday: SavedActivity? {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: currentDay)
            ?? currentDay.addingTimeInterval(24 * 60 * 60)
        return activityStore.activities.first {
            $0.startedAt >= currentDay && $0.startedAt < tomorrow
        }
    }

    private func refreshCurrentDayIfNeeded() {
        let day = Calendar.current.startOfDay(for: Date())
        guard day != currentDay else { return }
        currentDay = day
        customizedRunIntent = nil
        companionTodayMessage = nil
        companionActivityID = nil
        Task { await loadCompanionTodayMessage(force: true) }
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
        let base = "What is the one most useful thing for me to know about today's training? The workout currently displayed in the app is \(todayWorkoutName), \(todayTotalDuration), with workout ID \(todayWorkoutID). Refer to that workout, not an earlier cached plan day. If a situational signal matters, recommend the smallest safe adjustment, but do not mutate the plan."
        guard let activity else { return base }
        let distance = measurementPreferences.unitSystem.distanceString(meters: activity.distanceM, fractionDigits: 1)
        return """
        \(base)
        The local activity store confirms that a workout was already completed today: \(activity.title), \(durationLabel(activity.durationSecs)), \(distance). The workout currently displayed is a new optional recommendation, not the completed session. Briefly explain whether doing it today is sensible, and favor recovery when another workout would add unnecessary stress.
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
            return String(localized: "You completed today’s \(durationLabel(activity.durationSecs)) activity. Let that work count and prioritize recovery now.")
        }
        return todayExplanation
    }

    private var plannedRunIntent: SessionIntent {
        if let workout = currentCalibrationWorkout {
            return workout.sessionIntent
        }
        if let suggestion = trainingPlanStore.todaySuggestion {
            return suggestion.suggestedSession.intent
        }
        return SessionIntent(
            id: "today-comfortable-run",
            sport: .run,
            title: String(localized: "Easy run"),
            detail: String(localized: "Run · 30 min · conversational effort"),
            guideLine: String(localized: "Settle into a conversational effort and keep this one comfortable."),
            startLabel: String(localized: "Start workout"),
            targetDurationSeconds: 30 * 60,
            workoutSteps: [
                SessionIntentStep(id: "warmup", label: String(localized: "Warm-up"), durationSeconds: 5 * 60, detail: String(localized: "Very easy")),
                SessionIntentStep(id: "relaxed", label: String(localized: "Relaxed"), durationSeconds: 20 * 60, detail: String(localized: "Conversational effort")),
                SessionIntentStep(id: "cooldown", label: String(localized: "Cool-down"), durationSeconds: 5 * 60, detail: String(localized: "Ease down")),
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
        if let customizedRunIntent { return localizedAppCopy(customizedRunIntent.title) }
        let rawName = currentCalibrationWorkout?.title ?? trainingPlanStore.todaySuggestion?.workout.title ?? "Easy run"
        return localizedAppCopy(rawName.components(separatedBy: " · ").first ?? rawName)
    }

    private var todayTotalDuration: String {
        if let distanceMeters = activeRunIntent.targetDistanceMeters {
            let kilometers = distanceMeters / 1_000
            return kilometers.rounded() == kilometers
                ? "\(Int(kilometers)) km"
                : String(format: "%.1f km", kilometers)
        }
        let stepSeconds = activeRunIntent.workoutSteps.reduce(0) { $0 + $1.durationSeconds }
        return durationLabel(stepSeconds > 0 ? stepSeconds : activeRunIntent.targetDurationSeconds ?? 30 * 60)
    }

    private var todayExplanation: String {
        if let workout = currentCalibrationWorkout { return localizedAppCopy(workout.purpose) }
        let copy = trainingPlanStore.todaySuggestion?.adjustmentLine
            ?? trainingPlanStore.todaySuggestion?.guideLine
            ?? "This approachable run builds consistency while Plainstride learns your natural easy effort."
        return localizedAppCopy(copy)
    }

    private var todayPhases: [WorkoutPhaseItem] {
        if let customizedRunIntent {
            if let meters = customizedRunIntent.targetDistanceMeters {
                return [WorkoutPhaseItem(
                    id: customizedRunIntent.id,
                    duration: distanceLabel(meters),
                    title: customizedRunIntent.title,
                    weight: 1
                )]
            }
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
                    title: localizedAppCopy($0.label),
                    weight: max(1, CGFloat($0.durationSeconds) / 300)
                )
            }
        }
        let steps = trainingPlanStore.todaySuggestion?.workout.steps ?? []
        guard !steps.isEmpty else {
            return [
                WorkoutPhaseItem(id: "warmup", duration: "5m", title: String(localized: "Warm-up"), weight: 1),
                WorkoutPhaseItem(id: "relaxed", duration: "20m", title: String(localized: "Relaxed"), weight: 3),
                WorkoutPhaseItem(id: "cooldown", duration: "5m", title: String(localized: "Cool-down"), weight: 1),
            ]
        }
        return steps.map {
            WorkoutPhaseItem(
                id: $0.id,
                duration: $0.durationLabel.replacingOccurrences(of: " min", with: "m"),
                title: localizedAppCopy($0.label),
                weight: max(1, CGFloat($0.durationSeconds) / 300)
            )
        }
    }

    /// Model and fallback copy uses English semantic values; catalog lookup localizes
    /// app-authored values while preserving unknown user- or server-authored prose.
    private func localizedAppCopy(_ value: String) -> String {
        String(localized: String.LocalizationValue(value))
    }

    private var currentCalibrationWorkout: CalibrationWorkoutDTO? {
        personalizationStore.snapshot.currentCalibrationWorkout
    }

    private func durationLabel(_ seconds: Int) -> String {
        seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds / 60)m \(seconds % 60)s"
    }

    private func distanceLabel(_ meters: Double) -> String {
        let kilometers = meters / 1_000
        return kilometers.rounded() == kilometers
            ? "\(Int(kilometers)) km"
            : String(format: "%.1f km", kilometers)
    }

    private func changedRunIntent(minutes: Int, reason: ReadinessChoice) -> SessionIntent {
        SessionIntent(
            id: "changed-\(reason.rawValue)-\(minutes)",
            sport: .run,
            title: "\(minutes) min easy run",
            detail: "Run · \(minutes) min · very easy",
            guideLine: reason == .sore
                ? "Keep this very easy and stop if discomfort becomes pain."
                : "Keep the effort easy. A shorter run still protects the habit.",
            startLabel: "Start changed run",
            targetDurationSeconds: minutes * 60
        )
    }
}

struct ThemeChooserView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var guideCatalog: GuideCatalogStore
    @EnvironmentObject private var appearancePreferences: AppearancePreferences

    var body: some View {
        NavigationStack {
            List {
                Section("Mode") {
                    Picker("Mode", selection: $appearancePreferences.mode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section("Theme") {
                    ForEach(OutboundTheme.allCases) { theme in
                        Button {
                            guideCatalog.setTheme(theme)
                        } label: {
                            HStack(spacing: 14) {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(theme.heroGradient)
                                    .frame(width: 52, height: 34)
                                    .shadow(color: theme.glowColor, radius: 6, y: 2)

                                Text(theme.displayName)
                                    .foregroundStyle(.primary)

                                Spacer()

                                if guideCatalog.selectedTheme == theme {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(theme.accentColor)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(guideCatalog.selectedTheme == theme ? "Selected" : "")
                    }
                }
            }
            .navigationTitle("Appearance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct TodayActivityCompanionSheet: View {
    private static let conversationStorageKey = "today_activity_companion_conversation_v1"

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appNavigationStore: AppNavigationStore
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
        _conversation = State(initialValue: Self.loadConversation())
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
                Text(localizedAppCopy(currentActivity.title)).font(.headline)
                Text(localizedAppCopy(currentActivity.detail)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: currentActivity.id)
    }

    private func send() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        draft = ""
        conversation.append(TodayCompanionLine(text: prompt, isUser: true))

        if let target = AssistantNavigationTarget.infer(from: prompt) {
            appNavigationStore.open(target)
            dismiss()
            return
        }

        if let adjusted = adjustedActivity(for: prompt) {
            currentActivity = adjusted
            onApply(adjusted)
            conversation.append(TodayCompanionLine(
                text: "Done — I updated the activity card to \(adjusted.summaryLabel). You can keep refining it here or start when ready.",
                isUser: false
            ))
            saveConversation()
            return
        }

        isResponding = true
        Task {
            let response = try? await APIClient.shared.sendCompanionTurn(CompanionTurnRequestDTO(
                task: .adaptToday,
                surface: .today,
                prompt: """
                You are the specialist for customizing the single planned activity shown on today's card. Current activity: \(currentActivity.title), \(currentActivity.detail). Request: \(prompt).
                The client can directly apply distances (km, kilometers, mi, miles), durations (minutes or hours), and run effort (recovery, easy, tempo). This request did not contain a change the client could apply. Do not say the card was updated. Briefly clarify what is missing or suggest a concrete adjustment that fits the current activity.
                """,
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
            conversation.append(TodayCompanionLine(
                text: response?.message ?? "Tell me a distance, duration, or effort—like “15 km,” “45 minutes,” or “make it easy”—and I’ll update this activity.",
                isUser: false
            ))
            saveConversation()
            isResponding = false
        }
    }

    private func adjustedActivity(for prompt: String) -> SessionIntent? {
        let normalized = prompt.lowercased()
        let requestedGoal = requestedGoal(in: normalized)
        let effort: (title: String, detail: String, guide: String)? = {
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
        guard requestedGoal != nil || effort != nil else { return nil }

        let distanceMeters: Double?
        let durationSeconds: Int?
        switch requestedGoal {
        case .distance(let meters):
            distanceMeters = meters
            durationSeconds = nil
        case .duration(let seconds):
            distanceMeters = nil
            durationSeconds = seconds
        case nil:
            distanceMeters = currentActivity.targetDistanceMeters
            durationSeconds = currentActivity.targetDurationSeconds
                ?? (currentActivity.targetDistanceMeters == nil ? currentMinutes * 60 : nil)
        }
        let title = localizedAppCopy(effort?.title ?? currentActivity.title)
        let goalDetail: String
        if let distanceMeters {
            goalDetail = distanceLabel(distanceMeters)
        } else {
            goalDetail = "\((durationSeconds ?? currentMinutes * 60) / 60) min"
        }
        return SessionIntent(
            id: "companion-\(UUID().uuidString)",
            sport: currentActivity.sport,
            title: title,
            detail: "\(currentActivity.sport.displayName) · \(goalDetail) · \(localizedAppCopy(effort?.detail ?? "customized"))",
            guideLine: localizedAppCopy(effort?.guide ?? currentActivity.guideLine),
            startLabel: String(localized: "Start activity"),
            targetDistanceMeters: distanceMeters,
            targetDurationSeconds: durationSeconds,
            routeName: currentActivity.routeName,
            workoutSteps: []
        )
    }

    private var currentMinutes: Int {
        let seconds = currentActivity.targetDurationSeconds
            ?? currentActivity.workoutSteps.reduce(0) { $0 + $1.durationSeconds }
        return max(5, seconds / 60)
    }

    private func localizedAppCopy(_ value: String) -> String {
        String(localized: String.LocalizationValue(value))
    }

    private enum RequestedGoal {
        case distance(Double)
        case duration(Int)
    }

    private func requestedGoal(in text: String) -> RequestedGoal? {
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*(kilometers?|kilometres?|kms?|km|miles?|mi|hours?|hrs?|hr|h|minutes?|mins?|min|m)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let valueRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let value = Double(text[valueRange]) else { return nil }

        let unit = String(text[unitRange])
        if unit.hasPrefix("k") {
            guard (0.1...200).contains(value) else { return nil }
            return .distance(value * 1_000)
        }
        if unit == "mi" || unit.hasPrefix("mile") {
            guard (0.1...125).contains(value) else { return nil }
            return .distance(value * 1_609.344)
        }
        if unit.hasPrefix("h") {
            guard (0.1...12).contains(value) else { return nil }
            return .duration(Int((value * 3_600).rounded()))
        }
        guard (1...720).contains(value) else { return nil }
        return .duration(Int((value * 60).rounded()))
    }

    private func distanceLabel(_ meters: Double) -> String {
        let kilometers = meters / 1_000
        return kilometers.rounded() == kilometers
            ? "\(Int(kilometers)) km"
            : String(format: "%.1f km", kilometers)
    }

    private static func loadConversation() -> [TodayCompanionLine] {
        guard let data = UserDefaults.standard.data(forKey: conversationStorageKey) else { return [] }
        return (try? JSONDecoder().decode([TodayCompanionLine].self, from: data)) ?? []
    }

    private func saveConversation() {
        let retained = Array(conversation.suffix(40))
        guard let data = try? JSONEncoder().encode(retained) else { return }
        UserDefaults.standard.set(data, forKey: Self.conversationStorageKey)
    }
}

private struct TodayCompanionLine: Identifiable, Codable {
    let id: UUID
    let text: String
    let isUser: Bool

    init(id: UUID = UUID(), text: String, isUser: Bool) {
        self.id = id
        self.text = text
        self.isUser = isUser
    }
}

enum TodayActivityCustomizer {
    static func adjustedActivity(_ currentActivity: SessionIntent, for prompt: String) -> SessionIntent? {
        let normalized = prompt.lowercased()
        let requestedGoal = requestedGoal(in: normalized)
        let effort: (title: String, detail: String, guide: String)? = {
            if normalized.contains("recovery") || normalized.contains("very easy") {
                return (
                    String(localized: "Recovery run"),
                    String(localized: "very easy"),
                    String(localized: "Keep this restorative and finish feeling better than you started.")
                )
            }
            if normalized.contains("easy") || normalized.contains("easier") {
                return (
                    String(localized: "Easy run"),
                    String(localized: "conversational effort"),
                    String(localized: "Relax the pace and keep the effort conversational.")
                )
            }
            if normalized.contains("tempo") || normalized.contains("harder") {
                return (
                    String(localized: "Tempo run"),
                    String(localized: "comfortably hard"),
                    String(localized: "Stay controlled; this should feel strong, not all-out.")
                )
            }
            return nil
        }()
        guard requestedGoal != nil || effort != nil else { return nil }

        let distanceMeters: Double?
        let durationSeconds: Int?
        switch requestedGoal {
        case .distance(let meters):
            distanceMeters = meters
            durationSeconds = nil
        case .duration(let seconds):
            distanceMeters = nil
            durationSeconds = seconds
        case nil:
            distanceMeters = currentActivity.targetDistanceMeters
            durationSeconds = currentActivity.targetDurationSeconds
                ?? (currentActivity.targetDistanceMeters == nil ? currentMinutes(for: currentActivity) * 60 : nil)
        }

        let goalDetail: String
        if let distanceMeters {
            goalDetail = distanceLabel(distanceMeters)
        } else {
            goalDetail = "\((durationSeconds ?? currentMinutes(for: currentActivity) * 60) / 60) min"
        }
        return SessionIntent(
            id: "companion-\(UUID().uuidString)",
            sport: currentActivity.sport,
            title: effort?.title ?? currentActivity.title,
            detail: "\(currentActivity.sport.displayName) · \(goalDetail) · \(effort?.detail ?? String(localized: "customized"))",
            guideLine: effort?.guide ?? currentActivity.guideLine,
            startLabel: String(localized: "Start activity"),
            targetDistanceMeters: distanceMeters,
            targetDurationSeconds: durationSeconds,
            routeName: currentActivity.routeName,
            workoutSteps: []
        )
    }

    private enum RequestedGoal {
        case distance(Double)
        case duration(Int)
    }

    private static func requestedGoal(in text: String) -> RequestedGoal? {
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*(kilometers?|kilometres?|kms?|km|miles?|mi|hours?|hrs?|hr|h|minutes?|mins?|min|m)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let valueRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let value = Double(text[valueRange]) else { return nil }

        let unit = String(text[unitRange])
        if unit.hasPrefix("k") {
            guard (0.1...200).contains(value) else { return nil }
            return .distance(value * 1_000)
        }
        if unit == "mi" || unit.hasPrefix("mile") {
            guard (0.1...125).contains(value) else { return nil }
            return .distance(value * 1_609.344)
        }
        if unit.hasPrefix("h") {
            guard (0.1...12).contains(value) else { return nil }
            return .duration(Int((value * 3_600).rounded()))
        }
        guard (1...720).contains(value) else { return nil }
        return .duration(Int((value * 60).rounded()))
    }

    private static func currentMinutes(for activity: SessionIntent) -> Int {
        let seconds = activity.targetDurationSeconds
            ?? activity.workoutSteps.reduce(0) { $0 + $1.durationSeconds }
        return max(5, seconds / 60)
    }

    private static func distanceLabel(_ meters: Double) -> String {
        let kilometers = meters / 1_000
        return kilometers.rounded() == kilometers
            ? "\(Int(kilometers)) km"
            : String(format: "%.1f km", kilometers)
    }
}

extension SessionIntent {
    var summaryLabel: String {
        if let meters = targetDistanceMeters {
            let kilometers = meters / 1_000
            let distance = kilometers.rounded() == kilometers
                ? "\(Int(kilometers)) km"
                : String(format: "%.1f km", kilometers)
            return "\(distance) \(sport.displayName.lowercased())"
        }
        if let seconds = targetDurationSeconds {
            return "\(seconds / 60) min \(title.lowercased())"
        }
        return title
    }
}

private struct WorkoutWeatherGuidance: View {
    let snapshot: RunningWeatherSnapshot?

    @ViewBuilder
    var body: some View {
        if let snapshot, snapshot.impact != .none {
            Label(snapshot.guidance ?? snapshot.headline, systemImage: snapshot.symbolName)
                .font(.subheadline)
                .foregroundStyle(weatherColor(snapshot.impact))
                .accessibilityLabel("Workout weather guidance: \(snapshot.guidance ?? snapshot.headline)")
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

struct GlobalConditionsButton: View {
    @EnvironmentObject private var weatherStore: SituationalWeatherStore
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    @State private var showsDetails = false

    var body: some View {
        Button { showsDetails = true } label: {
            if let snapshot = weatherStore.snapshot {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) {
                        Image(systemName: snapshot.symbolName)
                        if let placeName = snapshot.placeName {
                            Text(placeName)
                        }
                        Text(snapshot.temperatureLabel(unitSystem: measurementPreferences.unitSystem))
                            .monospacedDigit()
                    }
                    HStack(spacing: 3) {
                        Image(systemName: snapshot.symbolName)
                        Text(snapshot.temperatureLabel(unitSystem: measurementPreferences.unitSystem))
                            .monospacedDigit()
                    }
                }
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            } else if weatherStore.isLoading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "location.circle")
            }
        }
        .accessibilityLabel(accessibilityLabel)
        .sheet(isPresented: $showsDetails) {
            WeatherDetailSheet(
                snapshot: weatherStore.snapshot,
                errorMessage: weatherStore.errorMessage,
                unitSystem: measurementPreferences.unitSystem,
                onRefresh: { weatherStore.refresh(force: true) }
            )
            .presentationDetents([.medium])
        }
    }

    private var accessibilityLabel: String {
        guard let snapshot = weatherStore.snapshot else { return String(localized: "Local conditions") }
        let place = snapshot.placeName ?? String(localized: "your area")
        return String(localized: "Local conditions in \(place), \(snapshot.temperatureLabel(unitSystem: measurementPreferences.unitSystem)), \(snapshot.headline)")
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
        return String(localized: "\(snapshot.temperatureLabel(unitSystem: unitSystem)) · Wind \(snapshot.windLabel(unitSystem: unitSystem)) · \(precipitation)% rain")
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

    private func changeReasonButton(_ title: LocalizedStringKey, icon: String, reason: ReadinessChoice) -> some View {
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
        switch reason {
        case .tired: String(localized: "Try 15 minutes easy")
        case .sore: String(localized: "Rest today")
        case .shortOnTime: String(localized: "Fit the time you have")
        case .good: String(localized: "Keep today’s run")
        }
    }
    private func recommendationText(_ reason: ReadinessChoice) -> String {
        switch reason {
        case .tired: String(localized: "A short easy run keeps the rhythm without forcing the full workout.")
        case .sore: String(localized: "Skipping one run is better than turning discomfort into an injury.")
        case .shortOnTime: String(localized: "Plainstride will keep this easy and end it at your selected time.")
        case .good: String(localized: "The original workout still fits.")
        }
    }
    private func primaryTitle(_ reason: ReadinessChoice) -> String {
        reason == .sore ? String(localized: "Use rest day") : String(localized: "Start changed run")
    }
    private func primaryIcon(_ reason: ReadinessChoice) -> String { reason == .sore ? "bed.double" : "figure.run" }
}

private struct SimplifiedMeView: View {
    @EnvironmentObject private var appNavigationStore: AppNavigationStore
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var personalizationStore: PersonalizationStore
    @EnvironmentObject private var activityStore: ActivityStore
    @EnvironmentObject private var trainingPlanStore: TrainingPlanStore
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    @EnvironmentObject private var cycleAwareStore: CycleAwareStore
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @EnvironmentObject private var gearStore: GearStore
    @EnvironmentObject private var healthAuthorizationStore: HealthAuthorizationStore
    @EnvironmentObject private var healthImportStore: HealthImportStore
    @State private var profile: AppUserProfileDTO?
    @State private var trainingProfileSex: TrainingProfileSex?
    @State private var showsCycleAwareCheckIn = false
    @State private var showsManualWorkoutEntry = false
    @State private var manualWorkoutToast: String?
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                LazyVStack(spacing: OutboundSpacing.standard) {
                    NavigationLink {
                        SimplifiedProfileEditorView(initialProfile: profile) { profile = $0 }
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
                    NavigationLink {
                        CommunityRouteLibraryView(mode: .mine)
                    } label: {
                        OutboundCard {
                            HStack {
                                Label(String(localized: "library.my_routes", defaultValue: "My Routes"), systemImage: "map.fill").font(.headline)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
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
                                meStat(measurementPreferences.unitSystem.distanceString(meters: weekDistance, fractionDigits: 1), String(localized: "Distance"))
                                meStat(weekDuration.formatted(), String(localized: "Time"))
                            }
                            AIExplanationView(text: weekGuideLine)
                        }
                    }
                    if showsCycleAwareGuidance {
                        OutboundCard {
                            VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                                Toggle("Cycle-aware guidance", isOn: $cycleAwareStore.isEnabled)
                                    .onChange(of: cycleAwareStore.isEnabled) { wasEnabled, isEnabled in
                                        if !wasEnabled && isEnabled {
                                            showsCycleAwareCheckIn = true
                                        }
                                    }
                                if cycleAwareStore.isEnabled {
                                    Button {
                                        showsCycleAwareCheckIn = true
                                    } label: {
                                        HStack {
                                            Label("Add today’s private check-in", systemImage: "heart.text.clipboard")
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.primary)
                                }
                            }
                        }
                    }
                    OutboundCard {
                        VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                            HStack {
                                Text(String(localized: "me.recent.title", defaultValue: "RECENT")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Spacer()
                                HStack(spacing: 6) {
                                    Button {
                                        showsManualWorkoutEntry = true
                                    } label: {
                                        Image(systemName: "plus")
                                            .frame(width: 44, height: 44)
                                    }
                                    .font(.subheadline.weight(.semibold))
                                    .accessibilityLabel(String(localized: "me.recent.add", defaultValue: "Add workout"))
                                    Button {
                                        Task { await openHealthImport() }
                                    } label: {
                                        Image(systemName: "square.and.arrow.down")
                                            .frame(width: 44, height: 44)
                                    }
                                    .font(.subheadline.weight(.semibold))
                                    .accessibilityLabel(String(localized: "me.recent.import", defaultValue: "Import from Apple Health"))
                                    NavigationLink(String(localized: "me.recent.all", defaultValue: "All")) { ActivityHistoryView() }
                                        .font(.subheadline)
                                        .padding(.horizontal, 8)
                                }
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
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SavedActivity.self) { ActivityDetailView(activity: $0) }
            .navigationDestination(for: AssistantNavigationTarget.self) { target in
                assistantDestination(for: target)
            }
            .task { await loadMeData() }
            .onAppear {
                handlePendingAssistantTarget(appNavigationStore.pendingAssistantTarget)
            }
            .onChange(of: appNavigationStore.pendingAssistantTarget) { _, target in
                handlePendingAssistantTarget(target)
            }
            .sheet(isPresented: $showsCycleAwareCheckIn) {
                NavigationStack {
                    CycleAwareView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showsCycleAwareCheckIn = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $showsManualWorkoutEntry) {
                ManualWorkoutEntryView { _ in showManualWorkoutToast() }
                    .environmentObject(activityStore)
                    .environmentObject(gearStore)
                    .environmentObject(measurementPreferences)
            }
            .overlay(alignment: .top) {
                if let manualWorkoutToast {
                    Text(manualWorkoutToast)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    GlobalConditionsButton()
                    NavigationLink {
                        SimplifiedSettingsView(
                            profile: profile,
                            trainingProfileSex: trainingProfileSex,
                            onProfileUpdated: { profile = $0 },
                            onTrainingProfileUpdated: { trainingProfileSex = $0.sexAtBirth }
                        )
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

    private func showManualWorkoutToast() {
        withAnimation { manualWorkoutToast = String(localized: "Workout added") }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation { manualWorkoutToast = nil }
        }
    }

    private func openHealthImport() async {
        if healthAuthorizationStore.snapshot.requestState == .notRequested {
            await healthAuthorizationStore.requestAuthorization()
        }
        await healthImportStore.checkForNewWorkouts(
            existingExternalIDs: activityStore.importedHealthExternalIDs,
            presentWhenFound: true
        )
        if healthImportStore.importCandidates.isEmpty {
            withAnimation {
                manualWorkoutToast = healthImportStore.lastErrorMessage
                    ?? String(localized: "health.import.none", defaultValue: "No new Apple Health workouts")
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                withAnimation { manualWorkoutToast = nil }
            }
        }
    }

    @ViewBuilder
    private func assistantDestination(for target: AssistantNavigationTarget) -> some View {
        Group {
            switch target.destination {
            case .settingsAppleHealth:
                AppleHealthSettingsView()
            case .settingsAppleMusic:
                Form {
                    Section("Apple Music") {
                        Text("Choose and connect music from the Music section before starting an activity.")
                    }
                }
                .navigationTitle("Music")
            case .guideSettings:
                GuideSelectionView()
            case .activityHistory:
                ActivityHistoryView()
            case .settings:
                SimplifiedSettingsView(
                    profile: profile,
                    trainingProfileSex: trainingProfileSex,
                    onProfileUpdated: { profile = $0 },
                    onTrainingProfileUpdated: { trainingProfileSex = $0.sexAtBirth }
                )
            case .appearance:
                ThemeChooserView()
            case .social, .today, .me:
                EmptyView()
            }
        }
        .assistantHighlightAnchor(target.anchorID ?? target.definition.defaultAnchorID)
    }

    private func handlePendingAssistantTarget(_ target: AssistantNavigationTarget?) {
        guard let target else { return }
        guard ![.social, .today, .me].contains(target.destination) else { return }
        navigationPath.append(target)
        appNavigationStore.consume()
    }

    private func loadMeData() async {
        async let profileLoad: Void = loadProfile()
        async let trainingProfileLoad: Void = loadTrainingProfile()
        _ = await (profileLoad, trainingProfileLoad)
    }

    private func loadTrainingProfile() async {
        trainingProfileSex = try? await APIClient.shared.fetchTrainingProfile().sexAtBirth
    }

    private var showsCycleAwareGuidance: Bool {
        effectiveSexIsMale == false
    }

    private var effectiveSexIsMale: Bool {
        if let trainingProfileSex {
            return trainingProfileSex == .male
        }
        return onboardingStore.completedProfile?.bodyProfile.sex == .male
    }

    private var planTitle: String {
        guard let plan = trainingPlanStore.activePlan else { return String(localized: "Building your running rhythm") }
        let week = trainingPlanStore.currentWeek?.currentWeekIndex ?? 1
        return String(localized: "\(plan.localizedTitle) · Week \(week) of \(plan.durationWeeks)")
    }

    private var planDetail: String { String(localized: "\(weekTarget) runs per week") }
    private var weekTarget: Int { trainingPlanStore.currentWeek?.targetSessions ?? trainingPlanStore.activePlan?.sessionsPerWeek ?? 3 }
    private var weekRuns: Int { trainingPlanStore.currentWeek?.completedSessions ?? currentWeekActivities.count }
    private var weekDistance: Double { currentWeekActivities.reduce(0) { $0 + $1.distanceM } }
    private var weekDuration: Int { currentWeekActivities.reduce(0) { $0 + $1.durationSecs } }
    private var weekGuideLine: String {
        if let line = trainingPlanStore.currentWeek?.guideLine { return line }
        if weekRuns >= weekTarget { return String(localized: "You completed this week’s rhythm.") }
        let remaining = max(0, weekTarget - weekRuns)
        return remaining == 1
            ? String(localized: "One comfortable run completes the week.")
            : String(localized: "\(remaining) comfortable runs complete the week.")
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
    @EnvironmentObject private var appearancePreferences: AppearancePreferences
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var guideCatalog: GuideCatalogStore
    @EnvironmentObject private var onboardingStore: OnboardingStore
    let profile: AppUserProfileDTO?
    let trainingProfileSex: TrainingProfileSex?
    let onProfileUpdated: (AppUserProfileDTO) -> Void
    let onTrainingProfileUpdated: (TrainingProfileDTO) -> Void
    @State private var confirmsSignOut = false
    @State private var confirmsAccountDeletion = false

    var body: some View {
        Form {
            Section("Account") {
                if let label = authStore.currentLoginLabel {
                    LabeledContent("Signed in as", value: label)
                }
                if let error = authStore.authError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    confirmsSignOut = true
                }
            }
            Section("Profile") {
                NavigationLink {
                    BioSettingsView(
                        profile: profile,
                        onProfileUpdated: onProfileUpdated,
                        onTrainingProfileUpdated: onTrainingProfileUpdated
                    )
                } label: {
                    Label("Bio", systemImage: "person.crop.circle")
                }
                NavigationLink {
                    CompanionMemoryView()
                } label: {
                    Label("What Plainstride knows", systemImage: "brain.head.profile")
                }
            }
            Section("Live Guidance") {
                NavigationLink {
                    GuideSelectionView()
                } label: {
                    LabeledContent {
                        Text(guideCatalog.selectedVoice.displayName)
                            .foregroundStyle(.secondary)
                    } label: {
                        Label("Voice", systemImage: "waveform.circle")
                    }
                }
            }
            Section("Appearance") {
                Picker("Mode", selection: $appearancePreferences.mode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                NavigationLink {
                    ThemeChooserView()
                } label: {
                    LabeledContent {
                        Text(guideCatalog.selectedTheme.displayName)
                            .foregroundStyle(.secondary)
                    } label: {
                        Label {
                            Text("Theme")
                        } icon: {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(guideCatalog.selectedTheme.heroGradient)
                                .frame(width: 24, height: 18)
                                .shadow(color: guideCatalog.selectedTheme.glowColor, radius: 3, y: 1)
                        }
                    }
                }
            }
            Section("Units") {
                Picker("Measurement", selection: $measurementPreferences.unitSystem) {
                    ForEach(MeasurementUnitSystem.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            if effectiveSexIsMale == false {
                Section("Health & body") {
                    NavigationLink("Cycle-aware guidance") { CycleAwareView() }
                }
            }
            Section {
                Button {
                    FeedbackTrigger.present(currentPage: "Settings")
                } label: {
                    Label("Send feedback", systemImage: "ladybug")
                }
            } header: {
                Text("Help")
            } footer: {
                Text("You can also shake your iPhone twice when an activity isn’t recording.")
            }
            Section("Gear") {
                GearSettingsCard()
            }
            Section("Integrations") {
                NavigationLink {
                    AppleHealthSettingsView()
                } label: {
                    Label("Apple Health", systemImage: "heart.text.square")
                }
            }
            Section("Safety") {
                NavigationLink {
                    SafetyContactsSettingsView()
                } label: {
                    Label("Trusted contacts", systemImage: "person.crop.circle.badge.checkmark")
                }
            }
            #if DEBUG
            Section("Debug") {
                Button {
                    onboardingStore.restartForDebug()
                } label: {
                    Label("Run onboarding flow", systemImage: "sparkles")
                }
                Text("Presents the new-user flow again without signing out.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            #endif
            Section {
                Text("Plainstride keeps private health details on this device and never shows them in Together.")
                    .font(.footnote).foregroundStyle(.secondary)
                LabeledContent("Version", value: appVersion)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Delete account") {
                    confirmsAccountDeletion = true
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .disabled(authStore.isBusy)
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Sign out of Plainstride?", isPresented: $confirmsSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { authStore.signOut() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Permanently delete your account?",
            isPresented: $confirmsAccountDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete Account and Data", role: .destructive) {
                Task { await authStore.deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your Plainstride account, synced activities, plans, profile, social data, and locally stored Plainstride data. This cannot be undone.")
        }
    }

    private var effectiveSexIsMale: Bool {
        if let trainingProfileSex {
            return trainingProfileSex == .male
        }
        return onboardingStore.completedProfile?.bodyProfile.sex == .male
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(version) (\($0))" } ?? version
    }
}

private struct BioSettingsView: View {
    let profile: AppUserProfileDTO?
    let onProfileUpdated: (AppUserProfileDTO) -> Void
    let onTrainingProfileUpdated: (TrainingProfileDTO) -> Void

    var body: some View {
        Form {
            Section {
                NavigationLink("Name, photo, and bio") {
                    SimplifiedProfileEditorView(initialProfile: profile, onProfileUpdated: onProfileUpdated)
                }
                NavigationLink("Training details") {
                    TrainingProfileEditorView(onProfileUpdated: onTrainingProfileUpdated)
                }
            } footer: {
                Text("Your public bio and private personalization details live together here.")
            }
        }
        .navigationTitle("Bio")
    }
}

private struct TrainingProfileEditorView: View {
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    let onProfileUpdated: (TrainingProfileDTO) -> Void
    @State private var sexAtBirth: TrainingProfileSex?
    @State private var hasBirthDate = false
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    @State private var heightText = ""
    @State private var weightText = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var toast: ProfileToast?

    var body: some View {
        Form {
            Section {
                Text("These optional details help Plainstride personalize training load, recovery advice, and estimates. They stay private and are never shown in Together.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Sex assigned at birth", selection: $sexAtBirth) {
                    Text("Not provided").tag(nil as TrainingProfileSex?)
                    ForEach(TrainingProfileSex.allCases) { value in
                        Text(value.title).tag(value as TrainingProfileSex?)
                    }
                }
                Toggle("Add birthday", isOn: $hasBirthDate)
                if hasBirthDate {
                    DatePicker("Birthday", selection: $birthDate, in: oldestBirthDate...latestBirthDate, displayedComponents: .date)
                }
            } header: {
                Text("About you")
            } footer: {
                Text("Birthday is stored instead of age so your training profile stays accurate over time.")
            }

            Section {
                TextField(heightLabel, text: $heightText)
                    .keyboardType(.decimalPad)
                TextField(weightLabel, text: $weightText)
                    .keyboardType(.decimalPad)
            } header: {
                Text("Body measurements")
            } footer: {
                Text("Leave a field blank to remove it. You can update these values whenever they change.")
            }
        }
        .navigationTitle("Training profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                    .disabled(isLoading || isSaving || !measurementsAreValid)
            }
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
    }

    private var usesMetric: Bool { measurementPreferences.unitSystem == .metric }
    private var heightLabel: String { usesMetric ? String(localized: "Height (cm)") : String(localized: "Height (in)") }
    private var weightLabel: String { usesMetric ? String(localized: "Weight (kg)") : String(localized: "Weight (lb)") }
    private var oldestBirthDate: Date { Calendar.current.date(byAdding: .year, value: -120, to: Date()) ?? .distantPast }
    private var latestBirthDate: Date { Date() }

    private var measurementsAreValid: Bool {
        let heightValid = parsedMeasurement(heightText)
            .map { usesMetric ? (90...250).contains($0) : (35...98.5).contains($0) }
            ?? heightText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let weightValid = parsedMeasurement(weightText)
            .map { usesMetric ? (25...350).contains($0) : (55...772).contains($0) }
            ?? weightText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return heightValid && weightValid
    }

    private func load() async {
        defer { isLoading = false }
        do {
            apply(try await APIClient.shared.fetchTrainingProfile())
        } catch {
            showToast(String(localized: "Training profile could not be loaded."), style: .error)
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let formatter = Self.birthDateFormatter
            let request = TrainingProfileUpdateDTO(
                sexAtBirth: sexAtBirth,
                birthDate: hasBirthDate ? formatter.string(from: birthDate) : nil,
                heightCentimeters: parsedMeasurement(heightText).map { usesMetric ? $0 : $0 * 2.54 },
                weightKilograms: parsedMeasurement(weightText).map { usesMetric ? $0 : $0 * 0.45359237 }
            )
            let profile = try await APIClient.shared.updateTrainingProfile(request)
            apply(profile)
            onProfileUpdated(profile)
            showToast(String(localized: "Training profile saved"), style: .success)
        } catch {
            showToast(String(localized: "Could not save training profile. Try again."), style: .error)
        }
    }

    private func showToast(_ text: String, style: ProfileToast.Style) {
        toast = ProfileToast(text: text, style: style)
    }

    private func apply(_ profile: TrainingProfileDTO) {
        sexAtBirth = profile.sexAtBirth
        if let value = profile.birthDate, let date = Self.birthDateFormatter.date(from: value) {
            birthDate = date
            hasBirthDate = true
        } else {
            hasBirthDate = false
        }
        heightText = formatted(profile.heightCentimeters.map { usesMetric ? $0 : $0 / 2.54 })
        weightText = formatted(profile.weightKilograms.map { usesMetric ? $0 : $0 / 0.45359237 })
    }

    private func parsedMeasurement(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
    }

    private func formatted(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private static let birthDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct SimplifiedProfileEditorView: View {
    @EnvironmentObject private var authStore: AuthStore
    var onProfileUpdated: ((AppUserProfileDTO) -> Void)? = nil
    @State private var displayName = ""
    @State private var bio = ""
    @State private var contactEmail = ""
    @State private var contactPhone = ""
    @State private var savedContactEmail = ""
    @State private var savedContactPhone = ""
    @State private var isEditingContactDetails = false
    @State private var username = ""
    @State private var avatarUrl = UserAvatarPersistence.url(for: AuthStore.currentUserId)
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var isUploadingAvatar = false
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var toast: ProfileToast?

    init(
        initialProfile: AppUserProfileDTO? = nil,
        onProfileUpdated: ((AppUserProfileDTO) -> Void)? = nil
    ) {
        self.onProfileUpdated = onProfileUpdated
        _displayName = State(initialValue: initialProfile?.displayName ?? "")
        _bio = State(initialValue: initialProfile?.bio ?? "")
        _contactEmail = State(initialValue: initialProfile?.contactEmail ?? "")
        _contactPhone = State(initialValue: initialProfile?.contactPhone ?? "")
        _savedContactEmail = State(initialValue: initialProfile?.contactEmail ?? "")
        _savedContactPhone = State(initialValue: initialProfile?.contactPhone ?? "")
        _username = State(initialValue: initialProfile?.username ?? "")
        _avatarUrl = State(
            initialValue: initialProfile?.avatarUrl
                ?? UserAvatarPersistence.url(for: AuthStore.currentUserId)
        )
        _isLoading = State(initialValue: initialProfile == nil)
    }

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
            Section {
                if isEditingContactDetails || savedContactEmail.isEmpty {
                    TextField("Email", text: $contactEmail)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                } else {
                    LabeledContent("Email", value: savedContactEmail)
                }
                if isEditingContactDetails || savedContactPhone.isEmpty {
                    TextField("Phone number", text: $contactPhone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                } else {
                    LabeledContent("Phone number", value: savedContactPhone)
                }
            } header: {
                HStack {
                    Text("Contact details")
                    Spacer()
                    if hasSavedContactDetails && !isEditingContactDetails {
                        Button("Edit") { isEditingContactDetails = true }
                            .textCase(nil)
                    }
                }
            } footer: {
                Text("These profile details do not change how you sign in.")
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
            contactEmail = profile.contactEmail ?? ""
            contactPhone = profile.contactPhone ?? ""
            savedContactEmail = contactEmail
            savedContactPhone = contactPhone
            isEditingContactDetails = false
            username = profile.username
            avatarUrl = profile.avatarUrl
            UserAvatarPersistence.save(profile.avatarUrl, for: AuthStore.currentUserId)
        } catch {
            displayName = authStore.currentLoginLabel ?? ""
            showToast(String(localized: "Profile could not be loaded."), style: .error)
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let profile = try await APIClient.shared.updateMyProfile(
                AppUserProfileUpdateDTO(
                    displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                    bio: nilIfEmpty(bio),
                    contactEmail: nilIfEmpty(contactEmail),
                    contactPhone: nilIfEmpty(contactPhone)
                )
            )
            displayName = profile.displayName
            bio = profile.bio ?? ""
            contactEmail = profile.contactEmail ?? ""
            contactPhone = profile.contactPhone ?? ""
            savedContactEmail = contactEmail
            savedContactPhone = contactPhone
            isEditingContactDetails = false
            avatarUrl = profile.avatarUrl
            UserAvatarPersistence.save(profile.avatarUrl, for: AuthStore.currentUserId)
            onProfileUpdated?(profile)
            showToast(String(localized: "Profile saved"), style: .success)
        } catch {
            showToast(String(localized: "Could not save profile. Try again."), style: .error)
        }
    }

    private var hasSavedContactDetails: Bool {
        !savedContactEmail.isEmpty || !savedContactPhone.isEmpty
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
                showToast(String(localized: "That photo could not be used."), style: .error)
                return
            }
            let profile = try await APIClient.shared.uploadMyAvatar(jpegData: jpegData)
            avatarUrl = profile.avatarUrl
            UserAvatarPersistence.save(profile.avatarUrl, for: AuthStore.currentUserId)
            if let avatarUrl = profile.avatarUrl, let uploadedImage = UIImage(data: jpegData) {
                AvatarImageCache.shared.store(uploadedImage, for: avatarUrl)
            }
            onProfileUpdated?(profile)
            showToast(String(localized: "Profile photo updated"), style: .success)
        } catch {
            showToast(String(localized: "Could not upload photo. Try again."), style: .error)
        }
    }

    private func showToast(_ text: String, style: ProfileToast.Style) {
        toast = ProfileToast(text: text, style: style)
    }

    private func nilIfEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
    @StateObject private var loader: AvatarImageLoader

    init(url: String?, name: String, size: CGFloat, isProfileLoading: Bool = false) {
        self.url = url
        self.name = name
        self.size = size
        self.isProfileLoading = isProfileLoading
        _loader = StateObject(wrappedValue: AvatarImageLoader(url: url))
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
        .task(id: url) { await loader.load(url: url) }
    }

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
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
        case .low: String(localized: "Learning")
        case .medium: String(localized: "Some confidence")
        case .high: String(localized: "High confidence")
        }
    }
}

#Preview {
    SimplifiedAppShell(
        selection: .constant(.today),
        activitySessionState: .idle,
        activityElapsedSeconds: 0,
        activeSport: nil,
        feedbackPage: .constant("Today"),
        customizedTodayIntent: .constant(nil),
        activityLaunchSurface: AnyView(EmptyView()),
        launchGoalMode: .planned,
        onContextualStart: {},
        onStartRun: { _ in }
    )
        .environmentObject(ActivityStore())
        .environmentObject(AssistantStore())
        .environmentObject(AppNavigationStore())
        .environmentObject(GuideCatalogStore())
        .environmentObject(DailyCheckInStore())
        .environmentObject(PersonalizationStore())
        .environmentObject(TrainingPlanStore())
        .environmentObject(TogetherStore())
        .environmentObject(MeasurementPreferences())
        .environmentObject(CycleAwareStore())
}
