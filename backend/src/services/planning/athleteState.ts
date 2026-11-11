import { isRunningActivityType, reportedEffort, runningSessionLoad } from "./sessionEffort.js";
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
  const recentActivities = normalizeActivities(input.activities).filter((activity) => activity.startedAt <= now);
  const weekActivities = recentActivities.filter((activity) => activity.startedAt >= sevenDaysAgo);
  const fourWeekActivities = recentActivities.filter((activity) => activity.startedAt >= twentyEightDaysAgo);
  const weeklyMinutes = minutesFor(weekActivities);
  const fourWeekMinutes = minutesFor(fourWeekActivities);
  const weeklyDistanceMeters = distanceFor(weekActivities);
  const fourWeekDistanceMeters = distanceFor(fourWeekActivities);
  const recentRunSessions3Days = runActivities(recentActivities.filter((activity) => activity.startedAt >= addDays(now, -3))).length;
  const recentRunSessions7Days = runActivities(weekActivities).length;
  const recentRunDistance7DaysMeters = distanceFor(runActivities(weekActivities));
  const consecutiveActiveDays = consecutiveActiveDayCount(recentActivities, now);
  const completedOrSkipped = input.plannedWorkouts.filter((workout) =>
    ["completed", "skipped"].includes(workout.status) && !((workout.prescription as Record<string, unknown> | undefined)?.optional === true)
  );
  const completed = completedOrSkipped.filter((workout) => workout.status === "completed");
  const adherenceRate = completedOrSkipped.length > 0 ? completed.length / completedOrSkipped.length : 1;
  const activeWeeks = new Set(fourWeekActivities.map((activity) => weekKey(activity.startedAt))).size;
  const consistencyScore = Math.min(1, activeWeeks / 4);
  const latestReadiness = [...input.readiness].sort((a, b) => b.date.getTime() - a.date.getTime())[0];
  const sessionLoad = runningSessionLoad(recentActivities, now);
  const priorVolume = fourWeekActivities.filter((activity) => activity.startedAt < sevenDaysAgo
    && activity.durationSecs != null && Number.isFinite(activity.durationSecs) && activity.durationSecs > 0);
  const priorWindow = (activity: ActivityForPlanning) => Math.min(3, Math.ceil((now.getTime() - activity.startedAt.getTime()) / (7 * 86_400_000)) - 1);
  const priorVolumeWindows = new Set(priorVolume.map(priorWindow));
  // Running bootstrap: a first training week divided by four is not a baseline.
  // Retain the prior non-running-only behavior and all readiness/reported-load guards.
  const establishedVolumeBaseline = runActivities(fourWeekActivities).length === 0
    || priorVolume.length >= 3 && priorVolumeWindows.size === 3;
  const volumeFatigueRisk = fatigueRiskFor({
    weeklyMinutes,
    fourWeekAvgMinutes: fourWeekMinutes / 4,
    latestReadiness,
    establishedVolumeBaseline,
  });
  // A comparable reported-load rise prompts conservative review. Missing or
  // falling coverage cannot create an apparent load decrease or progression.
  const fatigueRisk = volumeFatigueRisk === "low" && sessionLoad.comparable && (sessionLoad.ratio ?? 0) > 1.4 ? "medium" : volumeFatigueRisk;
  const modalityBreakdown = modalityBreakdownFor(fourWeekActivities, now);
  if (modalityBreakdown.run) {
    const running = modalityBreakdown.run as Record<string, unknown>;
    running.sessionEffortLoad = sessionLoad;
    const priorRuns = runActivities(priorVolume);
    running.baselineEstablished = priorRuns.length >= 3 && new Set(priorRuns.map(priorWindow)).size === 3;
    running.lastReportedHardAt = runActivities(recentActivities).filter((activity) => (reportedEffort(activity.sessionEffortRating) ?? 0) >= 8)
      .map((activity) => activity.startedAt).sort((left, right) => right.getTime() - left.getTime())[0]?.toISOString() ?? null;
  }

  return {
    asOfDate: now,
    overallLoadScore: Math.round(weeklyMinutes * (fatigueRisk === "high" ? 1.25 : 1)),
    weeklyMinutes,
    weeklyDistanceMeters,
    fourWeekAvgMinutes: Math.round(fourWeekMinutes / 4),
    fourWeekAvgDistanceMeters: fourWeekDistanceMeters / 4,
    recentRunSessions3Days,
    recentRunSessions7Days,
    recentRunDistance7DaysMeters,
    consecutiveActiveDays,
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

function runActivities(activities: ActivityForPlanning[]): ActivityForPlanning[] {
  return activities.filter((activity) => isRunningActivityType(activity.type));
}

function consecutiveActiveDayCount(activities: ActivityForPlanning[], now: Date): number {
  const activeDays = new Set(
    activities
      .filter((activity) => activity.startedAt <= now && activity.startedAt >= addDays(now, -14))
      .map((activity) => dayKey(activity.startedAt))
  );
  const latestActivity = activities
    .filter((activity) => activity.startedAt <= now)
    .sort((left, right) => right.startedAt.getTime() - left.startedAt.getTime())[0];
  if (!latestActivity || startOfDay(latestActivity.startedAt) < addDays(startOfDay(now), -1)) return 0;
  let count = 0;
  let cursor = startOfDay(latestActivity.startedAt);
  while (activeDays.has(dayKey(cursor))) {
    count += 1;
    cursor = addDays(cursor, -1);
  }
  return count;
}

function dayKey(date: Date): string {
  return date.toISOString().slice(0, 10);
}

function startOfDay(date: Date): Date {
  const result = new Date(date);
  result.setUTCHours(0, 0, 0, 0);
  return result;
}

function fatigueRiskFor(params: {
  weeklyMinutes: number;
  fourWeekAvgMinutes: number;
  latestReadiness?: ReadinessForPlanning;
  establishedVolumeBaseline: boolean;
}): AthleteTrainingStateSnapshot["fatigueRisk"] {
  const readiness = params.latestReadiness;
  if (readiness?.illnessOrPain) return "high";
  if (readiness && readiness.energy <= 1 && readiness.soreness >= 4) return "high";
  if (params.establishedVolumeBaseline && params.fourWeekAvgMinutes > 0 && params.weeklyMinutes > params.fourWeekAvgMinutes * 1.4) {
    return "high";
  }
  if (readiness && (readiness.energy <= 2 || readiness.stress >= 4 || readiness.soreness >= 4)) {
    return "medium";
  }
  if (params.establishedVolumeBaseline && params.fourWeekAvgMinutes > 0 && params.weeklyMinutes > params.fourWeekAvgMinutes * 1.2) {
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

function modalityBreakdownFor(activities: ActivityForPlanning[], now: Date): Record<string, unknown> {
  const breakdown: Record<string, { sessions: number; minutes: number; distanceMeters: number; typicalSessionMinutes?: number; typicalDoseSessionMinutes?: number; representativeLongMinutes?: number; activeWeeks?: number; representativeSessions?: number }> = {};
  for (const activity of activities) {
    const key = modalityForActivityType(activity.type);
    const current = breakdown[key] ?? { sessions: 0, minutes: 0, distanceMeters: 0 };
    current.sessions += 1;
    current.minutes += Math.round((activity.durationSecs ?? 0) / 60);
    current.distanceMeters += activity.distanceM ?? 0;
    breakdown[key] = current;
  }
  const doseRuns = activities.filter((activity) => modalityForActivityType(activity.type) === "run"
    && activity.durationSecs != null && Number.isFinite(activity.durationSecs) && activity.durationSecs >= 300);
  if (breakdown.run && doseRuns.length) {
    const values = doseRuns.map((activity) => activity.durationSecs! / 60).sort((a, b) => a - b);
    const middle = Math.floor(values.length / 2);
    breakdown.run.typicalDoseSessionMinutes = values.length % 2 ? values[middle] : (values[middle - 1] + values[middle]) / 2;
    // Median of repeated weekly maxima preserves one long run per week;
    // a single exceptional run cannot establish long-session capacity.
    const maxima = new Map<number, number>();
    for (const activity of doseRuns) {
      const window = Math.max(0, Math.min(3, Math.ceil((now.getTime() - activity.startedAt.getTime()) / (7 * 86400000)) - 1));
      maxima.set(window, Math.max(maxima.get(window) ?? 0, activity.durationSecs! / 60));
    }
    const weekly = [...maxima.values()].sort((left, right) => left - right);
    const midpoint = Math.floor(weekly.length / 2);
    breakdown.run.representativeLongMinutes = weekly.length >= 3
      ? weekly.length % 2 ? weekly[midpoint] : (weekly[midpoint - 1] + weekly[midpoint]) / 2
      : breakdown.run.typicalDoseSessionMinutes;
  }
  // Keep short activities in total load, but use standalone-length runs for the
  // representative long-slot duration. One outlier must not set capacity.
  const runs = activities.filter((activity) => modalityForActivityType(activity.type) === "run" && (activity.durationSecs ?? 0) >= 15 * 60);
  const durations = runs.map((activity) => activity.durationSecs! / 60).sort((a, b) => a - b);
  if (breakdown.run && durations.length > 0) {
    breakdown.run.representativeSessions = durations.length;
    const midpoint = Math.floor(durations.length / 2);
    breakdown.run.typicalSessionMinutes = Math.round(durations.length % 2 ? durations[midpoint] : (durations[midpoint - 1] + durations[midpoint]) / 2);
    breakdown.run.activeWeeks = new Set(runs.map((activity) => weekKey(activity.startedAt))).size;
  }
  return breakdown;
}

function modalityForActivityType(type: string): string {
  const normalized = type.toLowerCase();
  if (normalized.includes("walk")) return "walk";
  if (normalized.includes("hik")) return "walk";
  if (normalized.includes("bike") || normalized.includes("cycl")) return "bike";
  if (normalized.includes("swim")) return "swim";
  if (normalized.includes("strength")) return "strength";
  if (normalized.includes("mobility") || normalized.includes("flexibility") || normalized.includes("yoga")) return "mobility";
  if (isRunningActivityType(normalized)) return "run";
  return "unknown";
}

function weekKey(date: Date): string {
  const start = startOfWeek(date);
  return start.toISOString().slice(0, 10);
}

function startOfWeek(date: Date): Date {
  const result = new Date(date);
  result.setUTCHours(0, 0, 0, 0);
  const day = result.getUTCDay();
  const diff = day === 0 ? -6 : 1 - day;
  result.setUTCDate(result.getUTCDate() + diff);
  return result;
}

function addDays(date: Date, days: number): Date {
  const result = new Date(date);
  result.setUTCDate(result.getUTCDate() + days);
  return result;
}
