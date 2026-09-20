import type {
  ActivityForPlanning,
  AthleteTrainingStateSnapshot,
  PlannedWorkoutForState,
  ReadinessForPlanning,
} from "./types.js";

export type PlanFitAction = "keepPlan" | "recover" | "useObservedBaseline";

export interface PlanFitAssessment {
  classification: "onTrack" | "loadSpike" | "recoveryConcern" | "stalePrescription";
  action: PlanFitAction;
  recentRunSessions: number;
  recentRunDistanceKm: number;
  recentRunMinutes: number;
  consecutiveActiveDays: number;
  baselineWeeklyDistanceKm: number;
  observedAverageRunMinutes: number;
  explanation: string;
  reasons: string[];
  safetyFlags: string[];
}

export function assessPlanFit(input: {
  activities: ActivityForPlanning[];
  athleteState: AthleteTrainingStateSnapshot;
  workout?: Pick<PlannedWorkoutForState, "modality" | "stimulus" | "durationSeconds"> | null;
  readiness?: ReadinessForPlanning;
  now?: Date;
}): PlanFitAssessment {
  const now = input.now ?? new Date();
  const validActivities = input.activities
    .filter((activity) => !Number.isNaN(activity.startedAt.getTime()))
    .sort((left, right) => right.startedAt.getTime() - left.startedAt.getTime());
  const recentRuns = validActivities.filter((activity) => isRun(activity.type));
  const recentRunWindow = recentRuns.filter((activity) => activity.startedAt >= addDays(now, -7));
  const recentRun14 = recentRuns.filter((activity) => activity.startedAt >= addDays(now, -14));
  const recentRunDistanceKm = sumDistance(recentRunWindow) / 1_000;
  const recentRunMinutes = sumMinutes(recentRunWindow);
  const observedAverageRunMinutes = recentRun14.length > 0
    ? Math.round(sumMinutes(recentRun14) / recentRun14.length)
    : 0;
  const baselineWeeklyDistanceKm = Math.round(input.athleteState.fourWeekAvgDistanceMeters / 1_000 * 10) / 10;
  const consecutiveActiveDays = consecutiveActiveDayCount(validActivities, now);
  const distanceLoadSpike = baselineWeeklyDistanceKm > 0
    && recentRunDistanceKm > baselineWeeklyDistanceKm * 1.4;
  const streakRecoveryConcern = consecutiveActiveDays >= 4 || recentRunWindow.length >= 4;
  const readinessConcern = Boolean(
    input.readiness?.illnessOrPain
      || input.readiness && (input.readiness.energy <= 2 || input.readiness.soreness >= 4 || input.readiness.stress >= 4)
  );
  const recoveryConcern = input.athleteState.fatigueRisk === "high"
    || distanceLoadSpike
    || streakRecoveryConcern
    || readinessConcern;

  if (recoveryConcern) {
    const reasons = [
      ...(recentRunDistanceKm > 0 ? [`recent_run_distance_${recentRunDistanceKm.toFixed(1)}km`] : []),
      ...(consecutiveActiveDays > 1 ? [`consecutive_active_days_${consecutiveActiveDays}`] : []),
      ...(distanceLoadSpike ? ["running_load_above_baseline"] : []),
      ...(readinessConcern ? ["readiness_or_health_concern"] : []),
      ...(input.athleteState.fatigueRisk !== "low" ? [`fatigue_${input.athleteState.fatigueRisk}`] : []),
    ];
    return {
      classification: input.athleteState.fatigueRisk === "high" || readinessConcern ? "recoveryConcern" : "loadSpike",
      action: "recover",
      recentRunSessions: recentRunWindow.length,
      recentRunDistanceKm: round(recentRunDistanceKm),
      recentRunMinutes,
      consecutiveActiveDays,
      baselineWeeklyDistanceKm,
      observedAverageRunMinutes,
      explanation: recoveryExplanation({
        recentRunDistanceKm,
        recentRunWindow: recentRunWindow.length,
        consecutiveActiveDays,
        baselineWeeklyDistanceKm,
        fatigueRisk: input.athleteState.fatigueRisk,
        readinessConcern,
      }),
      reasons,
      safetyFlags: [
        ...(input.athleteState.fatigueRisk !== "low" ? [`fatigue_${input.athleteState.fatigueRisk}`] : []),
        ...(readinessConcern ? ["readiness_or_health_concern"] : []),
      ],
    };
  }

  const staleWalkRun = input.workout?.modality === "run"
    && input.workout.stimulus === "easyAerobic"
    && input.workout.durationSeconds <= 30 * 60
    && observedAverageRunMinutes >= Math.max(35, Math.round(input.workout.durationSeconds / 60 * 1.5))
    && recentRun14.length >= 3;
  if (staleWalkRun) {
    return {
      classification: "stalePrescription",
      action: "useObservedBaseline",
      recentRunSessions: recentRunWindow.length,
      recentRunDistanceKm: round(recentRunDistanceKm),
      recentRunMinutes,
      consecutiveActiveDays,
      baselineWeeklyDistanceKm,
      observedAverageRunMinutes,
      explanation: `Your last ${recentRun14.length} runs average ${observedAverageRunMinutes} minutes, so this short return-style prescription no longer matches your demonstrated running baseline. I am keeping the next run easy and continuous rather than adding intensity.`,
      reasons: ["observed_running_baseline_exceeds_prescription", "consistent_recent_running"],
      safetyFlags: [],
    };
  }

  return {
    classification: "onTrack",
    action: "keepPlan",
    recentRunSessions: recentRunWindow.length,
    recentRunDistanceKm: round(recentRunDistanceKm),
    recentRunMinutes,
    consecutiveActiveDays,
    baselineWeeklyDistanceKm,
    observedAverageRunMinutes,
    explanation: onTrackExplanation(input.athleteState, recentRunDistanceKm, consecutiveActiveDays),
    reasons: ["active_plan_fits_recent_training"],
    safetyFlags: [],
  };
}

