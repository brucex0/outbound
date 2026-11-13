import SwiftUI
import PhotosUI
import UIKit
import Combine
import WidgetKit

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

private enum ConnectionProfilePresentation: Identifiable {
    case loading
    case profile(ConnectionLinkProfilePreview)

    var id: String {
        switch self {
        case .loading: "connection_link_loading"
        case .profile(let preview): "connection_link_profile_\(preview.id)"
        }
    }
}

private enum SimplifiedAppShellPresentation: Identifiable {
    case notifications
    case companionNotification(String)
    case liveCheer(LiveCheerPresentationRequest)

    var id: String {
        switch self {
        case .notifications: "notification_center"
        case .companionNotification(let id): "companion_notification_\(id)"
        case .liveCheer(let request): request.id
        }
    }
}

private struct ConnectionLinkProfileLoadingView: View {
    var body: some View {
        ZStack {
            OutboundPalette.background.ignoresSafeArea()
            VStack(spacing: OutboundSpacing.compact) {
                ProgressView()
                Text(String(localized: "Checking QR code…", table: "ConnectionQRCode"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

enum FixedTabBarLayout {
    static let navigationWidth: CGFloat = 204
    static let navigationHeight: CGFloat = 64
    static let selectedIconDiameter: CGFloat = 46
    static let dockTopPadding: CGFloat = 6
    static let dockBottomOffset: CGFloat = 8
    static let dockHeight = navigationHeight + dockTopPadding
    static let embeddedSetupBottomInset: CGFloat = 0
}

private struct CompactNavigationBar: View {
    let selection: SimplifiedAppTab
    let showsStart: Bool
    let accentColor: Color
    let actionColor: Color
    let onSelect: (SimplifiedAppTab) -> Void
    let onStart: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            tabButton(.social)
            tabButton(.today)
            tabButton(.me)
        }
        .padding(.horizontal, 5)
        .frame(width: FixedTabBarLayout.navigationWidth, height: FixedTabBarLayout.navigationHeight)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.24), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }

    private func tabButton(_ tab: SimplifiedAppTab) -> some View {
        let isSelected = selection == tab
        let isStart = tab == .today && showsStart
        let iconSize: CGFloat = tab == .me ? 27 : isStart ? 23 : 24
        let symbol: String = switch tab {
        case .social: "person.2.fill"
        case .today: isStart ? "play.fill" : "sparkles"
        case .me: "person.crop.circle"
        }
        let label: String = switch tab {
        case .social: String(localized: "Social")
        case .today: isStart
            ? String(localized: "record.start.short", defaultValue: "Start")
            : String(localized: "Today")
        case .me: String(localized: "Me")
        }
        let identifier: String = switch tab {
        case .social: "tab.social"
        case .today: isStart ? "tab.start" : "tab.today"
        case .me: "tab.me"
        }

        return Button {
            if isStart {
                onStart()
            } else if !isSelected {
                onSelect(tab)
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(isStart ? actionColor : isSelected ? accentColor : .primary)
                .frame(width: FixedTabBarLayout.selectedIconDiameter, height: FixedTabBarLayout.selectedIconDiameter)
                .background {
                    if isSelected {
                        Circle().fill(Color.primary.opacity(0.10))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint(isStart
            ? String(localized: "record.start.accessibility_hint", defaultValue: "Starts the prepared activity")
            : "")
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct SimplifiedAppShell: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.outboundTheme) private var theme
    @Environment(\.analyticsManager) private var analyticsManager
    @EnvironmentObject private var guideCatalog: GuideCatalogStore
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var activityStore: ActivityStore
    @EnvironmentObject private var dailyCheckInStore: DailyCheckInStore
    @EnvironmentObject private var trainingPlanStore: TrainingPlanStore
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @EnvironmentObject private var weatherStore: SituationalWeatherStore
    @EnvironmentObject private var appNavigationStore: AppNavigationStore
    @EnvironmentObject private var pushNotifications: PushNotificationCoordinator
    @EnvironmentObject private var communityRouteStore: CommunityRouteStore
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
    let onGroupRunAction: () -> Void
    let onStartRun: (SessionIntent?) -> Void
    @State private var showsAssistant = false
    @StateObject private var companionPresence = CompanionPresenceStore()
    @State private var hasPresentedSurface = false
    @State private var selectedRouteName: String?
    @State private var showsPlanDetails = false
    @State private var showsPlanPicker = false
    @State private var selectedPlanRecommendation: TrainingPlanRecommendation?
    @State private var replacementPlanRecommendation: TrainingPlanRecommendation?
    @State private var connectionFeedback: ConnectionLinkFeedback?
    @State private var connectionProfilePresentation: ConnectionProfilePresentation?
    @State private var appShellPresentation: SimplifiedAppShellPresentation?
    @State private var showsHomeWidgetOnboarding = false
    @State private var homeWidgetOnboardingEntrySource = "settings"
    @AppStorage("home_widget_onboarding_seen_v1") private var hasSeenHomeWidgetOnboarding = false

    private var completedOutboundWorkoutCount: Int {
        activityStore.accountStatistics?.outboundActivityCount ?? (AuthStore.currentUserId == nil ? activityStore.activities.filter { $0.source.kind == .outbound }.count : 0)
    }

    private var homeWidgetOnboardingTaskID: String {
        let sessionState: String = switch activitySessionState {
        case .idle: "idle"
        case .active: "active"
        case .paused: "paused"
        }
        return "\(completedOutboundWorkoutCount)-\(sessionState)-\(isActivityFullscreenVisible)"
    }

    private var canPresentHomeWidgetOnboarding: Bool {
        !hasSeenHomeWidgetOnboarding
            && completedOutboundWorkoutCount >= homeWidgetOnboardingWorkoutThreshold
            && activitySessionState == .idle
            && !isActivityFullscreenVisible
    }

    private let homeWidgetOnboardingWorkoutThreshold = 3

    var body: some View {
        TabView(selection: $selection) {
            tabRoot {
                SocialHomeView(isSelected: selection == .social)
            }
            .tag(SimplifiedAppTab.social)
            .tabItem {
                Image(systemName: "person.2.fill")
                    .accessibilityIdentifier("tab.social")
            }
            .toolbar(.hidden, for: .tabBar)

            tabRoot {
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
                    onGroupRunAction: onGroupRunAction,
                    onOpenPlan: { openPlanManagement(from: "today_planned_card_plan") },
                    onStartRun: onStartRun
                )
                .assistantHighlightAnchor("today.primary-action")
            }
            .tag(SimplifiedAppTab.today)
            .tabItem {
                Image(systemName: "sparkles")
                    .accessibilityIdentifier("tab.today")
            }
            .toolbar(.hidden, for: .tabBar)

            tabRoot {
                SimplifiedMeView(
                    onOpenPlan: { openPlanManagement(from: "me_current_focus") }
                )
            }
            .tag(SimplifiedAppTab.me)
            .tabItem {
                Image(systemName: "person.crop.circle")
                    .accessibilityIdentifier("tab.me")
            }
            .toolbar(.hidden, for: .tabBar)
        }
        .overlay {
            if !isActivityFullscreenVisible {
                // Only the dock ignores the keyboard; tab content keeps native avoidance.
                bottomNavigationDock
                    .frame(height: FixedTabBarLayout.dockHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
        .background {
            CompanionPresentationObserver { hasPresentedSurface = $0 }
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .task(id: companionPresenceTaskID) {
            companionPresence.activate(accountID: companionAccountID)
            companionPresence.reconcile(notifications: socialStore.notifications)
            guard companionPresenceIsActive else {
                companionPresence.dismissPreview()
                return
            }
            if companionPresence.recordVisibleIdleExposure() {
                await analyticsManager?.track(.init(.featureExposed, properties: [
                    .feature: .string("fox_companion_presence"), .result: .string("idle")
                ]))
                await analyticsManager?.track(.init(.assistantLauncherEligibleExposure, properties: [
                    .destination: .string(assistantAnalyticsDestination), .entrySource: .string("app_shell")
                ]))
            }
            do { try await Task.sleep(for: .milliseconds(companionDeliveryDelayMilliseconds)) } catch { return }
            guard !Task.isCancelled, companionPresenceIsActive else { return }
            companionPresence.offerDelivery(notifications: socialStore.notifications)
        }
        .task(id: "\(companionPresence.preview?.id ?? "none")-\(voiceOverEnabled)") {
            guard let previewID = companionPresence.preview?.id else { return }
            do { try await Task.sleep(for: .seconds(voiceOverEnabled ? 20 : 7)) } catch { return }
            guard !Task.isCancelled, companionPresence.preview?.id == previewID else { return }
            companionPresence.dismissPreview()
        }
        .tint(guideCatalog.selectedTheme.accentColor)
        .fullScreenCover(isPresented: Binding(
            get: { !appNavigationStore.sharedDestinations.isEmpty },
            set: { if !$0 { appNavigationStore.closeAllSharedDestinations() } }
        )) {
            NavigationStack {
                if let destination = appNavigationStore.sharedDestinations.last {
                    sharedDestinationView(destination)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button {
                                    appNavigationStore.closeSharedDestination()
                                } label: {
                                    Label(String(localized: "Back"), systemImage: "chevron.left")
                                }
                            }
                        }
            }
        }
        }
        .fullScreenCover(item: $appShellPresentation) { presentation in
            NavigationStack {
                switch presentation {
                case .notifications:
                    SocialNotificationsView(showsDismissButton: true)
                case .companionNotification(let notificationID):
                    SocialNotificationsView(showsDismissButton: true, initialNotificationID: notificationID)
                case .liveCheer(let request):
                    LiveCheerView(sessionID: request.sessionID, entrySource: request.entrySource)
                }
            }
        }
        .onChange(of: selection, initial: true) { _, tab in
            feedbackPage = tab.feedbackPageName
        }
        .overlay(alignment: .top) {
            if let connectionFeedback {
                connectionFeedbackToast(connectionFeedback)
            } else if let notice = activityStore.photoAlbumNotice {
                Label(
                    notice.message,
                    systemImage: notice.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
                )
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: connectionFeedback)
        .task(id: connectionFeedback) {
            guard let connectionFeedback, connectionFeedback.style != .progress else { return }
            try? await Task.sleep(for: .seconds(3.6))
            guard !Task.isCancelled else { return }
            self.connectionFeedback = nil
        }
        .task(id: activityStore.photoAlbumNotice?.id) {
            guard activityStore.photoAlbumNotice != nil else { return }
            try? await Task.sleep(for: .seconds(3.6))
            guard !Task.isCancelled else { return }
            activityStore.clearPhotoAlbumNotice()
        }
        .task(id: homeWidgetOnboardingTaskID) {
            await presentHomeWidgetOnboardingIfNeeded()
        }
        .fullScreenCover(item: $connectionProfilePresentation) { presentation in
            switch presentation {
            case .loading:
                ConnectionLinkProfileLoadingView()
            case .profile(let preview):
                NavigationStack {
                    ConnectionLinkProfileDestination(preview: preview)
                }
            }
        }
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
        .sheet(isPresented: $showsHomeWidgetOnboarding, onDismiss: {
            hasSeenHomeWidgetOnboarding = true
        }) {
            HomeWidgetOnboardingView(
                snapshot: HomeWorkoutWidgetStore.read() ?? HomeWidgetOnboardingView.exampleSnapshot,
                entrySource: homeWidgetOnboardingEntrySource
            ) {
                showsHomeWidgetOnboarding = false
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsPlanDetails) {
            NavigationStack {
                ActiveTrainingPlanDetailsProjectionView(store: trainingPlanStore, accentColor: theme.accentColor,
                    onChangePlan: changePlanFromDetails, onEndPlan: endPlanFromDetails)
            }
        }
        .sheet(isPresented: $showsPlanPicker) {
            NavigationStack {
                TrainingPlanPickerView(
                    recommendations: trainingPlanStore.planOptions,
                    isRefreshing: trainingPlanStore.isRefreshingPlanRecommendations,
                    accentColor: theme.accentColor,
                    onBuildPlan: {
                        showsPlanPicker = false
                        onboardingStore.beginPlanBuilder(source: .allPlans)
                    },
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
        .onAppear { weatherStore.refreshForToday() }
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
        .onChange(of: pushNotifications.pendingNotificationID, initial: true) { _, notificationID in
            guard notificationID != nil else { return }
            let type = pushNotifications.pendingNotificationType
            if type == "liveCheerInvitation",
               let sessionID = pushNotifications.pendingObjectID,
               !sessionID.isEmpty {
                appShellPresentation = .liveCheer(LiveCheerPresentationRequest(
                    sessionID: sessionID,
                    entrySource: "push"
                ))
                pushNotifications.consumePendingNotification()
                Task {
                    await analyticsManager?.track(.init(.pushNotificationOpened, properties: [
                        .sourceType: .string("live_cheer_invitation"),
                        .selectionType: .string("live_cheer"),
                    ]))
                }
            } else if type == "connectionRequest" {
                selection = .social
            } else {
                appShellPresentation = .notifications
                Task {
                    await analyticsManager?.track(.init(.pushNotificationOpened, properties: [
                        .sourceType: .string(type ?? "unknown"),
                        .selectionType: .string("notifications"),
                    ]))
                }
            }
        }
        .onChange(of: appNavigationStore.pendingLiveCheerPresentation) { _, request in
            guard let request else { return }
            appShellPresentation = .liveCheer(request)
            appNavigationStore.consumeLiveCheerPresentation()
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
        .onChange(of: socialStore.connectionLinkFeedback, initial: true) { _, feedback in
            guard let feedback else { return }
            selection = .social
            connectionFeedback = feedback
            socialStore.clearConnectionLinkFeedback()
        }
        .onChange(of: socialStore.pendingConnectionProfile?.id, initial: true) { _, profileID in
            guard profileID != nil, let preview = socialStore.takePendingConnectionProfile() else { return }
            selection = .social
            connectionProfilePresentation = .profile(preview)
        }
        .onChange(of: socialStore.isConnectionProfileLoading, initial: true) { _, isLoading in
            guard isLoading else {
                if case .loading = connectionProfilePresentation {
                    connectionProfilePresentation = nil
                }
                return
            }
            selection = .social
            connectionProfilePresentation = .loading
        }
        .onChange(of: preActivityRoute) { _, route in
            selectedRouteName = route?.name
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                weatherStore.refreshForToday()
            } else {
                companionPresence.resetIdleExposure()
            }
        }
        .onChange(of: isActivityFullscreenVisible) { _, isVisible in
            if isVisible {
                showsAssistant = false
            }
        }
    }

    @ViewBuilder
    private func sharedDestinationView(_ destination: SharedAppDestination) -> some View {
        switch destination {
        case .savedActivity(let activity):
            ActivityDetailView(activity: activity)
        case .socialActivity(let post):
            SocialActivityDetailView(post: post)
        case .plannedActivity(let event, let entrySource):
            ActivityEventDetailView(run: event, entrySource: entrySource)
        case .runnerProfile(let person, let username, let connection, let entrySource):
            SocialProfileDestination(person: person, username: username, connection: connection, entrySource: entrySource)
        }
    }

    private func connectionFeedbackToast(_ feedback: ConnectionLinkFeedback) -> some View {
        HStack(spacing: 8) {
            switch feedback.style {
            case .progress:
                ProgressView()
                    .controlSize(.small)
                    .tint(theme.accentColor)
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .information:
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(theme.accentColor)
            case .error:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            }

            Text(feedback.text)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
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
            analyticsDestination: assistantAnalyticsDestination,
            isPresenceActive: companionPresenceIsActive,
            deliveryToken: companionPresence.deliveryToken,
            deliveryIsSubdued: companionPresence.preview?.presentation.tier == .cheersAndMilestones
        ) {
            showsAssistant = true
        }
        .overlay(alignment: .topTrailing) {
            if companionPresenceIsActive && socialStore.unreadNotificationCount > 0 {
                Button {
                    companionPresence.dismissPreview()
                    trackCompanionAction("envelope_opened")
                    appShellPresentation = .notifications
                } label: {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.accentColor)
                        .frame(width: 26, height: 26)
                        .background(.regularMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(theme.accentColor.opacity(0.25)))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                // Keep the 44 pt target inside the dock gap so it never covers the tab bar.
                .offset(x: 10, y: -16)
                .accessibilityLabel(String(localized: "fox.companion.notifications", defaultValue: "Open unread notifications"))
                .accessibilityIdentifier("fox.companion.envelope")
            }
        }
    }

    private var companionAccountID: String? {
        if let id = authStore.user?.id { return id }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-OutboundUITestSeedData") { return "ui_test" }
        #endif
        return nil
    }

    private var companionPresenceIsActive: Bool {
        scenePhase == .active && activitySessionState == .idle && !isActivityFullscreenVisible
            && !hasPresentedSurface && !showsAssistant && !showsHomeWidgetOnboarding
            && !showsPlanDetails && !showsPlanPicker && selectedPlanRecommendation == nil
            && replacementPlanRecommendation == nil && connectionProfilePresentation == nil
            && appShellPresentation == nil && appNavigationStore.sharedDestinations.isEmpty
    }

    private var companionPresenceTaskID: String {
        let notifications = socialStore.notifications.map { "\($0.id):\($0.readAt == nil)" }.joined(separator: ",")
        return "\(companionAccountID ?? "none")-\(companionPresenceIsActive)-\(notifications)"
    }

    /// Fixture-only override so UI tests can place delivery after a recording or a
    /// presented surface owns the screen. Production keeps the short 900 ms beat.
    private var companionDeliveryDelayMilliseconds: Int {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-OutboundUITestSeedData") {
            let seconds = UserDefaults.standard.double(forKey: "OutboundCompanionDeliveryDelaySeconds")
            if seconds > 0 { return Int(seconds * 1_000) }
        }
        #endif
        return 900
    }

    private func trackCompanionAction(_ selection: String) {
        Task {
            await analyticsManager?.track(.init(.foxCompanionActionSelected, properties: [
                .selectionType: .string(selection)
            ]))
        }
    }

    private func openCompanionPreview(_ item: NotificationCenterPresentationItem) {
        companionPresence.dismissPreview()
        trackCompanionAction("notification_preview")
        Task {
            await analyticsManager?.track(.init(.notificationActionSelected, properties: [
                .section: .string(item.presentation.tier.analyticsValue),
                .category: .string(item.presentation.category.rawValue),
                .selectionType: .string(item.notifications.count > 1 ? "aggregated" : "single"),
                .countBucket: .string(ProductAnalyticsBucket.count(item.notifications.count))
            ]))
        }
        appShellPresentation = .companionNotification(item.primary.id)
    }

    private var bottomNavigationDock: some View {
        HStack(alignment: .center, spacing: 10) {
            assistantLaunchButton
            CompactNavigationBar(
                selection: selection,
                showsStart: selection == .today && activitySessionState == .idle,
                accentColor: guideCatalog.selectedTheme.accentColor,
                actionColor: theme.actionColor,
                onSelect: selectTabWithoutAnimation,
                onStart: onContextualStart
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.top, FixedTabBarLayout.dockTopPadding)
        .overlay(alignment: .bottomLeading) {
            if companionPresenceIsActive, companionPresence.isActiveAccount(companionAccountID),
               let item = companionPresence.preview {
                CompanionNotificationPreview(item: item, onOpen: { openCompanionPreview(item) }, onDismiss: {
                    companionPresence.dismissPreview()
                    trackCompanionAction("notification_dismissed")
                })
                .frame(maxWidth: 340)
                .padding(.horizontal, 16)
                .offset(y: -76)
                .onAppear {
                    guard companionPresenceIsActive,
                          companionPresence.recordVisibleDelivery(id: item.id) else { return }
                    Task {
                        await analyticsManager?.track(.init(.featureExposed, properties: [
                            .feature: .string("fox_companion_presence"), .result: .string("delivery")
                        ]))
                    }
                }
            }
        }
        .offset(y: FixedTabBarLayout.dockBottomOffset)
        .background {
            if selection == .today {
                Rectangle()
                    .fill(.ultraThickMaterial)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
    }

    private func tabRoot<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !isActivityFullscreenVisible {
                // Preserve the page viewport without tying the dock to keyboard resizing.
                Color.clear
                    .frame(height: FixedTabBarLayout.dockHeight)
                    .accessibilityHidden(true)
            }
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

    @MainActor
    private func presentHomeWidgetOnboardingIfNeeded() async {
        guard canPresentHomeWidgetOnboarding else { return }
        do {
            try await Task.sleep(for: .milliseconds(900))
        } catch {
            return
        }
        guard !Task.isCancelled, canPresentHomeWidgetOnboarding else { return }

        if let configurations = try? await WidgetCenter.shared.currentConfigurations(),
           configurations.contains(where: { $0.kind == HomeWorkoutWidgetStore.widgetKind }) {
            guard !Task.isCancelled, canPresentHomeWidgetOnboarding else { return }
            hasSeenHomeWidgetOnboarding = true
            await analyticsManager?.track(.init(.homeWidgetAlreadyPresent, properties: [
                .result: .string("present")
            ]))
            return
        }

        guard !Task.isCancelled, canPresentHomeWidgetOnboarding else { return }
        homeWidgetOnboardingEntrySource = "after_workouts"
        showsHomeWidgetOnboarding = true
    }

    private func openPlanManagement(from entrySource: String) {
        if trainingPlanStore.activePlan == nil {
            presentPlanPicker(from: entrySource)
        } else {
            trackPlanningSurfaceOpened("plan_details", entrySource: entrySource)
            showsPlanDetails = true
        }
    }

    private func changePlanFromDetails() {
        showsPlanDetails = false
        Task { @MainActor in
            await Task.yield()
            presentPlanPicker(from: "plan_details_change")
        }
    }

    private func endPlanFromDetails() {
        trainingPlanStore.clearActivePlan()
        showsPlanDetails = false
        Task {
            await analyticsManager?.track(.init(.trainingPlanEnded, properties: [
                .entrySource: .string("plan_details"),
            ]))
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
        var properties: [ProductPropertyKey: AnalyticsValue] = [
            .sourceType: .string(surface),
            .entrySource: .string(entrySource),
        ]
        if surface == "plan_details", let currentWeek = trainingPlanStore.currentWeek {
            properties[.countBucket] = .string(ProductAnalyticsBucket.count(currentWeek.scheduledWorkouts.count))
        }
        Task {
            await analyticsManager?.track(.init(.planningSurfaceOpened, properties: properties))
        }
    }

}

private enum ActivityOverflowAction {
    case photo
    case route
    case groupRun
    case removeRoute
}

struct SharedActivityEventButton<Label: View>: View {
    @EnvironmentObject private var appNavigationStore: AppNavigationStore
    let event: ActivityEventDTO
    var entrySource = "social_upcoming"
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button {
            appNavigationStore.openSharedDestination(.plannedActivity(event, entrySource: entrySource))
        } label: {
            label()
        }
        .buttonStyle(.plain)
    }
}

private struct SimplifiedTodayView: View {
    @EnvironmentObject private var activityFlowStore: ActivityFlowStore
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
    @EnvironmentObject private var appNavigationStore: AppNavigationStore
    @EnvironmentObject private var liveGroupStore: LiveGroupStore
    @EnvironmentObject private var healthImportStore: HealthImportStore
    @EnvironmentObject private var guideCatalog: GuideCatalogStore
    @EnvironmentObject private var tooltipCoordinator: TooltipCoordinator
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
    let onGroupRunAction: () -> Void
    let onOpenPlan: () -> Void
    let onStartRun: (SessionIntent?) -> Void
    @EnvironmentObject private var launchLocationManager: LocationManager
    @State private var showsStretch = false
    @State private var workoutChangePresentation: TodayWorkoutEditPresentation?
    @State private var showsPlannedWorkoutDetails = false
    @State private var companionTodayMessage: String?
    @State private var companionWeatherFetchDate: Date?
    @State private var companionActivityID: UUID?
    @State private var isCompanionInsightLoading = false
    @State private var companionRequestID: UUID?
    @State private var currentDay = Calendar.current.startOfDay(for: Date())
    @State private var mapAttributionBottomInset: CGFloat = 0
    @State private var activityLaunchFloatingContentHeight: CGFloat = 0
    @State private var activityLaunchMapControlsHeight: CGFloat = 0
    @State private var showsSocialInbox = false
    @State private var presentedAdjustmentID: String?
    @State private var isApplyingWorkoutChange = false
    @State private var pendingWorkoutChangeBaseline: ActivitySuggestionResponse?
    @State private var pendingWorkoutChange: WorkoutEditApplyRequestDTO?
    @State private var workoutChangeToast: ProfileToast?

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    ZStack(alignment: .bottom) {
                        OutboundPalette.background
                        if !isActivityFullscreenVisible {
                            GeometryReader { geometry in
                                ActivityLaunchMap(
                                    locationManager: launchLocationManager,
                                    route: preActivityRoute,
                                    safeZone: ActivityMapSafeZone(bottomInset: max(
                                        mapAttributionBottomInset,
                                        activityLaunchMapControlsHeight + activityLaunchFloatingContentHeight
                                    ) + 8)
                                )
                                .frame(width: geometry.size.width, height: geometry.size.height)
                            }
                            .clipped()
                        }

                        if launchGoalMode == .planned
                            || activitySessionState != .idle
                            || activityEventToday != nil {
                            todayPeerCards
                                .padding(.horizontal, OutboundSpacing.screen)
                                .padding(.bottom, todayPeerCardsBottomPadding)
                                .reportsMapAttributionOcclusionHeight()
                                .animation(.snappy, value: launchGoalMode)
                                .animation(.snappy, value: activityLaunchFloatingContentHeight)
                        }
                    }

                    Color.clear
                        .frame(
                            height: ActivityLaunchLayout.dockHeight
                                + (isActivityFullscreenVisible ? 0 : FixedTabBarLayout.embeddedSetupBottomInset)
                        )
                        .allowsHitTesting(false)
                }

                activityLaunchSurface
                    .opacity(isSelected ? 1 : 0)
                    .allowsHitTesting(isSelected)
                    .padding(.bottom, isActivityFullscreenVisible ? 0 : FixedTabBarLayout.embeddedSetupBottomInset)
                    .zIndex(isActivityFullscreenVisible ? 10 : 0)
            }
            .onPreferenceChange(MapAttributionOcclusionHeightPreferenceKey.self) { height in
                mapAttributionBottomInset = height
            }
            .onPreferenceChange(ActivityLaunchMapControlsHeightPreferenceKey.self) { height in
                activityLaunchMapControlsHeight = height
            }
            .onPreferenceChange(ActivityLaunchFloatingContentHeightPreferenceKey.self) { height in
                activityLaunchFloatingContentHeight = height
            }
            .background(OutboundPalette.background)
            .ignoresSafeArea(edges: isActivityFullscreenVisible ? [] : .top)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showsSocialInbox) { SocialNotificationsView() }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar(isActivityFullscreenVisible ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                if activitySessionState == .idle {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(stretchUI("entry")) { showsStretch = true }
                            .font(.subheadline.weight(.semibold))
                            .accessibilityIdentifier("today.stretch")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    GlobalConditionsButton()
                        .accessibilityIdentifier("today.conditions")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    socialInboxButton(entrySource: "today")
                        .accessibilityIdentifier("today.inbox")
                }
                if showsActivityOverflowMenu, activitySessionState == .idle {
                    ToolbarItem(placement: .topBarTrailing) {
                        activityOverflowMenu
                            .accessibilityIdentifier("today.overflow")
                    }
                }
            }
            .onAppear {
                presentPendingAdjustmentIfNeeded(personalizationStore.snapshot.pendingAdjustment?.id)
            }
            .onChange(of: personalizationStore.snapshot.pendingAdjustment?.id, initial: true) { _, adjustmentID in
                presentPendingAdjustmentIfNeeded(adjustmentID)
            }
            .task(id: isSelected) {
                guard isSelected else { return }
                // Today owns the event card, so refresh the shared social snapshot
                // when this tab becomes visible. Creating an event from Social can
                // happen while Today is already mounted with an older snapshot.
                await socialStore.refresh()
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
            .onChange(of: trainingPlanStore.activitySuggestion?.decision) { _, _ in
                companionTodayMessage = nil
                Task { await loadCompanionTodayMessage(force: true) }
            }
            .onChange(of: displayedWorkoutSelectionKey) { _, _ in
                customizedRunIntent = nil
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await socialStore.refresh() }
                    refreshCurrentDayIfNeeded()
                    // Pull a fresh fix on foreground so activity start never
                    // anchors on a stale location and permission revocations
                    // made in Settings are detected immediately.
                    launchLocationManager.refreshForForeground()
                    launchLocationManager.requestForegroundLocationRefresh()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                refreshCurrentDayIfNeeded()
            }
        }
        .fullScreenCover(isPresented: $showsStretch) {
            StretchSessionView(launch: StretchLaunchContext(entryPoint: .today), voiceProfileID: guideCatalog.selectedVoice.id) { showsStretch = false }
        }
        .sheet(isPresented: $showsPlannedWorkoutDetails) {
            plannedWorkoutDetailsSheet
                .presentationDetents([.medium, .large])
        }
        .overlay(alignment: .top) {
            if let workoutChangeToast { ProfileToastView(toast: workoutChangeToast).padding(.top, OutboundSpacing.standard) }
        }
        .task(id: workoutChangeToast?.id) {
            guard workoutChangeToast != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            workoutChangeToast = nil
        }
        .sheet(item: $workoutChangePresentation) { presentation in
            TodayChangeSheet(
                baseline: presentation.baseline,
                displayedOverride: presentation.displayedOverride,
                pendingAdjustment: personalizationStore.snapshot.pendingAdjustment,
                busy: isApplyingWorkoutChange,
                onApply: { selection in await applyWorkoutChange(selection) },
                onDecision: { accept in
                    Task {
                        await analyticsManager?.track(.init(.todayAdjustmentDecided, properties: [
                            .result: .string(accept ? "accepted" : "kept_original"),
                            .sourceType: .string("workout_change")
                        ]))
                        await personalizationStore.decideAdjustment(accept: accept)
                        try? await trainingPlanStore.refetchAfterWorkoutMutation()
                    }
                    workoutChangePresentation = nil
                }
            )
        }
    }

    @MainActor private func applyWorkoutChange(_ selection: TodayWorkoutChangeSelection) async -> Bool {
        guard !isApplyingWorkoutChange else { return false }
        guard var envelope = selection.baseline, envelope.primary != nil else { return false }
        isApplyingWorkoutChange = true
        defer { isApplyingWorkoutChange = false }
        // Retry an already-submitted command verbatim after an ambiguous response.
        // Re-fetching first could observe our own successful edit and reject its old baseline.
        let retry: WorkoutEditApplyRequestDTO? = pendingWorkoutChange.flatMap { pending in
            pendingWorkoutChangeBaseline == selection.baseline
                && pending.plannedWorkoutId == envelope.primary?.plannedWorkoutId
                && pending.suggestionId == envelope.primary?.id
                && pending.validForDate == envelope.validForDate
                && pending.reason == selection.reason && pending.change == selection.change ? pending : nil
        }
        if retry == nil && (envelope.editContext == nil || !envelope.isValid()) {
            do {
                let refreshed = try await trainingPlanStore.refreshWorkoutEditSuggestion()
                // A local draft cannot be attached to a changed slot, day or prescription.
                // Keep the frozen sheet intact; the next opening uses the refreshed state.
                guard refreshed.isValid(), refreshed.editContext != nil,
                      refreshed.validForDate == envelope.validForDate,
                      refreshed.primary == envelope.primary,
                      refreshed.planVersionId == envelope.planVersionId,
                      refreshed.planContext == envelope.planContext,
                      refreshed.activityWatermark == envelope.activityWatermark,
                      refreshed.decision == envelope.decision else {
                    ActivityDiagnosticLog.notice(.sync, "operation=refresh_workout_edit_baseline result=unavailable_or_changed")
                    await analyticsManager?.track(.init(.todayAdjustmentDecided, properties: [.result: .string("failed"), .sourceType: .string("workout_change")]))
                    return false
                }
                envelope = refreshed
            } catch is CancellationError { return false }
            catch {
                ActivityDiagnosticLog.error(.sync, "operation=refresh_workout_edit_baseline error=\(ActivityDiagnosticLog.errorCategory(error))")
                await analyticsManager?.track(.init(.todayAdjustmentDecided, properties: [.result: .string("failed"), .sourceType: .string("workout_change")]))
                return false
            }
        }
        guard let primary = envelope.primary else { return false }
        guard let revision = retry?.baseRevision ?? envelope.editContext?.baseRevision else { return false }
        let request = WorkoutEditApplyRequestDTO(
            idempotencyKey: retry?.idempotencyKey ?? UUID().uuidString,
            plannedWorkoutId: primary.plannedWorkoutId, suggestionId: primary.id,
            validForDate: envelope.validForDate, baseRevision: revision,
            reason: selection.reason, change: selection.change
        )
        pendingWorkoutChange = request
        pendingWorkoutChangeBaseline = selection.baseline
        await analyticsManager?.track(.init(.todayAdjustmentSelected, properties: [
            .result: .string(selection.change.operation), .sourceType: .string("workout_change")
        ]))
        do {
            try await trainingPlanStore.applyWorkoutChange(request)
            await analyticsManager?.track(.init(.todayAdjustmentDecided, properties: [.result: .string("saved"), .sourceType: .string("workout_change")]))
            customizedRunIntent = nil
            pendingWorkoutChange = nil
            pendingWorkoutChangeBaseline = nil
            workoutChangePresentation = nil
            let confirmation = String(localized: "today.change.applied", defaultValue: "Workout change applied")
            workoutChangeToast = ProfileToast(text: confirmation, style: .success)
            UIAccessibility.post(notification: .announcement, argument: confirmation)
            return true
        } catch is CancellationError {
            // An ambiguous response retains the same request key and draft for retry.
            return false
        } catch {
            await analyticsManager?.track(.init(.todayAdjustmentDecided, properties: [.result: .string("failed"), .sourceType: .string("workout_change")]))
            ActivityDiagnosticLog.error(.sync,
                "operation=apply_workout_edit error=\(ActivityDiagnosticLog.errorCategory(error))")
            return false
        }
    }

    private func socialInboxButton(entrySource: String) -> some View {
        Button {
            showsSocialInbox = true
            Task {
                await analyticsManager?.track(.init(.socialInboxOpened, properties: [
                    .entrySource: .string(entrySource),
                ]))
            }
        } label: {
            NotificationCenterIcon(count: notificationCenterBadgeCount)
        }
        .accessibilityLabel(String(localized: "app.notifications.destination", defaultValue: "Notification Center"))
        .accessibilityValue(notificationCenterAccessibilityValue(count: notificationCenterBadgeCount))
    }

    private var notificationCenterBadgeCount: Int {
        socialStore.actionableNotificationCount + (healthImportStore.importCandidates.isEmpty ? 0 : 1)
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

            Divider()

            Button {
                performActivityOverflowAction(.groupRun)
            } label: {
                Label(
                    String(localized: "record.group.title", defaultValue: "Group run"),
                    systemImage: "person.2.fill"
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
        .coordinatedTooltip(
            .activityOverflow,
            isEligible: isSelected && showsActivityOverflowMenu && activitySessionState == .idle,
            text: String(localized: "record.more_actions.discovery.tip", defaultValue: "Tap for photos and routes"),
            arrowEdge: .top
        )
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

    private func performActivityOverflowAction(_ action: ActivityOverflowAction) {
        let waitsForTipDismissal = tooltipCoordinator.isPresented(.activityOverflow)
        tooltipCoordinator.dismiss(.activityOverflow, outcome: "opened")
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
        case .groupRun:
            onGroupRunAction()
        case .removeRoute:
            onRouteRemovalAction()
        }
    }

    private var activityEventToday: ActivityEventDTO? {
        socialStore.state.upcomingRuns.first {
            guard !activityFlowStore.hasCompletedEvent($0.id), $0.currentUserOutcome == nil,
                  ["scheduled", "active"].contains($0.status ?? "scheduled"),
                  $0.currentUserGoing == true || $0.canParticipate == true else { return false }
            return Calendar.current.isDateInToday($0.startsAt) || $0.status == "active"
        }
    }

    @ViewBuilder
    private var todayPeerCards: some View {
        VStack(spacing: OutboundSpacing.compact) {
            if let activityEventToday {
                activityEventCard(activityEventToday)
            } else if launchGoalMode == .planned && trainingPlanStore.shouldBlockPlannedLaunch {
                OutboundCard {
                    VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                        Text(String(localized: "Rest today")).font(.headline)
                        Text(trainingPlanStore.plannedLaunchBlockedMessage)
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if launchGoalMode == .planned {
                plannedWorkoutCard
            }

            if activitySessionState != .idle {
                inProgressActivityCard
            }
        }
    }

    private var todayPeerCardsBottomPadding: CGFloat {
        let goalPillHeight = activityLaunchMapControlsHeight
        let hasAdjacentFloatingContent = goalPillHeight > 0 || activityLaunchFloatingContentHeight > 0
        let gap = hasAdjacentFloatingContent
            ? ActivityLaunchLayout.peerCardGap / 2
            : ActivityLaunchLayout.peerCardGap
        return goalPillHeight + activityLaunchFloatingContentHeight + gap
    }

    private func activityEventCard(_ event: ActivityEventDTO) -> some View {
        OutboundCard(style: .companion) {
            VStack(alignment: .leading, spacing: 8) {
                SharedActivityEventButton(event: event, entrySource: "today_primary") {
                    VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                        HStack {
                            Text(String(localized: "today.group_activity", defaultValue: "TODAY'S GROUP ACTIVITY"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        ActivityEventSummaryContent(
                            showsAttendanceIcon: false,
                            title: event.title,
                            startsAt: event.startsAt,
                            locationName: event.locationName,
                            note: event.paceNote
                        )
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(String(localized: "social.event.open_details", defaultValue: "Opens activity details"))

                if event.canParticipate == true || event.currentUserGoing == true {
                    Divider()
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 20) {
                            todayGroupJoinButton(event)
                            Spacer(minLength: 0)
                            todayGroupLocationToggle(event, compact: true)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        VStack(alignment: .leading, spacing: 0) {
                            todayGroupJoinButton(event)
                            todayGroupLocationToggle(event)
                        }
                    }
                    .font(.subheadline)
                }
            }
        }
        .task(id: "\(event.id):\(event.currentUserGoing == true):\(activityFlowStore.selectedEvent?.id ?? ""):\(isSelected):\(liveGroupStore.isJoining):\(liveGroupStore.activeSession?.id ?? ""):\(liveGroupStore.isSharing)") {
            guard isSelected else { return }
            activityFlowStore.applyParticipationDefault(event)
            guard !hasDifferentActiveLiveMap(for: event), !liveGroupStore.isJoining,
                  activityFlowStore.consumeLocationSharingDefault(event) else { return }
            if !isSharingLiveMap(for: event) { toggleTodayActivityLiveMapSharing(for: event) }
        }
    }

    private func todayGroupJoinButton(_ event: ActivityEventDTO) -> some View {
        Button {
            activityFlowStore.setJoined(event, joined: activityFlowStore.selectedEvent?.id != event.id)
        } label: {
            Label(String(localized: "group.activity.join_short", table: "GroupActivity"),
                  systemImage: activityFlowStore.selectedEvent?.id == event.id ? "checkmark.square.fill" : "square")
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "group.activity.join_accessibility", table: "GroupActivity"))
        .accessibilityIdentifier("today.group.join")
        .accessibilityAddTraits(activityFlowStore.selectedEvent?.id == event.id ? .isSelected : [])
        .accessibilityValue(activityFlowStore.selectedEvent?.id == event.id ? "1" : "0")
        .disabled(activityFlowStore.hasUnfinishedSession)
    }

    private func todayGroupLocationToggle(_ event: ActivityEventDTO, compact: Bool = false) -> some View {
        Toggle(String(localized: "group.activity.share_location_short", table: "GroupActivity"),
               isOn: Binding(get: { isSharingLiveMap(for: event) }, set: { enabled in
            if enabled != isSharingLiveMap(for: event) { toggleTodayActivityLiveMapSharing(for: event) }
        }))
        .fixedSize(horizontal: compact, vertical: true)
        .frame(minHeight: 44)
        .accessibilityLabel(String(localized: "group.activity.share_location", table: "GroupActivity"))
        .accessibilityIdentifier("today.group.shareLocation")
        .disabled(liveGroupStore.isJoining || hasDifferentActiveLiveMap(for: event)
                  || activityFlowStore.selectedEvent?.id != event.id)
    }

    private func isSharingLiveMap(for event: ActivityEventDTO) -> Bool {
        liveGroupStore.isSharing
            && liveGroupStore.activeSession?.activityEventId == event.id
    }

    private func hasDifferentActiveLiveMap(for event: ActivityEventDTO) -> Bool {
        liveGroupStore.isSharing && !isSharingLiveMap(for: event)
    }

    private func toggleTodayActivityLiveMapSharing(for event: ActivityEventDTO) {
        Task { await analyticsManager?.track(.init(.groupActivityLocationSharingChanged, properties: [
            .selectionType: .string(isSharingLiveMap(for: event) ? "off" : "on"), .result: .string("requested")
        ])) }
        if isSharingLiveMap(for: event) {
            liveGroupStore.stopFromManagementControl()
            return
        }

        Task {
            await analyticsManager?.track(.init(.groupRunJoinAttempted))
            await liveGroupStore.joinActivityEvent(event.id)
            if isSharingLiveMap(for: event) {
                await analyticsManager?.track(.init(.groupRunJoined, properties: [
                    .participantCountBucket: .string(ProductAnalyticsBucket.count(liveGroupStore.participants.count))
                ]))
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
                                Text(trainingPlanStore.activitySuggestion?.relationship == "optionalRecovery" ? "Up next" : "Today’s workout")
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

                if trainingPlanStore.activitySuggestion?.recoveryChangeRecommended == true {
                    VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                        Text(String(localized: "today.recovery.caution", defaultValue: "Recovery is recommended. Your planned workout is unchanged. Choose a recovery workout or skip today before adding more strain."))
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(String(localized: "today.change.sheet_title", defaultValue: "Change workout")) { openWorkoutChange() }
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("todayRecoveryChange")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .task {
                        await analyticsManager?.track(.init(.featureExposed, properties: [.feature: .string("planned_workout_recovery_advice")]))
                    }
                }

                if !isPlannedWorkoutCardMinimized {
                    VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                        WorkoutWeatherGuidance(snapshot: weatherStore.snapshot)
                        CompactIntervalPreview(phases: todayPhases)
                    }

                    if activitySessionState == .idle, !isActivityFullscreenVisible, activeRunIntent.resolvedActivityType == .running {
                        Button {
                            Task {
                                await analyticsManager?.track(.init(.featureExposed, properties: [
                                    .feature: .string("planned_workout_warmup"),
                                    .result: .string("opened")
                                ]))
                            }
                            showsStretch = true
                        } label: {
                            HStack(spacing: OutboundSpacing.compact) {
                                Text(String(localized: "record.planned_warmup.title", defaultValue: "Warm-up exercises"))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(theme.accentColor)
                                Spacer(minLength: 8)
                                Text(plannedWorkoutWarmupRoutine.calculatedDuration)
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(.primary)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(String(localized: "record.planned_warmup.hint", defaultValue: "Opens the warm-up routine without starting your workout."))
                    }

                    HStack(spacing: 0) {
                        Button(action: onOpenPlan) {
                            Label(String(localized: "Plan"), systemImage: "calendar")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 40)
                        }
                        .buttonStyle(.plain)

                        Button {
                            openWorkoutChange()
                        } label: {
                            Label(String(localized: "today.change", defaultValue: "Change"), systemImage: "pencil")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity, minHeight: 40)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("todayDirectEdit")
                    }
                }
            }
            .animation(.snappy, value: isPlannedWorkoutCardMinimized)
        }
    }

    private var plannedWorkoutWarmupRoutine: StretchRoutine {
        let routines = StretchCatalog.routines(entryPoint: .today)
        return StretchCatalog.initial(routines, isIndoor: false, last: nil, lastStanding: nil, sport: nil, entryPoint: .today)
    }

    private func togglePlannedWorkoutCard() {
        let isMinimized = !isPlannedWorkoutCardMinimized
        withAnimation(.snappy) {
            isPlannedWorkoutCardMinimized = isMinimized
        }
        trackTodayCardDisplay(sourceType: todayCardSourceType, isMinimized: isMinimized)
    }

    private var todayCardSourceType: String {
        if currentCalibrationWorkout != nil { return "calibration_workout" }
        if trainingPlanStore.activitySuggestion?.recoveryChangeRecommended == true { return "planned_workout" }
        if trainingPlanStore.shouldSupersedeCalibration { return "optional_recovery" }
        switch trainingPlanStore.activitySuggestion?.relationship {
        case "adjustedFromPlan": return "adjusted_from_plan"
        default: return "planned_workout"
        }
    }

    private func trackTodayCardDisplay(sourceType: String, isMinimized: Bool) {
        Task {
            await analyticsManager?.track(.init(.todayCardDisplayChanged, properties: [
                .sourceType: .string(sourceType),
                .selectionType: .string(isMinimized ? "minimized" : "expanded"),
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
                        Text(String(localized: "today.purpose", defaultValue: "Why this workout?"))
                            .font(.headline)
                        if trainingPlanStore.activitySuggestion?.recoveryChangeRecommended == true {
                            Text(String(localized: "today.recovery.caution", defaultValue: "Recovery is recommended. Your planned workout is unchanged. Choose a recovery workout or skip today before adding more strain."))
                                .font(.subheadline.weight(.semibold))
                        }
                        Text(todayExplanation)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    WorkoutExecutionNotes(intent: activeRunIntent)

                    Button {
                        showsPlannedWorkoutDetails = false
                        Task { @MainActor in
                            await Task.yield()
                            presentWorkoutChangeSheet()
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

    private func openWorkoutChange() {
        Task {
            await analyticsManager?.track(.init(.planningSurfaceOpened, properties: [
                .sourceType: .string("workout_change"),
                .entrySource: .string("today_planned_card_change"),
            ]))
        }
        presentWorkoutChangeSheet()
    }

    private func presentWorkoutChangeSheet() {
        guard workoutChangePresentation == nil else { return }
        // Item-driven presentation freezes identity and content before the first sheet frame.
        // A background refresh must never attach an existing draft to a new slot/revision.
        var baseline = trainingPlanStore.activitySuggestion
#if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-OutboundUITestSeedData"),
           ProcessInfo.processInfo.arguments.contains("-OutboundWorkoutEditMissingContextUITest") {
            baseline?.editContext = nil
        }
#endif
        workoutChangePresentation = TodayWorkoutEditPresentation(
            baseline: baseline,
            displayedOverride: customizedRunIntent ?? currentCalibrationWorkout?.sessionIntent
        )
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
                    Button {
                        appNavigationStore.openSharedDestination(.savedActivity(activity))
                    } label: {
                        HStack(spacing: OutboundSpacing.standard) {
                            Image(systemName: "figure.run.circle.fill")
                                .font(.title2)
                                .foregroundStyle(theme.accentColor)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(activity.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                if activity.activityEventID != nil {
                                    Label(String(localized: "group.activity.label", table: "GroupActivity"), systemImage: "person.2.fill")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(OutboundPalette.companion)
                                }
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
        let safety = trainingPlanStore.activitySuggestion?.recoveryAdvised == true
            ? " Recovery is recommended. Do not endorse the hard session. Suggest an explicit Change workout choice or rest; the plan has not been automatically replaced."
            : ""
        let base = "What is the one most useful thing for me to know about today's training? The workout currently displayed in the app is \(todayWorkoutName), \(todayTotalDuration), with workout ID \(todayWorkoutID). Refer to that workout, not an earlier cached plan day. If a situational signal matters, recommend the smallest safe adjustment, but do not mutate the plan.\(safety)"
        guard let activity else { return base }
        let distance = measurementPreferences.unitSystem.distanceString(meters: activity.distanceM, fractionDigits: 1)
        return """
        \(base)
        The local activity store confirms that a workout was already completed today: \(activity.title), \(durationLabel(activity.durationSecs)), \(distance). \(trainingPlanStore.activitySuggestion?.relationship == "optionalRecovery"
            ? "The backend confirms today's planned session is complete, and the displayed workout is optional recovery."
            : "This activity does not confirm completion of the currently displayed planned workout. Keep that prescription and its incomplete status unless the user explicitly applies a change.") Briefly explain whether doing it today is sensible, and favor recovery when another workout would add unnecessary stress.
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

    private func presentPendingAdjustmentIfNeeded(_ adjustmentID: String?) {
        guard isSelected,
              let adjustmentID,
              adjustmentID != presentedAdjustmentID,
              !isActivityFullscreenVisible else { return }
        presentedAdjustmentID = adjustmentID
        presentWorkoutChangeSheet()
    }

    private var companionInsightMessage: String {
        if trainingPlanStore.activitySuggestion?.recoveryChangeRecommended == true {
            return String(localized: "today.recovery.caution", defaultValue: "Recovery is recommended. Your planned workout is unchanged. Choose a recovery workout or skip today before adding more strain.")
        }
        if let companionTodayMessage { return companionTodayMessage }
        if trainingPlanStore.activitySuggestion?.relationship == "optionalRecovery", let activity = completedActivityToday {
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
        if let customizedRunIntent {
            return workoutCopyWithoutLeadingDuration(customizedRunIntent.title)
        }
        let rawName = currentCalibrationWorkout?.title ?? trainingPlanStore.todaySuggestion?.workout.title ?? "Easy run"
        return workoutCopyWithoutLeadingDuration(rawName.components(separatedBy: " · ").first ?? rawName)
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
        if let advice = trainingPlanStore.activitySuggestion?.localizedPlanAdvice { return advice }
        if let workout = currentCalibrationWorkout { return localizedAppCopy(workout.purpose) }
        if let evidence = trainingPlanStore.activitySuggestion?.primary?.why {
            return localizedAppCopy(evidence)
        }
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
        if let meters = activeRunIntent.targetDistanceMeters,
           trainingPlanStore.activitySuggestion?.primary?.catalogWorkout != nil || trainingPlanStore.activitySuggestion?.primary?.effectiveWorkout != nil {
            return [WorkoutPhaseItem(id: activeRunIntent.id, duration: distanceLabel(meters), title: displayWorkoutCopy(activeRunIntent.title), weight: 1)]
        }
        if let customizedRunIntent {
            if let meters = customizedRunIntent.targetDistanceMeters {
                return [WorkoutPhaseItem(
                    id: customizedRunIntent.id,
                    duration: distanceLabel(meters),
                    title: displayWorkoutCopy(customizedRunIntent.title),
                    weight: 1
                )]
            }
            let seconds = customizedRunIntent.targetDurationSeconds ?? 0
            return [workoutPhaseItem(
                id: customizedRunIntent.id,
                label: customizedRunIntent.title,
                durationSeconds: seconds
            )]
        }
        if let workout = currentCalibrationWorkout {
            return workout.steps.map {
                workoutPhaseItem(
                    id: $0.id,
                    label: $0.label,
                    durationSeconds: $0.durationSeconds
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
            workoutPhaseItem(
                id: $0.id,
                label: $0.label,
                durationSeconds: $0.durationSeconds
            )
        }
    }

    private func workoutPhaseItem(id: String, label: String, durationSeconds: Int) -> WorkoutPhaseItem {
        let parsed = leadingMinuteDuration(in: label)
        let displayedDurationSeconds = parsed?.seconds ?? durationSeconds
        return WorkoutPhaseItem(
            id: id,
            duration: durationLabel(displayedDurationSeconds).replacingOccurrences(of: " min", with: "m"),
            title: displayWorkoutCopy(parsed?.copy ?? label),
            weight: max(1, CGFloat(displayedDurationSeconds) / 300)
        )
    }

    private func workoutCopyWithoutLeadingDuration(_ value: String) -> String {
        displayWorkoutCopy(leadingMinuteDuration(in: value)?.copy ?? value)
    }

    private func displayWorkoutCopy(_ value: String) -> String {
        let localized = localizedAppCopy(value).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = localized.first else { return localized }
        return first.uppercased() + localized.dropFirst()
    }

    private func leadingMinuteDuration(in value: String) -> (seconds: Int, copy: String)? {
        let pattern = #"^\s*([0-9]+(?:\.[0-9]+)?)\s*(?:min|mins|minute|minutes)\s+(.+?)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let minutesRange = Range(match.range(at: 1), in: value),
              let copyRange = Range(match.range(at: 2), in: value),
              let minutes = Double(value[minutesRange])
        else {
            return nil
        }

        return (Int((minutes * 60).rounded()), String(value[copyRange]))
    }

    /// Model and fallback copy uses English semantic values; catalog lookup localizes
    /// app-authored values while preserving unknown user- or server-authored prose.
    private func localizedAppCopy(_ value: String) -> String {
        String(localized: String.LocalizationValue(value))
    }

    private var currentCalibrationWorkout: CalibrationWorkoutDTO? {
        guard !trainingPlanStore.shouldSupersedeCalibration else {
            return nil
        }
        return personalizationStore.snapshot.currentCalibrationWorkout
    }

    private var displayedWorkoutSelectionKey: String {
        if let workout = currentCalibrationWorkout {
            return "calibration:\(workout.id)"
        }
        let relationship = trainingPlanStore.activitySuggestion?.relationship ?? "plan"
        return "suggestion:\(trainingPlanStore.todaySuggestion?.workout.id ?? "fallback"):\(relationship)"
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
    @State private var paywallEnabled = false
    @State private var trainingProfileSex: TrainingProfileSex?
    @State private var showsCycleAwareCheckIn = false
    @State private var showsManualWorkoutEntry = false
    @State private var showsConnections = false
    @State private var showsAddConnection = false
    @State private var showsSocialInbox = false
    @State private var showsQRCode = false
    @State private var showsProfilePhotoPreview = false
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
                            Button {
                                showsProfilePhotoPreview = true
                            } label: {
                                EditableProfileAvatar(
                                    url: profile?.avatarUrl,
                                    name: profile?.displayName ?? authStore.currentLoginLabel ?? "Me",
                                    size: 58
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(localized: "profile.photo.preview", defaultValue: "Preview profile photo"))

                            NavigationLink {
                                SimplifiedProfileView(
                                    profile: profile,
                                    onProfileUpdated: { profile = $0 },
                                    onTrainingProfileUpdated: applyTrainingProfile
                                )
                            } label: {
                                HStack(spacing: 14) {
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
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(localized: "Open profile"))

                            Button {
                                showsQRCode = true
                            } label: {
                                Image(systemName: "qrcode")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(localized: "Show my QR code"))

                            NavigationLink {
                                SimplifiedProfileView(
                                    profile: profile,
                                    onProfileUpdated: { profile = $0 },
                                    onTrainingProfileUpdated: applyTrainingProfile
                                )
                            } label: {
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 32, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(localized: "Open profile"))
                        }
                    }
                    benefitsNavigationCard
                    connectionsPreview
                    NavigationLink {
                        RunnerProgressView()
                    } label: {
                        OutboundCard {
                            VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                                HStack {
                                    Text("This week")
                                        .font(.headline)
                                    Spacer()
                                    HStack(spacing: 4) {
                                        Image(systemName: "sparkles")
                                        Text(String(localized: "progress.view_insights", defaultValue: "View insights"))
                                        Image(systemName: "chevron.right")
                                            .accessibilityHidden(true)
                                    }
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(OutboundPalette.companion)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 6)
                                    .background(OutboundPalette.companion.opacity(0.12), in: Capsule())
                                }
                                if AuthStore.currentUserId != nil && activityStore.accountStatistics == nil {
                                    AccountStatisticsStatus(store: activityStore)
                                } else if AuthStore.currentUserId != nil && !hasCurrentWeekStatistics {
                                    Text(String(localized: "me.week.statistics_unavailable", defaultValue: "Connect to load statistics for this week."))
                                        .font(.subheadline).foregroundStyle(.secondary)
                                    Button(String(localized: "common.retry", defaultValue: "Retry")) {
                                        activityStore.retrySynchronization()
                                    }
                                } else {
                                HStack {
                                    meStat(measurementPreferences.unitSystem.distanceString(meters: weekDistance, fractionDigits: 1), String(localized: "me.week.total_distance", defaultValue: "Total distance"))
                                    meStat(weekDuration.formatted(), String(localized: "Time"))
                                }
                                VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                                    HStack {
                                        Text(String(localized: "me.week.run_goal", defaultValue: "Weekly run goal"))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        if let progress = weeklyRunProgress {
                                            Text(progress.targetRuns.map { target in
                                                String(format: String(localized: "me.week.run_progress", defaultValue: "%1$d of %2$d"), progress.completedRuns, target)
                                            } ?? String(format: String(localized: "me.week.runs_logged", defaultValue: "Runs logged: %d"), progress.completedRuns))
                                                .font(.subheadline.weight(.semibold))
                                        }
                                    }
                                    if let progress = weeklyRunProgress, let target = progress.targetRuns {
                                        ProgressView(value: Double(min(progress.completedRuns, target)), total: Double(target))
                                            .tint(OutboundPalette.companion)
                                        Text(weeklyRunDetail(progress))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text(weeklyRunProgress == nil
                                             ? String(localized: "me.week.run_goal_unavailable", defaultValue: "Run goal unavailable")
                                             : String(localized: "me.week.no_run_goal", defaultValue: "No weekly run goal set."))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                    AccountStatisticsStatus(store: activityStore)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    recognitionSection
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
                                    Button {
                                        appNavigationStore.openSharedDestination(.savedActivity(activity))
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading) {
                                                Text(activity.title).font(.subheadline.weight(.semibold))
                                                if activity.activityEventID != nil {
                                                    Label(String(localized: "group.activity.label", table: "GroupActivity"), systemImage: "person.2.fill")
                                                        .font(.caption.weight(.semibold))
                                                        .foregroundStyle(OutboundPalette.companion)
                                                }
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
            .navigationDestination(isPresented: $showsConnections) { SocialConnectionsView() }
            .sheet(isPresented: $showsAddConnection) {
                AddConnectionSheet()
            }
            .navigationDestination(isPresented: $showsSocialInbox) { SocialNotificationsView() }
            .navigationDestination(isPresented: $showsQRCode) {
                InvitationCodeView(entrySource: "me_profile_card")
            }
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
            .sheet(isPresented: $showsProfilePhotoPreview) {
                ProfilePhotoPreviewView(
                    avatarURL: profile?.avatarUrl,
                    displayName: profile?.displayName ?? authStore.currentLoginLabel ?? "Me",
                    entrySource: "me_card",
                    onProfileUpdated: { profile = $0 }
                )
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
                    Button {
                        showsSocialInbox = true
                        Task {
                            await analyticsManager?.track(.init(.socialInboxOpened, properties: [
                                .entrySource: .string("me"),
                            ]))
                        }
                    } label: {
                        NotificationCenterIcon(count: notificationCenterBadgeCount)
                    }
                    .accessibilityLabel(String(localized: "app.notifications.destination", defaultValue: "Notification Center"))
                    .accessibilityValue(notificationCenterAccessibilityValue(count: notificationCenterBadgeCount))
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

    private var notificationCenterBadgeCount: Int {
        socialStore.actionableNotificationCount + (healthImportStore.importCandidates.isEmpty ? 0 : 1)
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
        async let featureControlsLoad: Void = loadFeatureControls()
        _ = await (profileLoad, trainingProfileLoad, connectionsLoad, featureControlsLoad)
        await analyticsManager?.track(.init(.featureExposed, properties: [
            .feature: .string("me_weekly_run_goal"),
        ]))
        await analyticsManager?.track(.init(.featureExposed, properties: [
            .feature: .string("me_connections_preview"),
        ]))
    }

    private func loadFeatureControls() async {
        guard let status = try? await APIClient.shared.fetchRewardsStatus() else { return }
        paywallEnabled = status.featureControls.paywallEnabled
        if paywallEnabled {
            await analyticsManager?.track(.init(.featureExposed, properties: [
                .feature: .string("me_plus_paywall_entry"),
            ]))
        }
    }

    private func loadConnectionsIfNeeded() async {
        guard !socialStore.hasLoadedConnections else { return }
        await socialStore.refreshConnections()
    }

    private var connectionsPreview: some View {
        SocialConnectionsPreviewCard(
            connections: socialStore.connections
                .filter { $0.status == "accepted" }
                .sorted(by: SocialConnectionDTO.previewOrder),
            isLoading: socialStore.isConnectionsLoading && !socialStore.hasLoadedConnections,
            entrySource: "me_connections_preview",
            onAdd: openAddConnection,
            onOpenAll: openConnections
        )
    }

    private var benefitsNavigationCard: some View {
        OutboundCard {
            VStack(spacing: 0) {
                if paywallEnabled {
                    NavigationLink {
                        PlusView(entrySource: "me")
                            .onAppear { trackMeBenefitDestination("plus") }
                    } label: {
                        benefitNavigationLabel(
                            title: String(localized: "rewards.plus", table: "Rewards"),
                            detail: String(localized: "rewards.plus_settings_body", table: "Rewards"),
                            systemImage: "sparkles"
                        )
                    }
                    Divider()
                }
                NavigationLink {
                    RewardsCenterView()
                        .onAppear { trackMeBenefitDestination("rewards_center") }
                } label: {
                    benefitNavigationLabel(
                        title: String(localized: "rewards.settings_title", table: "Rewards"),
                        detail: String(localized: "rewards.settings_body", table: "Rewards"),
                        systemImage: "gift"
                    )
                }
            }
        }
    }

    private func benefitNavigationLabel(title: String, detail: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(OutboundPalette.companion)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func trackMeBenefitDestination(_ destination: String) {
        Task {
            await analyticsManager?.track(.init(.meDestinationOpened, properties: [
                .destination: .string(destination),
                .entrySource: .string("me"),
            ]))
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

    private func openAddConnection() {
        showsAddConnection = true
        Task {
            await analyticsManager?.track(.init(.connectionsOpened, properties: [
                .entrySource: .string("me_add"),
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
        if week > plan.durationWeeks {
            return String(format: String(localized: "plan.calendar.plan_week", defaultValue: "%1$@ · Week %2$d", table: "PlanningCalendar"), plan.localizedTitle, week)
        }
        return String(localized: "\(plan.localizedTitle) · Week \(week) of \(plan.durationWeeks)")
    }

    private var planDetail: String {
        guard let plan = trainingPlanStore.activePlan else { return String(localized: "Choose a plan") }
        return String(format: String(localized: "me.plan.weekly_sessions", defaultValue: "Weekly sessions: %d"), plan.sessionsPerWeek)
    }
    private var hasCurrentWeekStatistics: Bool {
        guard let snapshot = activityStore.accountStatistics else { return false }
        let now = Date()
        return snapshot.weekStart <= now && now < snapshot.weekEnd
            && snapshot.firstWeekday == 2
    }
    private var weeklyRunProgress: AccountStatisticsSnapshot.WeeklyRunGoal? {
        if AuthStore.currentUserId != nil { return activityStore.accountStatistics?.weeklyRunGoal }
        let target = trainingPlanStore.activePlan.flatMap { $0.sport == .run ? $0.sessionsPerWeek : nil }
        return .init(completedRuns: currentWeekActivities.filter {
                         $0.activityType == .running && ActivitySaveEligibility.evaluate(durationSecs: $0.durationSecs, distanceM: $0.distanceM) == .eligible
                     }.count,
                     targetRuns: target, scheduledRunsByToday: nil)
    }
    private var weekDistance: Double { activityStore.accountStatistics?.currentWeek.distanceMeters ?? (AuthStore.currentUserId == nil ? currentWeekActivities.reduce(0) { $0 + $1.distanceM } : 0) }
    private var weekDuration: Int { activityStore.accountStatistics?.currentWeek.durationSeconds ?? (AuthStore.currentUserId == nil ? currentWeekActivities.reduce(0) { $0 + $1.durationSecs } : 0) }
    private func weeklyRunDetail(_ progress: AccountStatisticsSnapshot.WeeklyRunGoal) -> String {
        // Cached and pending snapshots keep their last complete counts, without a live schedule claim.
        if AuthStore.currentUserId != nil && (activityStore.statisticsAreCached || activityStore.pendingActivityCount > 0
            || activityStore.accountStatistics.map { !Calendar.current.isDateInToday($0.computedAt) } == true) {
            return String(localized: "me.week.all_runs_count", defaultValue: "Runs count once they reach 5 min or 500 m.")
        }
        guard let target = progress.targetRuns else { return "" }
        if progress.completedRuns > target {
            return String(format: String(localized: "me.week.above_goal", defaultValue: "Above weekly run goal: %d"), progress.completedRuns - target)
        }
        if progress.completedRuns == target {
            return String(localized: "me.week.goal_reached", defaultValue: "Weekly run goal reached.")
        }
        if let scheduled = progress.scheduledRunsByToday {
            let difference = progress.completedRuns - scheduled
            if difference > 0 {
                return String(format: String(localized: "me.week.schedule_ahead", defaultValue: "%d ahead of your usual schedule"), difference)
            }
            if difference == 0 {
                return String(localized: "me.week.schedule_on_track", defaultValue: "On your usual schedule")
            }
            return String(format: String(localized: "me.week.schedule_remaining", defaultValue: "%d more to match your usual schedule by today"), -difference)
        }
        return String(format: String(localized: "me.week.runs_remaining", defaultValue: "Remaining this week: %d"), target - progress.completedRuns)
    }
    private var currentWeekActivities: [SavedActivity] {
        let now = Date()
        guard let interval = PlanningCalendarContext.accountCalendar().dateInterval(of: .weekOfYear, for: now) else { return [] }
        return activityStore.activities.filter { $0.startedAt >= interval.start && $0.startedAt < interval.end && $0.startedAt <= now }
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
    @EnvironmentObject private var pushNotifications: PushNotificationCoordinator
    @EnvironmentObject private var guideCatalog: GuideCatalogStore
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @EnvironmentObject private var cycleAwareStore: CycleAwareStore
    @EnvironmentObject private var stravaImportStore: StravaImportStore
    @Binding var trainingProfileSex: TrainingProfileSex?
    @State private var confirmsSignOut = false
    @State private var confirmsAccountDeletion = false
    @State private var showsHomeWidgetOnboarding = false
    @State private var homeWidgetOnboardingEntrySource = "settings"
    @State private var hasTrackedNotificationPromptExposure = false
    @AppStorage(ActivityPhotoAlbumPreferences.savesPhotosKey) private var savesActivityPhotos = true

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
            Section(String(localized: "social.notifications.settings_title", defaultValue: "Notifications")) {
                Text(String(localized: "social.notifications.permission_body", defaultValue: "Get connection requests, Group invitations, Cheers, comments, and activity updates as they happen."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if pushNotifications.hasResolvedAuthorization, !pushNotifications.notificationsEnabled {
                    Button {
                        Task { await pushNotifications.enableFromPrompt(entrySource: "settings", analyticsManager: analyticsManager) }
                    } label: {
                        Label(
                            String(localized: "social.notifications.permission_enable", defaultValue: "Turn on notifications"),
                            systemImage: "bell.badge"
                        )
                    }
                }
            }
            Section(String(localized: "workout.reminders.section", defaultValue: "Planned workouts")) {
                NavigationLink {
                    WorkoutReminderSettingsView()
                } label: {
                    Label(String(localized: "workout.reminders.title", defaultValue: "Workout reminders"), systemImage: "bell.badge")
                }
            }
            Section(String(localized: "widget.settings.section", table: "HomeWidget")) {
                Button {
                    homeWidgetOnboardingEntrySource = "settings"
                    showsHomeWidgetOnboarding = true
                } label: {
                    Label(
                        String(localized: "widget.settings.title", table: "HomeWidget"),
                        systemImage: "square.grid.2x2"
                    )
                }
            }
            Section(String(localized: "settings.photos.section", defaultValue: "Photos")) {
                Toggle(isOn: Binding(
                    get: { savesActivityPhotos },
                    set: { setSavesActivityPhotos($0) }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(
                            localized: "settings.photos.save.activity",
                            defaultValue: "Save activity photos"
                        ))
                        Text(String(
                            localized: "settings.photos.save.activity.detail",
                            defaultValue: "Automatically save activity photos to Photos"
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
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
            Section("Gear") {
                GearSettingsCard()
            }
            Section("Integrations") {
                NavigationLink {
                    AppleHealthSettingsView()
                } label: {
                    Label("Apple Health", systemImage: "heart.text.square")
                }
                Button {
                    stravaImportStore.present()
                } label: {
                    LabeledContent {
                        Text(String(localized: "strava.import.settings.action", defaultValue: "Import"))
                            .foregroundStyle(.secondary)
                    } label: {
                        Label(
                            String(localized: "strava.import.settings.title", defaultValue: "Import activity history"),
                            systemImage: "square.and.arrow.down"
                        )
                    }
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
            Section {
                legalDocumentButton(.terms, title: String(localized: "legal.terms.title"), systemImage: "doc.text")
                legalDocumentButton(.privacy, title: String(localized: "legal.privacy.title"), systemImage: "hand.raised")
                legalDocumentButton(.support, title: String(localized: "legal.support.title"), systemImage: "questionmark.circle")
            } header: {
                Text("legal.section.title")
            }
            #if DEBUG
            Section("Debug") {
                NavigationLink {
                    DebugAppReviewView()
                } label: {
                    Label(String(localized: "title", table: "AppReviewDebug"), systemImage: "star.bubble")
                }
                Button {
                    onboardingStore.restartForDebug()
                } label: {
                    Label("Run onboarding flow", systemImage: "sparkles")
                }
                Text("Presents the new-user flow again without signing out.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    homeWidgetOnboardingEntrySource = "debug"
                    showsHomeWidgetOnboarding = true
                } label: {
                    Label(
                        String(localized: "widget.debug.preview", table: "HomeWidget"),
                        systemImage: "square.grid.2x2"
                    )
                }
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
        .task {
            _ = await pushNotifications.refreshAuthorizationStatus()
            trackNotificationPromptExposureIfNeeded()
        }
        .onChange(of: pushNotifications.notificationsEnabled) { _, enabled in
            if enabled { hasTrackedNotificationPromptExposure = false }
            trackNotificationPromptExposureIfNeeded()
        }
        .sheet(isPresented: $showsHomeWidgetOnboarding) {
            HomeWidgetOnboardingView(
                snapshot: HomeWorkoutWidgetStore.read() ?? HomeWidgetOnboardingView.exampleSnapshot,
                entrySource: homeWidgetOnboardingEntrySource,
                onFinish: { showsHomeWidgetOnboarding = false }
            )
        }
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

    private func trackNotificationPromptExposureIfNeeded() {
        guard pushNotifications.hasResolvedAuthorization,
              !pushNotifications.notificationsEnabled,
              !hasTrackedNotificationPromptExposure
        else { return }
        hasTrackedNotificationPromptExposure = true
        Task {
            await analyticsManager?.track(.init(.pushNotificationPromptExposed, properties: [
                .entrySource: .string("settings"),
            ]))
        }
    }

    private var effectiveSexIsMale: Bool {
        if let trainingProfileSex {
            return trainingProfileSex == .male
        }
        return onboardingStore.completedProfile?.bodyProfile.sex == .male
    }

    private func setSavesActivityPhotos(_ enabled: Bool) {
        guard savesActivityPhotos != enabled else { return }
        savesActivityPhotos = enabled
        Task {
            await analyticsManager?.track(.init(.preferenceChanged, properties: [
                .changeType: .string("save_activity_photos_to_album"),
                .selectionType: .string(enabled ? "enabled" : "disabled")
            ]))
        }
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

private struct SimplifiedProfileEditorView: View {
    @FocusState private var focusedInput: String?
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
    @State private var showsProfilePhotoPreview = false

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
                    Button {
                        showsProfilePhotoPreview = true
                    } label: {
                        EditableProfileAvatar(
                            url: avatarUrl,
                            name: displayName.isEmpty ? authStore.currentLoginLabel ?? "Me" : displayName,
                            size: 58,
                            isProfileLoading: isLoading
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "profile.photo.preview", defaultValue: "Preview profile photo"))
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
                    .accessibilityLabel(String(localized: "Show my QR code"))
                }
            }
            Section {
                TextField("Display name", text: $displayName)
                    .focused($focusedInput, equals: "displayName")
                    .submitLabel(.next)
                    .inputSubmissionAnalytics(.profile)
                    .onSubmit { focusedInput = "username" }
                    .textInputAutocapitalization(.words)
                TextField(
                    String(localized: "profile.username.label", defaultValue: "Username"),
                    text: $username
                )
                .focused($focusedInput, equals: "username")
                .submitLabel(.next)
                .inputSubmissionAnalytics(.profile)
                .onSubmit { focusedInput = "bio" }
                .textInputAutocapitalization(.never)
                .textContentType(.username)
                .autocorrectionDisabled()
                .onChange(of: username) { _, value in
                    let normalized = value.lowercased()
                    if normalized != value { username = normalized }
                }
                TextField("Running bio", text: $bio, axis: .vertical)
                    .focused($focusedInput, equals: "bio")
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
                    .submitLabel(.done)
                    .onSubmit { focusedInput = nil }
                    .focused($focusedInput, equals: "heightText")
                    .keyboardType(.decimalPad)
                    .disabled(preservedTrainingProfile == nil)
                TextField(weightLabel, text: $weightText)
                    .submitLabel(.done)
                    .onSubmit { focusedInput = nil }
                    .focused($focusedInput, equals: "weightText")
                    .keyboardType(.decimalPad)
                    .disabled(preservedTrainingProfile == nil)
                TextField("Email", text: $contactEmail)
                    .focused($focusedInput, equals: "contactEmail")
                    .submitLabel(.next)
                    .inputSubmissionAnalytics(.profile)
                    .onSubmit { focusedInput = "contactPhone" }
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                TextField("Phone number", text: $contactPhone)
                    .submitLabel(.done)
                    .onSubmit { focusedInput = nil }
                    .focused($focusedInput, equals: "contactPhone")
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
            InvitationCodeView(entrySource: "profile_editor")
        }
        .sheet(isPresented: $showsProfilePhotoPreview) {
            ProfilePhotoPreviewView(
                avatarURL: avatarUrl,
                displayName: displayName.isEmpty ? authStore.currentLoginLabel ?? "Me" : displayName,
                entrySource: "profile_editor",
                onProfileUpdated: { profile in
                    avatarUrl = profile.avatarUrl
                    UserAvatarPersistence.save(profile.avatarUrl, for: AuthStore.currentUserId)
                    onProfileUpdated?(profile)
                }
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
        focusedInput = nil
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

    private func showToast(_ text: String, style: ProfileToast.Style) {
        toast = ProfileToast(text: text, style: style)
    }

    private func nilIfEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

private struct EditableProfileAvatar: View {
    let url: String?
    let name: String
    let size: CGFloat
    var isProfileLoading = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            UserAvatarView(
                url: url,
                name: name,
                size: size,
                isProfileLoading: isProfileLoading
            )

            Image(systemName: "camera.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(OutboundPalette.companion, in: Circle())
                .overlay {
                    Circle().strokeBorder(OutboundPalette.background, lineWidth: 2)
                }
                .accessibilityHidden(true)
        }
    }
}

private struct ProfilePhotoPreviewView: View {
    @Environment(\.analyticsManager) private var analyticsManager
    @Environment(\.dismiss) private var dismiss
    let displayName: String
    let entrySource: String
    let onProfileUpdated: (AppUserProfileDTO) -> Void

    @State private var avatarURL: String?
    @State private var showsPhotoActions = false
    @State private var showsPhotoLibrary = false
    @State private var showsCamera = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var pendingCrop: ProfilePhotoCropCandidate?
    @State private var queuedCameraCrop: ProfilePhotoCropCandidate?
    @State private var isUpdating = false
    @State private var toast: ProfileToast?

    init(
        avatarURL: String?,
        displayName: String,
        entrySource: String,
        onProfileUpdated: @escaping (AppUserProfileDTO) -> Void
    ) {
        self.displayName = displayName
        self.entrySource = entrySource
        self.onProfileUpdated = onProfileUpdated
        _avatarURL = State(initialValue: avatarURL)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: OutboundSpacing.standard) {
                Spacer(minLength: OutboundSpacing.standard)

                UserAvatarView(url: avatarURL, name: displayName, size: 240)
                    .overlay {
                        Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.12), radius: 18, y: 8)

                Text(displayName)
                    .font(.title3.weight(.semibold))

                Spacer(minLength: OutboundSpacing.standard)

                Button {
                    showsPhotoActions = true
                } label: {
                    if isUpdating {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label(
                            String(localized: "profile.photo.update", defaultValue: "Update Photo"),
                            systemImage: "camera.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isUpdating)
            }
            .padding(OutboundSpacing.screen)
            .background(OutboundPalette.background)
            .navigationTitle(String(localized: "profile.photo.title", defaultValue: "Profile Photo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.close", defaultValue: "Close")) { dismiss() }
                }
            }
            .confirmationDialog(
                String(localized: "profile.photo.update", defaultValue: "Update Photo"),
                isPresented: $showsPhotoActions,
                titleVisibility: .visible
            ) {
                Button(String(localized: "profile.photo.choose", defaultValue: "Choose Photo")) {
                    track(action: "choose", result: "selected")
                    showsPhotoLibrary = true
                }
                Button(String(localized: "profile.photo.take", defaultValue: "Take Photo")) {
                    track(action: "take", result: "selected")
                    guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                        track(action: "take", result: "unavailable")
                        showToast(
                            String(localized: "profile.photo.camera_unavailable", defaultValue: "Camera is unavailable."),
                            style: .error
                        )
                        return
                    }
                    showsCamera = true
                }
                Button(
                    String(localized: "profile.photo.remove", defaultValue: "Remove Photo"),
                    role: .destructive
                ) {
                    track(action: "remove", result: "selected")
                    Task { await removePhoto() }
                }
                .disabled(avatarURL == nil)
            }
            .photosPicker(
                isPresented: $showsPhotoLibrary,
                selection: $selectedPhotoItem,
                matching: .images
            )
            .sheet(isPresented: $showsCamera, onDismiss: presentQueuedCameraCrop) {
                ProfilePhotoCameraPicker(
                    onImage: { image in
                        queuedCameraCrop = ProfilePhotoCropCandidate(image: image, action: "take")
                        showsCamera = false
                    },
                    onCancel: { showsCamera = false }
                )
                .ignoresSafeArea()
            }
            .fullScreenCover(item: $pendingCrop) { candidate in
                ProfilePhotoCropView(
                    image: candidate.image,
                    onCancel: {
                        track(action: candidate.action, result: "crop_cancelled")
                        pendingCrop = nil
                    },
                    onUsePhoto: { image in
                        track(action: candidate.action, result: "crop_saved")
                        pendingCrop = nil
                        Task { await upload(image: image, action: candidate.action) }
                    }
                )
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
            .onChange(of: selectedPhotoItem) { _, item in
                guard let item else { return }
                Task { await prepareCrop(item: item) }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func prepareCrop(item: PhotosPickerItem) async {
        defer { selectedPhotoItem = nil }
        do {
            guard let sourceData = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: sourceData) else {
                track(action: "choose", result: "failure")
                showToast(String(localized: "That photo could not be used."), style: .error)
                return
            }
            presentCrop(image: image, action: "choose")
        } catch {
            track(action: "choose", result: "failure")
            showToast(String(localized: "Could not upload photo. Try again."), style: .error)
        }
    }

    private func presentQueuedCameraCrop() {
        guard let candidate = queuedCameraCrop else { return }
        queuedCameraCrop = nil
        presentCrop(image: candidate.image, action: candidate.action)
    }

    private func presentCrop(image: UIImage, action: String) {
        track(action: action, result: "crop_opened")
        pendingCrop = ProfilePhotoCropCandidate(image: image, action: action)
    }

    private func upload(image: UIImage, action: String) async {
        isUpdating = true
        defer { isUpdating = false }
        guard let jpegData = resizedAvatarData(from: image) else {
            track(action: action, result: "failure")
            showToast(String(localized: "That photo could not be used."), style: .error)
            return
        }
        do {
            let profile = try await APIClient.shared.uploadMyAvatar(jpegData: jpegData)
            avatarURL = profile.avatarUrl
            UserAvatarPersistence.save(profile.avatarUrl, for: AuthStore.currentUserId)
            if let avatarURL = profile.avatarUrl,
               let uploadedImage = UIImage(data: jpegData) {
                AvatarImageCache.shared.store(uploadedImage, for: avatarURL)
            }
            onProfileUpdated(profile)
            await analyticsManager?.track(.init(.preferenceChanged, properties: [
                .changeType: .string("profile_photo"),
                .selectionType: .string("\(entrySource)_\(action)_success"),
            ]))
            showToast(String(localized: "Profile photo updated"), style: .success)
        } catch {
            track(action: action, result: "failure")
            showToast(String(localized: "Could not upload photo. Try again."), style: .error)
        }
    }

    private func removePhoto() async {
        isUpdating = true
        defer { isUpdating = false }
        do {
            let profile = try await APIClient.shared.removeMyAvatar()
            avatarURL = profile.avatarUrl
            UserAvatarPersistence.save(profile.avatarUrl, for: AuthStore.currentUserId)
            onProfileUpdated(profile)
            await analyticsManager?.track(.init(.preferenceChanged, properties: [
                .changeType: .string("profile_photo"),
                .selectionType: .string("\(entrySource)_remove_success"),
            ]))
            showToast(
                String(localized: "profile.photo.removed", defaultValue: "Profile photo removed"),
                style: .success
            )
        } catch {
            track(action: "remove", result: "failure")
            showToast(
                String(localized: "profile.photo.remove_error", defaultValue: "Could not remove photo. Try again."),
                style: .error
            )
        }
    }

    private func track(action: String, result: String) {
        Task {
            await analyticsManager?.track(.init(.preferenceChanged, properties: [
                .changeType: .string("profile_photo"),
                .selectionType: .string("\(entrySource)_\(action)_\(result)"),
            ]))
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

private struct ProfilePhotoCropCandidate: Identifiable {
    let id = UUID()
    let image: UIImage
    let action: String

    init(image: UIImage, action: String) {
        self.image = image.normalizedForProfileCrop()
        self.action = action
    }
}

private struct ProfilePhotoCameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage) -> Void
        let onCancel: () -> Void

        init(onImage: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onImage = onImage
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else {
                onCancel()
                return
            }
            onImage(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
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
        onGroupRunAction: {},
        onStartRun: { _ in }
    )
        .environmentObject(ActivityStore())
        .environmentObject(AuthStore())
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

#if DEBUG
/// Renders the production Me surface without duplicating its data formulas or weekly card.
struct DebugRepositoryMeSurface: View {
    var body: some View { SimplifiedMeView(onOpenPlan: {}) }
}
#endif
