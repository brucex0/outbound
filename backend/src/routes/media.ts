import { Hono } from "hono";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";
import { requireDatabase } from "../services/database.js";
import { getPrismaClient } from "../services/prisma.js";

const router = new Hono();

// Returns a signed GCS upload URL — client uploads directly, then calls /confirm
router.post(
  "/upload-url",
  zValidator(
    "json",
    z.object({
      activityId: z.string(),
      filename: z.string(),
      contentType: z.string(),
    })
  ),
  async (c) => {
    const unavailable = requireDatabase(c);
    if (unavailable) return unavailable;

    const prisma = getPrismaClient();
    const { activityId, filename, contentType } = c.req.valid("json");
    const key = `activities/${activityId}/${Date.now()}-${filename}`;
    // TODO: generate signed GCS URL
    // const { Storage } = await import("@google-cloud/storage");
    // const [url] = await new Storage().bucket(process.env.GCS_BUCKET_NAME!).file(key).getSignedUrl(...)
    const signedUrl = `https://storage.googleapis.com/${process.env.GCS_BUCKET_NAME}/${key}`;
    return c.json({ uploadUrl: signedUrl, key });
  }
);

// Confirm upload and attach photo record to activity
router.post(
  "/confirm",
  zValidator(
    "json",
    z.object({
      activityId: z.string(),
      key: z.string(),
      takenAt: z.string(),
      paceAtShot: z.number().optional(),
      hrAtShot: z.number().optional(),
      distAtShot: z.number().optional(),
      lat: z.number().optional(),
      lng: z.number().optional(),
    })
  ),
  async (c) => {
    const unavailable = requireDatabase(c);
    if (unavailable) return unavailable;

    const prisma = getPrismaClient();
    const body = c.req.valid("json");
    const url = `https://storage.googleapis.com/${process.env.GCS_BUCKET_NAME}/${body.key}`;
    const photo = await prisma.photo.create({
      data: {
        activityId: body.activityId,
        url,
        takenAt: new Date(body.takenAt),
        paceAtShot: body.paceAtShot,
        hrAtShot: body.hrAtShot,
        distAtShot: body.distAtShot,
        lat: body.lat,
        lng: body.lng,
      },
    });
    return c.json(photo, 201);
  }
);

export default router;
