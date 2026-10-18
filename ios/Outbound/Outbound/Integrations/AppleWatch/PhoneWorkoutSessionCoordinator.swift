import Combine
import Foundation
import HealthKit

struct WatchInitiatedSession: Equatable {
    let sessionUUID: UUID
    let identity: PlainstrideWorkoutIdentity
}

@MainActor
final class PhoneWorkoutSessionCoordinator: NSObject, ObservableObject {
    static let shared = PhoneWorkoutSessionCoordinator()
    static let preparationTimeout: TimeInterval = 6

    @Published private(set) var connection: PlainstrideWorkoutConnection = .unavailable
    @Published private(set) var lifecycle: PlainstrideWorkoutLifecycle = .ready
    @Published private(set) var origin: PlainstrideWorkoutOrigin?
    @Published private(set) var latestMetrics: PlainstrideLiveMetrics?
    @Published private(set) var finalMetrics: PlainstrideFinalWorkoutMetrics?
    @Published private(set) var isWatchAvailable = false
    @Published private(set) var currentSessionUUID: UUID?
    @Published private(set) var watchOwnsHealthKitPersistence = false
    @Published private(set) var savedWorkoutExternalReference: String?
    @Published private(set) var incomingWatchSession: WatchInitiatedSession?
    @Published private(set) var finishRequestToken = 0
    @Published private(set) var toastMessage: String?

    private let healthStore = HKHealthStore()
    private weak var recorder: ActivityRecorder?
    private weak var activityStore: ActivityStore?
    private var mirroredSession: HKWorkoutSession?
    private var pendingIdentity: PlainstrideWorkoutIdentity?
    private var nextSequence: UInt64 = 0
    private var lastRemoteSequence: UInt64 = 0
    private var preparationTimeoutTask: Task<Void, Never>?
    private var analyticsManager: AnalyticsManager?
    private var receivedFirstHeartRate = false
    private var hasTrackedConnectionAttempt = false
    private var hasTrackedWorkoutOrigin = false
    private var installedHandler = false
    private var pendingWatchAutoSave: PendingWatchAutoSave?

    private struct PendingWatchAutoSave {
        let sessionUUID: UUID
        let identity: PlainstrideWorkoutIdentity
        let finalMetrics: PlainstrideFinalWorkoutMetrics
        let externalReference: String?
    }

    private override init() {
        super.init()
    }

    var canonicalStartDate: Date? { pendingIdentity?.canonicalStartDate }

    func recordingMetadata(externalReference: String? = nil) -> ActivityRecordingSessionMetadata? {
        guard let sessionUUID = currentSessionUUID else { return nil }
        let sessionOrigin: ActivityRecordingSessionMetadata.Origin = origin == .appleWatch ? .appleWatch : .iPhone
        return ActivityRecordingSessionMetadata(
            sessionUUID: sessionUUID,
            origin: sessionOrigin,
            recordingDevice: watchOwnsHealthKitPersistence ? .appleWatch : .phoneOnly,
            healthKitOwnership: watchOwnsHealthKitPersistence ? .appleWatchPrimary : .phoneWriteBack,
            healthKitWorkoutExternalReference: externalReference ?? savedWorkoutExternalReference
        )
    }

    /// References come only from a successful Watch save acknowledgement or an
    /// exact session-UUID Health import, never from sport/time overlap guesses.
    func hasConfirmedWatchHealthSave(for metadata: ActivityRecordingSessionMetadata?) -> Bool {
        guard let metadata else { return false }
        if metadata.healthKitOwnership == .appleWatchPrimary,
           let reference = metadata.healthKitWorkoutExternalReference,
           UUID(uuidString: reference) != nil {
            return true
        }
        // Include an acknowledgement that arrived after the local activity save.
        return currentSessionUUID == metadata.sessionUUID
            && savedWorkoutExternalReference.flatMap(UUID.init(uuidString:)) != nil
    }

    func configureAnalytics(_ manager: AnalyticsManager) {
        analyticsManager = manager
    }

