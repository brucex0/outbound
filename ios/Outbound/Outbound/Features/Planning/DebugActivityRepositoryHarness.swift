#if DEBUG
import CoreLocation
import SwiftUI

/// Bounded synthetic transport for the explicit isolated simulator route. Server receipt
/// and snapshot payloads are exported by the separate real HTTP/Prisma reproduction.
@MainActor
enum DebugActivityRepositoryTransport {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("-OutboundDebugActivityRepository") }
    static var failPlanning = true
    static var rejectUpload = false
    static var uploadDelay: Duration = .milliseconds(350)
    static var uploads = 0
    static var accepted = 0
    static var owners: [String] = []
    static var fixture: [String: Any] = [:]

    static func data(_ key: String) throws -> Data {
        if fixture.isEmpty {
            let url = URL.documentsDirectory.appendingPathComponent("repository-fixture.json")
            fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
        }
        guard let value = fixture[key] else { throw CocoaError(.fileReadCorruptFile) }
        return try JSONSerialization.data(withJSONObject: value)
    }

    static func upload(_ request: ActivityUploadRequest) async throws -> ActivityUploadResponse {
        uploads += 1
        let context = ActivityAccountBoundary.context
        owners.append(context.owner)
        try await Task.sleep(for: uploadDelay)
        try ActivityAccountBoundary.validate(context)
        if rejectUpload { throw APIError.http(statusCode: 409, message: "Synthetic association conflict", code: "performed_workout_conflict") }
        accepted += 1
        if DebugRepositorySupplementalTransport.enabled {
            DebugRepositorySupplementalTransport.events.append("upload_accepted")
            if let target = DebugRepositorySupplementalTransport.canonicalTarget {
                return .init(id: target.sync!.serverActivityId!, clientActivityId: target.id.uuidString, status: "updated", uploadedAt: Date(), serverUpdatedAt: Date(), groupContributions: nil,
                    reconciliation: .init(planningRevision: 0, statisticsRevision: 0, completion: nil))
            }
        }
        let raw = try JSONSerialization.jsonObject(with: data("activityAcknowledgement")) as? [String: Any] ?? [:]
        let receiptRaw = raw["reconciliation"] as? [String: Any] ?? [:]
        let reference = request.clientData.performedWorkoutReference
        let completion = reference.map { reference in
            ActivityCompletionAssociation(activityId: "synthetic-server-\(request.clientActivityId)",
                plannedWorkoutId: reference.plannedWorkoutId, planVersionId: reference.planVersionId,
                status: "completed", prescribedDurationSeconds: (receiptRaw["completion"] as? [String: Any])?["prescribedDurationSeconds"] as? Int ?? request.durationSecs)
        }
        return ActivityUploadResponse(id: "synthetic-server-\(request.clientActivityId)", clientActivityId: request.clientActivityId,
            status: "created", uploadedAt: Date(), serverUpdatedAt: Date(), groupContributions: nil,
            reconciliation: .init(planningRevision: receiptRaw["planningRevision"] as? Int ?? 2,
                statisticsRevision: receiptRaw["statisticsRevision"] as? Int ?? 1, completion: completion))
    }
}

struct DebugActivityRepositoryHarness: View {
    @StateObject private var activities = ActivityStore()
    @StateObject private var planning = TrainingPlanStore()
    @State private var status = "Running synthetic repository scenario"
    @State private var coordinator: ActivitySyncCoordinator?
    @State private var connectivity = ConnectivityStore()
    @State private var checkIn = DailyCheckInStore()
    @State private var preferences = WorkoutReminderPreferences()
    @State private var report: [String] = []

    var body: some View {
        NavigationStack {
            Group {
                if let plan = planning.activePlan, let week = planning.currentWeek {
                    ActiveTrainingPlanDetailView(activePlan: plan, week: week, todaySuggestion: planning.todaySuggestion,
                        accentColor: .accentColor, benchmarkSaveOverride: { _ in })
                } else { Text(status).padding() }
            }
            .safeAreaInset(edge: .bottom) {
                VStack {
                    GlobalConnectivityBanner().environmentObject(connectivity).environmentObject(activities)
                    Text(status).font(.caption).padding(8)
                }.background(.bar)
            }
        }.task { await run() }
    }

