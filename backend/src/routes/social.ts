import { createHash, randomBytes } from "node:crypto";
import { Hono, type Context } from "hono";
import { Prisma } from "@prisma/client";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";
import { requireDatabase } from "../services/database.js";
import { getAuthenticatedAppUser } from "../services/currentUser.js";
import { getPrismaClient } from "../services/prisma.js";
import type { AppEnv } from "../types/hono.js";
import { deliverPushNotification } from "../services/pushNotifications.js";
import { signedActivityPhotoURL } from "../services/activityPhotoStorage.js";

const router = new Hono<AppEnv>();
const activityEventReconciliationWindowMs = 4 * 60 * 60 * 1000;
const socialFeedPageSize = 12;
const socialConnectionsPageSize = 20;
const socialPeopleSearchLimit = 20;
const reactionSchema = z.object({ type: z.enum(["fire", "clap", "heart", "strong"]) });
const commentSchema = z.object({ body: z.string().trim().min(1).max(500) });
const reportSchema = z.object({
  targetType: z.enum(["post", "comment", "user"]),
  targetId: z.string().min(1),
  reason: z.enum(["spam", "harassment", "hate", "sexual", "violence", "privacy", "other"]),
  details: z.string().trim().max(500).optional(),
});
const createActivityEventSchema = z.object({
  title: z.string().trim().min(1).max(80),
  startsAt: z.string().datetime(),
  durationMinutes: z.number().int().min(15).max(24 * 60).default(60),
  locationName: z.string().trim().max(120).nullable().optional(),
  note: z.string().trim().max(240).nullable().optional(),
});
const invitationBatchSchema = z.object({ recipientUserIds: z.array(z.string().min(1)).min(1).max(50) });
const linkActivityEventSchema = z.object({ activityId: z.string().min(1) });
const attendanceModeSchema = z.object({ attendanceMode: z.enum(["in_person", "virtual"]) });

router.get("/home", socialHome);
router.get("/together", socialHome);

async function socialHome(c: Context<AppEnv>) {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const prisma = getPrismaClient();
  const connections = await acceptedConnectionIDs(user.id);
  await refreshActivityEventStatuses();
  const unsharedActivities = await prisma.activity.findMany({
    where: { userId: user.id, deletedAt: null, posts: { none: {} } },
    select: { id: true, createdAt: true },
  });
  if (unsharedActivities.length > 0) {
    await prisma.post.createMany({
      data: unsharedActivities.map((activity) => ({
        userId: user.id,
        activityId: activity.id,
        visibility: "connections",
        createdAt: activity.createdAt,
      })),
      skipDuplicates: true,
    });
  }
  const visibility = [
    { creatorId: { in: [user.id, ...connections] }, visibility: "connections" },
    { participants: { some: { userId: user.id, status: "going" } } },
    { invitations: { some: { recipientId: user.id, status: "pending" } } },
    { club: { memberships: { some: { userId: user.id } } } },
  ];
  const feedCursorValue = c.req.query("feedCursor");
  const feedCursor = feedCursorValue ? decodeFeedCursor(feedCursorValue) : null;
  if (feedCursorValue && !feedCursor) return c.json({ error: "Invalid activity feed cursor." }, 400);
  const [upcomingRuns, pastEvents, memberships, posts] = await Promise.all([
    prisma.activityEvent.findMany({
      where: {
        status: { in: ["scheduled", "active"] },
        OR: visibility,
      },
      include: activityEventInclude(user.id),
      orderBy: { startsAt: "asc" },
      take: 5,
    }),
    prisma.activityEvent.findMany({
      where: {
        status: { in: ["reconciling", "completed"] },
        OR: visibility,
      },
      include: activityEventInclude(user.id),
      orderBy: { startsAt: "desc" },
      take: 10,
    }),
    prisma.clubMembership.findMany({ where: { userId: user.id }, include: { club: true } }),
    prisma.post.findMany({
      where: {
        userId: { in: [user.id, ...connections] },
        activityId: { not: null },
        visibility: { in: ["connections", "public"] },
        deletedAt: null,
        ...(feedCursor ? {
          OR: [
            { activity: { startedAt: { lt: feedCursor.createdAt } } },
            { activity: { startedAt: feedCursor.createdAt }, id: { lt: feedCursor.id } },
          ],
        } : {}),
      },
      include: {
        user: { select: socialPersonSelect },
        activity: { select: socialPostActivitySelect },
        reactions: { select: { id: true, userId: true, type: true } },
        comments: {
          include: { author: { select: socialPersonSelect } },
          orderBy: { createdAt: "asc" },
          take: 2,
        },
        _count: { select: { comments: true } },
      },
      orderBy: [{ activity: { startedAt: "desc" } }, { id: "desc" }],
      take: socialFeedPageSize + 1,
    }),
  ]);

  const feedPosts = posts.slice(0, socialFeedPageSize);
  const lastFeedPost = feedPosts.at(-1);
  const lastFeedTimestamp = lastFeedPost?.activity?.startedAt;
  const nextFeedCursor = posts.length > socialFeedPageSize && lastFeedPost
    && lastFeedTimestamp
    ? encodeFeedCursor(lastFeedTimestamp, lastFeedPost.id)
    : null;

  return c.json({
    upcomingRuns: upcomingRuns.map((activity) => activityEventPayload(activity, user.id, connections)),
    pastEvents: pastEvents.map((activity) => activityEventPayload(activity, user.id, connections)),
    clubs: memberships.map((membership) => ({ ...membership.club, role: membership.role })),
    posts: await Promise.all(feedPosts.map((post) => postPayload(post, user.id))),
    nextFeedCursor,
  });
}

