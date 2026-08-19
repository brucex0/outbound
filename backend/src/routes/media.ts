import { Hono, type Context } from "hono";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";
import { requireDatabase } from "../services/database.js";
import { getAuthenticatedAppUser } from "../services/currentUser.js";
import { getPrismaClient } from "../services/prisma.js";
import type { AppEnv } from "../types/hono.js";
import {
  activityPhotoSHA256,
  activityPhotoStorageKey,
  deleteActivityPhoto,
  maximumActivityPhotoBytes,
  signedActivityPhotoURL,
  saveActivityPhoto,
} from "../services/activityPhotoStorage.js";

const router = new Hono<AppEnv>();

const activityPhotoSchema = z.object({
  activityId: z.string().min(1),
  clientPhotoId: z.string().uuid(),
  base64: z.string().min(1).max(Math.ceil(maximumActivityPhotoBytes * 4 / 3) + 16),
  takenAt: z.string().datetime(),
  paceAtShot: z.number().finite().optional(),
  hrAtShot: z.number().int().nonnegative().optional(),
  distAtShot: z.number().finite().nonnegative().optional(),
  latitude: z.number().min(-90).max(90).optional(),
  longitude: z.number().min(-180).max(180).optional(),
  captureContext: z.string().max(40).optional(),
});

router.post("/activity-photos", zValidator("json", activityPhotoSchema), async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) return user;
  const input = c.req.valid("json");
  const prisma = getPrismaClient();
  const activity = await prisma.activity.findFirst({
    where: {
      userId: user.id,
      deletedAt: null,
      OR: [{ id: input.activityId }, { clientActivityId: input.activityId }],
    },
  });
  if (!activity) return c.json({ error: "Activity not found." }, 404);

  const data = Buffer.from(input.base64, "base64");
  if (data.length === 0 || data.toString("base64").replace(/=+$/, "") !== input.base64.replace(/=+$/, "")) {
    return c.json({ error: "Photo data is invalid." }, 400);
  }
  const storageKey = activityPhotoStorageKey(user.id, activity.id, input.clientPhotoId);
  try {
    await saveActivityPhoto(storageKey, data);
    const photo = await prisma.photo.upsert({
      where: { activityId_clientPhotoId: { activityId: activity.id, clientPhotoId: input.clientPhotoId } },
      create: {
        activityId: activity.id,
        clientPhotoId: input.clientPhotoId,
        storageKey,
        contentType: "image/jpeg",
        byteSize: data.length,
        sha256: activityPhotoSHA256(data),
        url: "",
        takenAt: new Date(input.takenAt),
        paceAtShot: input.paceAtShot,
        hrAtShot: input.hrAtShot,
        distAtShot: input.distAtShot,
        lat: input.latitude,
        lng: input.longitude,
        captureContext: input.captureContext,
      },
      update: {
        storageKey,
        byteSize: data.length,
        sha256: activityPhotoSHA256(data),
        takenAt: new Date(input.takenAt),
        paceAtShot: input.paceAtShot,
        hrAtShot: input.hrAtShot,
        distAtShot: input.distAtShot,
        lat: input.latitude,
        lng: input.longitude,
        captureContext: input.captureContext,
      },
    });
    return c.json(activityPhotoResponse(photo), 201);
  } catch (error) {
    console.error("[activity-photo] upload failed", error);
    return c.json({ error: error instanceof Error ? error.message : "Photo upload failed." }, 503);
  }
});

router.get("/activity-photos/:id/content", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) return user;
  const photo = await getPrismaClient().photo.findFirst({
    where: { id: c.req.param("id"), activity: { userId: user.id, deletedAt: null } },
  });
  if (!photo) return c.json({ error: "Photo not found." }, 404);
  const url = await signedActivityPhotoURL(photo.storageKey);
  if (!url) return c.json({ error: "Photo content not found." }, 404);
  return c.redirect(url, 302);
});

router.delete("/activity-photos/:id", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) return user;
  const prisma = getPrismaClient();
  const photo = await prisma.photo.findFirst({
    where: { id: c.req.param("id"), activity: { userId: user.id } },
  });
  if (!photo) return c.json({ status: "deleted" });
  await deleteActivityPhoto(photo.storageKey);
  await prisma.photo.delete({ where: { id: photo.id } });
  return c.json({ status: "deleted", id: photo.id });
});

const momentSchema = z.object({
  activityId: z.string().min(1),
  clientMomentId: z.string().min(1).max(100),
  storageKey: z.string().min(1).max(1000),
  takenAt: z.string().datetime(),
  elapsedSeconds: z.number().int().nonnegative().optional(),
  phaseId: z.string().max(100).optional(),
  latitude: z.number().min(-90).max(90).optional(),
  longitude: z.number().min(-180).max(180).optional(),
  altText: z.string().trim().max(300).optional(),
});

router.post("/moments", zValidator("json", momentSchema), async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) return user;
  const input = c.req.valid("json");
  const activity = await getPrismaClient().activity.findFirst({ where: { id: input.activityId, userId: user.id } });
  if (!activity) return c.json({ error: "Activity not found." }, 404);
  const moment = await getPrismaClient().moment.upsert({
    where: { userId_clientMomentId: { userId: user.id, clientMomentId: input.clientMomentId } },
    create: { userId: user.id, ...input, takenAt: new Date(input.takenAt), visibility: "private" },
    update: { storageKey: input.storageKey, altText: input.altText, elapsedSeconds: input.elapsedSeconds, phaseId: input.phaseId, latitude: input.latitude, longitude: input.longitude },
  });
  return c.json(privateMoment(moment), 201);
});

router.post("/moments/:id/share", zValidator("json", z.object({ visibility: z.enum(["connections", "public"]) })), async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) return user;
  const result = await getPrismaClient().moment.updateMany({ where: { id: c.req.param("id"), userId: user.id }, data: { visibility: c.req.valid("json").visibility } });
  if (!result.count) return c.json({ error: "Moment not found." }, 404);
  const moment = await getPrismaClient().moment.findUniqueOrThrow({ where: { id: c.req.param("id") } });
  return c.json(sharedMoment(moment));
});

async function requireUser(c: Context<AppEnv>) {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication required." }, 401);
  return user;
}

function privateMoment(moment: { id: string; activityId: string; takenAt: Date; elapsedSeconds: number | null; phaseId: string | null; altText: string | null; visibility: string }) {
  return { id: moment.id, activityId: moment.activityId, takenAt: moment.takenAt, elapsedSeconds: moment.elapsedSeconds, phaseId: moment.phaseId, altText: moment.altText, visibility: moment.visibility };
}

function sharedMoment(moment: Parameters<typeof privateMoment>[0]) {
  // Location and storage keys never cross this boundary. Media delivery must use a short-lived CDN URL.
  return privateMoment(moment);
}

function activityPhotoResponse(photo: {
  id: string; clientPhotoId: string; takenAt: Date; paceAtShot: number | null;
  hrAtShot: number | null; distAtShot: number | null; lat: number | null;
  lng: number | null; captureContext: string | null; byteSize: number; sha256: string;
  createdAt: Date; updatedAt: Date;
}) {
  return {
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
  };
}

export default router;
