import Combine
import Foundation

struct ImportedWorkout: Identifiable, Equatable {
    let id: String
    let activityName: String
    let sourceName: String
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: Int
    let distanceMeters: Double?
    let energyBurnedKilocalories: Double?

    var summaryLine: String {
        summaryLine(unitSystem: .metric)
    }

    func summaryLine(unitSystem: MeasurementUnitSystem) -> String {
        var parts = [durationSeconds.formatted()]

        if let distanceMeters {
            parts.append(unitSystem.distanceString(meters: distanceMeters))
        }

        if let energyBurnedKilocalories {
            parts.append("\(Int(energyBurnedKilocalories.rounded())) kcal")
        }

        return parts.joined(separator: " • ")
    }
}

@MainActor
final class HealthAuthorizationStore: ObservableObject {
    @Published private(set) var snapshot: HealthAuthorizationSnapshot
    @Published private(set) var isRefreshing = false
    @Published private(set) var isRequestingAccess = false
    @Published private(set) var lastErrorMessage: String?

    private let service: HealthKitServing

    init(service: HealthKitServing? = nil) {
        let resolvedService = service ?? HealthKitService()
        self.service = resolvedService
        self.snapshot = resolvedService.currentAuthorizationSnapshot()
    }

    func refresh() async {
        isRefreshing = true
        snapshot = await service.refreshAuthorizationSnapshot()
        isRefreshing = false
    }

    func requestAuthorization() async {
        guard snapshot.isHealthDataAvailable else { return }

        isRequestingAccess = true
        lastErrorMessage = nil

        do {
            snapshot = try await service.requestAuthorization()
        } catch {
            lastErrorMessage = HealthAuthorizationStore.message(for: error)
            snapshot = await service.refreshAuthorizationSnapshot()
        }

        isRequestingAccess = false
    }

    var actionLabel: String {
        switch snapshot.requestState {
        case .notRequested:
            return "Connect Apple Health"
        case .reviewed:
            return "Review Access"
        case .unknown:
            return "Check Access"
        case .unavailable:
            return "Unavailable"
        }
    }

    private static func message(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return "Apple Health access could not be updated in this build."
    }
}

@MainActor
final class HealthImportStore: ObservableObject {
    @Published private(set) var recentWorkouts: [ImportedWorkout] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastErrorMessage: String?

    private let service: HealthKitServing

    init(service: HealthKitServing? = nil) {
        self.service = service ?? HealthKitService()
    }

    func refreshRecentWorkouts(limit: Int = 3) async {
        isLoading = true
        defer { isLoading = false }

        do {
            recentWorkouts = try await service.fetchRecentWorkouts(limit: limit)
            lastErrorMessage = nil
        } catch {
            recentWorkouts = []
            if let localizedError = error as? LocalizedError,
               let description = localizedError.errorDescription {
                lastErrorMessage = description
            } else {
                lastErrorMessage = "Recent Apple Health workouts could not be loaded."
            }
        }
    }
}