function encodeFeedCursor(createdAt: Date, id: string) {
  return Buffer.from(JSON.stringify({ createdAt: createdAt.toISOString(), id }), "utf8").toString("base64url");
}

function decodeFeedCursor(value: string): { createdAt: Date; id: string } | null {
  try {
    const decoded = JSON.parse(Buffer.from(value, "base64url").toString("utf8")) as {
      createdAt?: unknown;
      id?: unknown;
    };
    if (typeof decoded.createdAt !== "string" || typeof decoded.id !== "string" || !decoded.id) return null;
    const createdAt = new Date(decoded.createdAt);
    return Number.isNaN(createdAt.getTime()) ? null : { createdAt, id: decoded.id };
  } catch {
    return null;
  }
}

router.get("/connections", async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const cursorValue = c.req.query("cursor");
  const cursor = cursorValue ? decodeFeedCursor(cursorValue) : null;
  if (cursorValue && !cursor) return c.json({ error: "Invalid connections cursor." }, 400);
  const connections = await getPrismaClient().connection.findMany({
    where: {
      AND: [
        { OR: [{ requesterId: user.id }, { addresseeId: user.id }] },
        ...(cursor ? [{
          OR: [
            { updatedAt: { lt: cursor.createdAt } },
            { updatedAt: cursor.createdAt, id: { lt: cursor.id } },
          ],
        }] : []),
      ],
    },
    include: {
      requester: { select: socialPersonSelect },
      addressee: { select: socialPersonSelect },
    },
    orderBy: [{ updatedAt: "desc" }, { id: "desc" }],
    take: socialConnectionsPageSize + 1,
  });
  const page = connections.slice(0, socialConnectionsPageSize);
  const lastConnection = page.at(-1);
  const nextCursor = connections.length > socialConnectionsPageSize && lastConnection
    ? encodeFeedCursor(lastConnection.updatedAt, lastConnection.id)
    : null;
  return c.json({
    connections: page.map((connection) => connectionPayload(connection, user.id)),
    nextCursor,
  });
});

