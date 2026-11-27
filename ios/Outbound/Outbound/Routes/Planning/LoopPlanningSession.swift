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
    @Published private(set) var startLabel = String(localized: "route.planner.my_location", defaultValue: "My location")
    @Published private(set) var start: LoopPlanningCoordinate?
    @Published private(set) var includedPlace: LoopPlanningPlace?
    var via: LoopPlanningCoordinate? { includedPlace?.coordinate }
    @Published private(set) var candidates: [LoopPlanningCandidate] = []
    enum PlaceSearchState: Equatable { case idle, loading, ready, empty, failed }
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
    private let cache: (any LoopPlanningCache)?
    private let account: ActivityAccountContext
    private var recentResults: [LoopPlanningCacheEntry] = []
    struct CacheEvent: Equatable {
        let id = UUID()
        let result: String
    }
    @Published private(set) var cacheEvent: CacheEvent?

    init(activity: ActivityType, distanceM: Double?, units: MeasurementUnitSystem,
         repository: any LoopPlanningRepository,
         placeSearch: any LoopPlanningPlaceSearch,
         location: any LoopPlanningLocationProvider, cache: (any LoopPlanningCache)? = nil,
         account: ActivityAccountContext = ActivityAccountBoundary.current, isCurrentAccount: @escaping () -> Bool) {
        self.activity = activity; self.repository = repository; self.units = units
        self.cache = cache; self.account = account
        committedDistanceM = distanceM ?? units.distanceMeters(from: units == .metric ? 5 : 3)
        self.placeSearch = placeSearch; self.location = location; self.isCurrentAccount = isCurrentAccount
        start = location.cachedLocation()
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
    func invalidate() { restoredRoute = nil; revision = UUID(); task?.cancel(); task = nil; resultsCurrent = false; busy = false; searched = false; generationUnavailable = false; rateLimited = false }
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
    func setStart(_ point: LoopPlanningCoordinate, trigger: GenerationTrigger = .confirmedStart, label: String? = nil) {
        guard current else { return }
        invalidate()
        startLabel = label ?? ((trigger == .initialLocation || trigger == .myLocation) ? String(localized: "route.planner.my_location", defaultValue: "My location") : String(localized: "route.planner.map_start", defaultValue: "Map location"))
        switch trigger {
        case .initialLocation, .myLocation: break // GPS context is independent of an in-flight place query.
        default: clearSearch()
        }
        stopLocation(); choosingStart = false; locationUnavailable = false; start = point
        loadRecommendations(); generate(trigger: trigger, reuseExisting: true)
    }
    func setVia(_ point: LoopPlanningCoordinate?, name: String? = nil, lessClimbing: Bool? = nil) {
        guard current else { return }
        invalidate(); choosingStart = false
        includedPlace = point.map { LoopPlanningPlace(id: UUID(), name: name ?? String(localized: "route.planner.via", defaultValue: "Waypoint"), coordinate: $0) }
        if let lessClimbing { self.lessClimbing = lessClimbing }
        generate(trigger: .confirmedVia, reuseExisting: true)
    }
    /// The opening captures a valid shared fix synchronously, before its first map render.
    func beginInitialLocation() {
        guard current else { return }
        if let point = location.cachedLocation() {
            locationSourceResult = "cached"
            setStart(point, trigger: .initialLocation)
        } else { requestLocation(trigger: .initialLocation) }
    }
    @Published private(set) var locationSourceResult: String?
    func requestLocation(trigger: GenerationTrigger = .myLocation) {
        guard current else { return }
        stopLocation(); invalidate(); choosingStart = false; requestingLocation = true; locating = true; locationUnavailable = false
        if let point = location.cachedLocation() {
            locationSourceResult = "cached"
            setStart(point, trigger: trigger); return
        }
        let token = locationRevision
        locationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let point = try await location.locate()
                guard current, requestingLocation, locationRevision == token, !Task.isCancelled else { return }; locationSourceResult = "fresh"; setStart(point, trigger: trigger)
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
        let request = LoopPlanningRequest(start: .init(start), via: via.map(LoopPlanningRequest.Coordinate.init), targetDistanceM: distanceM, activityType: LoopPlanningActivity(rawValue: activity.rawValue) ?? .running, variationSeed: Int.random(in: 0...1000000), preference: lessClimbing ? "less_climbing" : "balanced")
        invalidate(); let token = revision; busy = true
        task = Task { [weak self] in
            guard let self else { return }
            var entries = recentResults
            var expired = entries.contains { !$0.fresh(at: Date()) }
            if let cache {
                do {
                    let saved = try await cache.load(account: account)
                    entries += saved.entries; expired = expired || saved.discardedExpired
                }
                catch is CancellationError { return }
                catch {
                    guard current, revision == token, !Task.isCancelled else { return }
                    cacheEvent = .init(result: "error")
                    ActivityDiagnosticLog.error(.sync, "route_cache_read_failed category=\(ActivityDiagnosticLog.errorCategory(error))")
                }
            }
            guard current, revision == token, !Task.isCancelled else { return }
            let fallback = LoopPlanningCacheEntry.matching(entries, request: request)
            if reuseExisting, !fallback.isEmpty {
                candidates = fallback; resultsCurrent = true
                cacheEvent = .init(result: "hit")
            }
            if fallback.isEmpty || !reuseExisting { cacheEvent = .init(result: reuseExisting ? (expired ? "expired" : "miss") : "bypass") }
            await fetch(request, token: token, fallback: fallback, reuseExisting: reuseExisting, trigger: trigger)
        }
    }
    private func fetch(_ request: LoopPlanningRequest, token: UUID, fallback: [LoopPlanningCandidate], reuseExisting: Bool, trigger: GenerationTrigger) async {
        var nearby: [LoopPlanningCandidate] = []
        do {
            do {
                nearby = try await repository.existing(request)
                guard current, revision == token, !Task.isCancelled else { return }
            } catch {
                guard current, revision == token, !Task.isCancelled else { return }
                ActivityDiagnosticLog.error(.sync, "route_planner_existing_failed category=\(ActivityDiagnosticLog.errorCategory(error))")
            }
            let available = LoopPlanningRanking.select(nearby + fallback, request: request)
            if reuseExisting && !available.isEmpty {
                candidates = available; resultsCurrent = true
            }
            if reuseExisting && available.count == 3 {
                searched = true; busy = false; return
            }
            generation = Generation(trigger: trigger)
            let result = try await repository.generate(request)
            guard current, revision == token, !Task.isCancelled else { return }
            candidates = LoopPlanningRanking.select(nearby + result + fallback, request: request)
            let successful = result.map { LoopPlanningCacheEntry(storedAt: Date(), request: request, route: $0) }.filter(\.valid)
            recentResults.removeAll { old in successful.contains { $0.route.id == old.route.id } }
            recentResults = Array((recentResults.filter { $0.fresh(at: Date()) } + successful).suffix(30))
            if !successful.isEmpty, let cache {
                do { try await cache.store(successful.map(\.route), request: request, account: account) }
                catch is CancellationError { return }
                catch {
                    guard current, revision == token, !Task.isCancelled else { return }
                    cacheEvent = .init(result: "error")
                    ActivityDiagnosticLog.error(.sync, "route_cache_write_failed category=\(ActivityDiagnosticLog.errorCategory(error))")
                }
                guard current, revision == token, !Task.isCancelled else { return }
            }
            resultsCurrent = true; searched = true; busy = false
        } catch {
            guard current, revision == token, !Task.isCancelled else { return }
            candidates = LoopPlanningRanking.select(nearby + fallback, request: request)
            resultsCurrent = !candidates.isEmpty; busy = false; searched = false; generationUnavailable = true
            ActivityDiagnosticLog.error(.sync, "route_planner_generate_failed category=\(ActivityDiagnosticLog.errorCategory(error))")
            if case let APIError.http(statusCode, _, _) = error, statusCode == 429 { rateLimited = true }
            showToast(fallback.isEmpty ? generationFailureMessage : String(localized: "route.planner.cached_fallback", defaultValue: "Couldn’t load new routes. Showing saved suggestions."))
        }
    }
    var generationFailureMessage: String {
        rateLimited
            ? String(localized: "route.planner.rate_limited", defaultValue: "Please wait a minute before finding more loops, or choose a saved route.")
            : String(localized: "route.planner.unavailable", defaultValue: "Loop generation is unavailable. Try again later, or choose an existing route.")
    }
    func queryChanged(_ query: String) {
        // SwiftUI may publish the exact submitted text after the keyboard action.
        guard query != submittedQuery else { return }
        search(query, debounce: true)
    }
    func search(_ query: String, debounce: Bool = false) {
        guard current else { return }
        clearSearch()
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        submittedQuery = query; placeSearchState = .loading
        let token = searchRevision
        placeTask = Task { [weak self] in
            guard let self else { return }
            do {
                if debounce { try await Task.sleep(for: .milliseconds(300)) }
                guard current, searchRevision == token, !Task.isCancelled else { return }
                ActivityDiagnosticLog.notice(.sync, "route_planner_place_search state=started")
                let response = try await placeSearch.search(query, near: start)
                guard current, searchRevision == token, !Task.isCancelled else { return }
                places = response; placeSearchState = response.isEmpty ? .empty : .ready
                ActivityDiagnosticLog.notice(.sync, "route_planner_place_search state=completed result_bucket=\(ActivityDiagnosticLog.countBucket(response.count))")
            } catch {
                guard current, searchRevision == token, !Task.isCancelled, !(error is CancellationError) else { return }
                placeSearchState = .failed
                ActivityDiagnosticLog.error(.sync, "route_planner_place_search_failed category=\(ActivityDiagnosticLog.errorCategory(error))")
            }
        }
    }
    private(set) var restoredRoute: PreparedRoute?
    func restoreSelection(_ route: PreparedRoute) {
        guard current, route.isUsableForGuidance, let first = route.directedPoints.first else { return }
        restoredRoute = route
        let points = route.directedPoints.map { LoopPlanningCoordinate(latitude: $0.latitude, longitude: $0.longitude, altitude: $0.altitude) }
        let distance = zip(points, points.dropFirst()).reduce(0.0) { $0 + LoopPlanningCacheEntry.distance(.init($1.0), .init($1.1)) }
        let gain: Double? = points.allSatisfy { $0.altitude != nil }
            ? zip(points, points.dropFirst()).reduce(0) { $0 + max(0, $1.1.altitude! - $1.0.altitude!) } : nil
        let origin = LoopPlanningRequest.Coordinate(.init(latitude: first.latitude, longitude: first.longitude))
        start = points.first; startLabel = route.name
        candidates = [.init(id: route.id, name: route.name, points: points, distanceM: distance, elevationGainM: gain,
                            deviationFraction: 0, requestedStart: origin, snappedStart: origin,
                            attribution: route.attribution ?? "", source: LoopPlanningSource(rawValue: route.source.rawValue) ?? .imported, saved: true)]
        resultsCurrent = true
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
    func cancel() { guard active else { return }; active = false; stopLocation(); invalidate(); candidates = []; recentResults = []; choosingStart = false; start = nil; includedPlace = nil; recommendations = []; clearSearch(); recommendationTask?.cancel(); toastTask?.cancel() }
    deinit { locationTask?.cancel(); task?.cancel(); placeTask?.cancel(); recommendationTask?.cancel(); toastTask?.cancel() }
}
