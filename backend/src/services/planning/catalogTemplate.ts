import { synchronizeRunningPrescription } from "./runningPrescription.js";
import type { Modality, PlannedWorkoutDraft, TrainingStimulus } from "./types.js";
import type {
  TrainingPlanFocus,
  TrainingPlanRecommendation,
  TrainingPlanSport,
  TrainingPlanWorkout,
} from "../trainingPlans.js";

export interface CatalogRecommendationSelection {
  candidateID: string;
  templateID: string;
}

export function readCatalogRecommendationSelection(
  constraints: Record<string, unknown> | undefined
): CatalogRecommendationSelection | null {
  const candidateID = constraints?.candidateID;
  const templateID = constraints?.templateID;
  if (candidateID == null && templateID == null) return null;
  if (typeof candidateID !== "string" || candidateID.length === 0 ||
      typeof templateID !== "string" || templateID.length === 0) {
    throw new Error("Both recommendation candidateID and templateID are required to select a catalog plan.");
  }
  return { candidateID, templateID };
}

export function catalogFocusGoalType(focus: TrainingPlanFocus): string {
  switch (focus) {
    case "comeback": return "healthEnergy";
    case "consistency": return "endurance";
    default: return "eventPreparation";
  }
}

export function catalogFocusDistanceMeters(focus: TrainingPlanFocus): number | null {
  switch (focus) {
    case "fiveK": return 5_000;
    case "tenK": return 10_000;
    case "tenMile": return 16_093.4;
    case "halfMarathon": return 21_097.5;
    case "marathon": return 42_195;
    default: return null;
  }
}

export function instantiateCatalogRecommendation(
  recommendation: TrainingPlanRecommendation,
  now: Date = new Date()
): PlannedWorkoutDraft[] {
  const monday = startOfWeek(now);
  return instantiateCatalogWeek(recommendation.template, 1, monday, now)
    .concat(instantiateCatalogWeek(recommendation.template, 2, addDays(monday, 7), now));
}

/** Source sequence stays intact; only dates and bounded session durations change. */
export function instantiateCatalogWeek(
  template: import("../trainingPlans.js").TrainingPlanTemplate,
  weekIndex: number,
  anchor: Date,
  now: Date,
  schedule?: { preferredDays: string[]; daysPerWeekTarget: number; maxSessionMinutes: number },
): PlannedWorkoutDraft[] {
  const source = template.weeks[weekIndex - 1];
  if (!source) return [];
  const required = source.workouts.filter((workout) => !workout.isOptional && workout.durationSeconds > 0);
  const exposureSchedule = template.sport === "run" && template.weeks[0].workouts.some((row) => !row.isOptional && row.kind === "walkRun");
  if (schedule && (schedule.daysPerWeekTarget < (exposureSchedule ? 1 : template.minSessionsPerWeek) || schedule.daysPerWeekTarget > template.maxSessionsPerWeek)) {
    console.info("[planning] catalog_programme_validation", { operation: "schedule", category: "unsupported_frequency" });
    throw new Error("The selected programme does not support that weekly session frequency.");
  }
  const count = Math.min(required.length, schedule?.daysPerWeekTarget ?? required.length);
  // On reduced-frequency weeks retain long-easy work and one easy session;
  // allow a quality session only when at least three days are available.
  const firstEasy = required.find((workout) => ["easy", "recovery", "walkRun"].includes(workout.kind));
  const priority = (workout: TrainingPlanWorkout) => ["longRun", "race"].includes(workout.kind) ? 0
    : workout === firstEasy ? 1
    : count >= 3 && ["tempo", "interval", "fartlek", "hill", "racePrep", "race"].includes(workout.kind) ? 2 : 3;
  const chosen = new Set([...required].sort((a, b) => priority(a) - priority(b)).slice(0, count));
  const preferred = [...new Set((schedule?.preferredDays ?? []).map(weekdayIndex).filter((day): day is number => day != null))].sort((a, b) => a - b);
  if (preferred.length) {
    for (const workout of required) {
      const index = weekdayIndex(workout.dayLabel);
      if (preferred.length >= count) break;
      if (index != null && !preferred.includes(index)) preferred.push(index);
    }
    for (let index = 0; preferred.length < count && index < 7; index++) if (!preferred.includes(index)) preferred.push(index);
    preferred.sort((a, b) => a - b);
  }
  // Retain the source's ordered workouts rather than inventing catch-up sessions.
  return required.filter((workout) => chosen.has(workout)).flatMap((workout, index) => {
    const offset = preferred.length ? preferred[index] : weekdayIndex(workout.dayLabel);
    if (offset == null) return [];
    const scheduledDate = addDays(anchor, offset);
    if (scheduledDate < startOfDay(now)) return [];
    const draft = toPlannedWorkout(workout, template.sport, scheduledDate, template.id, weekIndex);
    const cap = (schedule?.maxSessionMinutes ?? 180) * 60;
    // Scale timed phases together, preserving every walk/run phase and its order.
    // The source already carries short-session exceptions for beginner run/walk.
    const total = draft.blocks.flatMap((block) => block.steps).reduce((sum, step) => sum + (step.durationSeconds ?? 0), 0);
    const target = Math.min(draft.durationSeconds, cap);
    if (total > 0) {
      const steps = draft.blocks[0].steps;
      let allocated = 0;
      for (const [i, step] of steps.entries()) {
        step.durationSeconds = i === steps.length - 1 ? target - allocated : Math.max(1, Math.floor((step.durationSeconds ?? 0) * target / total));
        allocated += step.durationSeconds;
      }
      draft.prescription.steps = steps;
    }
    draft.durationSeconds = target;
    draft.blocks[0].durationSeconds = target;
    return [synchronizeRunningPrescription(draft)];
  });
}

