import Foundation
import Testing
@testable import Outbound

@MainActor struct LoopPlanningCacheTests {
    private let start = LoopPlanningCoordinate(latitude: 47.61, longitude: -122.20)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func request(start: LoopPlanningCoordinate? = nil, activity: LoopPlanningActivity = .running,
                         target: Double = 5000, via: LoopPlanningCoordinate? = nil, preference: String = "balanced") -> LoopPlanningRequest {
        .init(start: .init(start ?? self.start), via: via.map(LoopPlanningRequest.Coordinate.init), targetDistanceM: target,
              activityType: activity, variationSeed: 1, preference: preference)
    }
    private func entry(id: String = "one", age: TimeInterval = 0, routedOffset: Double = 0) -> LoopPlanningCacheEntry {
        let radius = 5000 / (2 * Double.pi)
        let points = (0...180).map { step in
            let angle = Double(step) * 2 * Double.pi / 180
            return LoopPlanningCoordinate(latitude: start.latitude + routedOffset + radius * (cos(angle)-1)/111320,
                longitude: start.longitude + radius*sin(angle)/(111320*cos(start.latitude * .pi/180)))
        }
        return .init(storedAt: now.addingTimeInterval(-age), request: request(), route: .init(id: id, name: nil,
            points: points, distanceM: 5000, elevationGainM: 10, deviationFraction: 0,
            requestedStart: .init(start), snappedStart: .init(points[0]), attribution: "Provider", source: .generated))
    }
    @Test func actualGeometryBoundaryAndIntentAreRequired() {
        let route = entry()
        func matches(_ r: LoopPlanningRequest) -> [LoopPlanningCandidate] {
            LoopPlanningCacheEntry.matching([route], request: r, now: now)
        }
        let inside = LoopPlanningCoordinate(latitude: start.latitude + 49.9/111195, longitude: start.longitude)
        let outside = LoopPlanningCoordinate(latitude: start.latitude + 50.1/111195, longitude: start.longitude)
        #expect(matches(request(start: inside)).count == 1)
        #expect(matches(request(start: outside)).isEmpty)
        #expect(matches(request(activity: .walking)).isEmpty)
        #expect(matches(request(target: 6000)).isEmpty)
        #expect(matches(request(via: start)).isEmpty)
        #expect(matches(request(preference: "less_climbing")).isEmpty)
        let adjusted = matches(request(target: 5200))[0]
        #expect(adjusted.points == route.route.points && adjusted.distanceM == 5000)
        #expect(adjusted.attribution == route.route.attribution && adjusted.source == .generated)
        #expect(abs(adjusted.deviationFraction - (5000.0/5200-1)) < 0.00001)
        // Prior requested point is nearby, but snapped/first geometry is on the other side of a barrier.
        #expect(LoopPlanningCacheEntry.matching([entry(routedOffset: 200/111195)], request: request(), now: now).isEmpty)
        #expect(LoopPlanningCacheEntry.matching([entry(age: 7*86400)], request: request(), now: now).isEmpty)
        #expect(LoopPlanningCacheEntry.matching([entry(age: 7*86400-1)], request: request(), now: now).count == 1)
    }
    @Test func diskBoundsExpiryLogoutAndStaleAccount() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = ActivityAccountBoundary.current
        ActivityAccountBoundary.activate("cache-test-a")
        let account = ActivityAccountBoundary.current
        defer {
            ActivityAccountBoundary.activate(original.owner.hasPrefix("account:") ? String(original.owner.dropFirst(8)) : nil)
        }
        let instant = now
        let cache = DiskLoopPlanningCache(directory: directory, now: { instant })
        for i in 0..<35 { try await cache.store([entry(id: "route-\(i)").route], request: request(), account: account) }
        let loaded = try await cache.load(account: account).entries
        #expect(loaded.count == 30 && loaded.first?.route.id == "route-5")
        try await cache.store([], request: request(), account: account)
        #expect(try await cache.load(account: account).entries.count == 30)
        let reopened = DiskLoopPlanningCache(directory: directory, now: { instant })
        #expect(try await reopened.load(account: account).entries.count == 30)
        ActivityAccountBoundary.activate("cache-test-b")
        let other = ActivityAccountBoundary.current
        #expect(try await cache.load(account: other).entries.isEmpty)
        do { _ = try await cache.load(account: account); Issue.record("Stale account read accepted") } catch is CancellationError { }
        do { try await cache.store([entry().route], request: request(), account: account); Issue.record("Stale account write accepted") } catch is CancellationError { }
        ActivityAccountBoundary.activate(nil)
        try await cache.purge(account)
        ActivityAccountBoundary.activate("cache-test-a")
        let relogged = ActivityAccountBoundary.current
        #expect(try await cache.load(account: relogged).entries.isEmpty)
        try await cache.store([entry().route], request: request(), account: relogged)
        let expired = DiskLoopPlanningCache(directory: directory, now: { instant.addingTimeInterval(7*86400) })
        #expect(try await expired.load(account: relogged).entries.isEmpty)
        #expect(try await cache.load(account: relogged).entries.isEmpty, "Expired routes are removed from disk")
        try await cache.store([entry().route], request: request(), account: relogged)
        let path = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        var envelope = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
        envelope["schema"] = 999
        try JSONSerialization.data(withJSONObject: envelope).write(to: path, options: .atomic)
        #expect(try await cache.load(account: relogged).entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: path.path))
        try Data("broken json".utf8).write(to: path)
        #expect(try await cache.load(account: relogged).entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: path.path))
    }
}
