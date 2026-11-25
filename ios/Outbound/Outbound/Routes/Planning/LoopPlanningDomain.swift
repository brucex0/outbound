import Foundation

nonisolated struct LoopPlanningCoordinate: Codable, Hashable {
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    init(latitude: Double, longitude: Double, altitude: Double? = nil) {
        self.latitude = latitude; self.longitude = longitude; self.altitude = altitude
    }
}
nonisolated enum LoopPlanningActivity: String, Codable { case running, walking, hiking, cycling }
nonisolated enum LoopPlanningSource: String, Codable { case generated, community }

nonisolated struct LoopPlanningRequest: Codable {
    struct Coordinate: Codable, Hashable {
        let latitude: Double
        let longitude: Double
        init(_ point: LoopPlanningCoordinate) { latitude = point.latitude; longitude = point.longitude }
    }
    let start: Coordinate
    let via: Coordinate?
    let targetDistanceM: Double
    let activityType: LoopPlanningActivity
    let variationSeed: Int
    let preference: String
}
nonisolated struct LoopPlanningPlace: Identifiable {
    let id: UUID
    let name: String
    let coordinate: LoopPlanningCoordinate
}
nonisolated struct LoopPlanningCandidate: Identifiable, Codable {
    let id: String
    let name: String?
    let points: [LoopPlanningCoordinate]
    let distanceM: Double
    let elevationGainM: Double?
    let deviationFraction: Double
    let requestedStart: LoopPlanningRequest.Coordinate
    let snappedStart: LoopPlanningRequest.Coordinate
    let attribution: String
    let source: LoopPlanningSource
}
@MainActor protocol LoopPlanningRepository {
    func generate(_ request: LoopPlanningRequest) async throws -> [LoopPlanningCandidate]
    func existing(_ request: LoopPlanningRequest) async throws -> [LoopPlanningCandidate]
}
@MainActor protocol LoopPlanningPlaceSearch {
    func search(_ query: String, near: LoopPlanningCoordinate?) async throws -> [LoopPlanningPlace]
    func parks(near: LoopPlanningCoordinate) async throws -> [LoopPlanningPlace]
}
@MainActor protocol LoopPlanningLocationProvider {
    func locate() async throws -> LoopPlanningCoordinate
    func cancel()
}

nonisolated enum LoopPlanningRanking {
    static func select(_ candidates: [LoopPlanningCandidate], request: LoopPlanningRequest) -> [LoopPlanningCandidate] {
        let origin = request.start
        func distance(_ a: LoopPlanningCoordinate, _ b: LoopPlanningCoordinate) -> Double {
            let r = Double.pi / 180
            let h = pow(sin((b.latitude-a.latitude)*r/2),2) + cos(a.latitude*r)*cos(b.latitude*r)*pow(sin((b.longitude-a.longitude)*r/2),2)
            return 12742000 * asin(min(1,sqrt(h)))
        }
        func corridor(_ points: [LoopPlanningCoordinate]) -> [String] {
            func cell(_ point: LoopPlanningCoordinate) -> String {
                let x = (point.longitude-origin.longitude) * 111320 * cos(origin.latitude * .pi / 180)
                let y = (point.latitude-origin.latitude) * 111320
                return "\(Int(floor(x/50))),\(Int(floor(y/50)))"
            }
            guard let first = points.first else { return [] }
            var result = [cell(first)], carried = 0.0
            for (a,b) in zip(points, points.dropFirst()) {
                let length = distance(a,b)
                var at = 25-carried
                while at <= length {
                    let t = at/length
                    let key = cell(.init(latitude: a.latitude+t*(b.latitude-a.latitude), longitude: a.longitude+t*(b.longitude-a.longitude)))
                    if result.last != key { result.append(key) }; at += 25
                }
                carried = (carried+length).truncatingRemainder(dividingBy: 25)
            }
            return result
        }
        let scored = candidates.compactMap { candidate -> (LoopPlanningCandidate, Set<String>, Double)? in
            guard candidate.distanceM.isFinite, candidate.points.count >= 3,
                  candidate.points.allSatisfy({ $0.latitude.isFinite && $0.longitude.isFinite && abs($0.latitude) <= 90 && abs($0.longitude) <= 180 }),
                  abs(candidate.distanceM/request.targetDistanceM-1) <= 0.1 else { return nil }
            let cells = corridor(candidate.points), unique = Set(cells)
            let backtrack = 1-Double(unique.count)/Double(max(1,cells.count))
            guard backtrack < 0.45 else { return nil }
            return (candidate,unique,backtrack)
        }.sorted { a,b in
            if request.preference == "less_climbing" {
                let gainA = a.0.elevationGainM ?? .infinity, gainB = b.0.elevationGainM ?? .infinity
                if gainA != gainB { return gainA < gainB }
            }
            if a.2 != b.2 { return a.2 < b.2 }
            return abs(a.0.deviationFraction) < abs(b.0.deviationFraction)
        }
        var selected: [(LoopPlanningCandidate, Set<String>, Double)] = []
        for candidate in scored {
            guard !selected.contains(where: {
                Double($0.1.intersection(candidate.1).count)/Double(max(1,min($0.1.count,candidate.1.count))) > 0.8
            }) else { continue }
            selected.append(candidate); if selected.count == 3 { break }
        }
        return selected.map(\.0)
    }
}
