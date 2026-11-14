import { Hono } from "hono";
import { stream } from "hono/streaming";
import { bodyLimit } from "hono/body-limit";
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
import { LiveCoachPreparationService } from "../services/liveCoach/liveCoachPreparationService.js";
import { LiveCoachSessionService } from "../services/liveCoach/liveCoachSessionService.js";
import { LiveCoachStreamingService } from "../services/liveCoach/liveCoachStreamingService.js";
import { LiveCoachPhraseService } from "../services/liveCoach/liveCoachPhraseService.js";
import { LIVE_COACH_STREAM_CONTENT_TYPE, liveCoachStreamFrame } from "../services/liveCoach/liveCoachStreamProtocol.js";
import { LIVE_COACH_MOMENTS } from "../services/liveCoach/liveCoachTypes.js";

import { createSessionSchema } from "../services/liveCoach/liveCoachRequestContract.js";

import { stretchCueAudio, stretchCueKeys } from "../services/liveCoach/stretchCueAudio.js";

const router = new Hono<AppEnv>();
const identifier = z.string().uuid();

const liveStateSchema = z.object({
  elapsedSeconds: z.number().int().min(0).max(24 * 60 * 60),
  distanceMeters: z.number().finite().min(0).max(1_000_000),
  remainingDistanceMeters: z.number().finite().min(0).max(1_000_000).optional(),
  currentPaceSecondsPerKilometer: z.number().finite().min(60).max(3_600).optional(),
  rollingPaceSecondsPerKilometer: z.number().finite().min(60).max(3_600).optional(),
  targetPaceSecondsPerKilometer: z.number().finite().min(60).max(3_600).optional(),
  gradePercent: z.number().finite().min(-40).max(40).optional(),
  workoutSegmentIndex: z.number().int().min(0).max(200).optional(),
  workoutSegmentPhase: z.enum(["warmup", "easy", "work", "recovery", "walk", "cooldown", "open"]).optional(),
  routeGuidanceActive: z.boolean(),
}).strict();

