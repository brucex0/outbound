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
const reportSchema = z.object({
  targetType: z.enum(["post", "comment", "user"]),
  targetId: z.string().min(1),
  reason: z.enum(["spam", "harassment", "hate", "sexual", "violence", "privacy", "other"]),
  details: z.string().trim().max(500).optional(),
});

router.get("/home", socialHome);
router.get("/together", socialHome);

async function socialHome(c: Context<AppEnv>) {
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
      include: {
        user: { select: socialPersonSelect },
        activity: { select: socialActivitySelect },
        reactions: { select: { id: true, userId: true, type: true } },
        comments: {
          include: { author: { select: socialPersonSelect } },
          orderBy: { createdAt: "asc" },
          take: 2,
        },
        _count: { select: { comments: true } },
      },
      orderBy: { createdAt: "desc" },
      take: 12,
    }),
  ]);

  return c.json({
    upcomingRuns: upcomingRuns.map((run) => ({ ...run, compatibility: shareSafeCompatibility(run.groups) })),
    clubs: memberships.map((membership) => ({ ...membership.club, role: membership.role })),
    posts: posts.map((post) => postPayload(post, user.id)),
  });
}

router.get("/connections", async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const connections = await getPrismaClient().connection.findMany({
    where: { OR: [{ requesterId: user.id }, { addresseeId: user.id }] },
    include: {
      requester: { select: socialPersonSelect },
      addressee: { select: socialPersonSelect },
    },
    orderBy: { updatedAt: "desc" },
  });
  return c.json({
    connections: connections.map((connection) => connectionPayload(connection, user.id)),
  });
});

router.get("/people/search", async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const query = c.req.query("q")?.trim();
  if (!query || query.length < 2) return c.json({ people: [] });
  const blocked = await blockedUserIDs(user.id);
  const people = await getPrismaClient().user.findMany({
    where: {
      id: { notIn: [user.id, ...blocked] },
      OR: [
        { displayName: { contains: query, mode: "insensitive" } },
        { username: { contains: query, mode: "insensitive" } },
      ],
    },
    select: socialPersonSelect,
    orderBy: [{ displayName: "asc" }, { username: "asc" }],
    take: 20,
  });
  const relationships = await getPrismaClient().connection.findMany({
    where: {
      OR: [
        { requesterId: user.id, addresseeId: { in: people.map((person) => person.id) } },
        { addresseeId: user.id, requesterId: { in: people.map((person) => person.id) } },
      ],
    },
  });
  return c.json({
    people: people.map((person) => {
      const relationship = relationships.find((candidate) =>
        candidate.requesterId === person.id || candidate.addresseeId === person.id
      );
      return {
        ...person,
        relationship: relationship
          ? {
              id: relationship.id,
              status: relationship.status,
              direction: relationship.requesterId === user.id ? "outgoing" : "incoming",
            }
          : null,
      };
    }),
  });
});

router.post("/connections", zValidator("json", z.object({ userId: z.string().min(1) })), async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const addresseeId = c.req.valid("json").userId;
  if (addresseeId === user.id) return c.json({ error: "You cannot connect to yourself." }, 400);
  const addressee = await getPrismaClient().user.findUnique({
    where: { id: addresseeId },
    select: { id: true },
  });
  if (!addressee) return c.json({ error: "Person not found." }, 404);
  if ((await blockedUserIDs(user.id)).includes(addresseeId)) {
    return c.json({ error: "Person not found." }, 404);
  }
  const existing = await getPrismaClient().connection.findFirst({
    where: {
      OR: [
        { requesterId: user.id, addresseeId },
        { requesterId: addresseeId, addresseeId: user.id },
      ],
    },
  });
  if (existing) return c.json(existing, 200);
  const connection = await getPrismaClient().connection.create({
    data: { requesterId: user.id, addresseeId },
  });
  await createSocialNotification(addresseeId, user.id, "connectionRequest", connection.id, `${user.displayName} wants to connect.`);
  return c.json(connection, 201);
});

router.post("/connections/:id/accept", async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const result = await getPrismaClient().connection.updateMany({ where: { id: c.req.param("id"), addresseeId: user.id, status: "pending" }, data: { status: "accepted" } });
  if (!result.count) return c.json({ error: "Connection request not found." }, 404);
  const connection = await getPrismaClient().connection.findUnique({ where: { id: c.req.param("id") } });
  if (connection) {
    await dismissSocialNotification(user.id, "connectionRequest", connection.id);
    await createSocialNotification(connection.requesterId, user.id, "connectionAccepted", connection.id, `${user.displayName} accepted your connection request.`);
  }
  return c.json({ ok: true });
});

