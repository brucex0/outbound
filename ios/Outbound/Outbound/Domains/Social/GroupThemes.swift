import Foundation

struct GroupThemeDefinition: Identifiable, Equatable {
    let id: String
    let systemImage: String
    let title: String
    let detail: String
}

enum GroupThemeCatalog {
    static var all: [GroupThemeDefinition] {
        [
            .init(
                id: "build_consistency",
                systemImage: "repeat",
                title: String(localized: "group.theme.build_consistency.title", defaultValue: "Build consistency"),
                detail: String(localized: "group.theme.build_consistency.detail", defaultValue: "Small efforts count. Keep showing up.")
            ),
            .init(
                id: "one_small_step",
                systemImage: "shoeprints.fill",
                title: String(localized: "group.theme.one_small_step.title", defaultValue: "One small step"),
                detail: String(localized: "group.theme.one_small_step.detail", defaultValue: "Make moving feel possible again.")
            ),
            .init(
                id: "keep_the_rhythm",
                systemImage: "waveform.path",
                title: String(localized: "group.theme.keep_the_rhythm.title", defaultValue: "Keep the rhythm"),
                detail: String(localized: "group.theme.keep_the_rhythm.detail", defaultValue: "Carry the momentum into another week.")
            ),
            .init(
                id: "move_for_your_mood",
                systemImage: "sun.max.fill",
                title: String(localized: "group.theme.move_for_your_mood.title", defaultValue: "Move for your mood"),
                detail: String(localized: "group.theme.move_for_your_mood.detail", defaultValue: "Choose movement that helps you feel better.")
            ),
            .init(
                id: "recover_and_recharge",
                systemImage: "leaf.fill",
                title: String(localized: "group.theme.recover_and_recharge.title", defaultValue: "Recover and recharge"),
                detail: String(localized: "group.theme.recover_and_recharge.detail", defaultValue: "Keep it gentle and give your body room to recover.")
            ),
            .init(
                id: "do_something_together",
                systemImage: "person.2.fill",
                title: String(localized: "group.theme.do_something_together.title", defaultValue: "Do something together"),
                detail: String(localized: "group.theme.do_something_together.detail", defaultValue: "Make time to move and connect.")
            ),
            .init(
                id: "explore_somewhere_new",
                systemImage: "map.fill",
                title: String(localized: "group.theme.explore_somewhere_new.title", defaultValue: "Explore somewhere new"),
                detail: String(localized: "group.theme.explore_somewhere_new.detail", defaultValue: "Let curiosity choose the route.")
            ),
            .init(
                id: "try_something_different",
                systemImage: "sparkles",
                title: String(localized: "group.theme.try_something_different.title", defaultValue: "Try something different"),
                detail: String(localized: "group.theme.try_something_different.detail", defaultValue: "Change the routine and discover a new way to move.")
            ),
            .init(
                id: "celebrate_every_effort",
                systemImage: "heart.fill",
                title: String(localized: "group.theme.celebrate_every_effort.title", defaultValue: "Celebrate every effort"),
                detail: String(localized: "group.theme.celebrate_every_effort.detail", defaultValue: "Notice every activity, not just the biggest ones.")
            ),
        ]
    }

    static func definition(for key: String?) -> GroupThemeDefinition? {
        all.first { $0.id == key }
    }

    static func recommendations(for group: GroupDTO) -> [GroupThemeDefinition] {
        var keys: [String] = []
        if !group.upcomingActivities.isEmpty {
            keys.append("do_something_together")
        }
        if group.week.state == "completed" {
            keys.append("celebrate_every_effort")
        } else if group.week.contributedCount == 0 {
            keys.append("one_small_step")
        } else {
            keys.append("keep_the_rhythm")
        }
        keys.append(contentsOf: ["build_consistency", "move_for_your_mood", "recover_and_recharge"])

        var seen = Set<String>()
        return keys
            .filter { seen.insert($0).inserted }
            .compactMap(definition(for:))
            .prefix(3)
            .map { $0 }
    }

    static func displayTitle(key: String?, customTitle: String?) -> String? {
        if key == "custom" { return customTitle }
        return definition(for: key)?.title
    }

    static func displayDetail(key: String?, customNote: String?) -> String? {
        if key == "custom" { return customNote }
        return definition(for: key)?.detail
    }
}
