import { adapterFor } from "./adapters/index.js";
import type {
  AthleteTrainingStateSnapshot,
  CreateTrainingGoalInput,
  Modality,
  PlanGenerationResult,
  PlannedWorkoutDraft,
  TrainingStimulus,
} from "./types.js";

const DEFAULT_DAYS = ["mon", "wed", "sat"];

export interface GeneratePlanInput {
  goal: {
    type: string;
    primaryModality: string;
    preferredDays: string[];
    daysPerWeekTarget: number;
    maxSessionMinutes: number;
    riskTolerance: string;
  };
  athleteState: AthleteTrainingStateSnapshot;
  now?: Date;
  reason?: string;
}

export function normalizeGoalInput(input: CreateTrainingGoalInput) {
  return {
    type: input.type,
    primaryModality: input.primaryModality ?? "run",
    priority: input.priority ?? defaultPriorityFor(input.type),
    preferredDays: normalizePreferredDays(input.preferredDays),
    daysPerWeekTarget: clampInt(input.daysPerWeekTarget ?? 3, 1, 6),
    maxSessionMinutes: clampInt(input.maxSessionMinutes ?? 45, 10, 180),
    riskTolerance: input.riskTolerance ?? "balanced",
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
    sessionsPerWeek: input.goal.daysPerWeekTarget,
    horizonDays: 14,
  });
  const workouts = dates.map((date, index) =>
    workoutForDate({
      date,
      index,
      total: dates.length,
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
      modality: input.goal.primaryModality,
      fatigueRisk: input.athleteState.fatigueRisk,
    },
  };
}

function workoutForDate(params: {
  date: Date;
  index: number;
  total: number;
  goal: GeneratePlanInput["goal"];
  athleteState: AthleteTrainingStateSnapshot;
}): PlannedWorkoutDraft {
  const stimulus = stimulusFor(params.index, params.total, params.goal, params.athleteState);
  const modality = modalityFor(params.goal.primaryModality, stimulus);
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
  athleteState: AthleteTrainingStateSnapshot
): TrainingStimulus {
  if (athleteState.fatigueRisk === "high") {
    return index % 2 === 0 ? "recovery" : "mobility";
  }
  if (goal.primaryModality === "strength") {
    return "strength";
  }
  const sessionsPerWeek = Math.max(1, goal.daysPerWeekTarget);
  const positionInWeek = index % sessionsPerWeek;
  if (positionInWeek === sessionsPerWeek - 1 && total >= 2) return "longEndurance";
  if (sessionsPerWeek >= 3 && positionInWeek === 1 && athleteState.fatigueRisk === "low") {
    return goal.type === "race" ? "threshold" : "easyAerobic";
  }
  return "easyAerobic";
}

function modalityFor(primaryModality: string, stimulus: TrainingStimulus): Modality {
  if (stimulus === "mobility" || stimulus === "recovery" && primaryModality === "mobility") return "mobility";
  if (stimulus === "strength" || stimulus === "hypertrophy") return "strength";
  if (primaryModality === "walk") return "walk";
  if (primaryModality === "strength") return "strength";
  return "run";
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
  sessionsPerWeek: number;
  horizonDays: number;
}): Date[] {
  const preferred = params.preferredDays.length > 0
    ? params.preferredDays
    : DEFAULT_DAYS.slice(0, Math.max(1, params.sessionsPerWeek));
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
  const normalized = (days ?? DEFAULT_DAYS).map((day) => day.trim().toLowerCase()).filter(Boolean);
  return normalized.length > 0 ? normalized : DEFAULT_DAYS;
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

function phaseForGoal(type: string) {
  if (type === "race") return "build";
  if (type === "comeback") return "recovery";
  return "base";
}

function defaultPriorityFor(type: string): string {
  switch (type) {
    case "race": return "finish";
    case "strength": return "increaseStrength";
    case "comeback": return "returnSafely";
    default: return "buildHabit";
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
