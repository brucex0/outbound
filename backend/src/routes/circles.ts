import { Hono } from "hono";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";
import type { Context } from "hono";
import { Prisma } from "@prisma/client";
import type { AppEnv } from "../types/hono.js";
import { requireDatabase } from "../services/database.js";
import { getAuthenticatedAppUser } from "../services/currentUser.js";
import { getPrismaClient } from "../services/prisma.js";
import {
  assertAcceptedConnection,
  assertCircleMember,
  assertNoBlockedCircleMember,
  circlePayload,
  circleWeekInterval,
  createCircle,
  CircleDomainError,
  CIRCLE_CAPACITY,
  ensureCurrentWeek,
  refreshWeekState,
  reconcileActivityToCircles,
  transferCircleOwnership,
  validTimeZone,
} from "../services/circles.js";

const router = new Hono<AppEnv>();
const focusMode = z.enum(["personal_targets", "shared_target", "none"]);
const presetType = z.enum(["encouragement", "celebration", "support"]);
const createSchema = z.object({
  name: z.string().trim().max(80).optional(),
  memberUserIds: z.array(z.string().min(1)).max(CIRCLE_CAPACITY - 1).default([]),
  timeZone: z.string().trim().max(100).optional(),
  resetWeekday: z.number().int().min(1).max(7).optional(),
});
const focusSchema = z.object({
  mode: focusMode,
  sharedTarget: z.number().int().min(1).max(100).nullable().optional(),
  apply: z.enum(["now", "next_week"]).default("now"),
});
const commitmentSchema = z.object({ targetCount: z.number().int().min(1).max(100).nullable().optional(), skipped: z.boolean().default(false) });
const inviteSchema = z.object({ recipientUserIds: z.array(z.string().min(1)).min(1).max(CIRCLE_CAPACITY - 1), idempotencyKey: z.string().min(1).max(128).optional() });
const renameSchema = z.object({ name: z.string().trim().min(1).max(80) });
const calendarSchema = z.object({ resetWeekday: z.number().int().min(1).max(7), timeZone: z.string().trim().max(100), apply: z.enum(["now", "next_week"]).default("next_week") });
const transferSchema = z.object({ recipientUserId: z.string().min(1) });

router.get("/", async (c) => {
  const user = await requireCircleUser(c);
  if (user instanceof Response) return user;
  const prisma = getPrismaClient();
  const memberships = await prisma.circleMember.findMany({ where: { userId: user.id, status: "active" }, select: { circleId: true, circle: { select: { lifecycle: true } } }, orderBy: { updatedAt: "desc" } });
  const circles = await Promise.all(memberships.map(async (membership) => {
    try {
      await assertCircleMember(membership.circleId, user.id);
      return await circlePayload(membership.circleId, user.id);
    } catch {
      return null;
    }
  }));
  const visibleCircles = circles.filter((circle): circle is NonNullable<typeof circle> => circle != null);
  const storedPrimary = (await prisma.user.findUnique({ where: { id: user.id }, select: { primaryCircleId: true } }))?.primaryCircleId ?? null;
  const primaryIsValid = visibleCircles.some((circle) => circle.id === storedPrimary && circle.eligibleForToday);
  const primaryCircleId = primaryIsValid ? storedPrimary : (visibleCircles.find((circle) => circle.eligibleForToday)?.id ?? null);
  if (storedPrimary !== primaryCircleId) await prisma.user.update({ where: { id: user.id }, data: { primaryCircleId } });
  return c.json({ circles: visibleCircles, primaryCircleId });
});

