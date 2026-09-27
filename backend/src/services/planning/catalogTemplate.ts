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
  const firstDay = startOfDay(now);
  const monday = startOfWeek(firstDay);
  const windowEnd = addDays(monday, 14);
  const workouts = recommendation.template.weeks.slice(0, 2).flatMap((week, weekIndex) =>
    week.workouts
      .filter((workout) => !workout.isOptional && workout.durationSeconds > 0)
      .map((workout) => ({ workout, scheduledDate: dateForWorkout(workout, weekIndex, monday) }))
      .filter(({ scheduledDate }) => scheduledDate >= firstDay && scheduledDate < windowEnd)
      .map(({ workout, scheduledDate }) => toPlannedWorkout(workout, recommendation.template.sport, scheduledDate, recommendation.template.id, weekIndex + 1))
  );

  if (workouts.length === 0) {
    throw new Error("The selected catalog plan has no upcoming workouts to schedule.");
  }
  return workouts;
}

function dateForWorkout(workout: TrainingPlanWorkout, weekIndex: number, monday: Date): Date {
  const dayIndex = weekdayIndex(workout.dayLabel);
  if (dayIndex == null) throw new Error(`Catalog workout ${workout.id} has an unsupported day label.`);
  return addDays(monday, weekIndex * 7 + dayIndex);
}

function toPlannedWorkout(
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
    kind: step.kind,
    durationSeconds: step.durationSeconds,
    detail: step.detail ?? null,
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
  const mondayOffset = (result.getDay() + 6) % 7;
  result.setDate(result.getDate() - mondayOffset);
  return result;
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
