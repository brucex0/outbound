import Foundation
import Testing
@testable import Outbound

struct HealthKitStoreTests {

    @MainActor
    @Test func healthImportStoreLoadsRecentWorkoutsFromService() async throws {
        let workout = ImportedWorkout(
            id: "health-workout-1",
            activityName: "Run",
            sourceName: "Apple Watch",
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            endedAt: Date(timeIntervalSince1970: 1_800_000_900),
            durationSeconds: 900,
            distanceMeters: 5000,
            energyBurnedKilocalories: 420
        )
        let store = HealthImportStore(service: MockHealthKitService(recentWorkouts: [workout]))

        await store.refreshRecentWorkouts(limit: 1)

        #expect(store.recentWorkouts == [workout])
        #expect(store.lastErrorMessage == nil)
        #expect(store.isLoading == false)
    }

    @MainActor
    @Test func healthImportStoreSurfacesServiceErrors() async throws {
        let store = HealthImportStore(service: MockHealthKitService(fetchRecentWorkoutsError: MockError.healthUnavailable))

        await store.refreshRecentWorkouts(limit: 2)

        #expect(store.recentWorkouts.isEmpty)
        #expect(store.lastErrorMessage == "Health data is unavailable for tests.")
        #expect(store.isLoading == false)
    }

    @MainActor
    @Test func healthAuthorizationStoreUsesInitialSnapshotAndActionLabel() {
        let snapshot = HealthAuthorizationSnapshot(
            isHealthDataAvailable: true,
            requestState: .notRequested,
            workoutShareState: .notDetermined,
            readDataTypeTitles: ["Workouts"]
        )
        let store = HealthAuthorizationStore(service: MockHealthKitService(snapshot: snapshot))

        #expect(store.snapshot == snapshot)
        #expect(store.actionLabel == "Connect Apple Health")
    }
}

private struct MockHealthKitService: HealthKitServing {
    var snapshot: HealthAuthorizationSnapshot = HealthAuthorizationSnapshot(
        isHealthDataAvailable: true,
        requestState: .unknown,
        workoutShareState: .unknown,
        readDataTypeTitles: []
    )
    var requestAuthorizationResult: Result<HealthAuthorizationSnapshot, Error>?
    var recentWorkouts: [ImportedWorkout] = []
    var fetchRecentWorkoutsError: Error?

    func currentAuthorizationSnapshot() -> HealthAuthorizationSnapshot {
        snapshot
    }

    func refreshAuthorizationSnapshot() async -> HealthAuthorizationSnapshot {
        snapshot
    }

    func requestAuthorization() async throws -> HealthAuthorizationSnapshot {
        switch requestAuthorizationResult {
        case let .success(snapshot):
            return snapshot
        case let .failure(error):
            throw error
        case .none:
            return snapshot
        }
    }

    func fetchRecentWorkouts(limit: Int) async throws -> [ImportedWorkout] {
        if let fetchRecentWorkoutsError {
            throw fetchRecentWorkoutsError
        }
        return Array(recentWorkouts.prefix(limit))
    }
}

private enum MockError: LocalizedError {
    case healthUnavailable

    var errorDescription: String? {
        switch self {
        case .healthUnavailable:
            return "Health data is unavailable for tests."
        }
    }
}
