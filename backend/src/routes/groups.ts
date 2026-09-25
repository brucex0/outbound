import { Hono } from "hono";
import { createHash, randomBytes } from "node:crypto";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";
import type { Context } from "hono";
import { Prisma } from "@prisma/client";
import type { AppEnv } from "../types/hono.js";
import { requireDatabase } from "../services/database.js";
import { getAuthenticatedAppUser } from "../services/currentUser.js";
import { getPrismaClient } from "../services/prisma.js";
import { compactPerson } from "../services/apiAssetURLs.js";
import {
  assertAcceptedConnection,
  assertGroupMember,
  assertNoBlockedPair,
  assertNoBlockedGroupMember,
  groupPayload,
  groupWeekInterval,
  createGroup,
  GroupDomainError,
  GROUP_MEMBER_LIMIT_MAXIMUM,
  configuredGroupMemberLimit,
  ensureCurrentWeek,
  refreshWeekState,
  reconcileActivityToGroups,
  transferGroupOwnership,
  validTimeZone,
} from "../services/groups.js";

const router = new Hono<AppEnv>();
const focusMode = z.enum(["theme", "personal_targets", "shared_target", "none"]);
const themeKey = z.enum([
  "build_consistency",
  "one_small_step",
  "keep_the_rhythm",
  "move_for_your_mood",
  "recover_and_recharge",
  "do_something_together",
  "explore_somewhere_new",
  "try_something_different",
  "celebrate_every_effort",
  "custom",
]);
const presetType = z.enum(["encouragement", "celebration", "support"]);
const createSchema = z.object({
  template: z.enum(["motivation", "activities"]).default("motivation"),
  name: z.string().trim().max(80).nullable().optional(),
  description: z.string().trim().max(500).nullable().optional(),
  city: z.string().trim().max(120).nullable().optional(),
  activityInterests: z.array(z.enum(["running", "walking", "hiking", "cycling", "swimming", "strength", "mixed"])).max(12).default([]),
  memberUserIds: z.array(z.string().min(1)).max(GROUP_MEMBER_LIMIT_MAXIMUM - 1).default([]),
  timeZone: z.string().trim().max(100).optional(),
  resetWeekday: z.number().int().min(1).max(7).optional(),
  idempotencyKey: z.string().trim().min(8).max(128).optional(),
});
const focusSchema = z.object({
  mode: focusMode,
  sharedTarget: z.number().int().min(1).max(100).nullable().optional(),
  themeKey: themeKey.nullable().optional(),
  customThemeTitle: z.string().trim().min(1).max(50).nullable().optional(),
  customThemeNote: z.string().trim().max(120).nullable().optional(),
  apply: z.enum(["now", "next_week"]).default("now"),
}).superRefine((input, context) => {
  if (input.mode === "theme" && !input.themeKey) {
    context.addIssue({ code: z.ZodIssueCode.custom, path: ["themeKey"], message: "A weekly theme is required." });
  }
  if (input.themeKey && input.mode !== "theme") {
    context.addIssue({ code: z.ZodIssueCode.custom, path: ["themeKey"], message: "Themes require theme focus mode." });
  }
  if (input.themeKey === "custom" && !input.customThemeTitle) {
    context.addIssue({ code: z.ZodIssueCode.custom, path: ["customThemeTitle"], message: "A custom theme needs a title." });
  }
});
const commitmentSchema = z.object({ targetCount: z.number().int().min(1).max(100).nullable().optional(), skipped: z.boolean().default(false), clear: z.boolean().default(false) });
const inviteSchema = z.object({ recipientUserIds: z.array(z.string().min(1)).min(1).max(GROUP_MEMBER_LIMIT_MAXIMUM - 1), idempotencyKey: z.string().min(1).max(128).optional() });
const renameSchema = z.object({
  name: z.string().trim().min(1).max(80).optional(),
  description: z.string().trim().max(500).nullable().optional(),
  city: z.string().trim().max(120).nullable().optional(),
  activityInterests: z.array(z.string().trim().min(1).max(30)).max(12).optional(),
  visibility: z.enum(["private", "unlisted", "public"]).optional(),
  joinPolicy: z.enum(["invite_only", "request", "open"]).optional(),
  weeklyThemeEnabled: z.boolean().optional(),
  workoutContributionsEnabled: z.boolean().optional(),
  presetCheersEnabled: z.boolean().optional(),
  noticesEnabled: z.boolean().optional(),
  scheduledActivitiesEnabled: z.boolean().optional(),
  memberActivityCreation: z.boolean().optional(),
});
const calendarSchema = z.object({ resetWeekday: z.number().int().min(1).max(7), timeZone: z.string().trim().max(100), apply: z.enum(["now", "next_week"]).default("next_week") });
const transferSchema = z.object({ recipientUserId: z.string().min(1) });
const noticeSchema = z.object({ title: z.string().trim().max(120).nullable().optional(), body: z.string().trim().min(1).max(1000), activityEventId: z.string().min(1).nullable().optional(), pinned: z.boolean().default(false) });
const roleSchema = z.object({ role: z.enum(["admin", "member"]) });

