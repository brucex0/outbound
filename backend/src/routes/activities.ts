import { Hono } from "hono";
import { rebuildGuideProfile } from "../services/guideProfile.js";
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
const activityTypes = ["running", "cycling", "hiking", "walking", "swimming"] as const;
const MAX_ACTIVITY_ROUTE_POINTS = 100_000;

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
  type: string;
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
    activityType: activity.type,
    title: activity.title ?? "Restored Run",
    guideNudge: "",
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
  type: z.enum(activityTypes).default("running"),
  title: z.string().optional(),
  startedAt: z.string(),
  endedAt: z.string().optional(),
  durationSecs: z.number().optional(),
  distanceM: z.number().optional(),
  elevationM: z.number().optional(),
  avgPace: z.number().optional(),
  avgHeartRate: z.number().optional(),
  activityEventId: z.string().min(1).optional(),
  followedRouteId: z.string().min(1).max(128).optional(),
  followedRouteCompleted: z.boolean().optional(),
  calories: z.number().optional(),
  route: z
    .object({
      points: z
        .array(
          z.object({
            timestamp: z.string(),
            latitude: z.number().finite().min(-90).max(90),
            longitude: z.number().finite().min(-180).max(180),
            altitude: z.number().finite().optional().nullable(),
            verticalAccuracy: z.number().finite().optional().nullable(),
          })
        )
        .max(MAX_ACTIVITY_ROUTE_POINTS),
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
}).superRefine((body, context) => {
  if (body.followedRouteCompleted && !body.followedRouteId) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["followedRouteId"],
      message: "A followed route ID is required to record route completion.",
    });
  }
  if (body.followedRouteCompleted && !body.clientActivityId) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["clientActivityId"],
      message: "A client activity ID is required to record route completion idempotently.",
    });
  }
});

type ActivityRoutePayload = NonNullable<z.infer<typeof createSchema>["route"]>;

