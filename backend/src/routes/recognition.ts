import { Hono } from "hono";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";
import { requireDatabase } from "../services/database.js";
import { getAuthenticatedAppUser } from "../services/currentUser.js";
import {
  backfillActivityRecognitions,
  backfillSocialRecognitions,
  claimRecognitions,
  recognitionAwards,
  recognitionBadgeIds,
} from "../services/recognition.js";
import type { AppEnv } from "../types/hono.js";

const router = new Hono<AppEnv>();
const badgeIdSchema = z.enum(recognitionBadgeIds);
const claimSchema = z.object({
  claims: z.array(z.object({
    badgeId: badgeIdSchema,
    earnedAt: z.string().datetime(),
    sourceActivityId: z.string().uuid().nullable().optional(),
    sourceReferenceId: z.string().min(1).max(200).nullable().optional(),
  })).max(recognitionBadgeIds.length),
});

router.get("/", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication is required." }, 401);
  const timeZoneIdentifier = c.req.query("timeZoneIdentifier");
  const firstWeekday = Number(c.req.query("firstWeekday") ?? 2);
  await Promise.all([
    backfillActivityRecognitions(user.id, timeZoneIdentifier, firstWeekday),
    backfillSocialRecognitions(user.id, timeZoneIdentifier, firstWeekday),
  ]);
  return c.json({ awards: await recognitionAwards(user.id) });
});

router.post("/claims", zValidator("json", claimSchema), async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication is required." }, 401);
  await claimRecognitions(user.id, c.req.valid("json").claims.map((claim) => ({
    badgeId: claim.badgeId,
    earnedAt: new Date(claim.earnedAt),
    sourceActivityClientId: claim.sourceActivityId,
    sourceReferenceId: claim.sourceReferenceId,
  })));
  return c.json({ awards: await recognitionAwards(user.id) });
});

export default router;
