import Combine
import Foundation

/// The only mutable owner for a planner presentation. All asynchronous writers
/// verify account, input revision, cancellation and presentation lifetime.
@MainActor final class LoopPlanningSession: ObservableObject {
    @Published var distanceText: String { didSet { invalidate() } }
    @Published var lessClimbing = false { didSet { invalidate() } }
    @Published private(set) var start: LoopPlanningCoordinate?
    @Published private(set) var via: LoopPlanningCoordinate?
    @Published private(set) var candidates: [LoopPlanningCandidate] = []
    @Published private(set) var places: [LoopPlanningPlace] = []
    @Published private(set) var recommendations: [LoopPlanningPlace] = []
    @Published private(set) var busy = false
    @Published private(set) var searched = false
    @Published var toast: String?
    let activity: ActivityType
    private let repository: any LoopPlanningRepository
    private let isCurrentAccount: () -> Bool
    private let location: any LoopPlanningLocationProvider
    private let placeSearch: any LoopPlanningPlaceSearch
    let units: MeasurementUnitSystem
    private var locationTask: Task<Void, Never>?
    private var revision = UUID()
    private var searchRevision = UUID()
    private var recommendationRevision = UUID()
    private var task: Task<Void, Never>?
    private var placeTask: Task<Void, Never>?
    private var recommendationTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var active = true
    private var requestingLocation = false

    init(activity: ActivityType, distanceM: Double?, units: MeasurementUnitSystem,
         repository: any LoopPlanningRepository,
         placeSearch: any LoopPlanningPlaceSearch,
         location: any LoopPlanningLocationProvider, isCurrentAccount: @escaping () -> Bool) {
        self.activity = activity; self.repository = repository; self.units = units
        self.placeSearch = placeSearch; self.location = location; self.isCurrentAccount = isCurrentAccount
        distanceText = distanceM.map { String(format: "%.1f", units.distanceValue(meters: $0)) } ?? ""
    }
    var current: Bool { active && isCurrentAccount() }
    var supported: Bool { [.running, .walking, .hiking].contains(activity) }
    var distanceM: Double? {
        guard let value = Double(distanceText.replacingOccurrences(of: ",", with: ".")), value.isFinite, (1000...50000).contains(units.distanceMeters(from: value)) else { return nil }
        return units.distanceMeters(from: value)
    }
    var canGenerate: Bool { current && supported && start != nil && distanceM != nil && !busy }
    func invalidate() { revision = UUID(); task?.cancel(); task = nil; candidates = []; busy = false; searched = false }
    func setStart(_ point: LoopPlanningCoordinate) {
        guard current else { return }; invalidate(); clearSearch(); start = point; requestingLocation = false; location.cancel(); locationTask?.cancel(); loadRecommendations()
    }
    func setVia(_ point: LoopPlanningCoordinate?) { guard current else { return }; invalidate(); via = point }
    func requestLocation() {
        guard current else { return }; requestingLocation = true
        locationTask?.cancel()
        locationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let point = try await location.locate()
                guard current, requestingLocation, !Task.isCancelled else { return }; setStart(point)
            } catch {
                guard current, requestingLocation, !Task.isCancelled, !(error is CancellationError) else { return }
                requestingLocation = false
                ActivityDiagnosticLog.error(.lifecycle, "route_planner_location_failed category=\(ActivityDiagnosticLog.errorCategory(error))")
                showToast(String(localized: "route.planner.location_unavailable", defaultValue: "Choose a start on the map or enable location access in Settings."))
            }
        }
    }
    func generate() {
        guard canGenerate, let start, let distanceM else { return }
        invalidate(); let token = revision; busy = true
        let request = LoopPlanningRequest(start: .init(start), via: via.map(LoopPlanningRequest.Coordinate.init), targetDistanceM: distanceM, activityType: LoopPlanningActivity(rawValue: activity.rawValue) ?? .running, variationSeed: Int.random(in: 0...1000000), preference: lessClimbing ? "less_climbing" : "balanced")
        task = Task { [weak self] in
            guard let self else { return }
            do {
                do {
                    let nearby = try await repository.existing(request)
                    guard current, revision == token, !Task.isCancelled else { return }
                    candidates = LoopPlanningRanking.select(nearby, request: request)
                } catch {
                    guard current, revision == token, !Task.isCancelled else { return }
                    ActivityDiagnosticLog.error(.sync, "route_planner_existing_failed category=\(ActivityDiagnosticLog.errorCategory(error))")
                }
                let result = try await repository.generate(request)
                guard current, revision == token, !Task.isCancelled else { return }
                candidates = LoopPlanningRanking.select(candidates + result, request: request)
                searched = true; busy = false
            } catch {
                guard current, revision == token, !Task.isCancelled else { return }
                busy = false; searched = true
                ActivityDiagnosticLog.error(.sync, "route_planner_generate_failed category=\(ActivityDiagnosticLog.errorCategory(error))")
                showToast(String(localized: "route.planner.unavailable", defaultValue: "Loop generation is unavailable. Try again later, or choose an existing route."))
            }
        }
    }
    func search(_ query: String) {
        placeTask?.cancel(); searchRevision = UUID(); let token = searchRevision
        places = []; guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        placeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await placeSearch.search(query, near: start)
                guard current, searchRevision == token, !Task.isCancelled else { return }
                places = response
            } catch {
                guard current, searchRevision == token, !Task.isCancelled else { return }
                ActivityDiagnosticLog.error(.sync, "route_planner_place_search_failed category=\(ActivityDiagnosticLog.errorCategory(error))")
                showToast(String(localized: "route.planner.search_failed", defaultValue: "Places could not be loaded. Try again."))
            }
        }
    }
    private func loadRecommendations() {
        recommendationTask?.cancel(); recommendationRevision = UUID(); let token = recommendationRevision
        recommendations = []; guard let start else { return }
        recommendationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await placeSearch.parks(near: start)
                guard current, recommendationRevision == token, !Task.isCancelled else { return }
                recommendations = response
            } catch {
                guard current, recommendationRevision == token, !Task.isCancelled else { return }
                ActivityDiagnosticLog.error(.sync, "route_planner_recommendations_failed category=\(ActivityDiagnosticLog.errorCategory(error))")
            }
        }
    }
    func clearSearch() { searchRevision = UUID(); placeTask?.cancel(); places = [] }
    func showToast(_ message: String) {
        toastTask?.cancel(); toast = message
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4)) // Expected cancellation when feedback is replaced or dismissed.
            guard !Task.isCancelled else { return }; self?.toast = nil
        }
    }
    func cancel() { active = false; location.cancel(); locationTask?.cancel(); invalidate(); clearSearch(); recommendationTask?.cancel(); toastTask?.cancel() }
    deinit { locationTask?.cancel(); task?.cancel(); placeTask?.cancel(); recommendationTask?.cancel(); toastTask?.cancel() }
}
