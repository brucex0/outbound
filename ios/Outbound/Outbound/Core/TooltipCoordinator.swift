import Combine
import SwiftUI

enum TooltipBudget: Sendable, Equatable {
    case discovery
    case contextual
}

/// A discovery tooltip and its scheduling policy. Add new tips here, then attach
/// them to their anchor with `coordinatedTooltip`.
struct AppTooltip: Hashable, Sendable {
    let id: String
    let analyticsFeature: String
    let priority: Int
    let maximumPresentations: Int
    let delay: Duration
    let budget: TooltipBudget
    let legacyDismissedKey: String?

    static let activityOverflow = AppTooltip(
        id: "activity_overflow",
        analyticsFeature: "activity_overflow_tip",
        priority: 300,
        maximumPresentations: 2,
        delay: .milliseconds(650),
        budget: .discovery,
        legacyDismissedKey: "activity_overflow_tip_dismissed_v1"
    )

    static let musicDiscovery = AppTooltip(
        id: "music_discovery",
        analyticsFeature: "music_discovery_tip",
        priority: 200,
        maximumPresentations: 1,
        delay: .milliseconds(650),
        budget: .discovery,
        legacyDismissedKey: "music_discovery_tip_dismissed_v1"
    )

    static let themeDiscovery = AppTooltip(
        id: "theme_discovery",
        analyticsFeature: "theme_discovery_tip",
        priority: 100,
        maximumPresentations: 3,
        delay: .milliseconds(650),
        budget: .discovery,
        legacyDismissedKey: "theme_discovery_tip_dismissed_v1"
    )

    static let photoManagement = AppTooltip(
        id: "photo_management",
        analyticsFeature: "photo_management_tip",
        priority: 600,
        maximumPresentations: 1,
        delay: .milliseconds(450),
        budget: .contextual,
        legacyDismissedKey: nil
    )

    static let saveRoute = AppTooltip(
        id: "save_route",
        analyticsFeature: "save_route_tip",
        priority: 500,
        maximumPresentations: 1,
        delay: .milliseconds(450),
        budget: .contextual,
        legacyDismissedKey: nil
    )

    static let cheerMeOn = AppTooltip(
        id: "cheer_me_on",
        analyticsFeature: "cheer_me_on_tip",
        priority: 250,
        maximumPresentations: 1,
        delay: .milliseconds(650),
        budget: .discovery,
        legacyDismissedKey: nil
    )

    static let voiceGuide = AppTooltip(
        id: "voice_guide",
        analyticsFeature: "voice_guide_tip",
        priority: 225,
        maximumPresentations: 1,
        delay: .milliseconds(650),
        budget: .discovery,
        legacyDismissedKey: nil
    )

    static let shoes = AppTooltip(
        id: "shoes",
        analyticsFeature: "shoes_tip",
        priority: 175,
        maximumPresentations: 1,
        delay: .milliseconds(650),
        budget: .discovery,
        legacyDismissedKey: nil
    )

    static let swipeToMap = AppTooltip(
        id: "swipe_to_map",
        analyticsFeature: "swipe_to_map_tip",
        priority: 150,
        maximumPresentations: 1,
        delay: .milliseconds(650),
        budget: .discovery,
        legacyDismissedKey: nil
    )
}

@MainActor
final class TooltipCoordinator: ObservableObject {
    @Published private(set) var presentedTooltip: AppTooltip?

    private let analyticsManager: AnalyticsManager
    private let defaults: UserDefaults
    private var candidates: [String: AppTooltip] = [:]
    private var selectionTask: Task<Void, Never>?
    private let dailyPresentationLimit = 1

    init(analyticsManager: AnalyticsManager, defaults: UserDefaults = .standard) {
        self.analyticsManager = analyticsManager
        self.defaults = defaults
    }

    func request(_ tooltip: AppTooltip) {
        guard isEligible(tooltip) else { return }
        candidates[tooltip.id] = tooltip
        scheduleSelection()
    }

    /// Removes an off-screen anchor without treating the tooltip as learned.
    func withdraw(_ tooltip: AppTooltip) {
        candidates.removeValue(forKey: tooltip.id)
        guard presentedTooltip?.id == tooltip.id else { return }
        presentedTooltip = nil
    }

    func dismiss(_ tooltip: AppTooltip, outcome: String = "dismissed") {
        candidates.removeValue(forKey: tooltip.id)
        let wasPresented = presentedTooltip?.id == tooltip.id
        defaults.set(true, forKey: dismissedKey(for: tooltip))
        if wasPresented {
            presentedTooltip = nil
            trackDismissal(tooltip, outcome: outcome)
        }
    }

