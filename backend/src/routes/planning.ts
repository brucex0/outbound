import { recoveryChangeMessage } from "../services/personalization/workoutAdjustmentPolicy.js";
import { LongRunDaysError } from "../services/planning/longRunDays.js";
import { PerformedWorkoutConflictError, performedWorkoutReferenceSchema } from "../services/planning/workoutIssuance.js";
import { RunningScheduleError, ProgrammeTimelineError, ProgrammeConstraintError } from "../services/planning/runningDosePolicy.js";
import { GoalFeasibilityError } from "../services/planning/goalFeasibility.js";
import { RunningBenchmarkError, RunningBenchmarkConflictError } from "../services/planning/runningBenchmark.js";
import { Hono, type Context } from "hono";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";
import { requireDatabase } from "../services/database.js";
import { getAuthenticatedAppUser } from "../services/currentUser.js";
import {
  clearPlan,
  completeWorkout,
  createGoal,
  updateRaceGoal,
  updateRunningBenchmark,
  getActivitySuggestion,
  getAdjustments,
  getRecommendations,
  getState,
  getToday,
  rebuildPlan,
  skipWorkout,
  submitReadiness,
} from "../services/planning/planningService.js";
import type { AppEnv } from "../types/hono.js";
import { standaloneWorkoutCatalog } from "../data/standaloneWorkouts.js";
import {
  getPlanIntakeContext,
  PlanningContextChangedError,
  interpretPlanIntake,
  planIntakeInterpretSchema,
} from "../services/planning/planIntake.js";

import { applyWorkoutEdit, workoutEditApplySchema, WorkoutEditError } from "../services/planning/workoutEdits.js";

const router = new Hono<AppEnv>();

router.post("/workout-edits/apply", zValidator("json", workoutEditApplySchema), async (c) => {
  const user = await requirePlanningUser(c);
  if (user instanceof Response) return user;
  try { return c.json(await applyWorkoutEdit(user.id, c.req.valid("json"))); }
  catch (error) {
    const code = error && typeof error === "object" && "code" in error ? String(error.code) : "";
    console.error("[planning] workout_edit_apply_failed", { errorType: error instanceof Error ? error.name : "unknown",
      failureCode: /^(P\d{4}|E[A-Z_]{2,30})$/.test(code) ? code : "unknown", status: error instanceof WorkoutEditError ? error.status : 500 });
    return c.json({ error: error instanceof WorkoutEditError ? error.code === "recovery_change_required" ? recoveryChangeMessage(c.get("locale")) : error.message : "The workout change could not be confirmed. Retry the same change." }, error instanceof WorkoutEditError ? error.status : 500);
  }
});

router.get("/standalone-workouts", async (c) => {
  const user = await requirePlanningUser(c);
  if (user instanceof Response) return user;
  return c.json(standaloneWorkoutCatalog);
});

const objectiveSchema = z.enum(["eventPreparation", "endurance", "speed", "strength", "weightLoss", "healthEnergy"]);
const catalogFocusSchema = z.enum(["consistency", "comeback", "fiveK", "tenK", "tenMile", "halfMarathon", "marathon"]);
const goalTypeSchema = z.union([objectiveSchema, catalogFocusSchema]);
const activitySchema = z.enum(["run", "walk", "bike"]);
const goalSchema = z.object({
  runningBenchmark: z.unknown().optional(),
  type: goalTypeSchema,
  activities: z.array(activitySchema).min(1).max(3),
  baselineContext: z.enum(["startingOut", "currentlyActive", "returningAfterBreak"]).optional(),
  targetDate: z.string().optional().nullable(),
  targetDistanceMeters: z.number().positive().optional().nullable(),
  targetEventName: z.string().max(120).optional().nullable(),
  eventIntent: z.enum(["finish", "perform", "targetTime"]).optional().nullable(),
  targetTimeSeconds: z.number().int().positive().optional().nullable(),
  reviewHorizonWeeks: z.union([z.literal(4), z.literal(8), z.literal(12)]).optional().nullable(),
  successSignal: z.string().trim().max(120).optional().nullable(),
  goalDescription: z.string().trim().max(500).optional().nullable(),
  intakeContextVersion: z.string().max(240).optional().nullable(),
  priority: z.string().min(1).max(64).optional(),
  preferredDays: z.array(z.string().min(1).max(16)).optional(),
  preferredLongSessionDay: z.string().min(1).max(16).optional().nullable(),
  daysPerWeekTarget: z.number().int().min(1).max(6).optional(),
  maxSessionMinutes: z.number().int().min(10).max(180).optional(),
  riskTolerance: z.enum(["conservative", "balanced", "stretch"]).optional(),
  primaryMotivation: z.enum(["generalFitness", "consistency", "performance", "weightLoss", "weightMaintenance"]).optional(),
  preferredRunGoalType: z.enum(["time", "distance", "calories"]).optional(),
  constraints: z.record(z.unknown()).optional(),
});

