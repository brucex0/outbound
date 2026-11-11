import Foundation

/// Only exact issued slot identities affect the canonical schedule. Performed duration
/// belongs to history; progress continues to credit the currently scheduled prescription.
enum ActivityPlanProjector {
    static func project(_ state: TrainingPlanStateResponse, repository: ActivityRepositoryProjection, now: Date = Date()) -> TrainingPlanStateResponse {
        let confirmed = Set(repository.confirmedCompletions.filter { $0.status == "completed" }.map(\.plannedWorkoutId))
        let pending = repository.pendingWorkoutIDs.subtracting(confirmed)
        func overlay(_ workout: TrainingPlanWorkout) -> TrainingPlanWorkout {
            var result = workout
            if confirmed.contains(workout.id) { result.status = "completed" }
            else if workout.status != "completed", repository.conflictedWorkoutIDs.contains(workout.id) { result.status = "sync_conflict" }
            else if workout.status != "completed", pending.contains(workout.id) { result.status = "pending_sync" }
            return result
        }
        let context = state.calendar?.resolved(at: now)
        var plan = state.activePlan
        let projectedSchedule = plan?.plannedSchedule?.map(overlay)
        plan?.plannedSchedule = projectedSchedule
        if let context { plan?.calendar = context }
        let week: TrainingPlanWeekSnapshot?
        if let original = state.currentWeek {
            let rolled = context.map { $0.weekStart != original.calendar?.weekStart } ?? false
            let source: [TrainingPlanWorkout]
            if rolled, let context {
                // Date keys are logical account dates, independent of the travelling device.
                source = (projectedSchedule ?? original.scheduledWorkouts).filter { workout in
                    guard let key = workout.scheduledDateKey,
                          let date = PlanningCalendarContext.logicalDate(key, calendar: context.calendar) else { return false }
                    return date >= context.weekStart && date < context.weekEnd
                }
            } else { source = original.scheduledWorkouts }
            let workouts = source.map(overlay)
            let required = workouts.filter { !$0.isOptional }
            let completed = required.filter { $0.status == "completed" }
            let saved = required.filter { $0.status == "pending_sync" }
            let minutes = completed.reduce(0) { $0 + $1.durationMinutesRounded }
            let pendingMinutes = saved.reduce(0) { $0 + $1.durationMinutesRounded }
            let targets = rolled ? required.count : original.targetSessions
            let targetMinutes = rolled ? required.reduce(0) { $0 + $1.durationMinutesRounded } : original.targetMinutes
            let done = completed.count + saved.count
            let progress = min(1, max(Double(done) / Double(max(1, targets)), Double(minutes + pendingMinutes) / Double(max(1, targetMinutes))))
            let summary: String
            if rolled && workouts.isEmpty {
                summary = String(localized: "plan.progress.load_week", defaultValue: "Connect to load this week’s scheduled workouts.")
            } else if saved.isEmpty {
                summary = TrainingPlanWeekSnapshot.progressSummary(completedSessions: completed.count, targetSessions: targets,
                    completedMinutes: minutes, targetMinutes: targetMinutes)
            } else {
                summary = String(format: String(localized: "plan.progress.saved", defaultValue: "%1$d of %2$d sessions saved · %3$d of %4$d min"),
                    done, targets, minutes + pendingMinutes, targetMinutes)
            }
            var result = TrainingPlanWeekSnapshot(currentWeekIndex: context?.planWeekIndex ?? original.currentWeekIndex,
                totalWeeks: original.totalWeeks, completedSessions: completed.count, targetSessions: targets, completedMinutes: minutes,
                targetMinutes: targetMinutes, progressPercent: progress, summaryLine: summary,
                guideLine: original.guideLine, focus: original.focus, weekSummary: rolled ? "" : original.weekSummary,
                scheduledWorkouts: workouts, notes: rolled ? [] : original.notes)
            result.calendar = context ?? original.calendar
            result.pendingSessions = saved.count
            result.weekCoverageUnknown = rolled && workouts.isEmpty
            week = result
        } else { week = nil }
        let unavailable = confirmed.union(pending).union(Set(state.currentWeek?.scheduledWorkouts.filter { $0.status == "completed" }.map(\.id) ?? []))
        let validSuggestion = state.activitySuggestion?.isValid(now: now) == true ? state.activitySuggestion : nil
        let today = state.todaySuggestion.flatMap { suggestion -> TodayTrainingSuggestion? in
            guard !unavailable.contains(suggestion.workout.id) else { return nil }
            if state.activitySuggestion != nil, validSuggestion == nil { return nil }
            if let context, let key = suggestion.workout.scheduledDateKey,
               let date = PlanningCalendarContext.logicalDate(key, calendar: context.calendar),
               date < context.calendar.startOfDay(for: now) { return nil }
            return suggestion
        }
        var result = TrainingPlanStateResponse(activePlan: plan, recommendations: state.recommendations, currentWeek: week,
            todaySuggestion: today, activitySuggestion: today == nil && state.todaySuggestion != nil ? nil : validSuggestion,
            scheduledWorkouts: state.scheduledWorkouts.filter { !unavailable.contains($0.workoutID) }, calendar: context ?? state.calendar)
        result.revision = state.revision
        return result
    }
}