router.get("/", async (c) => {
  const user = await requireGroupUser(c);
  if (user instanceof Response) return user;
  const prisma = getPrismaClient();
  const scope = c.req.query("scope") ?? "mine";
  const query = c.req.query("query")?.trim();
  const city = c.req.query("city")?.trim();
  const cursor = c.req.query("cursor");
  const take = 20;
  const blocked = await prisma.socialBlock.findMany({ where: { OR: [{ blockerId: user.id }, { blockedId: user.id }] }, select: { blockerId: true, blockedId: true } });
  const blockedUserIds = blocked.map((item) => item.blockerId === user.id ? item.blockedId : item.blockerId);
  const where = scope === "discover"
    ? { trustPolicy: "community", visibility: "public", lifecycle: "active", ...(blockedUserIds.length ? { members: { none: { status: "active", userId: { in: blockedUserIds } } } } : {}), ...(city ? { city: { contains: city, mode: "insensitive" as const } } : {}), ...(query ? { normalizedName: { contains: normalizeSearchName(query) } } : {}) }
    : { lifecycle: "active", members: { some: { userId: user.id, status: "active" }, ...(blockedUserIds.length ? { none: { status: "active", userId: { in: blockedUserIds } } } : {}) } };
  const rows = await prisma.socialGroup.findMany({ where, include: { owner: { select: { id: true, displayName: true, avatarUrl: true } }, members: { where: { status: "active" }, select: { userId: true, role: true } }, _count: { select: { members: true } } }, orderBy: [{ featured: "desc" }, { updatedAt: "desc" }, { id: "asc" }], ...(cursor ? { skip: 1, cursor: { id: cursor } } : {}), take: take + 1 });
  const page = rows.slice(0, take);
  const visibleGroups = page.map((socialGroup) => ({
    id: socialGroup.id,
    name: socialGroup.name,
    normalizedName: socialGroup.normalizedName,
    description: socialGroup.description,
    city: socialGroup.city,
    activityInterests: socialGroup.activityInterests ?? [],
    trustPolicy: socialGroup.trustPolicy,
    groupType: socialGroup.trustPolicy === "community" ? "community" : "private",
    visibility: socialGroup.visibility,
    joinPolicy: socialGroup.joinPolicy,
    lifecycle: socialGroup.lifecycle,
    featured: socialGroup.featured,
    organizationVerificationState: socialGroup.organizationVerificationState,
    memberCount: socialGroup._count.members,
    membershipRole: socialGroup.members.find((member) => member.userId === user.id)?.role ?? null,
    owner: socialGroup.owner ? compactPerson(socialGroup.owner) : null,
    contextLabel: socialGroup.city ?? socialGroup.owner?.displayName ?? null,
    canJoin: socialGroup.trustPolicy === "community" && !socialGroup.members.some((member) => member.userId === user.id),
  }));
  return c.json({
    groups: visibleGroups,
    nextCursor: rows.length > take ? page.at(-1)?.id ?? null : null,
    scope,
    policy: { memberLimit: configuredGroupMemberLimit() },
  });
});

router.post("/", zValidator("json", createSchema), async (c) => {
  const user = await requireGroupUser(c);
  if (user instanceof Response) return user;
  try {
    const input = c.req.valid("json");
    const groupId = await createGroup(user.id, { ...input, name: input.name ?? undefined, locale: c.get("locale"), idempotencyKey: input.idempotencyKey ?? c.req.header("Idempotency-Key") });
    const socialGroup = await groupPayload(groupId, user.id);
    const created = await getPrismaClient().socialGroup.findUniqueOrThrow({ where: { id: groupId }, include: { invitations: { where: { status: "pending" }, select: { id: true, recipientId: true } } } });
    for (const invitation of created.invitations) await notify(invitation.recipientId, user.id, "groupInvitation", invitation.id, `${user.displayName} invited you to ${created.name}.`, groupId, false);
    return c.json(socialGroup, 201);
  } catch (error) {
    return groupError(c, error);
  }
});

router.get("/:id", async (c) => {
  const user = await requireGroupUser(c);
  if (user instanceof Response) return user;
  try {
    const group = await getPrismaClient().socialGroup.findUnique({ where: { id: c.req.param("id") }, select: { trustPolicy: true, visibility: true, lifecycle: true, joinPolicy: true } });
    if (!group || group.lifecycle === "archived") return c.json({ error: "Group not found." }, 404);
    const member = await getPrismaClient().groupMember.findUnique({ where: { groupId_userId: { groupId: c.req.param("id"), userId: user.id } }, select: { status: true } });
    const invitation = await getPrismaClient().groupInvitation.findFirst({ where: { groupId: c.req.param("id"), recipientId: user.id, status: "pending" }, select: { id: true } });
    if (group.trustPolicy === "trusted_private" && member?.status !== "active") return c.json({ error: "Group not found." }, 404);
    if (group.visibility === "unlisted" && member?.status !== "active" && !invitation) return c.json({ error: "Group not found." }, 404);
    await assertNoBlockedGroupMember(c.req.param("id"), user.id);
    const payload = await groupPayload(c.req.param("id"), user.id, true);
    return payload ? c.json(payload) : c.json({ error: "Group not found." }, 404);
  } catch (error) {
    return groupError(c, error);
  }
});

router.patch("/:id", zValidator("json", renameSchema), async (c) => {
  const user = await requireGroupUser(c);
  if (user instanceof Response) return user;
  await assertGroupMember(c.req.param("id"), user.id);
  const socialGroup = await getPrismaClient().socialGroup.findFirst({ where: { id: c.req.param("id"), lifecycle: { not: "archived" } } });
  if (!socialGroup) return c.json({ error: "Group not found." }, 404);
  const input = c.req.valid("json");
  const member = await getPrismaClient().groupMember.findUnique({ where: { groupId_userId: { groupId: socialGroup.id, userId: user.id } }, select: { role: true } });
  if (!member || !["owner", "admin"].includes(member.role)) return c.json({ error: "Group management access is required." }, 403);
  if (input.visibility || input.joinPolicy || input.weeklyThemeEnabled !== undefined || input.workoutContributionsEnabled !== undefined || input.presetCheersEnabled !== undefined || input.memberActivityCreation !== undefined) {
    if (member.role !== "owner") return c.json({ error: "Only the owner can change Group policy." }, 403);
    const visibility = input.visibility ?? socialGroup.visibility;
    const joinPolicy = input.joinPolicy ?? socialGroup.joinPolicy;
    if (socialGroup.trustPolicy === "trusted_private" && (visibility !== "private" || joinPolicy !== "invite_only")) return c.json({ error: "Private Groups must remain private and invitation-only." }, 422);
    if (socialGroup.trustPolicy === "community" && visibility === "private") return c.json({ error: "Community Groups cannot be private." }, 422);
    if (socialGroup.trustPolicy === "community" && (input.weeklyThemeEnabled || input.workoutContributionsEnabled || input.memberActivityCreation)) return c.json({ error: "Community Groups cannot enable private motivation capabilities." }, 422);
  }
  const name = input.name;
  await getPrismaClient().socialGroup.update({ where: { id: socialGroup.id }, data: { ...(name ? { name, normalizedName: normalizeSearchName(name) } : {}), ...(input.description !== undefined ? { description: input.description } : {}), ...(input.city !== undefined ? { city: input.city } : {}), ...(input.activityInterests ? { activityInterests: input.activityInterests } : {}), ...(input.visibility ? { visibility: input.visibility } : {}), ...(input.joinPolicy ? { joinPolicy: input.joinPolicy } : {}), ...(input.weeklyThemeEnabled !== undefined ? { weeklyThemeEnabled: input.weeklyThemeEnabled } : {}), ...(input.workoutContributionsEnabled !== undefined ? { workoutContributionsEnabled: input.workoutContributionsEnabled } : {}), ...(input.presetCheersEnabled !== undefined ? { presetCheersEnabled: input.presetCheersEnabled } : {}), ...(input.noticesEnabled !== undefined ? { noticesEnabled: input.noticesEnabled } : {}), ...(input.scheduledActivitiesEnabled !== undefined ? { scheduledActivitiesEnabled: input.scheduledActivitiesEnabled } : {}), ...(input.memberActivityCreation !== undefined ? { memberActivityCreation: input.memberActivityCreation } : {}) } });
  return c.json(await groupPayload(socialGroup.id, user.id, true));
});

