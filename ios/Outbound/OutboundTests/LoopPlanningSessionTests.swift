import Foundation
import Testing
@testable import Outbound

@MainActor struct LoopPlanningSessionTests {
    private let origin = LoopPlanningCoordinate(latitude: 47.6101, longitude: -122.2015)

    @Test func myLocationJitterReusesValidatedRoutesButAddressSelectionStaysExact() async throws {
        let repository = Repository(), location = Location()
        location.point = origin
        let session = makeSession(repository, location)
        session.requestLocation(trigger: .initialLocation)
        try await settle { session.resultsCurrent }
        #expect(repository.requests.count == 1)
        let jitter = LoopPlanningCoordinate(latitude: origin.latitude + 0.0001, longitude: origin.longitude)
        location.point = jitter
        session.requestLocation()
        try await settle { !session.locating && session.resultsCurrent }
        #expect(repository.requests.count == 1)
        #expect(session.candidates.first?.requestedStart.latitude == jitter.latitude)
        session.setStart(.init(latitude: jitter.latitude + 0.00005, longitude: jitter.longitude))
        try await settle { session.resultsCurrent }
        #expect(repository.requests.count == 2, "An explicit address five meters away is a distinct choice")
        session.cancel()
    }

    @Test func nearbyGPSCannotReuseGeometryBeyondTheStartSnapLimit() async throws {
        let repository = Repository(), location = Location()
        repository.longitudeOffset = 0.00325 // About 244 m east at this latitude.
        location.point = origin
        let session = makeSession(repository, location)
        session.requestLocation(trigger: .initialLocation)
        try await settle { session.resultsCurrent }
        location.point = .init(latitude: origin.latitude, longitude: origin.longitude - 0.0002) // About 15 m west.
        session.requestLocation()
        try await settle { !session.locating && session.resultsCurrent }
        #expect(repository.requests.count == 2, "Nearby GPS alone must not bypass the 250 m geometry bound")
        session.cancel()
    }

    @Test func pendingLocationAndOptionalPinWaitForTheAcceptedStart() async throws {
        let repository = Repository(), location = Location()
        location.point = origin
        let session = makeSession(repository, location)
        session.requestLocation(trigger: .initialLocation)
        try await settle { session.resultsCurrent }
        location.hold = true
        session.requestLocation()
        session.applyDistance("10")
        #expect(repository.requests.count == 1)
        try await settle { location.pending != nil }
        location.finish(origin)
        try await settle { session.resultsCurrent }
        #expect(repository.requests.count == 2)
        #expect(repository.requests.last?.targetDistanceM == 10000)
        session.beginChoosingPoint()
        session.applyDistance("3")
        #expect(repository.requests.count == 2)
        #expect(!session.resultsCurrent)
        session.cancelChoosingPoint()
        try await settle { session.resultsCurrent }
        #expect(repository.requests.last?.targetDistanceM == 3000)
        session.cancel()
        #expect(session.candidates.isEmpty && session.start == nil && session.via == nil)
    }

    @Test func rateLimitNeverMakesOldGeometrySelectable() async throws {
        let repository = Repository(), location = Location()
        let session = makeSession(repository, location)
        session.setStart(origin)
        try await settle { session.resultsCurrent }
        repository.fail = true
        session.applyDistance("10")
        try await settle { session.generationUnavailable }
        #expect(session.rateLimited)
        #expect(!session.resultsCurrent)
        #expect(session.candidates.isEmpty)
        session.cancel()
    }

    @Test func dismissingSavedRoutesDiscardsItsUnappliedDraft() {
        let points = [RouteCoordinate(latitude: 47.61, longitude: -122.20), RouteCoordinate(latitude: 47.62, longitude: -122.20), RouteCoordinate(latitude: 47.61, longitude: -122.20)]
        let committed = PreparedRoute(id: "attached", name: "Attached", points: points, source: .imported)
        let unapplied = PreparedRoute(id: "draft", name: "Draft", points: points, source: .imported)
        let opening = LoopPlanningPresentation(activity: .running, distanceM: nil, units: .metric, initialSelection: committed)
        opening.openSavedRoutes()
        let discarded = opening.savedDraft
        discarded.chooseImportedRoute(unapplied)
        opening.sheet = nil // The same binding departure used by interactive dismissal.
        #expect(!discarded.belongsToCurrentPresentation)
        opening.openSavedRoutes()
        #expect(opening.savedDraft.selectedRoute?.id == committed.id)
        opening.cancel()
    }

