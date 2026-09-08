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

private struct AssistantLauncherButton: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.analyticsManager) private var analyticsManager
    let accentColor: Color
    let analyticsDestination: String
    let onOpen: () -> Void

    @State private var scale = 1.0
    @State private var shimmerOpacity = 0.0
    @State private var rotation = 0.0
    @State private var ringScale = 0.72
    @State private var ringOpacity = 0.0
    @State private var hasTrackedForeground = false
    @State private var hasTrackedAnimation = false
    @State private var hasEvaluatedInitialScene = false

    var body: some View {
        Button {
            track(.assistantLauncherOpened, entrySource: "persistent_launcher")
            onOpen()
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 2)
                    .scaleEffect(ringScale)
                    .opacity(ringOpacity)

                Image(systemName: "sparkles")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(rotation))

                Image(systemName: "sparkles")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .scaleEffect(1.28)
                    .opacity(shimmerOpacity)
                    .blur(radius: 0.8)
            }
            .frame(width: 48, height: 48)
            .background(accentColor.gradient, in: Circle())
            .overlay {
                Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
            .scaleEffect(scale)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Open assistant"))
        .accessibilityHint(String(localized: "Get help with this page or anywhere in Plainstride"))
        .task(id: scenePhase) {
            await runAnimationLoop()
        }
    }

    @MainActor
    private func runAnimationLoop() async {
        let entrySource = hasEvaluatedInitialScene ? "foreground" : "app_shell"
        hasEvaluatedInitialScene = true

        guard scenePhase == .active else {
            hasTrackedForeground = false
            hasTrackedAnimation = false
            resetVisualState()
            return
        }

        if !hasTrackedForeground {
            hasTrackedForeground = true
            track(.assistantLauncherEligibleExposure, entrySource: entrySource)
        }

        do {
            try await Task.sleep(for: .milliseconds(500))
        } catch {
            return
        }

        while !Task.isCancelled, scenePhase == .active {
            if !hasTrackedAnimation {
                hasTrackedAnimation = true
                track(.assistantLauncherAnimationShown, entrySource: "foreground_loop")
            }

            withAnimation(.easeOut(duration: 0.32)) {
                scale = 1.17
                rotation = -10
                shimmerOpacity = 0.9
                ringScale = 0.94
                ringOpacity = 0.82
            }
            do {
                try await Task.sleep(for: .milliseconds(320))
            } catch {
                return
            }

            withAnimation(.spring(duration: 0.65, bounce: 0.38)) {
                scale = 1.0
                rotation = 0
                shimmerOpacity = 0.0
                ringScale = 1.55
                ringOpacity = 0.0
            }
            do {
                try await Task.sleep(for: .milliseconds(650))
            } catch {
                return
            }

            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                ringScale = 0.72
            }
            do {
                try await Task.sleep(for: .milliseconds(2_800))
            } catch {
                return
            }
        }
    }

    @MainActor
    private func resetVisualState() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            scale = 1.0
            shimmerOpacity = 0.0
            rotation = 0.0
            ringScale = 0.72
            ringOpacity = 0.0
        }
    }

    private func track(_ name: ProductEventName, entrySource: String) {
        let event = ProductAnalyticsEvent(name, properties: [
            .destination: .string(analyticsDestination),
            .entrySource: .string(entrySource)
        ])
        Task { await analyticsManager?.track(event) }
    }
}

