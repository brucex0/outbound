import { createHash, randomBytes } from "node:crypto";
import { Hono } from "hono";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";
import { requireDatabase } from "../services/database.js";
import { getAuthenticatedAppUser } from "../services/currentUser.js";
import { getPrismaClient } from "../services/prisma.js";
import type { AppEnv } from "../types/hono.js";

const router = new Hono<AppEnv>();

const createGroupRunSchema = z.object({
  title: z.string().trim().min(1).max(120).optional(),
  sport: z.string().trim().min(1).max(32).optional(),
  expiresInSeconds: z.number().int().min(300).max(8 * 60 * 60).optional(),
});

const joinGroupRunSchema = z.object({
  invite: z.string().trim().min(8).max(512),
});

const liveLocationSchema = z.object({
  recordedAt: z.string(),
  latitude: z.number().finite().min(-90).max(90),
  longitude: z.number().finite().min(-180).max(180),
  altitudeM: z.number().finite().optional().nullable(),
  accuracyM: z.number().finite().optional().nullable(),
  elapsedSeconds: z.number().int().min(0),
  distanceM: z.number().finite().min(0),
  paceSecondsPerKM: z.number().finite().optional().nullable(),
});

router.post("/group-runs", zValidator("json", createGroupRunSchema), async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication is required." }, 401);

  const body = c.req.valid("json");
  const prisma = getPrismaClient();
  const token = randomToken();
  const startedAt = new Date();
  const expiresAt = new Date(startedAt.getTime() + (body.expiresInSeconds ?? 4 * 60 * 60) * 1000);

  const session = await prisma.liveGroupSession.create({
    data: {
      creatorUserId: user.id,
      inviteTokenHash: hashToken(token),
      title: body.title,
      sport: body.sport,
      startedAt,
      expiresAt,
      participants: {
        create: {
          userId: user.id,
          displayName: user.displayName || user.username,
        },
      },
    },
    include: { participants: true },
  });

  return c.json(groupRunPayload(session, user.id, token, groupRunInviteURL(c.req.url, token)), 201);
});

router.post("/group-runs/join", zValidator("json", joinGroupRunSchema), async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication is required." }, 401);

  const token = inviteToken(c.req.valid("json").invite);
  if (!token) return c.json({ error: "Invite link is invalid." }, 400);

  const prisma = getPrismaClient();
  const session = await prisma.liveGroupSession.findUnique({
    where: { inviteTokenHash: hashToken(token) },
    include: { participants: true },
  });
  if (!session) return c.json({ error: "Live group not found." }, 404);

  const activeSession = await requireActiveSession(session.id);
  if (!activeSession) return c.json({ error: "Live group has ended." }, 410);

  await prisma.liveGroupParticipant.upsert({
    where: { sessionId_userId: { sessionId: session.id, userId: user.id } },
    update: {
      status: "active",
      leftAt: null,
      displayName: user.displayName || user.username,
    },
    create: {
      sessionId: session.id,
      userId: user.id,
      displayName: user.displayName || user.username,
    },
  });

  const updated = await prisma.liveGroupSession.findUniqueOrThrow({
    where: { id: session.id },
    include: { participants: true },
  });

  return c.json(groupRunPayload(updated, user.id, token, groupRunInviteURL(c.req.url, token)));
});

router.get("/group-runs/:id", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication is required." }, 401);

  const session = await requireParticipantSession(c.req.param("id"), user.id);
  if (!session) return c.json({ error: "Live group not found." }, 404);

  const refreshedSession = await refreshSessionStatus(session.id);
  return c.json(groupRunPayload(refreshedSession ?? session, user.id));
});

router.patch(
  "/group-runs/:id/participants/me/location",
  zValidator("json", liveLocationSchema),
  async (c) => {
    const unavailable = requireDatabase(c);
    if (unavailable) return unavailable;

    const user = await getAuthenticatedAppUser(c);
    if (!user) return c.json({ error: "Authentication is required." }, 401);

    const session = await requireParticipantSession(c.req.param("id"), user.id);
    if (!session) return c.json({ error: "Live group not found." }, 404);

    const activeSession = await requireActiveSession(session.id);
    if (!activeSession) return c.json({ error: "Live group has ended." }, 410);

    const body = c.req.valid("json");
    const recordedAt = new Date(body.recordedAt);
    const location = {
      latitude: body.latitude,
      longitude: body.longitude,
      altitudeM: body.altitudeM ?? null,
      accuracyM: body.accuracyM ?? null,
    };
    const activitySnapshot = {
      elapsedSeconds: body.elapsedSeconds,
      distanceM: body.distanceM,
      paceSecondsPerKM: body.paceSecondsPerKM ?? null,
    };

    await getPrismaClient().liveGroupParticipant.update({
      where: { sessionId_userId: { sessionId: session.id, userId: user.id } },
      data: {
        status: "active",
        leftAt: null,
        lastLocationAt: recordedAt,
        lastLocation: location,
        lastActivitySnapshot: activitySnapshot,
      },
    });

    const updated = await getPrismaClient().liveGroupSession.findUniqueOrThrow({
      where: { id: session.id },
      include: { participants: true },
    });

    return c.json(groupRunPayload(updated, user.id));
  }
);