router.get("/people/search", async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const query = c.req.query("q")?.trim().normalize("NFKC").slice(0, 50);
  if (!query) return c.json({ people: [], matchMode: "none" });
  const blocked = await blockedUserIDs(user.id);
  const excludedUserIDs = [user.id, ...blocked];
  let people: SocialPeopleSearchRow[];
  if (Array.from(query).length < 3) {
    people = await literalPeopleSearch(query, excludedUserIDs);
  } else {
    try {
      people = await fuzzyPeopleSearch(query, excludedUserIDs);
    } catch (error) {
      if (!isMissingTrigramExtension(error)) throw error;
      people = await literalPeopleSearch(query, excludedUserIDs);
    }
  }
  const relationships = await getPrismaClient().connection.findMany({
    where: {
      OR: [
        { requesterId: user.id, addresseeId: { in: people.map((person) => person.id) } },
        { addresseeId: user.id, requesterId: { in: people.map((person) => person.id) } },
      ],
    },
  });
  const matchKinds = new Set(people.map((person) => person.matchKind));
  const matchMode = matchKinds.size === 0
    ? "none"
    : matchKinds.size === 1
      ? people[0].matchKind
      : "mixed";
  return c.json({
    people: people.map((person) => {
      const relationship = relationships.find((candidate) =>
        candidate.requesterId === person.id || candidate.addresseeId === person.id
      );
      return {
        id: person.id,
        username: person.username,
        displayName: person.displayName,
        avatarUrl: person.avatarUrl,
        relationship: relationship
          ? {
              id: relationship.id,
              status: relationship.status,
              direction: relationship.requesterId === user.id ? "outgoing" : "incoming",
            }
          : null,
      };
    }),
    matchMode,
  });
});

type SocialPeopleSearchRow = {
  id: string;
  username: string;
  displayName: string;
  avatarUrl: string | null;
  matchKind: "literal" | "fuzzy";
};

async function literalPeopleSearch(query: string, excludedUserIDs: string[]): Promise<SocialPeopleSearchRow[]> {
  const people = await getPrismaClient().user.findMany({
    where: {
      id: { notIn: excludedUserIDs },
      OR: [
        { displayName: { contains: query, mode: "insensitive" } },
        { username: { contains: query, mode: "insensitive" } },
      ],
    },
    select: socialPersonSelect,
    orderBy: [{ displayName: "asc" }, { username: "asc" }],
    take: socialPeopleSearchLimit,
  });
  return people.map((person) => ({ ...person, matchKind: "literal" }));
}

async function fuzzyPeopleSearch(query: string, excludedUserIDs: string[]): Promise<SocialPeopleSearchRow[]> {
  return getPrismaClient().$transaction(async (transaction) => {
    await transaction.$executeRaw`SET LOCAL pg_trgm.similarity_threshold = 0.35`;
    await transaction.$executeRaw`SET LOCAL pg_trgm.strict_word_similarity_threshold = 0.35`;
    return transaction.$queryRaw<SocialPeopleSearchRow[]>(Prisma.sql`
      SELECT
        candidate.id,
        candidate.username,
        candidate."displayName",
        candidate."avatarUrl",
        CASE
          WHEN strpos(lower(candidate."displayName"), lower(${query})) > 0
            OR strpos(lower(candidate.username), lower(${query})) > 0
          THEN 'literal'
          ELSE 'fuzzy'
        END AS "matchKind"
      FROM "User" AS candidate
      WHERE candidate.id NOT IN (${Prisma.join(excludedUserIDs)})
        AND (
          strpos(lower(candidate."displayName"), lower(${query})) > 0
          OR strpos(lower(candidate.username), lower(${query})) > 0
          OR ${query} <<% candidate."displayName"
          OR candidate.username % ${query}
        )
      ORDER BY
        CASE
          WHEN lower(candidate.username) = lower(${query}) THEN 0
          WHEN lower(candidate."displayName") = lower(${query}) THEN 1
          WHEN strpos(lower(candidate.username), lower(${query})) = 1 THEN 2
          WHEN strpos(lower(candidate."displayName"), lower(${query})) = 1
            OR strpos(lower(candidate."displayName"), ' ' || lower(${query})) > 0 THEN 3
          WHEN strpos(lower(candidate.username), lower(${query})) > 0
            OR strpos(lower(candidate."displayName"), lower(${query})) > 0 THEN 4
          ELSE 5
        END,
        GREATEST(
          similarity(candidate.username, ${query}),
          strict_word_similarity(${query}, candidate."displayName")
        ) DESC,
        candidate."displayName" ASC,
        candidate.username ASC
      LIMIT ${socialPeopleSearchLimit}
    `);
  });
}

