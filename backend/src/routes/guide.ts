import { Hono } from "hono";
import { getGuideProfile, rebuildGuideProfile } from "../services/guideProfile.js";
import { generateWeeklyReview } from "../services/ai.js";
import { zValidator } from "@hono/zod-validator";
import { z } from "zod";
import { requireDatabase } from "../services/database.js";
import { getPrismaClient } from "../services/prisma.js";
import { getAuthenticatedAppUser } from "../services/currentUser.js";
import type { AppEnv } from "../types/hono.js";
import { findCoachPersona, findVoiceProfile } from "../services/liveCoach/liveCoachCatalog.js";

const router = new Hono<AppEnv>();

router.get("/profile", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

  const appUser = await getAuthenticatedAppUser(c);
  if (!appUser) {
    return c.json({ error: "Authentication required or user not registered." }, 401);
  }

  const profile = await getGuideProfile(appUser.id);
  if (!profile) return c.json({ error: "No guide profile yet" }, 404);
  return c.json(profile);
});

router.post("/rebuild", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

  const appUser = await getAuthenticatedAppUser(c);
  if (!appUser) {
    return c.json({ error: "Authentication required or user not registered." }, 401);
  }

  const payload = await rebuildGuideProfile(appUser.id);
  return c.json(payload);
});

// POST /v1/guide/customize
// Update the authenticated user's product-owned persona and voice profile.
router.post(
  "/customize",
  zValidator(
    "json",
    z.object({
      guideName: z.string().min(1).max(30).optional(),
      coachPersonaId: z.enum(["plainstride_supportive_v1", "plainstride_focused_v1", "plainstride_calm_v1"]).optional(),
      voiceProfileId: z.enum(["plainstride_warm_1", "plainstride_clear_1"]).optional(),
    }).strict()
  ),
  async (c) => {
    const unavailable = requireDatabase(c);
    if (unavailable) return unavailable;

    const prisma = getPrismaClient();
    const appUser = await getAuthenticatedAppUser(c);
    if (!appUser) return c.json({ error: "Authentication required or user not registered." }, 401);
    const body = c.req.valid("json");
    const current = await prisma.guideProfile.findUnique({ where: { userId: appUser.id } });
    if (!current) return c.json({ error: "No guide profile" }, 404);
    const persona = findCoachPersona(body.coachPersonaId ?? current.coachPersonaId);
    const voice = findVoiceProfile(body.voiceProfileId ?? current.voiceProfileId);
    if (!persona || !voice || !persona.allowedVoiceProfileIds.includes(voice.id)) {
      return c.json({ error: "The selected coach and voice combination is unavailable." }, 422);
    }
    await prisma.guideProfile.update({
      where: { userId: appUser.id },
      data: body,
    });
    return c.json(await getGuideProfile(appUser.id));
  }
);

// POST /v1/guide/weekly-review
// Generate a full weekly review via Claude
router.post("/weekly-review", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

  const prisma = getPrismaClient();
  const appUser = await getAuthenticatedAppUser(c);
  if (!appUser) return c.json({ error: "Authentication required or user not registered." }, 401);
  const userId = appUser.id;
  const oneWeekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
  const [profile, activities] = await Promise.all([
    prisma.guideProfile.findUnique({ where: { userId } }),
    prisma.activity.findMany({
      where: { userId, startedAt: { gte: oneWeekAgo } },
      orderBy: { startedAt: "desc" },
    }),
  ]);
  if (!profile) return c.json({ error: "No guide profile" }, 404);
  const review = await generateWeeklyReview(userId, activities, profile);
  return c.json({ review });
});

export default router;
