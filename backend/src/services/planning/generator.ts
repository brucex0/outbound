import { mondayDateLabel } from "../accountCalendar.js";
import { preferredLongRunDays, longRunWeekModalities, longRunAllocation, LongRunDaysError } from "./longRunDays.js";
import { raceTaperDays } from "./raceRoadmap.js";
import { evaluateRunWalkProgramme, RUN_WALK_LADDER, stampIssuedRunningDose, type RunWalkProgramme } from "./runWalkProgramme.js";
import { runningDoseBudget, RUNNING_DOSE_POLICY, type RunningDoseBudget } from "./runningDosePolicy.js";
import { RUN_STRUCTURE_VERSION } from "./runningPrescription.js";
import { applyRunningBenchmark, runningBenchmarkDecision } from "./runningBenchmark.js";
import { adapterFor } from "./adapters/index.js";
import type {
  AthleteTrainingStateSnapshot,
  CreateTrainingGoalInput,
  Modality,
  PlanGenerationResult,
  PlannedWorkoutDraft,
  PrimaryMotivation,
  RunGoalType,
  TrainingPlanPhase,
  TrainingStimulus,
} from "./types.js";

export const PLANNER_POLICY_VERSION = "running-dose-v3";

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
    targetDate?: string | Date | null;
    targetDistanceMeters?: number | null;
    eventIntent?: "finish" | "perform" | "targetTime" | null;
    targetTimeSeconds?: number | null;
    reviewHorizonWeeks?: 4 | 8 | 12 | null;
    constraints?: Record<string, unknown>;
  };
  athleteState: AthleteTrainingStateSnapshot;
  now?: Date;
  /** Account-local date label encoded at UTC midnight, separate from the evidence clock. */
  scheduleStart?: Date;
  reason?: string;
  runWalkProgramme?: RunWalkProgramme;
}

