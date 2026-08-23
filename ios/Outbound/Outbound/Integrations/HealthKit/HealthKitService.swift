import Foundation
import CoreLocation

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
            return "Plainstride can request workout write-back once HealthKit entitlements are enabled for this app."
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
    func fetchRecentWorkouts(limit: Int) async throws -> [ImportedWorkout]
    func saveWorkout(_ activity: SavedActivity, sport: SportType, energyKilocalories: Double?) async throws
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

    func fetchRecentWorkouts(limit: Int) async throws -> [ImportedWorkout] {
#if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitServiceError.unavailable
        }

        return try await fetchRecentWorkoutsInternal(limit: limit)
#else
        throw HealthKitServiceError.unavailable
#endif
    }

    func saveWorkout(_ activity: SavedActivity, sport: SportType, energyKilocalories: Double?) async throws {
#if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitServiceError.unavailable
        }

        guard healthStore.authorizationStatus(for: .workoutType()) == .sharingAuthorized else {
            throw HealthKitServiceError.requestFailed("Apple Health workout write access has not been granted.")
        }

        try await saveWorkoutInternal(activity, sport: sport, energyKilocalories: energyKilocalories)
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
            HealthReadableType(title: String(localized: "library.workouts", defaultValue: "Workouts"), objectType: HKObjectType.workoutType()),
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
        var types: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute()
        ]

        let distanceIdentifiers: [HKQuantityTypeIdentifier] = [
            .distanceWalkingRunning,
            .distanceCycling,
            .distanceSwimming,
        ]
        for identifier in distanceIdentifiers {
            if let distanceType = HKQuantityType.quantityType(forIdentifier: identifier) {
                types.insert(distanceType)
            }
        }
        if let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(energyType)
        }
        return types
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

    func fetchRecentWorkoutsInternal(limit: Int) async throws -> [ImportedWorkout] {
        try await withCheckedThrowingContinuation { continuation in
            let sortDescriptors = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: nil,
                limit: limit,
                sortDescriptors: sortDescriptors
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let workouts = (samples as? [HKWorkout] ?? []).map { workout in
                    ImportedWorkout(
                        id: workout.uuid.uuidString,
                        activityName: workout.workoutActivityType.displayName,
                        sourceName: workout.sourceRevision.source.name,
                        startedAt: workout.startDate,
                        endedAt: workout.endDate,
                        durationSeconds: Int(workout.duration.rounded()),
                        distanceMeters: workout.totalDistance?.doubleValue(for: .meter()),
                        energyBurnedKilocalories: energyBurnedKilocalories(for: workout)
                    )
                }

                continuation.resume(returning: workouts)
            }

            healthStore.execute(query)
        }
    }

    func saveWorkoutInternal(
        _ activity: SavedActivity,
        sport _: SportType,
        energyKilocalories: Double?
    ) async throws {
        let metadata: [String: Any] = [
            HKMetadataKeyExternalUUID: activity.id.uuidString,
            HKMetadataKeyIndoorWorkout: activity.indoor?.isIndoor ?? false,
            "com.plainstride.outbound.activity-title": activity.title,
            "com.plainstride.outbound.source": activity.source.displayName
        ]
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = switch activity.activityType {
        case .running: .running
        case .cycling: .cycling
        case .walking: .walking
        case .hiking: .hiking
        case .swimming: .swimming
        }
        configuration.locationType = activity.indoor?.isIndoor == true ? .indoor : .outdoor
        let workoutBuilder = HKWorkoutBuilder(
            healthStore: healthStore,
            configuration: configuration,
            device: .local()
        )

        try await begin(workoutBuilder, at: activity.startedAt)
        try await add(metadata, to: workoutBuilder)

        var samples: [HKSample] = []
        let distanceIdentifier: HKQuantityTypeIdentifier = switch activity.activityType {
        case .cycling: .distanceCycling
        case .swimming: .distanceSwimming
        case .running, .walking, .hiking: .distanceWalkingRunning
        }
        if activity.distanceM > 0,
           let distanceType = HKQuantityType.quantityType(forIdentifier: distanceIdentifier) {
            samples.append(HKQuantitySample(
                type: distanceType,
                quantity: HKQuantity(unit: .meter(), doubleValue: activity.distanceM),
                start: activity.startedAt,
                end: activity.endedAt
            ))
        }
        if let energyKilocalories,
           energyKilocalories > 0,
           let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            samples.append(HKQuantitySample(
                type: energyType,
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: energyKilocalories),
                start: activity.startedAt,
                end: activity.endedAt
            ))
        }
        if !samples.isEmpty {
            try await add(samples, to: workoutBuilder)
        }

        try await end(workoutBuilder, at: activity.endedAt)
        let workout = try await finish(workoutBuilder)

        let locations = activity.routePoints.map { point in
            CLLocation(
                coordinate: point.coordinate,
                altitude: point.altitude ?? 0,
                horizontalAccuracy: -1,
                verticalAccuracy: point.verticalAccuracy ?? -1,
                timestamp: point.timestamp
            )
        }
        guard locations.count > 1 else { return }

        let routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: .local())
        try await insert(locations, into: routeBuilder)
        try await finish(routeBuilder, workout: workout, metadata: metadata)
    }

    func begin(_ builder: HKWorkoutBuilder, at date: Date) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.beginCollection(withStart: date) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: HealthKitServiceError.requestFailed("Apple Health did not start the workout save."))
                }
            }
        }
    }

    func add(_ metadata: [String: Any], to builder: HKWorkoutBuilder) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.addMetadata(metadata) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: HealthKitServiceError.requestFailed("Apple Health did not save workout metadata."))
                }
            }
        }
    }

    func add(_ samples: [HKSample], to builder: HKWorkoutBuilder) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.add(samples) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: HealthKitServiceError.requestFailed("Apple Health did not save workout totals."))
                }
            }
        }
    }

    func end(_ builder: HKWorkoutBuilder, at date: Date) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.endCollection(withEnd: date) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: HealthKitServiceError.requestFailed("Apple Health did not finish collecting the workout."))
                }
            }
        }
    }

    func finish(_ builder: HKWorkoutBuilder) async throws -> HKWorkout {
        try await withCheckedThrowingContinuation { continuation in
            builder.finishWorkout { workout, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let workout {
                    continuation.resume(returning: workout)
                } else {
                    continuation.resume(throwing: HealthKitServiceError.requestFailed("Apple Health did not save the workout."))
                }
            }
        }
    }

    func insert(_ locations: [CLLocation], into routeBuilder: HKWorkoutRouteBuilder) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            routeBuilder.insertRouteData(locations) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: HealthKitServiceError.requestFailed("Apple Health did not save the workout route."))
                }
            }
        }
    }

    func finish(_ routeBuilder: HKWorkoutRouteBuilder, workout: HKWorkout, metadata: [String: Any]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            routeBuilder.finishRoute(with: workout, metadata: metadata) { route, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if route != nil {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: HealthKitServiceError.requestFailed("Apple Health did not finish the workout route."))
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

    func energyBurnedKilocalories(for workout: HKWorkout) -> Double? {
        if #available(iOS 18.0, *) {
            guard let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
                return nil
            }

            return workout
                .statistics(for: activeEnergyType)?
                .sumQuantity()?
                .doubleValue(for: .kilocalorie())
        } else {
            return workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
        }
    }
}

private struct HealthReadableType {
    let title: String
    let objectType: HKObjectType
}

private extension HKWorkoutActivityType {
    var displayName: String {
        switch self {
        case .running:
            return "Run"
        case .walking:
            return "Walk"
        case .cycling:
            return "Ride"
        case .hiking:
            return "Hike"
        case .traditionalStrengthTraining:
            return "Strength"
        case .functionalStrengthTraining:
            return "Functional strength"
        case .yoga:
            return "Yoga"
        case .mixedCardio:
            return "Cardio"
        default:
            return "Workout"
        }
    }
}
#endif
