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
import { Prisma } from "@prisma/client";
import { deleteActivityPhotos } from "../services/activityPhotoStorage.js";

const router = new Hono<AppEnv>();

router.get("/", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

  const prisma = getPrismaClient();
  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication is required." }, 401);
  const limit = Math.min(200, Math.max(1, Number(c.req.query("limit") ?? 100)));
  const offset = Number(c.req.query("offset") ?? 0);
  const activities = await prisma.activity.findMany({
    where: { userId: user.id },
    include: { photos: { orderBy: { takenAt: "asc" } } },
    orderBy: { updatedAt: "desc" },
    take: limit,
    skip: offset,
  });
  return c.json({
    activities: activities.map((activity) => ({
      id: activity.id,
      clientActivityId: activity.clientActivityId,
      clientData: activity.clientData ?? legacyClientData(activity),
      clientUpdatedAt: activity.clientUpdatedAt,
      deletedAt: activity.deletedAt,
      createdAt: activity.createdAt,
      updatedAt: activity.updatedAt,
      photos: activity.photos.map((photo) => ({
        id: photo.id,
        clientPhotoId: photo.clientPhotoId,
        takenAt: photo.takenAt,
        paceAtShot: photo.paceAtShot,
        hrAtShot: photo.hrAtShot,
        distAtShot: photo.distAtShot,
        latitude: photo.lat,
        longitude: photo.lng,
        captureContext: photo.captureContext,
        byteSize: photo.byteSize,
        sha256: photo.sha256,
        createdAt: photo.createdAt,
        updatedAt: photo.updatedAt,
      })),
    })),
    hasMore: activities.length === limit,
  });
});

router.get("/:id", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

  const prisma = getPrismaClient();
  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication is required." }, 401);
  const activity = await prisma.activity.findFirst({
    where: { id: c.req.param("id"), userId: user.id, deletedAt: null },
    include: { photos: true, posts: true },
  });
  if (!activity) return c.json({ error: "Not found" }, 404);
  return c.json(activity);
});

function legacyClientData(activity: {
  clientActivityId: string | null;
  title: string | null;
  startedAt: Date;
  endedAt: Date | null;
  durationSecs: number | null;
  distanceM: number | null;
  elevationM: number | null;
  avgPace: number | null;
  avgHeartRate: number | null;
  route: unknown;
  reflection: unknown;
  createdAt: Date;
}) {
  if (!activity.clientActivityId) return null;
  const durationSecs = activity.durationSecs ?? 1;
  const route = activity.route as {
    geometry?: { coordinates?: number[][] };
    properties?: { timestamps?: string[]; verticalAccuracy?: Array<number | null> };
  } | null;
  const coordinates = route?.geometry?.coordinates ?? [];
  const timestamps = route?.properties?.timestamps ?? [];
  const verticalAccuracy = route?.properties?.verticalAccuracy ?? [];
  return {
    id: activity.clientActivityId,
    title: activity.title ?? "Restored Run",
    coachNudge: "",
    reflection: activity.reflection,
    createdAt: activity.createdAt,
    startedAt: activity.startedAt,
    endedAt: activity.endedAt ?? new Date(activity.startedAt.getTime() + durationSecs * 1000),
    durationSecs,
    distanceM: activity.distanceM ?? 0,
    avgPace: activity.avgPace,
    elevationGainM: activity.elevationM,
    healthMetrics: activity.avgHeartRate == null ? null : {
      averageHeartRateBPM: activity.avgHeartRate,
      maxHeartRateBPM: null,
      heartRateSampleCount: 0,
    },
    source: { kind: "outbound", displayName: "Plainstride" },
    route: coordinates.length < 2 ? null : {
      points: coordinates.map((coordinate, index) => ({
        timestamp: timestamps[index] ?? activity.startedAt,
        latitude: coordinate[1],
        longitude: coordinate[0],
        altitude: coordinate[2] ?? null,
        verticalAccuracy: verticalAccuracy[index] ?? null,
      })),
    },
    photos: [],
  };
}

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
  clientData: z.record(z.unknown()).optional(),
  clientUpdatedAt: z.string().datetime().optional(),
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
    clientData: body.clientData as Prisma.InputJsonValue | undefined,
    clientUpdatedAt: body.clientUpdatedAt ? new Date(body.clientUpdatedAt) : undefined,
    deletedAt: null,
    userId: resolvedUserId,
  };

  let activity;
  let wasCreated = false;
  const createActivityWithSocialPost = () =>
    prisma.$transaction(async (transaction) => {
      const createdActivity = await transaction.activity.create({
        data: { ...activityData, socialSharingInitializedAt: new Date() },
      });
      await transaction.post.create({
        data: {
          userId: resolvedUserId,
          activityId: createdActivity.id,
          visibility: "connections",
        },
      });
      return createdActivity;
    });

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
      const incomingUpdatedAt = body.clientUpdatedAt ? new Date(body.clientUpdatedAt) : null;
      if (existing.clientUpdatedAt && incomingUpdatedAt && existing.clientUpdatedAt > incomingUpdatedAt) {
        activity = existing;
      } else {
        activity = await prisma.activity.update({
          where: { id: existing.id },
          data: activityData,
        });
      }
    } else {
      wasCreated = true;
      activity = await createActivityWithSocialPost();
    }
  } else {
    wasCreated = true;
    activity = await createActivityWithSocialPost();
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
      uploadedAt: activity.updatedAt,
      serverUpdatedAt: activity.updatedAt,
    },
    wasCreated ? 201 : 200
  );
});

router.delete("/:id", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication is required." }, 401);

  const prisma = getPrismaClient();
  const activity = await prisma.activity.findFirst({
    where: {
      userId: user.id,
      OR: [{ id: c.req.param("id") }, { clientActivityId: c.req.param("id") }],
    },
  });
  if (!activity) return c.json({ status: "deleted" });

  const photos = await prisma.photo.findMany({ where: { activityId: activity.id }, select: { storageKey: true } });
  await deleteActivityPhotos(photos.map((photo) => photo.storageKey));
  await prisma.photo.deleteMany({ where: { activityId: activity.id } });

  const deleted = await prisma.activity.update({
    where: { id: activity.id },
    data: { deletedAt: new Date(), clientData: undefined },
  });
  return c.json({ status: "deleted", id: deleted.id, deletedAt: deleted.deletedAt });
});

export default router;