const readinessSchema = z.object({
  date: z.string().optional(),
  energy: z.number().int().min(1).max(5).optional(),
  soreness: z.number().int().min(1).max(5).optional(),
  sleepQuality: z.number().int().min(1).max(5).optional(),
  stress: z.number().int().min(1).max(5).optional(),
  motivation: z.number().int().min(1).max(5).optional(),
  illnessOrPain: z.boolean().optional(),
  notes: z.string().max(1000).optional().nullable(),
});

const completionSchema = z.object({
  performedWorkoutReference: performedWorkoutReferenceSchema.optional(),
  workoutEditId: z.string().max(160).nullable().optional(),
  workoutRevision: z.string().length(64).nullable().optional(),
  activityId: z.string().optional().nullable(),
  completedAt: z.string().optional(),
  durationSeconds: z.number().int().positive().optional().nullable(),
  distanceMeters: z.number().nonnegative().optional().nullable(),
  targetCalories: z.number().int().positive().optional().nullable(),
  energyKilocalories: z.number().int().nonnegative().optional().nullable(),
  avgPace: z.number().positive().optional().nullable(),
  avgHeartRate: z.number().int().positive().optional().nullable(),
  avgPower: z.number().positive().optional().nullable(),
  perceivedEffort: z.number().int().min(1).max(10).optional().nullable(),
  completionQuality: z.string().max(64).optional(),
  notes: z.string().max(1000).optional().nullable(),
});

const rebuildSchema = z.object({
  reason: z.enum([
    "activityCompleted",
    "workoutSkipped",
    "readinessSubmitted",
    "goalUpdated",
    "scheduleUpdated",
    "weeklyRollover",
    "manualRebuild",
    "healthImportCompleted",
    "painFlagged",
    "workoutMissed",
    "dailyReview",
  ]).optional(),
}).optional();

router.get("/state", async (c) => {
  const user = await requirePlanningUser(c);
  if (user instanceof Response) return user;
  return c.json(await getState(user.id));
});

router.get("/today", async (c) => {
  const user = await requirePlanningUser(c);
  if (user instanceof Response) return user;
  return c.json(await getToday(user.id));
});

router.get("/activity-suggestion", async (c) => {
  const user = await requirePlanningUser(c);
  if (user instanceof Response) return user;
  return c.json(await getActivitySuggestion(user.id));
});

router.get("/recommendations", async (c) => {
  const user = await requirePlanningUser(c);
  if (user instanceof Response) return user;
  return c.json(await getRecommendations(user.id));
});

router.get("/goals", async (c) => {
  const user = await requirePlanningUser(c);
  if (user instanceof Response) return user;
  const state = await getState(user.id);
  return c.json({ goal: state.goal, plan: state.plan });
});

router.get("/intake-context", async (c) => {
  const user = await requirePlanningUser(c);
  if (user instanceof Response) return user;
  return c.json(await getPlanIntakeContext(
    user.id,
    c.req.query("objective"),
    c.req.header("X-Plainstride-Time-Zone")
  ));
});