    /// Install during UIApplication launch. HealthKit may invoke this on a background queue
    /// and may repeat it while recovering the same mirrored workout.
    func installMirroringHandler() {
        guard !installedHandler else { return }
        installedHandler = true
        healthStore.workoutSessionMirroringStartHandler = { session in
            Task { @MainActor in
                PhoneWorkoutSessionCoordinator.shared.acceptMirroredSession(session)
            }
        }
    }

    func bind(recorder: ActivityRecorder) {
        self.recorder = recorder
        if currentSessionUUID == nil,
           let metadata = recorder.recordingSessionMetadata,
           metadata.healthKitOwnership == .appleWatchPrimary {
            currentSessionUUID = metadata.sessionUUID
            origin = metadata.origin == .appleWatch ? .appleWatch : .iPhone
            watchOwnsHealthKitPersistence = true
            lifecycle = recorder.recoveredWatchLifecycle ?? .recovering
            lastRemoteSequence = recorder.recoveredWatchMessageSequence ?? 0
            connection = .connecting
        }
        guard let incomingWatchSession,
              recorder.state == .idle else { return }
        startPhoneRecorder(for: incomingWatchSession)
    }

    func bind(activityStore: ActivityStore) {
        self.activityStore = activityStore
        flushPendingWatchAutoSave()
    }

    private func flushPendingWatchAutoSave() {
        guard let pendingWatchAutoSave else { return }
        Task { @MainActor in
            let saved = await activityStore?.saveWatchWorkoutIfNeeded(
                sessionUUID: pendingWatchAutoSave.sessionUUID,
                identity: pendingWatchAutoSave.identity,
                finalMetrics: pendingWatchAutoSave.finalMetrics,
                externalReference: pendingWatchAutoSave.externalReference
            )
            if saved != nil {
                self.pendingWatchAutoSave = nil
            }
        }
    }

    func preparePhoneFirst(
        activityType: ActivityType,
        isIndoor: Bool,
        companionType: ActivityCompanionType? = nil,
        sessionUUID: UUID = UUID(),
        startWatchApp: Bool = true
    ) {
        resetForNewSession(sessionUUID: sessionUUID)
        if !startWatchApp {
            pendingIdentity = nil
            connection = .unavailable
            origin = .iPhone
            lifecycle = .ready
            track(.watchWorkoutOrigin, [.sourceType: .string("iphone")])
            return
        }
        origin = .iPhone
        pendingIdentity = PlainstrideWorkoutIdentity(
            activity: PlainstrideWorkoutActivity(activityType),
            isIndoor: isIndoor,
            origin: .iPhone,
            canonicalStartDate: nil,
            companionType: companionType?.rawValue
        )
        lifecycle = .preparing
        connection = .connecting
        toastMessage = String(
            localized: "watch.connecting.toast",
            defaultValue: "Connecting to Apple Watch…"
        )
        track(.watchConnectionAttempted, [.sourceType: .string("iphone")])
        track(.watchWorkoutOrigin, [.sourceType: .string("iphone")])
        hasTrackedConnectionAttempt = true
        hasTrackedWorkoutOrigin = true

#if DEBUG && targetEnvironment(simulator)
        if let uiTestWatchMode {
            uiTestWatchLaunchCount += 1
            if uiTestWatchMode == "timeout" {
                startPreparationTimeout()
            } else if uiTestWatchMode == "unavailable" {
                fallback(errorCategory: "watch_unavailable")
            } else {
                isWatchAvailable = true
                uiTestReceiveWatchMessage(.startReadiness, identity: pendingIdentity, lifecycle: .active)
                uiTestReceiveWatchMessage(.liveMetrics, metrics: Self.uiTestMetrics)
            }
            return
        }
#endif
        healthStore.startWatchApp(with: Self.configuration(activityType, isIndoor: isIndoor)) { success, error in
            Task { @MainActor in
                let coordinator = PhoneWorkoutSessionCoordinator.shared
                if success {
                    coordinator.isWatchAvailable = true
                    coordinator.startPreparationTimeout()
                } else {
                    coordinator.fallback(errorCategory: Self.errorCategory(error))
                }
            }
        }
    }