router.post("/group-runs/:id/participants/me/leave", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication is required." }, 401);

  const session = await requireParticipantSession(c.req.param("id"), user.id);
  if (!session) return c.json({ error: "Live group not found." }, 404);

  await getPrismaClient().liveGroupParticipant.update({
    where: { sessionId_userId: { sessionId: session.id, userId: user.id } },
    data: {
      status: "left",
      leftAt: new Date(),
    },
  });

  const updated = await getPrismaClient().liveGroupSession.findUniqueOrThrow({
    where: { id: session.id },
    include: { participants: true },
  });

  return c.json(groupRunPayload(updated, user.id));
});

router.post("/group-runs/:id/end", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication is required." }, 401);

  const prisma = getPrismaClient();
  const session = await prisma.liveGroupSession.findFirst({
    where: { id: c.req.param("id"), creatorUserId: user.id },
    include: { participants: true },
  });
  if (!session) return c.json({ error: "Live group not found." }, 404);

  const updated = await prisma.liveGroupSession.update({
    where: { id: session.id },
    data: {
      status: session.status === "active" ? "ended" : session.status,
      endedAt: session.endedAt ?? new Date(),
      participants: {
        updateMany: {
          where: { status: "active" },
          data: { status: "finished", leftAt: new Date() },
        },
      },
    },
    include: { participants: true },
  });

  return c.json(groupRunPayload(updated, user.id));
});

async function requireParticipantSession(sessionId: string, userId: string) {
  return getPrismaClient().liveGroupSession.findFirst({
    where: {
      id: sessionId,
      participants: { some: { userId } },
    },
    include: { participants: true },
  });
}

async function refreshSessionStatus(sessionId: string) {
  const prisma = getPrismaClient();
  const session = await prisma.liveGroupSession.findUnique({
    where: { id: sessionId },
    include: { participants: true },
  });
  if (!session) return null;
  if (session.status !== "active" || session.endedAt) return session;
  if (session.expiresAt > new Date()) return session;

  return prisma.liveGroupSession.update({
    where: { id: session.id },
    data: {
      status: "expired",
      endedAt: session.endedAt ?? new Date(),
      participants: {
        updateMany: {
          where: { status: "active" },
          data: { status: "finished", leftAt: new Date() },
        },
      },
    },
    include: { participants: true },
  });
}

async function requireActiveSession(sessionId: string) {
  const session = await refreshSessionStatus(sessionId);
  if (!session || session.status !== "active" || session.endedAt) return null;
  return session;
}

function groupRunPayload(
  session: {
    id: string;
    status: string;
    title: string | null;
    sport: string | null;
    creatorUserId: string;
    startedAt: Date;
    expiresAt: Date;
    endedAt: Date | null;
    participants: Array<{
      id: string;
      userId: string;
      displayName: string;
      status: string;
      joinedAt: Date;
      leftAt: Date | null;
      lastLocationAt: Date | null;
      lastLocation: unknown;
      lastActivitySnapshot: unknown;
    }>;
  },
  currentUserId: string,
  inviteToken?: string,
  inviteURL?: string
) {
  const now = Date.now();
  return {
    id: session.id,
    status: session.status,
    title: session.title,
    sport: session.sport,
    creatorUserId: session.creatorUserId,
    currentUserId,
    startedAt: session.startedAt,
    expiresAt: session.expiresAt,
    endedAt: session.endedAt,
    inviteToken,
    inviteURL,
    participants: session.participants.map((participant) => {
      const lastLocationAt = participant.lastLocationAt;
      const stale =
        participant.status === "active" &&
        Boolean(lastLocationAt) &&
        now - (lastLocationAt?.getTime() ?? 0) > 60_000;
      return {
        id: participant.id,
        userId: participant.userId,
        displayName: participant.displayName,
        status: stale ? "stale" : participant.status,
        joinedAt: participant.joinedAt,
        leftAt: participant.leftAt,
        lastLocationAt,
        lastLocation: participant.lastLocation,
        lastActivitySnapshot: participant.lastActivitySnapshot,
      };
    }),
  };
}

function randomToken() {
  return randomBytes(32).toString("base64url");
}

function hashToken(token: string) {
  return createHash("sha256").update(token).digest("hex");
}

function inviteToken(rawInvite: string) {
  const trimmed = rawInvite.trim();
  if (trimmed.length === 0) return null;
  try {
    const url = new URL(trimmed);
    const pathToken = url.pathname.split("/").filter(Boolean).at(-1);
    return pathToken && pathToken.length >= 8 ? pathToken : null;
  } catch {
    return trimmed;
  }
}

function groupRunInviteURL(requestURL: string, token: string) {
  const configured = process.env.PUBLIC_WEB_BASE_URL?.trim();
  const origin = configured && configured.length > 0 ? configured : new URL(requestURL).origin;
  return `${origin.replace(/\/$/, "")}/live/group/${encodeURIComponent(token)}`;
}

export default router;
