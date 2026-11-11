#if DEBUG
import Combine
import CoreLocation
import SwiftUI
import UserNotifications

@MainActor
enum DebugRepositorySupplementalTransport {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("-OutboundRepositorySupplemental") }
    static var canonicalTarget: SavedActivity?
    static var personalizationDelay: Duration = .zero
    static var personalizationStarted = 0
    static var personalizationOwners: [String] = []
    static var queueOwners: [String] = []
    static var events: [String] = []
    static var pluralOutputs: [String: [String]] = [:]
    static var planningResponses: [(TrainingPlanStateResponse, Duration)] = []
    static var planningStarted = 0
    static var refreshResult: AuthSession?
    static var refreshFailure = false
    static var refreshDelay: Duration = .milliseconds(180)
    static var refreshStarted = 0
    static var networkRequests = 0

    static func statisticsData() throws -> Data {
        let data = try Data(contentsOf: URL.documentsDirectory.appendingPathComponent("me-statistics.json"))
        guard DebugActivityRepositoryTransport.accepted == 0 else { events.append("statistics_after_acceptance"); return data }
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var goal = object["weeklyRunGoal"] as! [String: Any]
        goal["completedRuns"] = 3
        object["weeklyRunGoal"] = goal
        var week = object["currentWeek"] as! [String: Any]
        week["activityCount"] = 3
        object["currentWeek"] = week
        return try JSONSerialization.data(withJSONObject: object)
    }
    static func personalization() async throws -> PersonalizationSnapshotDTO {
        let context = ActivityAccountBoundary.context
        personalizationStarted += 1
        try await Task.sleep(for: personalizationDelay)
        try ActivityAccountBoundary.validate(context)
        personalizationOwners.append(context.owner)
        events.append(DebugActivityRepositoryTransport.accepted > 0 ? "personalization_after_acceptance" : "personalization_before_acceptance")
        let preview = PersonalizationSnapshotDTO.preview
        return .init(contractVersion: preview.contractVersion, modelVersion: "synthetic-\(context.owner)", generatedAt: Date(),
            calibration: preview.calibration, calibrationWorkouts: preview.calibrationWorkouts, insights: [], pendingAdjustment: nil)
    }
    static func refreshSession() async throws -> AuthSession {
        refreshStarted += 1
        let failure = refreshFailure, result = refreshResult, delay = refreshDelay
        await withCheckedContinuation { continuation in
            Task.detached { try? await Task.sleep(for: delay); continuation.resume() }
        }
        if failure { throw APIError.http(statusCode: 401, message: "Synthetic old refresh rejected", code: "invalid_refresh_token") }
        guard let result else { throw CocoaError(.fileReadCorruptFile) }
        return result
    }
    static func unauthorizedData(_ request: URLRequest) async -> (Data, URLResponse) {
        networkRequests += 1
        return (Data(), HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!)
    }
    static func canonicalRecord() -> RemoteActivityRecord? {
        guard let target = canonicalTarget else { return nil }
        let cloud = RemoteActivityPhoto(id: "synthetic-cloud", clientPhotoId: "6974E901-6DD9-4B45-B5DD-712629B1905B", thumbnailUrl: URL(string: "https://example.invalid/cloud.jpg"),
            takenAt: Date(), paceAtShot: nil, hrAtShot: nil, distAtShot: 0, latitude: nil, longitude: nil, captureContext: "active", byteSize: 0, sha256: "synthetic", createdAt: Date(), updatedAt: Date())
        return .init(id: target.sync!.serverActivityId!, clientActivityId: target.id.uuidString, clientData: ActivityClientExtras(from: target),
            activityType: target.activityType, title: target.title, reflection: target.reflection, companionType: target.companionType,
            startedAt: target.startedAt, endedAt: target.endedAt, durationSecs: target.durationSecs, distanceM: target.distanceM,
            avgPace: target.avgPace, elevationGainM: target.elevationGainM, route: target.route, clientUpdatedAt: target.sync?.localUpdatedAt,
            deletedAt: nil, createdAt: target.createdAt, updatedAt: Date(), photos: [cloud])
    }
}

nonisolated final class RepositoryMemorySessionRepository: SessionPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var value: AuthSession?
    init(_ value: AuthSession?) { self.value = value }
    func load() throws -> AuthSession? { lock.lock(); defer { lock.unlock() }; return value }
    func replace(_ session: AuthSession) throws { lock.lock(); defer { lock.unlock() }; value = session }
    func delete() throws { lock.lock(); defer { lock.unlock() }; value = nil }
}