router.post("/", zValidator("json", createSchema), async (c) => {
  const user = await requireCircleUser(c);
  if (user instanceof Response) return user;
  try {
    const circleId = await createCircle(user.id, { ...c.req.valid("json"), locale: c.get("locale") });
    const circle = await circlePayload(circleId, user.id);
    const created = await getPrismaClient().circle.findUniqueOrThrow({ where: { id: circleId }, include: { invitations: { where: { status: "pending" }, select: { id: true, recipientId: true } } } });
    for (const invitation of created.invitations) await notify(invitation.recipientId, user.id, "circleInvitation", invitation.id, `${user.displayName} invited you to ${created.name}.`, circleId, false);
    return c.json(circle, 201);
  } catch (error) {
    return circleError(c, error);
  }
});

router.get("/:id", async (c) => {
  const user = await requireCircleUser(c);
  if (user instanceof Response) return user;
  try {
    await assertCircleMember(c.req.param("id"), user.id);
    const payload = await circlePayload(c.req.param("id"), user.id, true);
    return payload ? c.json(payload) : c.json({ error: "Circle not found." }, 404);
  } catch (error) {
    return circleError(c, error);
  }
});

router.patch("/:id", zValidator("json", renameSchema), async (c) => {
  const user = await requireCircleUser(c);
  if (user instanceof Response) return user;
  await assertCircleMember(c.req.param("id"), user.id);
  const circle = await getPrismaClient().circle.findFirst({ where: { id: c.req.param("id"), ownerId: user.id, lifecycle: { not: "archived" } } });
  if (!circle) return c.json({ error: "Circle not found." }, 404);
  await getPrismaClient().circle.update({ where: { id: circle.id }, data: { name: c.req.valid("json").name } });
  return c.json(await circlePayload(circle.id, user.id, true));
});

router.post("/:id/invitations", zValidator("json", inviteSchema), async (c) => {
  const user = await requireCircleUser(c);
  if (user instanceof Response) return user;
  const prisma = getPrismaClient();
  await assertCircleMember(c.req.param("id"), user.id);
  const now = new Date();
  await prisma.circleInvitation.updateMany({ where: { circleId: c.req.param("id"), status: "pending", expiresAt: { lte: now } }, data: { status: "expired" } });
  const circle = await prisma.circle.findFirst({ where: { id: c.req.param("id"), ownerId: user.id, lifecycle: { not: "archived" } }, include: { members: { where: { status: "active" } }, invitations: { where: { status: "pending" } } } });
  if (!circle) return c.json({ error: "Circle not found." }, 404);
  const ids = [...new Set(c.req.valid("json").recipientUserIds.filter((id) => id !== user.id))];
  const newRecipientIDs = ids.filter((id) => !circle.members.some((member) => member.userId === id) && !circle.invitations.some((invitation) => invitation.recipientId === id));
  if (circle.members.length + circle.invitations.length + newRecipientIDs.length > CIRCLE_CAPACITY) return c.json({ error: "Those invitations would exceed Circle capacity." }, 409);
  const results = [];
  for (const recipientId of ids) {
    try { await assertAcceptedConnection(user.id, recipientId); } catch (error) { results.push({ recipientUserId: recipientId, status: error instanceof CircleDomainError ? error.code : "rejected" }); continue; }
    const existingMember = circle.members.some((member) => member.userId === recipientId);
    const existing = circle.invitations.find((invitation) => invitation.recipientId === recipientId);
    if (existingMember) { results.push({ recipientUserId: recipientId, status: "already_member" }); continue; }
    if (existing) { results.push({ recipientUserId: recipientId, status: "already_pending", id: existing.id }); continue; }
    const prior = await prisma.circleInvitation.findUnique({ where: { circleId_recipientId: { circleId: circle.id, recipientId } } });
    const invitation = prior
      ? await prisma.circleInvitation.update({ where: { id: prior.id }, data: { senderId: user.id, status: "pending", idempotencyKey: c.req.valid("json").idempotencyKey ? `${c.req.valid("json").idempotencyKey}:${recipientId}` : crypto.randomUUID(), expiresAt: new Date(Date.now() + 7 * 86400000), acceptedAt: null, declinedAt: null, cancelledAt: null } })
      : await prisma.circleInvitation.create({ data: { circleId: circle.id, senderId: user.id, recipientId, idempotencyKey: c.req.valid("json").idempotencyKey ? `${c.req.valid("json").idempotencyKey}:${recipientId}` : crypto.randomUUID(), expiresAt: new Date(Date.now() + 7 * 86400000) } });
    await notify(recipientId, user.id, "circleInvitation", invitation.id, `${user.displayName} invited you to ${circle.name}.`, circle.id, false);
    results.push({ recipientUserId: recipientId, status: "sent", id: invitation.id });
  }
  return c.json({ invitations: results, circle: await circlePayload(circle.id, user.id, true) }, 201);
});

