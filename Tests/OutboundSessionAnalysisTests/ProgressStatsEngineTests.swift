import Foundation
import Testing
@testable import OutboundSessionAnalysis

struct ProgressStatsEngineTests {
    @Test func computesCurrentWeekTotalsAndFourWeekBuckets() {
        let calendar = Calendar(identifier: .gregorian)
        let now = date(2026, 6, 10, 12)
        let activities = [
            activity(id: "current-a", startedAt: date(2026, 6, 8, 8), duration: 1_800, distance: 5_000, elevation: 20),
            activity(id: "current-b", startedAt: date(2026, 6, 10, 8), duration: 2_400, distance: 7_000, elevation: 45),
            activity(id: "prior", startedAt: date(2026, 6, 3, 8), duration: 1_200, distance: 3_000, elevation: 10)
        ]

        let snapshot = ProgressStatsEngine.snapshot(
            from: activities,
            now: now,
            calendar: calendar
        )

        #expect(snapshot.currentWeek.activityCount == 2)
        #expect(snapshot.currentWeek.distanceMeters == 12_000)
        #expect(snapshot.currentWeek.durationSeconds == 4_200)
        #expect(snapshot.currentWeek.elevationMeters == 65)
        #expect(snapshot.currentWeek.averagePaceSecondsPerKilometer == 350)
        #expect(snapshot.weeklyBuckets.count == 4)
        #expect(snapshot.weeklyBuckets.last?.distanceMeters == 12_000)
    }

    @Test func computesRouteBasedFastestEffortsAndWholeActivityFallbacks() {
        let calendar = Calendar(identifier: .gregorian)
        let now = date(2026, 6, 10, 12)
        let routeActivity = activity(
            id: "route",
            startedAt: date(2026, 6, 9, 8),
            duration: 1_500,
            distance: 4_000,
            elevation: 12,
            route: route(
                start: date(2026, 6, 9, 8),
                metersPerPoint: 1_000,
                secondsPerPoint: 300,
                count: 5
            )
        )
        let fallbackActivity = activity(
            id: "fallback",
            startedAt: date(2026, 6, 8, 8),
            duration: 1_500,
            distance: 5_000,
            elevation: 8
        )

        let snapshot = ProgressStatsEngine.snapshot(
            from: [fallbackActivity, routeActivity],
            now: now,
            calendar: calendar
        )

        let kilometer = snapshot.bestEfforts.first { $0.kind == .fastestKilometer }
        let fiveK = snapshot.bestEfforts.first { $0.kind == .fastestFiveKilometer }

        #expect(kilometer?.durationSeconds == 300)
        #expect(kilometer?.source == .routeWindow)
        #expect(fiveK?.durationSeconds == 1_500)
        #expect(fiveK?.source == .wholeActivityFallback)
    }

    @Test func reportsLongestRunAndBestWeek() {
        let calendar = Calendar(identifier: .gregorian)
        let now = date(2026, 6, 10, 12)
        let activities = [
            activity(id: "older-a", startedAt: date(2026, 5, 26, 8), duration: 3_000, distance: 9_000, elevation: 20),
            activity(id: "older-b", startedAt: date(2026, 5, 27, 8), duration: 2_000, distance: 6_000, elevation: 20),
            activity(id: "current", startedAt: date(2026, 6, 10, 8), duration: 2_600, distance: 8_000, elevation: 18)
        ]

        let snapshot = ProgressStatsEngine.snapshot(
            from: activities,
            now: now,
            calendar: calendar
        )

        let longest = snapshot.bestEfforts.first { $0.kind == .longestRun }
        let bestWeek = snapshot.bestEfforts.first { $0.kind == .bestWeeklyDistance }

        #expect(longest?.distanceMeters == 9_000)
        #expect(longest?.activityID == "older-a")
        #expect(bestWeek?.distanceMeters == 15_000)
    }

    @Test func derivesMomentumNoteForCompletedToday() {
        let calendar = Calendar(identifier: .gregorian)
        let now = date(2026, 6, 10, 12)
        let activities = [
            activity(id: "today", startedAt: date(2026, 6, 10, 8), duration: 1_200, distance: 3_000, elevation: 8),
            activity(id: "prior", startedAt: date(2026, 6, 9, 8), duration: 1_400, distance: 4_000, elevation: 10)
        ]

        let snapshot = ProgressStatsEngine.snapshot(
            from: activities,
            now: now,
            calendar: calendar
        )

        #expect(snapshot.momentumNote?.text == "You showed up today")
        #expect(snapshot.momentumNote?.symbolName == "checkmark.circle.fill")
    }

