import { Hono } from "hono";
import { z } from "zod";
import type { AppEnv } from "../types/hono.js";
import { getPrismaClient } from "../services/prisma.js";
import { reconcileRevenueCatPlus, verifyRevenueCatWebhookSignature } from "../services/revenueCat.js";

const router = new Hono<AppEnv>();
const webhookSchema = z.object({
  api_version: z.string(),
  event: z.object({
    id: z.string().optional(),
    app_user_id: z.string().min(1).max(256),
  }).passthrough(),
}).passthrough();

router.post("/", async (c) => {
  const rawBody = await c.req.text();
  if (rawBody.length > 131_072) return c.json({ error: "Payload too large." }, 413);
  if (!verifyRevenueCatWebhookSignature(rawBody, c.req.header("X-RevenueCat-Webhook-Signature"))) {
    return c.json({ error: "Invalid webhook signature." }, 401);
  }
  let parsed: unknown;
  try { parsed = JSON.parse(rawBody); }
  catch { return c.json({ error: "Invalid JSON." }, 400); }
  const payload = webhookSchema.safeParse(parsed);
  if (!payload.success) return c.json({ error: "Invalid webhook payload." }, 400);

  const prisma = getPrismaClient();
  const user = await prisma.user.findUnique({ where: { id: payload.data.event.app_user_id }, select: { id: true } });
  if (!user) return c.json({ received: true, reconciled: false });
  await reconcileRevenueCatPlus(prisma, user.id);
  return c.json({ received: true, reconciled: true });
});

export default router;