router.post("/users/:id/block", async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const blockedId = c.req.param("id");
  if (blockedId === user.id) return c.json({ error: "You cannot block yourself." }, 400);
  const target = await getPrismaClient().user.findUnique({ where: { id: blockedId }, select: { id: true } });
  if (!target) return c.json({ error: "Person not found." }, 404);
  await getPrismaClient().$transaction([
    getPrismaClient().socialBlock.upsert({
      where: { blockerId_blockedId: { blockerId: user.id, blockedId } },
      create: { blockerId: user.id, blockedId },
      update: {},
    }),
    getPrismaClient().connection.deleteMany({
      where: { OR: [{ requesterId: user.id, addresseeId: blockedId }, { requesterId: blockedId, addresseeId: user.id }] },
    }),
  ]);
  return c.json({ ok: true });
});

router.delete("/users/:id/block", async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  await getPrismaClient().socialBlock.deleteMany({ where: { blockerId: user.id, blockedId: c.req.param("id") } });
  return c.json({ ok: true });
});

router.get("/blocks", async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const blocks = await getPrismaClient().socialBlock.findMany({
    where: { blockerId: user.id },
    include: { blocked: { select: socialPersonSelect } },
    orderBy: { createdAt: "desc" },
  });
  return c.json({ blocks: blocks.map((block) => ({ id: block.id, person: block.blocked })) });
});

router.post("/reports", zValidator("json", reportSchema), async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const input = c.req.valid("json");
  const report = await getPrismaClient().socialReport.create({
    data: { reporterId: user.id, ...input, details: input.details || null },
  });
  return c.json({ id: report.id, status: report.status }, 201);
});

router.get("/notifications", async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const notifications = await getPrismaClient().socialNotification.findMany({
    where: { recipientId: user.id },
    include: { actor: { select: socialPersonSelect } },
    orderBy: { createdAt: "desc" },
    take: 50,
  });
  return c.json({ notifications });
});

router.post("/notifications/read-all", async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  await getPrismaClient().socialNotification.updateMany({
    where: { recipientId: user.id, readAt: null },
    data: { readAt: new Date() },
  });
  return c.json({ ok: true });
});

router.delete("/connections/:id", async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const connection = await getPrismaClient().connection.findFirst({
    where: {
      id: c.req.param("id"),
      OR: [{ requesterId: user.id }, { addresseeId: user.id }],
    },
    select: { id: true, addresseeId: true },
  });
  if (!connection) return c.json({ error: "Connection not found." }, 404);
  await getPrismaClient().connection.delete({ where: { id: connection.id } });
  await dismissSocialNotification(connection.addresseeId, "connectionRequest", connection.id);
  return c.json({ ok: true });
});

router.get("/clubs", async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const clubs = await getPrismaClient().club.findMany({ where: { isDiscoverable: true }, include: { _count: { select: { memberships: true } }, memberships: { where: { userId: user.id }, select: { role: true } } }, orderBy: { name: "asc" }, take: 50 });
  return c.json({ clubs });
});

router.get("/groups", async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const groups = await getPrismaClient().club.findMany({
    where: { isDiscoverable: true },
    include: {
      _count: { select: { memberships: true } },
      memberships: { where: { userId: user.id }, select: { role: true } },
    },
    orderBy: { name: "asc" },
    take: 50,
  });
  return c.json({
    groups: groups.map((group) => ({
      id: group.id,
      name: group.name,
      description: group.description,
      city: group.city,
      memberCount: group._count.memberships,
      membershipRole: group.memberships[0]?.role ?? null,
    })),
  });
});

router.post("/groups/:id/membership", async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const membership = await getPrismaClient().clubMembership.upsert({
    where: { clubId_userId: { clubId: c.req.param("id"), userId: user.id } },
    create: { clubId: c.req.param("id"), userId: user.id },
    update: {},
  });
  return c.json(membership, 201);
});

router.delete("/groups/:id/membership", async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  await getPrismaClient().clubMembership.deleteMany({ where: { clubId: c.req.param("id"), userId: user.id } });
  return c.json({ ok: true });
});

router.post("/clubs/:id/join", async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const membership = await getPrismaClient().clubMembership.upsert({ where: { clubId_userId: { clubId: c.req.param("id"), userId: user.id } }, create: { clubId: c.req.param("id"), userId: user.id }, update: {} });
  return c.json(membership, 201);
});