    func cancelPreparation() {
        preparationTimeoutTask?.cancel()
        preparationTimeoutTask = nil
        if mirroredSession != nil { requestFinish(source: "iphone") }
        resetTransientState()
    }

    func requestPause(autoTriggered: Bool = false, distanceGoalMeters: Double? = nil, source: String = "iphone") {
        guard lifecycle == .active || recorder?.state == .active else { return }
        send(kind: .pause)
        lifecycle = .paused
        recorder?.pause(autoTriggered: autoTriggered, distanceGoalMeters: distanceGoalMeters)
        track(.watchControlUsed, [.sourceType: .string(source), .control: .string("pause")])
    }

    func requestResume(source: String = "iphone") {
        guard lifecycle == .paused || recorder?.state == .paused else { return }
        send(kind: .resume)
        lifecycle = .active
        recorder?.resume()
        track(.watchControlUsed, [.sourceType: .string(source), .control: .string("resume")])
    }

    func requestFinish(source: String = "iphone") {
        guard lifecycle != .finishing, lifecycle != .finished else { return }
        lifecycle = .finishing
        send(kind: .finishRequest)
        track(.watchControlUsed, [.sourceType: .string(source), .control: .string("finish")])
    }

    func markPhoneRecorderStarted() {
        if lifecycle == .ready || lifecycle == .preparing { lifecycle = .active }
    }

    func clearCompletedSession() {
        incomingWatchSession = nil
        if watchOwnsHealthKitPersistence, savedWorkoutExternalReference == nil, lifecycle != .failed {
            recorder = nil
            return
        }
        resetTransientState()
    }

    private func acceptMirroredSession(_ session: HKWorkoutSession) {
        if mirroredSession === session {
            sendHandshake()
            return
        }
        let isReconnection = connection == .disconnected
        if !hasTrackedConnectionAttempt {
            track(.watchConnectionAttempted, [.sourceType: .string("apple_watch")])
            hasTrackedConnectionAttempt = true
        }
        mirroredSession?.delegate = nil
        mirroredSession = session
        session.delegate = self
        watchOwnsHealthKitPersistence = true
        isWatchAvailable = true
        connection = .connected
        lifecycle = session.state == .paused ? .paused : .recovering
        preparationTimeoutTask?.cancel()
        preparationTimeoutTask = nil
        if let metadata = recordingMetadata() {
            recorder?.updateRecordingSessionMetadata(metadata)
        }
        toastMessage = String(
            localized: isReconnection ? "watch.reconnected.toast" : "watch.connected.toast",
            defaultValue: isReconnection ? "Apple Watch reconnected." : "Heart rate connected."
        )
        sendHandshake()
        track(.watchConnectionResult, [
            .sourceType: .string(origin?.rawValue ?? "apple_watch"),
            .result: .string("success")
        ])
        if isReconnection {
            track(.watchReconnected, [
                .sourceType: .string(origin?.rawValue ?? "apple_watch"),
                .result: .string("success")
            ])
        }
    }

    private func sendHandshake() {
        guard mirroredSession != nil else { return }
        if currentSessionUUID == nil { currentSessionUUID = UUID() }
        send(kind: .handshake, identity: pendingIdentity, connection: .connected)
    }