router.post("/:id/join-requests", async (c) => {
  const user = await requireGroupUser(c);
  if (user instanceof Response) return user;
  const prisma = getPrismaClient();
  const group = await prisma.socialGroup.findUnique({ where: { id: c.req.param("id") } });
  if (!group || group.trustPolicy !== "community" || group.lifecycle === "archived") return c.json({ error: "Group not available." }, 404);
  if (group.joinPolicy === "invite_only") return c.json({ error: "This Group is invitation-only." }, 403);
  await assertNoBlockedGroupMember(group.id, user.id);
  const existing = await prisma.groupMember.findUnique({ where: { groupId_userId: { groupId: group.id, userId: user.id } } });
  if (existing?.status === "active") return c.json(await groupPayload(group.id, user.id, true));
  const activeCount = await prisma.groupMember.count({ where: { groupId: group.id, status: "active" } });
  if (activeCount >= group.memberLimit) return c.json({ error: "This Group is full." }, 409);
  if (group.joinPolicy === "open") {
    await prisma.groupMember.upsert({ where: { groupId_userId: { groupId: group.id, userId: user.id } }, create: { groupId: group.id, userId: user.id, status: "active", role: "member", displayNameSnapshot: user.displayName, avatarUrlSnapshot: user.avatarUrl }, update: { status: "active", joinedAt: new Date(), displayNameSnapshot: user.displayName, avatarUrlSnapshot: user.avatarUrl } });
    return c.json(await groupPayload(group.id, user.id, true), 201);
  }
  const request = await prisma.groupJoinRequest.upsert({ where: { groupId_requesterId: { groupId: group.id, requesterId: user.id } }, create: { groupId: group.id, requesterId: user.id, idempotencyKey: c.req.header("Idempotency-Key") ?? crypto.randomUUID() }, update: { status: "pending", reviewerId: null, decisionAt: null } });
  const managers = await prisma.groupMember.findMany({ where: { groupId: group.id, role: { in: ["owner", "admin"] }, status: "active" }, select: { userId: true } });
  for (const manager of managers) await notify(manager.userId, user.id, "groupJoinRequest", group.id, `${user.displayName} requested to join ${group.name}.`, group.id, true, request.id);
  return c.json({ request, group: await groupPayload(group.id, user.id, true) }, 201);
});

router.delete("/:id/join-requests", async (c) => {
  const user = await requireGroupUser(c);
  if (user instanceof Response) return user;
  await getPrismaClient().groupJoinRequest.updateMany({ where: { groupId: c.req.param("id"), requesterId: user.id, status: "pending" }, data: { status: "cancelled", decisionAt: new Date() } });
  return c.json({ status: "cancelled", group: await groupPayload(c.req.param("id"), user.id, true) });
});

router.get("/:id/join-requests", async (c) => {
  const user = await requireGroupUser(c);
  if (user instanceof Response) return user;
  const member = await assertGroupMember(c.req.param("id"), user.id);
  if (!member || !["owner", "admin"].includes(member.role)) return c.json({ error: "Group management access is required." }, 403);
  const requests = await getPrismaClient().groupJoinRequest.findMany({ where: { groupId: c.req.param("id"), status: "pending" }, include: { requester: { select: { id: true, displayName: true, avatarUrl: true } } }, orderBy: { createdAt: "asc" } });
  return c.json({ requests: requests.map((request) => ({ ...request, requester: compactPerson(request.requester) })) });
});

router.post("/:id/join-requests/:requestId/:decision", async (c) => {
  const user = await requireGroupUser(c);
  if (user instanceof Response) return user;
  const member = await assertGroupMember(c.req.param("id"), user.id);
  if (!member || !["owner", "admin"].includes(member.role)) return c.json({ error: "Group management access is required." }, 403);
  const decision = c.req.param("decision");
  if (decision !== "approve" && decision !== "deny") return c.json({ error: "Unsupported decision." }, 400);
  const prisma = getPrismaClient();
  const request = await prisma.groupJoinRequest.findFirst({ where: { id: c.req.param("requestId"), groupId: c.req.param("id"), status: "pending" }, include: { group: true, requester: true } });
  if (!request) return c.json({ error: "Join request not found." }, 404);
  if (decision === "deny") await prisma.groupJoinRequest.update({ where: { id: request.id }, data: { status: "denied", reviewerId: user.id, decisionAt: new Date() } });
  else await prisma.$transaction(async (tx) => { const count = await tx.groupMember.count({ where: { groupId: request.groupId, status: "active" } }); if (count >= request.group.memberLimit) throw new GroupDomainError("capacity", "This Group is full."); await tx.groupJoinRequest.update({ where: { id: request.id }, data: { status: "approved", reviewerId: user.id, decisionAt: new Date() } }); await tx.groupMember.upsert({ where: { groupId_userId: { groupId: request.groupId, userId: request.requesterId } }, create: { groupId: request.groupId, userId: request.requesterId, role: "member", status: "active", displayNameSnapshot: request.requester.displayName, avatarUrlSnapshot: request.requester.avatarUrl }, update: { role: "member", status: "active", joinedAt: new Date() } }); });
  await prisma.socialNotification.deleteMany({ where: { recipientId: request.requesterId, type: "groupJoinRequest", objectId: request.id } });
  await notify(request.requesterId, user.id, decision === "approve" ? "groupJoinRequestApproved" : "groupJoinRequestDenied", request.id, decision === "approve" ? `Your Group request was approved for ${request.group.name}.` : `Your request to join ${request.group.name} was declined.`, request.groupId, false);
  return c.json({ status: decision === "approve" ? "approved" : "denied", group: await groupPayload(request.groupId, user.id, true) });
});

