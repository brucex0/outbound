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
    func save(summary: ActivitySummary, photos: [(UIImage, PhotoMetadata)], lastNudge: String) throws -> SavedActivity {
        let activity = try LocalActivityStore.save(
            summary: summary,
            photos: photos,
            title: autoTitle(for: summary.startedAt),
            coachNudge: lastNudge
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
                    route: activity.route
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
            createdAt: current.createdAt,
            startedAt: current.startedAt,
            endedAt: current.endedAt,
            durationSecs: current.durationSecs,
            distanceM: current.distanceM,
            avgPace: current.avgPace,
            elevationGainM: current.elevationGainM,
            healthMetrics: current.healthMetrics,
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
            route: SavedRoute(points: points),
            photos: [],
            sync: nil
        )
    }
}
