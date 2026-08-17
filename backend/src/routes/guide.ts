import { Hono } from "hono";
import { rebuildGuideProfile } from "../services/guideProfile.js";
import { generateWeeklyReview } from "../services/ai.js";
import { zValidator } from "@hono/zod-validator";
import { z } from "zod";
import { requireDatabase } from "../services/database.js";
import { getPrismaClient } from "../services/prisma.js";
import { getAuthenticatedAppUser } from "../services/currentUser.js";
import type { AppEnv } from "../types/hono.js";

const router = new Hono<AppEnv>();

router.get("/profile", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

  const appUser = await getAuthenticatedAppUser(c);
  if (!appUser) {
    return c.json({ error: "Authentication required or user not registered." }, 401);
  }

  const prisma = getPrismaClient();
  const profile = await prisma.guideProfile.findUnique({ where: { userId: appUser.id } });
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

// GET /v1/guide/:userId/profile
// Returns the downloadable GuideProfilePayload for the device
router.get("/:userId/profile", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

  const prisma = getPrismaClient();
  const { userId } = c.req.param();
  const profile = await prisma.guideProfile.findUnique({ where: { userId } });
  if (!profile) return c.json({ error: "No guide profile yet" }, 404);
  return c.json(profile);
});

// POST /v1/guide/:userId/rebuild
// Trigger a full guide profile rebuild (called after activity sync)
router.post("/:userId/rebuild", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

  const { userId } = c.req.param();
  const payload = await rebuildGuideProfile(userId);
  return c.json(payload);
});

// POST /v1/guide/:userId/customize
// Update guide name, personality, voice
router.post(
  "/:userId/customize",
  zValidator(
    "json",
    z.object({
      guideName: z.string().min(1).max(30).optional(),
      personality: z.enum(["encouraging", "data-driven", "direct", "zen"]).optional(),
      voiceId: z.string().optional(),
    })
  ),
  async (c) => {
    const unavailable = requireDatabase(c);
    if (unavailable) return unavailable;

    const prisma = getPrismaClient();
    const { userId } = c.req.param();
    const body = c.req.valid("json");
    const profile = await prisma.guideProfile.update({
      where: { userId },
      data: body,
    });
    return c.json(profile);
  }
);

// POST /v1/guide/:userId/weekly-review
// Generate a full weekly review via Claude
router.post("/:userId/weekly-review", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

  const prisma = getPrismaClient();
  const { userId } = c.req.param();
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