router.post("/:id/invitations", zValidator("json", inviteSchema), async (c) => {
  const user = await requireGroupUser(c);
  if (user instanceof Response) return user;
  const prisma = getPrismaClient();
  await assertGroupMember(c.req.param("id"), user.id);
  const now = new Date();
  await prisma.groupInvitation.updateMany({ where: { groupId: c.req.param("id"), status: "pending", expiresAt: { lte: now } }, data: { status: "expired" } });
  const currentMember = await prisma.groupMember.findUnique({ where: { groupId_userId: { groupId: c.req.param("id"), userId: user.id } }, select: { role: true, status: true } });
  if (!currentMember || currentMember.status !== "active" || !["owner", "admin"].includes(currentMember.role)) return c.json({ error: "Group management access is required." }, 403);
  const socialGroup = await prisma.socialGroup.findFirst({ where: { id: c.req.param("id"), lifecycle: { not: "archived" } }, include: { members: { where: { status: "active" } }, invitations: { where: { status: "pending" } } } });
  if (!socialGroup) return c.json({ error: "Group not found." }, 404);
  const ids = [...new Set(c.req.valid("json").recipientUserIds.filter((id) => id !== user.id))];
  const newRecipientIDs = ids.filter((id) => !socialGroup.members.some((member) => member.userId === id) && !socialGroup.invitations.some((invitation) => invitation.recipientId === id));
  if (socialGroup.members.length + socialGroup.invitations.length + newRecipientIDs.length > socialGroup.memberLimit) return c.json({ error: "Those invitations would exceed this Group’s current capacity." }, 409);
  const results = [];
  for (const recipientId of ids) {
    try {
      if (socialGroup.trustPolicy === "trusted_private") {
        await assertAcceptedConnection(socialGroup.ownerId ?? user.id, recipientId);
        await assertAcceptedConnection(user.id, recipientId);
      } else {
        await assertNoBlockedGroupMember(socialGroup.id, recipientId);
      }
    } catch (error) { results.push({ recipientUserId: recipientId, status: error instanceof GroupDomainError ? error.code : "rejected" }); continue; }
    const existingMember = socialGroup.members.some((member) => member.userId === recipientId);
    const existing = socialGroup.invitations.find((invitation) => invitation.recipientId === recipientId);
    if (existingMember) { results.push({ recipientUserId: recipientId, status: "already_member" }); continue; }
    if (existing) { results.push({ recipientUserId: recipientId, status: "already_pending", id: existing.id }); continue; }
    const prior = await prisma.groupInvitation.findUnique({ where: { groupId_recipientId: { groupId: socialGroup.id, recipientId } } });
    const invitation = prior
      ? await prisma.groupInvitation.update({ where: { id: prior.id }, data: { senderId: user.id, status: "pending", idempotencyKey: c.req.valid("json").idempotencyKey ? `${c.req.valid("json").idempotencyKey}:${recipientId}` : crypto.randomUUID(), expiresAt: new Date(Date.now() + 7 * 86400000), acceptedAt: null, declinedAt: null, cancelledAt: null } })
      : await prisma.groupInvitation.create({ data: { groupId: socialGroup.id, senderId: user.id, recipientId, idempotencyKey: c.req.valid("json").idempotencyKey ? `${c.req.valid("json").idempotencyKey}:${recipientId}` : crypto.randomUUID(), expiresAt: new Date(Date.now() + 7 * 86400000) } });
    await notify(recipientId, user.id, "groupInvitation", invitation.id, `${user.displayName} invited you to ${socialGroup.name}.`, socialGroup.id, false);
    results.push({ recipientUserId: recipientId, status: "sent", id: invitation.id });
  }
  return c.json({ invitations: results, group: await groupPayload(socialGroup.id, user.id, true) }, 201);
});

router.get("/invitations/inbox", async (c) => {
  const user = await requireGroupUser(c);
  if (user instanceof Response) return user;
  const prisma = getPrismaClient();
  const now = new Date();
  await prisma.groupInvitation.updateMany({ where: { recipientId: user.id, status: "pending", expiresAt: { lte: now } }, data: { status: "expired" } });
  const candidates = await prisma.groupInvitation.findMany({ where: { recipientId: user.id, status: "pending", OR: [{ expiresAt: null }, { expiresAt: { gt: now } }] }, include: { group: { select: { id: true, name: true, trustPolicy: true } }, sender: { select: { id: true, displayName: true, avatarUrl: true } } }, orderBy: { createdAt: "desc" } });
  const invitations = [];
  for (const invitation of candidates) {
    try {
      if (invitation.group.trustPolicy === "trusted_private") await assertAcceptedConnection(invitation.senderId, user.id);
      else await assertNoBlockedPair(invitation.senderId, user.id);
      await assertNoBlockedGroupMember(invitation.groupId, user.id);
      invitations.push({ ...invitation, sender: compactPerson(invitation.sender) });
    } catch { /* Blocked and disconnected invitations are intentionally hidden. */ }
  }
  return c.json({ invitations });
});

