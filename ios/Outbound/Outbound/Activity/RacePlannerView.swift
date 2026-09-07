import SwiftUI

struct RacePlanRecommendation: Equatable {
    let raceIntent: RaceExecutionIntent
    let evidenceCount: Int

    static func make(distanceMeters: Double, activities: [SavedActivity]) -> RacePlanRecommendation {
        let eligible = activities
            .filter {
                $0.activityType == .running && $0.distanceM >= 2_000 && $0.durationSecs >= 10 * 60
                    && $0.distanceM >= distanceMeters * 0.5
                    && $0.distanceM <= distanceMeters * 1.1
            }
            .prefix(30)
        guard let longestDistance = eligible.map(\.distanceM).max() else {
            return finishRecommendation(distanceMeters: distanceMeters)
        }
        let comparable = eligible.filter { $0.distanceM >= longestDistance * 0.9 }
        let candidates = comparable
            .compactMap { activity -> Double? in
                let ratio = distanceMeters / activity.distanceM
                guard ratio >= 0.9, ratio <= 2 else { return nil }
                let projected = Double(activity.durationSecs) * pow(ratio, 1.08)
                if activity.distanceM >= distanceMeters * 0.95 {
                    return max(projected, Double(activity.durationSecs))
                }
                return projected * 1.05
            }
            .sorted()
        guard let prediction = candidates.first else {
            return finishRecommendation(distanceMeters: distanceMeters)
        }
        let seconds = Int((prediction / 60).rounded() * 60)
        return RacePlanRecommendation(
            raceIntent: RaceExecutionIntent(
                distanceMeters: distanceMeters,
                goalMode: .targetTime,
                goalTimeSeconds: seconds,
                targetPaceSecondsPerKilometer: Double(seconds) / (distanceMeters / 1_000),
                pacingStrategy: .negativeSplit,
                recommendationSource: "training_history"
            ),
            evidenceCount: comparable.count
        )
    }

    private static func finishRecommendation(distanceMeters: Double) -> RacePlanRecommendation {
        RacePlanRecommendation(
            raceIntent: RaceExecutionIntent(
                distanceMeters: distanceMeters,
                goalMode: .finish,
                goalTimeSeconds: nil,
                targetPaceSecondsPerKilometer: nil,
                pacingStrategy: .effortBased,
                recommendationSource: "insufficient_history"
            ),
            evidenceCount: 0
        )
    }
}

struct RacePlannerView: View {
    @Environment(\.dismiss) private var dismiss
    let activities: [SavedActivity]
    let unitSystem: MeasurementUnitSystem
    let onUsePlan: (RaceExecutionIntent) -> Void

    @State private var distanceMeters = 21_097.5
    @State private var usesTarget = true
    @State private var strategy: RacePacingStrategy = .negativeSplit
    @State private var targetHours = 2
    @State private var targetMinutes = 0

