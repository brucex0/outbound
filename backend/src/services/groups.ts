import { Prisma } from "@prisma/client";
import { getPrismaClient } from "./prisma.js";
import type { SupportedLocale } from "../middleware/locale.js";
import { compactPerson } from "./apiAssetURLs.js";

export const GROUP_MEMBER_LIMIT_DEFAULT = 6;
export const GROUP_MEMBER_LIMIT_MAXIMUM = 100;
const shareSafeMemberSelect = { id: true, displayName: true, avatarUrl: true } as const;

export function configuredGroupMemberLimit(env: NodeJS.ProcessEnv = process.env) {
  const raw = env.GROUP_MEMBER_LIMIT?.trim();
  if (!raw) return GROUP_MEMBER_LIMIT_DEFAULT;
  const value = Number(raw);
  if (!Number.isInteger(value) || value < 2 || value > GROUP_MEMBER_LIMIT_MAXIMUM) {
    throw new Error(`GROUP_MEMBER_LIMIT must be an integer from 2 to ${GROUP_MEMBER_LIMIT_MAXIMUM}.`);
  }
  return value;
}

export type GroupInput = {
  template?: "motivation" | "activities";
  name?: string;
  description?: string | null;
  city?: string | null;
  activityInterests?: string[];
  memberUserIds: string[];
  timeZone?: string;
  resetWeekday?: number;
  locale?: SupportedLocale;
  idempotencyKey?: string;
};

export type GroupContributionSummary = {
  groupId: string;
  groupName: string;
  weekId: string;
  contributedCount: number;
  targetCount: number | null;
  focusMode: string;
  memberCount: number;
  completed: boolean;
};

export function blockedPairWhere(userId: string, otherUserId: string) {
  return { OR: [{ blockerId: userId, blockedId: otherUserId }, { blockerId: otherUserId, blockedId: userId }] };
}

export async function assertAcceptedConnection(userId: string, otherUserId: string) {
  if (userId === otherUserId) return;
  const prisma = getPrismaClient();
  const [connection, block] = await Promise.all([
    prisma.connection.findFirst({ where: { status: "accepted", OR: [{ requesterId: userId, addresseeId: otherUserId }, { requesterId: otherUserId, addresseeId: userId }] } }),
    prisma.socialBlock.findFirst({ where: blockedPairWhere(userId, otherUserId) }),
  ]);
  if (!connection) throw new GroupDomainError("accepted_connection_required", "Group members must be accepted connections.");
  if (block) throw new GroupDomainError("blocked", "This person is unavailable.");
}

export async function assertNoBlockedPair(userId: string, otherUserId: string) {
  if (userId === otherUserId) return;
  const block = await getPrismaClient().socialBlock.findFirst({ where: blockedPairWhere(userId, otherUserId), select: { id: true } });
  if (block) throw new GroupDomainError("blocked", "This person is unavailable.");
}

export async function assertGroupMember(groupId: string, userId: string, allowPending = false) {
  const prisma = getPrismaClient();
  const member = await prisma.groupMember.findUnique({ where: { groupId_userId: { groupId, userId } }, include: { group: true, user: { select: shareSafeMemberSelect } } });
  if (member?.status === "active") {
    await assertNoBlockedGroupMember(groupId, userId);
    return member;
  }
  if (allowPending) {
    const invitation = await prisma.groupInvitation.findFirst({ where: { groupId, recipientId: userId, status: "pending", OR: [{ expiresAt: null }, { expiresAt: { gt: new Date() } }] } });
    if (invitation) return null;
  }
  throw new GroupDomainError("not_a_member", "Group membership is required.");
}

export async function assertNoBlockedGroupMember(groupId: string, userId: string) {
  const prisma = getPrismaClient();
  const activeMembers = await prisma.groupMember.findMany({ where: { groupId, status: "active", userId: { not: userId } }, select: { userId: true } });
  if (!activeMembers.length) return;
  const block = await prisma.socialBlock.findFirst({ where: { OR: activeMembers.flatMap((active) => blockedPairWhere(userId, active.userId).OR) } });
  if (block) throw new GroupDomainError("blocked", "This Group is unavailable.");
}

