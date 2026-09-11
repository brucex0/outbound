import { adapterFor } from "./adapters/index.js";
import type {
  AthleteTrainingStateSnapshot,
  CreateTrainingGoalInput,
  Modality,
  PlanGenerationResult,
  PlannedWorkoutDraft,
  PrimaryMotivation,
  RunGoalType,
  TrainingStimulus,
} from "./types.js";

export interface GeneratePlanInput {
  goal: {
    type: string;
    activities: Modality[];
    baselineContext: string;
    preferredDays: string[];
    preferredLongSessionDay: string | null;
    daysPerWeekTarget: number;
    maxSessionMinutes: number;
    riskTolerance: string;
    primaryMotivation: PrimaryMotivation;
    preferredRunGoalType: RunGoalType;
  };
  athleteState: AthleteTrainingStateSnapshot;
  now?: Date;
  reason?: string;
}

export function normalizeGoalInput(input: CreateTrainingGoalInput) {
  return {
    type: input.type,
    activities: [...new Set(input.activities)].slice(0, 3),
    baselineContext: input.baselineContext ?? "currentlyActive",
    priority: input.priority ?? defaultPriorityFor(input.type),
    preferredDays: normalizePreferredDays(input.preferredDays),
    preferredLongSessionDay: input.preferredLongSessionDay ?? null,
    daysPerWeekTarget: clampInt(input.daysPerWeekTarget ?? 3, 1, 6),
    maxSessionMinutes: clampInt(input.maxSessionMinutes ?? 45, 10, 180),
    riskTolerance: input.riskTolerance ?? "balanced",
    primaryMotivation: input.primaryMotivation ?? "generalFitness",
    preferredRunGoalType: input.preferredRunGoalType ?? "time",
    constraints: input.constraints ?? {},
  };
}

export function generateInitialPlan(input: GeneratePlanInput): PlanGenerationResult {
  return generateWindow(input, "Initial adaptive plan");
}

export function generateNextWindow(input: GeneratePlanInput): PlanGenerationResult {
  return generateWindow(input, "Updated adaptive plan");
}

function generateWindow(input: GeneratePlanInput, summaryPrefix: string): PlanGenerationResult {
  const now = input.now ?? new Date();
  const dates = scheduledDates({
    now,
    preferredDays: input.goal.preferredDays,
    preferredLongSessionDay: input.goal.preferredLongSessionDay,
    sessionsPerWeek: input.goal.daysPerWeekTarget,
    horizonDays: 14,
  });
  const workouts = dates.map((date, index) =>
    workoutForDate({
      date,
      index,
      total: dates.length,
      isPreferredLongSessionDay: isDay(date, input.goal.preferredLongSessionDay),
      goal: input.goal,
      athleteState: input.athleteState,
    })
  );

  return {
    summary: `${summaryPrefix}: ${workouts.length} sessions over the next two weeks.`,
    phase: phaseForGoal(input.goal.type),
    workouts,
    engineDecision: {
      reason: input.reason ?? "initial",
      horizonDays: 14,
      sessions: workouts.length,
      activities: input.goal.activities,
      objective: input.goal.type,
      baselineContext: input.goal.baselineContext,
      preferredRunGoalType: input.goal.preferredRunGoalType,
      fatigueRisk: input.athleteState.fatigueRisk,
    },
  };
}

function workoutForDate(params: {
  date: Date;
  index: number;
  total: number;
  isPreferredLongSessionDay: boolean;
  goal: GeneratePlanInput["goal"];
  athleteState: AthleteTrainingStateSnapshot;
}): PlannedWorkoutDraft {
  const stimulus = stimulusFor(
    params.index,
    params.total,
    params.goal,
    params.athleteState,
    params.isPreferredLongSessionDay
  );
  const modality = modalityFor(params.goal, stimulus, params.index);
  const durationMinutes = durationFor(stimulus, params.goal, params.athleteState);
  const adapter = adapterFor(modality, stimulus);
  return adapter.generateWorkout({
    scheduledDate: params.date,
    modality,
    stimulus,
    durationMinutes,
    isKeyWorkout: stimulus === "longEndurance" || stimulus === "threshold" || stimulus === "strength",
    athleteState: params.athleteState,
  });
}

function stimulusFor(
  index: number,
  total: number,
  goal: GeneratePlanInput["goal"],
  athleteState: AthleteTrainingStateSnapshot,
  isPreferredLongSessionDay: boolean
): TrainingStimulus {
  if (athleteState.fatigueRisk === "high") {
    return index % 2 === 0 ? "recovery" : "mobility";
  }
  const sessionsPerWeek = Math.max(1, goal.daysPerWeekTarget);
  if (sessionsPerWeek > 1 && isPreferredLongSessionDay) return "longEndurance";
  const positionInWeek = index % sessionsPerWeek;
  if (positionInWeek === sessionsPerWeek - 1 && total >= 2) return "longEndurance";
  if (sessionsPerWeek >= 3 && positionInWeek === 1 && athleteState.fatigueRisk === "low") {
    const hasQualityActivity = goal.activities.some((activity) => activity === "run" || activity === "bike");
    return hasQualityActivity && (goal.type === "eventPreparation" || goal.type === "speed") ? "threshold" : "easyAerobic";
  }
  return "easyAerobic";
}