@MainActor
final class RepositoryReminderClient: WorkoutNotificationFixtureClient {
    var pending: [String: UNNotificationRequest] = [:]
    var delayNextAdd = false
    var addStarted = false
    func authorizationStatus() async -> UNAuthorizationStatus { .authorized }
    func requests() async -> [UNNotificationRequest] { Array(pending.values) }
    func add(_ request: UNNotificationRequest) async throws {
        if delayNextAdd { delayNextAdd = false; addStarted = true; try await Task.sleep(for: .milliseconds(250)) }
        pending[request.identifier] = request
    }
    func remove(_ identifiers: [String]) { identifiers.forEach { pending.removeValue(forKey: $0) } }
}

struct DebugRepositorySupplementalHarness: View {
    @StateObject private var activities = ActivityStore()
    @StateObject private var planning = TrainingPlanStore()
    @StateObject private var goals = GoalStore()
    @StateObject private var personalization = PersonalizationStore()
    @State private var connectivity = ConnectivityStore()
    @State private var checkIn = DailyCheckInStore()
    @State private var preferences = WorkoutReminderPreferences()
    @State private var scheduler = WorkoutNotificationScheduler()
    @State private var coordinator: ActivitySyncCoordinator?
    @State private var status = "Running supplemental native scenarios"
    @State private var checks: [String] = []
    @State private var surface = "me"
    @State private var showsDetails = false
    @State private var ready = false