router.get("/invitations/inbox", async (c) => {
  const user = await requireCircleUser(c);
  if (user instanceof Response) return user;
  const prisma = getPrismaClient();
  const now = new Date();
  await prisma.circleInvitation.updateMany({ where: { recipientId: user.id, status: "pending", expiresAt: { lte: now } }, data: { status: "expired" } });
  const candidates = await prisma.circleInvitation.findMany({ where: { recipientId: user.id, status: "pending", OR: [{ expiresAt: null }, { expiresAt: { gt: now } }] }, include: { circle: { select: { id: true, name: true } }, sender: { select: { id: true, displayName: true, avatarUrl: true } } }, orderBy: { createdAt: "desc" } });
  const invitations = [];
  for (const invitation of candidates) {
    try {
      await assertAcceptedConnection(invitation.senderId, user.id);
      await assertNoBlockedCircleMember(invitation.circleId, user.id);
      invitations.push(invitation);
    } catch { /* Blocked and disconnected invitations are intentionally hidden. */ }
  }
  return c.json({ invitations });
});

router.post("/invitations/:invitationId/accept", async (c) => {
  const user = await requireCircleUser(c);
  if (user instanceof Response) return user;
  const prisma = getPrismaClient();
  try {
    const invitation = await prisma.circleInvitation.findFirst({ where: { id: c.req.param("invitationId"), recipientId: user.id }, include: { circle: { include: { members: { where: { status: "active" } } } } } });
    if (!invitation) return c.json({ error: "Circle invitation not found." }, 404);
    if (invitation.status === "accepted") {
      await assertCircleMember(invitation.circleId, user.id);
      await prisma.socialNotification.deleteMany({ where: { recipientId: user.id, type: "circleInvitation", objectId: invitation.id } });
      return c.json(await circlePayload(invitation.circleId, user.id, true));
    }
    if (invitation.status !== "pending") return c.json({ error: "This Circle invitation is no longer active." }, 409);
    await assertAcceptedConnection(invitation.senderId, user.id);
    if (invitation.expiresAt && invitation.expiresAt <= new Date()) {
      await prisma.circleInvitation.update({ where: { id: invitation.id }, data: { status: "expired" } });
      return c.json({ error: "This Circle invitation has expired." }, 410);
    }
    await assertNoBlockedCircleMember(invitation.circleId, user.id);
    const result = await prisma.$transaction(async (tx) => {
      const activeCount = await tx.circleMember.count({ where: { circleId: invitation.circleId, status: "active" } });
      if (activeCount >= CIRCLE_CAPACITY) throw new CircleDomainError("capacity", "This Circle is full.");
      await tx.circleInvitation.updateMany({ where: { id: invitation.id, status: "pending" }, data: { status: "accepted", acceptedAt: new Date() } });
      await tx.circleMember.upsert({ where: { circleId_userId: { circleId: invitation.circleId, userId: user.id } }, create: { circleId: invitation.circleId, userId: user.id, role: "member", status: "active", displayNameSnapshot: user.displayName, avatarUrlSnapshot: user.avatarUrl }, update: { status: "active", role: "member", joinedAt: new Date(), displayNameSnapshot: user.displayName, avatarUrlSnapshot: user.avatarUrl } });
      const count = await tx.circleMember.count({ where: { circleId: invitation.circleId, status: "active" } });
      await tx.circle.update({ where: { id: invitation.circleId }, data: { lifecycle: count >= 2 ? "active" : "awaiting_members" } });
      return tx.circle.findUniqueOrThrow({ where: { id: invitation.circleId }, select: { name: true, ownerId: true } });
    }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable });
    await prisma.socialNotification.deleteMany({ where: { recipientId: user.id, type: "circleInvitation", objectId: invitation.id } });
    await notify(result.ownerId, user.id, "circleInvitationAccepted", invitation.circleId, `${user.displayName} joined ${invitation.circle.name}.`, invitation.circleId, false);
    return c.json(await circlePayload(invitation.circleId, user.id, true));
  } catch (error) { return circleError(c, error); }
});