router.post("/invitations/:invitationId/accept", async (c) => {
  const user = await requireGroupUser(c);
  if (user instanceof Response) return user;
  const prisma = getPrismaClient();
  try {
    const invitation = await prisma.groupInvitation.findFirst({ where: { id: c.req.param("invitationId"), recipientId: user.id }, include: { group: { include: { members: { where: { status: "active" } } } } } });
    if (!invitation) return c.json({ error: "Group invitation not found." }, 404);
    if (invitation.status === "accepted") {
      await assertGroupMember(invitation.groupId, user.id);
      await prisma.socialNotification.deleteMany({ where: { recipientId: user.id, type: "groupInvitation", objectId: invitation.id } });
      return c.json(await groupPayload(invitation.groupId, user.id, true));
    }
    if (invitation.status !== "pending") return c.json({ error: "This Group invitation is no longer active." }, 409);
    if (invitation.group.trustPolicy === "trusted_private") await assertAcceptedConnection(invitation.senderId, user.id);
    else await assertNoBlockedPair(invitation.senderId, user.id);
    if (invitation.expiresAt && invitation.expiresAt <= new Date()) {
      await prisma.groupInvitation.update({ where: { id: invitation.id }, data: { status: "expired" } });
      return c.json({ error: "This Group invitation has expired." }, 410);
    }
    await assertNoBlockedGroupMember(invitation.groupId, user.id);
    const result = await prisma.$transaction(async (tx) => {
      const activeCount = await tx.groupMember.count({ where: { groupId: invitation.groupId, status: "active" } });
      if (activeCount >= invitation.group.memberLimit) throw new GroupDomainError("capacity", "This Group is full.");
      await tx.groupInvitation.updateMany({ where: { id: invitation.id, status: "pending" }, data: { status: "accepted", acceptedAt: new Date() } });
      await tx.groupMember.upsert({ where: { groupId_userId: { groupId: invitation.groupId, userId: user.id } }, create: { groupId: invitation.groupId, userId: user.id, role: "member", status: "active", displayNameSnapshot: user.displayName, avatarUrlSnapshot: user.avatarUrl }, update: { status: "active", role: "member", joinedAt: new Date(), displayNameSnapshot: user.displayName, avatarUrlSnapshot: user.avatarUrl } });
      const count = await tx.groupMember.count({ where: { groupId: invitation.groupId, status: "active" } });
      await tx.socialGroup.update({ where: { id: invitation.groupId }, data: { lifecycle: count >= 2 ? "active" : "awaiting_members" } });
      return tx.socialGroup.findUniqueOrThrow({ where: { id: invitation.groupId }, select: { name: true, ownerId: true } });
    }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable });
    await prisma.socialNotification.deleteMany({ where: { recipientId: user.id, type: "groupInvitation", objectId: invitation.id } });
    if (result.ownerId) await notify(result.ownerId, user.id, "groupInvitationAccepted", invitation.groupId, `${user.displayName} joined ${invitation.group.name}.`, invitation.groupId, false);
    return c.json(await groupPayload(invitation.groupId, user.id, true));
  } catch (error) { return groupError(c, error); }
});

router.post("/invitations/:invitationId/decline", async (c) => {
  const user = await requireGroupUser(c);
  if (user instanceof Response) return user;
  const prisma = getPrismaClient();
  const invitation = await prisma.groupInvitation.findFirst({ where: { id: c.req.param("invitationId"), recipientId: user.id, status: "pending" }, select: { id: true, groupId: true, senderId: true, group: { select: { trustPolicy: true } } } });
  if (invitation) {
    if (invitation.group.trustPolicy === "trusted_private") await assertAcceptedConnection(invitation.senderId, user.id);
    else await assertNoBlockedPair(invitation.senderId, user.id);
    await assertNoBlockedGroupMember(invitation.groupId, user.id);
    await prisma.groupInvitation.updateMany({ where: { id: invitation.id, status: "pending" }, data: { status: "declined", declinedAt: new Date() } });
  }
  await prisma.socialNotification.deleteMany({ where: { recipientId: user.id, type: "groupInvitation", objectId: c.req.param("invitationId") } });
  return c.json({ status: "declined" });
});

router.post("/:id/invitations/:invitationId/cancel", async (c) => {
  const user = await requireGroupUser(c);
  if (user instanceof Response) return user;
  await assertGroupMember(c.req.param("id"), user.id);
  const member = await getPrismaClient().groupMember.findUnique({ where: { groupId_userId: { groupId: c.req.param("id"), userId: user.id } }, select: { role: true, status: true } });
  if (!member || member.status !== "active" || !["owner", "admin"].includes(member.role)) return c.json({ error: "Group management access is required." }, 403);
  const invitation = await getPrismaClient().groupInvitation.findFirst({ where: { id: c.req.param("invitationId"), groupId: c.req.param("id"), status: "pending" }, select: { id: true, recipientId: true, status: true } });
  if (!invitation) return c.json({ error: "Group invitation not found." }, 404);
  const result = await getPrismaClient().groupInvitation.updateMany({ where: { id: invitation.id, status: "pending" }, data: { status: "cancelled", cancelledAt: new Date() } });
  if (result.count) await getPrismaClient().socialNotification.deleteMany({ where: { recipientId: invitation.recipientId, type: "groupInvitation", objectId: invitation.id } });
  return c.json({
    status: result.count ? "cancelled" : "already_handled",
    group: await groupPayload(c.req.param("id"), user.id, true),
  });
});

router.post("/:id/focus", zValidator("json", focusSchema), async (c) => {
  const user = await requireGroupUser(c);
  if (user instanceof Response) return user;
  await assertGroupMember(c.req.param("id"), user.id);
  const input = c.req.valid("json");
  const socialGroup = await getPrismaClient().socialGroup.findFirst({ where: { id: c.req.param("id"), lifecycle: { not: "archived" } } });
  const member = await getPrismaClient().groupMember.findUnique({ where: { groupId_userId: { groupId: c.req.param("id"), userId: user.id } }, select: { role: true, status: true } });
  if (!socialGroup || !member || member.status !== "active" || member.role !== "owner") return c.json({ error: "Owner access is required." }, 403);
  if (!socialGroup.weeklyThemeEnabled) return c.json({ error: "Weekly Themes are not enabled for this Group." }, 422);
  if (input.mode === "shared_target" && !input.sharedTarget) return c.json({ error: "A shared target is required." }, 422);
  const defaultTheme = input.themeKey === undefined ? {} : {
    defaultThemeKey: input.themeKey,
    defaultThemeTitle: input.themeKey === "custom" ? input.customThemeTitle : null,
    defaultThemeNote: input.themeKey === "custom" ? input.customThemeNote || null : null,
  };
  const weekTheme = input.themeKey === undefined ? {} : {
    themeKey: input.themeKey,
    themeTitle: input.themeKey === "custom" ? input.customThemeTitle : null,
    themeNote: input.themeKey === "custom" ? input.customThemeNote || null : null,
  };
  await getPrismaClient().socialGroup.update({ where: { id: socialGroup.id }, data: { defaultFocusMode: input.mode, defaultFocusConfigured: true, defaultTarget: input.sharedTarget ?? null, ...defaultTheme } });
  if (input.apply !== "next_week") {
    const week = await ensureCurrentWeek(getPrismaClient(), socialGroup.id, new Date());
    await getPrismaClient().groupWeek.update({ where: { id: week.id }, data: { focusMode: input.mode, focusConfigured: true, sharedTarget: input.sharedTarget ?? null, ...weekTheme } });
    await refreshWeekState(getPrismaClient(), week.id);
  }
  return c.json(await groupPayload(socialGroup.id, user.id, true));
});

