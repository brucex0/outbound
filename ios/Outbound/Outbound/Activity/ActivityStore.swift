import Combine
import CoreLocation
import Foundation
import UIKit

@MainActor
final class ActivityStore: ObservableObject {
    @Published private(set) var activities: [SavedActivity] = []
    @Published private(set) var isSyncing = false
    private let api = APIClient.shared
    private let persistence = ActivityPersistence.shared
    private var activityRevision = 0

    var pendingActivityCount: Int {
        activities.filter { !($0.sync?.isSynced ?? false) }.count
    }

    var failedActivityCount: Int {
        activities.filter { activity in
            !(activity.sync?.isSynced ?? false) && activity.sync?.lastError?.isEmpty == false
        }.count
    }

    init() {
        Task { await loadActivities() }
    }

    @discardableResult
    func save(
        summary: ActivitySummary,
        photos: [(UIImage, PhotoMetadata)],
        activityType: ActivityType = .running,
        reflection: FinishReflection?,
        goal: ActivityGoal? = nil,
        title: String? = nil,
        source: ActivitySourceMetadata = .outboundRecorded,
        gear: ActivityGearAttachment? = nil,
        manualEdits: ActivityManualEdits? = nil,
        indoor: ActivityIndoorMetadata? = nil,
        cadence: ActivityCadenceSummary? = nil,
        heartRateZones: ActivityHeartRateZoneSummary? = nil,
        activityEventID: String? = nil
    ) async throws -> SavedActivity {
        let resolvedTitle = title ?? autoTitle(for: summary.startedAt)
        let activity = try await persistence.save(
            summary: summary,
            photos: photos,
            activityType: activityType,
            title: resolvedTitle,
            guideNudge: "",
            reflection: reflection,
            goal: goal,
            source: source,
            gear: gear,
            manualEdits: manualEdits,
            indoor: indoor,
            cadence: cadence,
            heartRateZones: heartRateZones,
            activityEventID: activityEventID
        )
        activityRevision += 1
        activities.insert(activity, at: 0)
        Task {
            await syncActivityIfPossible(id: activity.id)
        }
        return activity
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

    func imageURL(for photo: SavedPhoto) -> URL? {
        if let remoteURL = URL(string: photo.relativePath),
           ["http", "https"].contains(remoteURL.scheme?.lowercased() ?? "") {
            return remoteURL
        }
        return ActivityPersistence.imageURL(for: photo)
    }

    func activity(id: UUID) -> SavedActivity? {
        activities.first { $0.id == id }
    }

    func exportRoute(for activity: SavedActivity, format: RouteExportFormat) async throws -> URL {
        try await persistence.exportRoute(for: self.activity(id: activity.id) ?? activity, format: format)
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
            healthMetrics: activity.healthMetrics,
            goal: activity.goal,
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
            activityEventID: activity.activityEventID,
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
    }

    private func loadActivities() async {
        if ProcessInfo.processInfo.arguments.contains("-OutboundUITestSeedData")
            || ProcessInfo.processInfo.arguments.contains("-OutboundUITestSeedSavedActivity")
        {
            activities = Self.uiTestActivityFixtures
            return
        }
        let revisionAtStart = activityRevision
        let loadedActivities = (try? await persistence.load()) ?? []
        guard activityRevision == revisionAtStart else { return }
        activities = loadedActivities
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
                    activityEventId: activity.activityEventID,
                    route: activity.route,
                    reflection: activity.reflection,
                    clientData: syncSnapshot(for: activity),
                    clientUpdatedAt: attemptState.localUpdatedAt ?? activity.createdAt
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
            print("[ActivityStore] activity sync failed: \(error.localizedDescription)")
        }
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
            healthMetrics: current.healthMetrics,
            goal: current.goal,
            source: current.source,
            gear: current.gear,
            manualEdits: current.manualEdits,
            indoor: current.indoor,
            cadence: current.cadence,
            heartRateZones: current.heartRateZones,
            activityEventID: current.activityEventID,
            route: current.route,
            photos: current.photos,
            sync: syncState
        )
        guard (try? await persistence.replace(updated)) != nil else { return }
        activityRevision += 1
        if let index = activities.firstIndex(where: { $0.id == updated.id }) {
            activities[index] = updated
        }
    }

    private func pullRemoteActivities() async {
        do {
            var offset = 0
            var hasMore = true
            while hasMore {
                let response = try await api.fetchActivities(offset: offset)
                for remote in response.activities {
                guard let clientID = remote.clientActivityId,
                      let activityID = UUID(uuidString: clientID) else { continue }

                if remote.deletedAt != nil {
                    if let local = activity(id: activityID) {
                        try? await persistence.delete(local)
                        activities.removeAll { $0.id == activityID }
                        activityRevision += 1
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
                    sync: synced
                )
                try await persistence.replaceOrInsert(restored)
                if let index = activities.firstIndex(where: { $0.id == activityID }) {
                    activities[index] = restored
                } else {
                    activities.append(restored)
                }
                await restoreRemotePhotos(remote.photos ?? [], activityID: activityID)
                }
                offset += response.activities.count
                hasMore = response.hasMore && !response.activities.isEmpty
            }
            activities.sort { $0.startedAt > $1.startedAt }
        } catch {
            print("[ActivityStore] activity restore failed: \(error.localizedDescription)")
        }
    }

    private func syncPhotosIfPossible(activityID: UUID) async {
        guard let activity = activity(id: activityID),
              let serverActivityID = activity.sync?.serverActivityId else { return }
        for photo in activity.photos where photo.remotePhotoId == nil {
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
            } catch {
                print("[ActivityStore] photo sync failed for \(photo.id): \(error.localizedDescription)")
            }
        }
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
                print("[ActivityStore] photo restore failed for \(remote.id): \(error.localizedDescription)")
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
        copy(activity, photos: [], sync: nil)
    }

    private func copy(
        _ activity: SavedActivity,
        photos: [SavedPhoto],
        sync: SavedActivitySyncState?
    ) -> SavedActivity {
        SavedActivity(
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
            healthMetrics: activity.healthMetrics,
            goal: activity.goal,
            source: activity.source,
            gear: activity.gear,
            manualEdits: activity.manualEdits,
            indoor: activity.indoor,
            cadence: activity.cadence,
            heartRateZones: activity.heartRateZones,
            activityEventID: activity.activityEventID,
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
        serverActivityID: String? = nil
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