function isMissingTrigramExtension(error: unknown): boolean {
  return error instanceof Prisma.PrismaClientKnownRequestError
    && error.code === "P2010"
    && error.meta?.code === "42883";
}

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

router.post("/activity-events", zValidator("json", createActivityEventSchema), async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const input = c.req.valid("json");
  const startsAt = new Date(input.startsAt);
  if (startsAt <= new Date()) return c.json({ error: "Choose a future date and time." }, 422);
  const activity = await getPrismaClient().$transaction(async (prisma) => {
    const created = await prisma.activityEvent.create({
      data: {
        creatorId: user.id,
        title: input.title,
        startsAt,
        endsAt: new Date(startsAt.getTime() + input.durationMinutes * 60 * 1000),
        locationName: input.locationName || null,
        note: input.note || null,
        participationMode: "hybrid",
        activityPolicy: "fixed",
        activityType: "running",
        visibility: "connections",
      },
    });
    await prisma.activityEventParticipant.create({
      data: { activityEventId: created.id, userId: user.id, status: "going" },
    });
    return prisma.activityEvent.findUniqueOrThrow({ where: { id: created.id }, include: activityEventInclude(user.id) });
  });
  return c.json(activityEventPayload(activity, user.id, []), 201);
});

router.get("/activity-events/:id", async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const connections = await acceptedConnectionIDs(user.id);
  const activity = await visibleActivityEvent(user.id, connections, c.req.param("id"));
  if (!activity) return c.json({ error: "Activity event not found." }, 404);
  await refreshActivityEventStatus(activity);
  return c.json(activityEventPayload(activity, user.id, connections, true));
});

router.post("/activity-events/:id/rsvp", zValidator("json", attendanceModeSchema), async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const connections = await acceptedConnectionIDs(user.id);
  const activity = await visibleActivityEvent(user.id, connections, c.req.param("id"));
  if (!activity || activity.status !== "scheduled") return c.json({ error: "Activity event not found." }, 404);
  const participant = await getPrismaClient().activityEventParticipant.upsert({
    where: { activityEventId_userId: { activityEventId: activity.id, userId: user.id } },
    create: { activityEventId: activity.id, userId: user.id, status: "going", attendanceMode: c.req.valid("json").attendanceMode },
    update: { status: "going", attendanceMode: c.req.valid("json").attendanceMode, outcome: null, resolvedAt: null },
  });
  if (activity.creatorId !== user.id) {
    await createSocialNotification(activity.creatorId, user.id, "activityEventJoined", activity.id, `${user.displayName} joined ${activity.title}.`);
  }
  return c.json(participant);
});

router.delete("/activity-events/:id/rsvp", async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const activity = await getPrismaClient().activityEvent.findUnique({ where: { id: c.req.param("id") } });
  if (!activity || activity.creatorId === user.id) return c.json({ error: "The creator cannot leave this activity." }, 422);
  await getPrismaClient().activityEventParticipant.updateMany({
    where: { activityEventId: activity.id, userId: user.id },
    data: { status: "left", outcome: null, recordedActivityId: null, resolvedAt: new Date() },
  });
  return c.json({ ok: true });
});

router.post("/activity-events/:id/invitations", zValidator("json", z.object({ recipientUserId: z.string().optional() })), async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const activity = await getPrismaClient().activityEvent.findFirst({ where: { id: c.req.param("id"), creatorId: user.id, status: "scheduled" } });
  if (!activity) return c.json({ error: "Activity event not found." }, 404);
  const token = randomBytes(24).toString("base64url");
  const recipientId = c.req.valid("json").recipientUserId;
  if (recipientId && !(await acceptedConnectionIDs(user.id)).includes(recipientId)) return c.json({ error: "Connect with this person before inviting them." }, 403);
  const invitation = await getPrismaClient().invitation.create({ data: { senderId: user.id, recipientId, activityEventId: activity.id, kind: "activityEvent", tokenHash: createHash("sha256").update(token).digest("hex"), expiresAt: new Date(Date.now() + 7 * 86400000) } });
  if (recipientId) await createSocialNotification(recipientId, user.id, "runInvitation", invitation.id, `${user.displayName} invited you to ${activity.title}.`);
  return c.json({ id: invitation.id, token, status: invitation.status }, 201);
});

