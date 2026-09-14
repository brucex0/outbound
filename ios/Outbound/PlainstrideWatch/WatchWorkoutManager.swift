import Combine
import Foundation
import HealthKit

@MainActor
final class WatchWorkoutManager: NSObject, ObservableObject {
    static let shared = WatchWorkoutManager()

    @Published private(set) var lifecycle: PlainstrideWorkoutLifecycle = .ready
    @Published private(set) var connection: PlainstrideWorkoutConnection = .unavailable
    @Published private(set) var metrics: PlainstrideLiveMetrics?
    @Published private(set) var errorCategory: String?
    @Published private(set) var savedWorkoutSucceeded: Bool?

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var identity: PlainstrideWorkoutIdentity?
    private var sessionUUID: UUID?
    private var nextSequence: UInt64 = 0
    private var lastRemoteSequence: UInt64 = 0
    private var effortEngine = HeartRateEffortEngine()
    private var finishStarted = false
    private var builderFinishStarted = false
    private var startInProgress = false
    private var recoveryInProgress = false
    private var lastMetricsSentAt: Date?
    private let persistenceKey = "plainstride.watch.active-workout.v1"

    var isWorkoutInProgress: Bool {
        switch lifecycle {
        case .preparing, .active, .paused, .finishing, .recovering: true
        case .ready, .finished, .failed: false
        }
    }

    func startFromPhone(configuration: HKWorkoutConfiguration) {
        let activity = Self.activity(from: configuration.activityType)
        Task {
            await start(
                activity: activity,
                isIndoor: configuration.locationType == .indoor,
                origin: .iPhone,
                configuration: configuration
            )
        }
    }

    func startFromWatch(activity: PlainstrideWorkoutActivity, isIndoor: Bool) {
        Task { await start(activity: activity, isIndoor: isIndoor, origin: .appleWatch) }
    }

    func recoverActiveWorkout() {
        guard session == nil, !recoveryInProgress, !startInProgress else { return }
        recoveryInProgress = true
        lifecycle = .recovering
        Task {
            defer { recoveryInProgress = false }
            do {
                let recovered = try await healthStore.recoverActiveWorkoutSession()
                guard let recovered else {
                    clearPersistedState()
                    lifecycle = .ready
                    return
                }
                bindRecoveredSession(recovered)
            } catch {
                fail("recovery")
            }
        }
    }

    func pause(notifyPhone: Bool = true) {
        guard lifecycle == .active else { return }
        lifecycle = .paused
        persistState()
        session?.pause()
        if notifyPhone { send(kind: .pause) }
    }

    func resume(notifyPhone: Bool = true) {
        guard lifecycle == .paused else { return }
        lifecycle = .active
        persistState()
        session?.resume()
        if notifyPhone { send(kind: .resume) }
    }

    func finish(notifyPhone: Bool = true) {
        guard !finishStarted, session != nil else { return }
        finishStarted = true
        lifecycle = .finishing
        persistState()
        if notifyPhone { send(kind: .finishRequest) }
        session?.end()
        send(kind: .lifecycleState, lifecycle: .finishing)
    }

    func dismissResult() {
        guard lifecycle == .finished || lifecycle == .failed else { return }
        metrics = nil
        errorCategory = nil
        savedWorkoutSucceeded = nil
        lifecycle = .ready
    }