router.post("/invitations/:invitationId/decline", async (c) => {
  const user = await requireCircleUser(c);
  if (user instanceof Response) return user;
  const prisma = getPrismaClient();
  const invitation = await prisma.circleInvitation.findFirst({ where: { id: c.req.param("invitationId"), recipientId: user.id, status: "pending" }, select: { id: true, circleId: true, senderId: true } });
  if (invitation) {
    await assertAcceptedConnection(invitation.senderId, user.id);
    await assertNoBlockedCircleMember(invitation.circleId, user.id);
    await prisma.circleInvitation.updateMany({ where: { id: invitation.id, status: "pending" }, data: { status: "declined", declinedAt: new Date() } });
  }
  await prisma.socialNotification.deleteMany({ where: { recipientId: user.id, type: "circleInvitation", objectId: c.req.param("invitationId") } });
  return c.json({ status: "declined" });
});

router.post("/:id/invitations/:invitationId/cancel", async (c) => {
  const user = await requireCircleUser(c);
  if (user instanceof Response) return user;
  await assertCircleMember(c.req.param("id"), user.id);
  const invitation = await getPrismaClient().circleInvitation.findFirst({ where: { id: c.req.param("invitationId"), circleId: c.req.param("id"), senderId: user.id, circle: { ownerId: user.id } }, select: { id: true, recipientId: true, status: true } });
  if (!invitation) return c.json({ error: "Circle invitation not found." }, 404);
  const result = await getPrismaClient().circleInvitation.updateMany({ where: { id: invitation.id, status: "pending" }, data: { status: "cancelled", cancelledAt: new Date() } });
  if (result.count) await getPrismaClient().socialNotification.deleteMany({ where: { recipientId: invitation.recipientId, type: "circleInvitation", objectId: invitation.id } });
  return c.json({
    status: result.count ? "cancelled" : "already_handled",
    circle: await circlePayload(c.req.param("id"), user.id, true),
  });
});

router.post("/:id/focus", zValidator("json", focusSchema), async (c) => {
  const user = await requireCircleUser(c);
  if (user instanceof Response) return user;
  await assertCircleMember(c.req.param("id"), user.id);
  const input = c.req.valid("json");
  const circle = await getPrismaClient().circle.findFirst({ where: { id: c.req.param("id"), ownerId: user.id, lifecycle: { not: "archived" } } });
  if (!circle) return c.json({ error: "Owner access is required." }, 403);
  if (input.mode === "shared_target" && !input.sharedTarget) return c.json({ error: "A shared target is required." }, 422);
  await getPrismaClient().circle.update({ where: { id: circle.id }, data: { defaultFocusMode: input.mode, defaultFocusConfigured: true, defaultTarget: input.sharedTarget ?? null } });
  if (input.apply !== "next_week") {
    const week = await ensureCurrentWeek(getPrismaClient(), circle.id, new Date());
    await getPrismaClient().circleWeek.update({ where: { id: week.id }, data: { focusMode: input.mode, focusConfigured: true, sharedTarget: input.sharedTarget ?? null } });
    await refreshWeekState(getPrismaClient(), week.id);
  }
  return c.json(await circlePayload(circle.id, user.id, true));
});

