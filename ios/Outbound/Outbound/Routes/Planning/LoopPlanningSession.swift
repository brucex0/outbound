import Combine
import Foundation

/// The only mutable owner for a planner presentation. All asynchronous writers
/// verify account, input revision, cancellation and presentation lifetime.
@MainActor final class LoopPlanningSession: ObservableObject {
    enum GenerationTrigger: String {
        case initialLocation = "initial_location", myLocation = "my_location"
        case confirmedStart = "confirmed_start", confirmedVia = "confirmed_via", explicit = "explicit"
    }
    struct Generation: Equatable {
        let id = UUID()
        let trigger: GenerationTrigger
    }
    @Published private(set) var generation: Generation?
    @Published private(set) var distanceText: String { didSet { invalidate() } }
    @Published private(set) var lessClimbing = false { didSet { invalidate() } }
    @Published private(set) var start: LoopPlanningCoordinate?
    @Published private(set) var via: LoopPlanningCoordinate?
    @Published private(set) var candidates: [LoopPlanningCandidate] = []
    enum PlaceSearchState { case idle, loading, ready, empty, failed }
    @Published private(set) var placeSearchState = PlaceSearchState.idle
    @Published private(set) var places: [LoopPlanningPlace] = []
    @Published private(set) var recommendations: [LoopPlanningPlace] = []
    @Published private(set) var busy = false
    @Published private(set) var resultsCurrent = false
    @Published private(set) var choosingStart = false
    @Published private(set) var locating = false
    @Published private(set) var locationUnavailable = false
    @Published private(set) var rateLimited = false
    @Published private(set) var generationUnavailable = false
    @Published private(set) var searched = false
    @Published var toast: String?
    let activity: ActivityType
    private var committedDistanceM: Double
    private let repository: any LoopPlanningRepository
    private let isCurrentAccount: () -> Bool
    private let location: any LoopPlanningLocationProvider
    private let placeSearch: any LoopPlanningPlaceSearch
    let units: MeasurementUnitSystem
    private var locationTask: Task<Void, Never>?
    private var revision = UUID()
    private var searchRevision = UUID()
    private var submittedQuery: String?
    private var recommendationRevision = UUID()
    private var task: Task<Void, Never>?
    private var placeTask: Task<Void, Never>?
    private var recommendationTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var active = true
    private var requestingLocation = false
    private var locationRevision = UUID()
    private struct InputKey: Hashable {
        let start: LoopPlanningRequest.Coordinate
        let via: LoopPlanningRequest.Coordinate?
        let distanceM: Double
        let lessClimbing: Bool
    }
    private var recentResults: [(InputKey, [LoopPlanningCandidate])] = []