    private func record(_ value: String) throws {
        report.append(value)
        let data = try JSONSerialization.data(withJSONObject: ["checks": report, "status": status], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL.documentsDirectory.appendingPathComponent("repository-harness-report.json"), options: .atomic)
        print("[RepositoryHarness] \(value)")
    }

    private func expect(_ condition: @autoclosure () -> Bool, _ label: String) throws {
        guard condition() else { throw HarnessFailure.failed(label) }
        try record(label)
    }

    private func makeCoordinator() async {
        let value = ActivitySyncCoordinator()
        coordinator = value
        value.configure(activities: activities, planning: planning, checkIn: checkIn, connectivity: connectivity,
            preferences: preferences, scheduler: WorkoutNotificationScheduler.shared)
        await value.activateAccount()
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<150 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw HarnessFailure.failed("timed_out")
    }

    private func run() async {
        let albumPreference = ActivityPhotoAlbumPreferences.savesPhotos
        ActivityPhotoAlbumPreferences.savesPhotos = false
        defer { ActivityPhotoAlbumPreferences.savesPhotos = albumPreference }
        do {
            AuthStore.activateRepositoryFixture("repository-fixture-a")
            connectivity.setRepositoryFixtureOffline(true)
            let initial = try await fixtureState(confirmed: false)
            let phase = ProcessInfo.processInfo.arguments.contains("-OutboundRepositoryResume") ? "resume" : "seed"
            if phase == "seed" {
                try await ActivityPersistence.shared.deleteAll()
                let encoder = JSONEncoder()
                try await ActivityPersistence.shared.storePlanningSnapshot(try encoder.encode(initial), revision: initial.revision)
                UserDefaults.standard.set(try encoder.encode(initial), forKey: "training_plan_store_state_v3.account:repository-fixture-a")
                UserDefaults.standard.set(AppLanguage.currentIdentifier, forKey: "training_plan_store_cache_locale_v1.account:repository-fixture-a")
            }
            await makeCoordinator()
            planning.applyRepositoryFixture(initial)
            guard let suggestion = initial.todaySuggestion,
                  let reference = suggestion.suggestedSession.performedWorkoutReference else { throw HarnessFailure.failed("missing_launch_receipt") }
            if phase == "seed" {
                let summary = ActivitySummary(startedAt: Date().addingTimeInterval(-1200), endedAt: Date(),
                    durationSecs: max(60, suggestion.workout.durationSeconds - 120), distanceM: 3000, avgPace: 400,
                    elevationGainM: 0, trackPoints: [])
                let saved = try await activities.save(summary: summary, photos: [], reflection: nil,
                    goal: .timeSeconds(suggestion.workout.durationSeconds), energyKilocalories: 170,
                    title: "Synthetic durable repository run", performedWorkoutReference: reference)
                try expect(saved.performedWorkoutReference == reference && saved.energyKilocalories == 170, "save_retains_exact_receipt_and_energy")
                try expect(activities.repositorySnapshot.activities.contains { $0.id == saved.id }, "save_publishes_committed_snapshot")
                try expect(planning.currentWeek?.pendingSessions == 1, "offline_save_updates_plan_pending_immediately")
                try expect(planning.currentWeek?.scheduledWorkouts.first { $0.id == reference.plannedWorkoutId }?.status == "pending_sync", "exact_slot_is_pending")
                try expect(DebugActivityRepositoryTransport.uploads == 0, "offline_does_not_upload")
                status = "Seed passed · terminate and resume"
                try record("seed_complete")
                return
            }
            try expect(activities.activities.count == 1, "process_relaunch_restores_owned_activity")
            try expect(planning.currentWeek?.pendingSessions == 1, "process_relaunch_restores_pending_plan_projection")
            guard let saved = activities.activities.first else { throw HarnessFailure.failed("missing_saved") }
            let generation = try await ActivityPersistence.shared.generation(for: saved.id)
            connectivity.setRepositoryFixtureOffline(false)
            try await waitUntil { DebugActivityRepositoryTransport.uploads > 0 }
            try await activities.updateActivity(saved, title: "Edited while upload waits", startedAt: saved.startedAt,
                distanceM: saved.distanceM, durationSecs: saved.durationSecs, gear: saved.gear)
            try await waitUntil { DebugActivityRepositoryTransport.accepted > 0 }
            let after = try await ActivityPersistence.shared.load().first { $0.id == saved.id }
            try expect(after?.title == "Edited while upload waits", "delayed_ack_cannot_overwrite_edit")
            let newGeneration = try await ActivityPersistence.shared.generation(for: saved.id)
            try expect(newGeneration != generation, "meaningful_edit_increments_generation")
            try await waitUntil { activities.pendingActivityCount == 0 }
            try expect(activities.repositoryProjection.reconciliation != nil, "accepted_upload_retains_failed_planning_cursor")
            try expect(activities.activities.first?.energyKilocalories == 170, "sync_metadata_preserves_energy")
            coordinator?.stopRepositoryFixture()
            DebugActivityRepositoryTransport.failPlanning = false
            await ActivityPersistence.shared.failNextPlanningWriteForRepositoryFixture()
            do {
                _ = try await planning.reconcileRepository()
                throw HarnessFailure.failed("planning_cache_write_failure_not_thrown")
            } catch let error as CocoaError {
                try expect(error.code == .fileWriteOutOfSpace, "planning_cache_write_failure_is_reported")
            }
            let failedCache = try await ActivityPersistence.shared.projection()
            try expect(failedCache.reconciliation != nil, "planning_cache_failure_retains_reconciliation_cursor")
            await makeCoordinator()
            try await waitUntil { activities.repositoryProjection.reconciliation == nil }
            try expect(planning.currentWeek?.pendingSessions == 0, "restarted_coordinator_finishes_remaining_read_reconciliation")
            try expect(planning.currentWeek?.scheduledWorkouts.first { $0.id == reference.plannedWorkoutId }?.status == "completed", "server_acceptance_confirms_exact_slot")
            let confirmed = planning.currentWeek?.completedSessions
            // Local history deletion does not revoke a server-owned completion.
            if let current = activities.activities.first { try await ActivityPersistence.shared.delete(current) }
            await activities.activateAccount()
            planning.applyRepositoryProjection(activities.repositorySnapshot.projection, activities: activities.repositorySnapshot.activities)
            try expect(planning.currentWeek?.completedSessions == confirmed, "confirmed_plan_credit_survives_local_history_deletion")
            try await verifyConflictAndAccountIsolation(reference: reference)
            try await verifyInvalidationTicket()
            try await verifyCanonicalMedia()
            try verifyProjectionEdges(initial: initial, reference: reference)
            status = "All synthetic repository checks passed"
            try record("resume_complete")
        } catch {
            status = "Failed: \(error)"
            try? record(status)
        }
    }