export async function createGroup(ownerId: string, input: GroupInput) {
  const template = input.template ?? "motivation";
  const memberLimit = template === "motivation" ? configuredGroupMemberLimit() : 100;
  const memberIds = [...new Set(input.memberUserIds.filter((id) => id !== ownerId))];
  if (template === "motivation" && memberIds.length === 0) throw new GroupDomainError("members_required", "Choose at least one accepted connection.");
  if (memberIds.length > memberLimit - 1) throw new GroupDomainError("capacity", "That is more people than this Group can currently include.");
  const timeZone = validTimeZone(input.timeZone) ? input.timeZone! : Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
  const resetWeekday = boundedWeekday(input.resetWeekday ?? 1);
  const prisma = getPrismaClient();
  const name = input.name?.trim().slice(0, 80) || "Your Group";
  if (template === "activities" && !input.name?.trim()) throw new GroupDomainError("name_required", "A community Group needs a name.");
  if (input.idempotencyKey) {
    const existing = await prisma.socialGroup.findUnique({ where: { creationIdempotencyKey: input.idempotencyKey } });
    if (existing) return existing.id;
  }
  for (const memberId of memberIds) {
    if (template === "motivation") await assertAcceptedConnection(ownerId, memberId);
    else await assertNoBlockedPair(ownerId, memberId);
  }
  return prisma.$transaction(async (tx) => {
    const owner = await tx.user.findUniqueOrThrow({ where: { id: ownerId }, select: { displayName: true, avatarUrl: true } });
    const selected = await tx.user.findMany({ where: { id: { in: memberIds } }, select: { id: true, displayName: true } });
    const resolvedName = input.name?.trim() ? name : generatedGroupName([owner.displayName, ...selected.map((m) => m.displayName)], input.locale ?? "en");
    const socialGroup = await tx.socialGroup.create({
      data: {
        ownerId,
        creationIdempotencyKey: input.idempotencyKey ?? null,
        name: resolvedName,
        normalizedName: normalizeGroupName(resolvedName),
        description: input.description?.trim() || null,
        city: input.city?.trim() || null,
        activityInterests: input.activityInterests ?? [],
        trustPolicy: template === "motivation" ? "trusted_private" : "community",
        visibility: template === "motivation" ? "private" : "unlisted",
        joinPolicy: template === "motivation" ? "invite_only" : "request",
        lifecycle: "active",
        memberLimit,
        weeklyThemeEnabled: template === "motivation",
        workoutContributionsEnabled: template === "motivation",
        presetCheersEnabled: template === "motivation",
        noticesEnabled: template === "activities",
        scheduledActivitiesEnabled: true,
        memberActivityCreation: template === "motivation",
        defaultFocusMode: template === "motivation" ? "personal_targets" : "none",
        resetWeekday, timeZone,
        members: { create: { userId: ownerId, role: "owner", displayNameSnapshot: owner.displayName, avatarUrlSnapshot: owner.avatarUrl } },
      },
    });
    await tx.groupInvitation.createMany({
      data: memberIds.map((recipientId) => ({ groupId: socialGroup.id, senderId: ownerId, recipientId, idempotencyKey: crypto.randomUUID(), expiresAt: new Date(Date.now() + 7 * 86400000) })),
      skipDuplicates: true,
    });
    if (template === "motivation") await ensureCurrentWeek(tx, socialGroup.id, new Date());
    return socialGroup.id;
  });
}

export async function ensureCurrentWeek(tx: Prisma.TransactionClient, groupId: string, now: Date) {
  const socialGroup = await tx.socialGroup.findUniqueOrThrow({ where: { id: groupId }, select: { resetWeekday: true, timeZone: true, defaultFocusMode: true, defaultFocusConfigured: true, defaultTarget: true, defaultThemeKey: true, defaultThemeTitle: true, defaultThemeNote: true } });
  const interval = groupWeekInterval(now, socialGroup.resetWeekday, socialGroup.timeZone);
  return tx.groupWeek.upsert({
    where: { groupId_startsAt: { groupId, startsAt: interval.startsAt } },
    create: { groupId, startsAt: interval.startsAt, endsAt: interval.endsAt, timeZone: socialGroup.timeZone, resetWeekday: socialGroup.resetWeekday, focusMode: socialGroup.defaultFocusMode, focusConfigured: socialGroup.defaultFocusConfigured, sharedTarget: socialGroup.defaultTarget, themeKey: socialGroup.defaultThemeKey, themeTitle: socialGroup.defaultThemeTitle, themeNote: socialGroup.defaultThemeNote },
    update: {},
  });
}