router.post("/activity-events/:id/invitations/batch", zValidator("json", invitationBatchSchema), async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const activity = await getPrismaClient().activityEvent.findFirst({ where: { id: c.req.param("id"), creatorId: user.id, status: "scheduled" } });
  if (!activity) return c.json({ error: "Activity event not found." }, 404);
  const connectionIds = new Set(await acceptedConnectionIDs(user.id));
  const recipientIds = [...new Set(c.req.valid("json").recipientUserIds)].filter((id) => connectionIds.has(id));
  const invitations = [];
  for (const recipientId of recipientIds) {
    const existing = await getPrismaClient().invitation.findFirst({ where: { activityEventId: activity.id, recipientId, status: "pending" } });
    if (existing) { invitations.push({ id: existing.id, recipientUserId: recipientId, status: "alreadyInvited" }); continue; }
    const created = await getPrismaClient().invitation.create({ data: { senderId: user.id, recipientId, activityEventId: activity.id, kind: "activityEvent", expiresAt: new Date(Date.now() + 7 * 86400000) } });
    await createSocialNotification(recipientId, user.id, "runInvitation", created.id, `${user.displayName} invited you to ${activity.title}.`);
    invitations.push({ id: created.id, recipientUserId: recipientId, status: "sent" });
  }
  return c.json({ invitations }, 201);
});

router.delete("/activity-events/:activityEventId/invitations/:invitationId", async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const invitation = await getPrismaClient().invitation.findFirst({
    where: {
      id: c.req.param("invitationId"),
      activityEventId: c.req.param("activityEventId"),
      senderId: user.id,
      status: "pending",
      activityEvent: { creatorId: user.id, status: "scheduled" },
    },
  });
  if (!invitation) return c.json({ error: "Invitation not found." }, 404);
  await getPrismaClient().$transaction([
    getPrismaClient().socialNotification.deleteMany({
      where: { recipientId: invitation.recipientId ?? undefined, type: "runInvitation", objectId: invitation.id },
    }),
    getPrismaClient().invitation.delete({ where: { id: invitation.id } }),
  ]);
  return c.json({ ok: true });
});

router.post("/invitations/:id/accept", zValidator("json", attendanceModeSchema), async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const invitation = await getPrismaClient().invitation.findFirst({
    where: { id: c.req.param("id"), recipientId: user.id, status: "pending" },
  });
  if (!invitation || !invitation.activityEventId) return c.json({ error: "Invitation not found." }, 404);
  await getPrismaClient().$transaction([
    getPrismaClient().invitation.update({ where: { id: invitation.id }, data: { status: "accepted" } }),
    getPrismaClient().activityEventParticipant.upsert({
      where: { activityEventId_userId: { activityEventId: invitation.activityEventId, userId: user.id } },
      create: { activityEventId: invitation.activityEventId, userId: user.id, status: "going", attendanceMode: c.req.valid("json").attendanceMode },
      update: { status: "going", attendanceMode: c.req.valid("json").attendanceMode },
    }),
  ]);
  await dismissSocialNotification(user.id, "runInvitation", invitation.id);
  await createSocialNotification(invitation.senderId, user.id, "invitationAccepted", invitation.activityEventId, `${user.displayName} accepted your activity invitation.`);
  return c.json({ ok: true });
});