export function normalizeGoalInput(input: CreateTrainingGoalInput) {
  const longDays = preferredLongRunDays(input.constraints);
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
    targetDate: input.targetDate ?? null,
    targetDistanceMeters: input.targetDistanceMeters ?? null,
    eventIntent: input.eventIntent ?? null,
    targetTimeSeconds: input.targetTimeSeconds ?? null,
    reviewHorizonWeeks: input.reviewHorizonWeeks ?? null,
    constraints: { ...input.constraints,
      ...(input.constraints?.preferredLongRunDays !== undefined ? { preferredLongRunDays: longDays } : {}),
      shortRunSessions: String(input.constraints?.shortRunSessions === true || input.constraints?.shortRunSessions === "true"), optionalMobility: String(input.constraints?.optionalMobility === true || input.constraints?.optionalMobility === "true") },
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
  const scheduleStart = input.scheduleStart ?? startOfDay(now);
  const calendarStart = mondayDateLabel(scheduleStart);
  const longDays = preferredLongRunDays(input.goal.constraints);
  const weekDates = longDays.length ? scheduledDates({ now: calendarStart, preferredDays: input.goal.preferredDays, preferredLongSessionDay: null,
    sessionsPerWeek: input.goal.daysPerWeekTarget, horizonDays: 7 }) : [];
  const weekModalities = longRunWeekModalities(input.goal, weekDates, longDays);
  const explicitRunCount = weekModalities ? [...weekModalities.values()].filter((activity) => activity === "run").length : undefined;
  const initialBudget = runningDoseBudget(input.goal, input.athleteState, input.runWalkProgramme, false, explicitRunCount);
  let programme = input.runWalkProgramme ?? evaluateRunWalkProgramme({ enabled: input.goal.activities.includes("run") && input.goal.baselineContext !== "currentlyActive",
    now, calendarDate: scheduleStart, evidence: [], athleteState: input.athleteState, initialSessionSeconds: (initialBudget?.ordinarySessionMinutes ?? 25) * 60,
    sessionCapSeconds: input.goal.maxSessionMinutes * 60 }).state;
  let budget = runningDoseBudget(input.goal, input.athleteState, programme, false, explicitRunCount);
  if (longDays.length && programme?.status === "active") throw new LongRunDaysError("programme");
  const effectiveGoal = programme?.status === "completed" ? { ...input.goal, baselineContext: "currentlyActive" } : input.goal;
  const phase = phaseForGoal(input.goal, scheduleStart);
  const dates = scheduledDates({ now: calendarStart, preferredDays: input.goal.preferredDays, preferredLongSessionDay: longDays.length ? null : input.goal.preferredLongSessionDay,
    sessionsPerWeek: input.goal.daysPerWeekTarget, horizonDays: horizonDaysFor(input.goal, calendarStart) })
    .filter((date) => !input.goal.activities.includes("run") || input.goal.type !== "eventPreparation" || !input.goal.targetDate || date < startOfDay(new Date(input.goal.targetDate)));
  const render = () => dates.map((date, index) => workoutForDate({ date, index, total: dates.length,
    isPreferredLongSessionDay: longDays.length ? longDays.some((day) => isDay(date, day)) : isDay(date, input.goal.preferredLongSessionDay),
    explicitModality: weekModalities?.get(date.getUTCDay()), longDays, goal: effectiveGoal, athleteState: input.athleteState,
    phase: input.goal.activities.includes("run") ? phaseForGoal(input.goal, date) : phase, budget, programme }));
  let workouts = render();
  const runCounts = [0, 0];
  for (const row of workouts) if (row.modality === "run") runCounts[Math.min(1, Math.floor((row.scheduledDate.getTime() - calendarStart.getTime()) / (7 * 86400000)))]++;
  const actualRunningSlots = Math.max(...runCounts);
  if (!weekModalities && budget && actualRunningSlots > 0 && actualRunningSlots !== budget.sessionsPerWeek) {
    budget = runningDoseBudget(input.goal, input.athleteState, programme, false, actualRunningSlots);
    if (programme?.status === "active") programme = { ...programme, sessionTotalSeconds: Math.min(programme.sessionTotalSeconds, budget!.ordinarySessionMinutes * 60) };
    workouts = render();
  }
  const balancedWorkouts = balanceRunningWeek(workouts, input, budget, programme);
  const withOptionalMobility = input.goal.constraints?.optionalMobility === "true"
    ? balancedWorkouts.flatMap((workout) => [workout, {
        ...adapterFor("mobility", "mobility").generateWorkout({ scheduledDate: workout.scheduledDate, modality: "mobility", stimulus: "mobility", durationMinutes: 10, isKeyWorkout: false, athleteState: input.athleteState }),
        prescription: { optional: true },
      }]) : balancedWorkouts;

  const issuedWorkouts = withOptionalMobility.filter((workout) => workout.scheduledDate >= scheduleStart);
  return {
    summary: `${summaryPrefix}: ${issuedWorkouts.filter((workout) => workout.prescription.optional !== true).length} sessions over the next two weeks.`,
    phase,
    workouts: issuedWorkouts.map((workout) => stampIssuedRunningDose(applyRunningBenchmark(workout, input.goal.constraints, now), programme)),
    engineDecision: {
      runningDosePolicy: RUNNING_DOSE_POLICY,
      runningDoseBasis: budget?.basis ?? null,
      explicitLongRunDays: longDays,
      runWalkProgramme: programme ?? null,
      effectiveBaselineContext: effectiveGoal.baselineContext,
      runningBenchmark: runningBenchmarkDecision(input.goal.constraints, now),
      plannerPolicyVersion: PLANNER_POLICY_VERSION,
      runStructureVersion: RUN_STRUCTURE_VERSION,
      reportedEffortLoadAvailable: ((input.athleteState.modalityBreakdown.run as { sessionEffortLoad?: { comparable?: boolean } } | undefined)?.sessionEffortLoad?.comparable === true),
      phase,
      runHistoryLongSessionBalanced: balancedWorkouts !== workouts,
      reason: input.reason ?? "initial",
      horizonDays: 14,
      sessions: workouts.length,
      activities: input.goal.activities,
      objective: input.goal.type,
      baselineContext: input.goal.baselineContext,
      preferredRunGoalType: input.goal.preferredRunGoalType,
      fatigueRisk: input.athleteState.fatigueRisk,
      adherenceRate: input.athleteState.adherenceRate,
      consistencyScore: input.athleteState.consistencyScore,
      targetDate: input.goal.targetDate ?? null,
      targetDistanceMeters: input.goal.targetDistanceMeters ?? null,
      eventIntent: input.goal.eventIntent ?? null,
      targetTimeSeconds: input.goal.targetTimeSeconds ?? null,
      reviewHorizonWeeks: input.goal.reviewHorizonWeeks ?? null,
    },
  };
}

