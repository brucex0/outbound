import Combine
import CoreLocation
import Foundation
import UIKit

@MainActor
final class ActivityStore: ObservableObject {
    @Published private(set) var activities: [SavedActivity] = []
    @Published private(set) var isSyncing = false
    @Published private(set) var hasLoadedActivities = false
    @Published private(set) var photoAlbumNotice: ActivityPhotoAlbumNotice?
    private let api = APIClient.shared
    private let persistence = ActivityPersistence.shared
    private let analyticsManager: AnalyticsManager?
    private var activityRevision = 0
    private var elevationCorrectionIDs = Set<UUID>()
    private var watchAutoSaveInFlight = Set<UUID>()

    var pendingActivityCount: Int {
        activities.filter { !($0.sync?.isSynced ?? false) }.count
    }

    var failedActivityCount: Int {
        activities.filter { activity in
            !(activity.sync?.isSynced ?? false) && activity.sync?.lastError?.isEmpty == false
        }.count
    }

    init(analyticsManager: AnalyticsManager? = nil) {
        self.analyticsManager = analyticsManager
        Task { await loadActivities() }
    }

    @discardableResult
    func save(
        summary: ActivitySummary,
        photos: [(UIImage, PhotoMetadata)],
        activityType: ActivityType = .running,
        reflection: FinishReflection?,
        goal: ActivityGoal? = nil,
        energyKilocalories: Int? = nil,
        title: String? = nil,
        source: ActivitySourceMetadata = .outboundRecorded,
        gear: ActivityGearAttachment? = nil,
        manualEdits: ActivityManualEdits? = nil,
        indoor: ActivityIndoorMetadata? = nil,
        cadence: ActivityCadenceSummary? = nil,
        heartRateZones: ActivityHeartRateZoneSummary? = nil,
        recordingSession: ActivityRecordingSessionMetadata? = nil,
        activityEventID: String? = nil,
        followedRoute: FollowedRouteMetadata? = nil,
        recognitionBadgeIDs: [RecognitionBadgeID] = [],
        companionType: ActivityCompanionType? = nil
    ) async throws -> SavedActivity {
        let resolvedTitle = title ?? autoTitle(for: summary.startedAt)
        ActivityDiagnosticLog.notice(
            .persistence,
            "Local activity save started type=\(activityType.rawValue) source=\(source.kind.rawValue) duration=\(ActivityDiagnosticLog.durationBucket(seconds: summary.durationSecs)) distance=\(ActivityDiagnosticLog.distanceBucket(meters: summary.distanceM)) photos=\(ActivityDiagnosticLog.countBucket(photos.count))"
        )
        let activity: SavedActivity
        do {
            activity = try await persistence.save(
                summary: summary,
                photos: photos,
                activityType: activityType,
                title: resolvedTitle,
                guideNudge: "",
                reflection: reflection,
                goal: goal,
                energyKilocalories: energyKilocalories,
                source: source,
                gear: gear,
                manualEdits: manualEdits,
                indoor: indoor,
                cadence: cadence,
                heartRateZones: heartRateZones,
                recordingSession: recordingSession,
                activityEventID: activityEventID,
                followedRoute: followedRoute,
                recognitionBadgeIDs: recognitionBadgeIDs,
                companionType: companionType
            )
            } catch {
            ActivityDiagnosticLog.error(
                .persistence,
                "Local activity save failed type=\(activityType.rawValue) source=\(source.kind.rawValue) error=\(ActivityDiagnosticLog.errorCategory(error))"
            )
            throw error
        }
        activityRevision += 1
        activities.append(activity)
        sortActivitiesByStartTime()
        ActivityDiagnosticLog.notice(
            .persistence,
            "Local activity save completed history_count=\(ActivityDiagnosticLog.countBucket(activities.count)) sync_pending=true"
        )
        await exportPhotosToAlbumIfNeeded(activity)
        Task {
            await syncActivityIfPossible(id: activity.id)
        }
        return activity
    }

    func clearPhotoAlbumNotice() {
        photoAlbumNotice = nil
    }

    func importHealthWorkouts(_ workouts: [ImportedWorkout]) async -> Set<String> {
        ActivityDiagnosticLog.notice(
            .healthKit,
            "Health import persistence started candidates=\(ActivityDiagnosticLog.countBucket(workouts.count))"
        )
        var importedIDs: Set<String> = []
        let existingIDs = Set(activities.compactMap(\.source.externalID))
        for workout in workouts where !existingIDs.contains(workout.id) {
            let distance = max(0, workout.distanceMeters ?? 0)
            let duration = max(1, workout.durationSeconds)
            let summary = ActivitySummary(
                startedAt: workout.startedAt,
                endedAt: workout.endedAt,
                durationSecs: duration,
                distanceM: distance,
                avgPace: distance > 0 ? Double(duration) / (distance / 1_000) : nil,
                trackPoints: []
            )
            do {
                _ = try await save(
                    summary: summary,
                    photos: [],
                    activityType: workout.activityType,
                    reflection: nil,
                    energyKilocalories: workout.energyBurnedKilocalories.map { Int($0.rounded()) },
                    title: workout.activityType.healthImportTitle,
                    source: ActivitySourceMetadata(
                        kind: .appleHealth,
                        displayName: workout.sourceName,
                        deviceName: nil,
                        externalID: workout.id,
                        importedAt: Date()
                    )
                )
                importedIDs.insert(workout.id)
            } catch {
                ActivityDiagnosticLog.error(
                    .healthKit,
                    "Health import persistence failed error=\(ActivityDiagnosticLog.errorCategory(error))"
                )
                continue
            }
        }
        ActivityDiagnosticLog.notice(
            .healthKit,
            "Health import persistence completed imported=\(ActivityDiagnosticLog.countBucket(importedIDs.count))"
        )
        return importedIDs
    }