router.put("/:id/commitment", zValidator("json", commitmentSchema), async (c) => {
  const user = await requireGroupUser(c);
  if (user instanceof Response) return user;
  const member = await assertGroupMember(c.req.param("id"), user.id);
  const group = await getPrismaClient().socialGroup.findUnique({ where: { id: c.req.param("id") }, select: { trustPolicy: true, workoutContributionsEnabled: true } });
  if (!group || group.trustPolicy !== "trusted_private" || !group.workoutContributionsEnabled) return c.json({ error: "Personal commitments are not available for this Group." }, 422);
  const input = c.req.valid("json");
  const week = await ensureCurrentWeek(getPrismaClient(), c.req.param("id"), new Date());
  if (!week.focusConfigured || !["theme", "personal_targets"].includes(week.focusMode)) return c.json({ error: "Personal commitments are not available for this weekly theme." }, 422);
  if (input.clear) {
    await getPrismaClient().groupCommitment.deleteMany({ where: { weekId: week.id, memberId: member!.id } });
  } else {
    await getPrismaClient().groupCommitment.upsert({ where: { weekId_memberId: { weekId: week.id, memberId: member!.id } }, create: { weekId: week.id, memberId: member!.id, targetCount: input.skipped ? null : input.targetCount ?? 3, skipped: input.skipped }, update: { targetCount: input.skipped ? null : input.targetCount ?? 3, skipped: input.skipped } });
  }
  await refreshWeekState(getPrismaClient(), week.id);
  return c.json(await groupPayload(c.req.param("id"), user.id, true));
});

router.post("/:id/cheers", zValidator("json", z.object({ recipientUserId: z.string().min(1), presetType })), async (c) => {
  const user = await requireGroupUser(c);
  if (user instanceof Response) return user;
  const member = await assertGroupMember(c.req.param("id"), user.id);
  const group = await getPrismaClient().socialGroup.findUnique({ where: { id: c.req.param("id") }, select: { trustPolicy: true, presetCheersEnabled: true } });
  if (!group || group.trustPolicy !== "trusted_private" || !group.presetCheersEnabled) return c.json({ error: "Cheers are not enabled for this Group." }, 422);
  const input = c.req.valid("json");
  const recipient = await assertGroupMember(c.req.param("id"), input.recipientUserId);
  if (!recipient || !member) return c.json({ error: "Group member not found." }, 404);
  const week = await ensureCurrentWeek(getPrismaClient(), c.req.param("id"), new Date());
  const cheer = await getPrismaClient().groupCheer.upsert({ where: { weekId_senderId_recipientId_presetType: { weekId: week.id, senderId: user.id, recipientId: input.recipientUserId, presetType: input.presetType } }, create: { groupId: c.req.param("id"), weekId: week.id, senderId: user.id, recipientId: input.recipientUserId, presetType: input.presetType }, update: {} });
  if (input.recipientUserId !== user.id) await notify(input.recipientUserId, user.id, "groupCheer", c.req.param("id"), `${user.displayName} sent you a Cheer.`, c.req.param("id"), true, cheer.id);
  return c.json({ id: cheer.id, status: "sent", group: await groupPayload(c.req.param("id"), user.id, true) }, 201);
});

router.delete("/:id/cheers/:cheerId", async (c) => {
  const user = await requireGroupUser(c);
  if (user instanceof Response) return user;
  await assertGroupMember(c.req.param("id"), user.id);
  await getPrismaClient().groupCheer.deleteMany({ where: { id: c.req.param("cheerId"), groupId: c.req.param("id"), senderId: user.id } });
  return c.json({ status: "removed", group: await groupPayload(c.req.param("id"), user.id, true) });
});

router.put("/:id/calendar", zValidator("json", calendarSchema), async (c) => {
  const user = await requireGroupUser(c);
  if (user instanceof Response) return user;
  await assertGroupMember(c.req.param("id"), user.id);
  const socialGroup = await getPrismaClient().socialGroup.findFirst({ where: { id: c.req.param("id"), lifecycle: { not: "archived" } } });
  if (!socialGroup || !["owner", "admin"].includes((await getPrismaClient().groupMember.findUnique({ where: { groupId_userId: { groupId: socialGroup.id, userId: user.id } }, select: { role: true } }))?.role ?? "")) return c.json({ error: "Group management access is required." }, 403);
  const value = c.req.valid("json");
  if (!validTimeZone(value.timeZone)) return c.json({ error: "A valid IANA time zone is required." }, 422);
  const currentWeek = value.apply === "now" ? await ensureCurrentWeek(getPrismaClient(), socialGroup.id, new Date()) : null;
  await getPrismaClient().socialGroup.update({ where: { id: socialGroup.id }, data: { resetWeekday: value.resetWeekday, timeZone: value.timeZone } });
  if (value.apply === "now") {
    const interval = groupWeekInterval(new Date(), value.resetWeekday, value.timeZone);
    await getPrismaClient().groupWeek.update({
      where: { id: currentWeek!.id },
      data: { startsAt: interval.startsAt, endsAt: interval.endsAt, resetWeekday: value.resetWeekday, timeZone: value.timeZone },
    });
    const activities = await getPrismaClient().activity.findMany({ where: { userId: { in: (await getPrismaClient().groupMember.findMany({ where: { groupId: socialGroup.id, status: "active" }, select: { userId: true } })).map((member) => member.userId) }, deletedAt: null, startedAt: { gte: new Date(Date.now() - 8 * 86400000) } }, select: { id: true, userId: true } });
    for (const activity of activities) await reconcileActivityToGroups(activity.userId, activity.id);
  }
  return c.json(await groupPayload(socialGroup.id, user.id, true));
});

router.put("/:id/notifications", zValidator("json", z.object({ muted: z.boolean() })), async (c) => {
  const user = await requireGroupUser(c);
  if (user instanceof Response) return user;
  await assertGroupMember(c.req.param("id"), user.id);
  await getPrismaClient().groupMember.update({ where: { groupId_userId: { groupId: c.req.param("id"), userId: user.id } }, data: { notificationMuted: c.req.valid("json").muted } });
  return c.json(await groupPayload(c.req.param("id"), user.id, true));
});