    private func process(_ dataItems: [Data]) {
        for data in dataItems {
            guard let message = try? PlainstrideWorkoutCodec.decode(data) else { continue }

            // A phone-first launch already owns the canonical UUID. Ignore any early
            // watch identity created before the watch receives our handshake; the watch
            // will adopt the phone UUID and echo it back.
            if currentSessionUUID == nil {
                currentSessionUUID = message.sessionUUID
            }
            guard message.sessionUUID == currentSessionUUID,
                  message.sequenceNumber > lastRemoteSequence else { continue }
            lastRemoteSequence = message.sequenceNumber
            defer {
                recorder?.updateWatchRecoveryState(
                    lifecycle: lifecycle,
                    lastReceivedSequence: message.sequenceNumber
                )
            }

            switch message.kind {
            case .controlUsed:
                let allowed = ["lap", "auto_lap", "goal_reached", "zone_alert", "pace_alert"]
                if let control = message.errorCategory, allowed.contains(control) {
                    track(.watchControlUsed, [.sourceType: .string("apple_watch"), .control: .string(control)])
                }

            case .sessionIdentity, .startReadiness:
                guard let identity = message.identity else { continue }
                pendingIdentity = identity
                origin = identity.origin
                if !hasTrackedWorkoutOrigin {
                    track(.watchWorkoutOrigin, [.sourceType: .string(identity.origin.rawValue)])
                    hasTrackedWorkoutOrigin = true
                }
                watchOwnsHealthKitPersistence = true
                lifecycle = message.lifecycle ?? .ready
                connection = .connected
                if identity.origin == .appleWatch,
                   let sessionUUID = currentSessionUUID {
                    let incoming = WatchInitiatedSession(sessionUUID: sessionUUID, identity: identity)
                    incomingWatchSession = incoming
                    startPhoneRecorder(for: incoming)
                }
            case .liveMetrics:
                guard let metrics = message.metrics else { continue }
                latestMetrics = metrics
                if let bpm = metrics.currentBPM, let sampledAt = metrics.sampledAt {
                    let accepted = recorder?.ingestHeartRate(
                        bpm: bpm,
                        sampledAt: sampledAt,
                        source: .appleWatch
                    ) ?? false
                    if accepted, !receivedFirstHeartRate {
                        receivedFirstHeartRate = true
                        track(.watchFirstLiveHeartRateReceived, [.sourceType: .string("apple_watch")])
                    }
                }
            case .pause:
                lifecycle = .paused
                recorder?.pause()
                track(.watchControlUsed, [
                    .sourceType: .string("apple_watch"),
                    .control: .string("pause")
                ])
            case .resume:
                lifecycle = .active
                recorder?.resume()
                track(.watchControlUsed, [
                    .sourceType: .string("apple_watch"),
                    .control: .string("resume")
                ])
            case .finishRequest:
                lifecycle = .finishing
                finishRequestToken &+= 1
                track(.watchControlUsed, [
                    .sourceType: .string("apple_watch"),
                    .control: .string("finish")
                ])
            case .finalMetrics:
                if let final = message.finalMetrics {
                    finalMetrics = final
                    recorder?.applyFinalHeartRateMetrics(final)
                }
            case .savedWorkout:
                if let final = message.finalMetrics {
                    finalMetrics = final
                    recorder?.applyFinalHeartRateMetrics(final)
                }
                savedWorkoutExternalReference = message.externalWorkoutReference
                if message.externalWorkoutReference == nil {
                    watchOwnsHealthKitPersistence = false
                    if let metadata = recordingMetadata() {
                        recorder?.updateRecordingSessionMetadata(metadata)
                    }
                }
                if let externalReference = message.externalWorkoutReference,
                   let sessionUUID = currentSessionUUID {
                    Task {
                        await activityStore?.attachHealthKitWorkoutReference(
                            sessionUUID: sessionUUID,
                            externalReference: externalReference
                        )
                    }
                }
                if recorder == nil,
                   let sessionUUID = currentSessionUUID,
                   let identity = pendingIdentity,
                   let completedMetrics = message.finalMetrics ?? finalMetrics {
                    let pending = PendingWatchAutoSave(
                        sessionUUID: sessionUUID,
                        identity: identity,
                        finalMetrics: completedMetrics,
                        externalReference: message.externalWorkoutReference
                    )
                    pendingWatchAutoSave = pending
                    flushPendingWatchAutoSave()
                }
                lifecycle = message.lifecycle
                    ?? (message.externalWorkoutReference == nil ? .failed : .finished)
                finishRequestToken &+= 1
                var saveProperties: [ProductPropertyKey: AnalyticsValue] = [
                    .sourceType: .string("apple_watch"),
                    .result: .string(message.externalWorkoutReference == nil ? "failure" : "success")
                ]
                if let category = message.errorCategory {
                    saveProperties[.errorCategory] = .string(category)
                }
                track(.watchWorkoutSaveResult, saveProperties)
            case .recoverableError:
                toastMessage = String(
                    localized: "watch.error.continuing",
                    defaultValue: "Apple Watch connection changed — your workout is still recording."
                )
            case .connectionState:
                connection = message.connection ?? connection
            case .lifecycleState:
                applyRemoteLifecycle(message.lifecycle)
            case .handshake:
                break
            }
        }
    }