    var importedHealthExternalIDs: Set<String> {
        Set(activities.compactMap { activity in
            activity.source.kind == .appleHealth
                ? activity.source.externalID
                : activity.recordingSession?.healthKitWorkoutExternalReference
        })
    }

    func attachHealthKitWorkoutReference(sessionUUID: UUID, externalReference: String) async {
        guard let index = activities.firstIndex(where: {
            $0.recordingSession?.sessionUUID == sessionUUID
        }), activities[index].recordingSession?.healthKitWorkoutExternalReference != externalReference else { return }
        let updated = activities[index].withHealthKitWorkoutReference(externalReference)
        do {
            try await persistence.replace(updated)
            activityRevision += 1
            activities[index] = updated
        } catch {
            ActivityDiagnosticLog.error(
                .persistence,
                "Watch workout reference reconciliation failed error=\(ActivityDiagnosticLog.errorCategory(error))"
            )
        }
    }

    /// Saves a watch-owned workout when no phone recorder was alive to create the normal post-run review.
    /// The session UUID makes repeated HealthKit mirror callbacks idempotent.
    @discardableResult
    func saveWatchWorkoutIfNeeded(
        sessionUUID: UUID,
        identity: PlainstrideWorkoutIdentity,
        finalMetrics: PlainstrideFinalWorkoutMetrics,
        externalReference: String?
    ) async -> SavedActivity? {
        if !hasLoadedActivities {
            await loadActivities()
        }
        guard !activities.contains(where: { $0.recordingSession?.sessionUUID == sessionUUID }) else {
            return activities.first { $0.recordingSession?.sessionUUID == sessionUUID }
        }
        guard watchAutoSaveInFlight.insert(sessionUUID).inserted else { return nil }
        defer { watchAutoSaveInFlight.remove(sessionUUID) }

        let startedAt = identity.canonicalStartDate ?? Date().addingTimeInterval(-finalMetrics.elapsedTime)
        let endedAt = startedAt.addingTimeInterval(max(0, finalMetrics.elapsedTime))
        let distance = max(0, finalMetrics.distanceMeters ?? 0)
        let summary = ActivitySummary(
            startedAt: startedAt,
            endedAt: endedAt,
            durationSecs: max(0, Int(finalMetrics.elapsedTime.rounded())),
            distanceM: distance,
            avgPace: distance > 0 ? finalMetrics.elapsedTime / (distance / 1_000) : nil,
            elevationGainM: 0,
            walkingStepCount: nil,
            healthMetrics: ActivityHealthMetrics(
                averageHeartRateBPM: finalMetrics.averageBPM,
                maxHeartRateBPM: finalMetrics.maximumBPM,
                heartRateSampleCount: finalMetrics.averageBPM == nil && finalMetrics.maximumBPM == nil ? 0 : 1
            ),
            heartRateZones: nil,
            sessionMetadata: ActivityRecordingSessionMetadata(
                sessionUUID: sessionUUID,
                origin: .appleWatch,
                recordingDevice: .appleWatch,
                healthKitOwnership: externalReference == nil ? .phoneWriteBack : .appleWatchPrimary,
                healthKitWorkoutExternalReference: externalReference
            ),
            routeGuidance: nil,
            trackPoints: [],
            trackSegmentStartIndices: []
        )
        guard ActivitySaveEligibility.evaluate(
            durationSecs: summary.durationSecs,
            distanceM: summary.distanceM
        ) == .eligible else {
            ActivityDiagnosticLog.notice(.persistence, "Watch workout auto-save skipped because it was too short")
            return nil
        }

        let activityType: ActivityType = switch identity.activity {
        case .running: .running
        case .walking: .walking
        case .cycling: .cycling
        case .hiking: .hiking
        case .swimming: .swimming
        case .strength: .strengthTraining
        case .mobility: .mobility
        }
        do {
            let saved = try await save(
                summary: summary,
                photos: [],
                activityType: activityType,
                reflection: nil,
                energyKilocalories: finalMetrics.activeEnergyKilocalories.map { Int($0.rounded()) },
                title: "Apple Watch \(activityType.rawValue)",
                source: .outboundRecorded,
                recordingSession: summary.sessionMetadata,
                companionType: ActivityCompanionType(safeDecoding: identity.companionType)
            )
            ActivityDiagnosticLog.notice(.persistence, "Watch workout auto-saved session=\(sessionUUID.uuidString)")
            return saved
        } catch {
            ActivityDiagnosticLog.error(
                .persistence,
                "Watch workout auto-save failed error=\(ActivityDiagnosticLog.errorCategory(error))"
            )
            return nil
        }
    }

    func delete(_ activity: SavedActivity) async throws {
        if AuthStore.currentUserId != nil {
            let remoteID = activity.sync?.serverActivityId ?? activity.sync?.clientActivityId ?? activity.id.uuidString
            _ = try await api.deleteActivity(id: remoteID)
        }
        try await persistence.delete(activity)
        activityRevision += 1
        activities.removeAll { $0.id == activity.id }
    }

