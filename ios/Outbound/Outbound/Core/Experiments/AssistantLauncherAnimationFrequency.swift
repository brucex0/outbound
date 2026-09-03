import Foundation

/// Local-only daily frequency cap for the assistant launcher animation.
struct AssistantLauncherAnimationFrequency {
    private static let lastEligibleDayKey = "assistant_launcher_sparkle_last_eligible_day_v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Returns true only for the first eligible launcher presentation in the current local day.
    func claimFirstEligiblePresentation(on date: Date = Date(), calendar: Calendar = .current) -> Bool {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return false
        }

        let localDay = "\(year)-\(month)-\(day)"
        guard defaults.string(forKey: Self.lastEligibleDayKey) != localDay else { return false }
        defaults.set(localDay, forKey: Self.lastEligibleDayKey)
        return true
    }
}