    var body: some View {
        Group {
            if ready && surface == "me" {
                DebugRepositoryMeSurface()
            } else if ready && surface == "blocked" {
                NavigationStack { ActiveTrainingPlanDetailsProjectionView(store: planning, accentColor: .accentColor) }
            } else { Text(status).padding() }
        }
        .environmentObject(activities).environmentObject(planning).environmentObject(personalization)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                GlobalConnectivityBanner().environmentObject(connectivity).environmentObject(activities)
                if ready {
                    HStack {
                        Button("Me") { surface = "me" }
                        Button("Blocked sync") { surface = "blocked" }
                        Button("Allow retry") { DebugActivityRepositoryTransport.rejectUpload = false; status = "Fixture now accepts retry" }
                        Button("Open details → no plan") { showsDetails = true; Task { await transitionNoPlan() } }
                    }.buttonStyle(.borderless).font(.caption).dynamicTypeSize(.large)
                }
                Text(status).font(.caption).dynamicTypeSize(.large).lineLimit(2)
            }.padding(8).background(.bar)
        }
        .sheet(isPresented: $showsDetails) {
            NavigationStack { ActiveTrainingPlanDetailsProjectionView(store: planning, accentColor: .accentColor) }
        }
        .task { await run() }
    }

    private func record(_ label: String) throws {
        checks.append(label)
        try JSONSerialization.data(withJSONObject: ["checks": checks, "status": status, "events": DebugRepositorySupplementalTransport.events, "pluralOutputs": DebugRepositorySupplementalTransport.pluralOutputs], options: [.prettyPrinted, .sortedKeys])
            .write(to: URL.documentsDirectory.appendingPathComponent("repository-supplemental-report.json"), options: .atomic)
        print("[RepositorySupplemental] \(label)")
    }
    private func expect(_ value: @autoclosure () -> Bool, _ label: String) throws {
        guard value() else { throw Failure.failed(label) }; try record(label)
    }
    private func waitFor(_ condition: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<150 { if condition() { return }; try await Task.sleep(for: .milliseconds(100)) }
        throw Failure.failed("timeout")
    }
    private func successState(_ activity: SavedActivity) -> SavedActivitySyncState {
        .init(clientActivityId: activity.id.uuidString, serverActivityId: "synthetic-\(activity.id)", lastAttemptAt: Date(), syncedAt: Date(), lastError: nil, localUpdatedAt: activity.sync?.localUpdatedAt)
    }
    private func summary(_ offset: Double) -> ActivitySummary {
        .init(startedAt: Date().addingTimeInterval(-600), endedAt: Date(), durationSecs: 600, distanceM: 1000, avgPace: 600, elevationGainM: 0,
            trackPoints: [CLLocation(latitude: 1 + offset, longitude: 1), CLLocation(latitude: 1.01 + offset, longitude: 1.01)])
    }
    private func renamed(_ activity: SavedActivity, _ title: String) throws -> SavedActivity {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(activity)) as! [String: Any]
        object["title"] = title
        return try JSONDecoder().decode(SavedActivity.self, from: JSONSerialization.data(withJSONObject: object)).withRoute(activity.route)
    }
    private func run() async {
        ActivityPhotoAlbumPreferences.savesPhotos = false
        do {
            AuthStore.activateRepositoryFixture("repository-supplemental")
            await activities.activateAccount()
            if !ProcessInfo.processInfo.arguments.contains("-OutboundRepositorySupplementalResume") {
                try await stageJournalFailure(); return
            }
            try await verifyJournalAndMutationRaces()
            try await verifyPlanningOrder()
            try await verifyReminderRace()
            try await verifyAuthentication()
            try verifyPlurals()
            try await verifyGoalTravelWithoutStatistics()
            try await verifyFanoutAndMe()
            try await prepareBlockedPhase()
            status = "Supplemental checks passed · normal Me and blocked sync ready"
            ready = true
            try record("supplemental_ready")
        } catch { status = "Failed: \(error)"; try? record(status) }
    }

    private struct JournalFixture: Codable {
        let target: SavedActivity
        let source: SavedActivity
        let targetRoute: SavedRoute
        let routeBytes: Data
        let metadataBytes: Data
        let originalBytes: Data
        let photoBytes: Data
    }
    private func routeDirectory(_ id: UUID) -> URL {
        URL.applicationSupportDirectory.appendingPathComponent("Outbound/Activities/\(id.uuidString)")
    }
    private func stageJournalFailure() async throws {
        try await ActivityPersistence.shared.deleteAll()
        await activities.activateAccount()
        let initial = try await activities.save(summary: summary(0), photos: [], reflection: nil, title: "Canonical target A")
        let metadata = ActivityElevationMetadata(algorithmVersion: "A", provider: "synthetic", attributionText: "Synthetic A", attributionURL: "https://example.invalid/A", modified: false)
        let target = initial.withRoute(SavedRoute(points: initial.route!.points, elevationMetadata: metadata))
        try await ActivityPersistence.shared.replace(target)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 32)).image { context in UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 24, height: 32)) }
        let capture = PhotoMetadata(takenAt: Date(), paceAtShot: nil, hrAtShot: nil, distAtShot: 0, coordinate: nil, captureContext: .active)
        let earlier = PhotoMetadata(takenAt: Date().addingTimeInterval(-120), paceAtShot: nil, hrAtShot: nil, distAtShot: 0, coordinate: nil, captureContext: .active)
        let source = try await activities.save(summary: summary(0.2), photos: [(image, capture), (image, earlier)], reflection: nil, title: "Source B")
        let targetSnapshot = try await ActivityPersistence.shared.uploadSnapshot(for: target.id)!
        _ = try await ActivityPersistence.shared.acknowledge(target.withSync(successState(target)), generation: targetSnapshot.generation,
            receipt: .init(planningRevision: 0, statisticsRevision: 0, completion: nil))
        let sourceSnapshot = try await ActivityPersistence.shared.uploadSnapshot(for: source.id)!
        let directory = routeDirectory(target.id)
        let fixture = try JournalFixture(target: target, source: source, targetRoute: target.route!,
            routeBytes: Data(contentsOf: directory.appendingPathComponent("route.bin")),
            metadataBytes: Data(contentsOf: directory.appendingPathComponent("route.meta.json")),
            originalBytes: Data(contentsOf: directory.appendingPathComponent("route.original.bin")),
            photoBytes: Data(contentsOf: ActivityPersistence.imageURL(for: source.photos[0])))
        let journal = try JSONEncoder().encode(fixture)
        try journal.write(to: URL.documentsDirectory.appendingPathComponent("repository-journal-fixture.json"), options: .atomic)
        await ActivityPersistence.shared.failNextWriteForRepositoryFixture()
        do {
            _ = try await ActivityPersistence.shared.adoptCanonical(target.withRoute(source.route).withSync(successState(target)), replacing: source,
                generation: sourceSnapshot.generation, canonicalGeneration: targetSnapshot.generation, receipt: .init(planningRevision: 0, statisticsRevision: 0, completion: nil))
            throw Failure.failed("journal_publish_should_fail")
        } catch let error as CocoaError {
            try expect(error.code == .fileWriteOutOfSpace, "existing_target_manifest_failure_leaves_recoverable_journal")
        }
        // Do not read the manifest: the external harness terminates this process here.
        status = "Journal staged · terminate and resume supplemental"
        try record("journal_restart_required")
    }

    private func verifyJournalAndMutationRaces() async throws {
        let fixture = try JSONDecoder().decode(JournalFixture.self, from: Data(contentsOf: URL.documentsDirectory.appendingPathComponent("repository-journal-fixture.json")))
        let target = fixture.target.withRoute(fixture.targetRoute), source = fixture.source
        let loaded = try await ActivityPersistence.shared.uploadSnapshot(for: target.id)!
        try expect(loaded.activity.route?.points.map(\.latitude) == target.route?.points.map(\.latitude)
            && loaded.activity.route?.points.map(\.longitude) == target.route?.points.map(\.longitude)
            && loaded.activity.route?.elevationMetadata == target.route?.elevationMetadata, "process_restart_recovers_existing_target_route_A")
        let retainedSource = try await ActivityPersistence.shared.uploadSnapshot(for: source.id)
        try expect(retainedSource != nil, "journal_recovery_retains_source_B")
        let directory = routeDirectory(target.id)
        let recoveredRoute = try Data(contentsOf: directory.appendingPathComponent("route.bin"))
        let recoveredMetadata = try Data(contentsOf: directory.appendingPathComponent("route.meta.json"))
        let recoveredOriginal = try Data(contentsOf: directory.appendingPathComponent("route.original.bin"))
        try expect(recoveredRoute == fixture.routeBytes && recoveredMetadata == fixture.metadataBytes && recoveredOriginal == fixture.originalBytes,
            "restart_restores_existing_target_route_metadata_and_original_bytes")
        let old = try await ActivityPersistence.shared.uploadSnapshot(for: source.id)!
        let order = old.activity.photos.map(\.id)
        try await ActivityPersistence.shared.mergePhotoMetadata(Array(old.activity.photos.reversed()), for: source.id)
        let ordered = try await ActivityPersistence.shared.uploadSnapshot(for: source.id)!
        try expect(ordered.activity.photos.map(\.id) == order, "photo_upload_metadata_preserves_manual_later_before_earlier_order")
        let edited = try renamed(old.activity, "Edited before upload snapshot capture")
        try await ActivityPersistence.shared.replace(edited)
        let current = try await ActivityPersistence.shared.uploadSnapshot(for: source.id)!
        try expect(current.activity.title == edited.title && current.generation > old.generation, "atomic_upload_snapshot_pairs_new_payload_with_new_generation")
        try await ActivityPersistence.shared.updateSyncState(successState(old.activity), for: source.id, expectedGeneration: old.generation)
        let rejected = try await ActivityPersistence.shared.applyRemoteBaseline(old.activity.withSync(successState(old.activity)), expectedGeneration: old.generation)
        let after = try await ActivityPersistence.shared.uploadSnapshot(for: source.id)!
        try expect(!rejected && after.activity.title == edited.title && after.activity.sync?.isSynced == false, "stale_sync_metadata_and_remote_baseline_cannot_overwrite_edit")
        DebugRepositorySupplementalTransport.canonicalTarget = loaded.activity
        await activities.activateAccount()
        await activities.syncPendingActivitiesIfNeeded()
        DebugRepositorySupplementalTransport.canonicalTarget = nil
        let records = try await ActivityPersistence.shared.load()
        try expect(records.count == 1 && records.first?.id == target.id, "actual_upload_canonical_DTO_adapter_adopts_one_identity")
        try expect(records.first?.photos.contains(where: { $0.remotePhotoId == "synthetic-cloud" }) == true, "canonical_adapter_retains_remote_photo_metadata")
        let localPhoto = records[0].photos.first(where: { $0.id == source.photos[0].id })!
        let copiedBytes = try Data(contentsOf: ActivityPersistence.imageURL(for: localPhoto))
        try expect(copiedBytes == fixture.photoBytes, "actual_canonical_adapter_preserves_local_JPEG_bytes")
    }

    private func verifyPlanningOrder() async throws {
        DebugActivityRepositoryTransport.failPlanning = false
        let base = try await APIClient.shared.fetchTrainingPlanState(readiness: nil)
        planning.activateAccount()
        var nine = base; nine.revision = 9
        var eleven = base; eleven.revision = 11
        DebugRepositorySupplementalTransport.planningResponses = [(nine, .milliseconds(250)), (eleven, .zero)]
        let before = DebugRepositorySupplementalTransport.planningStarted
        let reconcile = Task { try await planning.reconcileRepository() }
        try await waitFor { DebugRepositorySupplementalTransport.planningStarted > before }
        try await ActivityPersistence.shared.retainAcceptance(.init(planningRevision: 10, statisticsRevision: 0, completion: nil))
        planning.refresh(activities: activities.activities, readiness: nil, phase: .firstSession)
        try await waitFor { planning.serverRevision == 11 }
        let acknowledged = try await reconcile.value
        let diskData = try await ActivityPersistence.shared.planningSnapshot()!
        let disk = try JSONDecoder().decode(TrainingPlanStateResponse.self, from: diskData)
        try expect(acknowledged == 11 && disk.revision == 11, "out_of_order_read_9_returns_durable_11_after_ack_10")
        await activities.finishReconciliation(planning: acknowledged, statistics: nil)
        let projection = try await ActivityPersistence.shared.projection()
        try expect(projection.reconciliation == nil, "cursor_clears_only_after_newer_snapshot_is_on_disk")
    }

    private func verifyReminderRace() async throws {
        let client = RepositoryReminderClient()
        let value = WorkoutNotificationScheduler()
        value.useRepositoryFixtureClient(client)
        let prefs = WorkoutReminderPreferences(); prefs.isEnabled = true; prefs.reminderHour = 12
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let a = ScheduledWorkoutReminder(id: "A", workoutID: "A", date: nextDay, title: "A", durationSeconds: 600, sport: .run, source: "synthetic")
        let b = ScheduledWorkoutReminder(id: "B", workoutID: "B", date: nextDay, title: "B", durationSeconds: 600, sport: .run, source: "synthetic")
        AuthStore.activateRepositoryFixture("reminder-A")
        await value.configure(analyticsManager: nil, accountID: "reminder-A")
        let context = ActivityAccountBoundary.current
        client.delayNextAdd = true
        let old = Task { await ActivityAccountBoundary.$operation.withValue(context) { await value.reschedule(preferences: prefs, activities: [], workouts: [a], reason: "synthetic") } }
        try await waitFor { client.addStarted }
        AuthStore.activateRepositoryFixture("reminder-B")
        await value.configure(analyticsManager: nil, accountID: "reminder-B")
        await value.reschedule(preferences: prefs, activities: [], workouts: [b], reason: "synthetic")
        await old.value
        try expect(client.pending.count == 1 && client.pending.values.first?.content.userInfo["reminderID"] as? String == "B", "delayed_old_account_reminder_add_cannot_restore_A_or_remove_B")
        AuthStore.activateRepositoryFixture("repository-supplemental")
    }

    private func session(_ id: String, token: String, expired: Bool) -> AuthSession {
        .init(accessToken: token, accessTokenExpiresAt: Date().addingTimeInterval(expired ? -10 : 3600), refreshToken: "refresh-\(token)", refreshTokenExpiresAt: Date().addingTimeInterval(86400),
            refreshRecovery: nil, currentTermsVersion: nil, user: .init(id: id, username: "synthetic", displayName: "Synthetic", avatarUrl: nil, email: nil, onboardingCompleted: true, onboardingStatus: .completed, termsAcceptedVersion: nil))
    }
    private func verifyAuthentication() async throws {
        let a = session("auth-A", token: "old-A", expired: true)
        let rotated = session("auth-A", token: "rotated-A", expired: false)
        let b = session("auth-B", token: "new-B", expired: false)
        let repository = RepositoryMemorySessionRepository(a)
        let actor = SessionCoordinator(repository: repository)
        try await actor.replace(a)
        DebugRepositorySupplementalTransport.refreshResult = rotated
        DebugRepositorySupplementalTransport.refreshFailure = false
        let before = DebugRepositorySupplementalTransport.refreshStarted
        let context = ActivityAccountBoundary.current
        let first = Task { try await ActivityAccountBoundary.$operation.withValue(context) { try await actor.accessToken() } }
        let second = Task { try await ActivityAccountBoundary.$operation.withValue(context) { try await actor.accessToken() } }
        let tokens = try await (first.value, second.value)
        try expect(tokens.0 == rotated.accessToken && tokens.1 == rotated.accessToken && DebugRepositorySupplementalTransport.refreshStarted == before + 1,
            "same_account_coalesced_refresh_succeeds_for_both_waiters")
        for failure in [false, true] {
            try await actor.replace(a)
            let oldContext = ActivityAccountBoundary.current
            DebugRepositorySupplementalTransport.refreshFailure = failure
            let started = DebugRepositorySupplementalTransport.refreshStarted
            let old = Task { try await ActivityAccountBoundary.$operation.withValue(oldContext) { try await actor.accessToken() } }
            try await waitFor { DebugRepositorySupplementalTransport.refreshStarted > started }
            try await actor.replace(b)
            do { _ = try await old.value; throw Failure.failed("old_refresh_should_cancel") } catch is CancellationError { }
            let retained = await actor.storedSession()
            let persisted = try repository.load()
            try expect(retained?.accessToken == b.accessToken && persisted?.accessToken == b.accessToken,
                failure ? "delayed_old_refresh_failure_cannot_clear_new_account" : "delayed_old_refresh_cannot_replace_new_account")
        }
        try await actor.replace(a)
        DebugRepositorySupplementalTransport.refreshResult = rotated
        DebugRepositorySupplementalTransport.refreshFailure = false
        let flight = DebugRepositorySupplementalTransport.refreshStarted
        let contextA = ActivityAccountBoundary.current
        let oldA = Task { try await ActivityAccountBoundary.$operation.withValue(contextA) { try await actor.accessToken() } }
        try await waitFor { DebugRepositorySupplementalTransport.refreshStarted > flight }
        let expiredB = session("auth-B", token: "expired-B", expired: true)
        try await actor.replace(expiredB)
        DebugRepositorySupplementalTransport.refreshResult = b
        let tokenB = try await actor.accessToken()
        do { _ = try await oldA.value; throw Failure.failed("old_A_flight_should_cancel") } catch is CancellationError { }
        try expect(tokenB == b.accessToken && DebugRepositorySupplementalTransport.refreshStarted == flight + 2, "expired_new_account_refresh_never_coalesces_onto_old_account_flight")
        try await actor.replace(a)
        DebugRepositorySupplementalTransport.refreshResult = rotated
        DebugRepositorySupplementalTransport.refreshFailure = false
        let oldContext = ActivityAccountBoundary.current
        let start = DebugRepositorySupplementalTransport.refreshStarted
        DebugRepositorySupplementalTransport.networkRequests = 0
        var request = URLRequest(url: URL(string: "https://repository-auth.invalid/401")!)
        request.setValue("Bearer old-A", forHTTPHeaderField: "Authorization")
        let unauthorized = Task { try await ActivityAccountBoundary.$operation.withValue(oldContext) { try await APIClient.shared.verifyRepositoryAuthentication(request, coordinator: actor) } }
        try await waitFor { DebugRepositorySupplementalTransport.refreshStarted > start }
        try await actor.replace(b)
        do { _ = try await unauthorized.value; throw Failure.failed("old_401_should_cancel") } catch is CancellationError { }
        try expect(DebugRepositorySupplementalTransport.networkRequests == 1, "old_401_request_never_replays_with_new_account_token")
        AuthStore.activateRepositoryFixture("repository-supplemental")
    }

    private func verifyPlurals() throws {
        let expected = [
            "en": ["1 saved session pending sync", "2 saved sessions pending sync", "1 of 1 session saved · 10 of 10 min", "1 of 2 sessions saved · 10 of 20 min"],
            "es": ["1 sesión guardada pendiente de sincronizar", "2 sesiones guardadas pendientes de sincronizar", "1 de 1 sesión guardada · 10 de 10 min", "1 de 2 sesiones guardadas · 10 de 20 min"]
        ]
        for language in ["en", "es"] {
            guard let path = Bundle.main.path(forResource: language, ofType: "lproj"), let bundle = Bundle(path: path) else { throw Failure.failed("missing_\(language)_compiled_bundle") }
            let locale = Locale(identifier: language)
            let pending = String(localized: "plan.progress.pending", bundle: bundle, locale: locale)
            let saved = String(localized: "plan.progress.saved", bundle: bundle, locale: locale)
            let outputs = [String(format: pending, locale: locale, 1), String(format: pending, locale: locale, 2),
                String(format: saved, locale: locale, 1, 1, 10, 10), String(format: saved, locale: locale, 1, 2, 10, 20)]
            DebugRepositorySupplementalTransport.pluralOutputs[language] = outputs
            try expect(outputs == expected[language], "compiled_\(language)_exact_pending_and_target_one_many_strings")
        }
    }

    private func makeCoordinator() async {
        let value = ActivitySyncCoordinator(); coordinator = value
        let client = RepositoryReminderClient(); scheduler.useRepositoryFixtureClient(client)
        value.configure(activities: activities, planning: planning, checkIn: checkIn, connectivity: connectivity, preferences: preferences,
            scheduler: scheduler, goals: goals, personalization: personalization)
        await value.activateAccount()
    }
    private func verifyGoalTravelWithoutStatistics() async throws {
        let data = try Data(contentsOf: URL.documentsDirectory.appendingPathComponent("me-statistics.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value) { return date }
            throw CocoaError(.fileReadCorruptFile)
        }
        let statistics = try decoder.decode(AccountStatisticsSnapshot.self, from: data)
        let suite = "RepositoryGoalTravelFixture"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let goal = GoalDefinition(id: UUID(), kind: .weeklySessions, theme: .consistency, targetValue: 5,
            weekStart: statistics.weekStart, createdAt: Date(), status: .active)
        let conversation = GoalConversationState(step: .chooseTarget, draft: .init(kind: .weeklySessions, theme: .consistency, targetValue: 5), dismissedWeekStart: nil)
        let key = "goal_store_active_goal_v1.\(ActivityAccountBoundary.current.owner)"
        let conversationKey = "goal_store_conversation_v1.\(ActivityAccountBoundary.current.owner)"
        let goalData = try JSONEncoder().encode(goal), conversationData = try JSONEncoder().encode(conversation)
        defaults.set(goalData, forKey: key); defaults.set(conversationData, forKey: conversationKey)
        let model = GoalStore(defaults: defaults, calendar: PlanningCalendarContext.accountCalendar(timeZone: "Asia/Tokyo"))
        model.updateStatistics(nil, activities: [])
        try expect(model.activeGoal == goal && model.progress == nil && model.conversation.step == .chooseTarget,
            "Tokyo_device_nil_account_statistics_preserves_LA_goal_and_conversation")
        try expect(defaults.data(forKey: key) == goalData && defaults.data(forKey: conversationKey) == conversationData,
            "nil_account_statistics_does_not_expire_or_rewrite_persisted_LA_goal")
        model.updateStatistics(statistics, activities: [])
        try expect(model.progress?.currentValue == 4 && model.progress?.targetValue == 5 && model.activeGoal == goal,
            "canonical_LA_statistics_restore_four_of_five_progress_after_Tokyo_nil_state")
    }

    private func verifyFanoutAndMe() async throws {
        AuthStore.activateRepositoryFixture("repository-supplemental-fanout")
        try await ActivityPersistence.shared.deleteAll()
        DebugActivityRepositoryTransport.accepted = 0
        DebugActivityRepositoryTransport.uploads = 0
        let before = try await APIClient.shared.fetchAccountStatistics()
        let goal = GoalDefinition(id: UUID(), kind: .weeklySessions, theme: .consistency, targetValue: 5, weekStart: before.weekStart, createdAt: Date(), status: .active)
        UserDefaults.standard.set(try JSONEncoder().encode(goal), forKey: "goal_store_active_goal_v1.account:repository-supplemental-fanout")
        // Poisoned legacy device/Sunday cache is deliberately never loaded as account authority.
        var poison = try JSONSerialization.jsonObject(with: JSONEncoder().encode(before)) as! [String: Any]
        var poisonedGoal = poison["weeklyRunGoal"] as! [String: Any]; poisonedGoal["completedRuns"] = 999
        poison["weeklyRunGoal"] = poisonedGoal; poison["timeZone"] = "Asia/Tokyo"; poison["firstWeekday"] = 1
        let poisonData = try JSONSerialization.data(withJSONObject: poison)
        UserDefaults.standard.set(poisonData, forKey: "statistics.v1.repository-supplemental-fanout.Asia/Tokyo.1")
        UserDefaults.standard.set(poisonData, forKey: "statistics.v1.repository-supplemental-fanout.\(TimeZone.current.identifier).\(Calendar.current.firstWeekday)")
        connectivity.setRepositoryFixtureOffline(true)
        await makeCoordinator()
        try expect(activities.accountStatistics == nil, "legacy_device_Sunday_statistics_cache_is_ignored")
        await activities.refreshAccountStatistics()
        try expect(goals.progress?.currentValue == 3, "central_goal_observer_receives_complete_preupload_server_totals")
        let saved = try await activities.save(summary: summary(0), photos: [], reflection: nil, title: "One locally cached run")
        try expect(activities.activities.count == 1 && activities.accountStatistics?.weeklyRunGoal?.completedRuns == 3 && goals.progress?.currentValue == 3,
            "offline_save_does_not_add_optimistic_statistics_or_goal_delta")
        connectivity.setRepositoryFixtureOffline(false)
        try await waitFor { activities.accountStatistics?.weeklyRunGoal?.completedRuns == 4 && goals.progress?.currentValue == 4 }
        try await waitFor { DebugRepositorySupplementalTransport.events.contains("personalization_after_acceptance") }
        try expect(activities.accountStatistics?.weeklyRunGoal?.targetRuns == 5 && activities.activities.count == 1, "normal_Me_uses_complete_four_of_five_with_partial_local_history")
        try expect(activities.accountStatistics?.timeZone == "America/Los_Angeles" && activities.accountStatistics?.firstWeekday == 2, "travel_hint_and_Sunday_preference_do_not_replace_account_calendar")
        try expect(personalization.snapshot.modelVersion.contains("repository-supplemental-fanout"), "real_personalization_store_refreshes_after_accepted_upload")
        coordinator?.stopRepositoryFixture()
        let request = ReadinessCheckInRequestDTO(idempotencyKey: "synthetic-old-A", workoutId: "synthetic", recordedAt: Date(), choice: .good, note: nil)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        UserDefaults.standard.set(try encoder.encode([request]), forKey: "personalization_readiness_queue_v1.account:repository-supplemental-fanout")
        let oldCount = DebugRepositorySupplementalTransport.personalizationStarted
        let flushedBefore = DebugRepositorySupplementalTransport.queueOwners.count
        DebugRepositorySupplementalTransport.personalizationDelay = .milliseconds(300)
        let old = Task { await personalization.refresh() }
        try await waitFor { DebugRepositorySupplementalTransport.personalizationStarted > oldCount }
        AuthStore.activateRepositoryFixture("repository-supplemental-B")
        personalization.activateAccount()
        DebugRepositorySupplementalTransport.personalizationDelay = .zero
        await personalization.refresh()
        await old.value
        try expect(DebugRepositorySupplementalTransport.queueOwners.count == flushedBefore && personalization.snapshot.modelVersion.contains("repository-supplemental-B"), "old_account_personalization_response_cannot_publish_or_flush_its_queue_under_B")
        UserDefaults.standard.removeObject(forKey: "personalization_readiness_queue_v1.account:repository-supplemental-fanout")
        AuthStore.activateRepositoryFixture("repository-supplemental-fanout")
        await makeCoordinator()
        try await waitFor { activities.accountStatistics?.weeklyRunGoal?.completedRuns == 4 }
        try expect(activities.activities.contains(where: { $0.id == saved.id }), "account_return_restores_owned_partial_history")
    }
    private func prepareBlockedPhase() async throws {
        guard let slot = planning.currentWeek?.scheduledWorkouts.first(where: { $0.status != "completed" }) else { throw Failure.failed("missing_blocked_slot") }
        _ = try DebugActivityRepositoryTransport.data("planning")
        let raw = DebugActivityRepositoryTransport.fixture["planning"] as! [String: Any]
        let workouts = raw["workouts"] as! [[String: Any]]
        guard let referenceRaw = workouts.first(where: { $0["id"] as? String == slot.id })?["performedWorkoutReference"] else { throw Failure.failed("missing_blocked_receipt") }
        let reference = try JSONDecoder().decode(PerformedWorkoutReference.self, from: JSONSerialization.data(withJSONObject: referenceRaw))
        DebugActivityRepositoryTransport.rejectUpload = true
        let saved = try await activities.save(summary: summary(0), photos: [], reflection: nil, performedWorkoutReference: reference)
        try await waitFor { activities.repositoryProjection.blockedActivityIDs.contains(saved.id) && activities.failedActivityCount > 0 }
        try expect(planning.currentWeek?.scheduledWorkouts.first(where: { $0.id == slot.id })?.status == "sync_conflict", "stable_blocked_phase_uses_actual_plan_row_and_retry_banner")
    }

    private func transitionNoPlan() async {
        do {
            try await Task.sleep(for: .seconds(2))
            var empty = TrainingPlanStateResponse(activePlan: nil, recommendations: [], currentWeek: nil, todaySuggestion: nil, activitySuggestion: nil)
            empty.revision = (planning.serverRevision ?? 0) + 1
            _ = try await planning.commitRepositoryFixture(empty)
            try expect(planning.hasAuthoritativeNoPlan, "open_production_details_sheet_transitions_to_known_empty_projection")
        } catch { status = "Failed: \(error)"; try? record(status) }
    }
    private enum Failure: Error { case failed(String) }
}
#endif