    private func applyRemoteLifecycle(_ state: PlainstrideWorkoutLifecycle?) {
        guard let state else { return }
        lifecycle = state
        switch state {
        case .active:
            if recorder?.state == .paused { recorder?.resume() }
        case .paused:
            if recorder?.state == .active { recorder?.pause() }
        case .finishing, .finished:
            finishRequestToken &+= 1
        default: break
        }
    }

    private func startPhoneRecorder(for incoming: WatchInitiatedSession) {
        guard let recorder, recorder.state == .idle else { return }
        recorder.start(
            activityType: ActivityType(incoming.identity.activity),
            routeGuidance: nil,
            canonicalStartDate: incoming.identity.canonicalStartDate,
            sessionMetadata: ActivityRecordingSessionMetadata(
                sessionUUID: incoming.sessionUUID,
                origin: .appleWatch,
                recordingDevice: .appleWatch,
                healthKitOwnership: .appleWatchPrimary,
                healthKitWorkoutExternalReference: nil
            ),
            companionType: ActivityCompanionType(safeDecoding: incoming.identity.companionType)
        )
    }

    private func send(
        kind: PlainstrideWorkoutMessageKind,
        identity: PlainstrideWorkoutIdentity? = nil,
        connection: PlainstrideWorkoutConnection? = nil
    ) {
#if DEBUG && targetEnvironment(simulator)
        if let uiTestWatchMode {
            guard ["connected", "save_failure"].contains(uiTestWatchMode) else { return }
            uiTestOutboundControls.append(kind.rawValue)
            if kind == .finishRequest {
                Task { @MainActor in
                    // Deliver completion asynchronously like a remote Watch, after
                    // RecordView has had a chance to produce its phone summary.
                    await Task.yield()
                    uiTestReceiveWatchMessage(.savedWorkout, lifecycle: uiTestWatchMode == "save_failure" ? .failed : .finished,
                        externalReference: uiTestWatchMode == "save_failure" ? nil : "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
                }
            }
            return
        }
#endif
        guard let mirroredSession, let currentSessionUUID else { return }
        nextSequence &+= 1
        let message = PlainstrideWorkoutMessage(
            sessionUUID: currentSessionUUID,
            sequenceNumber: nextSequence,
            originDevice: .iPhone,
            kind: kind,
            identity: identity,
            connection: connection
        )
        guard let data = try? PlainstrideWorkoutCodec.encode(message) else { return }
        mirroredSession.sendToRemoteWorkoutSession(data: data) { _, _ in }
    }

    private func startPreparationTimeout() {
        preparationTimeoutTask?.cancel()
        preparationTimeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.preparationTimeout))
            guard !Task.isCancelled, connection != .connected else { return }
            fallback(errorCategory: "timeout")
        }
    }

    private func fallback(errorCategory: String) {
        preparationTimeoutTask?.cancel()
        preparationTimeoutTask = nil
        connection = .unavailable
        lifecycle = .ready
        watchOwnsHealthKitPersistence = false
        isWatchAvailable = false
        toastMessage = String(
            localized: "watch.phone_only.toast",
            defaultValue: "Apple Watch unavailable — continuing without live heart rate."
        )
        track(.watchConnectionResult, [
            .sourceType: .string("iphone"),
            .result: .string("fallback"),
            .errorCategory: .string(errorCategory)
        ])
        track(.watchPhoneOnlyFallback, [
            .sourceType: .string("iphone"),
            .result: .string("fallback"),
            .errorCategory: .string(errorCategory)
        ])
    }

    private func resetForNewSession(sessionUUID: UUID) {
        preparationTimeoutTask?.cancel()
        currentSessionUUID = sessionUUID
        nextSequence = 0
        lastRemoteSequence = 0
        latestMetrics = nil
        finalMetrics = nil
        savedWorkoutExternalReference = nil
        pendingWatchAutoSave = nil
        receivedFirstHeartRate = false
        hasTrackedConnectionAttempt = false
        hasTrackedWorkoutOrigin = false
        watchOwnsHealthKitPersistence = false
        toastMessage = nil
    }

    private func resetTransientState() {
        preparationTimeoutTask?.cancel()
        preparationTimeoutTask = nil
        mirroredSession?.delegate = nil
        mirroredSession = nil
        pendingIdentity = nil
        currentSessionUUID = nil
        origin = nil
        connection = .unavailable
        lifecycle = .ready
        latestMetrics = nil
        finalMetrics = nil
        watchOwnsHealthKitPersistence = false
        isWatchAvailable = false
        savedWorkoutExternalReference = nil
        nextSequence = 0
        lastRemoteSequence = 0
        receivedFirstHeartRate = false
        hasTrackedConnectionAttempt = false
        hasTrackedWorkoutOrigin = false
    }

    private func track(_ name: ProductEventName, _ properties: [ProductPropertyKey: AnalyticsValue] = [:]) {
        guard let analyticsManager else { return }
        Task { await analyticsManager.track(.init(name, properties: properties)) }
    }

