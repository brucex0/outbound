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
import { z } from "zod";

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

router.post(
  "/cycle-signal",
  zValidator("json", z.object({
    signal: z.enum(["noAdjustment", "offerFlexibleOption", "reduceLoad", "recommendRest"]),
    workoutId: z.string().min(1).optional(),
    day: z.string().date(),
    idempotencyKey: z.string().min(1).max(120),
  })),
  async (c) => {
    const user = await requireUser(c);
    if (user instanceof Response) return user;
    const { signal, workoutId, day } = c.req.valid("json");
    const options = {
      noAdjustment: { action: "keep", explanation: "Your planned workout still looks like a good fit." },
      offerFlexibleOption: { action: "offer", explanation: "A flexible version is available if it feels better today." },
      reduceLoad: { action: "reduce", explanation: "A gentler version can protect consistency without forcing the plan." },
      recommendRest: { action: "rest", explanation: "Rest or a very easy alternative may be the better training choice today." },
    } as const;
    return c.json({ workoutId: workoutId ?? null, day, signal, ...options[signal], rawHealthDataStored: false });
  }
);

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