router.post("/invitations/token/:token/accept", async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const tokenHash = createHash("sha256").update(c.req.param("token")).digest("hex");
  const invitation = await getPrismaClient().invitation.findFirst({
    where: { tokenHash, status: "pending", expiresAt: { gt: new Date() } },
    include: { activityEvent: true },
  });
  if (!invitation?.activityEvent || (invitation.recipientId && invitation.recipientId !== user.id)) {
    return c.json({ error: "Invitation not found." }, 404);
  }
  await getPrismaClient().$transaction([
    getPrismaClient().invitation.update({ where: { id: invitation.id }, data: { status: "accepted", recipientId: user.id } }),
    getPrismaClient().activityEventParticipant.upsert({
      where: { activityEventId_userId: { activityEventId: invitation.activityEvent.id, userId: user.id } },
      create: { activityEventId: invitation.activityEvent.id, userId: user.id, status: "going" },
      update: { status: "going", outcome: null, resolvedAt: null },
    }),
  ]);
  if (invitation.senderId !== user.id) {
    await createSocialNotification(invitation.senderId, user.id, "activityEventJoined", invitation.activityEvent.id, `${user.displayName} joined ${invitation.activityEvent.title}.`);
  }
  return c.json({ ok: true, activityEventId: invitation.activityEvent.id });
});

router.post("/activity-events/:id/link-activity", zValidator("json", linkActivityEventSchema), async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const recorded = await linkRecordedActivity(user.id, c.req.param("id"), c.req.valid("json").activityId);
  if (!recorded) return c.json({ error: "Activity or participation not found." }, 404);
  return c.json({ ok: true });
});

router.post("/activity-events/:id/no-recording", async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const result = await getPrismaClient().activityEventParticipant.updateMany({
    where: { activityEventId: c.req.param("id"), userId: user.id, status: "going" },
    data: { outcome: "no_recording", recordedActivityId: null, resolvedAt: new Date() },
  });
  if (!result.count) return c.json({ error: "Participation not found." }, 404);
  const activity = await getPrismaClient().activityEvent.findUnique({
    where: { id: c.req.param("id") },
    include: { participants: true },
  });
  if (activity) await refreshActivityEventStatus(activity);
  return c.json({ ok: true });
});

