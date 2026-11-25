import Combine
import Foundation

/// One opening, retained by its caller. View disappearance is not cancellation.
@MainActor final class LoopPlanningPresentation: ObservableObject, Identifiable {
    enum Sheet: Identifiable {
        case distance, location, options, via, savedRoutes
        case details(LoopPlanningCandidate)
        var id: String {
            switch self {
            case .distance: "distance"
            case .location: "location"
            case .options: "options"
            case .via: "via"
            case .savedRoutes: "saved_routes"
            case .details(let candidate): "details:" + candidate.id
            }
        }
    }
    let id = UUID()
    private let attachedRoute: PreparedRoute?
    private(set) var savedDraft: CommunityRouteSelectionDraft
    let session: LoopPlanningSession
    @Published var sheet: Sheet? {
        didSet {
            if case .savedRoutes = oldValue {
                if case .savedRoutes = sheet {} else { savedDraft.cancel() }
            }
        }
    }
    private var started = false
    var detail: LoopPlanningCandidate? {
        if case .details(let candidate) = sheet { candidate } else { nil }
    }
    init(activity: ActivityType, distanceM: Double?, units: MeasurementUnitSystem, initialSelection: PreparedRoute? = nil) {
        attachedRoute = initialSelection
        savedDraft = CommunityRouteSelectionDraft(initialSelection: initialSelection)
        let account = ActivityAccountBoundary.current
        session = LoopPlanningSession(activity: activity, distanceM: distanceM, units: units,
            repository: HTTPLoopPlanningRepository(), placeSearch: MapKitLoopPlaceSearch(), location: CoreLocationLoopProvider(),
            cache: account.owner.hasPrefix("account:") ? DiskLoopPlanningCache.shared : nil, account: account,
            isCurrentAccount: { account == ActivityAccountBoundary.current })
    }
    func openSavedRoutes() {
        guard session.current else { return }
        if case .savedRoutes = sheet { return }
        savedDraft.cancel()
        savedDraft = CommunityRouteSelectionDraft(initialSelection: attachedRoute)
        sheet = .savedRoutes
    }
    func startIfNeeded() {
        guard !started else { return }
        started = true
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-OutboundUITestDeferredPlannerLocation") { return }
#endif
        session.requestLocation(trigger: .initialLocation)
    }
    func cancel() { session.cancel(); savedDraft.cancel(); sheet = nil }
}
