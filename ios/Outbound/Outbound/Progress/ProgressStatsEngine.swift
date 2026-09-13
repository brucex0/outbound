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
    let activityType: String
    let goalCompleted: Bool?
    let heartRateZoneSeconds: [Int: Int]

    init(
        id: String,
        title: String,
        startedAt: Date,
        durationSeconds: Int,
        distanceMeters: Double,
        elevationGainMeters: Double?,
        averageHeartRate: Int?,
        routePoints: [ProgressRoutePoint],
        activityType: String = "running",
        goalCompleted: Bool? = nil,
        heartRateZoneSeconds: [Int: Int] = [:]
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.elevationGainMeters = elevationGainMeters
        self.averageHeartRate = averageHeartRate
        self.routePoints = routePoints
        self.activityType = activityType
        self.goalCompleted = goalCompleted
        self.heartRateZoneSeconds = heartRateZoneSeconds
    }
}

struct ProgressRoutePoint: Equatable {
    let timestamp: Date
    let cumulativeDistanceMeters: Double
}

struct ProgressStatsSnapshot: Equatable {
    let currentWeek: ProgressPeriodTotals
    let weeklyBuckets: [ProgressWeekBucket]
    let comparisons: [ProgressPeriodComparison]
    let trendSeries: [ProgressTrendSeries]
    let trainingLoad: ProgressTrainingLoadSnapshot
    let insights: [ProgressInsight]
    let bestEfforts: [ProgressBestEffort]
    let personalRecords: [ProgressPersonalRecord]
    let racePredictions: [ProgressRacePrediction]
    let momentumNote: ProgressMomentumNote?
    let eligibleActivityCount: Int

