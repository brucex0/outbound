import Combine
import Foundation

/// One opening, retained by its caller. View disappearance is not cancellation.
@MainActor final class LoopPlanningPresentation: ObservableObject, Identifiable {
    enum Sheet: Identifiable {
        case inputs
        case details(LoopPlanningCandidate)
        var id: String {
            switch self { case .inputs: "inputs"; case .details(let candidate): "details:" + candidate.id }
        }
    }
    let id = UUID()
    let session: LoopPlanningSession
    @Published var sheet: Sheet?
    private var started = false
    var detail: LoopPlanningCandidate? {
        if case .details(let candidate) = sheet { candidate } else { nil }
    }
    init(activity: ActivityType, distanceM: Double?, units: MeasurementUnitSystem) {
        let account = ActivityAccountBoundary.current
        session = LoopPlanningSession(activity: activity, distanceM: distanceM, units: units,
            repository: HTTPLoopPlanningRepository(), placeSearch: MapKitLoopPlaceSearch(), location: CoreLocationLoopProvider(),
            isCurrentAccount: { account == ActivityAccountBoundary.current })
    }
    func didPresent() { guard session.current else { return }; sheet = .inputs }
    func startIfNeeded() {
        guard !started else { return }
        started = true
        session.requestLocation()
    }
    func cancel() { session.cancel(); sheet = nil }
}
