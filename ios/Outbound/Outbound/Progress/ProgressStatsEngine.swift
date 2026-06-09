import Foundation

struct ProgressActivity: Equatable {
    let id: String
    let title: String
    let startedAt: Date
    let durationSeconds: Int
    let distanceMeters: Double
    let elevationGainMeters: Double?
    let averageHeartRate: Int?
    let routePoints: [ProgressRoutePoint]
}

struct ProgressRoutePoint: Equatable {
    let timestamp: Date
    let cumulativeDistanceMeters: Double
}

struct ProgressStatsSnapshot: Equatable {
    let currentWeek: ProgressPeriodTotals
    let weeklyBuckets: [ProgressWeekBucket]
    let bestEfforts: [ProgressBestEffort]
    let momentumNote: ProgressMomentumNote?
    let eligibleActivityCount: Int

    var coachNote: String {
        guard eligibleActivityCount > 0 else {
            return "Save your first activity to start building stats."
        }

        let priorBuckets = weeklyBuckets.dropLast()
        let recentBest = priorBuckets.map(\.distanceMeters).max() ?? 0
        if currentWeek.distanceMeters > 0, currentWeek.distanceMeters >= recentBest, recentBest > 0 {
            return "This is your strongest week in the last month."
        }
        if currentWeek.activityCount >= 3 {
            return "You have a solid rhythm going this week."
        }
        if let longest = bestEfforts.first(where: { $0.kind == .longestRun }) {
            return "Longest run to beat: \(Int((longest.distanceMeters ?? 0).rounded())) meters."
        }
        return "A few more saved activities will unlock stronger trends."
    }
}

struct ProgressMomentumNote: Equatable {
    let text: String
    let symbolName: String
}

struct ProgressPeriodTotals: Equatable {
    let activityCount: Int
    let distanceMeters: Double
    let durationSeconds: Int
    let elevationMeters: Double

    var averagePaceSecondsPerKilometer: Double? {
        guard distanceMeters > 0, durationSeconds > 0 else { return nil }
        return Double(durationSeconds) / (distanceMeters / 1000)
    }
}

struct ProgressWeekBucket: Identifiable, Equatable {
    let id: Date
    let startDate: Date
    let endDate: Date
    let activityCount: Int
    let distanceMeters: Double
    let durationSeconds: Int
    let elevationMeters: Double

    var averagePaceSecondsPerKilometer: Double? {
        guard distanceMeters > 0, durationSeconds > 0 else { return nil }
        return Double(durationSeconds) / (distanceMeters / 1000)
    }
}

struct ProgressBestEffort: Identifiable, Equatable {
    enum Kind: String, CaseIterable {
        case fastestKilometer
        case fastestMile
        case fastestFiveKilometer
        case longestRun
        case mostElevation
        case bestWeeklyDistance

        var title: String {
            switch self {
            case .fastestKilometer: return "Fastest 1K"
            case .fastestMile: return "Fastest Mile"
            case .fastestFiveKilometer: return "Fastest 5K"
            case .longestRun: return "Longest Run"
            case .mostElevation: return "Most Elevation"
            case .bestWeeklyDistance: return "Best Week"
            }
        }
    }

    enum Source: Equatable {
        case routeWindow
        case wholeActivityFallback
        case activitySummary
        case weeklyTotal
    }

    let kind: Kind
    let activityID: String?
    let activityTitle: String?
    let date: Date
    let durationSeconds: Int?
    let distanceMeters: Double?
    let elevationMeters: Double?
    let source: Source

    var id: String {
        "\(kind.rawValue)-\(activityID ?? date.timeIntervalSince1970.description)"
    }
}

enum ProgressStatsEngine {
    private static let minimumDurationSeconds = 60

    static func snapshot(
        from activities: [ProgressActivity],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ProgressStatsSnapshot {
        let eligible = activities
            .filter { $0.durationSeconds > minimumDurationSeconds }
            .sorted { $0.startedAt > $1.startedAt }

        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now)
            ?? DateInterval(start: now, duration: 7 * 24 * 60 * 60)
        let currentWeekActivities = eligible.filter { weekInterval.contains($0.startedAt) }
        let buckets = weeklyBuckets(from: eligible, now: now, calendar: calendar)

        return ProgressStatsSnapshot(
            currentWeek: totals(for: currentWeekActivities),
            weeklyBuckets: buckets,
            bestEfforts: bestEfforts(from: eligible, weeklyBuckets: buckets),
            momentumNote: momentumNote(
                from: eligible,
                currentWeekActivities: currentWeekActivities,
                now: now,
                calendar: calendar
            ),
            eligibleActivityCount: eligible.count
        )
    }

