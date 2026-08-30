import { Hono } from "hono";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";
import type { AppEnv } from "../types/hono.js";
import { AIProviderError } from "../services/aiProviders/errors.js";
import { SUPPORTED_AI_LOCALES, VOICE_PROFILE_IDS } from "../services/aiProviders/types.js";
import { requireDatabase } from "../services/database.js";
import { getAuthenticatedAppUser } from "../services/currentUser.js";
import { getPrismaClient } from "../services/prisma.js";
import { DatabaseLiveCoachEntitlementResolver } from "../services/liveCoach/liveCoachAccessPolicy.js";
import { publicLiveCoachCatalog } from "../services/liveCoach/liveCoachCatalog.js";
import { liveCoachCueRepository } from "../services/liveCoach/liveCoachCueRepository.js";
import { loadLiveCoachFeatureConfig, effectiveModeForUser, isLiveCoachLocaleEnabled } from "../services/liveCoach/liveCoachFeatureConfig.js";
import { LiveCoachOrchestrator } from "../services/liveCoach/liveCoachOrchestrator.js";
import { LiveCoachSessionService } from "../services/liveCoach/liveCoachSessionService.js";
import { LIVE_COACH_MOMENTS } from "../services/liveCoach/liveCoachTypes.js";

const router = new Hono<AppEnv>();
const identifier = z.string().uuid();

const createSessionSchema = z.object({
  contractVersion: z.literal(1),
  clientSessionId: identifier,
  workoutId: z.string().min(1).max(120).optional(),
  locale: z.enum(SUPPORTED_AI_LOCALES),
  coachPersonaId: z.enum(["plainstride_supportive_v1", "plainstride_focused_v1", "plainstride_calm_v1"]),
  voiceProfileId: z.enum(VOICE_PROFILE_IDS),
  coachingContract: z.enum(["quiet", "responsive", "coach_me"]),
  measurementUnitSystem: z.enum(["metric", "imperial"]),
  sessionIntent: z.object({
    activityType: z.enum(["running", "walking", "cycling", "hiking", "swimming"]),
    goalType: z.enum(["workout", "distance", "time", "freestyle"]),
  }).strict(),
  appDistributionHint: z.literal("global").optional(),
}).strict();

const liveStateSchema = z.object({
  elapsedSeconds: z.number().int().min(0).max(24 * 60 * 60),
  distanceMeters: z.number().finite().min(0).max(1_000_000),
  currentPaceSecondsPerKilometer: z.number().finite().min(60).max(3_600).optional(),
  rollingPaceSecondsPerKilometer: z.number().finite().min(60).max(3_600).optional(),
  targetPaceSecondsPerKilometer: z.number().finite().min(60).max(3_600).optional(),
  workoutSegmentIndex: z.number().int().min(0).max(200).optional(),
  workoutSegmentPhase: z.enum(["warmup", "work", "recovery", "cooldown"]).optional(),
  routeGuidanceActive: z.boolean(),
}).strict();

const cueSchema = z.object({
  contractVersion: z.literal(1),
  cueRequestId: identifier,
  moment: z.enum(LIVE_COACH_MOMENTS),
  detectedAtElapsedSeconds: z.number().int().min(0).max(24 * 60 * 60),
  validForMilliseconds: z.number().int().min(1_000).max(10_000),
  liveState: liveStateSchema,
}).strict();

const endSchema = z.object({
  contractVersion: z.literal(1),
  spokenCueCount: z.number().int().min(0).max(100),
  helpfulCueCount: z.number().int().min(0).max(100),
  outcome: z.enum(["completed", "discarded", "interrupted"]),
}).strict().refine((value) => value.helpfulCueCount <= value.spokenCueCount, {
  message: "helpfulCueCount cannot exceed spokenCueCount",
});

router.use("*", async (c, next) => {
  const contentLength = Number(c.req.header("Content-Length") ?? "0");
  if (Number.isFinite(contentLength) && contentLength > 16 * 1024) {
    return c.json({ error: "Live-coach request body is too large.", code: "invalid_request" }, 413);
  }
  await next();
});

router.get("/config", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;
  const appUser = await getAuthenticatedAppUser(c);
  if (!appUser) return c.json({ error: "Authentication required.", code: "authentication_required" }, 401);
  const config = loadLiveCoachFeatureConfig();
  const access = await new DatabaseLiveCoachEntitlementResolver(getPrismaClient())
    .resolve(appUser.id, new Date(), config);
  const localeEnabled = isLiveCoachLocaleEnabled(config, c.get("locale"));
  const mode = localeEnabled ? effectiveModeForUser(config, appUser.id) : "disabled";
  return c.json({
    contractVersion: 1,
    configVersion: config.configVersion,
    mode,
    catalogVersion: config.catalogVersion,
    access: {
      dynamicCoaching: mode === "dynamic" && access.allowed ? "allowed" : "unavailable",
      reason: localeEnabled ? access.reason : "feature_disabled",
      paywallAvailable: access.paywallAvailable,
    },
  });
});

router.get("/catalog", zValidator("query", z.object({ locale: z.enum(SUPPORTED_AI_LOCALES).optional() }).strict()), async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;
  const appUser = await getAuthenticatedAppUser(c);
  if (!appUser) return c.json({ error: "Authentication required.", code: "authentication_required" }, 401);
  const locale = c.req.valid("query").locale ?? c.get("locale");
  return c.json(publicLiveCoachCatalog(loadLiveCoachFeatureConfig(), locale));
});

router.post("/sessions", zValidator("json", createSessionSchema), async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;
  const appUser = await getAuthenticatedAppUser(c);
  if (!appUser) return c.json({ error: "Authentication required.", code: "authentication_required" }, 401);
  const response = await new LiveCoachSessionService(getPrismaClient()).create(appUser.id, c.req.valid("json"));
  return c.json(response, 201);
});

router.post("/sessions/:sessionId/cues", zValidator("json", cueSchema), async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;
  const appUser = await getAuthenticatedAppUser(c);
  if (!appUser) return c.json({ error: "Authentication required.", code: "authentication_required" }, 401);
  const response = await new LiveCoachOrchestrator(getPrismaClient()).requestCue(
    appUser.id,
    c.req.param("sessionId"),
    c.req.valid("json"),
    c.req.raw.signal
  );
  return c.json(response);
});

router.post("/sessions/:sessionId/end", zValidator("json", endSchema), async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;
  const appUser = await getAuthenticatedAppUser(c);
  if (!appUser) return c.json({ error: "Authentication required.", code: "authentication_required" }, 401);
  const sessionId = c.req.param("sessionId");
  await new LiveCoachSessionService(getPrismaClient()).end(appUser.id, sessionId);
  liveCoachCueRepository.abortSession(sessionId);
  return c.json({ contractVersion: 1, ended: true });
});

router.onError((error, c) => {
  if (error instanceof AIProviderError) {
    const status = error.code === "not_eligible" ? 409
      : error.code === "not_configured" ? 503
      : error.code === "rate_limited" ? 429
      : error.code === "budget_exhausted" ? 422
      : 502;
    return c.json({ error: error.message, code: error.code }, status);
  }
  console.error("[live-coach] request failed", { path: c.req.path, category: "internal_error" });
  return c.json({ error: "Live coaching is temporarily unavailable.", code: "unavailable" }, 503);
});

export default router;