/** Allocate the weekly budget with a separate evidenced long slot, then taper it. */
function balanceRunningWeek(workouts: PlannedWorkoutDraft[], input: GeneratePlanInput, budget?: RunningDoseBudget, programme?: RunWalkProgramme): PlannedWorkoutDraft[] {
  if (!budget) return workouts;
  const result = [...workouts];
  const longDays = preferredLongRunDays(input.goal.constraints);
  const allocation = longDays.length ? longRunAllocation({ sessions: budget.sessionsPerWeek, longSessions: longDays.length,
    weeklySeconds: budget.targetWeeklyMinutes * 60, ordinaryCeiling: budget.perSessionCeilingMinutes * 60,
    longCeiling: budget.longSessionCeilingMinutes * 60, minimum: budget.minimumMinutes * 60 }) : undefined;
  const weekKeys = [...new Set(workouts.map((row) => mondayDateLabel(row.scheduledDate).getTime()))];
  for (const weekKey of weekKeys) {
    const week = workouts.filter((row) => mondayDateLabel(row.scheduledDate).getTime() === weekKey && row.modality === "run");
    if (!week.length) continue;
    if (allocation) {
      for (const row of week) {
        const selected = longDays.some((day) => isDay(row.scheduledDate, day));
        // Prior hard work, pain/fatigue and the race approach may override a long slot.
        const base = selected && row.stimulus === "longEndurance" ? allocation.longSeconds : allocation.ordinarySeconds;
        const phase = phaseForGoal(input.goal, row.scheduledDate);
        const safetyReduction = row.stimulus === "recovery" || input.athleteState.fatigueRisk === "high";
        const factor = safetyReduction ? .7 : phase === "taper" ? .8 : 1;
        const floor = safetyReduction ? Math.min(900, base) : budget.minimumMinutes * 60;
        const seconds = Math.min(base, input.goal.maxSessionMinutes * 60, Math.max(floor, Math.floor(base * factor)));
        result[workouts.indexOf(row)] = regenerate(row, seconds, row.stimulus);
      }
      continue;
    }
    const candidate = week.find((row) => row.stimulus === "longEndurance");
    const ordinaryCeiling = budget.perSessionCeilingMinutes * 60;
    const longCeiling = budget.longSessionCeilingMinutes * 60;
    const minimum = budget.minimumMinutes * 60;
    const mayHaveLong = candidate && programme?.status !== "active" && longCeiling >= ordinaryCeiling * 1.15 && longCeiling - ordinaryCeiling >= 300;
    const target = Math.min(budget.targetWeeklyMinutes * 60 * week.length / budget.sessionsPerWeek,
      ordinaryCeiling * (week.length - (mayHaveLong ? 1 : 0)) + (mayHaveLong ? longCeiling : 0));
    const longSeconds = mayHaveLong ? Math.min(longCeiling, target - minimum * (week.length - 1)) : 0;
    const ordinarySeconds = Math.min(ordinaryCeiling, (target - longSeconds) / Math.max(1, week.length - (mayHaveLong ? 1 : 0)));
    const meaningfulLong = mayHaveLong && longSeconds >= ordinarySeconds * 1.15 && longSeconds - ordinarySeconds >= 300;
    for (const row of week) {
      const stimulus = row === candidate && !meaningfulLong ? "easyAerobic" : row.stimulus;
      const base = meaningfulLong && row === candidate ? longSeconds : meaningfulLong ? ordinarySeconds : Math.min(ordinaryCeiling, target / week.length);
      const phase = phaseForGoal(input.goal, row.scheduledDate);
      const safetyReduction = stimulus === "recovery" || input.athleteState.fatigueRisk === "high";
      const factor = safetyReduction ? .7 : phase === "taper" ? .8 : 1;
      const floor = safetyReduction ? Math.min(900, base) : minimum;
      const seconds = Math.min(base, input.goal.maxSessionMinutes * 60, Math.max(floor, Math.floor(base * factor)));
      result[workouts.indexOf(row)] = regenerate(row, seconds, stimulus);
    }
  }
  for (const row of [...result]) {
    if (row.modality !== "run" || !["threshold", "speed"].includes(row.stimulus)) continue;
    if (result.some((other) => other !== row && other.modality === "run" && ["longEndurance", "threshold", "speed"].includes(other.stimulus)
        && Math.abs(other.scheduledDate.getTime() - row.scheduledDate.getTime()) < 48 * 3600000)) {
      result[result.indexOf(row)] = regenerate(row, row.durationSeconds, "easyAerobic");
    }
  }
  return result;
  function regenerate(row: PlannedWorkoutDraft, seconds: number, stimulus: TrainingStimulus) {
    const generated = adapterFor("run", stimulus).generateWorkout({ scheduledDate: row.scheduledDate, modality: "run", stimulus, durationMinutes: seconds / 60,
      allowShortSession: allowsShortRuns(input.goal) || stimulus === "recovery" || input.athleteState.fatigueRisk === "high", baselineContext: programme?.status === "completed" ? "currentlyActive" : input.goal.baselineContext,
      runWalk: programme?.status === "active", runWalkStage: programme?.status === "active" ? stageFor(programme) : undefined, athleteState: input.athleteState,
      distanceMeters: row.distanceMeters, targetCalories: row.targetCalories });
    return row.prescription.eventTargetPaceSecondsPerKilometer == null ? generated : { ...generated,
      prescription: { ...generated.prescription, eventTargetPaceSecondsPerKilometer: row.prescription.eventTargetPaceSecondsPerKilometer } };
  }
}
function stageFor(programme: RunWalkProgramme) {
  const ratio = RUN_WALK_LADDER[programme.stageIndex];
  return ratio ? { runSeconds: ratio[0], walkSeconds: ratio[1], continuousTrial: false }
    : { runSeconds: programme.sessionTotalSeconds, walkSeconds: 0, continuousTrial: true };
}

