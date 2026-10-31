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
    @Published private(set) var hasMoreRemoteActivities = true
    private var remoteHistoryTask: Task<Bool, Never>?
    private var remoteHistoryCursor: String?
    private var remoteHistoryOffset = 0
    private var invalidatedRoutes: Set<UUID> = []
    private var resolvedRouteVersions: Set<String> = []
    private var detailRefreshIDs: Set<UUID> = []
    private var isRestoringPhotos = false
    private var pendingRemotePhotos: [UUID: [RemoteActivityPhoto]] = [:]
    @Published private(set) var accountStatistics: AccountStatisticsSnapshot?
    @Published private(set) var statisticsAreCached = true
    @Published private(set) var statisticsIsLoading = false
    private var statisticsAccountKey: String?
    private var statisticsRequestsInFlight: Set<String> = []
    private var knownRemoteImportIDs: [String: Set<String>] = [:]
    private var importIdentityAccountID: String?
    private let api = APIClient.shared
    private let persistence = ActivityPersistence.shared
    private let analyticsManager: AnalyticsManager?
    private var activityRevision = 0
    private var elevationCorrectionIDs = Set<UUID>()
    private var healthImportInFlight = false
    private var healthRouteRefreshInFlight = false
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
        guard !healthImportInFlight else { return [] }
        healthImportInFlight = true
        defer { healthImportInFlight = false }
        if !hasLoadedActivities { await loadActivities() }
        ActivityDiagnosticLog.notice(
            .healthKit,
            "Health import persistence started candidates=\(ActivityDiagnosticLog.countBucket(workouts.count))"
        )
        _ = await checkRemoteImportIdentities(workouts.map(\.id), sourceKind: "appleHealth")
        var canReconcileRemoteSessions = true
        if AuthStore.currentUserId != nil {
            do {
                let sessionIDs = workouts.compactMap { $0.plainstrideSessionUUID?.uuidString }
                let serverIDs = try await api.ownedSessionActivities(sessionIDs)
                for start in stride(from: 0, to: serverIDs.count, by: 200) {
                    let response = try await api.fetchActivities(ids: Array(serverIDs[start..<min(start + 200, serverIDs.count)]), includeRoute: false)
                    _ = try await applyRemoteActivities(response.activities, preserveCachedRoutes: true)
                }
            } catch {
                ActivityDiagnosticLog.error(.sync, "Health session identity check failed error=\(ActivityDiagnosticLog.errorCategory(error))")
                canReconcileRemoteSessions = false
            }
        }
        var importedIDs: Set<String> = []
        for workout in workouts where !importedHealthExternalIDs.contains(workout.id) {
            // Only an exact Plainstride session UUID proves these are the same
            // workout. External Apple workouts use the normal import flow.
            let matches = activities.filter { activity in
                guard let uuid = workout.plainstrideSessionUUID else { return false }
                return activity.recordingSession?.sessionUUID == uuid
            }
            if matches.count == 1, let uuid = matches.first?.recordingSession?.sessionUUID {
                await attachHealthKitWorkoutReference(sessionUUID: uuid, externalReference: workout.id)
                if importedHealthExternalIDs.contains(workout.id) {
                    await reconcileHealthDetails(id: workout.id, energy: workout.energyBurnedKilocalories.map { Int($0.rounded()) })
                    importedIDs.insert(workout.id)
                }
                continue
            }
            // An owned session absent from the cache needs an exact server match before import.
            // External workouts without a Plainstride session UUID can still be imported offline.
            if workout.plainstrideSessionUUID != nil && !canReconcileRemoteSessions { continue }
            let details: HealthWorkoutDetails
            do { details = try await HealthKitService().workoutDetails(id: workout.id) }
            catch {
                ActivityDiagnosticLog.error(.healthKit, "Health workout details failed error=\(ActivityDiagnosticLog.errorCategory(error))")
                // Keep the candidate retryable; do not persist a silently incomplete import.
                continue
            }
            let distance = max(0, workout.distanceMeters ?? 0)
            let duration = max(1, workout.durationSeconds)
            let summary = ActivitySummary(
                startedAt: workout.startedAt,
                endedAt: workout.endedAt,
                durationSecs: duration,
                distanceM: distance,
                avgPace: workout.activityType.plausibleAveragePace(
                    durationSeconds: Double(duration),
                    distanceMeters: distance
                ),
                healthMetrics: details.health,
                sessionMetadata: workout.plainstrideSessionUUID.map {
                    ActivityRecordingSessionMetadata(sessionUUID: $0, origin: .appleWatch,
                        recordingDevice: .appleWatch, healthKitOwnership: .appleWatchPrimary,
                        healthKitWorkoutExternalReference: workout.id)
                },
                trackPoints: details.locations,
                trackSegmentStartIndices: details.segmentStarts
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
                    ),
                    recordingSession: summary.sessionMetadata
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

    private func markHealthUpdatePending(_ activity: SavedActivity) -> SavedActivity {
        copy(activity, photos: activity.photos, sync: SavedActivitySyncState(
            clientActivityId: activity.sync?.clientActivityId ?? activity.id.uuidString,
            serverActivityId: activity.sync?.serverActivityId, lastAttemptAt: activity.sync?.lastAttemptAt,
            syncedAt: nil, lastError: nil, localUpdatedAt: Date()))
    }

    private func reconcileHealthDetails(id: String, energy: Int?) async {
        do {
            let details = try await HealthKitService().workoutDetails(id: id)
            guard let index = activities.firstIndex(where: { $0.recordingSession?.healthKitWorkoutExternalReference == id }) else { return }
            let changed = activities[index].withImportedHealth(health: details.health, energy: energy,
                route: details.route, distance: details.distanceMeters)
            let updated = markHealthUpdatePending(changed)
            try await persistence.replace(updated)
            activities[index] = updated
            activityRevision += 1
            Task { await syncActivityIfPossible(id: updated.id) }
        } catch {
            ActivityDiagnosticLog.error(.healthKit, "Linked Health metrics reconciliation failed error=\(ActivityDiagnosticLog.errorCategory(error))")
        }
    }

    /// Health routes may sync after their workout. Revisit recent linked records
    /// without a route; UUID ownership prevents creating a second activity.
    func refreshPendingHealthRoutes() async {
        guard !healthRouteRefreshInFlight else { return }
        healthRouteRefreshInFlight = true
        defer { healthRouteRefreshInFlight = false }
        let cutoff = Date().addingTimeInterval(-8 * 7 * 24 * 60 * 60)
        let pending = activities.filter {
            $0.startedAt > cutoff && ($0.routePoints.isEmpty || $0.healthMetrics?.hasHeartRateData != true ||
                $0.recordingSession?.healthKitOwnership == .appleWatchPrimary) &&
                ($0.source.kind == .appleHealth || $0.recordingSession?.healthKitWorkoutExternalReference != nil)
        }
        for activity in pending {
            guard let id = activity.recordingSession?.healthKitWorkoutExternalReference ?? activity.source.externalID else { continue }
            do {
                let details = try await HealthKitService().workoutDetails(id: id)
                guard let index = activities.firstIndex(where: { $0.id == activity.id }) else { continue }
                let changed = activities[index].withImportedHealth(health: details.health, energy: nil,
                    route: details.route, distance: details.distanceMeters)
                guard changed.route != activities[index].route || changed.healthMetrics != activities[index].healthMetrics else { continue }
                let updated = markHealthUpdatePending(changed)
                try await persistence.replace(updated)
                activities[index] = updated
                activityRevision += 1
                Task { await syncActivityIfPossible(id: updated.id) }
            } catch {
                ActivityDiagnosticLog.error(.healthKit, "Delayed Health route reconciliation failed error=\(ActivityDiagnosticLog.errorCategory(error))")
            }
        }
    }

    // MARK: - Strava export import

    /// Saves runner-confirmed activities read from a Strava data export.
    ///
    /// Imported activities keep their vendor identifier in `source.externalID`, so re-importing the
    /// same export never duplicates history. They are saved as ordinary local activities and then
    /// synchronized like any other, but they are never treated as a just-recorded session.
    func importStravaActivities(_ candidates: [StravaImportCandidate]) async -> StravaImportOutcome {
        ActivityDiagnosticLog.notice(
            .persistence,
            "Strava import persistence started candidates=\(ActivityDiagnosticLog.countBucket(candidates.count))"
        )
        var importedIDs: Set<String> = []
        var failedIDs: Set<String> = []
        _ = await checkRemoteImportIdentities(candidates.map(\.externalID), sourceKind: "strava")
        var knownExternalIDs = (knownRemoteImportIDs["strava"] ?? []).union(activities.compactMap { $0.source.kind == .strava ? $0.source.externalID : nil })

        for candidate in candidates {
            guard !knownExternalIDs.contains(candidate.externalID) else {
                failedIDs.insert(candidate.externalID)
                continue
            }
            knownExternalIDs.insert(candidate.externalID)

            let activityType = candidate.sport.activityType
            let duration = max(1, candidate.durationSeconds)
            let distance = max(0, candidate.distanceMeters ?? 0)
            let endedAt = candidate.startedAt.addingTimeInterval(TimeInterval(duration))
            let locations = Self.importedLocations(for: candidate)
            let summary = ActivitySummary(
                startedAt: candidate.startedAt,
                endedAt: endedAt,
                durationSecs: duration,
                distanceM: distance,
                avgPace: activityType.plausibleAveragePace(
                    durationSeconds: Double(duration),
                    distanceMeters: distance
                ),
                elevationGainM: candidate.elevationGainMeters ?? 0,
                healthMetrics: Self.importedHeartRateMetrics(for: candidate),
                trackPoints: locations.points,
                trackSegmentStartIndices: locations.segmentStarts
            )

            do {
                _ = try await save(
                    summary: summary,
                    photos: [],
                    activityType: activityType,
                    reflection: nil,
                    title: candidate.resolvedTitle(for: activityType),
                    source: ActivitySourceMetadata(
                        kind: .strava,
                        displayName: Self.stravaSourceDisplayName,
                        deviceName: nil,
                        externalID: candidate.externalID,
                        importedAt: Date()
                    )
                )
                importedIDs.insert(candidate.externalID)
            } catch {
                failedIDs.insert(candidate.externalID)
                ActivityDiagnosticLog.error(
                    .persistence,
                    "Strava import persistence failed error=\(ActivityDiagnosticLog.errorCategory(error))"
                )
                continue
            }
        }

        ActivityDiagnosticLog.notice(
            .persistence,
            "Strava import persistence completed imported=\(ActivityDiagnosticLog.countBucket(importedIDs.count)) failed=\(ActivityDiagnosticLog.countBucket(failedIDs.count))"
        )
        return StravaImportOutcome(importedIDs: importedIDs, failedIDs: failedIDs)
    }

    /// External identifiers already present locally, used to exclude known duplicates from review.
    var importedStravaExternalIDs: Set<String> {
        (knownRemoteImportIDs["strava"] ?? []).union(activities.compactMap { $0.source.kind == .strava ? $0.source.externalID : nil })
    }

    private static let stravaSourceDisplayName = "Strava"

    private static func importedHeartRateMetrics(for candidate: StravaImportCandidate) -> ActivityHealthMetrics? {
        guard candidate.averageHeartRateBPM != nil || candidate.maxHeartRateBPM != nil else { return nil }
        return ActivityHealthMetrics(
            averageHeartRateBPM: candidate.averageHeartRateBPM,
            maxHeartRateBPM: candidate.maxHeartRateBPM,
            heartRateSampleCount: 0
        )
    }

    /// Rebuilds `CLLocation` samples from parsed file points. Points without a timestamp are spread
    /// evenly across the activity so the recorded route keeps a usable time axis.
    private static func importedLocations(
        for candidate: StravaImportCandidate
    ) -> (points: [CLLocation], segmentStarts: Set<Int>) {
        guard candidate.routePoints.count > 1 else { return ([], []) }
        var points: [CLLocation] = []
        points.reserveCapacity(candidate.routePoints.count)
        var segmentStarts: Set<Int> = []
        let total = candidate.routePoints.count
        let duration = Double(max(1, candidate.durationSeconds))

        for (index, point) in candidate.routePoints.enumerated() {
            guard CLLocationCoordinate2DIsValid(
                CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
            ) else { continue }
            if point.startsNewSegment, !points.isEmpty { segmentStarts.insert(points.count) }
            let timestamp = point.timestamp
                ?? candidate.startedAt.addingTimeInterval(duration * Double(index) / Double(total))
            points.append(
                CLLocation(
                    coordinate: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude),
                    altitude: point.altitude ?? 0,
                    horizontalAccuracy: 10,
                    verticalAccuracy: point.altitude == nil ? -1 : 10,
                    course: -1,
                    speed: -1,
                    timestamp: timestamp
                )
            )
        }
        return (points, segmentStarts)
    }

    var importedHealthExternalIDs: Set<String> {
        (knownRemoteImportIDs["appleHealth"] ?? []).union(activities.compactMap { activity in
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
        let activityType: ActivityType = switch identity.activity {
        case .running: .running
        case .walking: .walking
        case .cycling: .cycling
        case .hiking: .hiking
        case .swimming: .swimming
        case .strength: .strengthTraining
        case .mobility: .mobility
        }
        let summary = ActivitySummary(
            startedAt: startedAt,
            endedAt: endedAt,
            durationSecs: max(0, Int(finalMetrics.elapsedTime.rounded())),
            distanceM: distance,
            avgPace: activityType.plausibleAveragePace(
                durationSeconds: finalMetrics.elapsedTime,
                distanceMeters: distance
            ),
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
        statisticsAreCached = true
        defer { Task { await refreshAccountStatistics() } }
        if AuthStore.currentUserId != nil {
            let remoteID = activity.sync?.serverActivityId ?? activity.sync?.clientActivityId ?? activity.id.uuidString
            _ = try await api.deleteActivity(id: remoteID)
        }
        try await persistence.delete(activity)
        WatchWorkoutImportSuppression.remember(activity.recordingSession)
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
    func imageURL(for photo: SavedPhoto, thumbnailPixelHeight: CGFloat? = nil) -> URL? {
        if let thumbnailPixelHeight,
           let thumbnailURL = photo.remoteThumbnailURL.flatMap(URL.init(string:)) {
            return ActivityPhotoCache.shared.renderedURL(for: photo, thumbnailURL: thumbnailURL)
        }
        return ActivityPhotoCache.shared.renderedURL(for: photo, thumbnailPixelHeight: thumbnailPixelHeight)
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
              (activity.route?.elevationMetadata == nil
                || activity.route?.elevationMetadata?.algorithmVersion == "terrain-v1"),
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
            guard !Task.isCancelled,
                  let elevationMetadata = corrected.elevationMetadata,
                  let latest = self.activity(id: activityID),
                  latest.route == activity.route
            else { return } // Deleted/replaced routes must not be restored by enrichment.
            let updated = SavedActivity(
                id: latest.id,
                activityType: latest.activityType,
                title: latest.title,
                guideNudge: latest.guideNudge,
                reflection: latest.reflection,
                createdAt: latest.createdAt,
                startedAt: latest.startedAt,
                endedAt: latest.endedAt,
                durationSecs: latest.durationSecs,
                distanceM: latest.distanceM,
                avgPace: latest.avgPace,
                elevationGainM: corrected.elevationGainM,
                walkingStepCount: latest.walkingStepCount,
                healthMetrics: latest.healthMetrics,
                goal: latest.goal,
                companionType: latest.companionType,
                source: latest.source,
                gear: latest.gear,
                manualEdits: latest.manualEdits,
                indoor: latest.indoor,
                cadence: latest.cadence,
                heartRateZones: latest.heartRateZones,
                recordingSession: latest.recordingSession,
                activityEventID: latest.activityEventID,
                followedRoute: latest.followedRoute,
                recognitionBadgeIDs: latest.recognitionBadgeIDs,
                route: SavedRoute(
                    points: SavedRoutePoint.simplified(from: corrected.trackSegments),
                    elevationMetadata: elevationMetadata
                ),
                photos: latest.photos,
                sync: SavedActivitySyncState(
                    clientActivityId: latest.sync?.clientActivityId ?? latest.id.uuidString,
                    serverActivityId: latest.sync?.serverActivityId,
                    lastAttemptAt: latest.sync?.lastAttemptAt,
                    syncedAt: nil,
                    lastError: nil,
                    localUpdatedAt: Date()
                )
            )
            if activity.route?.elevationMetadata == nil, let route = activity.route {
                try await persistence.preserveOriginalElevationRoute(route, for: activityID)
            }
            try await persistence.replace(updated)
            activityRevision += 1
            if let index = activities.firstIndex(where: { $0.id == updated.id }) {
                activities[index] = updated
            }
            await analyticsManager?.track(.init(.activityElevationCorrectionCompleted, properties: [
                .result: .string("success"),
                .sourceType: .string(activity.route?.elevationMetadata == nil ? "mapzen_backfill" : "mapzen_upgrade_v2"),
                .latencyBucket: .string(ProductAnalyticsBucket.latency(milliseconds: Date().timeIntervalSince(startedAt) * 1_000))
            ]))
            Task { await syncActivityIfPossible(id: updated.id) }
        } catch is CancellationError {
            // Discard/session replacement intentionally cancels enrichment.
        } catch {
            ActivityDiagnosticLog.error(.persistence,
                "Saved activity elevation enrichment failed error=\(ActivityDiagnosticLog.errorCategory(error))")
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
        // Nested editors may have already committed photos since this editor opened.
        let activity = self.activity(id: activity.id) ?? activity
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var editedFields: [String] = []
        if cleanedTitle != activity.title { editedFields.append("title") }
        if startedAt != activity.startedAt { editedFields.append("date") }
        if abs(distanceM - activity.distanceM) > 0.5 { editedFields.append("distance") }
        if durationSecs != activity.durationSecs { editedFields.append("duration") }
        if gear != activity.gear { editedFields.append("shoe") }

        let avgPace = activity.activityType.plausibleAveragePace(
            durationSeconds: Double(durationSecs),
            distanceMeters: distanceM
        )

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
        adding captures: [(UIImage, PhotoMetadata)],
        photoOrder: [Int]? = nil
    ) async throws {
        if let photoOrder {
            let count = photos.count + captures.count
            guard photoOrder.count == count, Set(photoOrder) == Set(0..<count) else {
                ActivityDiagnosticLog.error(.persistence, "Activity photo update failed: invalid draft order")
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let current = self.activity(id: activity.id) ?? activity
        let keptIDs = Set(photos.map(\.id))
        for removed in current.photos where !keptIDs.contains(removed.id) {
            if let remotePhotoID = removed.remotePhotoId {
                try await api.deleteActivityPhoto(id: remotePhotoID)
            }
        }
        let updated = try await persistence.updatePhotos(for: current, keeping: photos, adding: captures, photoOrder: photoOrder)
        activityRevision += 1
        if let index = activities.firstIndex(where: { $0.id == updated.id }) {
            activities[index] = updated
        }
        await exportPhotosToAlbumIfNeeded(updated)
        Task { await syncActivityIfPossible(id: updated.id) }
    }

    func refreshAccountStatistics() async {
        guard let userID = AuthStore.currentUserId else {
            accountStatistics = nil
            statisticsAccountKey = nil
            return
        }
        let key = "statistics.v1.\(userID).\(TimeZone.current.identifier).\(Calendar.current.firstWeekday)"
        if statisticsAccountKey != key {
            statisticsAccountKey = key
            statisticsAreCached = true
            statisticsIsLoading = statisticsRequestsInFlight.contains(key)
            accountStatistics = nil
            knownRemoteImportIDs.removeAll()
            if let data = UserDefaults.standard.data(forKey: key) {
                do { accountStatistics = try JSONDecoder().decode(AccountStatisticsSnapshot.self, from: data) }
                catch { ActivityDiagnosticLog.error(.sync, "Statistics cache decode failed error=\(ActivityDiagnosticLog.errorCategory(error))") }
            }
        }
        guard statisticsRequestsInFlight.insert(key).inserted else { return }
        statisticsIsLoading = true
        defer {
            statisticsRequestsInFlight.remove(key)
            statisticsIsLoading = statisticsRequestsInFlight.contains(statisticsAccountKey ?? "")
        }
        do {
            let snapshot = try await api.fetchAccountStatistics()
            guard statisticsAccountKey == key, AuthStore.currentUserId == userID else { return }
            guard snapshot.algorithmVersion == 1, snapshot.status == "complete" else {
                ActivityDiagnosticLog.error(.sync, "Statistics response rejected reason=incomplete_or_unknown_version")
                statisticsAreCached = true
                return
            }
            accountStatistics = snapshot
            statisticsAreCached = false
            UserDefaults.standard.set(try JSONEncoder().encode(snapshot), forKey: key)
            await analyticsManager?.track(.init(.featureExposed, properties: [.feature: .string("server_statistics")]))
        } catch is CancellationError {
            statisticsAreCached = true
        } catch {
            statisticsAreCached = true
            ActivityDiagnosticLog.error(.sync, "Account statistics refresh failed error=\(ActivityDiagnosticLog.errorCategory(error))")
        }
    }

    private func checkRemoteImportIdentities(_ ids: [String], sourceKind: String) async -> Bool {
        guard let userID = AuthStore.currentUserId else { return true }
        if importIdentityAccountID != userID { knownRemoteImportIDs.removeAll(); importIdentityAccountID = userID }
        do {
            let known = try await api.knownImportIdentities(ids, sourceKind: sourceKind)
            knownRemoteImportIDs[sourceKind, default: []].formUnion(known)
            return true
        } catch {
            ActivityDiagnosticLog.error(.sync, "Import identity check failed error=\(ActivityDiagnosticLog.errorCategory(error))")
            return false // Offline imports remain local/pending; upload reconciles the canonical source identity.
        }
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
        await refreshAccountStatistics()
        await refreshCachedActivityMetadata()
        _ = await pullRemoteActivities(reset: true)
        // Register photo metadata for cached records; JPEG bytes load when rendered.
        await restorePendingRemotePhotos()
        let pendingIDs = activities
            .filter { !($0.sync?.isSynced ?? false) }
            .map(\.id)

        for activityID in pendingIDs {
            await syncActivityIfPossible(id: activityID)
        }
        for activity in activities where activity.sync?.serverActivityId != nil {
            await syncPhotosIfPossible(activityID: activity.id)
        }
        await refreshAccountStatistics()
        ActivityDiagnosticLog.notice(
            .sync,
            "Activity sync pass completed pending=\(ActivityDiagnosticLog.countBucket(pendingActivityCount)) failed=\(ActivityDiagnosticLog.countBucket(failedActivityCount))"
        )
    }

    private func loadActivities() async {
        defer { hasLoadedActivities = true }
#if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-OutboundUITestPhotoEditing") {
            do {
                if !ProcessInfo.processInfo.arguments.contains("-OutboundUITestRestorePhotoEditing") {
                    for fixture in Self.uiTestActivityFixtures {
                        try await persistence.replaceOrInsert(fixture)
                    }
                    if ProcessInfo.processInfo.arguments.contains("-OutboundUITestSeedPhotoDraft"),
                       let fixture = Self.uiTestActivityFixtures.first(where: { $0.title == "Golden Gate Easy Run" }) {
                        let captures: [(UIImage, PhotoMetadata)] = [1_000.0, 2_000.0].enumerated().map { index, distance in
                            let image = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 180)).image { context in
                                (index == 0 ? UIColor.systemBlue : UIColor.systemGreen).setFill()
                                context.fill(CGRect(x: 0, y: 0, width: 240, height: 180))
                            }
                            return (image, PhotoMetadata(takenAt: fixture.startedAt.addingTimeInterval(Double(index + 1) * 300),
                                paceAtShot: fixture.avgPace, hrAtShot: nil, distAtShot: distance,
                                coordinate: nil, captureContext: .active))
                        }
                        _ = try await persistence.updatePhotos(for: fixture, keeping: [], adding: captures)
                    }
                }
                // Unlike in-memory UI seeds, these fixtures exercise disk writes
                // and can be reopened after a fresh app process.
                activities = try await persistence.load().sortedByStartTimeDescending()
            } catch {
                ActivityDiagnosticLog.error(.persistence,
                    "Photo UI fixture load failed error=\(ActivityDiagnosticLog.errorCategory(error))")
            }
            return
        }
#endif
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
        defer { Task { await refreshAccountStatistics() } }
        guard AuthStore.currentUserId != nil else { return }
        guard let activity = activity(id: id) else { return }
        statisticsAreCached = true

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
                    clientData: ActivityClientExtras(from: activity),
                    clientUpdatedAt: attemptState.localUpdatedAt ?? activity.createdAt,
                    recognitionContext: RecognitionContextDTO(
                        timeZoneIdentifier: TimeZone.current.identifier,
                        firstWeekday: Calendar.current.firstWeekday
                    )
                )
            )

            if let canonicalID = response.clientActivityId.flatMap(UUID.init(uuidString:)), canonicalID != activity.id {
                let canonicalResponse = try await api.fetchActivities(ids: [response.id], includeRoute: false)
                _ = try await applyRemoteActivities(canonicalResponse.activities, preserveCachedRoutes: true)
                guard var canonical = self.activity(id: canonicalID) else { throw CocoaError(.fileReadCorruptFile) }
                let existingPhotoIDs = Set(canonical.photos.map(\.id))
                let copiedPhotos = try await persistence.copyPhotos(activity.photos.filter { !existingPhotoIDs.contains($0.id) }, into: canonicalID)
                canonical = copy(canonical, photos: canonical.photos + copiedPhotos, sync: canonical.sync)
                try await persistence.replaceOrInsert(canonical)
                try await persistence.delete(activity)
                activities.removeAll { $0.id == activity.id }
                if let index = activities.firstIndex(where: { $0.id == canonicalID }) { activities[index] = canonical }
                activityRevision += 1
                ActivityDiagnosticLog.notice(.sync, "Imported activity reconciled to canonical source identity")
                await syncPhotosIfPossible(activityID: canonicalID)
                return
            }

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
            if let contributions = response.groupContributions, !contributions.isEmpty {
                GroupContributionCenter.shared.publish(contributions)
                for contribution in contributions {
                    await analyticsManager?.track(.init(.groupActivityContributionReconciled, properties: [
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

    func ensureActivityRouteLoaded(_ id: UUID) async {
        guard let local = activity(id: id), let serverID = local.sync?.serverActivityId else { return }
        let version = "\(serverID):\(local.sync?.syncedAt?.timeIntervalSince1970 ?? 0)"
        guard invalidatedRoutes.contains(id) || (local.route == nil && !resolvedRouteVersions.contains(version)) else { return }
        await refreshActivityDetails(id)
    }

    func refreshActivityDetails(_ id: UUID) async {
        guard AuthStore.currentUserId != nil, let local = activity(id: id), let serverID = local.sync?.serverActivityId,
              detailRefreshIDs.insert(id).inserted else { return }
        defer { detailRefreshIDs.remove(id) }
        do {
            let response = try await api.fetchActivities(ids: [serverID])
            _ = try await applyRemoteActivities(response.activities)
            invalidatedRoutes.remove(id)
            if let updated = activity(id: id) {
                resolvedRouteVersions.insert("\(serverID):\(updated.sync?.syncedAt?.timeIntervalSince1970 ?? 0)")
            }
            await restorePendingRemotePhotos()
        } catch is CancellationError {
            return
        } catch {
            ActivityDiagnosticLog.error(.sync, "Activity detail refresh failed error=\(ActivityDiagnosticLog.errorCategory(error))")
        }
    }

    func loadMoreRemoteActivities() async -> Bool {
        guard AuthStore.currentUserId != nil else { return false }
        let succeeded = await pullRemoteActivities(reset: false)
        Task { await restorePendingRemotePhotos() }
        return succeeded
    }

    private func restorePendingRemotePhotos() async {
        guard !isRestoringPhotos else { return }
        isRestoringPhotos = true
        defer { isRestoringPhotos = false }
        while let (activityID, photos) = pendingRemotePhotos.first {
            pendingRemotePhotos.removeValue(forKey: activityID)
            await restoreRemotePhotos(photos, activityID: activityID)
        }
    }

    private func pullRemoteActivities(reset: Bool) async -> Bool {
        if let remoteHistoryTask {
            let succeeded = await remoteHistoryTask.value
            guard reset else { return succeeded }
            // A foreground page may have been in flight when the recent-page refresh began.
            return await pullRemoteActivities(reset: true)
        }
        let task = Task {
            let succeeded = await restoreRemoteActivityPage(reset: reset)
            remoteHistoryTask = nil
            return succeeded
        }
        remoteHistoryTask = task
        return await task.value
    }

    private func applyRemoteActivities(_ records: [RemoteActivityRecord], preserveCachedRoutes: Bool = false) async throws -> (received: Int, restored: Int, deleted: Int) {
        var remoteCount = 0, restoredCount = 0, deletedCount = 0
        for remote in records {
            remoteCount += 1
            guard let clientID = remote.clientActivityId,
                  let activityID = UUID(uuidString: clientID) else { continue }

            if remote.deletedAt != nil {
                if let local = activity(id: activityID) {
                    try await persistence.delete(local)
                    activities.removeAll { $0.id == activityID }
                    activityRevision += 1
                    deletedCount += 1
                }
                continue
            }

            guard let clientExtras = remote.clientData else { continue }
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

            if preserveCachedRoutes, let local, remote.updatedAt > (local.sync?.syncedAt ?? .distantPast) { invalidatedRoutes.insert(activityID) }
            let synced = SavedActivitySyncState(
                clientActivityId: clientID,
                serverActivityId: remote.id,
                lastAttemptAt: local?.sync?.lastAttemptAt,
                syncedAt: remote.updatedAt,
                lastError: nil,
                localUpdatedAt: remote.clientUpdatedAt ?? remote.updatedAt
            )
            let restored = SavedActivity(
                id: activityID,
                activityType: remote.activityType,
                title: remote.title,
                guideNudge: clientExtras.guideNudge,
                reflection: remote.reflection,
                createdAt: remote.createdAt,
                startedAt: remote.startedAt,
                endedAt: remote.endedAt,
                durationSecs: remote.durationSecs,
                distanceM: remote.distanceM,
                avgPace: remote.avgPace,
                elevationGainM: remote.elevationGainM,
                walkingStepCount: clientExtras.walkingStepCount,
                healthMetrics: clientExtras.healthMetrics,
                goal: clientExtras.goal,
                energyKilocalories: clientExtras.energyKilocalories,
                companionType: remote.companionType,
                source: clientExtras.source,
                gear: clientExtras.gear,
                manualEdits: clientExtras.manualEdits,
                indoor: clientExtras.indoor,
                cadence: clientExtras.cadence,
                heartRateZones: clientExtras.heartRateZones,
                recordingSession: clientExtras.recordingSession,
                activityEventID: clientExtras.activityEventID,
                followedRoute: clientExtras.followedRoute ?? local?.followedRoute,
                recognitionBadgeIDs: clientExtras.recognitionBadgeIDs,
                route: preserveCachedRoutes ? local?.route : remote.route,
                photos: local?.photos ?? [],
                sync: synced
            )
            try await persistence.replaceOrInsert(restored)
            if let index = activities.firstIndex(where: { $0.id == activityID }) {
                activities[index] = restored
            } else {
                activities.append(restored)
            }
            activityRevision += 1
            restoredCount += 1
            pendingRemotePhotos[activityID] = remote.photos ?? []
        }
        return (remoteCount, restoredCount, deletedCount)
    }

    private func refreshCachedActivityMetadata() async {
        let records = activities.compactMap { activity -> CachedActivityVersion? in
            guard let id = activity.sync?.serverActivityId else { return nil }
            return CachedActivityVersion(id: id, updatedAt: activity.sync?.syncedAt)
        }
        do {
            for start in stride(from: 0, to: records.count, by: 200) {
                let response = try await api.fetchCachedActivityChanges(Array(records[start..<min(records.count, start + 200)]))
                _ = try await applyRemoteActivities(response.activities, preserveCachedRoutes: true)
            }
            sortActivitiesByStartTime()
        } catch is CancellationError {
            return
        } catch {
            ActivityDiagnosticLog.error(.sync, "Cached activity metadata refresh failed error=\(ActivityDiagnosticLog.errorCategory(error))")
        }
    }

    private func restoreRemoteActivityPage(reset: Bool) async -> Bool {
        if reset {
            remoteHistoryCursor = nil
            remoteHistoryOffset = 0
            hasMoreRemoteActivities = true
        }
        guard hasMoreRemoteActivities else { return true }
        var pageCount = 0
        do {
            var remoteCount = 0
            var restoredCount = 0
            var deletedCount = 0
            do {
                try Task.checkCancellation()
                let response = try await api.fetchActivities(offset: remoteHistoryOffset, cursor: remoteHistoryCursor)
                let counts = try await applyRemoteActivities(response.activities, preserveCachedRoutes: true)
                remoteCount += counts.received
                restoredCount += counts.restored
                deletedCount += counts.deleted
                // Advance only after the complete page is durable; a failure retries it.
                remoteHistoryOffset += response.activities.count
                remoteHistoryCursor = response.nextCursor
                hasMoreRemoteActivities = response.hasMore && !response.activities.isEmpty
                pageCount += 1
                sortActivitiesByStartTime()
                ActivityDiagnosticLog.notice(.sync, "Activity restore page completed received=\(ActivityDiagnosticLog.countBucket(response.activities.count)) has_more=\(hasMoreRemoteActivities)")
            }
            ActivityDiagnosticLog.notice(
                .sync,
                "Activity restore completed received=\(ActivityDiagnosticLog.countBucket(remoteCount)) restored=\(ActivityDiagnosticLog.countBucket(restoredCount)) deleted=\(ActivityDiagnosticLog.countBucket(deletedCount))"
            )
            return true
        } catch is CancellationError {
            return false
        } catch {
            sortActivitiesByStartTime()
            ActivityDiagnosticLog.error(
                .sync,
                "Activity restore failed pages=\(ActivityDiagnosticLog.countBucket(pageCount)) error=\(ActivityDiagnosticLog.errorCategory(error))"
            )
            return false
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
        guard let initial = activity(id: activityID) else { return }
        var photos = initial.photos
        var changed = false
        for remote in remotePhotos {
            if let index = photos.firstIndex(where: { $0.id.uuidString.caseInsensitiveCompare(remote.clientPhotoId) == .orderedSame }) {
                let local = photos[index]
                if local.remotePhotoId != remote.id || local.remoteThumbnailURL != remote.thumbnailUrl?.absoluteString {
                    photos[index] = copy(local, remotePhotoId: remote.id, remoteUploadedAt: remote.updatedAt, remoteThumbnailURL: remote.thumbnailUrl?.absoluteString)
                    changed = true
                }
                continue
            }
            guard let photoID = UUID(uuidString: remote.clientPhotoId) else {
                ActivityDiagnosticLog.error(.sync, "Photo metadata restore rejected reason=invalid_client_photo_id")
                continue
            }
            let coordinate: SavedCoordinate?
            if let latitude = remote.latitude, let longitude = remote.longitude { coordinate = SavedCoordinate(latitude: latitude, longitude: longitude) }
            else { coordinate = nil }
            // The existing photo cache downloads bytes only when a photo is rendered.
            photos.append(SavedPhoto(id: photoID, takenAt: remote.takenAt, paceAtShot: remote.paceAtShot, hrAtShot: remote.hrAtShot,
                                     distAtShot: remote.distAtShot ?? 0, coordinate: coordinate,
                                     captureContext: PhotoCaptureContext(rawValue: remote.captureContext ?? "active") ?? .active,
                                     relativePath: "\(activityID.uuidString)/photos/\(photoID.uuidString).jpg", remotePhotoId: remote.id,
                                     remoteUploadedAt: remote.updatedAt, remoteThumbnailURL: remote.thumbnailUrl?.absoluteString))
            changed = true
        }
        guard changed else { return }
        photos.sort { $0.takenAt < $1.takenAt }
        // Downloads suspend the actor; retain any edits made while they were in flight.
        guard let latest = activity(id: activityID) else { return }
        let initialIDs = Set(initial.photos.map(\.id))
        let restoredPhotos = photos.filter { !initialIDs.contains($0.id) }
        let metadataByID = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
        let mergedPhotos = (latest.photos.map { local in
            guard let remote = metadataByID[local.id] else { return local }
            return copy(local, remotePhotoId: remote.remotePhotoId, remoteUploadedAt: remote.remoteUploadedAt, remoteThumbnailURL: remote.remoteThumbnailURL)
        } + restoredPhotos.filter { restored in !latest.photos.contains(where: { $0.id == restored.id }) })
            .sorted { $0.takenAt < $1.takenAt }
        let current = copy(latest, photos: mergedPhotos, sync: latest.sync)
        do {
            try await persistence.replace(current)
            activityRevision += 1
            if let index = activities.firstIndex(where: { $0.id == activityID }) { activities[index] = current }
        } catch {
            ActivityDiagnosticLog.error(.sync, "Restored photo metadata save failed error=\(ActivityDiagnosticLog.errorCategory(error))")
        }
    }

    private func markPhotoUploaded(_ photoID: UUID, remote: RemoteActivityPhoto, activityID: UUID) async {
        guard let current = activity(id: activityID) else { return }
        let photos = current.photos.map { photo in
            photo.id == photoID
                ? copy(photo, remotePhotoId: remote.id, remoteUploadedAt: remote.updatedAt, remoteThumbnailURL: remote.thumbnailUrl?.absoluteString)
                : photo
        }
        let updated = copy(current, photos: photos, sync: current.sync)
        guard (try? await persistence.replace(updated)) != nil else { return }
        activityRevision += 1
        if let index = activities.firstIndex(where: { $0.id == activityID }) { activities[index] = updated }
    }

    private func syncSnapshot(for activity: SavedActivity) -> SavedActivity {
        copy(activity, photos: [], sync: nil, stripImportedFollowedRoute: true)
    }

    private func copy(
        _ photo: SavedPhoto,
        remotePhotoId: String?,
        remoteUploadedAt: Date?,
        remoteThumbnailURL: String? = nil
    ) -> SavedPhoto {
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
            remoteUploadedAt: remoteUploadedAt,
            remoteThumbnailURL: remoteThumbnailURL ?? photo.remoteThumbnailURL
        )
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

struct StravaImportOutcome: Sendable {
    let importedIDs: Set<String>
    let failedIDs: Set<String>
}

private extension ImportedActivitySport {
    var activityType: ActivityType {
        switch self {
        case .running: .running
        case .cycling: .cycling
        case .hiking: .hiking
        case .walking: .walking
        case .swimming: .swimming
        case .strength: .strengthTraining
        case .mobility: .mobility
        // Unrecognized vendor sports stay generic rather than being dropped.
        case .other: .running
        }
    }
}

private extension StravaImportCandidate {
    func resolvedTitle(for activityType: ActivityType) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? activityType.stravaImportTitle : trimmed
    }
}

private extension ActivityType {
    var stravaImportTitle: String {
        switch self {
        case .running: String(localized: "strava.import.title.run", defaultValue: "Imported Run")
        case .cycling: String(localized: "strava.import.title.ride", defaultValue: "Imported Ride")
        case .hiking: String(localized: "strava.import.title.hike", defaultValue: "Imported Hike")
        case .walking: String(localized: "strava.import.title.walk", defaultValue: "Imported Walk")
        case .swimming: String(localized: "strava.import.title.swim", defaultValue: "Imported Swim")
        case .strengthTraining: String(localized: "strava.import.title.strength", defaultValue: "Imported Strength Workout")
        case .mobility: String(localized: "strava.import.title.mobility", defaultValue: "Imported Mobility Workout")
        }
    }

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
