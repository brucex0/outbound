import { Hono } from "hono";
import { PrismaClient } from "@prisma/client";
import { rebuildCoachProfile } from "../services/coachProfile.js";
import { generateWeeklyReview } from "../services/ai.js";
import { zValidator } from "@hono/zod-validator";
import { z } from "zod";

const router = new Hono();
const prisma = new PrismaClient();

// GET /v1/coach/:userId/profile
// Returns the downloadable CoachProfilePayload for the device
router.get("/:userId/profile", async (c) => {
  const { userId } = c.req.param();
  const profile = await prisma.coachProfile.findUnique({ where: { userId } });
  if (!profile) return c.json({ error: "No coach profile yet" }, 404);
  return c.json(profile);
});

// POST /v1/coach/:userId/rebuild
// Trigger a full coach profile rebuild (called after activity sync)
router.post("/:userId/rebuild", async (c) => {
  const { userId } = c.req.param();
  const payload = await rebuildCoachProfile(userId);
  return c.json(payload);
});

// POST /v1/coach/:userId/customize
// Update coach name, personality, voice
router.post(
  "/:userId/customize",
  zValidator(
    "json",
    z.object({
      coachName: z.string().min(1).max(30).optional(),
      personality: z.enum(["encouraging", "data-driven", "direct", "zen"]).optional(),
      voiceId: z.string().optional(),
    })
  ),
  async (c) => {
    const { userId } = c.req.param();
    const body = c.req.valid("json");
    const profile = await prisma.coachProfile.update({
      where: { userId },
      data: body,
    });
    return c.json(profile);
  }
);

// POST /v1/coach/:userId/weekly-review
// Generate a full weekly review via Claude
router.post("/:userId/weekly-review", async (c) => {
  const { userId } = c.req.param();
  const oneWeekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
  const [profile, activities] = await Promise.all([
    prisma.coachProfile.findUnique({ where: { userId } }),
    prisma.activity.findMany({
      where: { userId, startedAt: { gte: oneWeekAgo } },
      orderBy: { startedAt: "desc" },
    }),
  ]);
  if (!profile) return c.json({ error: "No coach profile" }, 404);
  const review = await generateWeeklyReview(userId, activities, profile);
  return c.json({ review });
});

export default router;
