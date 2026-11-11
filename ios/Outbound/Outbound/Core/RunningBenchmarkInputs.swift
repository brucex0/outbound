import Foundation

/// Keep the user's local Gregorian calendar day when editing the date in UTC.
func benchmarkNewReportDate(now: Date = Date(), timeZone: TimeZone = .current) -> Date {
    var local = Calendar(identifier: .gregorian); local.timeZone = timeZone
    var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
    return utc.date(from: local.dateComponents([.year, .month, .day], from: now)) ?? now
}

func benchmarkLogicalDateLabel(_ value: String, locale: Locale = .autoupdatingCurrent) -> String? {
    let parser = ISO8601DateFormatter(); parser.formatOptions = [.withFullDate]; parser.timeZone = TimeZone(secondsFromGMT: 0)
    guard let date = parser.date(from: value) else { return nil }
    let formatter = DateFormatter(); formatter.locale = locale; formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateStyle = .medium
    return formatter.string(from: date)
}

func benchmarkDurationSeconds(_ value: String) -> Int? {
    let raw = value.split(separator: ":", omittingEmptySubsequences: false)
    guard raw.count == 3 else { return nil }
    let parsed = raw.map { Int($0) }
    guard parsed.allSatisfy({ $0 != nil }) else { return nil }
    let parts = parsed.map { $0! }
    guard (0...24).contains(parts[0]), (0...59).contains(parts[1]), (0...59).contains(parts[2]) else { return nil }
    let result = parts[0] * 3600 + parts[1] * 60 + parts[2]
    return (1...86400).contains(result) ? result : nil
}
