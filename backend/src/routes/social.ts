import { createHash, randomBytes } from "node:crypto";
import { Hono, type Context } from "hono";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";
import { requireDatabase } from "../services/database.js";
import { getAuthenticatedAppUser } from "../services/currentUser.js";
import { getPrismaClient } from "../services/prisma.js";
import type { AppEnv } from "../types/hono.js";

const router = new Hono<AppEnv>();
const reactionSchema = z.object({ type: z.enum(["fire", "clap", "heart", "strong"]) });
const commentSchema = z.object({ body: z.string().trim().min(1).max(500) });

router.get("/together", async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const prisma = getPrismaClient();
  const connections = await acceptedConnectionIDs(user.id);
  const [upcomingRuns, memberships, posts] = await Promise.all([
    prisma.groupRun.findMany({
      where: { status: "scheduled", startsAt: { gte: new Date() }, OR: [{ creatorId: { in: [user.id, ...connections] } }, { club: { memberships: { some: { userId: user.id } } } }] },
      include: { club: true, creator: true, groups: { orderBy: { sortOrder: "asc" } } },
      orderBy: { startsAt: "asc" },
      take: 5,
    }),
    prisma.clubMembership.findMany({ where: { userId: user.id }, include: { club: true } }),
    prisma.post.findMany({
      where: { userId: { in: [user.id, ...connections] }, visibility: { in: ["connections", "public"] } },
      include: { user: true, activity: { include: { photos: true } }, reactions: true, comments: true },
      orderBy: { createdAt: "desc" },
      take: 12,
    }),
  ]);

  return c.json({
    upcomingRuns: upcomingRuns.map((run) => ({ ...run, compatibility: shareSafeCompatibility(run.groups) })),
    clubs: memberships.map((membership) => ({ ...membership.club, role: membership.role })),
    posts,
  });
});

router.post("/connections", zValidator("json", z.object({ userId: z.string().min(1) })), async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const addresseeId = c.req.valid("json").userId;
  if (addresseeId === user.id) return c.json({ error: "You cannot connect to yourself." }, 400);
  const connection = await getPrismaClient().connection.upsert({
    where: { requesterId_addresseeId: { requesterId: user.id, addresseeId } },
    create: { requesterId: user.id, addresseeId },
    update: { status: "pending" },
  });
  return c.json(connection, 201);
});

router.post("/connections/:id/accept", async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const result = await getPrismaClient().connection.updateMany({ where: { id: c.req.param("id"), addresseeId: user.id, status: "pending" }, data: { status: "accepted" } });
  if (!result.count) return c.json({ error: "Connection request not found." }, 404);
  return c.json({ ok: true });
});

router.get("/clubs", async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const clubs = await getPrismaClient().club.findMany({ where: { isDiscoverable: true }, include: { _count: { select: { memberships: true } }, memberships: { where: { userId: user.id }, select: { role: true } } }, orderBy: { name: "asc" }, take: 50 });
  return c.json({ clubs });
});

router.post("/clubs/:id/join", async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const membership = await getPrismaClient().clubMembership.upsert({ where: { clubId_userId: { clubId: c.req.param("id"), userId: user.id } }, create: { clubId: c.req.param("id"), userId: user.id }, update: {} });
  return c.json(membership, 201);
});

router.get("/group-runs/:id", async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const run = await getPrismaClient().groupRun.findUnique({ where: { id: c.req.param("id") }, include: { club: true, creator: true, groups: { orderBy: { sortOrder: "asc" } } } });
  if (!run) return c.json({ error: "Group run not found." }, 404);
  return c.json({ ...run, compatibility: shareSafeCompatibility(run.groups) });
});

router.post("/group-runs/:id/invitations", zValidator("json", z.object({ recipientUserId: z.string().optional() })), async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const token = randomBytes(24).toString("base64url");
  const invitation = await getPrismaClient().invitation.create({ data: { senderId: user.id, recipientId: c.req.valid("json").recipientUserId, groupRunId: c.req.param("id"), kind: "groupRun", tokenHash: createHash("sha256").update(token).digest("hex"), expiresAt: new Date(Date.now() + 7 * 86400000) } });
  return c.json({ id: invitation.id, token, status: invitation.status }, 201);
});

router.post("/activity-shares", zValidator("json", z.object({ activityId: z.string().min(1), caption: z.string().trim().max(1000).nullable().optional(), visibility: z.enum(["connections", "public"]).default("connections") })), async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const input = c.req.valid("json");
  if (input.caption && !isAcceptableText(input.caption)) return c.json({ error: "Please revise the caption before sharing." }, 422);
  const activity = await getPrismaClient().activity.findFirst({ where: { id: input.activityId, userId: user.id } });
  if (!activity) return c.json({ error: "Activity not found." }, 404);
  const post = await getPrismaClient().post.create({ data: { userId: user.id, activityId: activity.id, caption: input.caption ?? null, visibility: input.visibility } });
  return c.json(post, 201);
});

router.post("/posts/:id/reactions", zValidator("json", reactionSchema), async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const reaction = await getPrismaClient().reaction.upsert({ where: { userId_postId: { userId: user.id, postId: c.req.param("id") } }, create: { userId: user.id, postId: c.req.param("id"), type: c.req.valid("json").type }, update: { type: c.req.valid("json").type } });
  return c.json(reaction);
});

router.post("/posts/:id/comments", zValidator("json", commentSchema), async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const body = c.req.valid("json").body;
  if (!isAcceptableText(body)) return c.json({ error: "Please revise the comment before posting." }, 422);
  const comment = await getPrismaClient().comment.create({ data: { postId: c.req.param("id"), authorId: user.id, body } });
  return c.json(comment, 201);
});

async function requireSocialUser(c: Context<AppEnv>) {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication required." }, 401);
  return user;
}

async function acceptedConnectionIDs(userId: string) {
  const connections = await getPrismaClient().connection.findMany({ where: { status: "accepted", OR: [{ requesterId: userId }, { addresseeId: userId }] } });
  return connections.map((connection) => connection.requesterId === userId ? connection.addresseeId : connection.requesterId);
}

function shareSafeCompatibility(groups: Array<{ id: string; label: string; distanceMeters: number | null }>) {
  const selected = groups.find((group) => group.distanceMeters != null) ?? groups[0];
  return selected ? { groupId: selected.id, explanation: `${selected.label} is compatible with your available training range.` } : null;
}

function isAcceptableText(text: string) {
  const normalized = text.toLowerCase();
  return !["kill yourself", "racial slur", "sexual violence"].some((term) => normalized.includes(term));
}

export default router;