    private func fixtureState(confirmed: Bool) async throws -> TrainingPlanStateResponse {
        let old = DebugActivityRepositoryTransport.failPlanning
        DebugActivityRepositoryTransport.failPlanning = false
        let count = DebugActivityRepositoryTransport.accepted
        DebugActivityRepositoryTransport.accepted = confirmed ? 1 : 0
        defer { DebugActivityRepositoryTransport.failPlanning = old; DebugActivityRepositoryTransport.accepted = count }
        return try await APIClient.shared.fetchTrainingPlanState(readiness: nil)
    }

    private func verifyConflictAndAccountIsolation(reference: PerformedWorkoutReference) async throws {
        connectivity.setRepositoryFixtureOffline(true)
        let summary = ActivitySummary(startedAt: Date().addingTimeInterval(-600), endedAt: Date(), durationSecs: 600,
            distanceM: 1000, avgPace: 600, elevationGainM: 0, trackPoints: [])
        // A different exact slot avoids existing confirmed credit masking rejection withdrawal.
        let previousPending = planning.currentWeek?.pendingSessions ?? 0
        let conflictSlot = planning.currentWeek?.scheduledWorkouts.first(where: { $0.id != reference.plannedWorkoutId && $0.status != "completed" })?.id
        guard let conflictSlot else { throw HarnessFailure.failed("fixture_needs_second_currentweek_slot") }
        let conflictReference = PerformedWorkoutReference(policyVersion: reference.policyVersion, issuanceId: reference.issuanceId,
            revision: reference.revision, plannedWorkoutId: conflictSlot, planVersionId: reference.planVersionId,
            performedAsIssued: true, workoutEditId: nil, workoutRevision: nil)
        let conflict = try await activities.save(summary: summary, photos: [], reflection: nil,
            performedWorkoutReference: conflictReference)
        try expect(planning.currentWeek?.pendingSessions == previousPending + 1, "real_currentweek_slot_receives_provisional_pending_credit")
        coordinator?.stopRepositoryFixture()
        DebugActivityRepositoryTransport.rejectUpload = true
        await makeCoordinator()
        connectivity.setRepositoryFixtureOffline(false)
        try await waitUntil { activities.repositoryProjection.blockedActivityIDs.contains(conflict.id) }
        try expect(!activities.repositoryProjection.pendingWorkoutIDs.contains(conflictReference.plannedWorkoutId), "terminal_conflict_withdraws_pending_credit")
        try expect(planning.currentWeek?.pendingSessions == previousPending, "terminal_conflict_rolls_back_visible_pending_progress")
        try expect(planning.currentWeek?.scheduledWorkouts.first(where: { $0.id == conflictSlot })?.status == "sync_conflict", "terminal_conflict_marks_same_scheduled_row")
        try expect(activities.activities.contains { $0.id == conflict.id }, "terminal_conflict_retains_local_activity")
        let reloaded = try await ActivityPersistence.shared.projection()
        try expect(reloaded.blockedActivityIDs.contains(conflict.id), "terminal_conflict_survives_disk_reload")
        coordinator?.stopRepositoryFixture()
        DebugActivityRepositoryTransport.rejectUpload = false
        AuthStore.activateRepositoryFixture("repository-fixture-b")
        await activities.activateAccount()
        planning.activateAccount()
        try expect(activities.activities.isEmpty && planning.activePlan == nil, "account_switch_clears_history_plan_and_cached_projection")
        try await ActivityPersistence.shared.deleteAll()
        AuthStore.activateRepositoryFixture("repository-fixture-a")
        await activities.activateAccount()
        try expect(activities.activities.contains { $0.id == conflict.id }, "other_account_delete_preserves_owned_pending_data")
        let stale = ActivityAccountBoundary.current
        AuthStore.activateRepositoryFixture("repository-fixture-b")
        do {
            try await ActivityAccountBoundary.$operation.withValue(stale) { _ = try await ActivityPersistence.shared.load() }
            throw HarnessFailure.failed("old_account_operation_was_not_rejected")
        } catch is CancellationError { try record("stale_account_epoch_rejects_disk_operation") }
        AuthStore.activateRepositoryFixture("repository-fixture-a")
        await activities.activateAccount()
        planning.activateAccount()
        planning.applyRepositoryFixture(try await fixtureState(confirmed: true))
        planning.applyRepositoryProjection(activities.repositorySnapshot.projection, activities: activities.repositorySnapshot.activities)
    }