router.put("/:id/commitment", zValidator("json", commitmentSchema), async (c) => {
  const user = await requireCircleUser(c);
  if (user instanceof Response) return user;
  const member = await assertCircleMember(c.req.param("id"), user.id);
  const input = c.req.valid("json");
  const week = await ensureCurrentWeek(getPrismaClient(), c.req.param("id"), new Date());
  if (!week.focusConfigured || week.focusMode !== "personal_targets") return c.json({ error: "Personal commitments are available only for a configured personal focus." }, 422);
  await getPrismaClient().circleCommitment.upsert({ where: { weekId_memberId: { weekId: week.id, memberId: member!.id } }, create: { weekId: week.id, memberId: member!.id, targetCount: input.skipped ? null : input.targetCount ?? 3, skipped: input.skipped }, update: { targetCount: input.skipped ? null : input.targetCount ?? 3, skipped: input.skipped } });
  await refreshWeekState(getPrismaClient(), week.id);
  return c.json(await circlePayload(c.req.param("id"), user.id, true));
});

router.post("/:id/cheers", zValidator("json", z.object({ recipientUserId: z.string().min(1), presetType })), async (c) => {
  const user = await requireCircleUser(c);
  if (user instanceof Response) return user;
  const member = await assertCircleMember(c.req.param("id"), user.id);
  const input = c.req.valid("json");
  const recipient = await assertCircleMember(c.req.param("id"), input.recipientUserId);
  if (!recipient || !member) return c.json({ error: "Circle member not found." }, 404);
  const week = await ensureCurrentWeek(getPrismaClient(), c.req.param("id"), new Date());
  const cheer = await getPrismaClient().circleCheer.upsert({ where: { weekId_senderId_recipientId_presetType: { weekId: week.id, senderId: user.id, recipientId: input.recipientUserId, presetType: input.presetType } }, create: { circleId: c.req.param("id"), weekId: week.id, senderId: user.id, recipientId: input.recipientUserId, presetType: input.presetType }, update: {} });
  if (input.recipientUserId !== user.id) await notify(input.recipientUserId, user.id, "circleCheer", c.req.param("id"), `${user.displayName} sent you a Cheer.`, c.req.param("id"), true, cheer.id);
  return c.json({ id: cheer.id, status: "sent", circle: await circlePayload(c.req.param("id"), user.id, true) }, 201);
});

router.delete("/:id/cheers/:cheerId", async (c) => {
  const user = await requireCircleUser(c);
  if (user instanceof Response) return user;
  await assertCircleMember(c.req.param("id"), user.id);
  await getPrismaClient().circleCheer.deleteMany({ where: { id: c.req.param("cheerId"), circleId: c.req.param("id"), senderId: user.id } });
  return c.json({ status: "removed", circle: await circlePayload(c.req.param("id"), user.id, true) });
});

router.put("/:id/calendar", zValidator("json", calendarSchema), async (c) => {
  const user = await requireCircleUser(c);
  if (user instanceof Response) return user;
  await assertCircleMember(c.req.param("id"), user.id);
  const circle = await getPrismaClient().circle.findFirst({ where: { id: c.req.param("id"), ownerId: user.id } });
  if (!circle) return c.json({ error: "Owner access is required." }, 403);
  const value = c.req.valid("json");
  if (!validTimeZone(value.timeZone)) return c.json({ error: "A valid IANA time zone is required." }, 422);
  const currentWeek = value.apply === "now" ? await ensureCurrentWeek(getPrismaClient(), circle.id, new Date()) : null;
  await getPrismaClient().circle.update({ where: { id: circle.id }, data: { resetWeekday: value.resetWeekday, timeZone: value.timeZone } });
  if (value.apply === "now") {
    const interval = circleWeekInterval(new Date(), value.resetWeekday, value.timeZone);
    await getPrismaClient().circleWeek.update({
      where: { id: currentWeek!.id },
      data: { startsAt: interval.startsAt, endsAt: interval.endsAt, resetWeekday: value.resetWeekday, timeZone: value.timeZone },
    });
    const activities = await getPrismaClient().activity.findMany({ where: { userId: { in: (await getPrismaClient().circleMember.findMany({ where: { circleId: circle.id, status: "active" }, select: { userId: true } })).map((member) => member.userId) }, type: "running", deletedAt: null, startedAt: { gte: new Date(Date.now() - 8 * 86400000) } }, select: { id: true, userId: true } });
    for (const activity of activities) await reconcileActivityToCircles(activity.userId, activity.id);
  }
  return c.json(await circlePayload(circle.id, user.id, true));
});