    var guideNote: String {
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

enum ProgressMetric: String, CaseIterable, Identifiable, Equatable {
    case distance
    case duration
    case activities
    case elevation
    case averagePace

    var id: Self { self }
}

struct ProgressMetricDelta: Equatable {
    let current: Double
    let previous: Double

    var percent: Double? {
        guard previous > 0 else { return nil }
        return ((current - previous) / previous) * 100
    }
}

struct ProgressPeriodComparison: Identifiable, Equatable {
    enum Kind: String, CaseIterable, Equatable {
        case week
        case month
        case rolling28Days
    }

    let kind: Kind
    let currentStart: Date
    let currentEnd: Date
    let previousStart: Date
    let previousEnd: Date
    let current: ProgressPeriodTotals
    let previous: ProgressPeriodTotals

    var id: String { kind.rawValue }

    func delta(for metric: ProgressMetric) -> ProgressMetricDelta? {
        guard let currentValue = current.value(for: metric),
              let previousValue = previous.value(for: metric) else {
            return nil
        }
        return ProgressMetricDelta(current: currentValue, previous: previousValue)
    }
}

enum ProgressTrendRange: String, CaseIterable, Identifiable, Equatable {
    case fourWeeks
    case threeMonths
    case sixMonths
    case oneYear

    var id: Self { self }
}

struct ProgressTrendSeries: Identifiable, Equatable {
    let range: ProgressTrendRange
    let buckets: [ProgressTrendBucket]

    var id: ProgressTrendRange { range }
}

struct ProgressTrendBucket: Identifiable, Equatable {
    let startDate: Date
    let endDate: Date
    let totals: ProgressPeriodTotals

    var id: Date { startDate }
}

struct ProgressTrainingLoadSnapshot: Equatable {
    let currentSevenDays: Double
    let previousSevenDays: Double
    let rampPercent: Double?
    let highIntensityPercent: Double?
    let heartRateActivityCount: Int
}

enum ProgressInsightConfidence: String, Equatable {
    case emerging
    case solid
    case strong
}

enum ProgressInsightCategory: String, Equatable {
    case volume
    case consistency
    case endurance
    case efficiency
    case trainingLoad
    case trainingBalance
    case goals
    case pattern
}

enum ProgressDayPart: String, Hashable {
    case morning
    case afternoon
    case evening
}

enum ProgressInsightEvidence: Equatable {
    case rollingDistance(percent: Int, currentMeters: Double, previousMeters: Double)
    case activeWeeks(count: Int, total: Int)
    case longRunShare(percent: Int, longRunMeters: Double, weekMeters: Double)
    case heartRateEfficiency(pacePercent: Int, heartRateDifference: Int)
    case loadRamp(percent: Int, current: Double, previous: Double)
    case intensityBalance(highIntensityPercent: Int)
    case goalCompletion(completed: Int, total: Int)
    case preferredTime(dayPart: ProgressDayPart, percent: Int, total: Int)
}

struct ProgressInsight: Identifiable, Equatable {
    let id: String
    let category: ProgressInsightCategory
    let confidence: ProgressInsightConfidence
    let symbolName: String
    let evidence: ProgressInsightEvidence
}

struct ProgressMomentumNote: Equatable {
    let text: String
    let symbolName: String
}

struct ProgressPersonalRecord: Identifiable, Equatable {
    let title: String
    let targetMeters: Double
    let effort: ProgressBestEffort

    var id: String { "\(Int(targetMeters.rounded()))-\(effort.id)" }
}

struct ProgressRacePrediction: Identifiable, Equatable {
    enum Confidence: String, Equatable {
        case low
        case medium
        case high

        var title: String { rawValue.capitalized }
    }

    let title: String
    let targetMeters: Double
    let predictedSeconds: Int
    let confidence: Confidence

    var id: String { title }
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

    func value(for metric: ProgressMetric) -> Double? {
        switch metric {
        case .distance: distanceMeters
        case .duration: Double(durationSeconds)
        case .activities: Double(activityCount)
        case .elevation: elevationMeters
        case .averagePace: averagePaceSecondsPerKilometer
        }
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
        let runningActivities = eligible.filter { $0.activityType == "running" }
        let runningBuckets = weeklyBuckets(from: runningActivities, now: now, calendar: calendar)
        let comparisons = periodComparisons(from: eligible, now: now, calendar: calendar)
        let trendSeries = ProgressTrendRange.allCases.map {
            ProgressTrendSeries(
                range: $0,
                buckets: trendBuckets(from: eligible, range: $0, now: now, calendar: calendar)
            )
        }
        let trainingLoad = trainingLoadSnapshot(from: eligible, now: now, calendar: calendar)

        return ProgressStatsSnapshot(
            currentWeek: totals(for: currentWeekActivities),
            weeklyBuckets: buckets,
            comparisons: comparisons,
            trendSeries: trendSeries,
            trainingLoad: trainingLoad,
            insights: insights(
                from: eligible,
                currentWeekActivities: currentWeekActivities,
                comparisons: comparisons,
                trainingLoad: trainingLoad,
                now: now,
                calendar: calendar
            ),
            bestEfforts: bestEfforts(from: runningActivities, weeklyBuckets: runningBuckets),
            personalRecords: personalRecords(from: runningActivities),
            racePredictions: racePredictions(from: runningActivities, now: now, calendar: calendar),
            momentumNote: momentumNote(
                from: eligible,
                currentWeekActivities: currentWeekActivities,
                now: now,
                calendar: calendar
            ),
            eligibleActivityCount: eligible.count
        )
    }

    private static func periodComparisons(
        from activities: [ProgressActivity],
        now: Date,
        calendar: Calendar
    ) -> [ProgressPeriodComparison] {
        [
            matchedCalendarComparison(
                kind: .week,
                component: .weekOfYear,
                activities: activities,
                now: now,
                calendar: calendar
            ),
            matchedCalendarComparison(
                kind: .month,
                component: .month,
                activities: activities,
                now: now,
                calendar: calendar
            ),
            rollingComparison(activities: activities, now: now, calendar: calendar)
        ].compactMap { $0 }
    }

    private static func matchedCalendarComparison(
        kind: ProgressPeriodComparison.Kind,
        component: Calendar.Component,
        activities: [ProgressActivity],
        now: Date,
        calendar: Calendar
    ) -> ProgressPeriodComparison? {
        guard let currentInterval = calendar.dateInterval(of: component, for: now),
              let previousStart = calendar.date(byAdding: component, value: -1, to: currentInterval.start),
              let previousFullInterval = calendar.dateInterval(of: component, for: previousStart) else {
            return nil
        }

        let currentEnd = min(now.addingTimeInterval(1), currentInterval.end)
        let elapsed = currentEnd.timeIntervalSince(currentInterval.start)
        let previousEnd = min(previousStart.addingTimeInterval(elapsed), previousFullInterval.end)
        let currentActivities = filteredActivities(in: DateInterval(start: currentInterval.start, end: currentEnd), from: activities)
        let previousActivities = filteredActivities(in: DateInterval(start: previousStart, end: previousEnd), from: activities)

        return ProgressPeriodComparison(
            kind: kind,
            currentStart: currentInterval.start,
            currentEnd: currentEnd,
            previousStart: previousStart,
            previousEnd: previousEnd,
            current: totals(for: currentActivities),
            previous: totals(for: previousActivities)
        )
    }

    private static func rollingComparison(
        activities: [ProgressActivity],
        now: Date,
        calendar: Calendar
    ) -> ProgressPeriodComparison? {
        let currentEnd = now.addingTimeInterval(1)
        guard let currentStart = calendar.date(byAdding: .day, value: -28, to: currentEnd),
              let previousStart = calendar.date(byAdding: .day, value: -28, to: currentStart) else {
            return nil
        }
        let currentActivities = filteredActivities(in: DateInterval(start: currentStart, end: currentEnd), from: activities)
        let previousActivities = filteredActivities(in: DateInterval(start: previousStart, end: currentStart), from: activities)
        return ProgressPeriodComparison(
            kind: .rolling28Days,
            currentStart: currentStart,
            currentEnd: currentEnd,
            previousStart: previousStart,
            previousEnd: currentStart,
            current: totals(for: currentActivities),
            previous: totals(for: previousActivities)
        )
    }

    private static func trendBuckets(
        from activities: [ProgressActivity],
        range: ProgressTrendRange,
        now: Date,
        calendar: Calendar
    ) -> [ProgressTrendBucket] {
        switch range {
        case .fourWeeks:
            return fixedBuckets(
                from: activities,
                count: 4,
                component: .weekOfYear,
                now: now,
                calendar: calendar
            )
        case .threeMonths:
            return fixedBuckets(
                from: activities,
                count: 13,
                component: .weekOfYear,
                now: now,
                calendar: calendar
            )
        case .sixMonths:
            return fixedBuckets(
                from: activities,
                count: 6,
                component: .month,
                now: now,
                calendar: calendar
            )
        case .oneYear:
            return fixedBuckets(
                from: activities,
                count: 12,
                component: .month,
                now: now,
                calendar: calendar
            )
        }
    }

    private static func fixedBuckets(
        from activities: [ProgressActivity],
        count: Int,
        component: Calendar.Component,
        now: Date,
        calendar: Calendar
    ) -> [ProgressTrendBucket] {
        guard let currentStart = calendar.dateInterval(of: component, for: now)?.start else { return [] }
        var buckets: [ProgressTrendBucket] = []
        for offset in (0..<count).reversed() {
            guard let start = calendar.date(byAdding: component, value: -offset, to: currentStart),
                  let end = calendar.date(byAdding: component, value: 1, to: start) else {
                continue
            }
            buckets.append(ProgressTrendBucket(
                startDate: start,
                endDate: end,
                totals: totals(for: filteredActivities(in: DateInterval(start: start, end: end), from: activities))
            ))
        }
        return buckets
    }

    private static func filteredActivities(
        in interval: DateInterval,
        from activities: [ProgressActivity]
    ) -> [ProgressActivity] {
        activities.filter { interval.contains($0.startedAt) }
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

    private static func trainingLoadSnapshot(
        from activities: [ProgressActivity],
        now: Date,
        calendar: Calendar
    ) -> ProgressTrainingLoadSnapshot {
        let currentEnd = now.addingTimeInterval(1)
        let currentStart = calendar.date(byAdding: .day, value: -7, to: currentEnd) ?? currentEnd
        let previousStart = calendar.date(byAdding: .day, value: -7, to: currentStart) ?? currentStart
        let currentActivities = filteredActivities(in: DateInterval(start: currentStart, end: currentEnd), from: activities)
        let previousActivities = filteredActivities(in: DateInterval(start: previousStart, end: currentStart), from: activities)
        let currentLoad = currentActivities.reduce(0) { $0 + heartRateLoad(for: $1) }
        let previousLoad = previousActivities.reduce(0) { $0 + heartRateLoad(for: $1) }
        let heartRateActivities = activities.filter { !$0.heartRateZoneSeconds.isEmpty }
        let recentHeartRateActivities = filteredActivities(
            in: DateInterval(
                start: calendar.date(byAdding: .day, value: -28, to: currentEnd) ?? currentEnd,
                end: currentEnd
            ),
            from: heartRateActivities
        )
        let totalZoneSeconds = recentHeartRateActivities.reduce(0) { result, activity in
            result + activity.heartRateZoneSeconds.values.reduce(0, +)
        }
        let highIntensitySeconds = recentHeartRateActivities.reduce(0) { result, activity in
            let activityHighIntensitySeconds = activity.heartRateZoneSeconds.reduce(0) { subtotal, entry in
                entry.key >= 4 ? subtotal + entry.value : subtotal
            }
            return result + activityHighIntensitySeconds
        }

        return ProgressTrainingLoadSnapshot(
            currentSevenDays: currentLoad,
            previousSevenDays: previousLoad,
            rampPercent: previousLoad > 0 ? ((currentLoad - previousLoad) / previousLoad) * 100 : nil,
            highIntensityPercent: totalZoneSeconds > 0
                ? (Double(highIntensitySeconds) / Double(totalZoneSeconds)) * 100
                : nil,
            heartRateActivityCount: recentHeartRateActivities.count
        )
    }

    private static func heartRateLoad(for activity: ProgressActivity) -> Double {
        activity.heartRateZoneSeconds.reduce(0) { result, entry in
            let boundedZone = min(max(entry.key, 1), 5)
            return result + (Double(max(entry.value, 0)) / 60) * Double(boundedZone)
        }
    }

    private static func insights(
        from activities: [ProgressActivity],
        currentWeekActivities: [ProgressActivity],
        comparisons: [ProgressPeriodComparison],
        trainingLoad: ProgressTrainingLoadSnapshot,
        now: Date,
        calendar: Calendar
    ) -> [ProgressInsight] {
        var result: [(priority: Int, insight: ProgressInsight)] = []

        if let rolling = comparisons.first(where: { $0.kind == .rolling28Days }),
           rolling.current.activityCount >= 2,
           let change = rolling.delta(for: .distance).flatMap({ $0.percent }),
           rolling.previous.distanceMeters > 0,
           abs(change) >= 8 {
            let confidence: ProgressInsightConfidence = min(
                rolling.current.activityCount,
                rolling.previous.activityCount
            ) >= 5 ? .strong : .solid
            result.append((
                90,
                ProgressInsight(
                    id: "rolling-distance",
                    category: .volume,
                    confidence: confidence,
                    symbolName: change >= 0 ? "chart.line.uptrend.xyaxis" : "arrow.down.right",
                    evidence: .rollingDistance(
                        percent: Int(change.rounded()),
                        currentMeters: rolling.current.distanceMeters,
                        previousMeters: rolling.previous.distanceMeters
                    )
                )
            ))
        }

        let activeWeekCount = activeWeeks(in: 8, activities: activities, now: now, calendar: calendar)
        if activeWeekCount >= 3 {
            result.append((
                activeWeekCount >= 6 ? 88 : 72,
                ProgressInsight(
                    id: "active-weeks",
                    category: .consistency,
                    confidence: activeWeekCount >= 6 ? .strong : .solid,
                    symbolName: "calendar.badge.checkmark",
                    evidence: .activeWeeks(count: activeWeekCount, total: 8)
                )
            ))
        }

        let currentWeekDistance = currentWeekActivities.reduce(0) { $0 + max($1.distanceMeters, 0) }
        if currentWeekActivities.count >= 2,
           currentWeekDistance > 0,
           let longest = currentWeekActivities.max(by: { $0.distanceMeters < $1.distanceMeters }) {
            let share = longest.distanceMeters / currentWeekDistance * 100
            if share >= 25 {
                result.append((
                    share > 50 ? 92 : 68,
                    ProgressInsight(
                        id: "long-run-share",
                        category: .endurance,
                        confidence: currentWeekActivities.count >= 3 ? .solid : .emerging,
                        symbolName: "arrow.left.and.right",
                        evidence: .longRunShare(
                            percent: Int(share.rounded()),
                            longRunMeters: longest.distanceMeters,
                            weekMeters: currentWeekDistance
                        )
                    )
                ))
            }
        }

        if let efficiency = heartRateEfficiency(from: activities, now: now, calendar: calendar) {
            result.append((
                86,
                ProgressInsight(
                    id: "heart-rate-efficiency",
                    category: .efficiency,
                    confidence: efficiency.sampleCount >= 8 ? .strong : .solid,
                    symbolName: efficiency.pacePercent >= 0 ? "heart.text.square.fill" : "waveform.path.ecg",
                    evidence: .heartRateEfficiency(
                        pacePercent: efficiency.pacePercent,
                        heartRateDifference: efficiency.heartRateDifference
                    )
                )
            ))
        }

        if trainingLoad.heartRateActivityCount >= 4,
           trainingLoad.currentSevenDays > 0,
           trainingLoad.previousSevenDays > 0,
           let ramp = trainingLoad.rampPercent,
           abs(ramp) >= 20 {
            result.append((
                abs(ramp) >= 40 ? 96 : 82,
                ProgressInsight(
                    id: "training-load",
                    category: .trainingLoad,
                    confidence: trainingLoad.heartRateActivityCount >= 7 ? .strong : .solid,
                    symbolName: ramp > 0 ? "gauge.with.dots.needle.67percent" : "gauge.with.dots.needle.33percent",
                    evidence: .loadRamp(
                        percent: Int(ramp.rounded()),
                        current: trainingLoad.currentSevenDays,
                        previous: trainingLoad.previousSevenDays
                    )
                )
            ))
        }

        if trainingLoad.heartRateActivityCount >= 3,
           let highIntensity = trainingLoad.highIntensityPercent {
            result.append((
                highIntensity > 30 ? 94 : 64,
                ProgressInsight(
                    id: "intensity-balance",
                    category: .trainingBalance,
                    confidence: trainingLoad.heartRateActivityCount >= 6 ? .strong : .solid,
                    symbolName: "chart.bar.fill",
                    evidence: .intensityBalance(highIntensityPercent: Int(highIntensity.rounded()))
                )
            ))
        }

        let recentGoalActivities = activities.filter {
            daysSince(date: $0.startedAt, now: now, calendar: calendar) <= 28 && $0.goalCompleted != nil
        }
        let completedGoals = recentGoalActivities.filter { $0.goalCompleted == true }.count
        if recentGoalActivities.count >= 3 {
            result.append((
                74,
                ProgressInsight(
                    id: "goal-completion",
                    category: .goals,
                    confidence: recentGoalActivities.count >= 6 ? .strong : .solid,
                    symbolName: "target",
                    evidence: .goalCompletion(completed: completedGoals, total: recentGoalActivities.count)
                )
            ))
        }

        let patternActivities = activities.filter { daysSince(date: $0.startedAt, now: now, calendar: calendar) <= 42 }
        if let preferredTime = preferredDayPart(from: patternActivities, calendar: calendar) {
            result.append((
                56,
                ProgressInsight(
                    id: "preferred-time",
                    category: .pattern,
                    confidence: patternActivities.count >= 10 ? .strong : .solid,
                    symbolName: preferredTime.dayPart == .morning ? "sunrise.fill" : "clock.fill",
                    evidence: .preferredTime(
                        dayPart: preferredTime.dayPart,
                        percent: preferredTime.percent,
                        total: patternActivities.count
                    )
                )
            ))
        }

        return result
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                return lhs.insight.id < rhs.insight.id
            }
            .map(\.insight)
    }

    private static func activeWeeks(
        in count: Int,
        activities: [ProgressActivity],
        now: Date,
        calendar: Calendar
    ) -> Int {
        guard let currentStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return 0 }
        return (0..<count).reduce(0) { result, offset in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentStart),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else {
                return result
            }
            let interval = DateInterval(start: start, end: end)
            return result + (activities.contains(where: { interval.contains($0.startedAt) }) ? 1 : 0)
        }
    }

