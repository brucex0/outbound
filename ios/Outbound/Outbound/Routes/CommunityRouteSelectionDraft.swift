import Combine
import Foundation
import SwiftUI

/// One picker presentation's draft. Its presenter retains this object so a
/// native sheet-content rebuild cannot discard a choice or its preparation.
@MainActor
final class CommunityRouteSelectionDraft: ObservableObject, Identifiable {
    let id = UUID()
    let plannerPresenter: StableSheetPresenter
    private(set) var planner: LoopPlanningPresentation?
    private var accountObservation: AnyCancellable?

    func openPlanner(activity: ActivityType, distanceM: Double?, preferences: MeasurementPreferences, store: CommunityRouteStore, authStore: AuthStore, analytics: AnalyticsManager?, onCancel: @escaping () -> Void = {}, onSelect: @escaping (PreparedRoute?) -> Void) {
        guard belongsToCurrentPresentation, planner == nil else { return }
        let opening = LoopPlanningPresentation(activity: activity, distanceM: distanceM, units: preferences.unitSystem, initialSelection: selectedRoute)
        planner = opening
        let presented = plannerPresenter.present(diagnosticName: "loop_planner", fullScreen: true, onDismiss: {
            opening.cancel()
            if self.planner === opening { self.planner = nil }
            self.accountObservation = nil
        }) { dismiss in
            LoopPlannerHost(presentation: opening, onSelect: { route in
                dismiss(completion: { [weak self] in
                    guard self?.belongsToCurrentPresentation == true else { return }
                    onSelect(route)
                })
            }, onSavedSelection: { route in
                dismiss(completion: { [weak self] in
                    guard self?.belongsToCurrentPresentation == true else { return }; onSelect(route)
                })
            }, onCancel: { dismiss(completion: onCancel) }).environmentObject(store).environmentObject(authStore)
                .environmentObject(preferences).environment(\.analyticsManager, analytics)
        }
        guard presented else { opening.cancel(); planner = nil; return }
        // Retain account observation with the opening, including while UIKit
        // covers/removes its originating scene content. objectWillChange emits
        // before AuthStore commits its boundary, so check on the next actor turn.
        accountObservation = authStore.objectWillChange.sink { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.account != ActivityAccountBoundary.current else { return }
                self.selectedRoute = nil
                self.cancel()
            }
        }
    }
    let initialSelection: PreparedRoute?
    @Published private(set) var selectedRoute: PreparedRoute?
    @Published private(set) var preparingRouteID: String?

    private let account = ActivityAccountBoundary.current
    private var isActive = true
    private var requestID: UUID?
    private var preparationTask: Task<Void, Never>?

    init(initialSelection: PreparedRoute?, presenter: StableSheetPresenter? = nil) {
        self.plannerPresenter = presenter ?? StableSheetPresenter()
        self.initialSelection = initialSelection
        selectedRoute = initialSelection
    }

    var belongsToCurrentPresentation: Bool {
        isActive && account == ActivityAccountBoundary.current
    }

    var canConfirm: Bool {
        belongsToCurrentPresentation && preparingRouteID == nil
            && (selectedRoute != nil || initialSelection != nil)
    }

    func toggleImportedRoute(_ route: PreparedRoute) {
        guard belongsToCurrentPresentation else { return }
        invalidatePreparation()
        selectedRoute = selectedRoute?.id == route.id ? nil : route
    }

    func chooseImportedRoute(_ route: PreparedRoute) {
        guard belongsToCurrentPresentation else { return }
        invalidatePreparation()
        selectedRoute = route
    }

    func toggleCommunityRoute(_ route: CommunityRoute, store: CommunityRouteStore) {
        guard belongsToCurrentPresentation else { return }
        let wasPreparing = preparingRouteID == route.id
        invalidatePreparation()
        if wasPreparing { return }
        if selectedRoute?.id == route.id {
            selectedRoute = nil
            return
        }
        // Local geometry is ready now; do not publish a false busy/disabled frame.
        if let prepared = store.prepareLocallyAvailableRoute(route) {
            selectedRoute = prepared
            return
        }

        let request = UUID()
        requestID = request
        preparingRouteID = route.id
        preparationTask = Task { @MainActor [weak self] in
            let prepared = await store.prepare(route)
            guard let self else { return }
            let isCurrent = self.belongsToCurrentPresentation && self.requestID == request
#if DEBUG
            StartupUIStabilityDiagnostics.emit("ui_stability component=route_selection event=preparation_completed success=\(prepared != nil) current_request=\(isCurrent)")
#endif
            guard isCurrent else { return }
            // Failure preserves the previous selection; only an explicit toggle clears it.
            if let prepared { self.selectedRoute = prepared }
            self.requestID = nil
            self.preparingRouteID = nil
            self.preparationTask = nil
        }
    }

    /// Called by the presentation owner on Close, Apply, interactive dismissal,
    /// or a genuinely new launch, never by a child view's onDisappear.
    func cancel() {
        guard isActive else { return }
        isActive = false
        planner?.cancel()
        plannerPresenter.dismiss()
        invalidatePreparation()
    }

    private func invalidatePreparation() {
        requestID = nil
        preparationTask?.cancel()
        preparationTask = nil
        if preparingRouteID != nil { preparingRouteID = nil }
    }

    deinit { preparationTask?.cancel() }
}