#if DEBUG && targetEnvironment(simulator)
    // Explicit seeded UI-test transport. No simulator fixture or entry point is
    // compiled into physical-device or Release builds.
    private var uiTestWatchMode: String?
    private var uiTestRemoteSequence: UInt64 = 0
    private(set) var uiTestSessionUUID: UUID?
    @Published private(set) var uiTestWatchLaunchCount = 0
    @Published private(set) var uiTestOutboundControls: [String] = []

    func configureWatchFlowUITest(recorder: ActivityRecorder) {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-OutboundUITestSeedData"),
              let index = arguments.firstIndex(of: "-OutboundUITestWatchScenario"),
              arguments.indices.contains(index + 1),
              ["connected", "unavailable", "timeout", "phone_only", "save_failure"].contains(arguments[index + 1]) else { return }
        resetTransientState()
        uiTestWatchMode = arguments[index + 1]
        uiTestRemoteSequence = 0
        uiTestWatchLaunchCount = 0
        uiTestOutboundControls = []
        bind(recorder: recorder)
        preparePhoneFirst(activityType: .running, isIndoor: true, startWatchApp: uiTestWatchMode != "phone_only")
        uiTestSessionUUID = currentSessionUUID
        if let metadata = recordingMetadata() { recorder.updateRecordingSessionMetadata(metadata) }
        markPhoneRecorderStarted()
    }

    var watchFlowUITestReport: String {
        "connection=\(connection.rawValue);lifecycle=\(lifecycle.rawValue);ownership=\(recordingMetadata()?.healthKitOwnership.rawValue ?? "none");heart=\(latestMetrics?.currentBPM ?? 0);phone_heart=\(recorder?.heartRate ?? 0);launches=\(uiTestWatchLaunchCount);reference=\(savedWorkoutExternalReference == nil ? "none" : "saved");outbound=\(uiTestOutboundControls.joined(separator: ","))"
    }

    func watchFlowUITestAction(_ action: String) {
        guard uiTestWatchMode != nil else { return }
        switch action {
        case "pause": uiTestReceiveWatchMessage(.pause)
        case "resume": uiTestReceiveWatchMessage(.resume)
        case "disconnect": uiTestReceiveWatchMessage(.connectionState, connection: .disconnected)
        case "reconnect": uiTestReceiveWatchMessage(.connectionState, connection: .connected)
        case "stale":
            // An old sequence and a different session must both be rejected.
            uiTestReceiveWatchMessage(.pause, sequence: uiTestRemoteSequence)
            uiTestReceiveWatchMessage(.pause, sessionID: UUID())
        default: break
        }
    }

    private static var uiTestMetrics: PlainstrideLiveMetrics {
        PlainstrideLiveMetrics(currentBPM: 166, sampledAt: Date(), averageBPM: 160, maximumBPM: 178,
            currentZone: 4, effort: .hard, timeInZones: [.init(zone: 4, seconds: 600)],
            elapsedTime: 2753, distanceMeters: 7820, activeEnergyKilocalories: 500)
    }

    private func uiTestReceiveWatchMessage(_ kind: PlainstrideWorkoutMessageKind,
        identity: PlainstrideWorkoutIdentity? = nil, metrics: PlainstrideLiveMetrics? = nil,
        lifecycle: PlainstrideWorkoutLifecycle? = nil, connection: PlainstrideWorkoutConnection? = nil,
        externalReference: String? = nil, sequence: UInt64? = nil, sessionID: UUID? = nil) {
        guard let currentSessionUUID else { return }
        uiTestRemoteSequence += 1
        let message = PlainstrideWorkoutMessage(sessionUUID: sessionID ?? currentSessionUUID,
            sequenceNumber: sequence ?? uiTestRemoteSequence, originDevice: .appleWatch, kind: kind,
            identity: identity, metrics: metrics, lifecycle: lifecycle, connection: connection,
            externalWorkoutReference: externalReference)
        do { process([try PlainstrideWorkoutCodec.encode(message)]) }
        catch { preconditionFailure("Invalid seeded Watch message encoding") }
    }