    private static func totals(for activities: [ProgressActivity]) -> ProgressPeriodTotals {
        ProgressPeriodTotals(
            activityCount: activities.count,
            distanceMeters: activities.reduce(0) { $0 + max(0, $1.distanceMeters) },
            durationSeconds: activities.reduce(0) { $0 + max(0, $1.durationSeconds) },
            elevationMeters: activities.reduce(0) { $0 + max(0, $1.elevationGainMeters ?? 0) }
        )
    }

    private static func weeklyBuckets(
        from activities: [ProgressActivity],
        now: Date,
        calendar: Calendar
    ) -> [ProgressWeekBucket] {
        let currentStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        return (0..<4).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentStart),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else {
                return nil
            }
            let interval = DateInterval(start: start, end: end)
            let weekActivities = activities.filter { interval.contains($0.startedAt) }
            let totals = totals(for: weekActivities)
            return ProgressWeekBucket(
                id: start,
                startDate: start,
                endDate: end,
                activityCount: totals.activityCount,
                distanceMeters: totals.distanceMeters,
                durationSeconds: totals.durationSeconds,
                elevationMeters: totals.elevationMeters
            )
        }
    }

    private static func bestEfforts(
        from activities: [ProgressActivity],
        weeklyBuckets: [ProgressWeekBucket]
    ) -> [ProgressBestEffort] {
        var efforts: [ProgressBestEffort] = []

        if let fastestK = fastestEffort(kind: .fastestKilometer, targetMeters: 1_000, activities: activities) {
            efforts.append(fastestK)
        }
        if let fastestMile = fastestEffort(kind: .fastestMile, targetMeters: 1_609.344, activities: activities) {
            efforts.append(fastestMile)
        }
        if let fastestFiveK = fastestEffort(kind: .fastestFiveKilometer, targetMeters: 5_000, activities: activities) {
            efforts.append(fastestFiveK)
        }
        if let longest = activities.max(by: { $0.distanceMeters < $1.distanceMeters }) {
            efforts.append(
                ProgressBestEffort(
                    kind: .longestRun,
                    activityID: longest.id,
                    activityTitle: longest.title,
                    date: longest.startedAt,
                    durationSeconds: longest.durationSeconds,
                    distanceMeters: longest.distanceMeters,
                    elevationMeters: longest.elevationGainMeters,
                    source: .activitySummary
                )
            )
        }
        if let hilliest = activities.max(by: { ($0.elevationGainMeters ?? 0) < ($1.elevationGainMeters ?? 0) }),
           (hilliest.elevationGainMeters ?? 0) > 0 {
            efforts.append(
                ProgressBestEffort(
                    kind: .mostElevation,
                    activityID: hilliest.id,
                    activityTitle: hilliest.title,
                    date: hilliest.startedAt,
                    durationSeconds: hilliest.durationSeconds,
                    distanceMeters: hilliest.distanceMeters,
                    elevationMeters: hilliest.elevationGainMeters,
                    source: .activitySummary
                )
            )
        }
        if let bestWeek = weeklyBuckets.max(by: { $0.distanceMeters < $1.distanceMeters }),
           bestWeek.distanceMeters > 0 {
            efforts.append(
                ProgressBestEffort(
                    kind: .bestWeeklyDistance,
                    activityID: nil,
                    activityTitle: "Week of \(bestWeek.startDate.formatted(date: .abbreviated, time: .omitted))",
                    date: bestWeek.startDate,
                    durationSeconds: bestWeek.durationSeconds,
                    distanceMeters: bestWeek.distanceMeters,
                    elevationMeters: bestWeek.elevationMeters,
                    source: .weeklyTotal
                )
            )
        }

        return efforts
    }

    private static func fastestEffort(
        kind: ProgressBestEffort.Kind,
        targetMeters: Double,
        activities: [ProgressActivity]
    ) -> ProgressBestEffort? {
        let routeWindow = activities.compactMap { activity in
            fastestRouteWindow(in: activity, targetMeters: targetMeters).map { duration in
                ProgressBestEffort(
                    kind: kind,
                    activityID: activity.id,
                    activityTitle: activity.title,
                    date: activity.startedAt,
                    durationSeconds: duration,
                    distanceMeters: targetMeters,
                    elevationMeters: nil,
                    source: .routeWindow
                )
            }
        }
        if let best = routeWindow.min(by: effortSort) {
            return best
        }

        return activities
            .filter { $0.distanceMeters >= targetMeters && $0.durationSeconds > 0 }
            .map { activity in
                let estimatedSeconds = Int((Double(activity.durationSeconds) * targetMeters / activity.distanceMeters).rounded())
                return ProgressBestEffort(
                    kind: kind,
                    activityID: activity.id,
                    activityTitle: activity.title,
                    date: activity.startedAt,
                    durationSeconds: estimatedSeconds,
                    distanceMeters: targetMeters,
                    elevationMeters: nil,
                    source: .wholeActivityFallback
                )
            }
            .min(by: effortSort)
    }

    private static func momentumNote(
        from activities: [ProgressActivity],
        currentWeekActivities: [ProgressActivity],
        now: Date,
        calendar: Calendar
    ) -> ProgressMomentumNote? {
        guard let latest = activities.first else { return nil }

        if calendar.isDate(latest.startedAt, inSameDayAs: now) {
            return ProgressMomentumNote(
                text: "You showed up today",
                symbolName: "checkmark.circle.fill"
            )
        }

        if daysSince(date: latest.startedAt, now: now, calendar: calendar) >= 2 {
            return ProgressMomentumNote(
                text: "Back after a rest window",
                symbolName: "arrow.clockwise"
            )
        }

        if currentWeekActivities.count >= 3 {
            return ProgressMomentumNote(
                text: "You are building rhythm",
                symbolName: "waveform.path.ecg"
            )
        }

        if latest.durationSeconds <= 15 * 60 {
            return ProgressMomentumNote(
                text: "Short sessions still count",
                symbolName: "bolt.heart"
            )
        }

        if currentWeekActivities.count > 0 {
            return ProgressMomentumNote(
                text: "\(currentWeekActivities.count) activit\(currentWeekActivities.count == 1 ? "y" : "ies") this week",
                symbolName: "calendar"
            )
        }

        return ProgressMomentumNote(
            text: "Keep the day simple",
            symbolName: "sun.max"
        )
    }

    private static func fastestRouteWindow(in activity: ProgressActivity, targetMeters: Double) -> Int? {
        let points = activity.routePoints
            .filter { $0.cumulativeDistanceMeters.isFinite }
            .sorted { $0.timestamp < $1.timestamp }
        guard points.count >= 2,
              let firstDistance = points.first?.cumulativeDistanceMeters,
              let lastDistance = points.last?.cumulativeDistanceMeters,
              lastDistance - firstDistance >= targetMeters else {
            return nil
        }

        var bestDuration: TimeInterval?
        var endIndex = 0

        for startIndex in points.indices {
            let targetDistance = points[startIndex].cumulativeDistanceMeters + targetMeters
            while endIndex < points.count, points[endIndex].cumulativeDistanceMeters < targetDistance {
                endIndex += 1
            }
            guard endIndex < points.count else { break }

            let duration = points[endIndex].timestamp.timeIntervalSince(points[startIndex].timestamp)
            guard duration > 0 else { continue }
            if bestDuration == nil || duration < bestDuration! {
                bestDuration = duration
            }
        }

        return bestDuration.map { Int($0.rounded()) }
    }

    private static func daysSince(date: Date, now: Date, calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: date)
        let end = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    nonisolated private static func effortSort(_ lhs: ProgressBestEffort, _ rhs: ProgressBestEffort) -> Bool {
        let lhsDuration = lhs.durationSeconds ?? Int.max
        let rhsDuration = rhs.durationSeconds ?? Int.max
        if lhsDuration != rhsDuration {
            return lhsDuration < rhsDuration
        }
        return lhs.date > rhs.date
    }
}