    @Test func identicalSubmittedTextDoesNotCancelItsPlaceSearch() async throws {
        let search = DeferredPlaces(), location = Location()
        location.hold = true
        let session = LoopPlanningSession(activity: .running, distanceM: nil, units: .metric, repository: Repository(),
            placeSearch: search, location: location, isCurrentAccount: { true })
        session.requestLocation(trigger: .initialLocation)
        session.search("fixture address")
        session.queryChanged("fixture address") // Delayed SwiftUI publication of the submitted draft.
        try await settle { search.pending != nil && location.pending != nil }
        location.finish(origin)
        try await settle { session.start != nil }
        #expect(session.placeSearchState == .loading, "A late GPS fix must not cancel the independent address query")
        search.finish([.init(id: UUID(), name: "Fixture", coordinate: origin)])
        try await settle { session.placeSearchState == .ready }
        #expect(session.places.count == 1)
        session.search("second submitted draft")
        try await settle { search.pending != nil }
        session.queryChanged("different draft")
        #expect(session.places.isEmpty && session.placeSearchState == .idle)
        search.finish([.init(id: UUID(), name: "Stale", coordinate: origin)])
        await Task.yield()
        #expect(session.places.isEmpty && session.placeSearchState == .idle)
        session.cancel()
    }

    @Test(arguments: [1000.0, 10000.0, 50000.0])
    func suppliedWorkoutDistanceStaysExactInImperialUnits(_ meters: Double) async throws {
        let repository = Repository()
        let session = LoopPlanningSession(activity: .running, distanceM: meters, units: .imperial, repository: repository,
            placeSearch: Places(), location: Location(), isCurrentAccount: { true })
        session.setStart(origin)
        try await settle { session.resultsCurrent }
        #expect(repository.requests.last?.targetDistanceM == meters)
        #expect(session.validDistanceText(session.distanceText))
        session.applyDistance(session.distanceText)
        #expect(session.distanceM == meters && repository.requests.count == 1)
        session.applyDistance("3")
        try await settle { session.resultsCurrent }
        #expect(repository.requests.last?.targetDistanceM == MeasurementUnitSystem.imperial.distanceMeters(from: 3))
        session.cancel()
    }

    private func makeSession(_ repository: Repository, _ location: Location) -> LoopPlanningSession {
        .init(activity: .running, distanceM: nil, units: .metric, repository: repository,
              placeSearch: Places(), location: location, isCurrentAccount: { true })
    }
    private func settle(_ ready: () -> Bool) async throws {
        for _ in 0..<200 {
            if ready() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Planner command did not settle")
    }

    private final class Repository: LoopPlanningRepository {
        var requests: [LoopPlanningRequest] = []
        var longitudeOffset = 0.0
        var fail = false
        func existing(_ request: LoopPlanningRequest) async throws -> [LoopPlanningCandidate] { [] }
        func generate(_ request: LoopPlanningRequest) async throws -> [LoopPlanningCandidate] {
            requests.append(request)
            if fail { throw APIError.http(statusCode: 429, message: "fixture", code: nil) }
            let radius = request.targetDistanceM / (2 * Double.pi)
            let points = (0...180).map { step in
                let angle = Double(step) * 2 * Double.pi / 180
                return LoopPlanningCoordinate(latitude: request.start.latitude + radius * (cos(angle) - 1) / 111320,
                    longitude: request.start.longitude + longitudeOffset + radius * sin(angle) / (111320 * cos(request.start.latitude * Double.pi / 180)))
            }
            return [.init(id: "fixture", name: nil, points: points, distanceM: request.targetDistanceM,
                elevationGainM: 10, deviationFraction: 0, requestedStart: request.start,
                snappedStart: .init(points[0]), attribution: "Fixture", source: .generated)]
        }
    }
    private final class Location: LoopPlanningLocationProvider {
        var point = LoopPlanningCoordinate(latitude: 0, longitude: 0)
        var hold = false
        var pending: CheckedContinuation<LoopPlanningCoordinate, Error>?
        func locate() async throws -> LoopPlanningCoordinate {
            if !hold { return point }
            return try await withCheckedThrowingContinuation { pending = $0 }
        }
        func finish(_ point: LoopPlanningCoordinate) { let current = pending; pending = nil; current?.resume(returning: point) }
        func cancel() { let current = pending; pending = nil; current?.resume(throwing: CancellationError()) }
    }
    private final class DeferredPlaces: LoopPlanningPlaceSearch {
        var pending: CheckedContinuation<[LoopPlanningPlace], Error>?
        func search(_ query: String, near: LoopPlanningCoordinate?) async throws -> [LoopPlanningPlace] {
            try await withCheckedThrowingContinuation { pending = $0 }
        }
        func parks(near: LoopPlanningCoordinate) async throws -> [LoopPlanningPlace] { [] }
        func finish(_ places: [LoopPlanningPlace]) { let current = pending; pending = nil; current?.resume(returning: places) }
    }
    private struct Places: LoopPlanningPlaceSearch {
        func search(_ query: String, near: LoopPlanningCoordinate?) async throws -> [LoopPlanningPlace] { [] }
        func parks(near: LoopPlanningCoordinate) async throws -> [LoopPlanningPlace] { [] }
    }
}