    @Test func derivesMomentumNoteForComebackWindow() {
        let calendar = Calendar(identifier: .gregorian)
        let now = date(2026, 6, 10, 12)
        let activities = [
            activity(id: "older", startedAt: date(2026, 6, 6, 8), duration: 1_800, distance: 5_000, elevation: 18)
        ]

        let snapshot = ProgressStatsEngine.snapshot(
            from: activities,
            now: now,
            calendar: calendar
        )

        #expect(snapshot.momentumNote?.text == "Back after a rest window")
        #expect(snapshot.momentumNote?.symbolName == "arrow.clockwise")
    }

    @Test func reportsPersonalRecordsForCommonDistances() {
        let calendar = Calendar(identifier: .gregorian)
        let now = date(2026, 6, 10, 12)
        let routeActivity = activity(
            id: "route-pr",
            startedAt: date(2026, 6, 9, 8),
            duration: 2_000,
            distance: 5_000,
            elevation: 20,
            route: route(
                start: date(2026, 6, 9, 8),
                metersPerPoint: 1_000,
                secondsPerPoint: 300,
                count: 6
            )
        )

        let snapshot = ProgressStatsEngine.snapshot(
            from: [routeActivity],
            now: now,
            calendar: calendar
        )

        #expect(snapshot.personalRecords.contains { $0.title == "1K" && $0.effort.durationSeconds == 300 })
        #expect(snapshot.personalRecords.contains { $0.title == "5K" && $0.effort.durationSeconds == 1_500 })
    }

    @Test func derivesRacePredictionsFromBestRecentRecord() {
        let calendar = Calendar(identifier: .gregorian)
        let now = date(2026, 6, 10, 12)
        let activities = [
            activity(id: "five-k", startedAt: date(2026, 6, 9, 8), duration: 1_500, distance: 5_000, elevation: 20),
            activity(id: "easy-a", startedAt: date(2026, 6, 7, 8), duration: 1_800, distance: 4_000, elevation: 10),
            activity(id: "easy-b", startedAt: date(2026, 6, 5, 8), duration: 1_900, distance: 4_200, elevation: 8),
            activity(id: "easy-c", startedAt: date(2026, 6, 3, 8), duration: 1_700, distance: 3_800, elevation: 8),
            activity(id: "easy-d", startedAt: date(2026, 6, 1, 8), duration: 1_600, distance: 3_600, elevation: 8)
        ]

        let snapshot = ProgressStatsEngine.snapshot(
            from: activities,
            now: now,
            calendar: calendar
        )

        let tenK = snapshot.racePredictions.first { $0.title == "10K" }
        #expect(tenK?.confidence == .medium)
        #expect((2_900...3_200).contains(tenK?.predictedSeconds ?? 0))
    }

    @Test func comparesPartialWeekAndMonthAtMatchingElapsedTime() {
        let calendar = Calendar(identifier: .gregorian)
        let now = date(2026, 6, 10, 12)
        let activities = [
            activity(id: "current", startedAt: date(2026, 6, 9, 8), duration: 1_800, distance: 5_000, elevation: 10),
            activity(id: "matched-prior", startedAt: date(2026, 6, 2, 8), duration: 1_500, distance: 4_000, elevation: 8),
            activity(id: "later-prior", startedAt: date(2026, 6, 5, 8), duration: 2_000, distance: 6_000, elevation: 12),
            activity(id: "matched-month", startedAt: date(2026, 5, 6, 8), duration: 1_200, distance: 3_000, elevation: 6),
            activity(id: "later-month", startedAt: date(2026, 5, 20, 8), duration: 2_400, distance: 7_000, elevation: 14)
        ]

        let snapshot = ProgressStatsEngine.snapshot(from: activities, now: now, calendar: calendar)
        let week = snapshot.comparisons.first { $0.kind == .week }
        let month = snapshot.comparisons.first { $0.kind == .month }

        #expect(week?.current.distanceMeters == 5_000)
        #expect(week?.previous.distanceMeters == 4_000)
        #expect(month?.previous.distanceMeters == 3_000)
    }

