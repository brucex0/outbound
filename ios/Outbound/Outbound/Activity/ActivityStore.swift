import Combine
import CoreLocation
import Foundation
import UIKit

@MainActor
final class ActivityStore: ObservableObject {
    @Published private(set) var activities: [SavedActivity] = []
    private let api = APIClient.shared

    init() { refresh() }

    @discardableResult
    func save(
        summary: ActivitySummary,
        photos: [(UIImage, PhotoMetadata)],
        reflection: FinishReflection?,
        goal: ActivityGoal? = nil,
        title: String? = nil,
        source: ActivitySourceMetadata = .outboundRecorded,
        gear: ActivityGearAttachment? = nil,
        manualEdits: ActivityManualEdits? = nil,
        indoor: ActivityIndoorMetadata? = nil,
        cadence: ActivityCadenceSummary? = nil,
        heartRateZones: ActivityHeartRateZoneSummary? = nil
    ) throws -> SavedActivity {
        let activity = try LocalActivityStore.save(
            summary: summary,
            photos: photos,
            title: title ?? autoTitle(for: summary.startedAt),
            coachNudge: "",
            reflection: reflection,
            goal: goal,
            source: source,
            gear: gear,
            manualEdits: manualEdits,
            indoor: indoor,
            cadence: cadence,
            heartRateZones: heartRateZones
        )
        refresh()
        Task {
            await syncActivityIfPossible(id: activity.id)
        }
        return activity
    }

    func delete(_ activity: SavedActivity) throws {
        try LocalActivityStore.delete(activity)
        refresh()
    }

    func imageURL(for photo: SavedPhoto) -> URL? {
        try? LocalActivityStore.imageURL(for: photo)
    }

    func activity(id: UUID) -> SavedActivity? {
        activities.first { $0.id == id }
    }

    func exportRoute(for activity: SavedActivity, format: RouteExportFormat) throws -> URL {
        try RouteFileExporter.export(activity: self.activity(id: activity.id) ?? activity, format: format)
    }

    func updateActivity(
        _ activity: SavedActivity,
        title: String,
        startedAt: Date,
        distanceM: Double,
        durationSecs: Int,
        gear: ActivityGearAttachment?
    ) throws {
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
            title: cleanedTitle.isEmpty ? activity.title : cleanedTitle,
            coachNudge: activity.coachNudge,
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
            route: activity.route,
            photos: activity.photos,
            sync: activity.sync
        )

        try LocalActivityStore.replace(updated)
        refresh()
    }

    func syncPendingActivitiesIfNeeded() async {
        guard AuthStore.currentUserId != nil else { return }
        let pendingIDs = activities
            .filter { !($0.sync?.isSynced ?? false) }
            .map(\.id)

        for activityID in pendingIDs {
            await syncActivityIfPossible(id: activityID)
        }
    }

    private func refresh() {
        if ProcessInfo.processInfo.arguments.contains("-OutboundUITestSeedSavedActivity") {
            activities = [Self.uiTestActivityFixture]
            return
        }
        activities = (try? LocalActivityStore.load()) ?? []
    }

    private func syncActivityIfPossible(id: UUID) async {
        guard AuthStore.currentUserId != nil else { return }
        guard let activity = activity(id: id) else { return }

        let priorState = activity.sync ?? SavedActivitySyncState(
            clientActivityId: activity.id.uuidString,
            serverActivityId: nil,
            lastAttemptAt: nil,
            syncedAt: nil,
            lastError: nil
        )

        let attemptState = SavedActivitySyncState(
            clientActivityId: priorState.clientActivityId,
            serverActivityId: priorState.serverActivityId,
            lastAttemptAt: Date(),
            syncedAt: priorState.syncedAt,
            lastError: nil
        )
        persistSyncState(attemptState, for: activity.id)

        do {
            let response = try await api.uploadActivity(
                ActivityUploadRequest(
                    clientActivityId: priorState.clientActivityId,
                    syncSource: "ios-local-store",
                    type: "running",
                    title: activity.title,
                    startedAt: activity.startedAt,
                    endedAt: activity.endedAt,
                    durationSecs: activity.durationSecs,
                    distanceM: activity.distanceM,
                    elevationM: activity.elevationGainM,
                    avgPace: activity.avgPace,
                    avgHeartRate: activity.healthMetrics?.averageHeartRateBPM,
                    route: activity.route,
                    reflection: activity.reflection
                )
            )

            let syncedState = SavedActivitySyncState(
                clientActivityId: priorState.clientActivityId,
                serverActivityId: response.id,
                lastAttemptAt: attemptState.lastAttemptAt,
                syncedAt: response.uploadedAt,
                lastError: nil
            )
            persistSyncState(syncedState, for: activity.id)
        } catch {
            let failedState = SavedActivitySyncState(
                clientActivityId: priorState.clientActivityId,
                serverActivityId: priorState.serverActivityId,
                lastAttemptAt: attemptState.lastAttemptAt,
                syncedAt: priorState.syncedAt,
                lastError: error.localizedDescription
            )
            persistSyncState(failedState, for: activity.id)
            print("[ActivityStore] activity sync failed: \(error.localizedDescription)")
        }
    }

    private func persistSyncState(_ syncState: SavedActivitySyncState, for activityID: UUID) {
        guard let current = activity(id: activityID) else { return }
        let updated = SavedActivity(
            id: current.id,
            title: current.title,
            coachNudge: current.coachNudge,
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
            route: current.route,
            photos: current.photos,
            sync: syncState
        )
        try? LocalActivityStore.replace(updated)
        refresh()
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

    private static var uiTestActivityFixture: SavedActivity {
        let startedAt = Date(timeIntervalSince1970: 1_714_368_400)
        let points = [
            SavedRoutePoint(location: CLLocation(latitude: 37.7749, longitude: -122.4194)),
            SavedRoutePoint(location: CLLocation(latitude: 37.7758, longitude: -122.4179)),
            SavedRoutePoint(location: CLLocation(latitude: 37.7767, longitude: -122.4163))
        ]

        return SavedActivity(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555") ?? UUID(),
            title: "UI Test Route Activity",
            coachNudge: "Keep your cadence steady.",
            reflection: nil,
            createdAt: startedAt,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(1_845),
            durationSecs: 1_845,
            distanceM: 5_420,
            avgPace: 340,
            elevationGainM: 74,
            healthMetrics: ActivityHealthMetrics(
                averageHeartRateBPM: 146,
                maxHeartRateBPM: 162,
                heartRateSampleCount: 12
            ),
            goal: .distanceMeters(5_000),
            route: SavedRoute(points: points),
            photos: [],
            sync: nil
        )
    }
}