router.put("/:id/primary", async (c) => {
  const user = await requireCircleUser(c);
  if (user instanceof Response) return user;
  const member = await assertCircleMember(c.req.param("id"), user.id);
  if (member?.circle.lifecycle !== "active") return c.json({ error: "Only an active Circle can be primary." }, 422);
  await getPrismaClient().user.update({ where: { id: user.id }, data: { primaryCircleId: c.req.param("id") } });
  return c.json({
    primaryCircleId: c.req.param("id"),
    circle: await circlePayload(c.req.param("id"), user.id, true),
  });
});

router.put("/:id/notifications", zValidator("json", z.object({ muted: z.boolean() })), async (c) => {
  const user = await requireCircleUser(c);
  if (user instanceof Response) return user;
  await assertCircleMember(c.req.param("id"), user.id);
  await getPrismaClient().circleMember.update({ where: { circleId_userId: { circleId: c.req.param("id"), userId: user.id } }, data: { notificationMuted: c.req.valid("json").muted } });
  return c.json(await circlePayload(c.req.param("id"), user.id, true));
});

router.post("/:id/transfer", zValidator("json", transferSchema), async (c) => {
  const user = await requireCircleUser(c);
  if (user instanceof Response) return user;
  try {
    await assertCircleMember(c.req.param("id"), user.id);
    const circle = await getPrismaClient().circle.findFirst({ where: { id: c.req.param("id"), ownerId: user.id, lifecycle: { not: "archived" } } });
    if (!circle) return c.json({ error: "Owner access is required." }, 403);
    await transferCircleOwnership(circle.id, user.id, c.req.valid("json").recipientUserId);
    await notify(c.req.valid("json").recipientUserId, user.id, "circleOwnershipTransferred", circle.id, `${user.displayName} transferred Circle ownership.`, circle.id, false);
    return c.json(await circlePayload(circle.id, user.id, true));
  } catch (error) { return circleError(c, error); }
});

router.post("/:id/leave", async (c) => {
  const user = await requireCircleUser(c);
  if (user instanceof Response) return user;
  const member = await assertCircleMember(c.req.param("id"), user.id);
  if (member?.role === "owner") return c.json({ error: "Transfer ownership or archive the Circle before leaving." }, 422);
  await getPrismaClient().circleMember.update({ where: { circleId_userId: { circleId: c.req.param("id"), userId: user.id } }, data: { status: "left" } });
  await normalizeCircleAfterMembershipChange(c.req.param("id"), user.id);
  return c.json({ ok: true });
});

router.delete("/:id/members/:memberUserId", async (c) => {
  const user = await requireCircleUser(c);
  if (user instanceof Response) return user;
  await assertCircleMember(c.req.param("id"), user.id);
  const circle = await getPrismaClient().circle.findFirst({ where: { id: c.req.param("id"), ownerId: user.id } });
  if (!circle) return c.json({ error: "Owner access is required." }, 403);
  if (c.req.param("memberUserId") === user.id) return c.json({ error: "Transfer ownership before removing yourself." }, 422);
  await getPrismaClient().circleMember.updateMany({ where: { circleId: circle.id, userId: c.req.param("memberUserId"), status: "active" }, data: { status: "removed" } });
  await normalizeCircleAfterMembershipChange(circle.id, c.req.param("memberUserId"));
  return c.json(await circlePayload(circle.id, user.id, true));
});

