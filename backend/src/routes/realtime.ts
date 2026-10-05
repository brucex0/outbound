import { Hono } from "hono";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";
import { getAuthenticatedAppUser } from "../services/currentUser.js";
import { getPrismaClient } from "../services/prisma.js";
import { requireDatabase } from "../services/database.js";
import { ablyChannel, issueAblyToken } from "../services/ably.js";
import type { AppEnv } from "../types/hono.js";

const router = new Hono<AppEnv>();
const tokenSchema = z.object({
  kind: z.enum(["group_run", "live_share"]),
  sessionId: z.string().min(1).max(128),
});

router.post("/token", zValidator("json", tokenSchema), async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication is required." }, 401);
  const { kind, sessionId } = c.req.valid("json");
  const prisma = getPrismaClient();
  let capabilities: string[] | null = null;

  if (kind === "group_run") {
    const participant = await prisma.liveGroupParticipant.findUnique({
      where: { sessionId_userId: { sessionId, userId: user.id } },
      include: { session: true },
    });
    if (participant?.session.status === "active" && participant.session.expiresAt > new Date()
      && participant.status === "active") {
      capabilities = ["publish", "subscribe"];
    }
  } else {
    const share = await prisma.safetyLiveShare.findFirst({
      where: {
        id: sessionId,
        status: "active",
        expiresAt: { gt: new Date() },
        OR: [
          { userId: user.id },
          { recipients: { some: { recipientId: user.id } } },
        ],
      },
      select: { userId: true },
    });
    if (share) capabilities = share.userId === user.id ? ["publish", "subscribe"] : ["subscribe"];
  }

  if (!capabilities) return c.json({ error: "Live session not found." }, 404);
  try {
    const channel = ablyChannel(kind, sessionId);
    const token = await issueAblyToken({ channel, clientId: user.id, capabilities });
    return c.json({ token: token.token, expiresAt: token.expires, channel, clientId: user.id });
  } catch {
    return c.json({ error: "Realtime connection is unavailable." }, 503);
  }
});

export default router;