    private func start(
        activity: PlainstrideWorkoutActivity,
        isIndoor: Bool,
        origin: PlainstrideWorkoutOrigin,
        configuration suppliedConfiguration: HKWorkoutConfiguration? = nil
    ) async {
        guard session == nil, !finishStarted, !startInProgress, !recoveryInProgress else { return }
        startInProgress = true
        defer { startInProgress = false }
        guard HKHealthStore.isHealthDataAvailable() else {
            fail("health_unavailable")
            return
        }

        lifecycle = .preparing
        errorCategory = nil
        savedWorkoutSucceeded = nil
        do {
            try await requestAuthorization()
            let configuration = suppliedConfiguration ?? Self.configuration(for: activity, indoor: isIndoor)
            let startedAt = Date()
            let workoutSession = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let workoutBuilder = workoutSession.associatedWorkoutBuilder()
            workoutBuilder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )
            workoutSession.delegate = self
            workoutBuilder.delegate = self

            sessionUUID = UUID()
            identity = PlainstrideWorkoutIdentity(
                activity: activity,
                isIndoor: isIndoor,
                origin: origin,
                canonicalStartDate: startedAt
            )
            session = workoutSession
            builder = workoutBuilder
            nextSequence = 0
            lastRemoteSequence = 0
            effortEngine = HeartRateEffortEngine()
            finishStarted = false
            builderFinishStarted = false
            persistState()

            workoutSession.startActivity(with: startedAt)
            try await workoutBuilder.beginCollection(at: startedAt)
            do {
                try await workoutSession.startMirroringToCompanionDevice()
                connection = .connected
                send(kind: .sessionIdentity, identity: identity)
                send(kind: .startReadiness, identity: identity, lifecycle: .active)
            } catch {
                // Mirroring is additive. The Watch-owned workout must continue even
                // when no companion phone is currently reachable.
                connection = .unavailable
                errorCategory = Self.errorCategory(error)
                persistState()
            }
        } catch {
            let failedSession = session
            session = nil
            builder = nil
            failedSession?.delegate = nil
            failedSession?.end()
            fail(Self.errorCategory(error))
        }
    }

    private func bindRecoveredSession(_ recovered: HKWorkoutSession) {
        let persisted = loadPersistedState()
        sessionUUID = persisted?.sessionUUID ?? UUID()
        identity = persisted?.identity ?? PlainstrideWorkoutIdentity(
            activity: Self.activity(from: recovered.workoutConfiguration.activityType),
            isIndoor: recovered.workoutConfiguration.locationType == .indoor,
            origin: .appleWatch,
            canonicalStartDate: nil
        )
        nextSequence = persisted?.nextSequence ?? 0
        lastRemoteSequence = persisted?.lastRemoteSequence ?? 0
        effortEngine = persisted?.effortEngine ?? HeartRateEffortEngine()
        finishStarted = false
        builderFinishStarted = false
        recovered.delegate = self
        let recoveredBuilder = recovered.associatedWorkoutBuilder()
        recoveredBuilder.delegate = self
        session = recovered
        builder = recoveredBuilder
        connection = .connecting
        lifecycle = recovered.state == .paused ? .paused : .recovering
        persistState()
        Task {
            do {
                try await recovered.startMirroringToCompanionDevice()
                connection = .connected
                send(kind: .sessionIdentity, identity: identity)
                send(kind: .lifecycleState, lifecycle: lifecycle)
            } catch {
                connection = .disconnected
            }
        }
    }

    private func requestAuthorization() async throws {
        let workout = HKObjectType.workoutType()
        let readable: Set<HKObjectType> = Set([
            HKQuantityType.quantityType(forIdentifier: .heartRate),
            HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning),
            HKQuantityType.quantityType(forIdentifier: .distanceCycling),
            HKQuantityType.quantityType(forIdentifier: .distanceSwimming),
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)
        ].compactMap { $0 })
        try await healthStore.requestAuthorization(toShare: [workout], read: readable)
    }

    private func finishBuilder(at endDate: Date) {
        guard !builderFinishStarted else { return }
        builderFinishStarted = true
        guard let builder else {
            resetAfterFinish(success: false)
            return
        }
        effortEngine.close(at: endDate)
        builder.endCollection(withEnd: endDate) { [weak self] success, _ in
            guard let self else { return }
            Task { @MainActor in
                guard success else {
                    self.send(
                        kind: .savedWorkout,
                        lifecycle: .failed,
                        errorCategory: "end_collection"
                    )
                    self.resetAfterFinish(success: false)
                    return
                }
                do {
                    if let sessionUUID = self.sessionUUID {
                        try await builder.addMetadata(["ai.plainstride.session_uuid": sessionUUID.uuidString])
                    }
                    let workout = try await builder.finishWorkout()
                    let snapshot = self.effortEngine.snapshot
                    let final = PlainstrideFinalWorkoutMetrics(
                        averageBPM: snapshot.averageBPM,
                        maximumBPM: snapshot.maximumBPM,
                        timeInZones: snapshot.timeInZones,
                        elapsedTime: builder.elapsedTime,
                        distanceMeters: self.quantity(.distanceWalkingRunning, from: builder)
                            ?? self.quantity(.distanceCycling, from: builder)
                            ?? self.quantity(.distanceSwimming, from: builder),
                        activeEnergyKilocalories: self.quantity(.activeEnergyBurned, from: builder)
                    )
                    self.metrics = PlainstrideLiveMetrics(
                        currentBPM: snapshot.currentBPM,
                        sampledAt: snapshot.lastSampleDate,
                        averageBPM: final.averageBPM,
                        maximumBPM: final.maximumBPM,
                        currentZone: snapshot.currentZone,
                        effort: snapshot.effort,
                        timeInZones: final.timeInZones,
                        elapsedTime: final.elapsedTime,
                        distanceMeters: final.distanceMeters,
                        activeEnergyKilocalories: final.activeEnergyKilocalories
                    )
                    self.send(kind: .finalMetrics, finalMetrics: final)
                    self.send(
                        kind: .savedWorkout,
                        finalMetrics: final,
                        lifecycle: .finished,
                        externalWorkoutReference: workout?.uuid.uuidString
                    )
                    self.resetAfterFinish(success: workout != nil)
                } catch {
                    self.send(kind: .recoverableError, errorCategory: "save")
                    self.send(
                        kind: .savedWorkout,
                        lifecycle: .failed,
                        errorCategory: "save"
                    )
                    self.resetAfterFinish(success: false)
                }
            }
        }
    }

    private func resetAfterFinish(success: Bool) {
        savedWorkoutSucceeded = success
        lifecycle = success ? .finished : .failed
        connection = .unavailable
        session = nil
        builder = nil
        finishStarted = false
        builderFinishStarted = false
        clearPersistedState()
    }

    private func updateMetrics(from builder: HKLiveWorkoutBuilder, collectedTypes: Set<HKSampleType>) {
        if let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate),
           collectedTypes.contains(heartRateType),
           let statistics = builder.statistics(for: heartRateType),
           let quantity = statistics.mostRecentQuantity() {
            let bpm = Int(quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())).rounded())
            _ = effortEngine.ingest(bpm: bpm, sampledAt: statistics.endDate)
        }

        let snapshot = effortEngine.snapshot
        let updated = PlainstrideLiveMetrics(
            currentBPM: snapshot.currentBPM,
            sampledAt: snapshot.lastSampleDate,
            averageBPM: snapshot.averageBPM,
            maximumBPM: snapshot.maximumBPM,
            currentZone: snapshot.currentZone,
            effort: snapshot.effort,
            timeInZones: snapshot.timeInZones,
            elapsedTime: builder.elapsedTime,
            distanceMeters: quantity(.distanceWalkingRunning, from: builder)
                ?? quantity(.distanceCycling, from: builder)
                ?? quantity(.distanceSwimming, from: builder),
            activeEnergyKilocalories: quantity(.activeEnergyBurned, from: builder)
        )
        metrics = updated
        persistState()
        let now = Date()
        guard lastMetricsSentAt.map({ now.timeIntervalSince($0) >= 2 }) ?? true else { return }
        lastMetricsSentAt = now
        send(kind: .liveMetrics, metrics: updated)
    }

    private func quantity(_ identifier: HKQuantityTypeIdentifier, from builder: HKLiveWorkoutBuilder) -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier),
              let quantity = builder.statistics(for: type)?.sumQuantity() else { return nil }
        let unit: HKUnit = identifier == .activeEnergyBurned ? .kilocalorie() : .meter()
        return quantity.doubleValue(for: unit)
    }

    private func receive(_ dataItems: [Data]) {
        for data in dataItems {
            guard let message = try? PlainstrideWorkoutCodec.decode(data),
                  message.sequenceNumber > lastRemoteSequence else { continue }
            lastRemoteSequence = message.sequenceNumber

            if message.kind == .handshake,
               identity?.origin == .iPhone,
               sessionUUID != message.sessionUUID {
                sessionUUID = message.sessionUUID
                send(kind: .sessionIdentity, identity: identity)
            }
            guard message.sessionUUID == sessionUUID else { continue }
            switch message.kind {
            case .pause: pause(notifyPhone: false)
            case .resume: resume(notifyPhone: false)
            case .finishRequest: finish(notifyPhone: false)
            case .handshake:
                connection = .connected
                send(kind: .sessionIdentity, identity: identity)
                send(kind: .lifecycleState, lifecycle: lifecycle)
            default: break
            }
        }
        persistState()
    }

    private func send(
        kind: PlainstrideWorkoutMessageKind,
        identity: PlainstrideWorkoutIdentity? = nil,
        metrics: PlainstrideLiveMetrics? = nil,
        finalMetrics: PlainstrideFinalWorkoutMetrics? = nil,
        lifecycle: PlainstrideWorkoutLifecycle? = nil,
        connection: PlainstrideWorkoutConnection? = nil,
        externalWorkoutReference: String? = nil,
        errorCategory: String? = nil
    ) {
        guard let session, let sessionUUID else { return }
        nextSequence &+= 1
        let message = PlainstrideWorkoutMessage(
            sessionUUID: sessionUUID,
            sequenceNumber: nextSequence,
            originDevice: .appleWatch,
            kind: kind,
            identity: identity,
            metrics: metrics,
            finalMetrics: finalMetrics,
            lifecycle: lifecycle,
            connection: connection,
            externalWorkoutReference: externalWorkoutReference,
            errorCategory: errorCategory
        )
        guard let data = try? PlainstrideWorkoutCodec.encode(message) else { return }
        persistState()
        session.sendToRemoteWorkoutSession(data: data) { _, _ in }
    }

    private func fail(_ category: String) {
        errorCategory = category
        lifecycle = .failed
        connection = .unavailable
        send(kind: .recoverableError, errorCategory: category)
        clearPersistedState()
    }

    private struct PersistedState: Codable {
        let sessionUUID: UUID
        let identity: PlainstrideWorkoutIdentity
        let nextSequence: UInt64
        let lastRemoteSequence: UInt64
        let effortEngine: HeartRateEffortEngine
    }

    private func persistState() {
        guard let sessionUUID, let identity else { return }
        let value = PersistedState(
            sessionUUID: sessionUUID,
            identity: identity,
            nextSequence: nextSequence,
            lastRemoteSequence: lastRemoteSequence,
            effortEngine: effortEngine
        )
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: persistenceKey)
        }
    }

    private func loadPersistedState() -> PersistedState? {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey) else { return nil }
        return try? JSONDecoder().decode(PersistedState.self, from: data)
    }

    private func clearPersistedState() {
        UserDefaults.standard.removeObject(forKey: persistenceKey)
    }

    static func configuration(for activity: PlainstrideWorkoutActivity, indoor: Bool) -> HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = switch activity {
        case .running: .running
        case .walking: .walking
        case .cycling: .cycling
        case .hiking: .hiking
        case .swimming: .swimming
        case .strength: .traditionalStrengthTraining
        case .mobility: .flexibility
        }
        configuration.locationType = indoor ? .indoor : .outdoor
        return configuration
    }

    private static func activity(from type: HKWorkoutActivityType) -> PlainstrideWorkoutActivity {
        switch type {
        case .walking: .walking
        case .cycling: .cycling
        case .hiking: .hiking
        case .swimming: .swimming
        case .traditionalStrengthTraining, .functionalStrengthTraining: .strength
        case .flexibility, .mindAndBody: .mobility
        default: .running
        }
    }

    private static func errorCategory(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == HKError.errorDomain {
            switch HKError.Code(rawValue: nsError.code) {
            case .errorAuthorizationDenied: return "authorization_denied"
            case .errorHealthDataUnavailable: return "health_unavailable"
            case .errorAnotherWorkoutSessionStarted: return "workout_active"
            default: return "healthkit"
            }
        }
        return "unknown"
    }
}

extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            switch toState {
            case .running:
                lifecycle = .active
                send(kind: .lifecycleState, lifecycle: .active)
            case .paused:
                lifecycle = .paused
                send(kind: .lifecycleState, lifecycle: .paused)
            case .ended:
                lifecycle = .finishing
                finishBuilder(at: date)
            default: break
            }
            persistState()
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in fail(Self.errorCategory(error)) }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didReceiveDataFromRemoteWorkoutSession data: [Data]
    ) {
        Task { @MainActor in receive(data) }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didDisconnectFromRemoteDeviceWithError error: Error?
    ) {
        Task { @MainActor in
            connection = .disconnected
            persistState()
        }
    }
}

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        Task { @MainActor in updateMetrics(from: workoutBuilder, collectedTypes: collectedTypes) }
    }
}