router.post("/:id/archive", async (c) => {
  const user = await requireCircleUser(c);
  if (user instanceof Response) return user;
  await assertCircleMember(c.req.param("id"), user.id);
  const result = await getPrismaClient().circle.updateMany({ where: { id: c.req.param("id"), ownerId: user.id, lifecycle: { not: "archived" } }, data: { lifecycle: "archived" } });
  if (!result.count) return c.json({ error: "Circle not found." }, 404);
  await getPrismaClient().user.updateMany({ where: { primaryCircleId: c.req.param("id") }, data: { primaryCircleId: null } });
  return c.json(await circlePayload(c.req.param("id"), user.id, true));
});

router.post("/:id/weeks/:weekId/presentation", async (c) => {
  const user = await requireCircleUser(c);
  if (user instanceof Response) return user;
  try {
    await assertCircleMember(c.req.param("id"), user.id);
    const result = await getPrismaClient().circleWeekPresentation.updateMany({ where: { weekId: c.req.param("weekId"), userId: user.id, presentedAt: null, week: { circleId: c.req.param("id"), state: "completed" } }, data: { presentedAt: new Date() } });
    return c.json({ presented: result.count > 0 });
  } catch (error) { return circleError(c, error); }
});

router.post("/:id/reactivate", async (c) => {
  const user = await requireCircleUser(c);
  if (user instanceof Response) return user;
  await assertCircleMember(c.req.param("id"), user.id);
  const activeCount = await getPrismaClient().circleMember.count({ where: { circleId: c.req.param("id"), status: "active" } });
  const result = await getPrismaClient().circle.updateMany({ where: { id: c.req.param("id"), ownerId: user.id, lifecycle: "archived" }, data: { lifecycle: activeCount >= 2 ? "active" : "awaiting_members" } });
  if (!result.count) return c.json({ error: "Circle not found." }, 404);
  return c.json(await circlePayload(c.req.param("id"), user.id, true));
});

async function requireCircleUser(c: Context<AppEnv>) {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c);
  return user ?? c.json({ error: "Authentication is required." }, 401);
}

function circleError(c: Context<AppEnv>, error: unknown) {
  if (error instanceof CircleDomainError) return c.json({ error: error.message, code: error.code }, error.code === "not_a_member" ? 403 : 409);
  console.error("[circle] request failed", error);
  return c.json({ error: "Circle operation failed." }, 500);
}

router.onError((error, c) => circleError(c, error));

async function notify(recipientId: string, actorId: string, type: string, objectId: string, message: string, circleId?: string, respectMute = true, dedupeReference = objectId) {
  if (respectMute && circleId) {
    const member = await getPrismaClient().circleMember.findUnique({ where: { circleId_userId: { circleId, userId: recipientId } }, select: { notificationMuted: true, status: true } });
    if (member?.status === "active" && member.notificationMuted) return;
  }
  const dedupeKey = `${type}:${dedupeReference}:${recipientId}`;
  await getPrismaClient().socialNotification.upsert({ where: { dedupeKey }, create: { recipientId, actorId, type, objectId, message, dedupeKey }, update: { message } });
}

async function normalizeCircleAfterMembershipChange(circleId: string, departingUserId: string) {
  const prisma = getPrismaClient();
  const activeCount = await prisma.circleMember.count({ where: { circleId, status: "active" } });
  await prisma.circle.updateMany({ where: { id: circleId, lifecycle: { not: "archived" } }, data: { lifecycle: activeCount >= 2 ? "active" : "awaiting_members" } });
  await prisma.user.updateMany({ where: { id: departingUserId, primaryCircleId: circleId }, data: { primaryCircleId: null } });
}

export default router;