router.post("/intake/interpret", zValidator("json", planIntakeInterpretSchema), async (c) => {
  const user = await requirePlanningUser(c);
  if (user instanceof Response) return user;
  const current = await getPlanIntakeContext(
    user.id,
    c.req.valid("json").draft.objective,
    c.req.header("X-Plainstride-Time-Zone")
  );
  if (current.contextVersion !== c.req.valid("json").contextVersion) {
    return c.json({ error: "Planning context changed. Refresh the intake summary before continuing.", context: current }, 409);
  }
  return c.json(await interpretPlanIntake(c.req.valid("json"), c.get("locale"), current));
});

const raceGoalUpdateSchema = z.object({
  targetDate: z.string().date().refine((value) => new Date(value) >= new Date(new Date().toISOString().slice(0, 10)), "Choose today or a future event date."),
  targetDistanceMeters: z.number().positive().max(500_000),
  eventIntent: z.enum(["finish", "perform", "targetTime"]),
  targetTimeSeconds: z.number().int().positive().nullable().optional(),
  daysPerWeekTarget: z.number().int().min(1).max(6),
  maxSessionMinutes: z.number().int().min(10).max(180),
  shortRunSessions: z.boolean(),
  optionalMobility: z.boolean(),
}).refine((input) => input.eventIntent !== "targetTime" || Boolean(input.targetTimeSeconds), "A target time is required.")
;

router.patch("/goals/:id", zValidator("json", raceGoalUpdateSchema), async (c) => {
  const user = await requirePlanningUser(c);
  if (user instanceof Response) return user;
  try {
    return c.json(await updateRaceGoal(user.id, c.req.param("id"), c.req.valid("json")));
  } catch (error) {
    if (error instanceof LongRunDaysError) {
      console.info("[planning] long_run_days_validation", { operation: "goal_write", status: 422, category: error.category });
      return c.json({ error: error.message, code: error.code }, 422);
    }
    if (error instanceof RunningScheduleError || error instanceof ProgrammeTimelineError || error instanceof ProgrammeConstraintError) {
      console.info("[planning] running_schedule_validation", { operation: "goal_write", category: error instanceof RunningScheduleError ? error.category : error instanceof ProgrammeTimelineError ? "programme_timeline" : "programme_quality" });
      return c.json({ error: error.message, code: error.code }, 422);
    }
    if (error instanceof GoalFeasibilityError) return c.json({ error: error.message, code: error.code }, 422);
    console.error("[planning] race_goal_update_failed", { errorType: error instanceof Error ? error.name : "unknown" });
    return c.json({ error: "The race goal could not be updated. Refresh the plan and try again." }, 409);
  }
});

router.post("/goals", zValidator("json", goalSchema), async (c) => {
  const user = await requirePlanningUser(c);
  if (user instanceof Response) return user;
  try {
    return c.json(await createGoal(user.id, c.req.valid("json")), 201);
  } catch (error) {
    if (error instanceof LongRunDaysError) {
      console.info("[planning] long_run_days_validation", { operation: "goal_write", status: 422, category: error.category });
      return c.json({ error: error.message, code: error.code }, 422);
    }
    if (error instanceof RunningScheduleError || error instanceof ProgrammeTimelineError || error instanceof ProgrammeConstraintError) {
      console.info("[planning] running_schedule_validation", { operation: "goal_write", category: error instanceof RunningScheduleError ? error.category : error instanceof ProgrammeTimelineError ? "programme_timeline" : "programme_quality" });
      return c.json({ error: error.message, code: error.code }, 422);
    }
    if (error instanceof GoalFeasibilityError) return c.json({ error: error.message, code: error.code }, 422);
    if (error instanceof RunningBenchmarkError) {
      console.info("[planning] running_benchmark_validation", { operation: "create", category: error.category });
      return c.json({ error: error.message, code: error.code }, 422);
    }
    if (error instanceof PlanningContextChangedError) {
      console.info("[planning] goal_create_rejected", { operation: "create", status: 409, code: error.code });
      return c.json({ error: error.message, code: error.code }, 409);
    }
    console.error("[planning] goal_create_failed", { operation: "create", status: 400, errorType: error instanceof Error ? error.name : "unknown" });
    return c.json({ error: error instanceof Error ? error.message : "Unable to create plan." }, 400);
  }
});