    init(activity: ActivityType, distanceM: Double?, units: MeasurementUnitSystem,
         repository: any LoopPlanningRepository,
         placeSearch: any LoopPlanningPlaceSearch,
         location: any LoopPlanningLocationProvider, isCurrentAccount: @escaping () -> Bool) {
        self.activity = activity; self.repository = repository; self.units = units
        committedDistanceM = distanceM ?? units.distanceMeters(from: units == .metric ? 5 : 3)
        self.placeSearch = placeSearch; self.location = location; self.isCurrentAccount = isCurrentAccount
        distanceText = distanceM.map { String(format: "%.1f", units.distanceValue(meters: $0)) } ?? (units == .metric ? "5" : "3")
    }
    var current: Bool { active && isCurrentAccount() }
    var supported: Bool { [.running, .walking, .hiking].contains(activity) }
    var distanceM: Double? {
        committedDistanceM.isFinite && (1000...50000).contains(committedDistanceM) ? committedDistanceM : nil
    }
    func validDistanceText(_ text: String) -> Bool {
        (text == distanceText && distanceM != nil) || parsedDistance(text) != nil
    }
    private func parsedDistance(_ text: String) -> Double? {
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".")), value.isFinite, (1000...50000).contains(units.distanceMeters(from: value)) else { return nil }
        return units.distanceMeters(from: value)
    }
    var canGenerate: Bool { current && supported && start != nil && distanceM != nil && !busy && !locating && !choosingStart && !locationUnavailable }
    func invalidate() { revision = UUID(); task?.cancel(); task = nil; resultsCurrent = false; busy = false; searched = false; generationUnavailable = false; rateLimited = false }
    /// Starting a map/access-point choice invalidates old results and late GPS,
    /// until the optional map adjustment is committed.
    func beginChoosingPoint() {
        guard current else { return }
        invalidate(); stopLocation(); clearSearch(); choosingStart = true
    }
    func cancelChoosingPoint() {
        guard current else { return }
        choosingStart = false; generate(reuseExisting: true)
    }
    private func stopLocation() {
        requestingLocation = false; locating = false; locationRevision = UUID()
        location.cancel(); locationTask?.cancel(); locationTask = nil
    }
    func setStart(_ point: LoopPlanningCoordinate, trigger: GenerationTrigger = .confirmedStart) {
        guard current else { return }
        invalidate()
        switch trigger {
        case .initialLocation, .myLocation: break // GPS context is independent of an in-flight place query.
        default: clearSearch()
        }
        stopLocation(); choosingStart = false; locationUnavailable = false; start = point
        loadRecommendations(); generate(trigger: trigger, reuseExisting: true)
    }
    func setVia(_ point: LoopPlanningCoordinate?, lessClimbing: Bool? = nil) {
        guard current else { return }
        invalidate(); choosingStart = false; via = point
        if let lessClimbing { self.lessClimbing = lessClimbing }
        generate(trigger: .confirmedVia, reuseExisting: true)
    }
    func requestLocation(trigger: GenerationTrigger = .myLocation) {
        guard current else { return }
        stopLocation(); invalidate(); choosingStart = false; requestingLocation = true; locating = true; locationUnavailable = false
        let token = locationRevision
        locationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let point = try await location.locate()
                guard current, requestingLocation, locationRevision == token, !Task.isCancelled else { return }; setStart(point, trigger: trigger)
            } catch {
                guard current, requestingLocation, locationRevision == token, !Task.isCancelled, !(error is CancellationError) else { return }
                requestingLocation = false; locating = false; locationUnavailable = true
                ActivityDiagnosticLog.error(.lifecycle, "route_planner_location_failed category=\(ActivityDiagnosticLog.errorCategory(error))")
                showToast(String(localized: "route.planner.location_unavailable", defaultValue: "Choose a start on the map or enable location access in Settings."))
            }
        }
    }
    func applyDistance(_ text: String) {
        guard current, let meters = text == distanceText ? distanceM : parsedDistance(text) else { return }
        // Rounded display units must never change an untouched workout target.
        committedDistanceM = meters
        distanceText = text; generate(reuseExisting: true)
    }
    func applyPreference(lessClimbing: Bool) {
        guard current else { return }
        self.lessClimbing = lessClimbing; generate(reuseExisting: true)
    }
    func generate(trigger: GenerationTrigger = .explicit, reuseExisting: Bool = false) {
        guard canGenerate, let start, let distanceM else { return }
        let key = InputKey(start: .init(start), via: via.map(LoopPlanningRequest.Coordinate.init), distanceM: distanceM, lessClimbing: lessClimbing)
        let request = LoopPlanningRequest(start: .init(start), via: via.map(LoopPlanningRequest.Coordinate.init), targetDistanceM: distanceM, activityType: LoopPlanningActivity(rawValue: activity.rawValue) ?? .running, variationSeed: Int.random(in: 0...1000000), preference: lessClimbing ? "less_climbing" : "balanced")
        if reuseExisting, let cached = cachedCandidates(for: key, request: request, trigger: trigger) {
            invalidate(); candidates = cached; resultsCurrent = true; searched = true; return
        }
        invalidate(); let token = revision; busy = true; generation = Generation(trigger: trigger)
        task = Task { [weak self] in
            guard let self else { return }
            var nearby: [LoopPlanningCandidate] = []
            do {
                do {
                    nearby = try await repository.existing(request)
                    guard current, revision == token, !Task.isCancelled else { return }
                } catch {
                    guard current, revision == token, !Task.isCancelled else { return }
                    ActivityDiagnosticLog.error(.sync, "route_planner_existing_failed category=\(ActivityDiagnosticLog.errorCategory(error))")
                }
                let result = try await repository.generate(request)
                guard current, revision == token, !Task.isCancelled else { return }
                candidates = LoopPlanningRanking.select(nearby + result, request: request)
                recentResults.removeAll { $0.0 == key }
                recentResults.append((key, candidates))
                if recentResults.count > 4 { recentResults.removeFirst() }
                resultsCurrent = true; searched = true; busy = false
            } catch {
                guard current, revision == token, !Task.isCancelled else { return }
                candidates = LoopPlanningRanking.select(nearby, request: request)
                resultsCurrent = !candidates.isEmpty; busy = false; searched = false; generationUnavailable = true
                ActivityDiagnosticLog.error(.sync, "route_planner_generate_failed category=\(ActivityDiagnosticLog.errorCategory(error))")
                if case let APIError.http(statusCode, _, _) = error, statusCode == 429 { rateLimited = true }
                showToast(generationFailureMessage)
            }
        }
    }
    private func cachedCandidates(for key: InputKey, request: LoopPlanningRequest, trigger: GenerationTrigger) -> [LoopPlanningCandidate]? {
        if let exact = recentResults.last(where: { $0.0 == key }) { return exact.1 }
        // Only a fresh GPS confirmation tolerates small positioning jitter.
        // Address/map choices remain exact; never approximate an explicit start.
        guard trigger == .myLocation else { return nil }
        for (prior, routes) in recentResults.reversed() where prior.via == key.via && prior.distanceM == key.distanceM && prior.lessClimbing == key.lessClimbing {
            guard Self.distance(prior.start, key.start) <= 20 else { continue }
            let valid = routes.compactMap { candidate -> LoopPlanningCandidate? in
                guard let first = candidate.points.first, let last = candidate.points.last,
                      Self.distance(.init(first), .init(last)) <= 100,
                      Self.distance(key.start, candidate.snappedStart) <= 250,
                      Self.distance(key.start, .init(first)) <= 250,
                      Self.distance(key.start, .init(last)) <= 250 else { return nil }
                return .init(id: candidate.id, name: candidate.name, points: candidate.points, distanceM: candidate.distanceM,
                             elevationGainM: candidate.elevationGainM, deviationFraction: candidate.deviationFraction,
                             requestedStart: key.start, snappedStart: candidate.snappedStart, attribution: candidate.attribution, source: candidate.source)
            }
            let selected = LoopPlanningRanking.select(valid, request: request)
            if !selected.isEmpty { return selected }
        }
        return nil
    }
    private static func distance(_ a: LoopPlanningRequest.Coordinate, _ b: LoopPlanningRequest.Coordinate) -> Double {
        let r = Double.pi / 180
        let h = pow(sin((b.latitude-a.latitude)*r/2),2) + cos(a.latitude*r)*cos(b.latitude*r)*pow(sin((b.longitude-a.longitude)*r/2),2)
        return 12742000 * asin(min(1, sqrt(h)))
    }
    var generationFailureMessage: String {
        rateLimited
            ? String(localized: "route.planner.rate_limited", defaultValue: "Please wait a minute before finding more loops, or choose a saved route.")
            : String(localized: "route.planner.unavailable", defaultValue: "Loop generation is unavailable. Try again later, or choose an existing route.")
    }
    func queryChanged(_ query: String) {
        // A queued publication of the exact submitted text is not a new draft.
        guard query != submittedQuery else { return }
        clearSearch()
    }
    func search(_ query: String) {
        guard current else { return }
        clearSearch()
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        submittedQuery = query; placeSearchState = .loading
        let token = searchRevision
        ActivityDiagnosticLog.notice(.sync, "route_planner_place_search state=started")
        placeTask = Task { [weak self] in
            guard let self else { return }
            guard current, searchRevision == token, !Task.isCancelled else { return }
            do {
                let response = try await placeSearch.search(query, near: start)
                guard current, searchRevision == token, !Task.isCancelled else { return }
                places = response; placeSearchState = response.isEmpty ? .empty : .ready
                ActivityDiagnosticLog.notice(.sync, "route_planner_place_search state=completed result_bucket=\(ActivityDiagnosticLog.countBucket(response.count))")
            } catch {
                guard current, searchRevision == token, !Task.isCancelled else { return }
                placeSearchState = .failed
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
    func clearSearch() {
        if placeSearchState == .loading { ActivityDiagnosticLog.notice(.sync, "route_planner_place_search state=cancelled") }
        searchRevision = UUID(); placeTask?.cancel(); places = []; submittedQuery = nil; placeSearchState = .idle
    }
    func showToast(_ message: String) {
        toastTask?.cancel(); toast = message
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4)) // Expected cancellation when feedback is replaced or dismissed.
            guard !Task.isCancelled else { return }; self?.toast = nil
        }
    }
    func cancel() { guard active else { return }; active = false; stopLocation(); invalidate(); candidates = []; recentResults = []; choosingStart = false; start = nil; via = nil; recommendations = []; clearSearch(); recommendationTask?.cancel(); toastTask?.cancel() }
    deinit { locationTask?.cancel(); task?.cancel(); placeTask?.cancel(); recommendationTask?.cancel(); toastTask?.cancel() }
}