export async function reconcileActivityToGroups(userId: string, activityId: string, deleted = false) {
    const prisma = getPrismaClient();
    const activity = await prisma.activity.findFirst({ where: { id: activityId, userId }, select: { id: true, type: true, startedAt: true, deletedAt: true } });
    if (!activity) return [];

    const existing = await prisma.groupContribution.findMany({
      where: { activityId: activity.id },
      select: { weekId: true, week: { select: { groupId: true } } },
    });
    const candidateMemberships = deleted || activity.deletedAt
      ? []
      : await prisma.groupMember.findMany({
          where: { userId, status: "active", joinedAt: { lte: activity.startedAt }, group: { lifecycle: { not: "archived" }, trustPolicy: "trusted_private", workoutContributionsEnabled: true } },
          include: { group: { select: { id: true, resetWeekday: true, timeZone: true, defaultFocusMode: true, defaultFocusConfigured: true, defaultTarget: true, defaultThemeKey: true, defaultThemeTitle: true, defaultThemeNote: true } } },
        });
    const memberships = (await Promise.all(candidateMemberships.map(async (membership) => {
      try {
        await assertNoBlockedGroupMember(membership.group.id, userId);
        return membership;
      } catch {
        return null;
      }
    }))).filter((membership): membership is NonNullable<typeof membership> => membership != null);

    const affectedGroupIds = new Set<string>();
    await prisma.$transaction(async (tx) => {
      await tx.groupContribution.deleteMany({ where: { activityId: activity.id } });
      for (const membership of memberships) {
        affectedGroupIds.add(membership.group.id);
        const interval = groupWeekInterval(activity.startedAt, membership.group.resetWeekday, membership.group.timeZone);
        const week = await tx.groupWeek.upsert({
          where: { groupId_startsAt: { groupId: membership.group.id, startsAt: interval.startsAt } },
          create: { groupId: membership.group.id, startsAt: interval.startsAt, endsAt: interval.endsAt, timeZone: membership.group.timeZone, resetWeekday: membership.group.resetWeekday, focusMode: membership.group.defaultFocusMode, focusConfigured: membership.group.defaultFocusConfigured, sharedTarget: membership.group.defaultTarget, themeKey: membership.group.defaultThemeKey, themeTitle: membership.group.defaultThemeTitle, themeNote: membership.group.defaultThemeNote },
          update: {},
        });
        await tx.groupContribution.createMany({ data: [{ weekId: week.id, memberId: membership.id, activityId: activity.id }], skipDuplicates: true });
        await refreshWeekState(tx, week.id);
      }
      for (const oldWeek of existing) {
        affectedGroupIds.add(oldWeek.week.groupId);
        if (!memberships.some((membership) => membership.group.id === oldWeek.week.groupId)) {
          await refreshWeekState(tx, oldWeek.weekId);
        }
      }
    });
    if (deleted || activity.deletedAt) return [];
    const summaries = await Promise.all([...affectedGroupIds].map(async (groupId): Promise<GroupContributionSummary | null> => {
      const payload: any = await groupPayload(groupId, userId);
      if (!payload) return null;
      return {
        groupId,
        groupName: payload.name,
        weekId: payload.week.id,
        contributedCount: payload.week.contributedCount,
        targetCount: payload.week.targetCount,
        focusMode: payload.week.focusMode,
        memberCount: payload.memberCount,
        completed: payload.week.state === "completed",
      };
    }));
    return summaries.filter((summary): summary is GroupContributionSummary => summary != null);
}

export async function transferGroupOwnership(groupId: string, ownerId: string, recipientUserId: string) {
  if (ownerId === recipientUserId) throw new GroupDomainError("invalid_owner", "Choose another active member.");
  const prisma = getPrismaClient();
  const group = await prisma.socialGroup.findUniqueOrThrow({ where: { id: groupId }, select: { trustPolicy: true } });
  if (group.trustPolicy === "trusted_private") await assertAcceptedConnection(ownerId, recipientUserId);
  return prisma.$transaction(async (tx) => {
    const recipient = await tx.groupMember.findUnique({ where: { groupId_userId: { groupId, userId: recipientUserId } } });
    const current = await tx.groupMember.findUnique({ where: { groupId_userId: { groupId, userId: ownerId } } });
    if (current?.role !== "owner" || recipient?.status !== "active") throw new GroupDomainError("owner_access_required", "Only the owner can transfer ownership to an active member.");
    await tx.groupMember.update({ where: { id: current.id }, data: { role: "member" } });
    await tx.groupMember.update({ where: { id: recipient.id }, data: { role: "owner" } });
    return tx.socialGroup.update({ where: { id: groupId }, data: { ownerId: recipientUserId } });
  });
}

