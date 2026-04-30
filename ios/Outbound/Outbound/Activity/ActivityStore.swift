import Combine
import Foundation
import UIKit

@MainActor
final class ActivityStore: ObservableObject {
    @Published private(set) var activities: [SavedActivity] = []

    init() { refresh() }

    @discardableResult
    func save(
        summary: ActivitySummary,
        photos: [(UIImage, PhotoMetadata)],
        lastNudge: String,
        saveRoute: Bool
    ) throws -> SavedActivity {
        let activity = try LocalActivityStore.save(
            summary: summary,
            photos: photos,
            title: autoTitle(for: summary.startedAt),
            coachNudge: lastNudge,
            saveRoute: saveRoute
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

    var savedRoutes: [SavedActivity] {
        activities.filter(\.hasRoute)
    }

    private func refresh() {
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
}
