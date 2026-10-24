import Foundation

struct SmartGoalPreference {
    let goal: ActivityGoal
    let count: Int
    let firstSeenOrder: Int

    static func preferredFrequentCustomGoal(from activities: [SavedActivity]) -> ActivityGoal? {
        [
            DistanceGoalPreset.preferredFrequentCustom(from: activities),
            TimeGoalPreset.preferredFrequentCustom(from: activities)
        ]
        .compactMap { $0 }
        .sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.firstSeenOrder < rhs.firstSeenOrder
        }
        .first?
        .goal
    }
}

struct DistanceGoalPreset: Identifiable, Hashable {
    let title: String
    let meters: Double

    var id: Int {
        Self.normalizedDistanceKey(meters)
    }

    static func recommended(from activities: [SavedActivity]) -> [DistanceGoalPreset] {
        let stats = distanceStats(from: activities)
        var presets = defaultPresets

        if stats.totalDistanceGoalCount >= matureHistoryCount {
            let usedDefaults = defaultPresets.filter { stats.usageCounts[$0.id, default: 0] > 0 }
            presets = usedDefaults.isEmpty ? Array(defaultPresets.prefix(2)) : usedDefaults
        }

        for custom in frequentCustomPresets(from: stats) where !presets.contains(where: { $0.id == custom.id }) {
            presets.insert(custom, at: 0)
        }

        if presets.count < minimumPresetCount {
            for preset in defaultPresets where !presets.contains(where: { $0.id == preset.id }) {
                presets.append(preset)
                if presets.count == minimumPresetCount { break }
            }
        }

        return Array(presets.prefix(maximumPresetCount))
    }

    static func preferredFrequentCustom(from activities: [SavedActivity]) -> SmartGoalPreference? {
        let stats = distanceStats(from: activities)
        guard let candidate = frequentCustomPresets(from: stats).first else { return nil }
        return SmartGoalPreference(
            goal: .distanceMeters(candidate.meters),
            count: stats.usageCounts[candidate.id, default: 0],
            firstSeenOrder: stats.firstSeenOrder[candidate.id, default: Int.max]
        )
    }

    private static let defaultPresets: [DistanceGoalPreset] = [
        DistanceGoalPreset(title: "5K", meters: 5_000),
        DistanceGoalPreset(title: "10K", meters: 10_000),
        DistanceGoalPreset(title: "Half marathon", meters: 21_097.5),
        DistanceGoalPreset(title: "Marathon", meters: 42_195)
    ]

    private static let frequentCustomUseThreshold = 3
    private static let recentActivityLimit = 30
    private static let matureHistoryCount = 8
    private static let minimumPresetCount = 4
    private static let maximumPresetCount = 6
    private static let distanceBucketMeters = 100.0

    private struct DistanceStats {
        var usageCounts: [Int: Int]
        var firstSeenOrder: [Int: Int]
        var totalDistanceGoalCount: Int
    }

    private static func frequentCustomPresets(from stats: DistanceStats) -> [DistanceGoalPreset] {
        stats.usageCounts
            .filter { key, count in
                count >= frequentCustomUseThreshold && !defaultPresets.contains { $0.id == key }
            }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return stats.firstSeenOrder[lhs.key, default: Int.max] < stats.firstSeenOrder[rhs.key, default: Int.max]
            }
            .map { key, _ in
                let meters = Double(key) * distanceBucketMeters
                return DistanceGoalPreset(title: label(forMeters: meters), meters: meters)
            }
    }

    private static func distanceStats(from activities: [SavedActivity]) -> DistanceStats {
        var usageCounts: [Int: Int] = [:]
        var firstSeenOrder: [Int: Int] = [:]
        var totalDistanceGoalCount = 0

        for (index, activity) in activities.prefix(recentActivityLimit).enumerated() {
            guard let meters = activity.goal?.targetDistanceMeters, meters >= 1_000 else { continue }
            let key = normalizedDistanceKey(meters)
            usageCounts[key, default: 0] += 1
            firstSeenOrder[key] = min(firstSeenOrder[key, default: index], index)
            totalDistanceGoalCount += 1
        }

        return DistanceStats(
            usageCounts: usageCounts,
            firstSeenOrder: firstSeenOrder,
            totalDistanceGoalCount: totalDistanceGoalCount
        )
    }

    private static func normalizedDistanceKey(_ meters: Double) -> Int {
        Int((meters / distanceBucketMeters).rounded())
    }

    private static func label(forMeters meters: Double) -> String {
        let kilometers = meters / 1000
        if abs(kilometers.rounded() - kilometers) < 0.05 {
            return "\(Int(kilometers.rounded()))K"
        }
        return String(format: "%.1fK", kilometers)
            .replacingOccurrences(of: #"\.0K$"#, with: "K", options: .regularExpression)
    }
}