export async function refreshWeekState(tx: Prisma.TransactionClient, weekId: string) {
  const week = await tx.groupWeek.findUniqueOrThrow({ where: { id: weekId }, include: { commitments: true, contributions: true, group: { select: { lifecycle: true, name: true } } } });
  if (!week.focusConfigured || week.focusMode === "none" || week.focusMode === "theme") {
    if (week.state === "completed") return tx.groupWeek.update({ where: { id: week.id }, data: { state: "open", completedAt: null } });
    return week;
  }
  const qualifying = week.focusMode === "shared_target"
    ? week.sharedTarget
    : week.commitments.filter((c) => !c.skipped && c.targetCount != null).reduce((sum, c) => sum + (c.targetCount ?? 0), 0);
  const progress = week.contributions.length;
  if (qualifying && progress >= qualifying && week.state !== "completed") {
    const completed = await tx.groupWeek.update({ where: { id: week.id }, data: { state: "completed", completedAt: new Date() } });
    const members = await tx.groupMember.findMany({ where: { groupId: week.groupId, status: "active" }, select: { userId: true } });
    await tx.groupWeekPresentation.createMany({ data: members.map((member) => ({ weekId: week.id, userId: member.userId })), skipDuplicates: true });
    for (const member of members) {
      const muted = await tx.groupMember.findUnique({ where: { groupId_userId: { groupId: week.groupId, userId: member.userId } }, select: { notificationMuted: true } });
      if (muted?.notificationMuted) continue;
      const dedupeKey = `socialGroup-week-completed:${week.id}:${member.userId}`;
      await tx.socialNotification.upsert({
        where: { dedupeKey },
        create: { recipientId: member.userId, type: "groupWeeklyGoalCompleted", objectId: week.groupId, message: `${week.group.name} completed this week’s focus.`, dedupeKey },
        update: {},
      });
    }
    return completed;
  }
  if (week.state === "completed" && progress < (qualifying ?? Number.MAX_SAFE_INTEGER)) {
    return tx.groupWeek.update({ where: { id: week.id }, data: { state: "open", completedAt: null } });
  }
  return week;
}

