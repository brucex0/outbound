import { resizeTimedRunningWorkout } from "./runningPrescription.js";
import { allowsShortRuns, generateNextWindow, type GeneratePlanInput } from "./generator.js";
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
  basePlan?: PlanGenerationResult;
  runWalkProgramme?: GeneratePlanInput["runWalkProgramme"];
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
  const base = input.basePlan ?? generateNextWindow({
    goal: input.goal,
    runWalkProgramme: input.runWalkProgramme,
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
      phase: base.phase,
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
            ? softenWorkout(workout, input.latestReadiness?.illnessOrPain === true, allowsShortRuns(input.goal), input.goal.maxSessionMinutes * 60)
            : workout
        ),
      };
    }
  }

  if (input.eventType === "workoutSkipped" || input.eventType === "workoutMissed") {
    return {
      ...base,
      summary: "Replanned after a skipped workout without cramming the missed work.",
      workouts: base.workouts.map((workout, index) =>
        index === 0 && workout.stimulus !== "recovery" ? softenWorkout(workout, false, allowsShortRuns(input.goal), input.goal.maxSessionMinutes * 60) : workout
      ),
    };
  }

  if (
    input.eventType === "painFlagged"
    || input.athleteState.fatigueRisk === "high"
  ) {
    return {
      ...base,
      summary: "Reduced near-term load to protect recovery.",
      workouts: base.workouts.map((workout, index) =>
        index <= 1 ? softenWorkout(workout, true, allowsShortRuns(input.goal), input.goal.maxSessionMinutes * 60) : workout
      ),
    };
  }

  return base;
}

function shouldCreateVersion(input: AdaptationInput): boolean {
  if (input.eventType === "planReviewRequested") return false;

  // Activity completion is reassessed immediately, but meaningful load changes
  // become a confirmation proposal. Today can still react safely through the
  // activity-suggestion endpoint while the multi-workout change is pending.
  if (input.eventType === "activityCompleted") return false;

  if (input.eventType === "readinessSubmitted") {
    return Boolean(
      input.latestReadiness?.illnessOrPain ||
      (input.latestReadiness?.energy ?? 5) <= 2 ||
      (input.latestReadiness?.soreness ?? 1) >= 4 ||
      (input.latestReadiness?.stress ?? 1) >= 4
    );
  }

  const versionCreatingEvents: PlanningEventType[] = [
    "workoutSkipped",
    "goalUpdated",
    "scheduleUpdated",
    "weeklyRollover",
    "manualRebuild",
    "painFlagged",
    "healthImportCompleted",
    "workoutMissed",
  ];
  return versionCreatingEvents.includes(input.eventType)
    || input.athleteState.fatigueRisk === "high";
}

function softenWorkout(workout: PlannedWorkoutDraft, recoveryOnly: boolean, allowShortSession = false, capSeconds = Infinity): PlannedWorkoutDraft {
  const durationSeconds = Math.min(workout.durationSeconds, capSeconds, recoveryOnly
    ? Math.min(workout.durationSeconds, 15 * 60)
    : Math.max((workout.modality === "run" && !allowShortSession ? 15 : 10) * 60, Math.round(workout.durationSeconds * 0.7)));
  if (!recoveryOnly && workout.modality === "run") return resizeTimedRunningWorkout(workout, durationSeconds, true, !allowShortSession && durationSeconds > 900 ? 900 : 0);
  const title = recoveryOnly ? "Recovery reset" : workout.prescription.source === "trainingPlanCatalog"
    ? `Lighter ${workout.modality}` : `Lighter ${workout.title}`;
  const stimulus = recoveryOnly ? "mobility" : "recovery";
  const modality = recoveryOnly ? "mobility" : workout.modality;

  return {
    ...workout,
    title,
    modality,
    stimulus,
    durationSeconds,
    intensityModel: recoveryOnly ? "open" : workout.prescription.source === "trainingPlanCatalog" ? "rpe" : workout.intensityModel,
    intensityTarget: recoveryOnly ? { effort: "gentle" } : { min: 2, max: 4 },
    prescription: {
      ...workout.prescription,
      runWalk: false,
      workoutKind: "recovery", qualitySeconds: 0, intensitySeconds: { threshold: 0, speed: 0 },
      steps: [{ label: title, kind: stimulus, durationSeconds }],
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
      return "today.race_goal.missed";
    case "workoutMissed":
      return "today.race_goal.missed";
    case "dailyReview":
      return "Checked the plan during the daily review.";
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
    case "planReviewRequested":
      return "Reviewed the near-term plan at the runner's request.";
    case "goalUpdated":
      return "Updated the plan around the new goal.";
    case "scheduleUpdated":
      return "Updated the plan around the new schedule.";
  }
}