export function toPlannedWorkout(
  workout: TrainingPlanWorkout,
  sport: TrainingPlanSport,
  scheduledDate: Date,
  templateID: string,
  weekIndex: number
): PlannedWorkoutDraft {
  const modality = modalityFor(sport, workout.kind);
  const stimulus = stimulusFor(workout.kind);
  const isKeyWorkout = ["tempo", "interval", "fartlek", "hill", "longRun", "racePrep", "race"].includes(workout.kind);
  const steps = workout.steps.map((step) => ({
    label: step.label,
    // The source uses steady rows for its explicit fartlek surges; preserve that role.
    kind: workout.kind === "fartlek" && step.kind === "steady" ? "fartlek" : step.kind,
    durationSeconds: step.durationSeconds,
    detail: step.detail ?? null,
    target: { rpe: workout.kind === "fartlek" && step.kind === "steady" ? [5, 6] : ["tempo"].includes(step.kind) ? [6, 7] : ["interval"].includes(step.kind) ? [7, 8]
      : ["walk", "cooldown", "recovery"].includes(step.kind) ? [1, 3] : step.kind === "race" ? [6, 8] : [2, 4] },
  }));

  return {
    scheduledDate,
    modality,
    stimulus,
    title: workout.title,
    durationSeconds: workout.durationSeconds,
    distanceMeters: null,
    intensityModel: "catalog",
    intensityTarget: { effortLabel: workout.effortLabel },
    prescription: {
      source: "trainingPlanCatalog",
      sourceWorkoutKind: workout.kind,
      runWalk: workout.kind === "walkRun",
      templateID,
      weekIndex,
      workoutID: workout.id,
      summary: workout.summary,
      purpose: workout.purpose,
      guideCue: workout.guideCue,
      effortLabel: workout.effortLabel,
      distanceLabel: workout.distanceLabel ?? null,
      steps,
    },
    isKeyWorkout,
    blocks: [{
      blockType: blockTypeFor(workout.kind),
      modality,
      stimulus,
      durationSeconds: workout.durationSeconds,
      metadata: {
        source: "trainingPlanCatalog",
        templateID,
        weekIndex,
        workoutID: workout.id,
        summary: workout.summary,
        purpose: workout.purpose,
        guideCue: workout.guideCue,
        effortLabel: workout.effortLabel,
      },
      steps,
    }],
  };
}

function modalityFor(sport: TrainingPlanSport, kind: TrainingPlanWorkout["kind"]): Modality {
  if (sport === "walk") return "walk";
  if (sport === "bike") return "bike";
  if (sport === "mixed" && kind === "crossTrain") return "bike";
  return "run";
}

function stimulusFor(kind: TrainingPlanWorkout["kind"]): TrainingStimulus {
  switch (kind) {
    case "recovery": return "recovery";
    case "tempo":
    case "fartlek": return "threshold";
    case "interval":
    case "hill": return "speed";
    case "longRun": return "longEndurance";
    case "crossTrain": return "strength";
    default: return "easyAerobic";
  }
}

function blockTypeFor(kind: TrainingPlanWorkout["kind"]): string {
  switch (kind) {
    case "longRun": return "longEndurance";
    case "crossTrain": return "crossTrain";
    case "walkRun": return "main";
    default: return kind;
  }
}

function weekdayIndex(dayLabel: string): number | null {
  const day = dayLabel.trim().slice(0, 3).toLowerCase();
  const index = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"].indexOf(day);
  return index < 0 ? null : index;
}

function startOfWeek(date: Date): Date {
  const result = startOfDay(date);
  const mondayOffset = (result.getUTCDay() + 6) % 7;
  result.setUTCDate(result.getUTCDate() - mondayOffset);
  return result;
}

function startOfDay(date: Date): Date {
  const result = new Date(date);
  result.setUTCHours(0, 0, 0, 0);
  return result;
}

function addDays(date: Date, days: number): Date {
  const result = new Date(date);
  result.setUTCDate(result.getUTCDate() + days);
  return result;
}
