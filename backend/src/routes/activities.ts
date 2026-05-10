import { Hono } from "hono";
import { rebuildCoachProfile } from "../services/coachProfile.js";
import { analyzeActivity } from "../services/ai.js";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";
import { requireDatabase } from "../services/database.js";
import { getPrismaClient } from "../services/prisma.js";
import { getAuthenticatedAppUser } from "../services/currentUser.js";
import { enqueueActivityCompletedEvent } from "../services/planning/planningService.js";
import type { AppEnv } from "../types/hono.js";

const router = new Hono<AppEnv>();

router.get("/user/:userId", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

  const prisma = getPrismaClient();
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
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

  const prisma = getPrismaClient();
  const activity = await prisma.activity.findUnique({
    where: { id: c.req.param("id") },
    include: { photos: true, posts: true },
  });
  if (!activity) return c.json({ error: "Not found" }, 404);
  return c.json(activity);
});

const createSchema = z.object({
  userId: z.string().optional(),
  clientActivityId: z.string().min(1).max(128).optional(),
  syncSource: z.string().min(1).max(64).optional(),
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
  route: z
    .object({
      points: z
        .array(
          z.object({
            timestamp: z.string(),
            latitude: z.number().finite(),
            longitude: z.number().finite(),
            altitude: z.number().finite().optional().nullable(),
            verticalAccuracy: z.number().finite().optional().nullable(),
          })
        )
        .min(2),
      visibility: z.string().optional().nullable(),
    })
    .optional()
    .nullable(),
  splits: z.any().optional(),
  reflection: z
    .object({
      title: z.string(),
      body: z.string(),
      highlight: z.string(),
      progressNote: z.string().optional().nullable(),
    })
    .optional()
    .nullable(),
});

type ActivityRoutePayload = NonNullable<z.infer<typeof createSchema>["route"]>;

function normalizeRoute(route: ActivityRoutePayload | null | undefined) {
  if (!route) return undefined;

  return {
    type: "Feature",
    geometry: {
      type: "LineString",
      coordinates: route.points.map((point) => {
        if (point.altitude == null) {
          return [point.longitude, point.latitude];
        }
        return [point.longitude, point.latitude, point.altitude];
      }),
    },
    properties: {
      visibility: route.visibility ?? "private",
      timestamps: route.points.map((point) => point.timestamp),
      verticalAccuracy: route.points.map((point) => point.verticalAccuracy ?? null),
    },
  };
}

router.post("/", zValidator("json", createSchema), async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

  const prisma = getPrismaClient();
  const body = c.req.valid("json");
  const authenticatedUser = await getAuthenticatedAppUser(c);
  const resolvedUserId = authenticatedUser?.id ?? body.userId;

  if (!resolvedUserId) {
    return c.json({ error: "Authentication or legacy userId is required." }, 401);
  }

  const activityData = {
    clientActivityId: body.clientActivityId,
    syncSource: body.syncSource,
    type: body.type,
    title: body.title,
    startedAt: new Date(body.startedAt),
    endedAt: body.endedAt ? new Date(body.endedAt) : undefined,
    durationSecs: body.durationSecs,
    distanceM: body.distanceM,
    elevationM: body.elevationM,
    avgPace: body.avgPace,
    avgHeartRate: body.avgHeartRate,
    calories: body.calories,
    route: normalizeRoute(body.route),
    splits: body.splits,
    reflection: body.reflection ?? undefined,
    userId: resolvedUserId,
  };

  let activity;
  let wasCreated = false;

  if (body.clientActivityId) {
    const existing = await prisma.activity.findUnique({
      where: {
        userId_clientActivityId: {
          userId: resolvedUserId,
          clientActivityId: body.clientActivityId,
        },
      },
    });

    if (existing) {
      activity = await prisma.activity.update({
        where: { id: existing.id },
        data: activityData,
      });
    } else {
      wasCreated = true;
      activity = await prisma.activity.create({
        data: activityData,
      });
    }
  } else {
    wasCreated = true;
    activity = await prisma.activity.create({
      data: activityData,
    });
  }

  // Fire-and-forget: analyze activity + rebuild coach profile
  if (wasCreated) {
    (async () => {
      const coachProfile = await prisma.coachProfile.findUnique({
        where: { userId: resolvedUserId },
      });
      const analysis = await analyzeActivity(activity, coachProfile ?? {});
      await Promise.all([
        prisma.activity.update({
          where: { id: activity.id },
          data: { coachAnalysis: analysis },
        }),
        rebuildCoachProfile(resolvedUserId),
        enqueueActivityCompletedEvent(resolvedUserId, activity.id),
      ]);
    })().catch(console.error);
  }

  return c.json(
    {
      id: activity.id,
      clientActivityId: activity.clientActivityId,
      status: wasCreated ? "created" : "updated",
      uploadedAt: activity.createdAt,
    },
    wasCreated ? 201 : 200
  );
});

export default router;
