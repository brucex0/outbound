import SwiftUI

/// Private activity headings; exported activity titles remain independent.
struct CompletedWorkoutTitleView: View {
    let title: String
    let context: CompletedWorkoutDisplayContext?
    var titleFont: Font = .headline
    var fallbackLineLimit: Int = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(titleFont)
                .lineLimit(context == nil ? fallbackLineLimit : 1)
                .truncationMode(.tail)
            if let context {
                Text(subtitle(context))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func subtitle(_ context: CompletedWorkoutDisplayContext) -> String {
        let fallback = String(localized: "completed_workout.plan_fallback", defaultValue: "Training plan", table: "CompletedWorkout")
        let planTitle = Bundle.main.localizedString(forKey: context.planTitleKey, value: fallback, table: nil)
        return String(format: String(localized: "completed_workout.plan_day_week", defaultValue: "%1$@: D%2$d/wk%3$d", table: "CompletedWorkout"),
                      planTitle, context.dayNumber, context.weekNumber)
    }
}

extension SavedActivity {
    var completedWorkoutDisplayContext: CompletedWorkoutDisplayContext? {
        guard activityEventID == nil, followedRoute == nil else { return nil }
        return performedWorkoutReference?.displayContext
    }

    var completedWorkoutDisplayTitle: String {
        if manualEdits?.editedFields.contains("title") == true { return title }
        return completedWorkoutDisplayContext.map { BuiltinWorkoutText.localized($0.workoutTitle) } ?? title
    }
}
