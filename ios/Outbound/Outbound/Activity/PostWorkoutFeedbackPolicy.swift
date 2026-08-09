import Foundation

enum PostWorkoutFeedbackPolicy {
    static func shouldRequestFeedback(
        summary: ActivitySummary,
        intent: SessionIntent?,
        priorActivityCount: Int
    ) -> Bool {
        let workoutID = intent?.id.lowercased() ?? "freestyle-run"

        if workoutID.hasPrefix("calibration-") || workoutID.hasPrefix("changed-") {
            return true
        }

        guard summary.durationSecs >= 10 * 60 else { return false }

        if isStructured(intent) {
            return true
        }

        // Routine sessions are sampled instead of asking after every activity.
        return (priorActivityCount + 1).isMultiple(of: 4)
    }

    private static func isStructured(_ intent: SessionIntent?) -> Bool {
        guard let intent else { return false }
        if intent.workoutSteps.count > 1 { return true }

        let description = "\(intent.title) \(intent.detail)".lowercased()
        return ["interval", "tempo", "threshold", "long run", "race", "hill", "pickup", "strides"]
            .contains { description.contains($0) }
    }
}
