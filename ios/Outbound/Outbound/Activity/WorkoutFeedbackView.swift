import SwiftUI

/// Reusable feedback editor. The presenter owns the draft and when it is submitted.
/// Dismissing the sheet retains edits; opening it never submits feedback.
struct WorkoutFeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedEffort: RunEffort?
    @Binding var continuationCapacity: ContinuationCapacity?
    @Binding var selectedGuidanceFeedback: LiveGuidanceFeedback?
    var guidanceReport: LiveGuidanceSessionReport = .empty

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    feedbackSection
                    if guidanceReport.spokenCueCount > 0 {
                        guidanceFeedbackSection
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(String(localized: "workout.feedback.title", defaultValue: "Feedback"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.done", defaultValue: "Done")) { dismiss() }
                }
            }
        }
    }

    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "summary.feedback.header", defaultValue: "How did that feel?"))
                .font(.headline)
            HStack {
                effortButton(.easy, title: String(localized: "summary.feedback.easy", defaultValue: "Easy"))
                effortButton(.aboutRight, title: String(localized: "summary.feedback.about_right", defaultValue: "About right"))
                effortButton(.tooHard, title: String(localized: "summary.feedback.too_hard", defaultValue: "Too hard"))
            }
            if selectedEffort == .easy {
                Text(String(localized: "summary.feedback.capacity.header", defaultValue: "Could you comfortably have continued?"))
                    .font(.subheadline.weight(.semibold))
                HStack {
                    capacityButton(.none, title: String(localized: "summary.feedback.capacity.no", defaultValue: "No"))
                    capacityButton(.tenMinutes, title: String(localized: "summary.feedback.capacity.10min", defaultValue: "10 min"))
                    capacityButton(.muchLonger, title: String(localized: "summary.feedback.capacity.much_longer", defaultValue: "Much longer"))
                }
            }
            Text(String(localized: "summary.feedback.note", defaultValue: "Optional. Plainstride asks after workouts where your answer can improve the plan."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private var guidanceFeedbackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "guide.feedback.section.title", defaultValue: "How was live guidance?"))
                .font(.headline)

            Text(guidanceSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(LiveGuidanceFeedback.allCases) { feedback in
                    Button(feedback.displayName) {
                        selectedGuidanceFeedback = feedback
                    }
                    .buttonStyle(.bordered)
                    .tint(selectedGuidanceFeedback == feedback ? .orange : .secondary)
                }
            }

            Text(String(localized: "guide.feedback.privacy", defaultValue: "Feedback improves cue timing and frequency. Coaching text is not included in analytics."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private var guidanceSummary: String {
        let format = String(
            localized: "guide.feedback.summary.format",
            defaultValue: "%1$d cues · %2$d helped"
        )
        return String(
            format: format,
            locale: .autoupdatingCurrent,
            guidanceReport.spokenCueCount,
            guidanceReport.helpfulCueCount
        )
    }

    private func effortButton(_ effort: RunEffort, title: String) -> some View {
        Button(title) {
            selectedEffort = effort
            if effort != .easy { continuationCapacity = nil }
        }
            .buttonStyle(.bordered)
            .tint(selectedEffort == effort ? .orange : .secondary)
            .frame(maxWidth: .infinity)
    }

    private func capacityButton(_ capacity: ContinuationCapacity, title: String) -> some View {
        Button(title) { continuationCapacity = capacity }
            .buttonStyle(.bordered)
            .tint(continuationCapacity == capacity ? .orange : .secondary)
            .frame(maxWidth: .infinity)
    }

}