    func delete(_ activitiesToDelete: [SavedActivity]) async throws {
        for activity in activitiesToDelete {
            try await delete(activity)
        }
    }

    /// Render URL for a saved photo, routing through the photo cache so
    /// previously uploaded or downloaded photos render from a stable local
    /// cache file instead of a freshly signed remote URL.
    func imageURL(for photo: SavedPhoto) -> URL? {
        ActivityPhotoCache.shared.renderedURL(for: photo)
    }

    func activity(id: UUID) -> SavedActivity? {
        activities.first { $0.id == id }
    }

    func exportRoute(for activity: SavedActivity, format: RouteExportFormat) async throws -> URL {
        try await persistence.exportRoute(for: self.activity(id: activity.id) ?? activity, format: format)
    }

    func correctElevationIfNeeded(for activityID: UUID) async {
        guard AuthStore.currentUserId != nil,
              !elevationCorrectionIDs.contains(activityID),
              let activity = activity(id: activityID),
              activity.source.kind == .outbound,
              activity.indoor?.isIndoor != true,
              activity.route?.elevationMetadata == nil,
              let route = activity.route,
              route.points.count >= 2
        else { return }

        elevationCorrectionIDs.insert(activityID)
        defer { elevationCorrectionIDs.remove(activityID) }
        let startedAt = Date()
        let locations = route.points.map { point in
            CLLocation(
                coordinate: point.coordinate,
                altitude: point.altitude ?? 0,
                horizontalAccuracy: 10,
                verticalAccuracy: point.verticalAccuracy ?? 50,
                timestamp: point.timestamp
            )
        }
        let segmentStarts = Set(route.points.indices.filter { route.points[$0].startsNewSegment })
        let summary = ActivitySummary(
            startedAt: activity.startedAt,
            endedAt: activity.endedAt,
            durationSecs: activity.durationSecs,
            distanceM: activity.distanceM,
            avgPace: activity.avgPace,
            elevationGainM: activity.elevationGainM ?? 0,
            walkingStepCount: activity.walkingStepCount,
            healthMetrics: activity.healthMetrics,
            trackPoints: locations,
            trackSegmentStartIndices: segmentStarts
        )

        do {
            let corrected = try await TerrainElevationCorrector.correct(summary)
            guard let elevationMetadata = corrected.elevationMetadata else { return }
            let updated = SavedActivity(
                id: activity.id,
                activityType: activity.activityType,
                title: activity.title,
                guideNudge: activity.guideNudge,
                reflection: activity.reflection,
                createdAt: activity.createdAt,
                startedAt: activity.startedAt,
                endedAt: activity.endedAt,
                durationSecs: activity.durationSecs,
                distanceM: activity.distanceM,
                avgPace: activity.avgPace,
                elevationGainM: corrected.elevationGainM,
                walkingStepCount: activity.walkingStepCount,
                healthMetrics: activity.healthMetrics,
                goal: activity.goal,
                companionType: activity.companionType,
                source: activity.source,
                gear: activity.gear,
                manualEdits: activity.manualEdits,
                indoor: activity.indoor,
                cadence: activity.cadence,
                heartRateZones: activity.heartRateZones,
                recordingSession: activity.recordingSession,
                activityEventID: activity.activityEventID,
                followedRoute: activity.followedRoute,
                recognitionBadgeIDs: activity.recognitionBadgeIDs,
                route: SavedRoute(
                    points: SavedRoutePoint.simplified(from: corrected.trackSegments),
                    elevationMetadata: elevationMetadata
                ),
                photos: activity.photos,
                sync: SavedActivitySyncState(
                    clientActivityId: activity.sync?.clientActivityId ?? activity.id.uuidString,
                    serverActivityId: activity.sync?.serverActivityId,
                    lastAttemptAt: activity.sync?.lastAttemptAt,
                    syncedAt: nil,
                    lastError: nil,
                    localUpdatedAt: Date()
                )
            )
            try await persistence.replace(updated)
            activityRevision += 1
            if let index = activities.firstIndex(where: { $0.id == updated.id }) {
                activities[index] = updated
            }
            await analyticsManager?.track(.init(.activityElevationCorrectionCompleted, properties: [
                .result: .string("success"),
                .sourceType: .string("mapzen_backfill"),
                .latencyBucket: .string(ProductAnalyticsBucket.latency(milliseconds: Date().timeIntervalSince(startedAt) * 1_000))
            ]))
            Task { await syncActivityIfPossible(id: updated.id) }
        } catch {
            await analyticsManager?.track(.init(.activityElevationCorrectionCompleted, properties: [
                .result: .string("fallback"),
                .sourceType: .string("existing_on_device"),
                .latencyBucket: .string(ProductAnalyticsBucket.latency(milliseconds: Date().timeIntervalSince(startedAt) * 1_000)),
                .errorCategory: .string(syncErrorCategory(error))
            ]))
        }
    }

