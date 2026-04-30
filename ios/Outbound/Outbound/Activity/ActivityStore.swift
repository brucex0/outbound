import Combine
import CoreLocation
import Foundation
import UIKit

@MainActor
final class ActivityStore: ObservableObject {
    @Published private(set) var activities: [SavedActivity] = []

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

    private func refresh() {
        if ProcessInfo.processInfo.arguments.contains("-OutboundUITestSeedSavedActivity") {
            activities = [Self.uiTestActivityFixture]
            return
        }
        activities = (try? LocalActivityStore.load()) ?? []
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
            route: SavedRoute(points: points),
            photos: []
        )
    }
}
