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
@MainActor struct HTTPLoopPlanningRepository: LoopPlanningRepository {
    func generate(_ request: LoopPlanningRequest) async throws -> [LoopPlanningCandidate] {
        try await APIClient.shared.generateLoopRoutes(request).candidates.map(\.domain)
    }
    func existing(_ request: LoopPlanningRequest) async throws -> [LoopPlanningCandidate] {
        let response = try await APIClient.shared.fetchNearbyRoutes(latitude: request.start.latitude, longitude: request.start.longitude, radiusKM: 2)
        let matches = response.routes.filter {
            $0.activityType == request.activityType.rawValue && $0.routeShape == "loop"
                && abs($0.distanceM / request.targetDistanceM - 1) <= 0.1
        }
        var result: [LoopPlanningCandidate] = []
        for summary in matches.prefix(6) {
            try Task.checkCancellation()
            let detail = try await APIClient.shared.fetchCommunityRoute(id: summary.id)
            guard let route = detail.prepared, route.isUsableForGuidance, let originalFirst = route.points.first,
                  let originalLast = route.points.last, Self.distance(.init(latitude: originalFirst.latitude, longitude: originalFirst.longitude), .init(latitude: originalLast.latitude, longitude: originalLast.longitude)) < 100 else { continue }
            let points = route.points.map { LoopPlanningCoordinate(latitude: $0.latitude, longitude: $0.longitude, altitude: $0.altitude) }
            if let via = request.via, !points.contains(where: { Self.distance($0, .init(latitude: via.latitude, longitude: via.longitude)) < 100 }) { continue }
            let distance = zip(points, points.dropFirst()).reduce(0) { $0 + Self.distance($1.0, $1.1) }
            guard abs(distance / request.targetDistanceM - 1) <= 0.1 else { continue }
            result.append(.init(id: route.id, name: route.name, points: points, distanceM: distance,
                elevationGainM: detail.elevationGainM, deviationFraction: distance / request.targetDistanceM - 1,
                requestedStart: request.start, snappedStart: .init(points[0]), attribution: detail.owner.displayName, source: .community))
            if result.count == 3 { break }
        }
        return result
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