    func updateActivity(
        _ activity: SavedActivity,
        title: String,
        startedAt: Date,
        distanceM: Double,
        durationSecs: Int,
        gear: ActivityGearAttachment?
    ) async throws {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var editedFields: [String] = []
        if cleanedTitle != activity.title { editedFields.append("title") }
        if startedAt != activity.startedAt { editedFields.append("date") }
        if abs(distanceM - activity.distanceM) > 0.5 { editedFields.append("distance") }
        if durationSecs != activity.durationSecs { editedFields.append("duration") }
        if gear != activity.gear { editedFields.append("shoe") }

        let avgPace = distanceM > 0 && durationSecs > 0
            ? Double(durationSecs) / (distanceM / 1000)
            : nil

        let updated = SavedActivity(
            id: activity.id,
            activityType: activity.activityType,
            title: cleanedTitle.isEmpty ? activity.title : cleanedTitle,
            guideNudge: activity.guideNudge,
            reflection: activity.reflection,
            createdAt: activity.createdAt,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(TimeInterval(durationSecs)),
            durationSecs: max(1, durationSecs),
            distanceM: max(0, distanceM),
            avgPace: avgPace,
            elevationGainM: activity.elevationGainM,
            walkingStepCount: activity.walkingStepCount,
            healthMetrics: activity.healthMetrics,
            goal: activity.goal,
            companionType: activity.companionType,
            source: editedFields.isEmpty ? activity.source : ActivitySourceMetadata(
                kind: activity.source.kind == .manual ? .manual : activity.source.kind,
                displayName: activity.source.displayName,
                deviceName: activity.source.deviceName,
                externalID: activity.source.externalID,
                importedAt: activity.source.importedAt
            ),
            gear: gear,
            manualEdits: editedFields.isEmpty ? activity.manualEdits : ActivityManualEdits(
                editedAt: Date(),
                editedFields: Array(Set((activity.manualEdits?.editedFields ?? []) + editedFields)).sorted()
            ),
            indoor: activity.indoor,
            cadence: activity.cadence,
            heartRateZones: activity.heartRateZones,
            recordingSession: activity.recordingSession,
            activityEventID: activity.activityEventID,
            followedRoute: activity.followedRoute,
            recognitionBadgeIDs: activity.recognitionBadgeIDs,
            route: activity.route,
            photos: activity.photos,
            sync: SavedActivitySyncState(
                clientActivityId: activity.sync?.clientActivityId ?? activity.id.uuidString,
                serverActivityId: activity.sync?.serverActivityId,
                lastAttemptAt: activity.sync?.lastAttemptAt,
                syncedAt: nil,
                lastError: nil,
                localUpdatedAt: Date()
            )
        )

        try await persistence.replace(updated)
        activityRevision += 1
        if let index = activities.firstIndex(where: { $0.id == updated.id }) {
            activities[index] = updated
            sortActivitiesByStartTime()
        }
    }

    func updatePhotos(
        for activity: SavedActivity,
        keeping photos: [SavedPhoto],
        adding captures: [(UIImage, PhotoMetadata)]
    ) async throws {
        let current = self.activity(id: activity.id) ?? activity
        let keptIDs = Set(photos.map(\.id))
        for removed in current.photos where !keptIDs.contains(removed.id) {
            if let remotePhotoID = removed.remotePhotoId {
                try await api.deleteActivityPhoto(id: remotePhotoID)
            }
        }
        let updated = try await persistence.updatePhotos(for: current, keeping: photos, adding: captures)
        activityRevision += 1
        if let index = activities.firstIndex(where: { $0.id == updated.id }) {
            activities[index] = updated
        }
        Task { await syncActivityIfPossible(id: updated.id) }
    }

    func syncPendingActivitiesIfNeeded() async {
        guard AuthStore.currentUserId != nil else { return }
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        ActivityDiagnosticLog.notice(
            .sync,
            "Activity sync pass started pending=\(ActivityDiagnosticLog.countBucket(pendingActivityCount))"
        )
        await loadActivities()
        await pullRemoteActivities()
        let pendingIDs = activities
            .filter { !($0.sync?.isSynced ?? false) }
            .map(\.id)

        for activityID in pendingIDs {
            await syncActivityIfPossible(id: activityID)
        }
        for activity in activities where activity.sync?.serverActivityId != nil {
            await syncPhotosIfPossible(activityID: activity.id)
        }
        ActivityDiagnosticLog.notice(
            .sync,
            "Activity sync pass completed pending=\(ActivityDiagnosticLog.countBucket(pendingActivityCount)) failed=\(ActivityDiagnosticLog.countBucket(failedActivityCount))"
        )
    }

    private func loadActivities() async {
        defer { hasLoadedActivities = true }
        if ProcessInfo.processInfo.arguments.contains("-OutboundUITestSeedData")
            || ProcessInfo.processInfo.arguments.contains("-OutboundUITestSeedSavedActivity")
        {
            activities = Self.uiTestActivityFixtures.sortedByStartTimeDescending()
            return
        }
        let revisionAtStart = activityRevision
        do {
            let loadedActivities = try await persistence.load()
            guard activityRevision == revisionAtStart else {
                ActivityDiagnosticLog.notice(.persistence, "Local activity load ignored because in-memory history changed")
                return
            }
            activities = loadedActivities.sortedByStartTimeDescending()
            ActivityDiagnosticLog.notice(
                .persistence,
                "Local activity load completed history_count=\(ActivityDiagnosticLog.countBucket(activities.count))"
            )
        } catch {
            ActivityDiagnosticLog.error(
                .persistence,
                "Local activity load failed error=\(ActivityDiagnosticLog.errorCategory(error))"
            )
        }
    }