    @Test func buildsEverySupportedTrendRange() {
        let snapshot = ProgressStatsEngine.snapshot(
            from: [activity(id: "run", startedAt: date(2026, 6, 9, 8), duration: 1_800, distance: 5_000, elevation: 10)],
            now: date(2026, 6, 10, 12),
            calendar: Calendar(identifier: .gregorian)
        )

        #expect(snapshot.trendSeries.first { $0.range == .fourWeeks }?.buckets.count == 4)
        #expect(snapshot.trendSeries.first { $0.range == .threeMonths }?.buckets.count == 13)
        #expect(snapshot.trendSeries.first { $0.range == .sixMonths }?.buckets.count == 6)
        #expect(snapshot.trendSeries.first { $0.range == .oneYear }?.buckets.count == 12)
    }

    @Test func derivesHeartRateEfficiencyOnlyForComparableRunningWindows() {
        let calendar = Calendar(identifier: .gregorian)
        let now = date(2026, 6, 30, 12)
        let activities = [
            activity(id: "new-a", startedAt: date(2026, 6, 25, 8), duration: 1_500, distance: 5_000, elevation: 5, heartRate: 150),
            activity(id: "new-b", startedAt: date(2026, 6, 15, 8), duration: 1_500, distance: 5_000, elevation: 5, heartRate: 151),
            activity(id: "old-a", startedAt: date(2026, 5, 25, 8), duration: 1_600, distance: 5_000, elevation: 5, heartRate: 149),
            activity(id: "old-b", startedAt: date(2026, 5, 15, 8), duration: 1_600, distance: 5_000, elevation: 5, heartRate: 150)
        ]

        let snapshot = ProgressStatsEngine.snapshot(from: activities, now: now, calendar: calendar)
        let insight = snapshot.insights.first { $0.category == .efficiency }

        guard let evidence = insight?.evidence,
              case .heartRateEfficiency(let pacePercent, let heartRateDifference) = evidence else {
            Issue.record("Expected a heart-rate efficiency insight")
            return
        }
        #expect(pacePercent == 6)
        #expect(abs(heartRateDifference) <= 5)
    }

    @Test func requiresHeartRateZonesBeforeProducingLoadAndBalanceInsights() {
        let calendar = Calendar(identifier: .gregorian)
        let now = date(2026, 6, 30, 12)
        let activities = (0..<6).map { offset in
            activity(
                id: "zoned-\(offset)",
                startedAt: date(2026, 6, 29 - offset * 3, 8),
                duration: 1_800,
                distance: 5_000,
                elevation: 5,
                heartRate: 150,
                zones: [2: 1_200, 4: 600]
            )
        }

        let withZones = ProgressStatsEngine.snapshot(from: activities, now: now, calendar: calendar)
        let withoutZones = ProgressStatsEngine.snapshot(
            from: activities.map {
                activity(id: $0.id, startedAt: $0.startedAt, duration: $0.durationSeconds, distance: $0.distanceMeters, elevation: $0.elevationGainMeters)
            },
            now: now,
            calendar: calendar
        )

        #expect(withZones.insights.contains { $0.category == .trainingBalance })
        #expect(!withoutZones.insights.contains { [.trainingLoad, .trainingBalance].contains($0.category) })
    }
}

private func activity(
    id: String,
    startedAt: Date,
    duration: Int,
    distance: Double,
    elevation: Double?,
    route: [ProgressRoutePoint] = [],
    heartRate: Int? = nil,
    zones: [Int: Int] = [:]
) -> ProgressActivity {
    ProgressActivity(
        id: id,
        title: id,
        startedAt: startedAt,
        durationSeconds: duration,
        distanceMeters: distance,
        elevationGainMeters: elevation,
        averageHeartRate: heartRate,
        routePoints: route,
        heartRateZoneSeconds: zones
    )
}

private func route(
    start: Date,
    metersPerPoint: Double,
    secondsPerPoint: Int,
    count: Int
) -> [ProgressRoutePoint] {
    (0..<count).map { index in
        ProgressRoutePoint(
            timestamp: start.addingTimeInterval(TimeInterval(index * secondsPerPoint)),
            cumulativeDistanceMeters: Double(index) * metersPerPoint
        )
    }
}

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
    DateComponents(
        calendar: Calendar(identifier: .gregorian),
        timeZone: TimeZone(secondsFromGMT: 0),
        year: year,
        month: month,
        day: day,
        hour: hour
    ).date!
}