struct SimplifiedAppShell: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.outboundTheme) private var theme
    @Environment(\.analyticsManager) private var analyticsManager
    @EnvironmentObject private var guideCatalog: GuideCatalogStore
    @EnvironmentObject private var activityStore: ActivityStore
    @EnvironmentObject private var dailyCheckInStore: DailyCheckInStore
    @EnvironmentObject private var trainingPlanStore: TrainingPlanStore
    @EnvironmentObject private var weatherStore: SituationalWeatherStore
    @EnvironmentObject private var appNavigationStore: AppNavigationStore
    @EnvironmentObject private var pushNotifications: PushNotificationCoordinator
    @EnvironmentObject private var communityRouteStore: CommunityRouteStore
    @EnvironmentObject private var circleStore: CircleStore
    @EnvironmentObject private var socialStore: TogetherStore
    @Binding var selection: SimplifiedAppTab
    let activitySessionState: ActivitySessionPortalState
    let isActivityFullscreenVisible: Bool
    let activityElapsedSeconds: Int
    let activeSport: SportType?
    @Binding var feedbackPage: String
    @Binding var customizedTodayIntent: SessionIntent?
    let activityLaunchSurface: AnyView
    let launchGoalMode: SessionGoalMode
    let showsActivityOverflowMenu: Bool
    let preActivityPhoto: UIImage?
    let preActivityRoute: PreparedRoute?
    let onContextualStart: () -> Void
    let onPreActivityPhotoAction: () -> Void
    let onRouteSelectionAction: () -> Void
    let onRouteRemovalAction: () -> Void
    let onStartRun: (SessionIntent?) -> Void
    @State private var showsAssistant = false
    @State private var selectedRouteName: String?
    @State private var showsPlanDetails = false
    @State private var showsPlanPicker = false
    @State private var selectedPlanRecommendation: TrainingPlanRecommendation?
    @State private var replacementPlanRecommendation: TrainingPlanRecommendation?
    @State private var completionCircle: CircleDTO?
    @State private var circleToast: String?
    @State private var connectionToast: String?

    var body: some View {
        TabView(selection: $selection) {
            SocialHomeView()
                .tag(SimplifiedAppTab.social)
                .tabItem { Label("Social", systemImage: "person.2") }

            SimplifiedTodayView(
                isSelected: selection == .today,
                activitySessionState: activitySessionState,
                isActivityFullscreenVisible: isActivityFullscreenVisible,
                activityElapsedSeconds: activityElapsedSeconds,
                activeSport: activeSport,
                customizedRunIntent: $customizedTodayIntent,
                selectedRouteName: $selectedRouteName,
                activityLaunchSurface: activityLaunchSurface,
                launchGoalMode: launchGoalMode,
                showsActivityOverflowMenu: showsActivityOverflowMenu,
                preActivityPhoto: preActivityPhoto,
                preActivityRoute: preActivityRoute,
                onPreActivityPhotoAction: onPreActivityPhotoAction,
                onRouteSelectionAction: onRouteSelectionAction,
                onRouteRemovalAction: onRouteRemovalAction,
                onOpenPlan: { openPlanManagement(from: "today_planned_card_plan") },
                onChangePlan: { presentPlanPicker(from: "today_planned_card_change") },
                onStartRun: onStartRun
            )
                .assistantHighlightAnchor("today.primary-action")
                .tag(SimplifiedAppTab.today)
                .tabItem { Label(String(localized: "Today"), systemImage: "sparkles") }

            SimplifiedMeView(
                onOpenPlan: { openPlanManagement(from: "me_current_focus") }
            )
                .tag(SimplifiedAppTab.me)
                .tabItem { Label("Me", systemImage: "person.crop.circle") }
        }
        .tint(guideCatalog.selectedTheme.accentColor)
        .background {
            NativeContextualTabBarBridge(
                selectedTab: selection,
                showsStart: selection == .today
                    && activitySessionState == .idle
                    && !isActivityFullscreenVisible,
                actionColor: theme.actionColor,
                onSelect: selectTabWithoutAnimation,
                onStart: onContextualStart
            )
            .frame(width: 0, height: 0)
        }
        .onChange(of: selection, initial: true) { _, tab in
            feedbackPage = tab.feedbackPageName
        }
        .overlay(alignment: .bottom) {
            HStack {
                assistantLaunchButton
                    .opacity(isActivityFullscreenVisible ? 0 : 1)
                    .allowsHitTesting(!isActivityFullscreenVisible)
                    .accessibilityHidden(isActivityFullscreenVisible)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
        .overlay(alignment: .top) {
            if let toast = circleToast ?? connectionToast {
                Label(
                    toast,
                    systemImage: circleToast == nil ? "person.badge.plus" : "person.3.fill"
                )
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: circleToast)
        .animation(.snappy, value: connectionToast)
        .task(id: circleToast) {
            guard circleToast != nil else { return }
            try? await Task.sleep(for: .seconds(3.6))
            guard !Task.isCancelled else { return }
            circleToast = nil
        }
        .task(id: connectionToast) {
            guard connectionToast != nil else { return }
            try? await Task.sleep(for: .seconds(3.6))
            guard !Task.isCancelled else { return }
            connectionToast = nil
        }
        .fullScreenCover(item: $completionCircle) { circle in
            CircleCompletionCelebrationView(circle: circle) {
                completionCircle = nil
                Task {
                    if await circleStore.presentCompletionIfNeeded(for: circle) {
                        await analyticsManager?.track(.init(.circleWeeklyFocusCompleted, properties: [
                            .selectionType: .string(circle.week.focusMode),
                            .participantCountBucket: .string(ProductAnalyticsBucket.count(circle.memberCount))
                        ]))
                    }
                }
            }
        }
        .ignoresSafeArea(
            .keyboard,
            edges: selection == .today && activitySessionState == .idle ? .bottom : []
        )
        .sheet(isPresented: $showsAssistant) {
            AssistantView(
                screenName: assistantScreenName,
                isRecordingActive: activitySessionState != .idle,
                focusedActivity: selection == .today ? customizedTodayIntent ?? trainingPlanStore.todaySuggestion?.suggestedSession.intent : nil,
                onApplyFocusedActivity: { customizedTodayIntent = $0 },
                analyticsDestination: assistantAnalyticsDestination
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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
                                    presentPlanPicker(from: "plan_details_change")
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
        .onChange(of: circleStore.pendingCompletion?.id, initial: true) { _, _ in
            guard completionCircle == nil else { return }
            circleToast = nil
            completionCircle = circleStore.pendingCompletion
        }
        .onChange(of: circleStore.toastMessage) { _, message in
            guard completionCircle == nil, let message else { return }
            circleToast = message
            circleStore.clearToast()
        }
        .onChange(of: socialStore.connectionLinkToast, initial: true) { _, message in
            guard let message else { return }
            selection = .social
            connectionToast = message
            socialStore.clearConnectionLinkToast()
        }
        .onChange(of: preActivityRoute) { _, route in
            selectedRouteName = route?.name
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                weatherStore.refreshForToday()
            }
        }
        .onChange(of: isActivityFullscreenVisible) { _, isVisible in
            if isVisible {
                showsAssistant = false
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

    private var assistantLaunchButton: some View {
        AssistantLauncherButton(
            accentColor: guideCatalog.selectedTheme.accentColor,
            analyticsDestination: assistantAnalyticsDestination
        ) {
            showsAssistant = true
        }
    }

    private var assistantAnalyticsDestination: String {
        switch selection {
        case .social: "social"
        case .today: "today"
        case .me: "me"
        }
    }

    private func selectTabWithoutAnimation(_ tab: SimplifiedAppTab) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selection = tab
        }
    }

    private func openPlanManagement(from entrySource: String) {
        if trainingPlanStore.activePlan == nil {
            presentPlanPicker(from: entrySource)
        } else {
            trackPlanningSurfaceOpened("plan_details", entrySource: entrySource)
            showsPlanDetails = true
        }
    }

    private func presentPlanPicker(from entrySource: String) {
        trainingPlanStore.prepareRecommendations(
            activities: activityStore.activities,
            readiness: dailyCheckInStore.readiness,
            phase: DailyMotivationEngine.phase(for: activityStore.activities)
        )
        trackPlanningSurfaceOpened("plan_picker", entrySource: entrySource)
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
            presentPlanPicker(from: "recommendation_more_plans")
        }
    }

    private func activatePlan(_ recommendation: TrainingPlanRecommendation) {
        trainingPlanStore.acceptRecommendation(recommendation)
        replacementPlanRecommendation = nil
        selectedPlanRecommendation = nil
        showsPlanPicker = false
    }

    private func trackPlanningSurfaceOpened(_ surface: String, entrySource: String) {
        Task {
            await analyticsManager?.track(.init(.planningSurfaceOpened, properties: [
                .sourceType: .string(surface),
                .entrySource: .string(entrySource),
            ]))
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
            // Hide Today-owned overlays before UIKit lays out the incoming tab.
            onSelect?(targetTab)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            UIView.performWithoutAnimation {
                tabBarController.selectedIndex = targetIndex
            }
            CATransaction.commit()
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

private enum ActivityOverflowAction {
    case photo
    case route
    case removeRoute
}

private struct SimplifiedTodayView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.outboundTheme) private var theme
    @Environment(\.analyticsManager) private var analyticsManager
    @EnvironmentObject private var activityStore: ActivityStore
    @EnvironmentObject private var dailyCheckInStore: DailyCheckInStore
    @EnvironmentObject private var personalizationStore: PersonalizationStore
    @EnvironmentObject private var trainingPlanStore: TrainingPlanStore
    @EnvironmentObject private var weatherStore: SituationalWeatherStore
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    @EnvironmentObject private var socialStore: TogetherStore
    @EnvironmentObject private var circleStore: CircleStore
    @EnvironmentObject private var guideCatalog: GuideCatalogStore
    @AppStorage("theme_discovery_tip_dismissed_v1") private var hasDismissedThemeTip = false
    @AppStorage("theme_discovery_tip_presentation_count_v1") private var themeTipPresentationCount = 0
    @AppStorage("activity_overflow_tip_dismissed_v1") private var hasDismissedActivityOverflowTip = false
    @AppStorage("activity_overflow_tip_presentation_count_v1") private var activityOverflowTipPresentationCount = 0
    @AppStorage("today_planned_workout_card_minimized_v1") private var isPlannedWorkoutCardMinimized = false
    let isSelected: Bool
    let activitySessionState: ActivitySessionPortalState
    let isActivityFullscreenVisible: Bool
    let activityElapsedSeconds: Int
    let activeSport: SportType?
    @Binding var customizedRunIntent: SessionIntent?
    @Binding var selectedRouteName: String?
    let activityLaunchSurface: AnyView
    let launchGoalMode: SessionGoalMode
    let showsActivityOverflowMenu: Bool
    let preActivityPhoto: UIImage?
    let preActivityRoute: PreparedRoute?
    let onPreActivityPhotoAction: () -> Void
    let onRouteSelectionAction: () -> Void
    let onRouteRemovalAction: () -> Void
    let onOpenPlan: () -> Void
    let onChangePlan: () -> Void
    let onStartRun: (SessionIntent?) -> Void
    @StateObject private var launchLocationManager = LocationManager()
    @State private var showsChangeSheet = false
    @State private var showsPlannedWorkoutDetails = false
    @State private var companionTodayMessage: String?
    @State private var companionWeatherFetchDate: Date?
    @State private var companionActivityID: UUID?
    @State private var isCompanionInsightLoading = false
    @State private var companionRequestID: UUID?
    @State private var currentDay = Calendar.current.startOfDay(for: Date())
    @State private var showsThemeTip = false
    @State private var showsActivityOverflowTip = false
    @State private var showsThemeChooser = false
    @State private var mapAttributionBottomInset: CGFloat = 0
    @State private var activityLaunchFloatingContentHeight: CGFloat = 0
    @State private var lastExposedTodayCircleID: String?

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    ZStack(alignment: .bottom) {
                        OutboundPalette.background
                        ActivityLaunchMap(
                            locationManager: launchLocationManager,
                            route: preActivityRoute,
                            attributionBottomInset: mapAttributionBottomInset
                        )
                        .clipped()

                        if launchGoalMode == .planned
                            || activitySessionState != .idle
                            || activityEventToday != nil
                            || circleStore.eligiblePrimaryCircle != nil {
                            todayPeerCards
                                .padding(.horizontal, OutboundSpacing.screen)
                                .padding(.bottom, todayPeerCardsBottomPadding)
                                .reportsMapAttributionOcclusionHeight()
                                .animation(.snappy, value: launchGoalMode)
                                .animation(.snappy, value: activityLaunchFloatingContentHeight)
                        }
                    }

                    Color.clear
                        .frame(height: ActivityLaunchLayout.dockHeight)
                        .allowsHitTesting(false)
                }

                activityLaunchSurface
                    .opacity(isSelected ? 1 : 0)
                    .allowsHitTesting(isSelected)
                    .zIndex(isActivityFullscreenVisible ? 10 : 0)
            }
            .onPreferenceChange(MapAttributionOcclusionHeightPreferenceKey.self) { height in
                mapAttributionBottomInset = height
            }
            .onPreferenceChange(ActivityLaunchFloatingContentHeightPreferenceKey.self) { height in
                activityLaunchFloatingContentHeight = height
            }
            .background(OutboundPalette.background)
            .ignoresSafeArea(edges: isActivityFullscreenVisible ? [] : .top)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SavedActivity.self) { ActivityDetailView(activity: $0) }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar(isActivityFullscreenVisible ? .hidden : .visible, for: .navigationBar)
            .toolbar(isActivityFullscreenVisible ? .hidden : .visible, for: .tabBar)
            .toolbar {
                if canPresentThemeTip || showsThemeTip {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            openThemeChooserFromTip()
                        } label: {
                            Image(systemName: "paintpalette.fill")
                        }
                        .accessibilityLabel("Change appearance")
                        .popover(isPresented: $showsThemeTip, arrowEdge: .top) {
                            OutboundTooltip(
                                text: String(
                                    localized: "theme.discovery.tip",
                                    defaultValue: "Tap to change appearance"
                                )
                            )
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    GlobalConditionsButton()
                }
                if showsActivityOverflowMenu, activitySessionState == .idle {
                    ToolbarItem(placement: .topBarTrailing) {
                        activityOverflowMenu
                    }
                }
            }
            .onAppear {
                launchLocationManager.requestCurrentLocation()
                trackTodayCircleExposureIfNeeded()
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
                guard isSelected else { return }
                do {
                    try await Task.sleep(for: .milliseconds(650))
                } catch {
                    return
                }
                guard isSelected else { return }
                if canPresentActivityOverflowTip {
                    presentActivityOverflowTip()
                } else if canPresentThemeTip {
                    presentThemeTip()
                }
            }
            .onChange(of: isSelected) { _, isSelected in
                if !isSelected {
                    showsThemeTip = false
                    showsActivityOverflowTip = false
                } else {
                    trackTodayCircleExposureIfNeeded()
                }
            }
            .onChange(of: circleStore.eligiblePrimaryCircle?.id) { _, _ in
                trackTodayCircleExposureIfNeeded()
            }
            .onChange(of: activitySessionState) { _, state in
                if state != .idle {
                    showsActivityOverflowTip = false
                }
            }
        }
        .sheet(isPresented: $showsPlannedWorkoutDetails) {
            plannedWorkoutDetailsSheet
                .presentationDetents([.medium, .large])
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
    }

    private var activityOverflowMenu: some View {
        Menu {
            Button {
                performActivityOverflowAction(.photo)
            } label: {
                Label(
                    preActivityPhoto == nil
                        ? String(localized: "record.photo.take", defaultValue: "Take photo")
                        : String(localized: "record.photo.view", defaultValue: "View photo"),
                    systemImage: preActivityPhoto == nil ? "camera.fill" : "photo.fill"
                )
            }

            Button {
                performActivityOverflowAction(.route)
            } label: {
                Label(
                    preActivityRoute == nil
                        ? String(localized: "record.route.find", defaultValue: "Find a route")
                        : String(localized: "record.route.change", defaultValue: "Change route"),
                    systemImage: "map.fill"
                )
            }

            if preActivityRoute != nil {
                Divider()
                Button(role: .destructive) {
                    performActivityOverflowAction(.removeRoute)
                } label: {
                    Label(
                        String(localized: "record.route.remove", defaultValue: "Remove route"),
                        systemImage: "map.fill"
                    )
                }
            }
        } label: {
            activityOverflowLabel
        }
        .accessibilityLabel(String(localized: "record.more_actions", defaultValue: "More activity options"))
        .accessibilityValue(activityOverflowAccessibilityValue)
        .popover(isPresented: $showsActivityOverflowTip, arrowEdge: .top) {
            OutboundTooltip(
                text: String(
                    localized: "record.more_actions.discovery.tip",
                    defaultValue: "Tap for photos and routes"
                )
            )
        }
    }

    @ViewBuilder
    private var activityOverflowLabel: some View {
        if let preActivityPhoto {
            ZStack(alignment: .bottomTrailing) {
                Image(uiImage: preActivityPhoto)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 34, height: 34)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(theme.actionColor, lineWidth: 2))

                Image(systemName: "ellipsis")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.primary)
                    .frame(width: 16, height: 16)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1))
                    .offset(x: 3, y: 3)
            }
            .frame(width: 38, height: 38)
        } else {
            Image(systemName: "ellipsis.circle")
                .font(.title3.weight(.semibold))
        }
    }

    private var activityOverflowAccessibilityValue: String {
        switch (preActivityPhoto != nil, preActivityRoute != nil) {
        case (true, true):
            return String(localized: "record.more_actions.photo_route_selected", defaultValue: "Photo and route selected")
        case (true, false):
            return String(localized: "record.photo.added", defaultValue: "Photo added")
        case (false, true):
            return String(localized: "record.route.selected", defaultValue: "Route selected")
        case (false, false):
            return String(localized: "record.more_actions.none_selected", defaultValue: "No photo or route selected")
        }
    }

    private var canPresentActivityOverflowTip: Bool {
        showsActivityOverflowMenu
            && activitySessionState == .idle
            && !hasDismissedActivityOverflowTip
            && activityOverflowTipPresentationCount < 2
    }

    private func presentActivityOverflowTip() {
        activityOverflowTipPresentationCount += 1
        showsThemeTip = false
        showsActivityOverflowTip = true
        Task {
            await analyticsManager?.track(.init(.featureExposed, properties: [
                .feature: .string("activity_overflow_tip")
            ]))
        }
    }

    private func dismissActivityOverflowTip(permanently: Bool) {
        if permanently {
            hasDismissedActivityOverflowTip = true
        }
        showsActivityOverflowTip = false
    }

    private func performActivityOverflowAction(_ action: ActivityOverflowAction) {
        let waitsForTipDismissal = showsActivityOverflowTip
        dismissActivityOverflowTip(permanently: true)
        guard waitsForTipDismissal else {
            executeActivityOverflowAction(action)
            return
        }
        Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            executeActivityOverflowAction(action)
        }
    }

    private func executeActivityOverflowAction(_ action: ActivityOverflowAction) {
        switch action {
        case .photo:
            onPreActivityPhotoAction()
        case .route:
            onRouteSelectionAction()
        case .removeRoute:
            onRouteRemovalAction()
        }
    }

    private var canPresentThemeTip: Bool {
        !hasDismissedThemeTip && themeTipPresentationCount < 3
    }

    private func presentThemeTip() {
        guard canPresentThemeTip else { return }
        themeTipPresentationCount += 1
        showsThemeTip = true
        Task {
            await analyticsManager?.track(.init(.featureExposed, properties: [
                .feature: .string("theme_discovery_tip")
            ]))
        }
    }

    private func openThemeChooserFromTip() {
        hasDismissedThemeTip = true
        let waitsForTipDismissal = showsThemeTip
        showsThemeTip = false
        guard waitsForTipDismissal else {
            showsThemeChooser = true
            return
        }
        Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            showsThemeChooser = true
        }
    }

    private var activityEventToday: ActivityEventDTO? {
        socialStore.state.upcomingRuns.first {
            $0.currentUserGoing == true && $0.startsAt <= Date().addingTimeInterval(24 * 60 * 60)
        }
    }

    @ViewBuilder
    private var todayPeerCards: some View {
        VStack(spacing: OutboundSpacing.compact) {
            if preActivityRoute == nil {
                if completedActivityToday == nil, let activityEventToday {
                    activityEventCard(activityEventToday)
                } else if launchGoalMode == .planned {
                    plannedWorkoutCard
                }
            }

            if let circle = circleStore.eligiblePrimaryCircle {
                todayCircleCard(circle)
            }

            if activitySessionState != .idle {
                inProgressActivityCard
            }
        }
    }

    private var todayPeerCardsBottomPadding: CGFloat {
        let goalPillHeight = launchGoalMode == .planned ? 0 : ActivityLaunchLayout.goalPillRowHeight
        let hasAdjacentFloatingContent = goalPillHeight > 0 || activityLaunchFloatingContentHeight > 0
        let gap = hasAdjacentFloatingContent
            ? ActivityLaunchLayout.peerCardGap / 2
            : ActivityLaunchLayout.peerCardGap
        return goalPillHeight + activityLaunchFloatingContentHeight + gap
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
            VStack(spacing: isPlannedWorkoutCardMinimized ? 0 : OutboundSpacing.standard) {
                HStack(spacing: OutboundSpacing.compact) {
                    Button(action: openPlannedWorkoutDetails) {
                        HStack(spacing: OutboundSpacing.standard) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(completedActivityToday == nil ? "Today’s workout" : "Up next")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(theme.accentColor)
                                    .textCase(.uppercase)
                                Text(todayWorkoutName)
                                    .font((isPlannedWorkoutCardMinimized ? Font.headline : .title3).weight(.bold))
                                    .foregroundStyle(OutboundPalette.primaryText)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                            Spacer(minLength: 8)
                            Text(todayTotalDuration)
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(String(localized: "Opens workout details"))

                    Button(action: togglePlannedWorkoutCard) {
                        Image(systemName: isPlannedWorkoutCardMinimized ? "chevron.down" : "chevron.up")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(Color.primary.opacity(0.06), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        isPlannedWorkoutCardMinimized
                            ? String(localized: "Expand workout card")
                            : String(localized: "Collapse workout card")
                    )
                }

                if !isPlannedWorkoutCardMinimized {
                    VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                        WorkoutWeatherGuidance(snapshot: weatherStore.snapshot)
                        CompactIntervalPreview(phases: todayPhases)
                    }

                    Divider()

                    HStack(spacing: 0) {
                        Button(action: onOpenPlan) {
                            Label(String(localized: "Plan"), systemImage: "calendar")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 40)
                        }
                        .buttonStyle(.plain)

                        Divider()
                            .frame(height: 24)

                        Button(action: onChangePlan) {
                            Label(String(localized: "Change plan"), systemImage: "arrow.triangle.2.circlepath")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity, minHeight: 40)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .animation(.snappy, value: isPlannedWorkoutCardMinimized)
        }
    }

    private func todayCircleCard(_ circle: CircleDTO) -> some View {
        OutboundCard(style: .companion, contentPadding: 14) {
            NavigationLink {
                CircleDetailView(circle: circle)
            } label: {
                CircleCompactContent(
                    circle: circle,
                    isPrimary: true,
                    isSingleRow: true,
                    showsNavigationIndicator: false
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func togglePlannedWorkoutCard() {
        let isMinimized = !isPlannedWorkoutCardMinimized
        withAnimation(.snappy) {
            isPlannedWorkoutCardMinimized = isMinimized
        }
        trackTodayCardDisplay(sourceType: "planned_workout", isMinimized: isMinimized)
    }

    private func trackTodayCardDisplay(sourceType: String, isMinimized: Bool) {
        Task {
            await analyticsManager?.track(.init(.todayCardDisplayChanged, properties: [
                .sourceType: .string(sourceType),
                .selectionType: .string(isMinimized ? "minimized" : "expanded"),
            ]))
        }
    }

    private func trackTodayCircleExposureIfNeeded() {
        guard isSelected,
              let circle = circleStore.eligiblePrimaryCircle,
              circle.id != lastExposedTodayCircleID else { return }
        lastExposedTodayCircleID = circle.id
        Task {
            await analyticsManager?.track(.init(.circleSectionExposed, properties: [
                .entrySource: .string("today"),
                .participantCountBucket: .string(ProductAnalyticsBucket.count(circle.memberCount)),
            ]))
        }
    }

    private var plannedWorkoutDetailsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OutboundSpacing.section) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(todayWorkoutName)
                            .font(.title2.weight(.bold))
                        Text(todayTotalDuration)
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    CompactIntervalPreview(phases: todayPhases)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Why this workout?")
                            .font(.headline)
                        Text(todayExplanation)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        showsPlannedWorkoutDetails = false
                        Task { @MainActor in
                            await Task.yield()
                            showsChangeSheet = true
                        }
                    } label: {
                        Label("Change workout", systemImage: "slider.horizontal.3")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(OutboundSpacing.screen)
            }
            .background(OutboundPalette.background)
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showsPlannedWorkoutDetails = false }
                }
            }
        }
    }

    private func openPlannedWorkoutDetails() {
        Task {
            await analyticsManager?.track(.init(.planningSurfaceOpened, properties: [
                .sourceType: .string("planned_workout_details"),
                .entrySource: .string("today_planned_card"),
            ]))
        }
        showsPlannedWorkoutDetails = true
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
        return .todayComfortableRun
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
        if let targetCalories = activeRunIntent.targetCalories {
            let target = String(
                format: String(localized: "activity.goal.calories.format", defaultValue: "%d kcal"),
                locale: .autoupdatingCurrent,
                targetCalories
            )
            guard let distanceMeters = activeRunIntent.estimatedDistanceMeters,
                  let durationSeconds = activeRunIntent.estimatedDurationSeconds else { return target }
            let distance = measurementPreferences.unitSystem.distanceString(
                meters: distanceMeters,
                fractionDigits: 1
            )
            let minutes = max(1, Int((Double(durationSeconds) / 60).rounded()))
            return String(
                format: String(
                    localized: "today.calorie_goal.summary_format",
                    defaultValue: "%@ · about %@ · %d min"
                ),
                locale: .autoupdatingCurrent,
                target,
                distance,
                minutes
            )
        }
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
        if let targetCalories = activeRunIntent.targetCalories {
            return [WorkoutPhaseItem(
                id: activeRunIntent.id,
                duration: String(
                    format: String(localized: "activity.goal.calories.format", defaultValue: "%d kcal"),
                    locale: .autoupdatingCurrent,
                    targetCalories
                ),
                title: String(localized: "today.calorie_goal.continuous_run", defaultValue: "Continuous easy run"),
                weight: 1
            )]
        }
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
    @EnvironmentObject private var activityStore: ActivityStore
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @EnvironmentObject private var personalizationStore: PersonalizationStore
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
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
                The client can directly apply distances (km, kilometers, mi, miles), durations (minutes or hours), calorie targets, and run effort (recovery, easy, tempo). This request did not contain a change the client could safely apply. Do not say the card was updated. Briefly clarify what is missing or suggest a concrete adjustment that fits the current activity.
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
                text: response?.message ?? String(
                    localized: "today.companion.adjustment_hint",
                    defaultValue: "Tell me a distance, duration, calorie target, or effort—like “15 km,” “45 minutes,” “300 calories,” or “make it easy”—and I’ll update this activity."
                ),
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

        if case .calories(let targetCalories) = requestedGoal {
            guard currentActivity.sport == .run,
                  currentActivity.allowsCalorieGoal,
                  effort?.title != "Tempo run",
                  let weightKilograms = onboardingStore.latestWeightKilograms,
                  let paceSecondsPerKilometer = WorkoutCalorieEstimator.resolveLearnedRunPace(
                      activities: activityStore.activities,
                      calibrationCompleted: personalizationStore.snapshot.calibration.status == .completed
                  ).secondsPerKilometer,
                  let estimate = WorkoutCalorieEstimator.plannedRun(
                      targetCalories: targetCalories,
                      weightKilograms: weightKilograms,
                      paceSecondsPerKilometer: paceSecondsPerKilometer
                  ) else { return nil }
            return currentActivity.replacingCalorieGoal(
                estimate,
                unitSystem: measurementPreferences.unitSystem
            )
        }

        let distanceMeters: Double?
        let durationSeconds: Int?
        switch requestedGoal {
        case .distance(let meters):
            distanceMeters = meters
            durationSeconds = nil
        case .duration(let seconds):
            distanceMeters = nil
            durationSeconds = seconds
        case .calories:
            return nil
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
            allowsCalorieGoal: currentActivity.allowsCalorieGoal,
            routeName: currentActivity.routeName,
            preparedRoute: currentActivity.preparedRoute,
            activityTypeOverride: currentActivity.activityTypeOverride,
            workoutSteps: [],
            coachingTarget: currentActivity.coachingTarget,
            workoutReference: currentActivity.workoutReference,
            activityEvent: currentActivity.activityEvent
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
        case calories(Int)
    }

    private func requestedGoal(in text: String) -> RequestedGoal? {
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*(kilocalories?|calories?|kcals?|kcal|kilometers?|kilometres?|kms?|km|miles?|mi|hours?|hrs?|hr|h|minutes?|mins?|min|m)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let valueRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let value = Double(text[valueRange]) else { return nil }

        let unit = String(text[unitRange])
        if unit.hasPrefix("cal") || unit.hasPrefix("kcal") || unit.hasPrefix("kilocal") {
            let calories = Int(value.rounded())
            guard (50...5_000).contains(calories) else { return nil }
            return .calories(calories)
        }
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
                        Text(snapshot.temperatureLabel(unit: measurementPreferences.temperatureUnit))
                            .monospacedDigit()
                    }
                    HStack(spacing: 3) {
                        Image(systemName: snapshot.symbolName)
                        Text(snapshot.temperatureLabel(unit: measurementPreferences.temperatureUnit))
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
                temperatureUnit: measurementPreferences.temperatureUnit,
                onRefresh: { weatherStore.refresh(force: true) }
            )
            .presentationDetents([.medium])
        }
    }

    private var accessibilityLabel: String {
        guard let snapshot = weatherStore.snapshot else { return String(localized: "Local conditions") }
        let place = snapshot.placeName ?? String(localized: "your area")
        return String(localized: "Local conditions in \(place), \(snapshot.temperatureLabel(unit: measurementPreferences.temperatureUnit)), \(snapshot.headline)")
    }
}