export async function groupPayload(groupId: string, viewerId: string, includeHistory = false) {
  const prisma = getPrismaClient();
  const socialGroup = await prisma.socialGroup.findUnique({ where: { id: groupId }, include: { owner: { select: shareSafeMemberSelect }, members: { where: { status: "active" }, include: { user: { select: shareSafeMemberSelect } }, orderBy: { joinedAt: "asc" } } } });
  if (!socialGroup) return null;
  if (socialGroup.trustPolicy === "community") return communityGroupPayload(socialGroup, viewerId);
  const week = await ensureCurrentWeek(prisma, socialGroup.id, new Date());
  const [commitments, history, cheers, viewerMembership, completionPresentation, invitations, activityEvents] = await Promise.all([
    prisma.groupCommitment.findMany({ where: { weekId: week.id } }),
    includeHistory ? prisma.groupWeek.findMany({ where: { groupId, startsAt: { lt: week.startsAt } }, orderBy: { startsAt: "desc" }, take: 12 }) : Promise.resolve([]),
    prisma.groupCheer.findMany({ where: { groupId, weekId: week.id }, orderBy: { createdAt: "desc" }, take: 30 }),
    prisma.groupMember.findUnique({ where: { groupId_userId: { groupId, userId: viewerId } }, select: { notificationMuted: true } }),
    prisma.groupWeekPresentation.findUnique({ where: { weekId_userId: { weekId: week.id, userId: viewerId } }, select: { presentedAt: true } }),
    socialGroup.ownerId === viewerId ? prisma.groupInvitation.findMany({ where: { groupId, status: "pending", OR: [{ expiresAt: null }, { expiresAt: { gt: new Date() } }] }, include: { sender: { select: shareSafeMemberSelect }, recipient: { select: shareSafeMemberSelect }, group: { select: { id: true, name: true } } }, orderBy: { createdAt: "desc" } }) : Promise.resolve([]),
    prisma.activityEvent.findMany({
      where: {
        groupId,
        status: { in: ["scheduled", "active", "reconciling", "completed"] },
        OR: [
          { participants: { some: { userId: viewerId, status: "going" } } },
          { invitations: { some: { recipientId: viewerId, status: { in: ["pending", "accepted"] } } } },
        ],
      },
      select: {
        id: true,
        creatorId: true,
        title: true,
        startsAt: true,
        endsAt: true,
        locationName: true,
        note: true,
        status: true,
        creator: { select: shareSafeMemberSelect },
        participants: { where: { status: "going" }, select: { userId: true } },
      },
      orderBy: { startsAt: "desc" },
      take: 10,
    }),
  ]);
  const contributions = await prisma.groupContribution.findMany({
    where: { weekId: week.id },
    select: {
      memberId: true,
      activity: {
        select: {
          type: true,
          title: true,
          startedAt: true,
          durationSecs: true,
          distanceM: true,
          elevationM: true,
          avgPace: true,
          avgHeartRate: true,
          energyKilocalories: true,
          companionType: true,
        },
      },
    },
    orderBy: { activity: { startedAt: "desc" } },
  });
  const counts = new Map<string, number>();
  for (const contribution of contributions) counts.set(contribution.memberId, (counts.get(contribution.memberId) ?? 0) + 1);
  const activeCount = socialGroup.members.length;
  const payload = {
    id: socialGroup.id,
    name: socialGroup.name,
    lifecycle: socialGroup.lifecycle,
    role: socialGroup.members.find((m) => m.userId === viewerId)?.role ?? null,
    owner: socialGroup.owner ? compactPerson(socialGroup.owner) : null,
    normalizedName: socialGroup.normalizedName,
    description: socialGroup.description,
    city: socialGroup.city,
    activityInterests: socialGroup.activityInterests ?? [],
    trustPolicy: socialGroup.trustPolicy,
    visibility: socialGroup.visibility,
    joinPolicy: socialGroup.joinPolicy,
    featured: socialGroup.featured,
    organizationVerificationState: socialGroup.organizationVerificationState,
    capabilities: {
      weeklyTheme: socialGroup.weeklyThemeEnabled,
      workoutContributions: socialGroup.workoutContributionsEnabled,
      presetCheers: socialGroup.presetCheersEnabled,
      notices: socialGroup.noticesEnabled,
      scheduledActivities: socialGroup.scheduledActivitiesEnabled,
    },
    resetWeekday: socialGroup.resetWeekday,
    timeZone: socialGroup.timeZone,
    memberLimit: socialGroup.memberLimit,
    memberCount: activeCount,
    eligibleForToday: activeCount >= 2 && socialGroup.lifecycle === "active",
    members: socialGroup.members.map((member) => {
      const commitment = commitments.find((item) => item.memberId === member.id);
      return {
        id: member.id,
        user: compactPerson(member.user),
        role: member.role,
        isCurrentUser: member.userId === viewerId,
        commitment: commitment ? { targetCount: commitment.targetCount, skipped: commitment.skipped } : null,
        contributedCount: counts.get(member.id) ?? 0,
        recentActivity: contributions.find((contribution) => contribution.memberId === member.id)?.activity ?? null,
      };
    }),
    upcomingFocus: { mode: socialGroup.defaultFocusMode, focusConfigured: socialGroup.defaultFocusConfigured, sharedTarget: socialGroup.defaultTarget, themeKey: socialGroup.defaultThemeKey, themeTitle: socialGroup.defaultThemeTitle, themeNote: socialGroup.defaultThemeNote },
    week: { id: week.id, startsAt: week.startsAt, endsAt: week.endsAt, focusMode: week.focusMode, focusConfigured: week.focusConfigured, sharedTarget: week.sharedTarget, themeKey: week.themeKey, themeTitle: week.themeTitle, themeNote: week.themeNote, state: week.state, contributedCount: contributions.length, targetCount: !week.focusConfigured || week.focusMode === "theme" ? null : week.focusMode === "shared_target" ? week.sharedTarget : commitments.filter((c) => !c.skipped).reduce((sum, c) => sum + (c.targetCount ?? 0), 0) || null },
    currentUserMuted: viewerMembership?.notificationMuted ?? false,
    completionPresentationPending: week.state === "completed" && completionPresentation != null && completionPresentation.presentedAt == null,
    cheers: cheers.map((cheer) => ({ id: cheer.id, senderUserId: cheer.senderId, recipientUserId: cheer.recipientId, presetType: cheer.presetType, createdAt: cheer.createdAt })),
    invitations: invitations.map((invitation) => ({ id: invitation.id, groupId: invitation.groupId, group: invitation.group, sender: compactPerson(invitation.sender), recipient: compactPerson(invitation.recipient), status: invitation.status, createdAt: invitation.createdAt, expiresAt: invitation.expiresAt })),
    upcomingActivities: activityEvents
      .filter((event) => ["scheduled", "active"].includes(event.status))
      .sort((a, b) => a.startsAt.getTime() - b.startsAt.getTime())
      .map((event) => ({
        id: event.id,
        title: event.title,
        startsAt: event.startsAt,
        endsAt: event.endsAt,
        locationName: event.locationName,
        paceNote: event.note,
        status: event.status,
        creator: compactPerson(event.creator),
        attendeeCount: event.participants.length,
        currentUserGoing: event.participants.some((participant) => participant.userId === viewerId),
        currentUserRole: event.creatorId === viewerId
          ? "owner"
          : event.participants.some((participant) => participant.userId === viewerId)
            ? "participant"
            : "viewer",
      })),
    recentMoments: [
      ...(week.state === "completed" && week.completedAt ? [{ id: `completion:${week.id}`, type: "weekly_completion", createdAt: week.completedAt, title: null }] : []),
      ...cheers.map((cheer) => ({ id: `cheer:${cheer.id}`, type: "cheer", createdAt: cheer.createdAt, title: cheer.presetType })),
      ...activityEvents
        .filter((event) => ["reconciling", "completed"].includes(event.status))
        .map((event) => ({ id: `event:${event.id}`, type: "completed_activity", createdAt: event.startsAt, title: event.title })),
    ].sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime()).slice(0, 10),
    history: includeHistory ? history.map((item) => ({ id: item.id, startsAt: item.startsAt, endsAt: item.endsAt, focusMode: item.focusMode, themeKey: item.themeKey, themeTitle: item.themeTitle, themeNote: item.themeNote, state: item.state })) : undefined,
  };
  return payload;
}