#endif

    private static func configuration(_ activityType: ActivityType, isIndoor: Bool) -> HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = switch activityType {
        case .running: .running
        case .walking: .walking
        case .cycling: .cycling
        case .hiking: .hiking
        case .swimming: .swimming
        case .strengthTraining: .traditionalStrengthTraining
        case .mobility: .flexibility
        }
        configuration.locationType = isIndoor ? .indoor : .outdoor
        return configuration
    }

    private static func errorCategory(_ error: Error?) -> String {
        guard let error else { return "unavailable" }
        let nsError = error as NSError
        if nsError.domain == HKError.errorDomain {
            switch HKError.Code(rawValue: nsError.code) {
            case .errorAuthorizationDenied: return "authorization_denied"
            case .errorHealthDataUnavailable: return "health_unavailable"
            case .errorAnotherWorkoutSessionStarted: return "workout_active"
            default: return "healthkit"
            }
        }
        return "connection"
    }
}

extension PhoneWorkoutSessionCoordinator: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            switch toState {
            case .running: applyRemoteLifecycle(.active)
            case .paused: applyRemoteLifecycle(.paused)
            case .ended: applyRemoteLifecycle(.finishing)
            default: break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            connection = .disconnected
            toastMessage = String(
                localized: "watch.disconnected.toast",
                defaultValue: "Apple Watch disconnected — phone recording continues."
            )
            track(.watchDisconnected, [
                .sourceType: .string("apple_watch"),
                .result: .string("failure"),
                .errorCategory: .string(Self.errorCategory(error))
            ])
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didReceiveDataFromRemoteWorkoutSession data: [Data]
    ) {
        Task { @MainActor in process(data) }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didDisconnectFromRemoteDeviceWithError error: Error?
    ) {
        Task { @MainActor in
            connection = .disconnected
            toastMessage = String(
                localized: "watch.disconnected.toast",
                defaultValue: "Apple Watch disconnected — phone recording continues."
            )
            track(.watchDisconnected, [
                .sourceType: .string("apple_watch"),
                .result: .string("failure"),
                .errorCategory: .string(Self.errorCategory(error))
            ])
        }
    }
}

private extension PlainstrideWorkoutActivity {
    init(_ activityType: ActivityType) {
        self = switch activityType {
        case .running: .running
        case .walking: .walking
        case .cycling: .cycling
        case .hiking: .hiking
        case .swimming: .swimming
        case .strengthTraining: .strength
        case .mobility: .mobility
        }
    }
}

private extension ActivityType {
    init(_ activity: PlainstrideWorkoutActivity) {
        self = switch activity {
        case .running: .running
        case .walking: .walking
        case .cycling: .cycling
        case .hiking: .hiking
        case .swimming: .swimming
        case .strength: .strengthTraining
        case .mobility: .mobility
        }
    }
}