router.post("/:id/transfer", zValidator("json", transferSchema), async (c) => {
  const user = await requireGroupUser(c);
  if (user instanceof Response) return user;
  try {
    await assertGroupMember(c.req.param("id"), user.id);
    const socialGroup = await getPrismaClient().socialGroup.findFirst({ where: { id: c.req.param("id"), ownerId: user.id, lifecycle: { not: "archived" } } });
    if (!socialGroup) return c.json({ error: "Owner access is required." }, 403);
    await transferGroupOwnership(socialGroup.id, user.id, c.req.valid("json").recipientUserId);
    await notify(c.req.valid("json").recipientUserId, user.id, "groupOwnershipTransferred", socialGroup.id, `${user.displayName} transferred Group ownership.`, socialGroup.id, false);
    return c.json(await groupPayload(socialGroup.id, user.id, true));
  } catch (error) { return groupError(c, error); }
});

router.post("/:id/leave", async (c) => {
  const user = await requireGroupUser(c);
  if (user instanceof Response) return user;
  const member = await assertGroupMember(c.req.param("id"), user.id);
  if (member?.role === "owner") return c.json({ error: "Transfer ownership or archive the Group before leaving." }, 422);
  await getPrismaClient().groupMember.update({ where: { groupId_userId: { groupId: c.req.param("id"), userId: user.id } }, data: { status: "left" } });
  await normalizeGroupAfterMembershipChange(c.req.param("id"), user.id);
  return c.json({ ok: true });
});

router.delete("/:id/members/:memberUserId", async (c) => {
  const user = await requireGroupUser(c);
  if (user instanceof Response) return user;
  await assertGroupMember(c.req.param("id"), user.id);
  const socialGroup = await getPrismaClient().socialGroup.findFirst({ where: { id: c.req.param("id"), lifecycle: { not: "archived" } } });
  const actingRole = socialGroup ? (await getPrismaClient().groupMember.findUnique({ where: { groupId_userId: { groupId: socialGroup.id, userId: user.id } }, select: { role: true } }))?.role : null;
  if (!socialGroup || !["owner", "admin"].includes(actingRole ?? "")) return c.json({ error: "Group management access is required." }, 403);
  if (c.req.param("memberUserId") === user.id) return c.json({ error: "Transfer ownership before removing yourself." }, 422);
  const target = await getPrismaClient().groupMember.findUnique({ where: { groupId_userId: { groupId: socialGroup.id, userId: c.req.param("memberUserId") } }, select: { role: true, status: true } });
  if (!target || target.status !== "active") return c.json({ error: "Member not found." }, 404);
  if (target.role === "owner" || (actingRole === "admin" && target.role === "admin")) return c.json({ error: "That member cannot be removed by this role." }, 403);
  await getPrismaClient().groupMember.update({ where: { groupId_userId: { groupId: socialGroup.id, userId: c.req.param("memberUserId") } }, data: { status: "removed", removedAt: new Date() } });
  await normalizeGroupAfterMembershipChange(socialGroup.id, c.req.param("memberUserId"));
  return c.json(await groupPayload(socialGroup.id, user.id, true));
});

router.patch("/:id/members/:memberUserId/role", zValidator("json", roleSchema), async (c) => {
  const user = await requireGroupUser(c);
  if (user instanceof Response) return user;
  const member = await assertGroupMember(c.req.param("id"), user.id);
  if (!member || member.role !== "owner") return c.json({ error: "Only the owner can change roles." }, 403);
  if (c.req.param("memberUserId") === user.id) return c.json({ error: "The owner role cannot be changed here." }, 422);
  const target = await getPrismaClient().groupMember.findUnique({ where: { groupId_userId: { groupId: c.req.param("id"), userId: c.req.param("memberUserId") } } });
  if (!target || target.status !== "active") return c.json({ error: "Member not found." }, 404);
  await getPrismaClient().groupMember.update({ where: { id: target.id }, data: { role: c.req.valid("json").role } });
  return c.json(await groupPayload(c.req.param("id"), user.id, true));
});

router.get("/:id/notices", async (c) => {
  const user = await requireGroupUser(c);
  if (user instanceof Response) return user;
  await assertGroupMember(c.req.param("id"), user.id);
  const notices = await getPrismaClient().groupNotice.findMany({ where: { groupId: c.req.param("id"), deletedAt: null }, select: { id: true, title: true, body: true, activityEventId: true, pinned: true, publishedAt: true, editedAt: true }, orderBy: [{ pinned: "desc" }, { publishedAt: "desc" }], take: 50 });
  return c.json({ notices });
});

router.post("/:id/notices", zValidator("json", noticeSchema), async (c) => {
  const user = await requireGroupUser(c);
  if (user instanceof Response) return user;
  const member = await assertGroupMember(c.req.param("id"), user.id);
  if (!member || !["owner", "admin"].includes(member.role)) return c.json({ error: "Group management access is required." }, 403);
  const group = await getPrismaClient().socialGroup.findUnique({ where: { id: c.req.param("id") }, select: { noticesEnabled: true, lifecycle: true } });
  if (!group?.noticesEnabled) return c.json({ error: "Notices are not enabled for this Group." }, 422);
  if (group.lifecycle === "archived") return c.json({ error: "Archived Groups cannot publish notices." }, 409);
  const noticeInput = c.req.valid("json");
  if (noticeInput.activityEventId) {
    const event = await getPrismaClient().activityEvent.findFirst({ where: { id: noticeInput.activityEventId, groupId: c.req.param("id") }, select: { id: true } });
    if (!event) return c.json({ error: "The referenced activity does not belong to this Group." }, 422);
  }
  const notice = await getPrismaClient().groupNotice.create({ data: { groupId: c.req.param("id"), authorId: user.id, ...noticeInput } });
  return c.json({ notice, group: await groupPayload(c.req.param("id"), user.id, true) }, 201);
});

router.patch("/:id/notices/:noticeId", zValidator("json", noticeSchema.partial()), async (c) => {
  const user = await requireGroupUser(c);
  if (user instanceof Response) return user;
  const member = await assertGroupMember(c.req.param("id"), user.id);
  if (!member || !["owner", "admin"].includes(member.role)) return c.json({ error: "Group management access is required." }, 403);
  const notice = await getPrismaClient().groupNotice.updateMany({ where: { id: c.req.param("noticeId"), groupId: c.req.param("id"), deletedAt: null }, data: { ...c.req.valid("json"), editedAt: new Date() } });
  if (!notice.count) return c.json({ error: "Notice not found." }, 404);
  return c.json({ group: await groupPayload(c.req.param("id"), user.id, true) });
});

