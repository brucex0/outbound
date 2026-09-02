import type { ActivityForPlanning, PlannedWorkoutDraft, RunGoalType } from "./types.js";

export type RunPaceResolution = {
  paceSecondsPerKilometer: number | null;
  validRunCount: number;
  reliable: boolean;
  reason: "available" | "insufficient_history" | "missing_valid_pace";
};

export type RunCalorieEstimate = {
  targetCalories: number;
  distanceMeters: number;
  durationSeconds: number;
};

const MIN_VALID_RUN_DISTANCE_METERS = 500;
const MIN_VALID_RUN_DURATION_SECONDS = 5 * 60;
const MAX_VALID_RUN_DURATION_SECONDS = 12 * 60 * 60;
const MIN_VALID_PACE_SECONDS_PER_KILOMETER = 150;
const MAX_VALID_PACE_SECONDS_PER_KILOMETER = 1_200;

export function resolveLearnedRunPace(
  activities: ActivityForPlanning[],
  calibrationCompleted: boolean
): RunPaceResolution {
  const values = activities
    .filter((activity) => isRunType(activity.type))
    .filter((activity) => activity.distanceM != null && activity.distanceM >= MIN_VALID_RUN_DISTANCE_METERS)
    .filter((activity) => activity.durationSecs != null
      && activity.durationSecs >= MIN_VALID_RUN_DURATION_SECONDS
      && activity.durationSecs <= MAX_VALID_RUN_DURATION_SECONDS)
    .map((activity) => activity.avgPace
      ?? ((activity.durationSecs ?? 0) / ((activity.distanceM ?? 0) / 1_000)))
    .filter((pace) => Number.isFinite(pace)
      && pace >= MIN_VALID_PACE_SECONDS_PER_KILOMETER
      && pace <= MAX_VALID_PACE_SECONDS_PER_KILOMETER)
    .slice(0, 10)
    .sort((left, right) => left - right);

  const reliable = values.length >= 3 || (calibrationCompleted && values.length > 0);
  if (!reliable) {
    return {
      paceSecondsPerKilometer: null,
      validRunCount: values.length,
      reliable: false,
      reason: values.length === 0 ? "missing_valid_pace" : "insufficient_history",
    };
  }

  const midpoint = Math.floor(values.length / 2);
  const paceSecondsPerKilometer = values.length % 2 === 0
    ? (values[midpoint - 1] + values[midpoint]) / 2
    : values[midpoint];
  return {
    paceSecondsPerKilometer,
    validRunCount: values.length,
    reliable: true,
    reason: "available",
  };
}

export function estimateCalorieRunFromTarget(input: {
  targetCalories: number;
  weightKilograms: number;
  paceSecondsPerKilometer: number;
}): RunCalorieEstimate | null {
  if (!validWeight(input.weightKilograms)
    || !validPace(input.paceSecondsPerKilometer)
    || !Number.isFinite(input.targetCalories)
    || input.targetCalories <= 0) {
    return null;
  }
  const targetCalories = roundCalories(input.targetCalories);
  const distanceKilometers = targetCalories / input.weightKilograms;
  return {
    targetCalories,
    distanceMeters: Math.round(distanceKilometers * 1_000),
    durationSeconds: Math.max(60, Math.round(distanceKilometers * input.paceSecondsPerKilometer)),
  };
}

export function estimateCalorieRunFromDuration(input: {
  durationSeconds: number;
  weightKilograms: number;
  paceSecondsPerKilometer: number;
}): RunCalorieEstimate | null {
  if (!Number.isFinite(input.durationSeconds) || input.durationSeconds <= 0) return null;
  if (!validWeight(input.weightKilograms) || !validPace(input.paceSecondsPerKilometer)) return null;
  const distanceKilometers = input.durationSeconds / input.paceSecondsPerKilometer;
  return estimateCalorieRunFromTarget({
    targetCalories: input.weightKilograms * distanceKilometers,
    weightKilograms: input.weightKilograms,
    paceSecondsPerKilometer: input.paceSecondsPerKilometer,
  });
}

export function applyCalorieTargets(input: {
  workouts: PlannedWorkoutDraft[];
  preferredRunGoalType: RunGoalType;
  weightKilograms: number | null | undefined;
  pace: RunPaceResolution;
}): PlannedWorkoutDraft[] {
  if (input.preferredRunGoalType !== "calories"
    || !validWeight(input.weightKilograms)
    || !input.pace.reliable
    || input.pace.paceSecondsPerKilometer == null) {
    return input.workouts.map(clearCalorieTarget);
  }

  return input.workouts.map((workout) => {
    if (!isCalorieEligibleWorkout(workout)) return clearCalorieTarget(workout);
    const estimate = estimateCalorieRunFromDuration({
      durationSeconds: workout.durationSeconds,
      weightKilograms: input.weightKilograms!,
      paceSecondsPerKilometer: input.pace.paceSecondsPerKilometer!,
    });
    if (!estimate) return clearCalorieTarget(workout);
    return {
      ...workout,
      targetCalories: estimate.targetCalories,
      distanceMeters: estimate.distanceMeters,
      durationSeconds: estimate.durationSeconds,
      prescription: {
        ...workout.prescription,
        runGoalType: "calories",
        targetCalories: estimate.targetCalories,
        estimatedDistanceMeters: estimate.distanceMeters,
        estimatedDurationSeconds: estimate.durationSeconds,
      },
    };
  });
}

export function isCalorieEligibleWorkout(workout: Pick<PlannedWorkoutDraft, "modality" | "stimulus">): boolean {
  return workout.modality === "run" && (workout.stimulus === "easyAerobic" || workout.stimulus === "recovery");
}

export function roundCalories(value: number): number {
  return Math.max(50, Math.round(value / 25) * 25);
}

function clearCalorieTarget(workout: PlannedWorkoutDraft): PlannedWorkoutDraft {
  const prescription = { ...workout.prescription };
  delete prescription.runGoalType;
  delete prescription.targetCalories;
  delete prescription.estimatedDistanceMeters;
  delete prescription.estimatedDurationSeconds;
  return { ...workout, targetCalories: null, prescription };
}

function isRunType(type: string): boolean {
  return type.toLowerCase().includes("run");
}

function validWeight(value: number | null | undefined): value is number {
  return value != null && Number.isFinite(value) && value >= 25 && value <= 350;
}

function validPace(value: number): boolean {
  return Number.isFinite(value)
    && value >= MIN_VALID_PACE_SECONDS_PER_KILOMETER
    && value <= MAX_VALID_PACE_SECONDS_PER_KILOMETER;
}