    private func syncActivityIfPossible(id: UUID) async {
        guard AuthStore.currentUserId != nil else { return }
        guard let activity = activity(id: id) else { return }

        let priorState = activity.sync ?? SavedActivitySyncState(
            clientActivityId: activity.id.uuidString,
            serverActivityId: nil,
            lastAttemptAt: nil,
            syncedAt: nil,
            lastError: nil,
            localUpdatedAt: activity.createdAt
        )

        let attemptState = SavedActivitySyncState(
            clientActivityId: priorState.clientActivityId,
            serverActivityId: priorState.serverActivityId,
            lastAttemptAt: Date(),
            syncedAt: priorState.syncedAt,
            lastError: nil,
            localUpdatedAt: priorState.localUpdatedAt ?? activity.createdAt
        )
        await persistSyncState(attemptState, for: activity.id)
        ActivityDiagnosticLog.notice(
            .sync,
            "Activity upload started source=\(activity.source.kind.rawValue) existing_remote=\(priorState.serverActivityId != nil) route_included=\(uploadableRoute(for: activity) != nil) photos=\(ActivityDiagnosticLog.countBucket(activity.photos.count))"
        )

        do {
            let response = try await api.uploadActivity(
                ActivityUploadRequest(
                    clientActivityId: priorState.clientActivityId,
                    syncSource: "ios-local-store",
                    type: activity.activityType.rawValue,
                    title: activity.title,
                    startedAt: activity.startedAt,
                    endedAt: activity.endedAt,
                    durationSecs: activity.durationSecs,
                    distanceM: activity.distanceM,
                    elevationM: activity.elevationGainM,
                    avgPace: activity.avgPace,
                    avgHeartRate: activity.healthMetrics?.averageHeartRateBPM,
                    energyKilocalories: activity.energyKilocalories,
                    companionType: activity.companionType?.rawValue,
                    activityEventId: activity.activityEventID,
                    followedRouteId: activity.followedRoute?.source == .community ? activity.followedRoute?.routeID : nil,
                    followedRouteCompleted: activity.followedRoute?.source == .community ? activity.followedRoute?.arrived : nil,
                    route: uploadableRoute(for: activity),
                    reflection: activity.reflection,
                    clientData: syncSnapshot(for: activity),
                    clientUpdatedAt: attemptState.localUpdatedAt ?? activity.createdAt,
                    recognitionContext: RecognitionContextDTO(
                        timeZoneIdentifier: TimeZone.current.identifier,
                        firstWeekday: Calendar.current.firstWeekday
                    )
                )
            )

            let syncedState = SavedActivitySyncState(
                clientActivityId: priorState.clientActivityId,
                serverActivityId: response.id,
                lastAttemptAt: attemptState.lastAttemptAt,
                syncedAt: response.serverUpdatedAt,
                lastError: nil,
                localUpdatedAt: attemptState.localUpdatedAt
            )
            await persistSyncState(syncedState, for: activity.id)
            await analyticsManager?.track(ProductAnalyticsEvent(
                .activitySyncCompleted,
                properties: syncAnalyticsProperties(for: activity)
            ))
            if let contributions = response.circleContributions, !contributions.isEmpty {
                CircleContributionCenter.shared.publish(contributions)
                for contribution in contributions {
                    await analyticsManager?.track(.init(.circleActivityContributionReconciled, properties: [
                        .selectionType: .string(contribution.focusMode),
                        .participantCountBucket: .string(ProductAnalyticsBucket.count(contribution.memberCount)),
                        .result: .string(contribution.completed ? "completed" : "contributed")
                    ]))
                }
            }
            ActivityDiagnosticLog.notice(
                .sync,
                "Activity upload completed source=\(activity.source.kind.rawValue) route_included=\(uploadableRoute(for: activity) != nil)"
            )
            await syncPhotosIfPossible(activityID: activity.id)
        } catch {
            let failedState = SavedActivitySyncState(
                clientActivityId: priorState.clientActivityId,
                serverActivityId: priorState.serverActivityId,
                lastAttemptAt: attemptState.lastAttemptAt,
                syncedAt: priorState.syncedAt,
                lastError: error.localizedDescription,
                localUpdatedAt: priorState.localUpdatedAt ?? activity.createdAt
            )
            await persistSyncState(failedState, for: activity.id)
            var properties = syncAnalyticsProperties(for: activity)
            properties[.errorCategory] = .string(syncErrorCategory(error))
            await analyticsManager?.track(ProductAnalyticsEvent(.activitySyncFailed, properties: properties))
            ActivityDiagnosticLog.error(
                .sync,
                "Activity upload failed source=\(activity.source.kind.rawValue) route_included=\(uploadableRoute(for: activity) != nil) error=\(ActivityDiagnosticLog.errorCategory(error))"
            )
        }
    }

    private func uploadableRoute(for activity: SavedActivity) -> SavedRoute? {
        guard let route = activity.route, route.points.count >= 2 else { return nil }
        return route
    }

    private func syncAnalyticsProperties(for activity: SavedActivity) -> [ProductPropertyKey: AnalyticsValue] {
        [
            .sourceType: .string(activity.source.kind.rawValue),
            .routeSelected: .boolean(uploadableRoute(for: activity) != nil)
        ]
    }

    private func syncErrorCategory(_ error: Error) -> String {
        if case let APIError.http(statusCode, _, _) = error {
            return "http_\(statusCode)"
        }
        if error is DecodingError { return "decoding" }
        if let urlError = error as? URLError {
            return urlError.code == .notConnectedToInternet ? "offline" : "network"
        }
        return "unknown"
    }

