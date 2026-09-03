import Foundation

enum AssistantLauncherExperimentVariant: String, Sendable {
    case control
    case treatment
}

/// Local-only assignment and daily frequency cap for the assistant launcher experiment.
struct AssistantLauncherExperiment {
    private static let variantKey = "assistant_launcher_sparkle_variant_v1"
    private static let lastEligibleDayKey = "assistant_launcher_sparkle_last_eligible_day_v1"

    let variant: AssistantLauncherExperimentVariant

    private let defaults: UserDefaults

    init(
        defaults: UserDefaults = .standard,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        self.defaults = defaults

        #if DEBUG
        if let flagIndex = arguments.firstIndex(of: "-AssistantLauncherExperimentVariant"),
           arguments.indices.contains(flagIndex + 1),
           let forcedVariant = AssistantLauncherExperimentVariant(rawValue: arguments[flagIndex + 1]) {
            variant = forcedVariant
            return
        }
        #endif

        if let storedValue = defaults.string(forKey: Self.variantKey),
           let storedVariant = AssistantLauncherExperimentVariant(rawValue: storedValue) {
            variant = storedVariant
        } else {
            let assignedVariant: AssistantLauncherExperimentVariant = Bool.random() ? .control : .treatment
            defaults.set(assignedVariant.rawValue, forKey: Self.variantKey)
            variant = assignedVariant
        }
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