router.get("/activity-events/:id/results", async (c) => {
  const user = await requireSocialUser(c);
  if (user instanceof Response) return user;
  const connections = await acceptedConnectionIDs(user.id);
  const activity = await visibleActivityEvent(user.id, connections, c.req.param("id"));
  if (!activity) return c.json({ error: "Activity event not found." }, 404);
  const status = await refreshActivityEventStatus(activity);
  return c.json(activityEventResultsPayload(activity, user.id, connections, status));
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
  return c.json(await postPayload(post, user.id), existingPost ? 200 : 201);
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
  const result = await getPrismaClient().post.updateMany({
    where: { id: c.req.param("id"), userId: user.id, deletedAt: null },
    data: { deletedAt: new Date() },
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
  const notification = await getPrismaClient().socialNotification.create({
    data: { recipientId, actorId, type, objectId, message },
  });
  void deliverPushNotification(notification).catch((error) => {
    console.error("[push] notification delivery failed", { notificationId: notification.id, error });
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
  startedAt: true,
  endedAt: true,
  durationSecs: true,
  distanceM: true,
  avgPace: true,
  route: true,
} as const;

const socialPostActivitySelect = {
  ...socialActivitySelect,
  photos: {
    select: {
      id: true,
      clientPhotoId: true,
      storageKey: true,
      takenAt: true,
      paceAtShot: true,
      hrAtShot: true,
      distAtShot: true,
      lat: true,
      lng: true,
      captureContext: true,
    },
    orderBy: { takenAt: "asc" as const },
  },
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
  activity: { select: socialPostActivitySelect },
  reactions: { select: { id: true, userId: true, type: true } },
  comments: {
    include: { author: { select: socialPersonSelect } },
    orderBy: { createdAt: "asc" as const },
    take: 2,
  },
  _count: { select: { comments: true } },
} as const;

async function postPayload(post: any, currentUserId: string) {
  const activity = post.activity
    ? {
        ...post.activity,
        photos: await Promise.all(post.activity.photos.map(async (photo: any) => ({
          id: photo.id,
          clientPhotoId: photo.clientPhotoId,
          url: await signedActivityPhotoURL(photo.storageKey),
          takenAt: photo.takenAt,
          paceAtShot: photo.paceAtShot,
          hrAtShot: photo.hrAtShot,
          distAtShot: photo.distAtShot,
          latitude: photo.lat,
          longitude: photo.lng,
          captureContext: photo.captureContext,
        }))),
      }
    : null;
  return {
    id: post.id,
    caption: post.caption,
    createdAt: post.createdAt,
    visibility: post.visibility,
    isCurrentUser: post.userId === currentUserId,
    user: post.user,
    activity,
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

function activityEventInclude(_currentUserId: string) {
  return {
    club: true,
    creator: { select: socialPersonSelect },
    options: { orderBy: { sortOrder: "asc" as const } },
    participants: {
      include: {
        user: { select: socialPersonSelect },
        recordedActivity: { select: socialActivitySelect },
      },
      orderBy: { joinedAt: "asc" as const },
    },
    invitations: {
      include: {
        sender: { select: socialPersonSelect },
        recipient: { select: socialPersonSelect },
      },
      orderBy: { createdAt: "desc" as const },
    },
  } as const;
}

async function visibleActivityEvent(userId: string, connectionIds: string[], id: string) {
  return getPrismaClient().activityEvent.findFirst({
    where: {
      id,
      OR: [
        { creatorId: userId },
        { creatorId: { in: connectionIds }, visibility: "connections" },
        { participants: { some: { userId } } },
        { invitations: { some: { recipientId: userId, status: { in: ["pending", "accepted"] } } } },
        { club: { memberships: { some: { userId } } } },
      ],
    },
    include: activityEventInclude(userId),
  });
}

function activityEventPayload(activity: any, currentUserId: string, connectionIds: string[], includeParticipants = false) {
  const going = activity.participants.filter((participant: any) => participant.status === "going");
  const currentParticipant = activity.participants.find((participant: any) => participant.userId === currentUserId);
  const directInvitation = activity.invitations.find((invitation: any) => invitation.recipientId === currentUserId && invitation.status === "pending");
  const source = activity.creatorId === currentUserId
    ? { kind: "createdByYou", label: "Created by you" }
    : currentParticipant?.status === "going"
      ? { kind: "joined", label: `Joined · From ${activity.creator.displayName}` }
      : directInvitation
        ? { kind: "directInvitation", label: `From ${directInvitation.sender.displayName} · Direct invitation` }
        : activity.club
          ? { kind: "group", label: `From ${activity.club.name} · Your group` }
          : connectionIds.includes(activity.creatorId)
            ? { kind: "connection", label: `From ${activity.creator.displayName} · Your connection` }
            : { kind: "invitation", label: `From ${activity.creator.displayName}` };
  const payload: Record<string, unknown> = {
    id: activity.id,
    title: activity.title,
    startsAt: activity.startsAt,
    endsAt: activity.endsAt,
    locationName: activity.locationName,
    paceNote: activity.note,
    note: activity.note,
    participationMode: activity.participationMode,
    activityPolicy: activity.activityPolicy,
    activityType: activity.activityType,
    visibility: activity.visibility,
    status: activity.status,
    club: activity.club,
    creator: activity.creator,
    groups: activity.options,
    options: activity.options,
    source,
    attendeeCount: going.length,
    attendeePreview: going.slice(0, 3).map((participant: any) => participant.user),
    currentUserGoing: currentParticipant?.status === "going",
    currentUserOutcome: currentParticipant?.outcome ?? null,
    currentUserAttendanceMode: currentParticipant?.attendanceMode ?? null,
    currentUserRole: activity.creatorId === currentUserId ? "owner" : currentParticipant?.status === "going" ? "participant" : "viewer",
    compatibility: shareSafeCompatibility(activity.options),
  };
  if (includeParticipants) {
    payload.participants = going.map((participant: any) => ({ person: participant.user, status: participant.status, outcome: participant.outcome, attendanceMode: participant.attendanceMode }));
    if (activity.creatorId === currentUserId) {
      payload.invitedUserIds = activity.invitations
        .filter((invitation: any) => invitation.recipientId && ["pending", "accepted"].includes(invitation.status))
        .map((invitation: any) => invitation.recipientId);
      payload.pendingInvitations = activity.invitations
        .filter((invitation: any) => invitation.status === "pending" && invitation.recipient)
        .map((invitation: any) => ({ id: invitation.id, recipient: invitation.recipient, createdAt: invitation.createdAt }));
    }
  }
  return payload;
}

function activityEventResultsPayload(activity: any, currentUserId: string, connectionIds: string[], status = activity.status) {
  const participants = activity.participants.filter((participant: any) => participant.status === "going");
  const canSeeDetails = (participant: any) => participant.userId === currentUserId || connectionIds.includes(participant.userId);
  const visibleRecorded = participants.filter((participant: any) => participant.recordedActivity && canSeeDetails(participant));
  const resolvedCount = participants.filter((participant: any) => participant.outcome).length;
  return {
    activityEventId: activity.id,
    status,
    goingCount: participants.length,
    resolvedCount,
    combinedDistanceMeters: visibleRecorded.reduce((sum: number, participant: any) => sum + (participant.recordedActivity.distanceM ?? 0), 0),
    combinedDurationSeconds: visibleRecorded.reduce((sum: number, participant: any) => sum + (participant.recordedActivity.durationSecs ?? 0), 0),
    participants: participants.map((participant: any) => ({
      person: participant.user,
      outcome: participant.outcome,
      result: participant.recordedActivity && canSeeDetails(participant) ? participant.recordedActivity : null,
    })),
  };
}

async function refreshActivityEventStatuses() {
  const prisma = getPrismaClient();
  const now = new Date();
  const graceCutoff = new Date(now.getTime() - activityEventReconciliationWindowMs);
  await prisma.$transaction([
    prisma.activityEvent.updateMany({
      where: { status: "scheduled", startsAt: { lte: now }, endsAt: { gt: now } },
      data: { status: "active" },
    }),
    prisma.activityEvent.updateMany({
      where: { status: { in: ["scheduled", "active"] }, endsAt: { lte: now, gt: graceCutoff } },
      data: { status: "reconciling" },
    }),
    prisma.activityEvent.updateMany({
      where: { status: { in: ["scheduled", "active", "reconciling"] }, endsAt: { lte: graceCutoff } },
      data: { status: "completed" },
    }),
  ]);
}

async function refreshActivityEventStatus(activity: any) {
  if (["completed", "cancelled"].includes(activity.status)) return activity.status;
  const now = Date.now();
  const startsAt = new Date(activity.startsAt).getTime();
  const endsAt = new Date(activity.endsAt).getTime();
  const going = activity.participants.filter((participant: any) => participant.status === "going");
  const allResolved = going.length > 0 && going.every((participant: any) => participant.outcome);
  const nextStatus = allResolved || now >= endsAt + activityEventReconciliationWindowMs
    ? "completed"
    : now >= endsAt
      ? "reconciling"
      : now >= startsAt
        ? "active"
        : "scheduled";
  if (nextStatus !== activity.status) {
    await getPrismaClient().activityEvent.update({ where: { id: activity.id }, data: { status: nextStatus } });
    activity.status = nextStatus;
  }
  return nextStatus;
}

async function linkRecordedActivity(userId: string, activityEventId: string, activityId: string) {
  const recordedActivity = await getPrismaClient().activity.findFirst({
    where: { userId, deletedAt: null, OR: [{ id: activityId }, { clientActivityId: activityId }] },
    select: { id: true },
  });
  if (!recordedActivity) return null;
  const result = await getPrismaClient().activityEventParticipant.updateMany({
    where: { activityEventId, userId, status: "going" },
    data: { recordedActivityId: recordedActivity.id, outcome: "completed", resolvedAt: new Date() },
  });
  return result.count ? recordedActivity : null;
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