router.delete("/:id/notices/:noticeId", async (c) => {
  const user = await requireGroupUser(c);
  if (user instanceof Response) return user;
  const member = await assertGroupMember(c.req.param("id"), user.id);
  if (!member || !["owner", "admin"].includes(member.role)) return c.json({ error: "Group management access is required." }, 403);
  await getPrismaClient().groupNotice.updateMany({ where: { id: c.req.param("noticeId"), groupId: c.req.param("id"), deletedAt: null }, data: { deletedAt: new Date() } });
  return c.json({ group: await groupPayload(c.req.param("id"), user.id, true) });
});

router.post("/:id/notices/read", async (c) => {
  const user = await requireGroupUser(c);
  if (user instanceof Response) return user;
  await assertGroupMember(c.req.param("id"), user.id);
  const latest = await getPrismaClient().groupNotice.findFirst({ where: { groupId: c.req.param("id"), deletedAt: null }, orderBy: { publishedAt: "desc" }, select: { id: true } });
  await getPrismaClient().groupNoticeRead.upsert({ where: { groupId_userId: { groupId: c.req.param("id"), userId: user.id } }, create: { groupId: c.req.param("id"), userId: user.id, lastSeenNoticeId: latest?.id }, update: { lastSeenNoticeId: latest?.id } });
  return c.json({ group: await groupPayload(c.req.param("id"), user.id, true) });
});

router.post("/:id/invite-links", async (c) => {
  const user = await requireGroupUser(c);
  if (user instanceof Response) return user;
  const member = await assertGroupMember(c.req.param("id"), user.id);
  if (!member || !["owner", "admin"].includes(member.role)) return c.json({ error: "Group management access is required." }, 403);
  const group = await getPrismaClient().socialGroup.findUnique({ where: { id: c.req.param("id") }, select: { id: true, lifecycle: true, joinPolicy: true, visibility: true } });
  if (!group || group.lifecycle === "archived") return c.json({ error: "Archived Groups cannot create invite links." }, 409);
  const rawToken = randomBytes(32).toString("base64url");
  const link = await getPrismaClient().groupInviteLink.create({ data: { groupId: group.id, creatorId: user.id, tokenDigest: createHash("sha256").update(rawToken).digest("hex"), expiresAt: new Date(Date.now() + 30 * 86400000) } });
  return c.json({ id: link.id, token: rawToken, expiresAt: link.expiresAt, url: `https://plainstride.ai/invite/group/${rawToken}` }, 201);
});

router.delete("/:id/invite-links/:linkId", async (c) => {
  const user = await requireGroupUser(c);
  if (user instanceof Response) return user;
  const member = await assertGroupMember(c.req.param("id"), user.id);
  if (!member || !["owner", "admin"].includes(member.role)) return c.json({ error: "Group management access is required." }, 403);
  await getPrismaClient().groupInviteLink.updateMany({ where: { id: c.req.param("linkId"), groupId: c.req.param("id"), revokedAt: null }, data: { revokedAt: new Date() } });
  return c.json({ group: await groupPayload(c.req.param("id"), user.id, true) });
});

router.post("/:id/archive", async (c) => {
  const user = await requireGroupUser(c);
  if (user instanceof Response) return user;
  await assertGroupMember(c.req.param("id"), user.id);
  const result = await getPrismaClient().socialGroup.updateMany({ where: { id: c.req.param("id"), ownerId: user.id, lifecycle: { not: "archived" } }, data: { lifecycle: "archived" } });
  if (!result.count) return c.json({ error: "Group not found." }, 404);
  return c.json(await groupPayload(c.req.param("id"), user.id, true));
});

router.post("/:id/weeks/:weekId/presentation", async (c) => {
  const user = await requireGroupUser(c);
  if (user instanceof Response) return user;
  try {
    await assertGroupMember(c.req.param("id"), user.id);
    const result = await getPrismaClient().groupWeekPresentation.updateMany({ where: { weekId: c.req.param("weekId"), userId: user.id, presentedAt: null, week: { groupId: c.req.param("id"), state: "completed" } }, data: { presentedAt: new Date() } });
    return c.json({ presented: result.count > 0 });
  } catch (error) { return groupError(c, error); }
});

router.post("/:id/reactivate", async (c) => {
  const user = await requireGroupUser(c);
  if (user instanceof Response) return user;
  await assertGroupMember(c.req.param("id"), user.id);
  const activeCount = await getPrismaClient().groupMember.count({ where: { groupId: c.req.param("id"), status: "active" } });
  const result = await getPrismaClient().socialGroup.updateMany({ where: { id: c.req.param("id"), ownerId: user.id, lifecycle: "archived" }, data: { lifecycle: activeCount >= 2 ? "active" : "awaiting_members" } });
  if (!result.count) return c.json({ error: "Group not found." }, 404);
  return c.json(await groupPayload(c.req.param("id"), user.id, true));
});

async function requireGroupUser(c: Context<AppEnv>) {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c);
  return user ?? c.json({ error: "Authentication is required." }, 401);
}

function groupError(c: Context<AppEnv>, error: unknown) {
  if (error instanceof GroupDomainError) return c.json({ error: error.message, code: error.code }, error.code === "not_a_member" ? 403 : 409);
  console.error("[socialGroup] request failed", error);
  return c.json({ error: "Group operation failed." }, 500);
}

router.onError((error, c) => groupError(c, error));

async function notify(recipientId: string, actorId: string, type: string, objectId: string, message: string, groupId?: string, respectMute = true, dedupeReference = objectId) {
  if (respectMute && groupId) {
    const member = await getPrismaClient().groupMember.findUnique({ where: { groupId_userId: { groupId, userId: recipientId } }, select: { notificationMuted: true, status: true } });
    if (member?.status === "active" && member.notificationMuted) return;
  }
  const dedupeKey = `${type}:${dedupeReference}:${recipientId}`;
  await getPrismaClient().socialNotification.upsert({ where: { dedupeKey }, create: { recipientId, actorId, type, objectId, message, dedupeKey }, update: { message } });
}

async function normalizeGroupAfterMembershipChange(groupId: string, departingUserId: string) {
  const prisma = getPrismaClient();
  const activeCount = await prisma.groupMember.count({ where: { groupId, status: "active" } });
  await prisma.socialGroup.updateMany({ where: { id: groupId, lifecycle: { not: "archived" } }, data: { lifecycle: activeCount >= 2 ? "active" : "awaiting_members" } });
}

function normalizeSearchName(value: string) {
  return value.trim().normalize("NFKC").toLocaleLowerCase().replace(/\s+/g, " ");
}

export default router;
