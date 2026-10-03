import Foundation
import WidgetKit

nonisolated struct HomeWorkoutWidgetSnapshot: Codable, Equatable, Sendable {
    let title: String
    let detail: String
    let systemImageName: String
}

@MainActor
enum HomeWorkoutWidgetStore {
    static let appGroupIdentifier = "group.ai.plainstride.shared"
    static let widgetKind = "PlainstrideHomeWorkoutWidget"
    private static let snapshotKey = "home_workout_widget_snapshot_v1"

    static func read() -> HomeWorkoutWidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = defaults.data(forKey: snapshotKey)
        else { return nil }
        return try? JSONDecoder().decode(HomeWorkoutWidgetSnapshot.self, from: data)
    }

    static func publish(_ snapshot: HomeWorkoutWidgetSnapshot) {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = try? JSONEncoder().encode(snapshot),
              defaults.data(forKey: snapshotKey) != data
        else { return }

        defaults.set(data, forKey: snapshotKey)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    static func clear() {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
        defaults.removeObject(forKey: snapshotKey)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }
}