export function groupWeekInterval(date: Date, resetWeekday: number, timeZone: string) {
  const local = localDateParts(date, timeZone);
  const delta = (local.weekday - resetWeekday + 7) % 7;
  const startLocal = new Date(Date.UTC(local.year, local.month - 1, local.day - delta));
  const endLocal = new Date(Date.UTC(local.year, local.month - 1, local.day - delta + 7));
  const startsAt = zonedLocalToUTC(startLocal, timeZone);
  return { startsAt, endsAt: zonedLocalToUTC(endLocal, timeZone) };
}

function normalizeGroupName(value: string) {
  return value.trim().normalize("NFKC").toLocaleLowerCase().replace(/\s+/g, " ");
}

async function communityGroupPayload(group: any, viewerId: string) {
  const prisma = getPrismaClient();
  const viewerMember = group.members.find((member: any) => member.userId === viewerId) ?? null;
  const [notices, noticeRead, activities, pendingRequest] = await Promise.all([
    group.noticesEnabled
      ? prisma.groupNotice.findMany({ where: { groupId: group.id, deletedAt: null }, select: { id: true, title: true, body: true, activityEventId: true, pinned: true, publishedAt: true, editedAt: true }, orderBy: [{ pinned: "desc" }, { publishedAt: "desc" }], take: 30 })
      : Promise.resolve([]),
    viewerMember ? prisma.groupNoticeRead.findUnique({ where: { groupId_userId: { groupId: group.id, userId: viewerId } }, select: { lastSeenNoticeId: true } }) : Promise.resolve(null),
    group.scheduledActivitiesEnabled
      ? prisma.activityEvent.findMany({ where: { groupId: group.id, status: { in: ["scheduled", "active", "reconciling", "completed"] }, OR: [{ participants: { some: { userId: viewerId, status: "going" } } }, { invitations: { some: { recipientId: viewerId, status: { in: ["pending", "accepted"] } } } }, { visibility: "public" }] }, select: { id: true, title: true, startsAt: true, endsAt: true, locationName: true, status: true, activityType: true, creatorId: true, participants: { where: { status: "going" }, select: { userId: true, attendanceMode: true } } }, orderBy: { startsAt: "asc" }, take: 20 })
      : Promise.resolve([]),
    !viewerMember && group.joinPolicy === "request" ? prisma.groupJoinRequest.findUnique({ where: { groupId_requesterId: { groupId: group.id, requesterId: viewerId } }, select: { id: true, status: true } }) : Promise.resolve(null),
  ]);
  const latestNotice = notices[0] as any;
  const unread = Boolean(viewerMember && latestNotice && latestNotice.id !== noticeRead?.lastSeenNoticeId);
  return {
    id: group.id,
    name: group.name,
    normalizedName: group.normalizedName,
    description: group.description,
    city: group.city,
    activityInterests: group.activityInterests ?? [],
    trustPolicy: group.trustPolicy,
    visibility: group.visibility,
    joinPolicy: group.joinPolicy,
    lifecycle: group.lifecycle,
    featured: group.featured,
    organizationVerificationState: group.organizationVerificationState,
    capabilities: {
      weeklyTheme: false,
      workoutContributions: false,
      presetCheers: false,
      notices: group.noticesEnabled,
      scheduledActivities: group.scheduledActivitiesEnabled,
    },
    role: viewerMember?.role ?? null,
    owner: group.owner ? compactPerson(group.owner) : null,
    memberCount: group.members.length,
    memberLimit: group.memberLimit,
    currentUserMuted: viewerMember?.notificationMuted ?? false,
    unreadNoticeCount: unread ? 1 : 0,
    pendingRequest,
    members: viewerMember ? group.members.map((member: any) => ({ id: member.id, user: compactPerson(member.user), role: member.role, isCurrentUser: member.userId === viewerId })) : [],
    notices,
    upcomingActivities: activities.map((event: any) => ({ id: event.id, title: event.title, startsAt: event.startsAt, endsAt: event.endsAt, locationName: event.locationName, status: event.status, activityType: event.activityType, attendeeCount: event.participants.length, currentUserGoing: event.participants.some((participant: any) => participant.userId === viewerId) })),
    recentMoments: [],
  };
}