router.delete("/clubs/:id/membership", async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const result = await getPrismaClient().clubMembership.deleteMany({
    where: { clubId: c.req.param("id"), userId: user.id },
  });
  if (!result.count) return c.json({ error: "Club membership not found." }, 404);
  return c.json({ ok: true });
});

router.get("/group-runs/:id", async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const run = await getPrismaClient().groupRun.findUnique({ where: { id: c.req.param("id") }, include: { club: true, creator: true, groups: { orderBy: { sortOrder: "asc" } }, rsvps: { select: { userId: true, status: true } } } });
  if (!run) return c.json({ error: "Group run not found." }, 404);
  return c.json({ ...run, attendeeCount: run.rsvps.filter((rsvp) => rsvp.status === "going").length, currentUserGoing: run.rsvps.some((rsvp) => rsvp.userId === user.id && rsvp.status === "going"), compatibility: shareSafeCompatibility(run.groups) });
});

router.post("/group-runs/:id/rsvp", async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const run = await getPrismaClient().groupRun.findUnique({ where: { id: c.req.param("id") }, select: { id: true } });
  if (!run) return c.json({ error: "Group run not found." }, 404);
  const rsvp = await getPrismaClient().groupRunRSVP.upsert({
    where: { groupRunId_userId: { groupRunId: run.id, userId: user.id } },
    create: { groupRunId: run.id, userId: user.id, status: "going" },
    update: { status: "going" },
  });
  return c.json(rsvp);
});

router.delete("/group-runs/:id/rsvp", async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  await getPrismaClient().groupRunRSVP.deleteMany({ where: { groupRunId: c.req.param("id"), userId: user.id } });
  return c.json({ ok: true });
});

router.post("/group-runs/:id/invitations", zValidator("json", z.object({ recipientUserId: z.string().optional() })), async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const token = randomBytes(24).toString("base64url");
  const recipientId = c.req.valid("json").recipientUserId;
  if (recipientId && !(await acceptedConnectionIDs(user.id)).includes(recipientId)) {
    return c.json({ error: "Connect with this person before inviting them." }, 403);
  }
  const invitation = await getPrismaClient().invitation.create({ data: { senderId: user.id, recipientId, groupRunId: c.req.param("id"), kind: "groupRun", tokenHash: createHash("sha256").update(token).digest("hex"), expiresAt: new Date(Date.now() + 7 * 86400000) } });
  if (recipientId) await createSocialNotification(recipientId, user.id, "runInvitation", invitation.id, `${user.displayName} invited you to a group run.`);
  return c.json({ id: invitation.id, token, status: invitation.status }, 201);
});

router.post("/invitations/:id/accept", async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const invitation = await getPrismaClient().invitation.findFirst({
    where: { id: c.req.param("id"), recipientId: user.id, status: "pending" },
  });
  if (!invitation || !invitation.groupRunId) return c.json({ error: "Invitation not found." }, 404);
  await getPrismaClient().$transaction([
    getPrismaClient().invitation.update({ where: { id: invitation.id }, data: { status: "accepted" } }),
    getPrismaClient().groupRunRSVP.upsert({
      where: { groupRunId_userId: { groupRunId: invitation.groupRunId, userId: user.id } },
      create: { groupRunId: invitation.groupRunId, userId: user.id, status: "going" },
      update: { status: "going" },
    }),
  ]);
  await dismissSocialNotification(user.id, "runInvitation", invitation.id);
  await createSocialNotification(invitation.senderId, user.id, "invitationAccepted", invitation.groupRunId, `${user.displayName} accepted your run invitation.`);
  return c.json({ ok: true });
});

router.post("/referrals", async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const existing = await getPrismaClient().referralLink.findUnique({ where: { creatorId: user.id } });
  const referral = existing ?? await getPrismaClient().referralLink.create({
    data: { creatorId: user.id, code: randomBytes(12).toString("base64url") },
  });
  return c.json({
    code: referral.code,
    url: `${publicWebBaseURL()}/invite/r/${referral.code}`,
    clickCount: referral.clickCount,
    claimCount: referral.claimCount,
  }, existing ? 200 : 201);
});

router.post("/referrals/:code/claim", async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const referral = await getPrismaClient().referralLink.findUnique({ where: { code: c.req.param("code") } });
  if (!referral) return c.json({ error: "Referral not found." }, 404);
  if (referral.creatorId === user.id) return c.json({ claimed: false, reason: "self" });
  const existing = await getPrismaClient().referralClaim.findUnique({ where: { claimantId: user.id } });
  if (existing) return c.json({ claimed: existing.referralLinkId === referral.id, reason: "already_claimed" });
  await getPrismaClient().$transaction([
    getPrismaClient().referralClaim.create({ data: { referralLinkId: referral.id, claimantId: user.id } }),
    getPrismaClient().referralLink.update({ where: { id: referral.id }, data: { claimCount: { increment: 1 } } }),
  ]);
  return c.json({ claimed: true });
});

