import { Hono } from "hono";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";
import { requireDatabase } from "../services/database.js";
import { getAuthenticatedAppUser } from "../services/currentUser.js";
import { getPrismaClient } from "../services/prisma.js";
import type { AppEnv } from "../types/hono.js";

const router = new Hono<AppEnv>();
const registrationSchema = z.object({
  token: z.string().min(20).max(4096),
  platform: z.literal("ios"),
  appBundle: z.string().min(1).max(255),
  locale: z.string().min(2).max(32).optional(),
});

router.put("/devices", zValidator("json", registrationSchema), async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication required." }, 401);
  const body = c.req.valid("json");
  await getPrismaClient().pushDevice.upsert({
    where: { token: body.token },
    create: { ...body, userId: user.id },
    update: { ...body, userId: user.id, enabled: true, lastSeenAt: new Date() },
  });
  return c.json({ ok: true });
});

router.delete("/devices/:token", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication required." }, 401);
  await getPrismaClient().pushDevice.deleteMany({ where: { token: c.req.param("token"), userId: user.id } });
  return c.json({ ok: true });
});

export default router;
