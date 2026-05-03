import { Hono } from "hono";
import { rebuildCoachProfile } from "../services/coachProfile.js";
import { generateWeeklyReview } from "../services/ai.js";
import { zValidator } from "@hono/zod-validator";
import { z } from "zod";
import { requireDatabase } from "../services/database.js";
import { getPrismaClient } from "../services/prisma.js";
import { getAuthenticatedAppUser } from "../services/currentUser.js";
import {
  buildTrainingPlanState,
  makeActivePlanData,
} from "../services/trainingPlans.js";
import type { AppEnv } from "../types/hono.js";

const router = new Hono<AppEnv>();

const planSelectionSchema = z.object({
  candidateID: z.string().min(1).optional(),
  templateID: z.string().min(1).optional(),
  durationWeeks: z.number().int().positive().optional(),
  sessionsPerWeek: z.number().int().positive().optional(),
  targetWeeklyMinutes: z.number().int().positive().optional(),
  longSessionMinutes: z.number().int().positive().optional(),
  readiness: z.string().optional(),
});

async function getPlanActivities(userId: string) {
  const prisma = getPrismaClient();
  const ninetyDaysAgo = new Date(Date.now() - 90 * 24 * 60 * 60 * 1000);
  return prisma.activity.findMany({
    where: { userId, startedAt: { gte: ninetyDaysAgo } },
    orderBy: { startedAt: "desc" },
    select: {
      startedAt: true,
      durationSecs: true,
      distanceM: true,
    },
  });
}

router.get("/profile", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

  const appUser = await getAuthenticatedAppUser(c);
  if (!appUser) {
    return c.json({ error: "Authentication required or user not registered." }, 401);
  }

  const prisma = getPrismaClient();
  const profile = await prisma.coachProfile.findUnique({ where: { userId: appUser.id } });
  if (!profile) return c.json({ error: "No coach profile yet" }, 404);
  return c.json(profile);
});

router.post("/rebuild", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

  const appUser = await getAuthenticatedAppUser(c);
  if (!appUser) {
    return c.json({ error: "Authentication required or user not registered." }, 401);
  }

  const payload = await rebuildCoachProfile(appUser.id);
  return c.json(payload);
});

router.get("/plans/state", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

  const appUser = await getAuthenticatedAppUser(c);
  if (!appUser) {
    return c.json({ error: "Authentication required or user not registered." }, 401);
  }

  const prisma = getPrismaClient();
  const [activePlan, activities] = await Promise.all([
    prisma.activeTrainingPlan.findUnique({ where: { userId: appUser.id } }),
    getPlanActivities(appUser.id),
  ]);

  return c.json(
    buildTrainingPlanState({
      activePlan,
      activities,
      readiness: c.req.query("readiness"),
    })
  );
});

router.post("/plans/recommendation", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

  const appUser = await getAuthenticatedAppUser(c);
  if (!appUser) {
    return c.json({ error: "Authentication required or user not registered." }, 401);
  }

  const activities = await getPlanActivities(appUser.id);
  return c.json({
    recommendations: buildTrainingPlanState({
      activePlan: null,
      activities,
      readiness: c.req.query("readiness"),
    }).recommendations,
  });
});

router.post("/plans", zValidator("json", planSelectionSchema), async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

  const appUser = await getAuthenticatedAppUser(c);
  if (!appUser) {
    return c.json({ error: "Authentication required or user not registered." }, 401);
  }

  const prisma = getPrismaClient();
  const body = c.req.valid("json");
  const activities = await getPlanActivities(appUser.id);

  let planData;
  try {
    planData = makeActivePlanData({
      selection: body,
      activities,
    });
  } catch (error) {
    return c.json({ error: error instanceof Error ? error.message : "Invalid training plan selection." }, 400);
  }

  const activePlan = await prisma.activeTrainingPlan.upsert({
    where: { userId: appUser.id },
    update: planData,
    create: {
      userId: appUser.id,
      ...planData,
    },
  });

  return c.json(
    buildTrainingPlanState({
      activePlan,
      activities,
      readiness: body.readiness,
      now: planData.startedAt,
    }),
    201
  );
});

router.get("/plans/active", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

  const appUser = await getAuthenticatedAppUser(c);
  if (!appUser) {
    return c.json({ error: "Authentication required or user not registered." }, 401);
  }

  const prisma = getPrismaClient();
  const [activePlan, activities] = await Promise.all([
    prisma.activeTrainingPlan.findUnique({ where: { userId: appUser.id } }),
    getPlanActivities(appUser.id),
  ]);
  if (!activePlan) return c.json({ error: "No active training plan." }, 404);

  return c.json(
    buildTrainingPlanState({
      activePlan,
      activities,
      readiness: c.req.query("readiness"),
    })
  );
});

router.get("/plans/active/week", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

  const appUser = await getAuthenticatedAppUser(c);
  if (!appUser) {
    return c.json({ error: "Authentication required or user not registered." }, 401);
  }

  const prisma = getPrismaClient();
  const [activePlan, activities] = await Promise.all([
    prisma.activeTrainingPlan.findUnique({ where: { userId: appUser.id } }),
    getPlanActivities(appUser.id),
  ]);
  if (!activePlan) return c.json({ error: "No active training plan." }, 404);

  const state = buildTrainingPlanState({
    activePlan,
    activities,
    readiness: c.req.query("readiness"),
  });
  return c.json({ week: state.currentWeek });
});

router.delete("/plans/active", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

  const appUser = await getAuthenticatedAppUser(c);
  if (!appUser) {
    return c.json({ error: "Authentication required or user not registered." }, 401);
  }

  const prisma = getPrismaClient();
  await prisma.activeTrainingPlan.deleteMany({ where: { userId: appUser.id } });
  const activities = await getPlanActivities(appUser.id);

  return c.json(
    buildTrainingPlanState({
      activePlan: null,
      activities,
      readiness: c.req.query("readiness"),
    })
  );
});

router.get("/today", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

  const appUser = await getAuthenticatedAppUser(c);
  if (!appUser) {
    return c.json({ error: "Authentication required or user not registered." }, 401);
  }

  const prisma = getPrismaClient();
  const [activePlan, activities] = await Promise.all([
    prisma.activeTrainingPlan.findUnique({ where: { userId: appUser.id } }),
    getPlanActivities(appUser.id),
  ]);
  if (!activePlan) return c.json({ error: "No active training plan." }, 404);

  const state = buildTrainingPlanState({
    activePlan,
    activities,
    readiness: c.req.query("readiness"),
  });
  return c.json({ today: state.todaySuggestion });
});

// GET /v1/coach/:userId/profile
// Returns the downloadable CoachProfilePayload for the device
router.get("/:userId/profile", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

  const prisma = getPrismaClient();
  const { userId } = c.req.param();
  const profile = await prisma.coachProfile.findUnique({ where: { userId } });
  if (!profile) return c.json({ error: "No coach profile yet" }, 404);
  return c.json(profile);
});

// POST /v1/coach/:userId/rebuild
// Trigger a full coach profile rebuild (called after activity sync)
router.post("/:userId/rebuild", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

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
    const unavailable = requireDatabase(c);
    if (unavailable) return unavailable;

    const prisma = getPrismaClient();
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
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

  const prisma = getPrismaClient();
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
