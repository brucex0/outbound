import Foundation

@MainActor
final class HealthAuthorizationStore: ObservableObject {
    @Published private(set) var snapshot: HealthAuthorizationSnapshot
    @Published private(set) var isRefreshing = false
    @Published private(set) var isRequestingAccess = false
    @Published private(set) var lastErrorMessage: String?

    private let service: HealthKitServing

    init(service: HealthKitServing = HealthKitService()) {
        self.service = service
        self.snapshot = service.currentAuthorizationSnapshot()
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