router.post("/activity-shares", zValidator("json", z.object({ activityId: z.string().min(1), caption: z.string().trim().max(1000).nullable().optional(), visibility: z.enum(["connections", "public"]).default("connections") })), async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const input = c.req.valid("json");
  if (input.caption && !isAcceptableText(input.caption)) return c.json({ error: "Please revise the caption before sharing." }, 422);
  const activity = await getPrismaClient().activity.findFirst({ where: { id: input.activityId, userId: user.id, deletedAt: null } });
  if (!activity) return c.json({ error: "Activity not found." }, 404);
  const existingPost = await getPrismaClient().post.findFirst({ where: { userId: user.id, activityId: activity.id } });
  const post = existingPost
    ? await getPrismaClient().post.update({
        where: { id: existingPost.id },
        data: { caption: input.caption ?? null, visibility: input.visibility },
        include: socialPostInclude,
      })
    : await getPrismaClient().post.create({
        data: { userId: user.id, activityId: activity.id, caption: input.caption ?? null, visibility: input.visibility },
        include: socialPostInclude,
      });
  return c.json(postPayload(post, user.id), existingPost ? 200 : 201);
});

router.put("/posts/:id/cheer", async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const post = await visiblePost(c.req.param("id"), user.id);
  if (!post) return c.json({ error: "Post not found." }, 404);
  const reaction = await getPrismaClient().reaction.upsert({ where: { userId_postId: { userId: user.id, postId: post.id } }, create: { userId: user.id, postId: post.id, type: "heart" }, update: { type: "heart" } });
  if (post.userId !== user.id) await createSocialNotification(post.userId, user.id, "cheer", post.id, `${user.displayName} cheered your activity.`);
  return c.json(reaction);
});

router.delete("/posts/:id/cheer", async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const post = await visiblePost(c.req.param("id"), user.id);
  if (!post) return c.json({ error: "Post not found." }, 404);
  await getPrismaClient().reaction.deleteMany({ where: { userId: user.id, postId: post.id } });
  return c.json({ ok: true });
});

router.post("/posts/:id/reactions", zValidator("json", reactionSchema), async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const post = await visiblePost(c.req.param("id"), user.id);
  if (!post) return c.json({ error: "Post not found." }, 404);
  const reaction = await getPrismaClient().reaction.upsert({ where: { userId_postId: { userId: user.id, postId: post.id } }, create: { userId: user.id, postId: post.id, type: c.req.valid("json").type }, update: { type: c.req.valid("json").type } });
  return c.json(reaction);
});

router.get("/posts/:id/comments", async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const post = await visiblePost(c.req.param("id"), user.id);
  if (!post) return c.json({ error: "Post not found." }, 404);
  const comments = await getPrismaClient().comment.findMany({
    where: { postId: post.id },
    include: { author: { select: socialPersonSelect } },
    orderBy: { createdAt: "asc" },
  });
  return c.json({ comments: comments.map((comment) => commentPayload(comment, user.id, post.userId)) });
});

router.post("/posts/:id/comments", zValidator("json", commentSchema), async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const post = await visiblePost(c.req.param("id"), user.id);
  if (!post) return c.json({ error: "Post not found." }, 404);
  const body = c.req.valid("json").body;
  if (!isAcceptableText(body)) return c.json({ error: "Please revise the comment before posting." }, 422);
  const comment = await getPrismaClient().comment.create({
    data: { postId: post.id, authorId: user.id, body },
    include: { author: { select: socialPersonSelect } },
  });
  if (post.userId !== user.id) await createSocialNotification(post.userId, user.id, "comment", post.id, `${user.displayName} commented on your activity.`);
  return c.json(commentPayload(comment, user.id, post.userId), 201);
});

router.delete("/comments/:id", async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const comment = await getPrismaClient().comment.findUnique({
    where: { id: c.req.param("id") },
    include: { post: { select: { userId: true } } },
  });
  if (!comment || (comment.authorId !== user.id && comment.post.userId !== user.id)) {
    return c.json({ error: "Comment not found." }, 404);
  }
  await getPrismaClient().comment.delete({ where: { id: comment.id } });
  return c.json({ ok: true });
});

