import Foundation

/// Feature-owned port. Entries retain the original intent and canonical provider geometry.
nonisolated protocol LoopPlanningCache: Sendable {
    func load(account: ActivityAccountContext) async throws -> LoopPlanningCacheRead
    func store(_ routes: [LoopPlanningCandidate], request: LoopPlanningRequest, account: ActivityAccountContext) async throws
}

nonisolated struct LoopPlanningCacheRead {
    let entries: [LoopPlanningCacheEntry]
    var discardedExpired = false
}

nonisolated struct LoopPlanningCacheEntry: Codable {
    let storedAt: Date
    let request: LoopPlanningRequest
    let route: LoopPlanningCandidate

    static let lifetime: TimeInterval = 7 * 24 * 60 * 60
    func fresh(at now: Date) -> Bool { storedAt <= now && now.timeIntervalSince(storedAt) < Self.lifetime }
    var valid: Bool {
        let points = route.points
        return route.source == .generated && route.distanceM.isFinite && route.distanceM > 0
            && request.targetDistanceM.isFinite && (1000...50000).contains(request.targetDistanceM)
            && abs(route.distanceM / request.targetDistanceM - 1) <= 0.1
            && ["balanced", "less_climbing"].contains(request.preference)
            && [request.start, route.requestedStart, route.snappedStart].allSatisfy(Self.validCoordinate)
            && (request.via.map(Self.validCoordinate) ?? true)
            && points.count >= 3 && points.count <= 100000
            && points.allSatisfy { Self.validCoordinate(.init($0)) && ($0.altitude?.isFinite ?? true) }
            && (route.elevationGainM.map { $0.isFinite && $0 >= 0 } ?? true)
            && route.deviationFraction.isFinite
            && Self.distance(.init(points[0]), .init(points[points.count - 1])) <= 100
            && Self.distance(route.snappedStart, .init(points[0])) <= 50
            && Self.distance(request.start, .init(points[0])) <= 250
            && (request.via.map { via in points.contains { Self.distance(via, .init($0)) <= 100 } } ?? true)
    }
    static func validCoordinate(_ p: LoopPlanningRequest.Coordinate) -> Bool {
        p.latitude.isFinite && p.longitude.isFinite && abs(p.latitude) <= 90 && abs(p.longitude) <= 180
    }
    static func distance(_ a: LoopPlanningRequest.Coordinate, _ b: LoopPlanningRequest.Coordinate) -> Double {
        let r = Double.pi / 180
        let h = pow(sin((b.latitude-a.latitude)*r/2),2) + cos(a.latitude*r)*cos(b.latitude*r)*pow(sin((b.longitude-a.longitude)*r/2),2)
        return 12742000 * asin(min(1, sqrt(h)))
    }
    static func matching(_ entries: [Self], request: LoopPlanningRequest, now: Date = Date()) -> [LoopPlanningCandidate] {
        let matches = entries.reversed().compactMap { entry -> LoopPlanningCandidate? in
            let route = entry.route
            guard entry.fresh(at: now), entry.valid,
                  entry.request.activityType == request.activityType, entry.request.preference == request.preference,
                  entry.request.via == request.via, // An explicit required place is never approximated.
                  let first = route.points.first, let last = route.points.last,
                  distance(request.start, .init(first)) <= 50,
                  distance(request.start, route.snappedStart) <= 50,
                  distance(request.start, .init(last)) <= 50 else { return nil }
            return .init(id: route.id, name: route.name, points: route.points, distanceM: route.distanceM,
                         elevationGainM: route.elevationGainM, deviationFraction: route.distanceM / request.targetDistanceM - 1,
                         requestedStart: request.start, snappedStart: route.snappedStart, attribution: route.attribution, source: route.source)
        }
        return LoopPlanningRanking.select(matches, request: request)
    }
}