    func isPresented(_ tooltip: AppTooltip) -> Bool {
        presentedTooltip?.id == tooltip.id
    }

    func canEventuallyPresent(_ tooltip: AppTooltip) -> Bool {
        isEligible(tooltip)
    }

    private func presentNextIfPossible() {
        guard presentedTooltip == nil else { return }
        let eligibleCandidates = candidates.values.filter {
            isEligible($0) && ($0.budget == .contextual || presentationsToday < dailyPresentationLimit)
        }
        guard let next = eligibleCandidates
                .sorted(by: tooltipOrder)
                .first
        else { return }

        // Do not cascade into a second tip when this one closes. Visible anchors
        // will register again on a later visit or meaningful eligibility change.
        candidates.removeAll()
        presentedTooltip = next
        defaults.set(presentationCount(for: next) + 1, forKey: presentationKey(for: next))
        if next.budget == .discovery {
            let priorDailyCount = presentationsToday
            defaults.set(todayStamp, forKey: dailyStampKey)
            defaults.set(priorDailyCount + 1, forKey: dailyCountKey)
        }
        Task {
            await analyticsManager.track(.init(.featureExposed, properties: [
                .feature: .string(next.analyticsFeature)
            ]))
        }
    }

    private func scheduleSelection() {
        selectionTask?.cancel()
        selectionTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return
            }
            self?.presentNextIfPossible()
        }
    }

    private func isEligible(_ tooltip: AppTooltip) -> Bool {
        let legacyDismissed = tooltip.legacyDismissedKey.map(defaults.bool(forKey:)) ?? false
        return !legacyDismissed
            && !defaults.bool(forKey: dismissedKey(for: tooltip))
            && presentationCount(for: tooltip) < tooltip.maximumPresentations
    }

    private func tooltipOrder(_ lhs: AppTooltip, _ rhs: AppTooltip) -> Bool {
        if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
        return lhs.id < rhs.id
    }

    private func presentationCount(for tooltip: AppTooltip) -> Int {
        defaults.integer(forKey: presentationKey(for: tooltip))
    }

    private func trackDismissal(_ tooltip: AppTooltip, outcome: String) {
        Task {
            await analyticsManager.track(.init(.activityConfigurationChanged, properties: [
                .changeType: .string("coordinated_tooltip"),
                .selectionType: .string(outcome),
                .sourceType: .string(tooltip.id)
            ]))
        }
    }

    private var todayStamp: String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    private var presentationsToday: Int {
        defaults.string(forKey: dailyStampKey) == todayStamp
            ? defaults.integer(forKey: dailyCountKey)
            : 0
    }

    private func dismissedKey(for tooltip: AppTooltip) -> String { "tooltip.\(tooltip.id).dismissed.v1" }
    private func presentationKey(for tooltip: AppTooltip) -> String { "tooltip.\(tooltip.id).presentations.v1" }
    private let dailyStampKey = "tooltip.daily.stamp.v1"
    private let dailyCountKey = "tooltip.daily.count.v1"
}

private struct CoordinatedTooltipModifier: ViewModifier {
    @EnvironmentObject private var coordinator: TooltipCoordinator

    let tooltip: AppTooltip
    let isEligible: Bool
    let text: String
    let arrowEdge: Edge

    func body(content: Content) -> some View {
        content
            .task(id: isEligible) {
                guard isEligible else {
                    coordinator.withdraw(tooltip)
                    return
                }
                do {
                    try await Task.sleep(for: tooltip.delay)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                coordinator.request(tooltip)
            }
            .onDisappear { coordinator.withdraw(tooltip) }
            .popover(isPresented: presentation, arrowEdge: arrowEdge) {
                OutboundTooltip(text: text)
            }
    }

    private var presentation: Binding<Bool> {
        Binding(
            get: { coordinator.isPresented(tooltip) },
            set: { isPresented in
                if !isPresented { coordinator.dismiss(tooltip) }
            }
        )
    }
}

extension View {
    func coordinatedTooltip(
        _ tooltip: AppTooltip,
        isEligible: Bool,
        text: String,
        arrowEdge: Edge
    ) -> some View {
        modifier(CoordinatedTooltipModifier(
            tooltip: tooltip,
            isEligible: isEligible,
            text: text,
            arrowEdge: arrowEdge
        ))
    }
}