function localDateParts(date: Date, timeZone: string) {
  const parts = new Intl.DateTimeFormat("en-US", { timeZone, year: "numeric", month: "2-digit", day: "2-digit", weekday: "short" }).formatToParts(date);
  const get = (type: string) => Number(parts.find((part) => part.type === type)?.value ?? 0);
  const weekday = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].indexOf(parts.find((part) => part.type === "weekday")?.value ?? "Mon") + 1;
  return { year: get("year"), month: get("month"), day: get("day"), weekday };
}

function zonedLocalToUTC(localDate: Date, timeZone: string) {
  const target = Date.UTC(localDate.getUTCFullYear(), localDate.getUTCMonth(), localDate.getUTCDate(), 0, 0, 0);
  let guess = target;
  const formatter = new Intl.DateTimeFormat("en-US", { timeZone, year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit", hourCycle: "h23" });
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const parts = formatter.formatToParts(new Date(guess));
    const value = (type: string) => Number(parts.find((part) => part.type === type)?.value ?? 0);
    const rendered = Date.UTC(value("year"), value("month") - 1, value("day"), value("hour"), value("minute"), value("second"));
    guess += target - rendered;
  }
  return new Date(guess);
}

function generatedGroupName(names: string[], locale: SupportedLocale) {
  const firstNames = names.map((name) => name.trim().split(/\s+/)[0]).filter(Boolean).slice(0, 3);
  if (!firstNames.length) return locale === "es" ? "Tu grupo" : locale === "zh-Hans" ? "你的群组" : "Your Group";
  if (locale === "zh-Hans") return `${firstNames.join("、")}的群组`;
  if (locale === "es") return `Grupo de ${firstNames.join(", ")}`;
  return `${firstNames.join(", ")}’s Group`;
}

function boundedWeekday(value: number) { return Number.isInteger(value) && value >= 1 && value <= 7 ? value : 1; }
export function validTimeZone(value: string | undefined) { if (!value) return false; try { new Intl.DateTimeFormat("en-US", { timeZone: value }).format(); return true; } catch { return false; } }

export class GroupDomainError extends Error {
  constructor(public readonly code: string, message: string) { super(message); }
}