    private func persistSyncState(_ syncState: SavedActivitySyncState, for activityID: UUID) async {
        guard let current = activity(id: activityID) else { return }
        let updated = SavedActivity(
            id: current.id,
            activityType: current.activityType,
            title: current.title,
            guideNudge: current.guideNudge,
            reflection: current.reflection,
            createdAt: current.createdAt,
            startedAt: current.startedAt,
            endedAt: current.endedAt,
            durationSecs: current.durationSecs,
            distanceM: current.distanceM,
            avgPace: current.avgPace,
            elevationGainM: current.elevationGainM,
            walkingStepCount: current.walkingStepCount,
            healthMetrics: current.healthMetrics,
            goal: current.goal,
            companionType: current.companionType,
            source: current.source,
            gear: current.gear,
            manualEdits: current.manualEdits,
            indoor: current.indoor,
            cadence: current.cadence,
            heartRateZones: current.heartRateZones,
            recordingSession: current.recordingSession,
            activityEventID: current.activityEventID,
            followedRoute: current.followedRoute,
            recognitionBadgeIDs: current.recognitionBadgeIDs,
            route: current.route,
            photos: current.photos,
            sync: syncState
        )
        do {
            try await persistence.replace(updated)
        } catch {
            ActivityDiagnosticLog.error(
                .persistence,
                "Sync-state persistence failed error=\(ActivityDiagnosticLog.errorCategory(error))"
            )
            return
        }
        activityRevision += 1
        if let index = activities.firstIndex(where: { $0.id == updated.id }) {
            activities[index] = updated
        }
    }

    private func pullRemoteActivities() async {
        do {
            var offset = 0
            var hasMore = true
            var remoteCount = 0
            var restoredCount = 0
            var deletedCount = 0
            while hasMore {
                let response = try await api.fetchActivities(offset: offset)
                for remote in response.activities {
                remoteCount += 1
                guard let clientID = remote.clientActivityId,
                      let activityID = UUID(uuidString: clientID) else { continue }

                if remote.deletedAt != nil {
                    if let local = activity(id: activityID) {
                        try? await persistence.delete(local)
                        activities.removeAll { $0.id == activityID }
                        activityRevision += 1
                        deletedCount += 1
                    }
                    continue
                }

                guard let snapshot = remote.clientData else { continue }
                let local = activity(id: activityID)
                if let local, remote.clientUpdatedAt == nil {
                    let upgradeState = SavedActivitySyncState(
                        clientActivityId: clientID,
                        serverActivityId: remote.id,
                        lastAttemptAt: local.sync?.lastAttemptAt,
                        syncedAt: nil,
                        lastError: nil,
                        localUpdatedAt: local.sync?.localUpdatedAt ?? local.createdAt
                    )
                    await persistSyncState(upgradeState, for: activityID)
                    continue
                }
                let localUpdatedAt = local?.sync?.localUpdatedAt ?? local?.createdAt
                if local?.sync?.isSynced == false,
                   let localUpdatedAt,
                   let remoteClientUpdatedAt = remote.clientUpdatedAt,
                   localUpdatedAt > remoteClientUpdatedAt {
                    continue
                }

                let synced = SavedActivitySyncState(
                    clientActivityId: clientID,
                    serverActivityId: remote.id,
                    lastAttemptAt: local?.sync?.lastAttemptAt,
                    syncedAt: remote.updatedAt,
                    lastError: nil,
                    localUpdatedAt: remote.clientUpdatedAt ?? remote.updatedAt
                )
                let restored = copy(
                    snapshot,
                    photos: local?.photos ?? [],
                    sync: synced,
                    preservedFollowedRoute: local?.followedRoute
                )
                try await persistence.replaceOrInsert(restored)
                if let index = activities.firstIndex(where: { $0.id == activityID }) {
                    activities[index] = restored
                } else {
                    activities.append(restored)
                }
                restoredCount += 1
                await restoreRemotePhotos(remote.photos ?? [], activityID: activityID)
                }
                offset += response.activities.count
                hasMore = response.hasMore && !response.activities.isEmpty
            }
            sortActivitiesByStartTime()
            ActivityDiagnosticLog.notice(
                .sync,
                "Activity restore completed received=\(ActivityDiagnosticLog.countBucket(remoteCount)) restored=\(ActivityDiagnosticLog.countBucket(restoredCount)) deleted=\(ActivityDiagnosticLog.countBucket(deletedCount))"
            )
        } catch {
            ActivityDiagnosticLog.error(
                .sync,
                "Activity restore failed error=\(ActivityDiagnosticLog.errorCategory(error))"
            )
        }
    }

    private func sortActivitiesByStartTime() {
        activities = activities.sortedByStartTimeDescending()
    }

