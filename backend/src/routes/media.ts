import { Hono, type Context } from "hono";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";
import { requireDatabase } from "../services/database.js";
import { getAuthenticatedAppUser } from "../services/currentUser.js";
import { getPrismaClient } from "../services/prisma.js";
import type { AppEnv } from "../types/hono.js";

const router = new Hono<AppEnv>();

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

export default router;
