import Foundation

struct WatchLap: Codable, Identifiable {
    var id = UUID()
    let seconds: TimeInterval
    let meters: Double
    let automatic: Bool
    var pace: Double? { meters > 0 ? seconds * 1_000 / meters : nil }
}

enum WatchRunningSettings {
    static var miles: Bool { UserDefaults.standard.bool(forKey: "watch.miles") }
    static var splitMeters: Double { miles ? 1609.344 : 1000 }
    static var autoSplits: Bool { UserDefaults.standard.object(forKey: "watch.autoSplits") as? Bool ?? true }
    static var zoneAlerts: Bool { UserDefaults.standard.bool(forKey: "watch.zoneAlerts") }
    static var goalIsTime: Bool { UserDefaults.standard.bool(forKey: "watch.goalIsTime") }
    static var goalValue: Double { UserDefaults.standard.double(forKey: "watch.goalValue") }
    static var paceTarget: Double { UserDefaults.standard.double(forKey: "watch.paceTarget") }
}
