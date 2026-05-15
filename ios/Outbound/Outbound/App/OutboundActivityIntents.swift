import AppIntents
import Foundation

enum OutboundDistancePreset: String, AppEnum {
    case threeK
    case fiveK
    case tenK

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Distance")

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .threeK: "3K",
        .fiveK: "5K",
        .tenK: "10K"
    ]

    var meters: Double {
        switch self {
        case .threeK:
            return 3_000
        case .fiveK:
            return 5_000
        case .tenK:
            return 10_000
        }
    }
}

enum OutboundTimePreset: String, AppEnum {
    case twentyMinutes
    case thirtyMinutes
    case fortyFiveMinutes

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Time")

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .twentyMinutes: "20 minutes",
        .thirtyMinutes: "30 minutes",
        .fortyFiveMinutes: "45 minutes"
    ]

    var seconds: Int {
        switch self {
        case .twentyMinutes:
            return 20 * 60
        case .thirtyMinutes:
            return 30 * 60
        case .fortyFiveMinutes:
            return 45 * 60
        }
    }
}

private enum OutboundActivityIntentWriter {
    static func save(sport: SportType, goal: ActivityGoal) {
        PreparedActivityLaunchStore.save(
            PreparedActivityLaunch(sport: sport, goal: goal)
        )
    }

    static func dialogTitle(sport: SportType, goal: ActivityGoal) -> String {
        PreparedActivityLaunch(sport: sport, goal: goal)
            .sessionIntent(unitSystem: .metric)
            .title
    }
}

struct PrepareDistanceRunIntent: AppIntent {
    static let title: LocalizedStringResource = "Prepare Distance Run"
    static let description = IntentDescription("Prepare an Outbound run with a distance goal.")
    static let openAppWhenRun = true
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Distance", default: .tenK)
    var distance: OutboundDistancePreset

    static var parameterSummary: some ParameterSummary {
        Summary("Prepare a \(\.$distance) run")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let goal = ActivityGoal.distanceMeters(distance.meters)
        await MainActor.run {
            OutboundActivityIntentWriter.save(sport: .run, goal: goal)
        }
        let title = await MainActor.run {
            OutboundActivityIntentWriter.dialogTitle(sport: .run, goal: goal)
        }
        return .result(dialog: IntentDialog("Opening \(title). Tap Start when you are ready."))
    }
}

struct PrepareTimedRunIntent: AppIntent {
    static let title: LocalizedStringResource = "Prepare Timed Run"
    static let description = IntentDescription("Prepare an Outbound run with a time goal.")
    static let openAppWhenRun = true
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Time", default: .thirtyMinutes)
    var duration: OutboundTimePreset

    static var parameterSummary: some ParameterSummary {
        Summary("Prepare a \(\.$duration) run")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let goal = ActivityGoal.timeSeconds(duration.seconds)
        await MainActor.run {
            OutboundActivityIntentWriter.save(sport: .run, goal: goal)
        }
        let title = await MainActor.run {
            OutboundActivityIntentWriter.dialogTitle(sport: .run, goal: goal)
        }
        return .result(dialog: IntentDialog("Opening \(title). Tap Start when you are ready."))
    }
}

struct PrepareFreestyleRunIntent: AppIntent {
    static let title: LocalizedStringResource = "Prepare Run"
    static let description = IntentDescription("Prepare an open-ended Outbound run.")
    static let openAppWhenRun = true
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run {
            OutboundActivityIntentWriter.save(sport: .run, goal: .freestyle)
        }
        let title = await MainActor.run {
            OutboundActivityIntentWriter.dialogTitle(sport: .run, goal: .freestyle)
        }
        return .result(dialog: IntentDialog("Opening \(title). Tap Start when you are ready."))
    }
}

struct PrepareDistanceBikeIntent: AppIntent {
    static let title: LocalizedStringResource = "Prepare Distance Bike"
    static let description = IntentDescription("Prepare an Outbound bike activity with a distance goal.")
    static let openAppWhenRun = true
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Distance", default: .tenK)
    var distance: OutboundDistancePreset