function workoutForDate(params: {
  date: Date;
  index: number;
  total: number;
  isPreferredLongSessionDay: boolean;
  explicitModality?: Modality;
  longDays?: string[];
  goal: GeneratePlanInput["goal"];
  athleteState: AthleteTrainingStateSnapshot;
  phase: TrainingPlanPhase;
  budget?: RunningDoseBudget;
  programme?: RunWalkProgramme;
}): PlannedWorkoutDraft {
  let stimulus = stimulusFor(
    params.index,
    params.total,
    params.goal,
    params.athleteState,
    params.isPreferredLongSessionDay,
    params.phase
  );
  if (params.longDays?.length && stimulus === "longEndurance" && !params.isPreferredLongSessionDay) stimulus = "easyAerobic";
  const modality = params.explicitModality ?? modalityFor(params.goal, stimulus, params.index);
  if (params.explicitModality && !activitySupports(modality, stimulus)) stimulus = "easyAerobic";
  if (modality === "run") {
    const run = params.athleteState.modalityBreakdown.run as { lastReportedHardAt?: string } | undefined;
    const recentHard = Math.max(params.athleteState.lastHardWorkoutAt?.getTime() ?? 0, run?.lastReportedHardAt ? new Date(run.lastReportedHardAt).getTime() : 0);
    const daysToEvent = daysUntil(params.goal.targetDate, params.date);
    const longDays = params.longDays?.length ? params.longDays : [params.goal.preferredLongSessionDay].filter((day): day is string => day != null);
    // Weekday checks include the next/previous cycle outside this 14-day window.
    const nearLong = longDays.some((day) => [1, -1].some((offset) => isDay(addDays(params.date, offset), day)));
    if (params.programme?.status === "active" || recentHard > params.date.getTime() - 48 * 3600000 || daysToEvent != null && daysToEvent <= 2
        || ["threshold", "speed"].includes(stimulus) && (nearLong || params.goal.daysPerWeekTarget < 3)) stimulus = "easyAerobic";
    if (stimulus === "threshold" && (params.goal.type === "speed" || (params.goal.targetDistanceMeters ?? Infinity) <= 10000) && Math.floor(params.index / params.goal.daysPerWeekTarget) % 2 === 1) stimulus = "speed";
  }
  const durationMinutes = durationFor(stimulus, params.goal, params.athleteState, params.phase, modality === "run" ? params.budget : undefined);
  const adapter = adapterFor(modality, stimulus);
  const workout = adapter.generateWorkout({
    scheduledDate: params.date,
    modality,
    stimulus,
    durationMinutes,
    allowShortSession: allowsShortRuns(params.goal),
    baselineContext: params.goal.baselineContext,
    runWalk: params.programme?.status === "active",
    runWalkStage: params.programme?.status === "active" ? stageFor(params.programme) : undefined,
    isKeyWorkout: stimulus === "longEndurance" || stimulus === "threshold" || stimulus === "strength",
    athleteState: params.athleteState,
  });
  const targetPace = eventTargetPaceSecondsPerKilometer(params.goal);
  if (targetPace == null || modality !== "run" || stimulus !== "threshold") return workout;
  return {
    ...workout,
    prescription: {
      ...workout.prescription,
      eventTargetPaceSecondsPerKilometer: targetPace,
    },
  };
}