function normalizeRoute(route: ActivityRoutePayload | null | undefined) {
  // Older clients persist an empty SavedRoute for activities without usable
  // GPS (for example Apple Health imports and manual entries). Treat a route
  // with fewer than two points as absent instead of rejecting the activity.
  if (!route || route.points.length < 2) return undefined;

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

  let resolvedFollowedRouteId: string | undefined;
  if (body.followedRouteId) {
    const followedRoute = await prisma.route.findFirst({
      where: {
        id: body.followedRouteId,
        OR: [{ visibility: "public" }, { ownerId: resolvedUserId }],
      },
      select: { id: true },
    });
    resolvedFollowedRouteId = followedRoute?.id;
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
    followedRouteId: resolvedFollowedRouteId,
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
  let routeCompletionRecorded = false;
  const createActivityWithSocialPost = () =>
    prisma.$transaction(async (transaction) => {
      const createdActivity = await transaction.activity.create({
        data: activityData,
      });
      await transaction.post.create({
        data: {
          userId: resolvedUserId,
          activityId: createdActivity.id,
          visibility: "connections",
        },
      });
      if (body.followedRouteCompleted && resolvedFollowedRouteId) {
        await recordRouteCompletion(transaction, createdActivity.id, resolvedFollowedRouteId);
      }
      return {
        activity: createdActivity,
        routeCompletionRecorded: body.followedRouteCompleted === true && resolvedFollowedRouteId != null,
      };
    });

  const updateExistingActivity = (existingActivityId: string) =>
    prisma.$transaction(async (transaction) => {
      const existing = await transaction.activity.findUniqueOrThrow({
        where: { id: existingActivityId },
      });
      if (
        existing.followedRouteId
        && resolvedFollowedRouteId
        && existing.followedRouteId !== resolvedFollowedRouteId
      ) {
        throw new RouteAssociationConflictError("A saved activity cannot be reassigned to a different followed route.");
      }

      const incomingUpdatedAt = body.clientUpdatedAt ? new Date(body.clientUpdatedAt) : null;
      const isIncomingOlder = existing.clientUpdatedAt
        && incomingUpdatedAt
        && existing.clientUpdatedAt > incomingUpdatedAt;
      let updatedActivity = existing;
      if (isIncomingOlder) {
        if (resolvedFollowedRouteId && !existing.followedRouteId) {
          const associated = await transaction.activity.updateMany({
            where: {
              id: existing.id,
              followedRouteId: null,
            },
            data: { followedRouteId: resolvedFollowedRouteId },
          });
          if (associated.count === 0) {
            throw new RouteAssociationConflictError("A saved activity cannot be reassigned to a different followed route.");
          }
          updatedActivity = await transaction.activity.findUniqueOrThrow({ where: { id: existing.id } });
        }
      } else if (!resolvedFollowedRouteId) {
        updatedActivity = await transaction.activity.update({
          where: { id: existing.id },
          data: activityData,
        });
      } else {
        const updated = await transaction.activity.updateMany({
          where: {
            id: existing.id,
            OR: [{ followedRouteId: null }, { followedRouteId: resolvedFollowedRouteId }],
          },
          data: activityData,
        });
        if (updated.count === 0) {
          throw new RouteAssociationConflictError("A saved activity cannot be reassigned to a different followed route.");
        }
        updatedActivity = await transaction.activity.findUniqueOrThrow({ where: { id: existing.id } });
      }

      if (body.followedRouteCompleted && resolvedFollowedRouteId) {
        await recordRouteCompletion(transaction, updatedActivity.id, resolvedFollowedRouteId);
      }
      return {
        activity: updatedActivity,
        routeCompletionRecorded: body.followedRouteCompleted === true && resolvedFollowedRouteId != null,
      };
    });

  try {
    if (body.clientActivityId) {
      const uniqueActivity = {
        userId_clientActivityId: {
          userId: resolvedUserId,
          clientActivityId: body.clientActivityId,
        },
      } as const;
      const existing = await prisma.activity.findUnique({ where: uniqueActivity });

      if (existing) {
        const result = await updateExistingActivity(existing.id);
        activity = result.activity;
        routeCompletionRecorded = result.routeCompletionRecorded;
      } else {
        try {
          const result = await createActivityWithSocialPost();
          activity = result.activity;
          routeCompletionRecorded = result.routeCompletionRecorded;
          wasCreated = true;
        } catch (error) {
          if (!(error instanceof Prisma.PrismaClientKnownRequestError) || error.code !== "P2002") {
            throw error;
          }
          const racedActivity = await prisma.activity.findUnique({ where: uniqueActivity });
          if (!racedActivity) throw error;
          const result = await updateExistingActivity(racedActivity.id);
          activity = result.activity;
          routeCompletionRecorded = result.routeCompletionRecorded;
        }
      }
    } else {
      const result = await createActivityWithSocialPost();
      activity = result.activity;
      routeCompletionRecorded = result.routeCompletionRecorded;
      wasCreated = true;
    }
  } catch (error) {
    if (error instanceof RouteAssociationConflictError || error instanceof RouteCompletionConflictError) {
      return c.json({ error: error.message }, 409);
    }
    throw error;
  }

  // Fire-and-forget: analyze activity + rebuild guide profile
  if (wasCreated) {
    (async () => {
      const guideProfile = await prisma.guideProfile.findUnique({
        where: { userId: resolvedUserId },
      });
      const analysis = await analyzeActivity(activity, guideProfile ?? {});
      await Promise.all([
        prisma.activity.update({
          where: { id: activity.id },
          data: { guideAnalysis: analysis },
        }),
        rebuildGuideProfile(resolvedUserId),
        enqueueActivityCompletedEvent(resolvedUserId, activity.id),
      ]);
    })().catch(console.error);
  }

  if (body.activityEventId) {
    await prisma.$transaction(async (transaction) => {
      await transaction.activityEventParticipant.updateMany({
        where: { activityEventId: body.activityEventId, userId: resolvedUserId, status: "going" },
        data: { recordedActivityId: activity.id, outcome: "completed", resolvedAt: new Date() },
      });

      const [goingCount, unresolvedCount] = await Promise.all([
        transaction.activityEventParticipant.count({
          where: { activityEventId: body.activityEventId, status: "going" },
        }),
        transaction.activityEventParticipant.count({
          where: { activityEventId: body.activityEventId, status: "going", outcome: null },
        }),
      ]);
      if (goingCount > 0 && unresolvedCount === 0) {
        await transaction.activityEvent.updateMany({
          where: { id: body.activityEventId, status: { notIn: ["completed", "cancelled"] } },
          data: { status: "completed" },
        });
      }
    });
  }

  return c.json(
    {
      id: activity.id,
      clientActivityId: activity.clientActivityId,
      status: wasCreated ? "created" : "updated",
      uploadedAt: activity.updatedAt,
      serverUpdatedAt: activity.updatedAt,
      followedRouteId: activity.followedRouteId,
      routeCompletionRecorded,
      followedRouteUnavailable: body.followedRouteId != null && resolvedFollowedRouteId == null,
    },
    wasCreated ? 201 : 200
  );
});

class RouteAssociationConflictError extends Error {}
class RouteCompletionConflictError extends Error {}

async function recordRouteCompletion(
  transaction: Prisma.TransactionClient,
  activityId: string,
  routeId: string
) {
  const activity = await transaction.activity.findUnique({
    where: { id: activityId },
    select: { followedRouteId: true },
  });
  if (activity?.followedRouteId !== routeId) {
    throw new RouteCompletionConflictError("The activity is not associated with this followed route.");
  }
  const inserted = await transaction.routeCompletion.createMany({
    data: [{ activityId, routeId }],
    skipDuplicates: true,
  });
  if (inserted.count === 0) {
    const existing = await transaction.routeCompletion.findUnique({
      where: { activityId },
      select: { routeId: true },
    });
    if (existing?.routeId !== routeId) {
      throw new RouteCompletionConflictError("This activity already completed a different route.");
    }
    return;
  }
  await transaction.route.update({
    where: { id: routeId },
    data: { completionCount: { increment: 1 } },
  });
}

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

  const deleted = await prisma.$transaction(async (transaction) => {
    await transaction.activityEventParticipant.updateMany({
      where: { recordedActivityId: activity.id },
      data: { recordedActivityId: null, outcome: null, resolvedAt: null },
    });
    return transaction.activity.update({
      where: { id: activity.id },
      data: { deletedAt: new Date(), clientData: undefined },
    });
  });
  return c.json({ status: "deleted", id: deleted.id, deletedAt: deleted.deletedAt });
});

export default router;