    private func verifyInvalidationTicket() async throws {
        let before = try await ActivityPersistence.shared.statisticsReadTicket()
        try await ActivityPersistence.shared.invalidateReadModels()
        let after = try await ActivityPersistence.shared.statisticsReadTicket()
        try await ActivityPersistence.shared.finishReconciliation(planning: Int.max, statistics: Int.max, statisticsTicket: before)
        let stale = try await ActivityPersistence.shared.projection()
        try expect(stale.reconciliation?.requiresStatisticsRead == true, "older_statistics_read_cannot_clear_newer_command_invalidation")
        try await ActivityPersistence.shared.finishReconciliation(planning: Int.max, statistics: Int.max, statisticsTicket: after)
        let fresh = try await ActivityPersistence.shared.projection()
        try expect(fresh.reconciliation == nil, "matching_statistics_read_ticket_finishes_command_invalidation")
    }

    private func verifyCanonicalMedia() async throws {
        coordinator?.stopRepositoryFixture()
        let locations = [CLLocation(latitude: 1, longitude: 1), CLLocation(latitude: 1.01, longitude: 1.01)]
        let summary = ActivitySummary(startedAt: Date().addingTimeInterval(-600), endedAt: Date(), durationSecs: 600,
            distanceM: 1000, avgPace: 600, elevationGainM: 0, trackPoints: locations)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 32)).image { context in
            UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 24, height: 32))
        }
        let metadata = PhotoMetadata(takenAt: Date(), paceAtShot: nil, hrAtShot: nil, distAtShot: 0, coordinate: nil, captureContext: .active)
        let source = try await activities.save(summary: summary, photos: [(image, metadata)], reflection: nil)
        let sourceGeneration = try await ActivityPersistence.shared.generation(for: source.id)!
        let sourceBytes = try Data(contentsOf: ActivityPersistence.imageURL(for: source.photos[0]))
        let sourceDirectory = ActivityPersistence.imageURL(for: source.photos[0]).deletingLastPathComponent().deletingLastPathComponent()
        let originalBytes = try Data(contentsOf: sourceDirectory.appendingPathComponent("route.original.bin"))
        let canonicalID = UUID()
        let copied = try await ActivityPersistence.shared.copyPhotos(source.photos, into: canonicalID)
        let placeholder = SavedPhoto(id: UUID(), takenAt: Date(), paceAtShot: nil, hrAtShot: nil, distAtShot: 0,
            coordinate: nil, captureContext: .active, relativePath: "\(canonicalID)/photos/cloud.jpg",
            remotePhotoId: "synthetic-cloud-photo", remoteUploadedAt: Date(), remoteThumbnailURL: "https://example.invalid/cloud.jpg")
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        var raw = try JSONSerialization.jsonObject(with: encoder.encode(source)) as! [String: Any]
        raw["id"] = canonicalID.uuidString
        raw["photos"] = try JSONSerialization.jsonObject(with: encoder.encode(copied + [placeholder]))
        let sync = SavedActivitySyncState(clientActivityId: canonicalID.uuidString, serverActivityId: "synthetic-canonical",
            lastAttemptAt: Date(), syncedAt: Date(), lastError: nil, localUpdatedAt: source.sync?.localUpdatedAt)
        raw["sync"] = try JSONSerialization.jsonObject(with: encoder.encode(sync))
        let canonical = try decoder.decode(SavedActivity.self, from: JSONSerialization.data(withJSONObject: raw)).withRoute(source.route)
        let receipt = ActivityReconciliationReceipt(planningRevision: 0, statisticsRevision: 0, completion: nil)
        await ActivityPersistence.shared.failNextWriteForRepositoryFixture()
        do {
            _ = try await ActivityPersistence.shared.adoptCanonical(canonical, replacing: source,
                generation: sourceGeneration, canonicalGeneration: nil, receipt: receipt)
            throw HarnessFailure.failed("canonical_write_failure_not_thrown")
        } catch let error as CocoaError {
            try expect(error.code == .fileWriteOutOfSpace, "canonical_commit_failure_is_reported")
        }
        let afterFailure = try await ActivityPersistence.shared.load()
        try expect(afterFailure.contains { $0.id == source.id } && !afterFailure.contains { $0.id == canonicalID }, "failed_canonical_commit_retains_source_identity")
        try await ActivityPersistence.shared.replace(source)
        let refused = try await ActivityPersistence.shared.adoptCanonical(canonical, replacing: source,
            generation: sourceGeneration, canonicalGeneration: nil, receipt: receipt)
        try expect(refused == nil, "stale_source_generation_refuses_canonical_overwrite")
        let generation = try await ActivityPersistence.shared.generation(for: source.id)!
        let adopted = try await ActivityPersistence.shared.adoptCanonical(canonical, replacing: source,
            generation: generation, canonicalGeneration: nil, receipt: receipt)
        let loaded = try await ActivityPersistence.shared.load()
        try expect(adopted != nil && !loaded.contains { $0.id == source.id } && loaded.contains { $0.id == canonicalID }, "canonical_switch_is_one_manifest_transition")
        let restored = loaded.first { $0.id == canonicalID }!
        try expect(restored.photos.count == 2 && restored.photos.contains { $0.remotePhotoId == "synthetic-cloud-photo" }, "canonical_switch_retains_local_and_remote_photos")
        let copiedBytes = try Data(contentsOf: ActivityPersistence.imageURL(for: copied[0]))
        try expect(sourceBytes == copiedBytes, "canonical_photo_copy_preserves_exact_encoded_bytes")
        let canonicalDirectory = ActivityPersistence.imageURL(for: copied[0]).deletingLastPathComponent().deletingLastPathComponent()
        let canonicalOriginal = try Data(contentsOf: canonicalDirectory.appendingPathComponent("route.original.bin"))
        try expect(canonicalOriginal == originalBytes && restored.route?.points.count == source.route?.points.count, "canonical_switch_preserves_route_and_original_sidecar")
        // The same atomic write path must propagate failed sync acknowledgements.
        await ActivityPersistence.shared.failNextWriteForRepositoryFixture()
        do {
            _ = try await ActivityPersistence.shared.acknowledge(restored, generation: generation, receipt: receipt)
            throw HarnessFailure.failed("ack_write_failure_not_thrown")
        } catch let error as CocoaError {
            try expect(error.code == .fileWriteOutOfSpace, "acknowledgement_persistence_failure_is_reported")
        }
        try await ActivityPersistence.shared.delete(restored)
        await activities.activateAccount()
    }

    private func verifyProjectionEdges(initial: TrainingPlanStateResponse, reference: PerformedWorkoutReference) throws {
        let neutral = ActivityPlanProjector.project(initial, repository: .init())
        try expect(neutral.currentWeek?.completedSessions == initial.currentWeek?.completedSessions, "free_activity_does_not_infer_plan_credit")
        var pending = ActivityRepositoryProjection()
        pending.pendingWorkoutIDs = [reference.plannedWorkoutId]
        let once = ActivityPlanProjector.project(initial, repository: pending)
        try expect(once.currentWeek?.pendingSessions == 1, "repeated_exact_slot_pending_is_deduplicated")
        if let calendar = initial.calendar {
            let monday = calendar.calendar.date(byAdding: .day, value: 7, to: calendar.weekStart)!
            let next = ActivityPlanProjector.project(initial, repository: pending, now: monday)
            try expect(next.currentWeek?.calendar?.weekStart == monday, "offline_monday_rollover_uses_account_calendar")
            try expect(next.currentWeek?.pendingSessions == 0, "offline_rollover_does_not_relabel_priorweek_credit")
        }
        var noPlan = TrainingPlanStateResponse(activePlan: nil, recommendations: [], currentWeek: nil,
            todaySuggestion: nil, activitySuggestion: nil)
        noPlan.revision = (planning.serverRevision ?? 0) + 1
        planning.applyRepositoryFixture(noPlan)
        try expect(planning.activePlan == nil && planning.currentWeek == nil, "authoritative_no_plan_clears_retained_plan")
        planning.applyRepositoryFixture(initial)
        try expect(planning.activePlan == nil, "older_snapshot_cannot_restore_ended_plan")
        var display = initial
        display.revision = (planning.serverRevision ?? 0) + 1
        planning.applyRepositoryFixture(display)
        planning.applyRepositoryProjection(activities.repositorySnapshot.projection, activities: activities.repositorySnapshot.activities)
    }

    private enum HarnessFailure: Error { case failed(String) }
}
#endif