function modalityFor(goal: GeneratePlanInput["goal"], stimulus: TrainingStimulus, index: number): Modality {
  if (stimulus === "mobility") return "mobility";
  if (stimulus === "strength" || stimulus === "hypertrophy") return "strength";
  const activities: Modality[] = goal.activities.length > 0 ? goal.activities : ["run"];
  const rotated = activities.map((_, offset) => activities[(index + offset) % activities.length]);
  return rotated.find((activity) => activitySupports(activity, stimulus)) ?? activities[index % activities.length];
}

function activitySupports(activity: Modality, stimulus: TrainingStimulus): boolean {
  if (activity === "walk") return ["easyAerobic", "longEndurance", "recovery"].includes(stimulus);
  if (activity === "run" || activity === "bike") {
    return ["easyAerobic", "longEndurance", "threshold", "speed", "recovery"].includes(stimulus);
  }
  return false;
}

function durationFor(
  stimulus: TrainingStimulus,
  goal: GeneratePlanInput["goal"],
  athleteState: AthleteTrainingStateSnapshot
): number {
  const baseline = athleteState.fourWeekAvgMinutes > 0
    ? Math.max(20, Math.round(athleteState.fourWeekAvgMinutes / Math.max(1, goal.daysPerWeekTarget)))
    : Math.min(goal.maxSessionMinutes, 30);
  const cap = goal.maxSessionMinutes;
  const riskMultiplier = goal.riskTolerance === "stretch" ? 1.12 : goal.riskTolerance === "conservative" ? 0.88 : 1;

  switch (stimulus) {
    case "longEndurance":
      return Math.min(cap, Math.max(baseline + 10, Math.round(baseline * 1.35 * riskMultiplier)));
    case "threshold":
    case "speed":
      return Math.min(cap, Math.max(25, Math.round(baseline * riskMultiplier)));
    case "strength":
      return Math.min(cap, Math.max(25, baseline));
    case "mobility":
      return Math.min(20, Math.max(10, Math.round(baseline * 0.5)));
    case "recovery":
      return Math.min(cap, Math.max(15, Math.round(baseline * 0.7)));
    default:
      return Math.min(cap, Math.max(20, Math.round(baseline * riskMultiplier)));
  }
}

function scheduledDates(params: {
  now: Date;
  preferredDays: string[];
  preferredLongSessionDay: string | null;
  sessionsPerWeek: number;
  horizonDays: number;
}): Date[] {
  let preferred = params.preferredDays.length > 0
    ? params.preferredDays.slice(0, params.sessionsPerWeek)
    : evenlySpacedDays(params.now, params.sessionsPerWeek);
  const longDay = params.preferredLongSessionDay?.trim().toLowerCase();
  if (longDay && dayIndexFor(longDay) !== null && !preferred.includes(longDay)) {
    preferred = [...preferred.slice(0, Math.max(0, params.sessionsPerWeek - 1)), longDay];
  }
  const preferredIndexes = new Set(preferred.map(dayIndexFor).filter((day): day is number => day !== null));
  const dates: Date[] = [];

  for (let offset = 0; offset < params.horizonDays; offset += 1) {
    const date = startOfDay(addDays(params.now, offset));
    if (preferredIndexes.has(date.getDay())) {
      dates.push(date);
    }
  }

  if (dates.length > 0) return dates;

  for (let offset = 0; offset < params.horizonDays && dates.length < params.sessionsPerWeek * 2; offset += 2) {
    dates.push(startOfDay(addDays(params.now, offset)));
  }
  return dates;
}

function normalizePreferredDays(days?: string[]): string[] {
  return [...new Set((days ?? []).map((day) => day.trim().toLowerCase()).filter(Boolean))];
}

function evenlySpacedDays(now: Date, count: number): string[] {
  const names = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"];
  const start = now.getDay();
  return Array.from({ length: Math.max(1, count) }, (_, index) => names[(start + Math.floor(index * 7 / Math.max(1, count))) % 7]);
}

function dayIndexFor(day: string): number | null {
  switch (day.slice(0, 3).toLowerCase()) {
    case "sun": return 0;
    case "mon": return 1;
    case "tue": return 2;
    case "wed": return 3;
    case "thu": return 4;
    case "fri": return 5;
    case "sat": return 6;
    default: return null;
  }
}

function isDay(date: Date, day: string | null): boolean {
  if (!day) return false;
  return dayIndexFor(day) === date.getDay();
}

function phaseForGoal(type: string) {
  if (type === "eventPreparation") return "build";
  return "base";
}

function defaultPriorityFor(type: string): string {
  switch (type) {
    case "eventPreparation": return "finish";
    case "strength": return "increaseStrength";
    case "weightLoss": return "generalHealth";
    default: return "generalHealth";
  }
}

function clampInt(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, Math.round(value)));
}

function addDays(date: Date, days: number): Date {
  const result = new Date(date);
  result.setDate(result.getDate() + days);
  return result;
}

function startOfDay(date: Date): Date {
  const result = new Date(date);
  result.setHours(0, 0, 0, 0);
  return result;
}