struct TimeGoalPreset: Identifiable, Hashable {
    let title: String
    let seconds: Int

    var id: Int {
        Self.normalizedTimeKey(seconds)
    }

    static func recommended(from activities: [SavedActivity]) -> [TimeGoalPreset] {
        let stats = timeStats(from: activities)
        var presets = defaultPresets

        if stats.totalTimeGoalCount >= matureHistoryCount {
            let usedDefaults = defaultPresets.filter { stats.usageCounts[$0.id, default: 0] > 0 }
            presets = usedDefaults.isEmpty ? Array(defaultPresets.prefix(3)) : usedDefaults
        }

        for custom in frequentCustomPresets(from: stats) where !presets.contains(where: { $0.id == custom.id }) {
            presets.insert(custom, at: 0)
        }

        if presets.count < minimumPresetCount {
            for preset in defaultPresets where !presets.contains(where: { $0.id == preset.id }) {
                presets.append(preset)
                if presets.count == minimumPresetCount { break }
            }
        }

        return Array(presets.prefix(maximumPresetCount))
    }

    static func preferredFrequentCustom(from activities: [SavedActivity]) -> SmartGoalPreference? {
        let stats = timeStats(from: activities)
        guard let candidate = frequentCustomPresets(from: stats).first else { return nil }
        return SmartGoalPreference(
            goal: .timeSeconds(candidate.seconds),
            count: stats.usageCounts[candidate.id, default: 0],
            firstSeenOrder: stats.firstSeenOrder[candidate.id, default: Int.max]
        )
    }

    private static let defaultPresets: [TimeGoalPreset] = [
        TimeGoalPreset(title: "20 min", seconds: 20 * 60),
        TimeGoalPreset(title: "30 min", seconds: 30 * 60),
        TimeGoalPreset(title: "45 min", seconds: 45 * 60),
        TimeGoalPreset(title: "1 hr", seconds: 60 * 60),
        TimeGoalPreset(title: "1.5 hr", seconds: 90 * 60)
    ]

    private static let frequentCustomUseThreshold = 3
    private static let recentActivityLimit = 30
    private static let matureHistoryCount = 8
    private static let minimumPresetCount = 4
    private static let maximumPresetCount = 6
    private static let timeBucketSeconds = 60

    private struct TimeStats {
        var usageCounts: [Int: Int]
        var firstSeenOrder: [Int: Int]
        var totalTimeGoalCount: Int
    }

    private static func frequentCustomPresets(from stats: TimeStats) -> [TimeGoalPreset] {
        stats.usageCounts
            .filter { key, count in
                count >= frequentCustomUseThreshold && !defaultPresets.contains { $0.id == key }
            }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return stats.firstSeenOrder[lhs.key, default: Int.max] < stats.firstSeenOrder[rhs.key, default: Int.max]
            }
            .map { key, _ in
                let seconds = key * timeBucketSeconds
                return TimeGoalPreset(title: label(forSeconds: seconds), seconds: seconds)
            }
    }

    private static func timeStats(from activities: [SavedActivity]) -> TimeStats {
        var usageCounts: [Int: Int] = [:]
        var firstSeenOrder: [Int: Int] = [:]
        var totalTimeGoalCount = 0

        for (index, activity) in activities.prefix(recentActivityLimit).enumerated() {
            guard let seconds = activity.goal?.targetDurationSeconds, seconds >= timeBucketSeconds else { continue }
            let key = normalizedTimeKey(seconds)
            usageCounts[key, default: 0] += 1
            firstSeenOrder[key] = min(firstSeenOrder[key, default: index], index)
            totalTimeGoalCount += 1
        }

        return TimeStats(
            usageCounts: usageCounts,
            firstSeenOrder: firstSeenOrder,
            totalTimeGoalCount: totalTimeGoalCount
        )
    }

    private static func normalizedTimeKey(_ seconds: Int) -> Int {
        Int((Double(seconds) / Double(timeBucketSeconds)).rounded())
    }

    private static func label(forSeconds seconds: Int) -> String {
        if seconds < 3600 {
            return "\(max(1, seconds / 60)) min"
        }

        let hours = Double(seconds) / 3600
        if abs(hours.rounded() - hours) < 0.01 {
            return "\(Int(hours.rounded())) hr"
        }
        return String(format: "%.1f hr", hours)
            .replacingOccurrences(of: #"\.0 hr$"#, with: " hr", options: .regularExpression)
    }
}