function stimulusFor(
  index: number,
  total: number,
  goal: GeneratePlanInput["goal"],
  athleteState: AthleteTrainingStateSnapshot,
  isPreferredLongSessionDay: boolean,
  phase: TrainingPlanPhase
): TrainingStimulus {
  // Required slots retain their selected sport. Optional mobility never replaces a run.
  if (athleteState.fatigueRisk === "high") return "recovery";
  const sessionsPerWeek = Math.max(1, goal.daysPerWeekTarget);
  if (sessionsPerWeek > 1 && isPreferredLongSessionDay) return "longEndurance";
  const positionInWeek = index % sessionsPerWeek;
  if (positionInWeek === sessionsPerWeek - 1 && total >= 2 && (!goal.activities.includes("run") || !goal.preferredLongSessionDay)) return "longEndurance";
  if (phase === "taper" && positionInWeek !== 0) return "easyAerobic";
  if (goal.baselineContext === "currentlyActive" && sessionsPerWeek >= 3
      && positionInWeek === 1
      && athleteState.fatigueRisk === "low"
      && athleteState.adherenceRate >= 0.5) {
    const hasQualityActivity = goal.activities.some((activity) => activity === "run" || activity === "bike");
    const qualityFocusedGoal = goal.type === "speed"
      || (goal.type === "eventPreparation" && goal.eventIntent !== "finish");
    return hasQualityActivity && qualityFocusedGoal ? "threshold" : "easyAerobic";
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
  athleteState: AthleteTrainingStateSnapshot,
  phase: TrainingPlanPhase,
  budget?: RunningDoseBudget
): number {
  if (budget) {
    const ordinary = budget.ordinarySessionMinutes;
    const factor = stimulus === "recovery" || athleteState.fatigueRisk === "high" ? .7 : phase === "taper" ? .8 : phase === "sharpen" ? .95 : 1;
    const minimum = stimulus === "recovery" || athleteState.fatigueRisk === "high" ? Math.min(15, ordinary) : budget.minimumMinutes;
    return Math.min(goal.maxSessionMinutes, ordinary, Math.max(minimum, Math.floor(ordinary * factor)));
  }
  const baseline = athleteState.fourWeekAvgMinutes > 0
    ? Math.max(20, Math.round(athleteState.fourWeekAvgMinutes / Math.max(1, goal.daysPerWeekTarget)))
    : Math.min(goal.maxSessionMinutes, 30);
  // The saved cap includes preparation and cooldown. A sub-25-minute total
  // requires an explicit short-session choice, never inferred poor adherence.
  const cap = allowsShortRuns(goal) ? goal.maxSessionMinutes : Math.max(25, goal.maxSessionMinutes);
  const riskMultiplier = goal.riskTolerance === "stretch" ? 1.12 : goal.riskTolerance === "conservative" ? 0.88 : 1;
  const adherenceMultiplier = athleteState.adherenceRate < 0.5
    ? 0.85
    : athleteState.adherenceRate < 0.75 ? 0.93 : 1;
  const progressionMultiplier = riskMultiplier * adherenceMultiplier;
  const phaseMultiplier = phase === "taper" ? 0.8 : phase === "sharpen" ? 0.95 : 1;

  switch (stimulus) {
    case "longEndurance": {
      if (phase === "taper") return Math.min(cap, Math.max(20, Math.round(baseline * phaseMultiplier)));
      const minimumProgression = athleteState.adherenceRate < 0.75 ? 5 : 10;
      const distanceMultiplier = longSessionMultiplier(goal.targetDistanceMeters);
      return Math.min(cap, Math.max(baseline + minimumProgression, Math.round(baseline * distanceMultiplier * progressionMultiplier)));
    }
    case "threshold":
    case "speed":
      return Math.min(cap, Math.max(25, Math.round(baseline * progressionMultiplier * phaseMultiplier)));
    case "strength":
      return Math.min(cap, Math.max(25, baseline));
    case "mobility":
      return Math.min(20, Math.max(10, Math.round(baseline * 0.5)));
    case "recovery":
      return Math.min(cap, Math.max(15, Math.round(baseline * 0.7)));
    default:
      return Math.min(cap, Math.max(20, Math.round(baseline * progressionMultiplier * phaseMultiplier)));
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
  // Fill a partial/invalid day selection to honor the promised frequency.
  preferred = [...new Set(preferred.filter((day) => dayIndexFor(day) !== null))];
  for (const day of evenlySpacedDays(params.now, 7)) {
    if (preferred.length >= params.sessionsPerWeek) break;
    if (!preferred.some((selected) => dayIndexFor(selected) === dayIndexFor(day))) preferred.push(day);
  }
  const preferredIndexes = new Set(preferred.map(dayIndexFor).filter((day): day is number => day !== null));
  const dates: Date[] = [];

  for (let offset = 0; offset < params.horizonDays; offset += 1) {
    const date = startOfDay(addDays(params.now, offset));
    if (preferredIndexes.has(date.getUTCDay())) {
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
  const start = now.getUTCDay();
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
  return dayIndexFor(day) === date.getUTCDay();
}

export function phaseForGoal(goal: GeneratePlanInput["goal"], now: Date): TrainingPlanPhase {
  if (goal.type !== "eventPreparation") return "base";
  const days = daysUntil(goal.targetDate, now);
  if (days != null && days < 0) return days >= -14 ? "recovery" : "maintenance";
  if (days == null || days > 112) return "base";
  const taperDays = raceTaperDays(goal);
  if (days <= taperDays) return "taper";
  if (days <= 49) return "sharpen";
  return "build";
}

function horizonDaysFor(goal: GeneratePlanInput["goal"], now: Date) {
  const days = daysUntil(goal.targetDate, now);
  return days == null ? 14 : days < 0 ? 0 : Math.max(1, Math.min(14, days + 1));
}

function daysUntil(value: string | Date | null | undefined, now: Date) {
  if (!value) return null;
  const target = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(target.getTime())) return null;
  return Math.ceil((target.getTime() - startOfDay(now).getTime()) / 86_400_000);
}

function longSessionMultiplier(distanceMeters: number | null | undefined) {
  if (!distanceMeters) return 1.35;
  if (distanceMeters <= 5_000) return 1.15;
  if (distanceMeters <= 10_000) return 1.25;
  if (distanceMeters <= 21_097.5) return 1.35;
  return 1.45;
}

function eventTargetPaceSecondsPerKilometer(goal: GeneratePlanInput["goal"]) {
  if (goal.eventIntent !== "targetTime"
      || !goal.targetTimeSeconds
      || !goal.targetDistanceMeters
      || goal.targetDistanceMeters <= 0) return null;
  const pace = Math.round(goal.targetTimeSeconds / (goal.targetDistanceMeters / 1_000));
  return pace >= 150 && pace <= 1_200 ? pace : null;
}

export function allowsShortRuns(goal: GeneratePlanInput["goal"]): boolean {
  return goal.constraints?.shortRunSessions === "true" || goal.constraints?.shortRunSessions === true;
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
  result.setUTCDate(result.getUTCDate() + days);
  return result;
}

function startOfDay(date: Date): Date {
  const result = new Date(date);
  result.setUTCHours(0, 0, 0, 0);
  return result;
}
