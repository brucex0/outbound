export const GOAL_FEASIBILITY_POLICY = "confirmed-novice-marathon-v1";
export const UNREALISTIC_GOAL_MESSAGE = "This goal isn’t realistic from your current starting point. Choose a later race or start with a shorter-distance plan.";
export class GoalFeasibilityError extends Error {
  readonly code = "goal_timeline_unrealistic";
  constructor() { super(UNREALISTIC_GOAL_MESSAGE); }
}

/** Narrow product guard, not a clinically validated minimum preparation time. */
export function assessGoalFeasibility(goal: { type: string; baselineContext?: string; targetDistanceMeters?: number | null; targetDate?: string | Date | null; activities?: string[] }, now: Date): { eligible: boolean; code: "eligible" | "goal_timeline_unrealistic" } {
  const distance = goal.targetDistanceMeters ?? (goal.type === "marathon" ? 42_195 : 0);
  const target = goal.targetDate == null ? null : new Date(goal.targetDate);
  const days = target && Number.isFinite(target.getTime()) ? (target.getTime() - Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate())) / 86_400_000 : null;
  const runningGoal = goal.type === "marathon" || goal.activities?.includes("run") === true;
  const eventGoal = goal.type === "eventPreparation" || goal.type === "marathon";
  const blocked = eventGoal && runningGoal && goal.baselineContext === "startingOut" && distance >= 40_000 && days != null && days >= 0 && days < 56;
  return { eligible: !blocked, code: blocked ? "goal_timeline_unrealistic" : "eligible" };
}