router.patch("/goals/:id/running-benchmark", zValidator("json", z.object({ runningBenchmark: z.unknown() })), async (c) => {
  const user = await requirePlanningUser(c);
  if (user instanceof Response) return user;
  try {
    return c.json(await updateRunningBenchmark(user.id, c.req.param("id"), c.req.valid("json").runningBenchmark));
  } catch (error) {
    if (error instanceof RunningBenchmarkError) {
      console.info("[planning] running_benchmark_validation", { operation: "update", category: error.category });
      return c.json({ error: error.message, code: error.code }, 422);
    }
    if (error instanceof LongRunDaysError) {
      console.info("[planning] long_run_days_validation", { operation: "goal_write", status: 422, category: error.category });
      return c.json({ error: error.message, code: error.code }, 422);
    }
    if (error instanceof RunningScheduleError || error instanceof ProgrammeTimelineError || error instanceof ProgrammeConstraintError) {
      console.info("[planning] running_schedule_validation", { operation: "benchmark_update", category: error instanceof RunningScheduleError ? error.category : error instanceof ProgrammeTimelineError ? "programme_timeline" : "programme_quality" });
      return c.json({ error: error.message, code: error.code }, 422);
    }
    if (error instanceof RunningBenchmarkConflictError) {
      console.info("[planning] running_benchmark_validation", { operation: "update", category: "goal_changed" });
      return c.json({ error: error.message, code: error.code }, 409);
    }
    console.error("[planning] running_benchmark_update_failed", { errorType: error instanceof Error ? error.name : "unknown" });
    return c.json({ error: "The benchmark could not be updated. Refresh the plan and try again." }, 409);
  }
});

router.post("/readiness", zValidator("json", readinessSchema), async (c) => {
  const user = await requirePlanningUser(c);
  if (user instanceof Response) return user;
  return c.json(await submitReadiness(user.id, c.req.valid("json")));
});

router.post("/workouts/:id/skip", async (c) => {
  const user = await requirePlanningUser(c);
  if (user instanceof Response) return user;
  try {
    return c.json(await skipWorkout(user.id, c.req.param("id")));
  } catch (error) {
    return c.json({ error: error instanceof Error ? error.message : "Unable to skip workout." }, 404);
  }
});

router.post("/workouts/:id/complete", zValidator("json", completionSchema), async (c) => {
  const user = await requirePlanningUser(c);
  if (user instanceof Response) return user;
  try {
    return c.json(await completeWorkout(user.id, c.req.param("id"), c.req.valid("json")));
  } catch (error) {
    if (error instanceof PerformedWorkoutConflictError) {
      console.info("[planning] performed_workout_validation", { operation: "complete", category: error.category });
      return c.json({ error: error.message, code: error.code }, 409);
    }
    return c.json({ error: error instanceof Error ? error.message : "Unable to complete workout." }, 404);
  }
});

router.post("/plan/rebuild", zValidator("json", rebuildSchema), async (c) => {
  const user = await requirePlanningUser(c);
  if (user instanceof Response) return user;
  return c.json(await rebuildPlan(user.id, c.req.valid("json") ?? {}));
});

router.delete("/plan", async (c) => {
  const user = await requirePlanningUser(c);
  if (user instanceof Response) return user;
  return c.json(await clearPlan(user.id));
});

router.get("/adjustments", async (c) => {
  const user = await requirePlanningUser(c);
  if (user instanceof Response) return user;
  return c.json({ adjustments: await getAdjustments(user.id) });
});

async function requirePlanningUser(c: Context<AppEnv>) {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

  const user = await getAuthenticatedAppUser(c);
  if (!user) {
    return c.json({ error: "Authentication required or user not registered." }, 401);
  }
  return user;
}

export default router;
