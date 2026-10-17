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
    let activityType: ActivityType

    var plainstrideSessionUUID: UUID? = nil
    var sourceBundleIdentifier: String? = nil

    var isRunning: Bool { activityType == .running }

    var summaryLine: String {
        summaryLine(unitSystem: .metric)
    }

    func summaryLine(unitSystem: MeasurementUnitSystem) -> String {
        let minutes = max(1, Int((Double(durationSeconds) / 60).rounded()))
        var parts = [String(format: String(localized: "health.import.minutes.format", defaultValue: "%d min"), locale: .autoupdatingCurrent, minutes)]

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
    @Published private(set) var importCandidates: [ImportedWorkout] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastErrorMessage: String?
    @Published var isReviewPresented = false

    private let service: HealthKitServing
    private let defaults: UserDefaults
    private let lastCheckKey = "apple_health_import_last_check_v1"
    private let dismissedIDsKey = "apple_health_import_dismissed_ids_v1"

    init(service: HealthKitServing? = nil, defaults: UserDefaults = .standard) {
        self.service = service ?? HealthKitService()
        self.defaults = defaults
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


    func personalizationData(since: Date) async throws -> HealthPersonalizationData {
        try await service.fetchPersonalizationData(since: since)
    }

    func checkForNewWorkouts(existingExternalIDs: Set<String>, presentWhenFound: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let initialStart = Calendar.current.date(byAdding: .weekOfYear, value: -8, to: Date()) ?? .distantPast
            // A Watch can stay offline for days; its workout may arrive much
            // later than its end date. UUID filtering makes this bounded rescan safe.
            let data = try await service.fetchPersonalizationData(since: initialStart)
            let dismissedIDs = Set(defaults.stringArray(forKey: dismissedIDsKey) ?? [])
            let suppressedSessions = Set(defaults.stringArray(forKey: "watch.suppressedSessionIDs") ?? [])
            importCandidates = data.recentWorkouts.filter {
                !existingExternalIDs.contains($0.id) && !dismissedIDs.contains($0.id) &&
                    ($0.plainstrideSessionUUID.map { suppressedSessions.contains($0.uuidString) } != true) &&
                    ($0.plainstrideSessionUUID == nil || $0.plainstrideSessionUUID != PhoneWorkoutSessionCoordinator.shared.currentSessionUUID)
            }
            lastErrorMessage = nil
            if presentWhenFound, !importCandidates.isEmpty {
                isReviewPresented = true
            }
        } catch {
            lastErrorMessage = Self.message(for: error)
        }
    }

    func finishImport(importedIDs: Set<String>) {
        importCandidates.removeAll { importedIDs.contains($0.id) }
        if importCandidates.isEmpty {
            defaults.set(Date(), forKey: lastCheckKey)
        }
        isReviewPresented = false
    }

    func dismissCandidates() {
        let prior = Set(defaults.stringArray(forKey: dismissedIDsKey) ?? [])
        defaults.set(Array(prior.union(importCandidates.map(\.id))).sorted(), forKey: dismissedIDsKey)
        importCandidates = []
        defaults.set(Date(), forKey: lastCheckKey)
        isReviewPresented = false
    }

    func closeReview() {
        isReviewPresented = false
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription
            ?? String(localized: "health.import.load_error", defaultValue: "Apple Health workouts could not be loaded.")
    }
}

/// Local deletion/discard must not be undone by delayed Watch Health sync.
@MainActor
enum WatchWorkoutImportSuppression {
    static func remember(_ metadata: ActivityRecordingSessionMetadata?) {
        guard let metadata, metadata.healthKitOwnership == .appleWatchPrimary else { return }
        let key = "watch.suppressedSessionIDs"
        let previous = UserDefaults.standard.stringArray(forKey: key) ?? []
        guard !previous.contains(metadata.sessionUUID.uuidString) else { return }
        UserDefaults.standard.set(previous + [metadata.sessionUUID.uuidString], forKey: key)
    }
}