router.delete("/posts/:id", async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const result = await getPrismaClient().post.deleteMany({
    where: { id: c.req.param("id"), userId: user.id },
  });
  if (!result.count) return c.json({ error: "Post not found." }, 404);
  return c.json({ ok: true });
});

async function requireSocialUser(c: Context<AppEnv>) {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication required." }, 401);
  return user;
}

async function acceptedConnectionIDs(userId: string) {
  const [connections, blocked] = await Promise.all([
    getPrismaClient().connection.findMany({ where: { status: "accepted", OR: [{ requesterId: userId }, { addresseeId: userId }] } }),
    blockedUserIDs(userId),
  ]);
  return connections
    .map((connection) => connection.requesterId === userId ? connection.addresseeId : connection.requesterId)
    .filter((id) => !blocked.includes(id));
}

async function blockedUserIDs(userId: string) {
  const blocks = await getPrismaClient().socialBlock.findMany({
    where: { OR: [{ blockerId: userId }, { blockedId: userId }] },
    select: { blockerId: true, blockedId: true },
  });
  return blocks.map((block) => block.blockerId === userId ? block.blockedId : block.blockerId);
}

async function createSocialNotification(recipientId: string, actorId: string, type: string, objectId: string, message: string) {
  await getPrismaClient().socialNotification.create({
    data: { recipientId, actorId, type, objectId, message },
  });
}

async function dismissSocialNotification(recipientId: string, type: string, objectId: string) {
  await getPrismaClient().socialNotification.deleteMany({
    where: { recipientId, type, objectId },
  });
}

const socialPersonSelect = {
  id: true,
  username: true,
  displayName: true,
  avatarUrl: true,
} as const;

const socialActivitySelect = {
  id: true,
  title: true,
  durationSecs: true,
  distanceM: true,
  avgPace: true,
  route: true,
} as const;

function connectionPayload(
  connection: {
    id: string;
    status: string;
    requesterId: string;
    requester: { id: string; username: string; displayName: string; avatarUrl: string | null };
    addressee: { id: string; username: string; displayName: string; avatarUrl: string | null };
  },
  userId: string,
) {
  const isOutgoing = connection.requesterId === userId;
  return {
    id: connection.id,
    status: connection.status,
    direction: isOutgoing ? "outgoing" : "incoming",
    person: isOutgoing ? connection.addressee : connection.requester,
  };
}

const socialPostInclude = {
  user: { select: socialPersonSelect },
  activity: { select: socialActivitySelect },
  reactions: { select: { id: true, userId: true, type: true } },
  comments: {
    include: { author: { select: socialPersonSelect } },
    orderBy: { createdAt: "asc" as const },
    take: 2,
  },
  _count: { select: { comments: true } },
} as const;

function postPayload(post: any, currentUserId: string) {
  return {
    id: post.id,
    caption: post.caption,
    createdAt: post.createdAt,
    visibility: post.visibility,
    isCurrentUser: post.userId === currentUserId,
    user: post.user,
    activity: post.activity,
    reactionCount: post.reactions.length,
    currentUserCheered: post.reactions.some((reaction: { userId: string }) => reaction.userId === currentUserId),
    commentCount: post._count.comments,
    comments: post.comments.map((comment: any) => commentPayload(comment, currentUserId, post.userId)),
  };
}

function commentPayload(comment: any, currentUserId: string, postOwnerId: string) {
  return {
    id: comment.id,
    body: comment.body,
    createdAt: comment.createdAt,
    author: comment.author,
    canDelete: comment.authorId === currentUserId || postOwnerId === currentUserId,
  };
}

async function visiblePost(postId: string, userId: string) {
  const connections = await acceptedConnectionIDs(userId);
  return getPrismaClient().post.findFirst({
    where: {
      id: postId,
      OR: [
        { userId },
        { userId: { in: connections }, visibility: { in: ["connections", "public"] } },
      ],
    },
    select: { id: true, userId: true },
  });
}

function shareSafeCompatibility(groups: Array<{ id: string; label: string; distanceMeters: number | null }>) {
  const selected = groups.find((group) => group.distanceMeters != null) ?? groups[0];
  return selected ? { groupId: selected.id, explanation: `${selected.label} is compatible with your available training range.` } : null;
}

function isAcceptableText(text: string) {
  const normalized = text.toLowerCase();
  return !["kill yourself", "racial slur", "sexual violence"].some((term) => normalized.includes(term));
}

function publicWebBaseURL() {
  return (process.env.PUBLIC_WEB_BASE_URL?.trim() || "https://run.plainstride.com").replace(/\/$/, "");
}

export default router;
