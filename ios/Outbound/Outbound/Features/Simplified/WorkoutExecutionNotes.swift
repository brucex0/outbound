import SwiftUI

/// Presentation-only coaching derived from typed phases; does not alter prescriptions.
struct WorkoutExecutionNotes: View {
    let intent: SessionIntent

    private var phases: [SessionCoachingPhase] {
        let source = intent.workoutSteps.compactMap { $0.coachingTarget?.phase }
        var seen: Set<SessionCoachingPhase> = []
        return (source.isEmpty ? [intent.coachingTarget?.phase ?? .open] : source)
            .filter { seen.insert($0).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "workout.coaching.heading"))
                .font(.headline)
            note(title: String(localized: "workout.coaching.success"),
                 body: String(localized: "workout.coaching.success_body"))
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "workout.coaching.feel"))
                    .font(.subheadline.weight(.semibold))
                ForEach(phases, id: \.self) { phase in
                    Text(instruction(for: phase))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if intent.resolvedActivityType == .running {
                note(title: String(localized: "workout.coaching.form"),
                     body: String(localized: "workout.coaching.form_body"))
                Text(String(localized: "workout.coaching.pacer"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func note(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(body).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func instruction(for phase: SessionCoachingPhase) -> String {
        switch phase {
        case .warmup: String(localized: "workout.coaching.warmup")
        case .easy: String(localized: "workout.coaching.easy")
        case .work: String(localized: "workout.coaching.work")
        case .recovery: String(localized: "workout.coaching.recovery")
        case .cooldown: String(localized: "workout.coaching.cooldown")
        case .walk: String(localized: "workout.coaching.walk")
        case .open: String(localized: "workout.coaching.open")
        }
    }
}