function recoveryExplanation(input: {
  recentRunDistanceKm: number;
  recentRunWindow: number;
  consecutiveActiveDays: number;
  baselineWeeklyDistanceKm: number;
  fatigueRisk: AthleteTrainingStateSnapshot["fatigueRisk"];
  readinessConcern: boolean;
}): string {
  const evidence: string[] = [];
  if (input.recentRunDistanceKm > 0) evidence.push(`${input.recentRunDistanceKm.toFixed(1)} km of running in the last 7 days`);
  if (input.consecutiveActiveDays > 1) evidence.push(`${input.consecutiveActiveDays} consecutive active days`);
  if (input.baselineWeeklyDistanceKm > 0 && input.recentRunDistanceKm > input.baselineWeeklyDistanceKm * 1.4) {
    evidence.push(`above the ${input.baselineWeeklyDistanceKm.toFixed(1)} km four-week weekly baseline`);
  }
  if (input.readinessConcern) evidence.push("a readiness or health signal that favors caution");
  const joined = evidence.length > 0 ? evidence.join(", ") : "elevated recent training load";
  return `Your recent training shows ${joined}. Recovery is the useful next step, so I am reducing stress instead of stacking another progression workout.`;
}

function onTrackExplanation(
  state: AthleteTrainingStateSnapshot,
  distanceKm: number,
  consecutiveActiveDays: number
): string {
  const distance = distanceKm > 0 ? `${distanceKm.toFixed(1)} km of running in the last 7 days` : "your recent training load";
  return `This session still fits ${distance}, ${consecutiveActiveDays} consecutive active days, and a ${state.fatigueRisk} fatigue assessment. Keep the prescribed effort rather than adding extra intensity.`;
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
  if (!latestActivity) return 0;

  let count = 0;
  let cursor = startOfDay(latestActivity.startedAt);
  while (activeDays.has(dayKey(cursor))) {
    count += 1;
    cursor = addDays(cursor, -1);
  }
  return count;
}

function isRun(type: string): boolean {
  const normalized = type.toLowerCase();
  return normalized.includes("run") || normalized.includes("jog");
}

function sumMinutes(activities: ActivityForPlanning[]): number {
  return Math.round(activities.reduce((sum, activity) => sum + (activity.durationSecs ?? 0), 0) / 60);
}

function sumDistance(activities: ActivityForPlanning[]): number {
  return activities.reduce((sum, activity) => sum + (activity.distanceM ?? 0), 0);
}

function round(value: number): number {
  return Math.round(value * 10) / 10;
}

function dayKey(date: Date): string {
  return date.toISOString().slice(0, 10);
}

function startOfDay(date: Date): Date {
  const result = new Date(date);
  result.setHours(0, 0, 0, 0);
  return result;
}

function addDays(date: Date, days: number): Date {
  const result = new Date(date);
  result.setDate(result.getDate() + days);
  return result;
}
