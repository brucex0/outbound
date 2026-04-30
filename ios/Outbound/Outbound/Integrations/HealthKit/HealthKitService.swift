import Foundation

#if canImport(HealthKit)
import HealthKit
#endif

struct HealthAuthorizationSnapshot: Equatable {
    let isHealthDataAvailable: Bool
    let requestState: HealthAuthorizationRequestState
    let workoutShareState: HealthShareAuthorizationState
    let readDataTypeTitles: [String]

    static let unavailable = HealthAuthorizationSnapshot(
        isHealthDataAvailable: false,
        requestState: .unavailable,
        workoutShareState: .unknown,
        readDataTypeTitles: []
    )

    var statusTitle: String {
        guard isHealthDataAvailable else { return "Not available on this device" }

        switch workoutShareState {
        case .authorized:
            return "Write-back ready"
        case .denied:
            return "Access reviewed"
        case .notDetermined:
            return requestState == .reviewed ? "Access reviewed" : "Permission not requested"
        case .unknown:
            switch requestState {
            case .notRequested:
                return "Permission not requested"
            case .reviewed:
                return "Access reviewed"
            case .unknown:
                return "Available on this iPhone"
            case .unavailable:
                return "Not available on this device"
            }
        }
    }

    var statusDetail: String {
        guard isHealthDataAvailable else {
            return "Apple Health is only available on supported iPhone hardware."
        }

        switch workoutShareState {
        case .authorized:
            return "Outbound can request workout write-back once HealthKit entitlements are enabled for this app."
        case .denied:
            return "Health permissions were previously reviewed. You can reopen the system sheet to adjust access."
        case .notDetermined:
            switch requestState {
            case .reviewed:
                return "The system has already reviewed this permission set for at least one type."
            case .notRequested, .unknown:
                return "Start with workouts, routes, heart rate, active energy, distance, and resting heart rate."
            case .unavailable:
                return "Apple Health is unavailable in the current environment."
            }
        case .unknown:
            switch requestState {
            case .notRequested:
                return "Start with workouts, routes, heart rate, active energy, distance, and resting heart rate."
            case .reviewed:
                return "Health permissions were previously reviewed for this app."
            case .unknown:
                return "This scaffold can request workout import and write-back access when the build is properly signed."
            case .unavailable:
                return "Apple Health is unavailable in the current environment."
            }
        }
    }
}

enum HealthAuthorizationRequestState: Equatable {
    case unknown
    case notRequested
    case reviewed
    case unavailable
}

enum HealthShareAuthorizationState: Equatable {
    case unknown
    case notDetermined
    case denied
    case authorized
}

protocol HealthKitServing {
    func currentAuthorizationSnapshot() -> HealthAuthorizationSnapshot
    func refreshAuthorizationSnapshot() async -> HealthAuthorizationSnapshot
    func requestAuthorization() async throws -> HealthAuthorizationSnapshot
}

enum HealthKitServiceError: LocalizedError {
    case unavailable
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Apple Health is not available on this device."
        case let .requestFailed(message):
            return message
        }
    }
}

struct HealthKitService: HealthKitServing {
#if canImport(HealthKit)
    private let healthStore = HKHealthStore()
#endif

    func currentAuthorizationSnapshot() -> HealthAuthorizationSnapshot {
        makeSnapshot(requestState: .unknown)
    }

    func refreshAuthorizationSnapshot() async -> HealthAuthorizationSnapshot {
#if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }

        do {
            let requestStatus = try await fetchRequestStatus()
            return makeSnapshot(requestState: mapRequestStatus(requestStatus))
        } catch {
            return makeSnapshot(requestState: .unknown)
        }
#else
        return .unavailable
#endif
    }

    func requestAuthorization() async throws -> HealthAuthorizationSnapshot {
#if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitServiceError.unavailable
        }

        do {
            try await requestAuthorizationInternal()
        } catch {
            throw HealthKitServiceError.requestFailed(error.localizedDescription)
        }

        return await refreshAuthorizationSnapshot()
#else
        throw HealthKitServiceError.unavailable
#endif
    }

    private func makeSnapshot(requestState: HealthAuthorizationRequestState) -> HealthAuthorizationSnapshot {
#if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }

        let workoutType = HKObjectType.workoutType()
        let workoutShareState = mapShareStatus(healthStore.authorizationStatus(for: workoutType))

        return HealthAuthorizationSnapshot(
            isHealthDataAvailable: true,
            requestState: requestState,
            workoutShareState: workoutShareState,
            readDataTypeTitles: readDataTypes.map(\.title)
        )
#else
        return .unavailable
#endif
    }
}

#if canImport(HealthKit)
private extension HealthKitService {
    var readDataTypes: [HealthReadableType] {
        var types: [HealthReadableType] = [
            HealthReadableType(title: "Workouts", objectType: HKObjectType.workoutType()),
            HealthReadableType(title: "Workout routes", objectType: HKSeriesType.workoutRoute())
        ]

        let quantityIdentifiers: [(HKQuantityTypeIdentifier, String)] = [
            (.heartRate, "Heart rate"),
            (.activeEnergyBurned, "Active energy"),
            (.distanceWalkingRunning, "Running distance"),
            (.restingHeartRate, "Resting heart rate")
        ]

        for (identifier, title) in quantityIdentifiers {
            if let objectType = HKObjectType.quantityType(forIdentifier: identifier) {
                types.append(HealthReadableType(title: title, objectType: objectType))
            }
        }

        return types
    }

    var shareTypes: Set<HKSampleType> {
        [HKObjectType.workoutType()]
    }

    var readTypes: Set<HKObjectType> {
        Set(readDataTypes.map(\.objectType))
    }

    func fetchRequestStatus() async throws -> HKAuthorizationRequestStatus {
        try await withCheckedThrowingContinuation { continuation in
            healthStore.getRequestStatusForAuthorization(toShare: shareTypes, read: readTypes) { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }

    func requestAuthorizationInternal() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: shareTypes, read: readTypes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: HealthKitServiceError.requestFailed("Apple Health access was not granted."))
                }
            }
        }
    }

    func mapRequestStatus(_ status: HKAuthorizationRequestStatus) -> HealthAuthorizationRequestState {
        switch status {
        case .shouldRequest:
            return .notRequested
        case .unnecessary:
            return .reviewed
        case .unknown:
            return .unknown
        @unknown default:
            return .unknown
        }
    }

    func mapShareStatus(_ status: HKAuthorizationStatus) -> HealthShareAuthorizationState {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .sharingDenied:
            return .denied
        case .sharingAuthorized:
            return .authorized
        @unknown default:
            return .unknown
        }
    }
}

private struct HealthReadableType {
    let title: String
    let objectType: HKObjectType
}
#endif
