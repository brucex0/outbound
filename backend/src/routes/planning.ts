import { Hono, type Context } from "hono";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";
import { requireDatabase } from "../services/database.js";
import { getAuthenticatedAppUser } from "../services/currentUser.js";
import {
  clearPlan,
  completeWorkout,
  createGoal,
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

const router = new Hono<AppEnv>();

const goalSchema = z.object({
  type: z.string().min(1).max(64),
  primaryModality: z.enum(["run", "walk", "bike", "swim", "strength", "hiit", "skate", "mobility"]).optional(),
  targetDate: z.string().optional().nullable(),
  targetDistanceMeters: z.number().positive().optional().nullable(),
  targetEventName: z.string().max(120).optional().nullable(),
  priority: z.string().min(1).max(64).optional(),
  preferredDays: z.array(z.string().min(1).max(16)).optional(),
  daysPerWeekTarget: z.number().int().min(1).max(6).optional(),
  maxSessionMinutes: z.number().int().min(10).max(180).optional(),
  riskTolerance: z.enum(["conservative", "balanced", "stretch"]).optional(),
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
  activityId: z.string().optional().nullable(),
  completedAt: z.string().optional(),
  durationSeconds: z.number().int().positive().optional().nullable(),
  distanceMeters: z.number().nonnegative().optional().nullable(),
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

router.post("/goals", zValidator("json", goalSchema), async (c) => {
  const user = await requirePlanningUser(c);
  if (user instanceof Response) return user;
  return c.json(await createGoal(user.id, c.req.valid("json")), 201);
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