    private static func heartRateEfficiency(
        from activities: [ProgressActivity],
        now: Date,
        calendar: Calendar
    ) -> (pacePercent: Int, heartRateDifference: Int, sampleCount: Int)? {
        let currentEnd = now.addingTimeInterval(1)
        guard let currentStart = calendar.date(byAdding: .day, value: -28, to: currentEnd),
              let previousStart = calendar.date(byAdding: .day, value: -28, to: currentStart) else {
            return nil
        }
        let comparable = activities.filter {
            $0.activityType == "running"
                && $0.averageHeartRate != nil
                && $0.distanceMeters >= 1_000
                && $0.durationSeconds >= 10 * 60
        }
        let current = filteredActivities(in: DateInterval(start: currentStart, end: currentEnd), from: comparable)
        let previous = filteredActivities(in: DateInterval(start: previousStart, end: currentStart), from: comparable)
        guard current.count >= 2, previous.count >= 2,
              let currentSummary = efficiencySummary(current),
              let previousSummary = efficiencySummary(previous) else {
            return nil
        }
        let heartRateDifference = Int((currentSummary.heartRate - previousSummary.heartRate).rounded())
        guard abs(heartRateDifference) <= 5 else { return nil }
        let pacePercent = Int(((previousSummary.pace - currentSummary.pace) / previousSummary.pace * 100).rounded())
        guard abs(pacePercent) >= 2 else { return nil }
        return (pacePercent, heartRateDifference, current.count + previous.count)
    }

