import { Hono } from "hono";
import { PrismaClient } from "@prisma/client";
import { rebuildCoachProfile } from "../services/coachProfile.js";
import { analyzeActivity } from "../services/ai.js";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";

const router = new Hono();
const prisma = new PrismaClient();

router.get("/user/:userId", async (c) => {
  const { userId } = c.req.param();
  const limit = Number(c.req.query("limit") ?? 20);
  const offset = Number(c.req.query("offset") ?? 0);
  const activities = await prisma.activity.findMany({
    where: { userId },
    orderBy: { startedAt: "desc" },
    take: limit,
    skip: offset,
    include: { photos: true },
  });
  return c.json(activities);
});

router.get("/:id", async (c) => {
  const activity = await prisma.activity.findUnique({
    where: { id: c.req.param("id") },
    include: { photos: true, posts: true },
  });
  if (!activity) return c.json({ error: "Not found" }, 404);
  return c.json(activity);
});

const createSchema = z.object({
  userId: z.string(),
  type: z.string().default("running"),
  title: z.string().optional(),
  startedAt: z.string(),
  endedAt: z.string().optional(),
  durationSecs: z.number().optional(),
  distanceM: z.number().optional(),
  elevationM: z.number().optional(),
  avgPace: z.number().optional(),
  avgHeartRate: z.number().optional(),
  calories: z.number().optional(),
  route: z.any().optional(),
  splits: z.any().optional(),
});

router.post("/", zValidator("json", createSchema), async (c) => {
  const body = c.req.valid("json");
  const activity = await prisma.activity.create({
    data: {
      ...body,
      startedAt: new Date(body.startedAt),
      endedAt: body.endedAt ? new Date(body.endedAt) : undefined,
    },
  });

  // Fire-and-forget: analyze activity + rebuild coach profile
  (async () => {
    const coachProfile = await prisma.coachProfile.findUnique({
      where: { userId: body.userId },
    });
    const analysis = await analyzeActivity(activity, coachProfile ?? {});
    await Promise.all([
      prisma.activity.update({
        where: { id: activity.id },
        data: { coachAnalysis: analysis },
      }),
      rebuildCoachProfile(body.userId),
    ]);
  })().catch(console.error);

  return c.json(activity, 201);
});

export default router;