    static var parameterSummary: some ParameterSummary {
        Summary("Prepare a \(\.$distance) bike ride")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let goal = ActivityGoal.distanceMeters(distance.meters)
        await MainActor.run {
            OutboundActivityIntentWriter.save(sport: .bike, goal: goal)
        }
        let title = await MainActor.run {
            OutboundActivityIntentWriter.dialogTitle(sport: .bike, goal: goal)
        }
        return .result(dialog: IntentDialog("Opening \(title). Tap Start when you are ready."))
    }
}

struct PrepareTimedBikeIntent: AppIntent {
    static let title: LocalizedStringResource = "Prepare Timed Bike"
    static let description = IntentDescription("Prepare an Outbound bike activity with a time goal.")
    static let openAppWhenRun = true
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Time", default: .thirtyMinutes)
    var duration: OutboundTimePreset

    static var parameterSummary: some ParameterSummary {
        Summary("Prepare a \(\.$duration) bike ride")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let goal = ActivityGoal.timeSeconds(duration.seconds)
        await MainActor.run {
            OutboundActivityIntentWriter.save(sport: .bike, goal: goal)
        }
        let title = await MainActor.run {
            OutboundActivityIntentWriter.dialogTitle(sport: .bike, goal: goal)
        }
        return .result(dialog: IntentDialog("Opening \(title). Tap Start when you are ready."))
    }
}

struct PrepareFreestyleBikeIntent: AppIntent {
    static let title: LocalizedStringResource = "Prepare Bike"
    static let description = IntentDescription("Prepare an open-ended Outbound bike activity.")
    static let openAppWhenRun = true
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run {
            OutboundActivityIntentWriter.save(sport: .bike, goal: .freestyle)
        }
        let title = await MainActor.run {
            OutboundActivityIntentWriter.dialogTitle(sport: .bike, goal: .freestyle)
        }
        return .result(dialog: IntentDialog("Opening \(title). Tap Start when you are ready."))
    }
}

struct OutboundActivityShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .orange

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PrepareDistanceRunIntent(),
            phrases: [
                "Start a \(\.$distance) run in \(.applicationName)",
                "Set up a \(\.$distance) run in \(.applicationName)"
            ],
            shortTitle: "Distance Run",
            systemImageName: "figure.run"
        )

        AppShortcut(
            intent: PrepareTimedRunIntent(),
            phrases: [
                "Start a \(\.$duration) run in \(.applicationName)",
                "Set up a \(\.$duration) run in \(.applicationName)"
            ],
            shortTitle: "Timed Run",
            systemImageName: "timer"
        )

        AppShortcut(
            intent: PrepareFreestyleRunIntent(),
            phrases: [
                "Start a run in \(.applicationName)",
                "Set up a run in \(.applicationName)"
            ],
            shortTitle: "Run",
            systemImageName: "figure.run"
        )

        AppShortcut(
            intent: PrepareDistanceBikeIntent(),
            phrases: [
                "Start a \(\.$distance) bike ride in \(.applicationName)",
                "Set up a \(\.$distance) bike ride in \(.applicationName)"
            ],
            shortTitle: "Distance Bike",
            systemImageName: "bicycle"
        )

        AppShortcut(
            intent: PrepareTimedBikeIntent(),
            phrases: [
                "Start a \(\.$duration) bike ride in \(.applicationName)",
                "Set up a \(\.$duration) bike ride in \(.applicationName)"
            ],
            shortTitle: "Timed Bike",
            systemImageName: "timer"
        )

        AppShortcut(
            intent: PrepareFreestyleBikeIntent(),
            phrases: [
                "Start a bike ride in \(.applicationName)",
                "Set up a bike ride in \(.applicationName)"
            ],
            shortTitle: "Bike",
            systemImageName: "bicycle"
        )
    }
}
