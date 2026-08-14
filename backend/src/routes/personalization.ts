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
    const options = localizedCycleOptions(c.get("locale"));
    return c.json({ workoutId: workoutId ?? null, day, signal, ...options[signal], locale: c.get("locale"), rawHealthDataStored: false });
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

function localizedCycleOptions(locale: "en" | "es" | "zh-Hans") {
  if (locale === "es") return {
    noAdjustment: { action: "keep", explanation: "El entrenamiento previsto todavía parece adecuado." },
    offerFlexibleOption: { action: "offer", explanation: "Hay una versión flexible disponible si hoy te resulta mejor." },
    reduceLoad: { action: "reduce", explanation: "Una versión más suave puede proteger la constancia sin forzar el plan." },
    recommendRest: { action: "rest", explanation: "Descansar o elegir una alternativa muy suave puede ser la mejor opción de entrenamiento hoy." },
  } as const;
  if (locale === "zh-Hans") return {
    noAdjustment: { action: "keep", explanation: "原计划训练看起来仍然适合你。" },
    offerFlexibleOption: { action: "offer", explanation: "如果今天感觉更合适，可以选择灵活版本。" },
    reduceLoad: { action: "reduce", explanation: "更轻松的版本可以在不勉强执行计划的情况下保持连续性。" },
    recommendRest: { action: "rest", explanation: "今天休息或选择非常轻松的替代训练可能更合适。" },
  } as const;
  return {
    noAdjustment: { action: "keep", explanation: "Your planned workout still looks like a good fit." },
    offerFlexibleOption: { action: "offer", explanation: "A flexible version is available if it feels better today." },
    reduceLoad: { action: "reduce", explanation: "A gentler version can protect consistency without forcing the plan." },
    recommendRest: { action: "rest", explanation: "Rest or a very easy alternative may be the better training choice today." },
  } as const;
}
