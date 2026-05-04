import type {
  ActivityForPlanning,
  AthleteTrainingStateSnapshot,
  PlannedWorkoutForState,
  ReadinessForPlanning,
} from "./types.js";

export interface AthleteStateInput {
  activities: ActivityForPlanning[];
  plannedWorkouts: PlannedWorkoutForState[];
  readiness: ReadinessForPlanning[];
  now?: Date;
}

export function computeAthleteTrainingState(input: AthleteStateInput): AthleteTrainingStateSnapshot {
  const now = input.now ?? new Date();
  const sevenDaysAgo = addDays(now, -7);
  const twentyEightDaysAgo = addDays(now, -28);
  const recentActivities = normalizeActivities(input.activities);
  const weekActivities = recentActivities.filter((activity) => activity.startedAt >= sevenDaysAgo);
  const fourWeekActivities = recentActivities.filter((activity) => activity.startedAt >= twentyEightDaysAgo);
  const weeklyMinutes = minutesFor(weekActivities);
  const fourWeekMinutes = minutesFor(fourWeekActivities);
  const weeklyDistanceMeters = distanceFor(weekActivities);
  const fourWeekDistanceMeters = distanceFor(fourWeekActivities);
  const completedOrSkipped = input.plannedWorkouts.filter((workout) =>
    ["completed", "skipped"].includes(workout.status)
  );
  const completed = completedOrSkipped.filter((workout) => workout.status === "completed");
  const adherenceRate = completedOrSkipped.length > 0 ? completed.length / completedOrSkipped.length : 1;
  const activeWeeks = new Set(fourWeekActivities.map((activity) => weekKey(activity.startedAt))).size;
  const consistencyScore = Math.min(1, activeWeeks / 4);
  const latestReadiness = [...input.readiness].sort((a, b) => b.date.getTime() - a.date.getTime())[0];
  const fatigueRisk = fatigueRiskFor({
    weeklyMinutes,
    fourWeekAvgMinutes: fourWeekMinutes / 4,
    latestReadiness,
  });
  const modalityBreakdown = modalityBreakdownFor(fourWeekActivities);

  return {
    asOfDate: now,
    overallLoadScore: Math.round(weeklyMinutes * (fatigueRisk === "high" ? 1.25 : 1)),
    weeklyMinutes,
    weeklyDistanceMeters,
    fourWeekAvgMinutes: Math.round(fourWeekMinutes / 4),
    fourWeekAvgDistanceMeters: fourWeekDistanceMeters / 4,
    longestRecentSessionSeconds: Math.max(0, ...fourWeekActivities.map((activity) => activity.durationSecs ?? 0)),
    adherenceRate,
    consistencyScore,
    fatigueRisk,
    lastHardWorkoutAt: lastHardWorkoutAt(input.plannedWorkouts),
    modalityBreakdown,
  };
}

function normalizeActivities(activities: ActivityForPlanning[]): ActivityForPlanning[] {
  return activities
    .filter((activity) => !Number.isNaN(activity.startedAt.getTime()))
    .sort((a, b) => b.startedAt.getTime() - a.startedAt.getTime());
}

function minutesFor(activities: ActivityForPlanning[]): number {
  return Math.round(activities.reduce((sum, activity) => sum + (activity.durationSecs ?? 0), 0) / 60);
}

function distanceFor(activities: ActivityForPlanning[]): number {
  return activities.reduce((sum, activity) => sum + (activity.distanceM ?? 0), 0);
}

function fatigueRiskFor(params: {
  weeklyMinutes: number;
  fourWeekAvgMinutes: number;
  latestReadiness?: ReadinessForPlanning;
}): AthleteTrainingStateSnapshot["fatigueRisk"] {
  const readiness = params.latestReadiness;
  if (readiness?.illnessOrPain) return "high";
  if (readiness && readiness.energy <= 1 && readiness.soreness >= 4) return "high";
  if (params.fourWeekAvgMinutes > 0 && params.weeklyMinutes > params.fourWeekAvgMinutes * 1.4) {
    return "high";
  }
  if (readiness && (readiness.energy <= 2 || readiness.stress >= 4 || readiness.soreness >= 4)) {
    return "medium";
  }
  if (params.fourWeekAvgMinutes > 0 && params.weeklyMinutes > params.fourWeekAvgMinutes * 1.2) {
    return "medium";
  }
  return "low";
}

function lastHardWorkoutAt(workouts: PlannedWorkoutForState[]): Date | null {
  const hardStimuli = new Set(["threshold", "speed", "longEndurance", "strength", "power"]);
  return (
    workouts
      .filter((workout) => workout.status === "completed" && (workout.isKeyWorkout || hardStimuli.has(workout.stimulus)))
      .map((workout) => workout.scheduledDate)
      .sort((a, b) => b.getTime() - a.getTime())[0] ?? null
  );
}

function modalityBreakdownFor(activities: ActivityForPlanning[]): Record<string, unknown> {
  const breakdown: Record<string, { sessions: number; minutes: number; distanceMeters: number }> = {};
  for (const activity of activities) {
    const key = modalityForActivityType(activity.type);
    const current = breakdown[key] ?? { sessions: 0, minutes: 0, distanceMeters: 0 };
    current.sessions += 1;
    current.minutes += Math.round((activity.durationSecs ?? 0) / 60);
    current.distanceMeters += activity.distanceM ?? 0;
    breakdown[key] = current;
  }
  return breakdown;
}

function modalityForActivityType(type: string): string {
  const normalized = type.toLowerCase();
  if (normalized.includes("walk")) return "walk";
  if (normalized.includes("bike") || normalized.includes("cycl")) return "bike";
  if (normalized.includes("swim")) return "swim";
  if (normalized.includes("strength")) return "strength";
  return "run";
}

function weekKey(date: Date): string {
  const start = startOfWeek(date);
  return start.toISOString().slice(0, 10);
}

function startOfWeek(date: Date): Date {
  const result = new Date(date);
  result.setHours(0, 0, 0, 0);
  const day = result.getDay();
  const diff = day === 0 ? -6 : 1 - day;
  result.setDate(result.getDate() + diff);
  return result;
}

function addDays(date: Date, days: number): Date {
  const result = new Date(date);
  result.setDate(result.getDate() + days);
  return result;
}
