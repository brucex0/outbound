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
}

private func activity(
    id: String,
    startedAt: Date,
    duration: Int,
    distance: Double,
    elevation: Double?,
    route: [ProgressRoutePoint] = []
) -> ProgressActivity {
    ProgressActivity(
        id: id,
        title: id,
        startedAt: startedAt,
        durationSeconds: duration,
        distanceMeters: distance,
        elevationGainMeters: elevation,
        averageHeartRate: nil,
        routePoints: route
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