    private var recommendation: RacePlanRecommendation {
        .make(distanceMeters: distanceMeters, activities: activities)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "race.planner.distance", defaultValue: "Race distance")) {
                    Picker(String(localized: "race.planner.distance", defaultValue: "Race distance"), selection: $distanceMeters) {
                        Text("5K").tag(5_000.0)
                        Text("10K").tag(10_000.0)
                        Text(String(localized: "race.planner.half", defaultValue: "Half marathon")).tag(21_097.5)
                        Text(String(localized: "race.planner.marathon", defaultValue: "Marathon")).tag(42_195.0)
                    }
                }

                Section(String(localized: "race.planner.recommendation", defaultValue: "Plainstride recommendation")) {
                    if recommendation.evidenceCount > 0 {
                        Text(String(
                            format: String(localized: "race.planner.based_on_history", defaultValue: "Based on %d relevant recent runs, start patiently and aim for %@."),
                            locale: .autoupdatingCurrent,
                            recommendation.evidenceCount,
                            durationLabel(recommendation.raceIntent.goalTimeSeconds ?? 0)
                        ))
                        Toggle(String(localized: "race.planner.use_target", defaultValue: "Time goal"), isOn: $usesTarget)
                    } else {
                        Text(String(localized: "race.planner.no_history", defaultValue: "There isn’t enough comparable training history for a responsible time target. Race by effort and focus on finishing well."))
                        Toggle(String(localized: "race.planner.use_target", defaultValue: "Time goal"), isOn: $usesTarget)
                    }
                    if usesTarget {
                        durationPicker
                    }
                }

                Section(String(localized: "race.planner.strategy", defaultValue: "Pacing strategy")) {
                    Picker(String(localized: "race.planner.strategy", defaultValue: "Pacing strategy"), selection: $strategy) {
                        Text(String(localized: "race.planner.negative_split", defaultValue: "Patient start, stronger finish")).tag(RacePacingStrategy.negativeSplit)
                        Text(String(localized: "race.planner.even", defaultValue: "Even effort")).tag(RacePacingStrategy.even)
                        Text(String(localized: "race.planner.effort", defaultValue: "Finish by feel")).tag(RacePacingStrategy.effortBased)
                    }
                }
            }
            .navigationTitle(String(localized: "race.planner.title", defaultValue: "Plan this race"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel", defaultValue: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "race.planner.use_plan", defaultValue: "Use race plan")) {
                        onUsePlan(resolvedIntent)
                        dismiss()
                    }
                    .disabled(usesTarget && targetDurationSeconds == nil)
                }
            }
            .onAppear { seedRecommendation() }
            .onChange(of: distanceMeters) { _, _ in seedRecommendation() }
        }
    }

    private var resolvedIntent: RaceExecutionIntent {
        let recommended = recommendation.raceIntent
        guard usesTarget else {
            return RaceExecutionIntent(distanceMeters: distanceMeters, goalMode: .finish, goalTimeSeconds: nil, targetPaceSecondsPerKilometer: nil, pacingStrategy: .effortBased, recommendationSource: recommended.recommendationSource)
        }
        let seconds = targetDurationSeconds
        return RaceExecutionIntent(
            distanceMeters: distanceMeters,
            goalMode: seconds == nil ? .finish : .targetTime,
            goalTimeSeconds: seconds,
            targetPaceSecondsPerKilometer: seconds.map { Double($0) / (distanceMeters / 1_000) },
            pacingStrategy: strategy,
            recommendationSource: seconds == recommended.goalTimeSeconds ? recommended.recommendationSource : "manual"
        )
    }

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "race.planner.goal_time", defaultValue: "Goal time"))
                .font(.subheadline)
            HStack(spacing: 6) {
                Spacer()
                Picker(String(localized: "race.planner.hours", defaultValue: "Hours"), selection: $targetHours) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text("\(hour)").tag(hour)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 70, height: 120)
                .clipped()
                Text(String(localized: "race.planner.hours", defaultValue: "Hours"))
                    .foregroundStyle(.secondary)
                Picker(String(localized: "race.planner.minutes", defaultValue: "Minutes"), selection: $targetMinutes) {
                    ForEach(0..<60, id: \.self) { minute in
                        Text(String(format: "%02d", minute)).tag(minute)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 70, height: 120)
                .clipped()
                Text(String(localized: "race.planner.minutes", defaultValue: "Minutes"))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private var targetDurationSeconds: Int? {
        let seconds = targetHours * 3_600 + targetMinutes * 60
        return (5 * 60...24 * 60 * 60).contains(seconds) ? seconds : nil
    }

    private func seedRecommendation() {
        let race = recommendation.raceIntent
        usesTarget = race.goalTimeSeconds != nil
        strategy = race.pacingStrategy
        targetHours = (race.goalTimeSeconds ?? 2 * 3_600) / 3_600
        targetMinutes = ((race.goalTimeSeconds ?? 2 * 3_600) % 3_600) / 60
    }

    private func durationLabel(_ seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60
        return String(format: "%d:%02d:%02d", hours, minutes, remainder)
    }
}
