import { generateNextWindow, type GeneratePlanInput } from "./generator.js";
import { chooseBestCandidate } from "./scoring.js";
import type {
  AthleteTrainingStateSnapshot,
  PlanGenerationResult,
  PlannedWorkoutDraft,
  PlanningEventType,
  ReadinessForPlanning,
} from "./types.js";

export interface AdaptationInput {
  eventType: PlanningEventType;
  goal: GeneratePlanInput["goal"];
  athleteState: AthleteTrainingStateSnapshot;
  latestReadiness?: ReadinessForPlanning;
  now?: Date;
}

export interface AdaptationResult {
  shouldCreateVersion: boolean;
  reason: PlanningEventType;
  summary: string;
  workouts: PlannedWorkoutDraft[];
  engineDecision: Record<string, unknown>;
  adjustmentMessage: string;
}

export function adaptPlan(input: AdaptationInput): AdaptationResult {
  const now = input.now ?? new Date();
  const base = generateNextWindow({
    goal: input.goal,
    athleteState: input.athleteState,
    now,
    reason: input.eventType,
  });
  const result = resultForEvent(input, base);
  const candidate = chooseBestCandidate([
    {
      id: "balanced",
      workouts: result.workouts,
      summary: result.summary,
    },
  ], input.athleteState);

  return {
    shouldCreateVersion: shouldCreateVersion(input),
    reason: input.eventType,
    summary: candidate.summary,
    workouts: candidate.workouts,
    engineDecision: {
      ...result.engineDecision,
      candidate: candidate.id,
      fatigueRisk: input.athleteState.fatigueRisk,
    },
    adjustmentMessage: adjustmentMessageFor(input),
  };
}

function resultForEvent(input: AdaptationInput, base: PlanGenerationResult): PlanGenerationResult {
  if (input.eventType === "readinessSubmitted" && input.latestReadiness) {
    const lowReadiness =
      input.latestReadiness.illnessOrPain ||
      input.latestReadiness.energy <= 2 ||
      input.latestReadiness.soreness >= 4 ||
      input.latestReadiness.stress >= 4;

    if (lowReadiness) {
      return {
        ...base,
        summary: "Adjusted for today's readiness.",
        workouts: base.workouts.map((workout, index) =>
          index === 0
            ? softenWorkout(workout, input.latestReadiness?.illnessOrPain === true)
            : workout
        ),
      };
    }
  }

  if (input.eventType === "workoutSkipped") {
    return {
      ...base,
      summary: "Replanned after a skipped workout without cramming the missed work.",
      workouts: base.workouts.map((workout, index) =>
        index === 0 && workout.stimulus !== "recovery" ? softenWorkout(workout, false) : workout
      ),
    };
  }

  if (input.eventType === "painFlagged" || input.athleteState.fatigueRisk === "high") {
    return {
      ...base,
      summary: "Reduced near-term load to protect recovery.",
      workouts: base.workouts.map((workout, index) =>
        index <= 1 ? softenWorkout(workout, true) : workout
      ),
    };
  }

  return base;
}

function shouldCreateVersion(input: AdaptationInput): boolean {
  if (input.eventType === "readinessSubmitted") {
    return Boolean(
      input.latestReadiness?.illnessOrPain ||
      (input.latestReadiness?.energy ?? 5) <= 2 ||
      (input.latestReadiness?.soreness ?? 1) >= 4 ||
      (input.latestReadiness?.stress ?? 1) >= 4
    );
  }

  return [
    "workoutSkipped",
    "goalUpdated",
    "scheduleUpdated",
    "weeklyRollover",
    "manualRebuild",
    "painFlagged",
    "healthImportCompleted",
  ].includes(input.eventType) || input.athleteState.fatigueRisk === "high";
}

function softenWorkout(workout: PlannedWorkoutDraft, recoveryOnly: boolean): PlannedWorkoutDraft {
  const durationSeconds = recoveryOnly
    ? Math.min(workout.durationSeconds, 15 * 60)
    : Math.max(12 * 60, Math.round(workout.durationSeconds * 0.7));
  const title = recoveryOnly ? "Recovery reset" : `Lighter ${workout.title}`;
  const stimulus = recoveryOnly ? "mobility" : "recovery";
  const modality = recoveryOnly ? "mobility" : workout.modality;

  return {
    ...workout,
    title,
    modality,
    stimulus,
    durationSeconds,
    intensityModel: recoveryOnly ? "open" : workout.intensityModel,
    intensityTarget: recoveryOnly ? { effort: "gentle" } : { min: 2, max: 4 },
    prescription: {
      blocks: [
        {
          type: recoveryOnly ? "mobility" : "recovery",
          durationSeconds,
        },
      ],
    },
    isKeyWorkout: false,
    blocks: [
      {
        blockType: recoveryOnly ? "mobility" : "main",
        modality,
        stimulus,
        durationSeconds,
        metadata: {},
        steps: [
          {
            label: title,
            kind: stimulus,
            durationSeconds,
            target: recoveryOnly ? { effort: "gentle" } : { rpe: 3 },
            detail: recoveryOnly
              ? "Keep this restorative. Pain or illness beats training targets today."
              : "Keep it relaxed and let the routine count.",
          },
        ],
      },
    ],
  };
}

function adjustmentMessageFor(input: AdaptationInput): string {
  switch (input.eventType) {
    case "readinessSubmitted":
      return "Adjusted the plan using today's readiness.";
    case "workoutSkipped":
      return "Moved forward without cramming the skipped workout.";
    case "activityCompleted":
      return "Reassessed training state after the completed activity.";
    case "healthImportCompleted":
      return "Reassessed after imported activities.";
    case "painFlagged":
      return "Reduced training stress after a pain or illness flag.";
    case "weeklyRollover":
      return "Generated the next planning window.";
    case "manualRebuild":
      return "Rebuilt the near-term plan.";
    case "goalUpdated":
      return "Updated the plan around the new goal.";
    case "scheduleUpdated":
      return "Updated the plan around the new schedule.";
  }
}