const cueSchema = z.object({
  contractVersion: z.literal(1),
  cueRequestId: identifier,
  moment: z.enum(LIVE_COACH_MOMENTS),
  detectedAtElapsedSeconds: z.number().int().min(0).max(24 * 60 * 60),
  validForMilliseconds: z.number().int().min(1_000).max(10_000),
  selectedPhraseId: z.string().trim().min(1).max(120).optional(),
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
  if (Number.isFinite(contentLength) && contentLength > 64 * 1024) {
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

// Only catalog keys reach TTS; no user-authored text or workout context is accepted.
router.post("/stretch/audio", zValidator("json", z.object({
  cue: z.enum(stretchCueKeys),
  locale: z.enum(SUPPORTED_AI_LOCALES),
  voiceProfileId: z.enum(VOICE_PROFILE_IDS),
}).strict()), async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication required.", code: "authentication_required" }, 401);
  if (!liveCoachCueRepository.allowSessionRequest(`stretch:${user.id}`)) {
    return c.json({ error: "Stretch audio request limit reached.", code: "rate_limited" }, 429);
  }
  const input = c.req.valid("json");
  const audio = await stretchCueAudio(input.cue, input.locale, input.voiceProfileId);
  c.header("Content-Type", "audio/wav");
  c.header("Cache-Control", "private, max-age=86400");
  return c.body(Uint8Array.from(audio).buffer);
});

const coachingBodyLimit = bodyLimit({ maxSize: 128 * 1024, onError: (c) => {
  console.warn("live_coach_request_invalid", { operation: "session_contract", reason: "body_limit" });
  return c.json({ error: "Coaching request is too large.", code: "invalid_coaching_request" }, 413);
} });
const validateSessionRequest = zValidator("json", createSessionSchema, (result, c) => {
  if (!result.success) {
    const fields = result.error.issues.slice(0, 12).map((issue) => ({
      path: issue.path.map((part) => typeof part === "number" ? "item" : String(part)).join("."),
      code: issue.code,
    }));
    console.warn("live_coach_request_invalid", { operation: "session_contract", fields });
    return c.json({ error: "Invalid coaching request.", code: "invalid_coaching_request", fields }, 400);
  }
});

router.post("/preparations", coachingBodyLimit, validateSessionRequest, async (c) => {
  const unavailable = requireDatabase(c); if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication required.", code: "authentication_required" }, 401);
  const row = await new LiveCoachPreparationService(getPrismaClient()).prepare(user.id, c.req.valid("json"));
  return c.json(LiveCoachPreparationService.response(row), 202);
});

router.post("/preparations/:id/generate", async (c) => {
  const unavailable = requireDatabase(c); if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication required.", code: "authentication_required" }, 401);
  const row = await new LiveCoachPreparationService(getPrismaClient()).generate(user.id, c.req.param("id"));
  return c.json(LiveCoachPreparationService.response(row));
});

router.get("/sessions/:sessionId", async (c) => {
  const unavailable = requireDatabase(c); if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication required.", code: "authentication_required" }, 401);
  c.header("Cache-Control", "private, no-store");
  return c.json(await new LiveCoachSessionService(getPrismaClient()).refresh(user.id, c.req.param("sessionId")));
});

router.post("/sessions", coachingBodyLimit, validateSessionRequest, async (c) => {
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

router.post("/sessions/:sessionId/cues/stream", zValidator("json", cueSchema), async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;
  const appUser = await getAuthenticatedAppUser(c);
  if (!appUser) return c.json({ error: "Authentication required.", code: "authentication_required" }, 401);
  const prepared = await new LiveCoachStreamingService(getPrismaClient()).prepare(
    appUser.id,
    c.req.param("sessionId"),
    c.req.valid("json"),
    c.req.raw.signal
  );
  c.header("Content-Type", LIVE_COACH_STREAM_CONTENT_TYPE);
  c.header("Cache-Control", "no-store, no-transform");
  c.header("X-Accel-Buffering", "no");
  return stream(c, async (body) => {
    await body.write(liveCoachStreamFrame(1, prepared.metadata));
    let byteCount = 0;
    let firstAudioAt: number | undefined;
    try {
      for await (const chunk of prepared.chunks) {
        if (firstAudioAt == null) firstAudioAt = Date.now();
        byteCount += chunk.byteLength;
        await body.write(liveCoachStreamFrame(2, chunk));
      }
      await body.write(liveCoachStreamFrame(3, {
        byteCount,
        firstAudioAtUnixMilliseconds: firstAudioAt,
        serverCompletedAtUnixMilliseconds: Date.now(),
      }));
    } catch {
      await body.write(liveCoachStreamFrame(4, {
        code: "stream_interrupted",
        firstAudioAtUnixMilliseconds: firstAudioAt,
        serverFailedAtUnixMilliseconds: Date.now(),
      }));
    }
  });
});

router.post("/sessions/:sessionId/phrases/:phraseId/audio", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;
  const appUser = await getAuthenticatedAppUser(c);
  if (!appUser) return c.json({ error: "Authentication required.", code: "authentication_required" }, 401);
  const phraseId = z.string().trim().min(1).max(120).parse(c.req.param("phraseId"));
  const result = await new LiveCoachPhraseService(getPrismaClient()).synthesize(
    appUser.id,
    c.req.param("sessionId"),
    phraseId,
    c.req.raw.signal
  );
  c.header("Content-Type", "audio/wav");
  c.header("Cache-Control", "private, max-age=14400");
  c.header("X-Content-Type-Options", "nosniff");
  return c.body(Uint8Array.from(result.audio).buffer);
});

router.post("/sessions/:sessionId/cues/cached", zValidator("json", cueSchema), async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;
  const appUser = await getAuthenticatedAppUser(c);
  if (!appUser) return c.json({ error: "Authentication required.", code: "authentication_required" }, 401);
  await new LiveCoachPhraseService(getPrismaClient()).recordCachedUse(
    appUser.id,
    c.req.param("sessionId"),
    c.req.valid("json")
  );
  return c.json({ contractVersion: 1, recorded: true });
});

router.post("/sessions/:sessionId/end", zValidator("json", endSchema), async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;
  const appUser = await getAuthenticatedAppUser(c);
  if (!appUser) return c.json({ error: "Authentication required.", code: "authentication_required" }, 401);
  const sessionId = c.req.param("sessionId");
  await new LiveCoachSessionService(getPrismaClient()).end(appUser.id, sessionId, c.req.valid("json").outcome);
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
