import CoreLocation
import Foundation
import MapKit

nonisolated struct LoopPlanningResponse: Decodable {
    struct CandidateDTO: Decodable {
        let id: String
        let points: [LoopPlanningCoordinate]
        let distanceM: Double
        let elevationGainM: Double?
        let deviationFraction: Double
        let requestedStart: LoopPlanningRequest.Coordinate
        let snappedStart: LoopPlanningRequest.Coordinate
        let attribution: String
        var domain: LoopPlanningCandidate {
            .init(id: id, name: nil, points: points, distanceM: distanceM, elevationGainM: elevationGainM,
                  deviationFraction: deviationFraction, requestedStart: requestedStart, snappedStart: snappedStart, attribution: attribution, source: .generated)
        }
    }
    let candidates: [CandidateDTO]
}
struct LoopPlanningSavedRoute {
    let route: PreparedRoute
    let elevationGainM: Double?
}
@MainActor struct HTTPLoopPlanningRepository: LoopPlanningRepository {
    func generate(_ request: LoopPlanningRequest) async throws -> [LoopPlanningCandidate] {
        try await APIClient.shared.generateLoopRoutes(request).candidates.map(\.domain)
    }
    var personalRoutes: (LoopPlanningRequest) async -> [LoopPlanningSavedRoute] = { _ in [] }
    func existing(_ request: LoopPlanningRequest) async throws -> [LoopPlanningCandidate] {
        let saved = await personalRoutes(request)
        try Task.checkCancellation()
        var result = saved.compactMap { Self.candidate($0.route, request: request, saved: true, gain: $0.elevationGainM) }
        do {
            let response = try await APIClient.shared.fetchNearbyRoutes(latitude: request.start.latitude, longitude: request.start.longitude, radiusKM: 2)
            let matches = response.routes.filter {
                $0.activityType == request.activityType.rawValue && $0.routeShape == "loop"
                    && abs($0.distanceM / request.targetDistanceM - 1) <= 0.1
            }
            for summary in matches.prefix(6) {
                try Task.checkCancellation()
                guard !result.contains(where: { $0.id == summary.id }) else { continue }
                do {
                    let detail = try await APIClient.shared.fetchCommunityRoute(id: summary.id)
                    if let route = detail.prepared,
                       let match = Self.candidate(route, request: request, saved: false, gain: detail.elevationGainM, attribution: detail.owner.displayName) { result.append(match) }
                } catch {
                    try Task.checkCancellation()
                    ActivityDiagnosticLog.error(.sync, "route_planner_detail_failed category=\(ActivityDiagnosticLog.errorCategory(error))")
                }
            }
        } catch {
            try Task.checkCancellation()
            ActivityDiagnosticLog.error(.sync, "route_planner_nearby_failed category=\(ActivityDiagnosticLog.errorCategory(error))")
        }
        return result
    }
    private static func candidate(_ route: PreparedRoute, request: LoopPlanningRequest, saved: Bool, gain: Double? = nil, attribution: String? = nil) -> LoopPlanningCandidate? {
        // Unknown-sport imports remain available via Saved, never auto-matched.
        guard route.activityType?.rawValue == request.activityType.rawValue,
              route.routeShape == nil || route.routeShape == "loop", route.isUsableForGuidance else { return nil }
        let points = route.directedPoints.map { LoopPlanningCoordinate(latitude: $0.latitude, longitude: $0.longitude, altitude: $0.altitude) }
        guard let first = points.first, let last = points.last, distance(first, last) <= 100,
              distance(first, .init(latitude: request.start.latitude, longitude: request.start.longitude)) <= 2000 else { return nil }
        if let via = request.via, !points.contains(where: { distance($0, .init(latitude: via.latitude, longitude: via.longitude)) <= 100 }) { return nil }
        let length = zip(points, points.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
        guard abs(length / request.targetDistanceM - 1) <= 0.1 else { return nil }
        let measuredGain: Double? = points.allSatisfy { $0.altitude != nil }
            ? zip(points, points.dropFirst()).reduce(0) { $0 + max(0, $1.1.altitude! - $1.0.altitude!) } : nil
        return .init(id: route.id, name: route.name, points: points, distanceM: length,
            elevationGainM: gain ?? measuredGain, deviationFraction: length / request.targetDistanceM - 1,
            requestedStart: request.start, snappedStart: .init(first), attribution: route.attribution ?? attribution ?? "",
            source: LoopPlanningSource(rawValue: route.source.rawValue) ?? .imported, saved: saved)
    }
    private static func distance(_ a: LoopPlanningCoordinate, _ b: LoopPlanningCoordinate) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}
@MainActor struct MapKitLoopPlaceSearch: LoopPlanningPlaceSearch {
    func search(_ query: String, near: LoopPlanningCoordinate?) async throws -> [LoopPlanningPlace] {
        let request = MKLocalSearch.Request(); request.naturalLanguageQuery = query
        if let near { request.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: near.latitude, longitude: near.longitude), latitudinalMeters: 15000, longitudinalMeters: 15000) }
        return try await execute(request)
    }
    func parks(near: LoopPlanningCoordinate) async throws -> [LoopPlanningPlace] {
        let request = MKLocalSearch.Request(); request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.park, .nationalPark])
        request.resultTypes = .pointOfInterest; request.naturalLanguageQuery = "parks"
        request.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: near.latitude, longitude: near.longitude), latitudinalMeters: 10000, longitudinalMeters: 10000)
        return try await execute(request)
    }
    private func execute(_ request: MKLocalSearch.Request) async throws -> [LoopPlanningPlace] {
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.prefix(6).map { .init(id: UUID(), name: $0.name ?? "", coordinate: .init(latitude: $0.placemark.coordinate.latitude, longitude: $0.placemark.coordinate.longitude)) }
    }
}
@MainActor final class CoreLocationLoopProvider: LoopPlanningLocationProvider {
    private let source: ForegroundLocationSource
    private var requestID: UUID?
    init(source: ForegroundLocationSource? = nil) { self.source = source ?? .shared }
    func cachedLocation() -> LoopPlanningCoordinate? {
        source.cachedLocation(policy: .planner).map { .init(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
    }
    func locate() async throws -> LoopPlanningCoordinate {
        cancel()
        let id = UUID(); requestID = id
        defer { if requestID == id { requestID = nil } }
        let fix = try await source.locate(id: id, policy: .planner)
        return .init(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude)
    }
    func cancel() {
        if let requestID { source.cancel(id: requestID) }
        requestID = nil
    }
}
