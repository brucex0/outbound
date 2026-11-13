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
  /** Current running streak; general athlete-state activity streak is separate. */
  consecutiveActiveDays: number;
  baselineWeeklyDistanceKm: number;
  baselineWeeklyRunMinutes: number;
  baselineWeeklyRunSessions: number;
  observedAverageRunMinutes: number;
  explanation: string;
  reasons: string[];
  safetyFlags: string[];
}

export function assessPlanFit(input: {
  activities: ActivityForPlanning[];
  athleteState: AthleteTrainingStateSnapshot;
  workout?: Pick<PlannedWorkoutForState, "modality" | "stimulus" | "durationSeconds" | "prescription"> | null;
  readiness?: ReadinessForPlanning;
  now?: Date;
}): PlanFitAssessment {
  const now = input.now ?? new Date();
  const validActivities = input.activities
    .filter((activity) => !Number.isNaN(activity.startedAt.getTime()) && activity.startedAt <= now)
    .sort((left, right) => right.startedAt.getTime() - left.startedAt.getTime());
  const recentRuns = validActivities.filter((activity) => isRun(activity.type));
  const recentRunWindow = recentRuns.filter((activity) => activity.startedAt >= addDays(now, -7));
  const recentRun14 = recentRuns.filter((activity) => activity.startedAt >= addDays(now, -14));
  const recentRunDistanceKm = sumDistance(recentRunWindow) / 1_000;
  const recentRunMinutes = sumMinutes(recentRunWindow);
  const observedAverageRunMinutes = recentRun14.length > 0
    ? Math.round(sumMinutes(recentRun14) / recentRun14.length)
    : 0;
  const baselineRuns = recentRuns.filter((activity) => activity.startedAt >= addDays(now, -28));
  const priorRuns = baselineRuns.filter((activity) => activity.startedAt < addDays(now, -7));
  const baselineWeeklyDistanceKm = round(sumDistance(baselineRuns) / 4_000);
  const baselineWeeklyRunMinutes = Math.round(sumMinutes(baselineRuns) / 4);
  const baselineWeeklyRunSessions = baselineRuns.length / 4;
  // A recent count alone says nothing about overload. Compare like-for-like
  // running load, with repeated prior evidence, instead of all-sport distance.
  const priorWeeklyWindows = new Set(priorRuns.map((activity) =>
    Math.floor((now.getTime() - activity.startedAt.getTime()) / (7 * 86_400_000))
  ));
  const hasBaseline = priorRuns.length >= 3 && priorWeeklyWindows.size >= 2;
  const distanceLoadSpike = hasBaseline && baselineWeeklyDistanceKm > 0
    && recentRunDistanceKm > baselineWeeklyDistanceKm * 1.4;
  const durationLoadSpike = hasBaseline && baselineWeeklyRunMinutes > 0
    && recentRunMinutes > baselineWeeklyRunMinutes * 1.4;
  const consecutiveActiveDays = currentRunStreak(recentRuns, now);
  const previousLongestStreak = longestStreak(priorRuns);
  const streakRecoveryConcern = consecutiveActiveDays >= 4 && consecutiveActiveDays > previousLongestStreak;
  const readinessConcern = Boolean(
    input.readiness?.illnessOrPain
      || input.readiness && (input.readiness.energy <= 2 || input.readiness.soreness >= 4 || input.readiness.stress >= 4)
  );
  const recoveryConcern = input.athleteState.fatigueRisk === "high"
    || distanceLoadSpike
    || durationLoadSpike
    || streakRecoveryConcern
    || readinessConcern;

  if (recoveryConcern) {
    const reasons = [
      ...(recentRunDistanceKm > 0 ? [`recent_run_distance_${recentRunDistanceKm.toFixed(1)}km`] : []),
      ...(consecutiveActiveDays > 1 ? [`consecutive_active_days_${consecutiveActiveDays}`] : []),
      ...(distanceLoadSpike ? ["running_load_above_baseline"] : []),
      ...(durationLoadSpike ? ["running_duration_above_baseline"] : []),
      ...(streakRecoveryConcern ? ["running_streak_above_baseline"] : []),
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
      baselineWeeklyRunMinutes,
      baselineWeeklyRunSessions,
      observedAverageRunMinutes,
      explanation: recoveryExplanation({
        recentRunDistanceKm,
        consecutiveActiveDays,
        baselineWeeklyDistanceKm,
        baselineWeeklyRunMinutes,
        distanceLoadSpike,
        durationLoadSpike,
        streakRecoveryConcern,
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

  const prescription = input.workout?.prescription as Record<string, unknown> | undefined;
  const managedRunning = prescription?.source === "generatedRun" || prescription?.source === "trainingPlanCatalog"
    || prescription?.templateID != null || prescription?.runWalkProgramme != null || prescription?.issuedRunningDose != null;
  const staleWalkRun = !managedRunning && input.workout?.modality === "run"
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
      baselineWeeklyRunMinutes,
      baselineWeeklyRunSessions,
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
    baselineWeeklyRunMinutes,
    baselineWeeklyRunSessions,
    observedAverageRunMinutes,
    explanation: onTrackExplanation(input.athleteState, recentRunDistanceKm, consecutiveActiveDays),
    reasons: ["active_plan_fits_recent_training"],
    safetyFlags: [],
  };
}

function recoveryExplanation(input: {
  recentRunDistanceKm: number;
  consecutiveActiveDays: number;
  baselineWeeklyDistanceKm: number;
  baselineWeeklyRunMinutes: number;
  distanceLoadSpike: boolean;
  durationLoadSpike: boolean;
  streakRecoveryConcern: boolean;
  fatigueRisk: AthleteTrainingStateSnapshot["fatigueRisk"];
  readinessConcern: boolean;
}): string {
  const evidence: string[] = [];
  if (input.recentRunDistanceKm > 0) evidence.push(`${input.recentRunDistanceKm.toFixed(1)} km of running in the last 7 days`);
  if (input.streakRecoveryConcern) evidence.push(`${input.consecutiveActiveDays} consecutive running days, a denser streak than your prior running pattern`);
  if (input.distanceLoadSpike) {
    evidence.push(`above the ${input.baselineWeeklyDistanceKm.toFixed(1)} km four-week weekly baseline`);
  }
  if (input.durationLoadSpike) evidence.push(`running time above the ${input.baselineWeeklyRunMinutes} minute four-week weekly running baseline`);
  if (input.fatigueRisk === "high") evidence.push("a high current fatigue assessment");
  if (input.readinessConcern) evidence.push("a readiness or health signal that favors caution");
  const joined = evidence.length > 0 ? evidence.join(", ") : "elevated recent training load";
  return `Your recent training shows ${joined}. Recovery is recommended before another progression workout. Use Change workout to choose a gentler session or rest.`;
}

function onTrackExplanation(
  state: AthleteTrainingStateSnapshot,
  distanceKm: number,
  consecutiveActiveDays: number
): string {
  const distance = distanceKm > 0 ? `${distanceKm.toFixed(1)} km of running in the last 7 days` : "your recent training load";
  return `This session still fits ${distance}, ${consecutiveActiveDays} consecutive running days, and a ${state.fatigueRisk} fatigue assessment. Keep the prescribed effort rather than adding extra intensity.`;
}

function currentRunStreak(activities: ActivityForPlanning[], now: Date): number {
  const days = new Set(activities.map((activity) => dayKey(activity.startedAt)));
  let cursor = startOfDay(now);
  if (!days.has(dayKey(cursor))) cursor = addDays(cursor, -1);
  let count = 0;
  while (days.has(dayKey(cursor))) {
    count += 1;
    cursor = addDays(cursor, -1);
  }
  return count;
}

function longestStreak(activities: ActivityForPlanning[]): number {
  const days = [...new Set(activities.map((activity) => dayKey(activity.startedAt)))].sort();
  let longest = 0;
  let current = 0;
  let previous: string | undefined;
  for (const day of days) {
    current = previous && new Date(day).getTime() - new Date(previous).getTime() === 86_400_000 ? current + 1 : 1;
    longest = Math.max(longest, current);
    previous = day;
  }
  return longest;
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