    private static func efficiencySummary(
        _ activities: [ProgressActivity]
    ) -> (pace: Double, heartRate: Double)? {
        let totalDistance = activities.reduce(0) { $0 + $1.distanceMeters }
        let totalDuration = activities.reduce(0) { $0 + $1.durationSeconds }
        guard totalDistance > 0, totalDuration > 0 else { return nil }
        let weightedHeartRate = activities.reduce(0.0) { result, activity in
            result + Double(activity.averageHeartRate ?? 0) * Double(activity.durationSeconds)
        } / Double(totalDuration)
        return (Double(totalDuration) / (totalDistance / 1_000), weightedHeartRate)
    }

    private static func preferredDayPart(
        from activities: [ProgressActivity],
        calendar: Calendar
    ) -> (dayPart: ProgressDayPart, percent: Int)? {
        guard activities.count >= 5 else { return nil }
        var counts: [ProgressDayPart: Int] = [.morning: 0, .afternoon: 0, .evening: 0]
        for activity in activities {
            switch calendar.component(.hour, from: activity.startedAt) {
            case 5..<12: counts[.morning, default: 0] += 1
            case 12..<18: counts[.afternoon, default: 0] += 1
            default: counts[.evening, default: 0] += 1
            }
        }
        guard let dominant = counts.max(by: { $0.value < $1.value }) else { return nil }
        let percent = Int((Double(dominant.value) / Double(activities.count) * 100).rounded())
        guard percent >= 60 else { return nil }
        return (dominant.key, percent)
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

    private static func personalRecords(from activities: [ProgressActivity]) -> [ProgressPersonalRecord] {
        [
            ("400m", 400),
            ("1K", 1_000),
            ("1 mile", 1_609.344),
            ("5K", 5_000),
            ("10K", 10_000),
            ("10 mile", 16_093.44),
            ("Half marathon", 21_097.5),
            ("Marathon", 42_195)
        ].compactMap { title, meters in
            fastestEffort(kind: .fastestKilometer, targetMeters: meters, activities: activities).map {
                ProgressPersonalRecord(title: title, targetMeters: meters, effort: $0)
            }
        }
    }

    private static func racePredictions(
        from activities: [ProgressActivity],
        now: Date,
        calendar: Calendar
    ) -> [ProgressRacePrediction] {
        guard let reference = personalRecords(from: activities)
            .filter({ $0.targetMeters >= 1_000 && $0.targetMeters <= 21_097.5 })
            .compactMap({ record -> (ProgressPersonalRecord, Int)? in
                guard let seconds = record.effort.durationSeconds else { return nil }
                return (record, seconds)
            })
            .min(by: { lhs, rhs in
                let lhsRecency = daysSince(date: lhs.0.effort.date, now: now, calendar: calendar)
                let rhsRecency = daysSince(date: rhs.0.effort.date, now: now, calendar: calendar)
                let lhsScore = lhs.0.targetMeters * (lhsRecency <= 90 ? 1 : 0.75)
                let rhsScore = rhs.0.targetMeters * (rhsRecency <= 90 ? 1 : 0.75)
                return lhsScore > rhsScore
            }) else {
            return []
        }

        let activityCount = activities.count
        let recentCount = activities.filter { daysSince(date: $0.startedAt, now: now, calendar: calendar) <= 42 }.count
        let confidence: ProgressRacePrediction.Confidence
        if activityCount >= 12, recentCount >= 6 {
            confidence = .high
        } else if activityCount >= 5, recentCount >= 3 {
            confidence = .medium
        } else {
            confidence = .low
        }

        return [
            ("5K", 5_000),
            ("10K", 10_000),
            ("Half", 21_097.5),
            ("Marathon", 42_195)
        ].map { title, meters in
            let predicted = Double(reference.1) * pow(meters / reference.0.targetMeters, 1.06)
            return ProgressRacePrediction(
                title: title,
                targetMeters: meters,
                predictedSeconds: Int(predicted.rounded()),
                confidence: confidence
            )
        }
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