private struct WeatherDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let snapshot: RunningWeatherSnapshot?
    let errorMessage: String?
    let unitSystem: MeasurementUnitSystem
    let temperatureUnit: TemperatureUnit
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
        return String(localized: "\(snapshot.temperatureLabel(unit: temperatureUnit)) · Wind \(snapshot.windLabel(unitSystem: unitSystem)) · \(precipitation)% rain")
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
    @Environment(\.analyticsManager) private var analyticsManager
    @EnvironmentObject private var appNavigationStore: AppNavigationStore
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var personalizationStore: PersonalizationStore
    @EnvironmentObject private var activityStore: ActivityStore
    @EnvironmentObject private var recognitionStore: RecognitionStore
    @EnvironmentObject private var trainingPlanStore: TrainingPlanStore
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    @EnvironmentObject private var cycleAwareStore: CycleAwareStore
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @EnvironmentObject private var gearStore: GearStore
    @EnvironmentObject private var healthAuthorizationStore: HealthAuthorizationStore
    @EnvironmentObject private var healthImportStore: HealthImportStore
    @EnvironmentObject private var socialStore: TogetherStore
    @State private var profile: AppUserProfileDTO?
    @State private var trainingProfileSex: TrainingProfileSex?
    @State private var showsCycleAwareCheckIn = false
    @State private var showsManualWorkoutEntry = false
    @State private var showsConnections = false
    @State private var manualWorkoutToast: String?
    @State private var navigationPath = NavigationPath()
    @State private var hasTrackedCalorieExposure = false
    let onOpenPlan: () -> Void

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                LazyVStack(spacing: OutboundSpacing.standard) {
                    OutboundCard {
                        HStack(spacing: 12) {
                            NavigationLink {
                                SimplifiedProfileView(
                                    profile: profile,
                                    onProfileUpdated: { profile = $0 },
                                    onTrainingProfileUpdated: applyTrainingProfile
                                )
                            } label: {
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
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                        .accessibilityHidden(true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    connectionsPreview
                    Button(action: onOpenPlan) {
                        OutboundCard {
                            HStack(spacing: OutboundSpacing.standard) {
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
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        trainingPlanStore.activePlan == nil
                            ? String(localized: "Choose a plan")
                            : String(localized: "View plan")
                    )
                    .accessibilityHint(String(localized: "View, change, or end the current training plan"))
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
                    recognitionSection
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
                                                Text(completedWorkoutStatLine(for: activity))
                                                    .font(.caption.monospacedDigit())
                                                    .foregroundStyle(.secondary)
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
            .navigationDestination(isPresented: $showsConnections) { SocialConnectionsView() }
            .navigationDestination(for: AssistantNavigationTarget.self) { target in
                assistantDestination(for: target)
            }
            .task { await loadMeData() }
            .onAppear {
                handlePendingAssistantTarget(appNavigationStore.pendingAssistantTarget)
                trackCalorieExposureIfNeeded()
            }
            .onChange(of: activityStore.activities) { _, _ in trackCalorieExposureIfNeeded() }
            .onChange(of: onboardingStore.latestWeightKilograms) { _, _ in trackCalorieExposureIfNeeded() }
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
                            trainingProfileSex: $trainingProfileSex
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
                    trainingProfileSex: $trainingProfileSex
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
        await analyticsManager?.track(.init(.featureExposed, properties: [
            .feature: .string("me_recognition_section"),
        ]))
        async let profileLoad: Void = loadProfile()
        async let trainingProfileLoad: Void = loadTrainingProfile()
        async let connectionsLoad: Void = loadConnectionsIfNeeded()
        _ = await (profileLoad, trainingProfileLoad, connectionsLoad)
        await analyticsManager?.track(.init(.featureExposed, properties: [
            .feature: .string("me_connections_preview"),
        ]))
    }

    private func loadConnectionsIfNeeded() async {
        guard !socialStore.hasLoadedConnections else { return }
        await socialStore.refreshConnections()
    }

    private var connectionPreview: [SocialConnectionDTO] {
        Array(
            socialStore.connections
                .filter { $0.status == "accepted" }
                .sorted(by: SocialConnectionDTO.previewOrder)
                .prefix(4)
        )
    }

    private var connectionsPreview: some View {
        OutboundCard {
            VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                Text("Connections")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                HStack(spacing: 12) {
                    if socialStore.isConnectionsLoading && !socialStore.hasLoadedConnections {
                        ProgressView()
                            .frame(width: 44, height: 44)
                    } else if connectionPreview.isEmpty {
                        Text("Find people")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(connectionPreview) { connection in
                            SocialProfileLink(
                                person: connection.person,
                                connection: connection,
                                entrySource: "me_connections_preview"
                            ) {
                                SocialAvatar(
                                    name: connection.person.displayName,
                                    avatarURL: connection.person.avatarUrl
                                )
                            }
                        }
                    }

                    Spacer(minLength: 0)

                    Button(action: openConnections) {
                        Image(systemName: "ellipsis")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .background(OutboundPalette.companion.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(
                        localized: "me.connections.more",
                        defaultValue: "View all connections"
                    ))
                }
            }
        }
    }

    private func openConnections() {
        showsConnections = true
        Task {
            await analyticsManager?.track(.init(.connectionsOpened, properties: [
                .entrySource: .string("me_preview"),
            ]))
        }
    }

    private func loadTrainingProfile() async {
        guard let profile = try? await APIClient.shared.fetchTrainingProfile() else { return }
        applyTrainingProfile(profile)
    }

    private func applyTrainingProfileSex(_ sex: TrainingProfileSex?) {
        trainingProfileSex = sex
        guard sex == .male else { return }
        cycleAwareStore.isEnabled = false
        showsCycleAwareCheckIn = false
    }

    private func applyTrainingProfile(_ profile: TrainingProfileDTO) {
        applyTrainingProfileSex(profile.sexAtBirth)
        onboardingStore.applyTrainingProfile(profile)
    }

    private func completedWorkoutStatLine(for activity: SavedActivity) -> String {
        let estimate = WorkoutCalorieEstimator.estimate(
            for: activity,
            weightKilograms: onboardingStore.latestWeightKilograms
        )
        return WorkoutCalorieEstimator.durationAndCalorieLine(
            durationSeconds: activity.durationSecs,
            kilocalories: estimate.kilocalories
        )
    }

    private func trackCalorieExposureIfNeeded() {
        guard !hasTrackedCalorieExposure,
              activityStore.activities.prefix(3).contains(where: {
                  WorkoutCalorieEstimator.estimate(
                      for: $0,
                      weightKilograms: onboardingStore.latestWeightKilograms
                  ).kilocalories != nil
              })
        else { return }
        hasTrackedCalorieExposure = true
        Task {
            await analyticsManager?.track(.init(.featureExposed, properties: [
                .feature: .string("completed_workout_calories"),
            ]))
        }
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
    private var recognitionSection: some View {
        NavigationLink {
            RecognitionHistoryView()
        } label: {
            OutboundCard {
                VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                    Text(String(localized: "recognition.me.title", defaultValue: "Milestones"))
                        .font(.headline)

                    HStack(spacing: 8) {
                        if recognitionStore.awards.isEmpty {
                            Image(systemName: "sparkles")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.orange)
                                .frame(width: 40, height: 40)
                                .background(Color.orange.opacity(0.12), in: Circle())
                                .accessibilityLabel(String(
                                    localized: "recognition.me.empty.accessibility",
                                    defaultValue: "No milestones yet"
                                ))
                        } else {
                            ForEach(recognitionStore.awards.prefix(4)) { award in
                                let preview = recognitionStore.preview(for: award.badgeID)
                                RecognitionOrb(preview: preview, size: 40)
                                    .accessibilityElement()
                                    .accessibilityLabel(preview.title)
                            }
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 40, height: 40)
                            .background(Color.primary.opacity(0.06), in: Circle())
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
    private func meStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading) { Text(value).font(.headline.monospacedDigit()); Text(label).font(.caption).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SimplifiedSettingsView: View {
    @Environment(\.analyticsManager) private var analyticsManager
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    @EnvironmentObject private var appearancePreferences: AppearancePreferences
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var guideCatalog: GuideCatalogStore
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @EnvironmentObject private var cycleAwareStore: CycleAwareStore
    @Binding var trainingProfileSex: TrainingProfileSex?
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
                NavigationLink {
                    AccountTransferView()
                } label: {
                    Label(String(localized: "account_transfer.settings_title", table: "AccountTransfer"), systemImage: "iphone.and.arrow.forward")
                }
            }
            Section(String(localized: "workout.reminders.section", defaultValue: "Planned workouts")) {
                NavigationLink {
                    WorkoutReminderSettingsView()
                } label: {
                    Label(String(localized: "workout.reminders.title", defaultValue: "Workout reminders"), systemImage: "bell.badge")
                }
            }
            Section("Safety") {
                NavigationLink {
                    SafetyContactsSettingsView()
                } label: {
                    Label("Trusted Contacts", systemImage: "person.badge.shield.checkmark")
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
                Picker("Measurement", selection: Binding(
                    get: { measurementPreferences.unitSystem },
                    set: { setMeasurementUnitSystem($0) }
                )) {
                    ForEach(MeasurementUnitSystem.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Temperature", selection: Binding(
                    get: { measurementPreferences.temperatureUnit },
                    set: { setTemperatureUnit($0) }
                )) {
                    ForEach(TemperatureUnit.allCases) { Text($0.title).tag($0) }
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
            Section {
                legalDocumentButton(.terms, title: String(localized: "legal.terms.title"), systemImage: "doc.text")
                legalDocumentButton(.privacy, title: String(localized: "legal.privacy.title"), systemImage: "hand.raised")
                legalDocumentButton(.support, title: String(localized: "legal.support.title"), systemImage: "questionmark.circle")
            } header: {
                Text("legal.section.title")
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
                Button(String(localized: "account.delete.title")) {
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

    private func setMeasurementUnitSystem(_ unitSystem: MeasurementUnitSystem) {
        guard measurementPreferences.unitSystem != unitSystem else { return }
        measurementPreferences.unitSystem = unitSystem
        trackPreferenceChange(type: "measurement_unit_system", selection: unitSystem.rawValue)
    }

    private func setTemperatureUnit(_ unit: TemperatureUnit) {
        guard measurementPreferences.temperatureUnit != unit else { return }
        measurementPreferences.temperatureUnit = unit
        trackPreferenceChange(type: "temperature_unit", selection: unit.rawValue)
    }

    private func trackPreferenceChange(type: String, selection: String) {
        Task {
            await analyticsManager?.track(.init(.preferenceChanged, properties: [
                .changeType: .string(type),
                .selectionType: .string(selection),
            ]))
        }
    }

    private func legalDocumentButton(
        _ document: PlainstrideLegalDocument,
        title: String,
        systemImage: String
    ) -> some View {
        Button {
            Task {
                await analyticsManager?.track(.init(.legalDocumentOpened, properties: [
                    .documentType: .string(document.rawValue),
                    .entrySource: .string("settings"),
                ]))
            }
            openURL(document.url)
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(version) (\($0))" } ?? version
    }
}

private struct SimplifiedProfileView: View {
    @Environment(\.analyticsManager) private var analyticsManager
    let profile: AppUserProfileDTO?
    let onProfileUpdated: (AppUserProfileDTO) -> Void
    let onTrainingProfileUpdated: (TrainingProfileDTO) -> Void

    var body: some View {
        SimplifiedProfileEditorView(
            initialProfile: profile,
            onProfileUpdated: onProfileUpdated,
            onTrainingProfileUpdated: onTrainingProfileUpdated
        )
        .task {
            await analyticsManager?.track(.init(.featureExposed, properties: [
                .feature: .string("me_profile_editor"),
            ]))
        }
    }
}

private struct SimplifiedMyQRCodeView: View {
    @Environment(\.analyticsManager) private var analyticsManager
    let displayName: String
    let username: String?
    let avatarURL: String?
    @State private var connectionURL: URL?
    @State private var isLoading = true
    @State private var hasError = false

    var body: some View {
        ScrollView {
            VStack(spacing: OutboundSpacing.standard) {
                OutboundCard {
                    VStack(spacing: OutboundSpacing.compact) {
                        UserAvatarView(url: avatarURL, name: displayName, size: 64)
                        Text(displayName)
                            .font(.headline)
                        if let username, !username.isEmpty {
                            Text("@\(username)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }

                OutboundCard {
                    VStack(spacing: OutboundSpacing.standard) {
                        if let connectionURL,
                           let qrImage = QRCodeRenderer.image(for: connectionURL) {
                            Image(uiImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 280, height: 280)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .accessibilityLabel(String(localized: "My Plainstride QR code"))

                            Text(String(
                                localized: "Scan this QR code to join me on Plainstride.",
                                defaultValue: "Scan this QR code to join me on Plainstride."
                            ))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        } else if isLoading {
                            ProgressView()
                                .frame(width: 280, height: 280)
                        } else if hasError {
                            ContentUnavailableView(
                                String(localized: "QR code unavailable"),
                                systemImage: "qrcode",
                                description: Text(String(
                                    localized: "Try again when you have a connection.",
                                    defaultValue: "Try again when you have a connection."
                                ))
                            )
                            .frame(height: 280)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(OutboundSpacing.screen)
        }
        .background(OutboundPalette.background)
        .navigationTitle(String(localized: "My QR Code"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await analyticsManager?.track(.init(.profileQRCodeOpened, properties: [
                .entrySource: .string("me_profile_card")
            ]))
            do {
                connectionURL = try await APIClient.shared.createConnectionLink().url
            } catch {
                hasError = true
            }
            isLoading = false
        }
    }
}

private struct SimplifiedProfileEditorView: View {
    @Environment(\.analyticsManager) private var analyticsManager
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    var onProfileUpdated: ((AppUserProfileDTO) -> Void)? = nil
    var onTrainingProfileUpdated: ((TrainingProfileDTO) -> Void)? = nil
    @State private var displayName = ""
    @State private var bio = ""
    @State private var contactEmail = ""
    @State private var contactPhone = ""
    @State private var username = ""
    @State private var savedUsername = ""
    @State private var avatarUrl = UserAvatarPersistence.url(for: AuthStore.currentUserId)
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var isUploadingAvatar = false
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var sexAtBirth: TrainingProfileSex?
    @State private var hasBirthDate = false
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    @State private var heightText = ""
    @State private var weightText = ""
    @State private var primaryMotivation: RunnerPrimaryMotivation = .generalFitness
    @State private var preferredRunGoalType: PreferredRunGoalType = .time
    @State private var preservedTrainingProfile: TrainingProfileDTO?
    @State private var toast: ProfileToast?
    @State private var showsQRCode = false

    init(
        initialProfile: AppUserProfileDTO? = nil,
        onProfileUpdated: ((AppUserProfileDTO) -> Void)? = nil,
        onTrainingProfileUpdated: ((TrainingProfileDTO) -> Void)? = nil
    ) {
        self.onProfileUpdated = onProfileUpdated
        self.onTrainingProfileUpdated = onTrainingProfileUpdated
        _displayName = State(initialValue: initialProfile?.displayName ?? "")
        _bio = State(initialValue: initialProfile?.bio ?? "")
        _contactEmail = State(initialValue: initialProfile?.contactEmail ?? "")
        _contactPhone = State(initialValue: initialProfile?.contactPhone ?? "")
        _username = State(initialValue: initialProfile?.username ?? "")
        _savedUsername = State(initialValue: initialProfile?.username ?? "")
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
                    PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                        UserAvatarView(
                            url: avatarUrl,
                            name: displayName.isEmpty ? authStore.currentLoginLabel ?? "Me" : displayName,
                            size: 58,
                            isProfileLoading: isLoading
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Change profile photo"))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(displayName.isEmpty ? "Your profile" : displayName).font(.headline)
                        if !username.isEmpty { Text("@\(username)").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Button {
                        showsQRCode = true
                    } label: {
                        Image(systemName: "qrcode")
                            .font(.headline.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(isUploadingAvatar)
                    .accessibilityLabel(String(localized: "Show my QR code"))
                }
            }
            Section {
                TextField("Display name", text: $displayName)
                    .textInputAutocapitalization(.words)
                TextField(
                    String(localized: "profile.username.label", defaultValue: "Username"),
                    text: $username
                )
                .textInputAutocapitalization(.never)
                .textContentType(.username)
                .autocorrectionDisabled()
                .onChange(of: username) { _, value in
                    let normalized = value.lowercased()
                    if normalized != value { username = normalized }
                }
                TextField("Running bio", text: $bio, axis: .vertical)
                    .lineLimit(2...4)
                Picker("Sex assigned at birth", selection: $sexAtBirth) {
                    Text("Not provided").tag(nil as TrainingProfileSex?)
                    ForEach(TrainingProfileSex.allCases) { value in
                        Text(value.title).tag(value as TrainingProfileSex?)
                    }
                }
                .disabled(preservedTrainingProfile == nil)
                Toggle("Add birthday", isOn: $hasBirthDate)
                    .disabled(preservedTrainingProfile == nil)
                if hasBirthDate {
                    DatePicker(
                        "Birthday",
                        selection: $birthDate,
                        in: oldestBirthDate...latestBirthDate,
                        displayedComponents: .date
                    )
                    .disabled(preservedTrainingProfile == nil)
                }
                TextField(heightLabel, text: $heightText)
                    .keyboardType(.decimalPad)
                    .disabled(preservedTrainingProfile == nil)
                TextField(weightLabel, text: $weightText)
                    .keyboardType(.decimalPad)
                    .disabled(preservedTrainingProfile == nil)
                TextField("Email", text: $contactEmail)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                TextField("Phone number", text: $contactPhone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
            } header: {
                Text("About you")
            } footer: {
                Text(
                    usernameIsValid
                        ? String(localized: "profile.about_you.footer", defaultValue: "Your name, username, and bio may appear in Together. Your other details stay private. You can change your username once every 30 days.")
                        : String(localized: "profile.username.invalid", defaultValue: "Use 3–30 letters, numbers, underscores, or hyphens.")
                )
            }
            Section {
                Picker(
                    String(localized: "profile.motivation.title", defaultValue: "Primary motivation"),
                    selection: $primaryMotivation
                ) {
                    ForEach(RunnerPrimaryMotivation.allCases) { motivation in
                        Text(motivation.title).tag(motivation)
                    }
                }
                Picker(
                    String(localized: "profile.run_goal_preference.title", defaultValue: "Easy-run goal"),
                    selection: $preferredRunGoalType
                ) {
                    ForEach(PreferredRunGoalType.allCases) { goalType in
                        Text(goalType.title).tag(goalType)
                    }
                }
            } header: {
                Text(String(localized: "profile.run_goals.title", defaultValue: "Run goals"))
            } footer: {
                Text(String(
                    localized: "profile.run_goals.footer",
                    defaultValue: "Calories apply only to eligible easy and recovery runs. Weight and a reliable learned pace are required."
                ))
            }
            .disabled(preservedTrainingProfile == nil)
            Section {
                NavigationLink {
                    CompanionMemoryView()
                } label: {
                    Label("What Plainstride knows", systemImage: "brain.head.profile")
                }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showsQRCode) {
            SimplifiedMyQRCodeView(
                displayName: displayName.isEmpty ? authStore.currentLoginLabel ?? "Me" : displayName,
                username: username.isEmpty ? nil : username,
                avatarURL: avatarUrl
            )
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                    .disabled(
                        isSaving
                            || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || !usernameIsValid
                            || !measurementsAreValid
                    )
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
            username = profile.username
            savedUsername = profile.username
            avatarUrl = profile.avatarUrl
            UserAvatarPersistence.save(profile.avatarUrl, for: AuthStore.currentUserId)
        } catch {
            displayName = authStore.currentLoginLabel ?? ""
            showToast(String(localized: "Profile could not be loaded."), style: .error)
        }
        do {
            let trainingProfile = try await APIClient.shared.fetchTrainingProfile()
            applyTrainingProfile(trainingProfile)
        } catch {
            showToast(String(
                localized: "profile.training_details.load_error",
                defaultValue: "Training details could not be loaded."
            ), style: .error)
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            if let preservedTrainingProfile,
               hasTrainingProfileChanges(from: preservedTrainingProfile) {
                let motivationChanged = primaryMotivation != preservedTrainingProfile.primaryMotivation
                let goalPreferenceChanged = preferredRunGoalType != preservedTrainingProfile.preferredRunGoalType
                let trainingProfile = try await APIClient.shared.updateTrainingProfile(trainingProfileRequest)
                applyTrainingProfile(trainingProfile)
                onTrainingProfileUpdated?(trainingProfile)
                if motivationChanged {
                    await analyticsManager?.track(.init(.preferenceChanged, properties: [
                        .changeType: .string("primary_motivation"),
                        .selectionType: .string(trainingProfile.primaryMotivation.rawValue)
                    ]))
                }
                if goalPreferenceChanged {
                    await analyticsManager?.track(.init(.preferenceChanged, properties: [
                        .changeType: .string("run_goal_type"),
                        .selectionType: .string(trainingProfile.preferredRunGoalType.rawValue)
                    ]))
                }
            }
            let profile = try await APIClient.shared.updateMyProfile(
                AppUserProfileUpdateDTO(
                    username: cleanedUsername == savedUsername ? nil : cleanedUsername,
                    displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                    bio: nilIfEmpty(bio),
                    contactEmail: nilIfEmpty(contactEmail),
                    contactPhone: nilIfEmpty(contactPhone)
                )
            )
            displayName = profile.displayName
            let usernameChanged = profile.username != savedUsername
            username = profile.username
            savedUsername = profile.username
            bio = profile.bio ?? ""
            contactEmail = profile.contactEmail ?? ""
            contactPhone = profile.contactPhone ?? ""
            avatarUrl = profile.avatarUrl
            UserAvatarPersistence.save(profile.avatarUrl, for: AuthStore.currentUserId)
            authStore.applyProfileIdentity(username: profile.username, displayName: profile.displayName)
            onProfileUpdated?(profile)
            if usernameChanged {
                await analyticsManager?.track(.init(.preferenceChanged, properties: [
                    .changeType: .string("username"),
                    .selectionType: .string("changed")
                ]))
            }
            showToast(String(localized: "Profile saved"), style: .success)
        } catch {
            showToast(usernameErrorMessage(for: error), style: .error)
        }
    }

    private var cleanedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var usernameIsValid: Bool {
        if cleanedUsername == savedUsername { return true }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_-")
        return (3...30).contains(cleanedUsername.count)
            && cleanedUsername.unicodeScalars.allSatisfy(allowed.contains)
    }

    private func usernameErrorMessage(for error: Error) -> String {
        guard let apiError = error as? APIError,
              case let .http(_, _, code) = apiError else {
            return String(localized: "Could not save profile. Try again.")
        }
        switch code {
        case "username_taken":
            return String(localized: "profile.username.taken", defaultValue: "That username is already taken.")
        case "username_reserved":
            return String(localized: "profile.username.reserved", defaultValue: "That username is reserved. Try another one.")
        case "username_change_too_soon":
            return String(localized: "profile.username.cooldown", defaultValue: "You can change your username once every 30 days.")
        default:
            return String(localized: "Could not save profile. Try again.")
        }
    }

    private var usesMetric: Bool {
        measurementPreferences.unitSystem == .metric
    }

    private var heightLabel: String {
        usesMetric ? String(localized: "Height (cm)") : String(localized: "Height (in)")
    }

    private var weightLabel: String {
        usesMetric ? String(localized: "Weight (kg)") : String(localized: "Weight (lb)")
    }

    private var oldestBirthDate: Date {
        Calendar.current.date(byAdding: .year, value: -120, to: Date()) ?? .distantPast
    }

    private var latestBirthDate: Date {
        Date()
    }

    private var measurementsAreValid: Bool {
        let heightValid = parsedMeasurement(heightText)
            .map { usesMetric ? (90...250).contains($0) : (35...98.5).contains($0) }
            ?? heightText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let weightValid = parsedMeasurement(weightText)
            .map { usesMetric ? (25...350).contains($0) : (55...772).contains($0) }
            ?? weightText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return heightValid && weightValid
    }

    private var trainingProfileRequest: TrainingProfileUpdateDTO {
        TrainingProfileUpdateDTO(
            sexAtBirth: sexAtBirth,
            birthDate: hasBirthDate ? Self.birthDateFormatter.string(from: birthDate) : nil,
            heightCentimeters: parsedMeasurement(heightText).map { usesMetric ? $0 : $0 * 2.54 },
            weightKilograms: parsedMeasurement(weightText).map { usesMetric ? $0 : $0 * 0.45359237 },
            primaryMotivation: primaryMotivation,
            preferredRunGoalType: preferredRunGoalType
        )
    }

    private func hasTrainingProfileChanges(from profile: TrainingProfileDTO) -> Bool {
        sexAtBirth != profile.sexAtBirth
            || (hasBirthDate ? Self.birthDateFormatter.string(from: birthDate) : nil) != profile.birthDate
            || heightText != formatted(profile.heightCentimeters.map { usesMetric ? $0 : $0 / 2.54 })
            || weightText != formatted(profile.weightKilograms.map { usesMetric ? $0 : $0 / 0.45359237 })
            || primaryMotivation != profile.primaryMotivation
            || preferredRunGoalType != profile.preferredRunGoalType
    }

    private func applyTrainingProfile(_ profile: TrainingProfileDTO) {
        preservedTrainingProfile = profile
        sexAtBirth = profile.sexAtBirth
        if let value = profile.birthDate, let date = Self.birthDateFormatter.date(from: value) {
            birthDate = date
            hasBirthDate = true
        } else {
            hasBirthDate = false
        }
        heightText = formatted(profile.heightCentimeters.map { usesMetric ? $0 : $0 / 2.54 })
        weightText = formatted(profile.weightKilograms.map { usesMetric ? $0 : $0 / 0.45359237 })
        primaryMotivation = profile.primaryMotivation
        preferredRunGoalType = profile.preferredRunGoalType
    }

    private func parsedMeasurement(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
    }

    private func formatted(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...1)))
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

    private static let birthDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
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
        isActivityFullscreenVisible: false,
        activityElapsedSeconds: 0,
        activeSport: nil,
        feedbackPage: .constant("Today"),
        customizedTodayIntent: .constant(nil),
        activityLaunchSurface: AnyView(EmptyView()),
        launchGoalMode: .planned,
        showsActivityOverflowMenu: true,
        preActivityPhoto: nil,
        preActivityRoute: nil,
        onContextualStart: {},
        onPreActivityPhotoAction: {},
        onRouteSelectionAction: {},
        onRouteRemovalAction: {},
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