    private func syncPhotosIfPossible(activityID: UUID) async {
        guard let activity = activity(id: activityID),
              let serverActivityID = activity.sync?.serverActivityId else { return }
        let pendingPhotos = activity.photos.filter { $0.remotePhotoId == nil }
        guard !pendingPhotos.isEmpty else { return }
        ActivityDiagnosticLog.notice(
            .sync,
            "Photo upload started pending=\(ActivityDiagnosticLog.countBucket(pendingPhotos.count))"
        )
        var uploadedCount = 0
        var failedCount = 0
        for photo in pendingPhotos {
            do {
                let data = try await persistence.uploadData(for: photo)
                let remote = try await api.uploadActivityPhoto(
                    ActivityPhotoUploadRequest(
                        activityId: serverActivityID,
                        clientPhotoId: photo.id.uuidString,
                        base64: data.base64EncodedString(),
                        takenAt: photo.takenAt,
                        paceAtShot: photo.paceAtShot,
                        hrAtShot: photo.hrAtShot,
                        distAtShot: photo.distAtShot,
                        latitude: photo.coordinate?.latitude,
                        longitude: photo.coordinate?.longitude,
                        captureContext: photo.captureContext.rawValue
                    )
                )
                await markPhotoUploaded(photo.id, remote: remote, activityID: activityID)
                ActivityPhotoCache.shared.rememberUploadedPhoto(
                    photo,
                    savedAt: ActivityPersistence.imageURL(for: photo)
                )
                uploadedCount += 1
            } catch {
                failedCount += 1
                ActivityDiagnosticLog.error(
                    .sync,
                    "Photo upload failed error=\(ActivityDiagnosticLog.errorCategory(error))"
                )
            }
        }
        ActivityDiagnosticLog.notice(
            .sync,
            "Photo upload completed uploaded=\(ActivityDiagnosticLog.countBucket(uploadedCount)) failed=\(ActivityDiagnosticLog.countBucket(failedCount))"
        )
    }

    private func restoreRemotePhotos(_ remotePhotos: [RemoteActivityPhoto], activityID: UUID) async {
        guard var current = activity(id: activityID) else { return }
        var photos = current.photos
        var changed = false
        for remote in remotePhotos {
            if let index = photos.firstIndex(where: { $0.id.uuidString.caseInsensitiveCompare(remote.clientPhotoId) == .orderedSame }) {
                let local = photos[index]
                if local.remotePhotoId != remote.id {
                    photos[index] = copy(local, remotePhotoId: remote.id, remoteUploadedAt: remote.updatedAt)
                    changed = true
                }
                continue
            }
            do {
                let data = try await api.downloadActivityPhoto(id: remote.id)
                photos.append(try await persistence.saveDownloadedPhoto(data, remote: remote, activityID: activityID))
                changed = true
            } catch {
                ActivityDiagnosticLog.error(
                    .sync,
                    "Photo restore failed error=\(ActivityDiagnosticLog.errorCategory(error))"
                )
            }
        }
        guard changed else { return }
        photos.sort { $0.takenAt < $1.takenAt }
        current = copy(current, photos: photos, sync: current.sync)
        try? await persistence.replace(current)
        activityRevision += 1
        if let index = activities.firstIndex(where: { $0.id == activityID }) { activities[index] = current }
    }

    private func markPhotoUploaded(_ photoID: UUID, remote: RemoteActivityPhoto, activityID: UUID) async {
        guard let current = activity(id: activityID) else { return }
        let photos = current.photos.map { photo in
            photo.id == photoID
                ? copy(photo, remotePhotoId: remote.id, remoteUploadedAt: remote.updatedAt)
                : photo
        }
        let updated = copy(current, photos: photos, sync: current.sync)
        guard (try? await persistence.replace(updated)) != nil else { return }
        activityRevision += 1
        if let index = activities.firstIndex(where: { $0.id == activityID }) { activities[index] = updated }
    }

    private func copy(_ photo: SavedPhoto, remotePhotoId: String?, remoteUploadedAt: Date?) -> SavedPhoto {
        SavedPhoto(
            id: photo.id,
            takenAt: photo.takenAt,
            paceAtShot: photo.paceAtShot,
            hrAtShot: photo.hrAtShot,
            distAtShot: photo.distAtShot,
            coordinate: photo.coordinate,
            captureContext: photo.captureContext,
            relativePath: photo.relativePath,
            remotePhotoId: remotePhotoId,
            remoteUploadedAt: remoteUploadedAt
        )
    }

    private func syncSnapshot(for activity: SavedActivity) -> SavedActivity {
        copy(activity, photos: [], sync: nil, stripImportedFollowedRoute: true)
    }

    private func copy(
        _ activity: SavedActivity,
        photos: [SavedPhoto],
        sync: SavedActivitySyncState?,
        stripImportedFollowedRoute: Bool = false,
        preservedFollowedRoute: FollowedRouteMetadata? = nil
    ) -> SavedActivity {
        let followedRoute = activity.followedRoute ?? preservedFollowedRoute
        return SavedActivity(
            id: activity.id,
            activityType: activity.activityType,
            title: activity.title,
            guideNudge: activity.guideNudge,
            reflection: activity.reflection,
            createdAt: activity.createdAt,
            startedAt: activity.startedAt,
            endedAt: activity.endedAt,
            durationSecs: activity.durationSecs,
            distanceM: activity.distanceM,
            avgPace: activity.avgPace,
            elevationGainM: activity.elevationGainM,
            walkingStepCount: activity.walkingStepCount,
            healthMetrics: activity.healthMetrics,
            goal: activity.goal,
            companionType: activity.companionType,
            source: activity.source,
            gear: activity.gear,
            manualEdits: activity.manualEdits,
            indoor: activity.indoor,
            cadence: activity.cadence,
            heartRateZones: activity.heartRateZones,
            recordingSession: activity.recordingSession,
            activityEventID: activity.activityEventID,
            followedRoute: stripImportedFollowedRoute && followedRoute?.source == .imported
                ? nil
                : followedRoute,
            recognitionBadgeIDs: activity.recognitionBadgeIDs,
            route: activity.route,
            photos: photos,
            sync: sync
        )
    }

