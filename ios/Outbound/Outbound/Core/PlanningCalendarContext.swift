import Foundation

/// Account policy. Workout timestamps remain date labels and are never instant-shifted.
struct PlanningCalendarContext: Codable, Equatable {
    let policyVersion: String
    let timeZone: String
    let firstWeekday: Int
    let weekStart: Date
    let weekEnd: Date
    let planStartDate: String?
    let planWeekIndex: Int?
    let isPartialWeek: Bool

    var calendar: Calendar { Self.accountCalendar(timeZone: timeZone) }

    static func accountCalendar(timeZone: String? = nil) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        if let timeZone {
            if let zone = TimeZone(identifier: timeZone) { calendar.timeZone = zone }
            else {
                print("[calendar] account_zone_failed category=invalid_time_zone")
                calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            }
        } else { calendar.timeZone = .current }
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    static func logicalDate(_ label: String, calendar: Calendar) -> Date? {
        let pieces = label.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard pieces.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: pieces[0], month: pieces[1], day: pieces[2]))
    }

    /// Recompute an offline period using the saved account zone, including DST transitions.
    func resolved(at now: Date = Date()) -> Self {
        let calendar = calendar
        let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        let planStart = planStartDate.flatMap { Self.logicalDate($0, calendar: calendar) }
        let planMonday = planStart.flatMap { calendar.dateInterval(of: .weekOfYear, for: $0)?.start }
        let index = planMonday.map { max(1, (calendar.dateComponents([.day], from: $0, to: start).day ?? 0) / 7 + 1) }
        return Self(policyVersion: "monday-v1", timeZone: timeZone, firstWeekday: 2,
                    weekStart: start, weekEnd: end, planStartDate: planStartDate, planWeekIndex: index,
                    isPartialWeek: index == 1 && planStart.map { calendar.component(.weekday, from: $0) != 2 } == true)
    }

    var localizedPeriod: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        let lastDay = calendar.date(byAdding: .day, value: -1, to: weekEnd) ?? weekEnd
        return "\(formatter.string(from: weekStart))–\(formatter.string(from: lastDay))"
    }
}
