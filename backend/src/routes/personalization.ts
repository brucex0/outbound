import { Hono, type Context } from "hono";
import { zValidator } from "@hono/zod-validator";
import { requireDatabase } from "../services/database.js";
import { getAuthenticatedAppUser } from "../services/currentUser.js";
import {
  adjustmentDecisionSchema,
  readinessCheckInRequestSchema,
  runnerProfileInputSchema,
  workoutFeedbackRequestSchema,
} from "../services/personalization/contracts.js";
import {
  decideAdjustment,
  getPersonalizationSnapshot,
  submitReadinessCheckIn,
  submitWorkoutFeedback,
  upsertRunnerProfile,
} from "../services/personalization/personalizationService.js";
import type { AppEnv } from "../types/hono.js";

const router = new Hono<AppEnv>();

router.get("/snapshot", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) return user;
  return c.json(await getPersonalizationSnapshot(user.id));
});

router.put("/profile", zValidator("json", runnerProfileInputSchema), async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) return user;
  return c.json(await upsertRunnerProfile(user.id, c.req.valid("json")));
});

router.post("/readiness", zValidator("json", readinessCheckInRequestSchema), async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) return user;
  return c.json(await submitReadinessCheckIn(user.id, c.req.valid("json")));
});

router.post("/workouts/:id/feedback", zValidator("json", workoutFeedbackRequestSchema), async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) return user;
  const input = c.req.valid("json");
  if (input.workoutId !== c.req.param("id")) return c.json({ error: "Workout ID mismatch." }, 400);
  return c.json(await submitWorkoutFeedback(user.id, input));
});

router.post("/adjustments/:id/decision", zValidator("json", adjustmentDecisionSchema), async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) return user;
  try {
    return c.json(await decideAdjustment(user.id, c.req.param("id"), c.req.valid("json").decision));
  } catch (error) {
    return c.json({ error: error instanceof Error ? error.message : "Unable to decide adjustment." }, 404);
  }
});

async function requireUser(c: Context<AppEnv>) {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication required." }, 401);
  return user;
}

export default router;