    private func autoTitle(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let day = date.formatted(.dateTime.weekday(.wide))
        switch hour {
        case 5..<10:  return "\(day) Morning Run"
        case 10..<13: return "\(day) Midday Run"
        case 13..<17: return "\(day) Afternoon Run"
        case 17..<21: return "\(day) Evening Run"
        default:      return "\(day) Night Run"
        }
    }

    private func exportPhotosToAlbumIfNeeded(_ activity: SavedActivity) async {
        let outcome = await ActivityPhotoAlbumExporter.shared.exportPhotos(from: activity)
        let result: String
        switch outcome {
        case .skipped, .alreadySaved:
            return
        case .saved:
            result = "success"
            photoAlbumNotice = ActivityPhotoAlbumNotice(
                message: String(
                    localized: "app.photo.album.saved",
                    defaultValue: "Photos saved to the Plainstride album"
                ),
                isError: false
            )
        case .permissionDenied:
            result = "permission_denied"
            photoAlbumNotice = ActivityPhotoAlbumNotice(
                message: String(
                    localized: "app.photo.album.permission.denied",
                    defaultValue: "Allow Photos access in Settings to save activity photos"
                ),
                isError: true
            )
        case .failed:
            result = "failure"
            photoAlbumNotice = ActivityPhotoAlbumNotice(
                message: String(
                    localized: "app.photo.album.save.failed",
                    defaultValue: "Activity saved, but photos couldn’t be added to the album"
                ),
                isError: true
            )
        }
        await analyticsManager?.track(.init(.photoAlbumExportCompleted, properties: [
            .result: .string(result),
            .sourceType: .string("automatic"),
            .countBucket: .string(ProductAnalyticsBucket.count(activity.photos.count))
        ]))
    }

    private static var uiTestActivityFixtures: [SavedActivity] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return [
            uiTestActivityFixture(
                id: "11111111-2222-3333-4444-555555555555",
                title: "Golden Gate Easy Run",
                startedAt: calendar.date(byAdding: .hour, value: 7, to: today) ?? today,
                durationSecs: 1_845,
                distanceM: 5_420,
                avgPace: 340,
                elevationGainM: 74,
                serverActivityID: "ui-test-server-activity"
            ),
            uiTestActivityFixture(
                id: "22222222-3333-4444-5555-666666666666",
                title: "Tuesday Tempo Session",
                startedAt: calendar.date(byAdding: .day, value: -2, to: today) ?? today,
                durationSecs: 2_280,
                distanceM: 7_100,
                avgPace: 321,
                elevationGainM: 41
            ),
            uiTestActivityFixture(
                id: "33333333-4444-5555-6666-777777777777",
                title: "Saturday Long Run",
                startedAt: calendar.date(byAdding: .day, value: -5, to: today) ?? today,
                durationSecs: 4_260,
                distanceM: 12_300,
                avgPace: 346,
                elevationGainM: 128
            ),
        ]
    }

    private static func uiTestActivityFixture(
        id: String,
        title: String,
        startedAt: Date,
        durationSecs: Int,
        distanceM: Double,
        avgPace: Double,
        elevationGainM: Double,
        serverActivityID: String? = nil,
        includeCompanion: Bool = false
    ) -> SavedActivity {
        let points = [
            SavedRoutePoint(location: CLLocation(latitude: 37.7749, longitude: -122.4194)),
            SavedRoutePoint(location: CLLocation(latitude: 37.7758, longitude: -122.4179)),
            SavedRoutePoint(location: CLLocation(latitude: 37.7767, longitude: -122.4163))
        ]

        return SavedActivity(
            id: UUID(uuidString: id) ?? UUID(),
            title: title,
            guideNudge: "Keep your cadence steady.",
            reflection: nil,
            createdAt: startedAt,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(TimeInterval(durationSecs)),
            durationSecs: durationSecs,
            distanceM: distanceM,
            avgPace: avgPace,
            elevationGainM: elevationGainM,
            healthMetrics: ActivityHealthMetrics(
                averageHeartRateBPM: 146,
                maxHeartRateBPM: 162,
                heartRateSampleCount: 12
            ),
            goal: .distanceMeters(5_000),
            companionType: includeCompanion ? .dog : nil,
            route: SavedRoute(points: points),
            photos: [],
            sync: serverActivityID.map {
                SavedActivitySyncState(
                    clientActivityId: id,
                    serverActivityId: $0,
                    lastAttemptAt: startedAt,
                    syncedAt: startedAt,
                    lastError: nil,
                    localUpdatedAt: startedAt
                )
            }
        )
    }
}

private extension Array where Element == SavedActivity {
    func sortedByStartTimeDescending() -> [SavedActivity] {
        sorted {
            if $0.startedAt == $1.startedAt {
                return $0.createdAt > $1.createdAt
            }
            return $0.startedAt > $1.startedAt
        }
    }
}

private extension ActivityType {
    var healthImportTitle: String {
        switch self {
        case .running: String(localized: "health.import.title.run", defaultValue: "Imported Run")
        case .cycling: String(localized: "health.import.title.ride", defaultValue: "Imported Ride")
        case .hiking: String(localized: "health.import.title.hike", defaultValue: "Imported Hike")
        case .walking: String(localized: "health.import.title.walk", defaultValue: "Imported Walk")
        case .swimming: String(localized: "health.import.title.swim", defaultValue: "Imported Swim")
        case .strengthTraining: String(localized: "health.import.title.strength", defaultValue: "Imported Strength Workout")
        case .mobility: String(localized: "health.import.title.mobility", defaultValue: "Imported Mobility Workout")
        }
    }
}
