import { Prisma } from "@prisma/client";
import { getPrismaClient } from "./prisma.js";
import type { SupportedLocale } from "../middleware/locale.js";

export const CIRCLE_MEMBER_LIMIT_DEFAULT = 6;
export const CIRCLE_MEMBER_LIMIT_MAXIMUM = 100;
const shareSafeMemberSelect = { id: true, displayName: true, avatarUrl: true } as const;

export function configuredCircleMemberLimit(env: NodeJS.ProcessEnv = process.env) {
  const raw = env.CIRCLE_MEMBER_LIMIT?.trim();
  if (!raw) return CIRCLE_MEMBER_LIMIT_DEFAULT;
  const value = Number(raw);
  if (!Number.isInteger(value) || value < 2 || value > CIRCLE_MEMBER_LIMIT_MAXIMUM) {
    throw new Error(`CIRCLE_MEMBER_LIMIT must be an integer from 2 to ${CIRCLE_MEMBER_LIMIT_MAXIMUM}.`);
  }
  return value;
}

export type CircleInput = {
  name?: string;
  memberUserIds: string[];
  timeZone?: string;
  resetWeekday?: number;
  locale?: SupportedLocale;
};

export type CircleContributionSummary = {
  circleId: string;
  circleName: string;
  weekId: string;
  contributedCount: number;
  targetCount: number | null;
  focusMode: string;
  memberCount: number;
  completed: boolean;
  primary: boolean;
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
  if (!connection) throw new CircleDomainError("accepted_connection_required", "Circle members must be accepted connections.");
  if (block) throw new CircleDomainError("blocked", "This person is unavailable.");
}

export async function assertCircleMember(circleId: string, userId: string, allowPending = false) {
  const prisma = getPrismaClient();
  const member = await prisma.circleMember.findUnique({ where: { circleId_userId: { circleId, userId } }, include: { circle: true, user: { select: shareSafeMemberSelect } } });
  if (member?.status === "active") {
    await assertNoBlockedCircleMember(circleId, userId);
    return member;
  }
  if (allowPending) {
    const invitation = await prisma.circleInvitation.findFirst({ where: { circleId, recipientId: userId, status: "pending", OR: [{ expiresAt: null }, { expiresAt: { gt: new Date() } }] } });
    if (invitation) return null;
  }
  throw new CircleDomainError("not_a_member", "Circle membership is required.");
}

export async function assertNoBlockedCircleMember(circleId: string, userId: string) {
  const prisma = getPrismaClient();
  const activeMembers = await prisma.circleMember.findMany({ where: { circleId, status: "active", userId: { not: userId } }, select: { userId: true } });
  if (!activeMembers.length) return;
  const block = await prisma.socialBlock.findFirst({ where: { OR: activeMembers.flatMap((active) => blockedPairWhere(userId, active.userId).OR) } });
  if (block) throw new CircleDomainError("blocked", "This Circle is unavailable.");
}

export async function createCircle(ownerId: string, input: CircleInput) {
  const memberLimit = configuredCircleMemberLimit();
  const memberIds = [...new Set(input.memberUserIds.filter((id) => id !== ownerId))];
  if (memberIds.length === 0) throw new CircleDomainError("members_required", "Choose at least one accepted connection.");
  if (memberIds.length > memberLimit - 1) throw new CircleDomainError("capacity", "That is more people than this Circle can currently include.");
  const timeZone = validTimeZone(input.timeZone) ? input.timeZone! : Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
  const resetWeekday = boundedWeekday(input.resetWeekday ?? 1);
  const prisma = getPrismaClient();
  const name = input.name?.trim().slice(0, 80) || "Your Circle";
  for (const memberId of memberIds) await assertAcceptedConnection(ownerId, memberId);
  return prisma.$transaction(async (tx) => {
    const owner = await tx.user.findUniqueOrThrow({ where: { id: ownerId }, select: { displayName: true, avatarUrl: true } });
    const selected = await tx.user.findMany({ where: { id: { in: memberIds } }, select: { id: true, displayName: true } });
    const resolvedName = input.name?.trim() ? name : generatedCircleName([owner.displayName, ...selected.map((m) => m.displayName)], input.locale ?? "en");
    const circle = await tx.circle.create({
      data: {
        ownerId, name: resolvedName, lifecycle: memberIds.length ? "awaiting_members" : "awaiting_members",
        memberLimit, resetWeekday, timeZone,
        members: { create: { userId: ownerId, role: "owner", displayNameSnapshot: owner.displayName, avatarUrlSnapshot: owner.avatarUrl } },
      },
    });
    await tx.circleInvitation.createMany({
      data: memberIds.map((recipientId) => ({ circleId: circle.id, senderId: ownerId, recipientId, idempotencyKey: crypto.randomUUID(), expiresAt: new Date(Date.now() + 7 * 86400000) })),
      skipDuplicates: true,
    });
    await ensureCurrentWeek(tx, circle.id, new Date());
    return circle.id;
  });
}

export async function ensureCurrentWeek(tx: Prisma.TransactionClient, circleId: string, now: Date) {
  const circle = await tx.circle.findUniqueOrThrow({ where: { id: circleId }, select: { resetWeekday: true, timeZone: true, defaultFocusMode: true, defaultFocusConfigured: true, defaultTarget: true, defaultThemeKey: true, defaultThemeTitle: true, defaultThemeNote: true } });
  const interval = circleWeekInterval(now, circle.resetWeekday, circle.timeZone);
  return tx.circleWeek.upsert({
    where: { circleId_startsAt: { circleId, startsAt: interval.startsAt } },
    create: { circleId, startsAt: interval.startsAt, endsAt: interval.endsAt, timeZone: circle.timeZone, resetWeekday: circle.resetWeekday, focusMode: circle.defaultFocusMode, focusConfigured: circle.defaultFocusConfigured, sharedTarget: circle.defaultTarget, themeKey: circle.defaultThemeKey, themeTitle: circle.defaultThemeTitle, themeNote: circle.defaultThemeNote },
    update: {},
  });
}

export async function reconcileActivityToCircles(userId: string, activityId: string, deleted = false) {
    const prisma = getPrismaClient();
    const activity = await prisma.activity.findFirst({ where: { id: activityId, userId }, select: { id: true, type: true, startedAt: true, deletedAt: true } });
    if (!activity) return [];

    const existing = await prisma.circleContribution.findMany({
      where: { activityId: activity.id },
      select: { weekId: true, week: { select: { circleId: true } } },
    });
    const candidateMemberships = deleted || activity.deletedAt
      ? []
      : await prisma.circleMember.findMany({
          where: { userId, status: "active", joinedAt: { lte: activity.startedAt }, circle: { lifecycle: { not: "archived" } } },
          include: { circle: { select: { id: true, resetWeekday: true, timeZone: true, defaultFocusMode: true, defaultFocusConfigured: true, defaultTarget: true, defaultThemeKey: true, defaultThemeTitle: true, defaultThemeNote: true } } },
        });
    const memberships = (await Promise.all(candidateMemberships.map(async (membership) => {
      try {
        await assertNoBlockedCircleMember(membership.circle.id, userId);
        return membership;
      } catch {
        return null;
      }
    }))).filter((membership): membership is NonNullable<typeof membership> => membership != null);

    const affectedCircleIds = new Set<string>();
    await prisma.$transaction(async (tx) => {
      await tx.circleContribution.deleteMany({ where: { activityId: activity.id } });
      for (const membership of memberships) {
        affectedCircleIds.add(membership.circle.id);
        const interval = circleWeekInterval(activity.startedAt, membership.circle.resetWeekday, membership.circle.timeZone);
        const week = await tx.circleWeek.upsert({
          where: { circleId_startsAt: { circleId: membership.circle.id, startsAt: interval.startsAt } },
          create: { circleId: membership.circle.id, startsAt: interval.startsAt, endsAt: interval.endsAt, timeZone: membership.circle.timeZone, resetWeekday: membership.circle.resetWeekday, focusMode: membership.circle.defaultFocusMode, focusConfigured: membership.circle.defaultFocusConfigured, sharedTarget: membership.circle.defaultTarget, themeKey: membership.circle.defaultThemeKey, themeTitle: membership.circle.defaultThemeTitle, themeNote: membership.circle.defaultThemeNote },
          update: {},
        });
        await tx.circleContribution.createMany({ data: [{ weekId: week.id, memberId: membership.id, activityId: activity.id }], skipDuplicates: true });
        await refreshWeekState(tx, week.id);
      }
      for (const oldWeek of existing) {
        affectedCircleIds.add(oldWeek.week.circleId);
        if (!memberships.some((membership) => membership.circle.id === oldWeek.week.circleId)) {
          await refreshWeekState(tx, oldWeek.weekId);
        }
      }
    });
    if (deleted || activity.deletedAt) return [];
    const user = await prisma.user.findUnique({ where: { id: userId }, select: { primaryCircleId: true } });
    const summaries = await Promise.all([...affectedCircleIds].map(async (circleId): Promise<CircleContributionSummary | null> => {
      const payload = await circlePayload(circleId, userId);
      if (!payload) return null;
      return {
        circleId,
        circleName: payload.name,
        weekId: payload.week.id,
        contributedCount: payload.week.contributedCount,
        targetCount: payload.week.targetCount,
        focusMode: payload.week.focusMode,
        memberCount: payload.memberCount,
        completed: payload.week.state === "completed",
        primary: user?.primaryCircleId === circleId,
      };
    }));
    return summaries.filter((summary): summary is CircleContributionSummary => summary != null);
}

export async function transferCircleOwnership(circleId: string, ownerId: string, recipientUserId: string) {
  if (ownerId === recipientUserId) throw new CircleDomainError("invalid_owner", "Choose another active member.");
  await assertAcceptedConnection(ownerId, recipientUserId);
  const prisma = getPrismaClient();
  return prisma.$transaction(async (tx) => {
    const recipient = await tx.circleMember.findUnique({ where: { circleId_userId: { circleId, userId: recipientUserId } } });
    const current = await tx.circleMember.findUnique({ where: { circleId_userId: { circleId, userId: ownerId } } });
    if (current?.role !== "owner" || recipient?.status !== "active") throw new CircleDomainError("owner_access_required", "Only the owner can transfer ownership to an active member.");
    await tx.circleMember.update({ where: { id: current.id }, data: { role: "member" } });
    await tx.circleMember.update({ where: { id: recipient.id }, data: { role: "owner" } });
    return tx.circle.update({ where: { id: circleId }, data: { ownerId: recipientUserId } });
  });
}

export async function refreshWeekState(tx: Prisma.TransactionClient, weekId: string) {
  const week = await tx.circleWeek.findUniqueOrThrow({ where: { id: weekId }, include: { commitments: true, contributions: true, circle: { select: { lifecycle: true, name: true } } } });
  if (!week.focusConfigured || week.focusMode === "none" || week.focusMode === "theme") {
    if (week.state === "completed") return tx.circleWeek.update({ where: { id: week.id }, data: { state: "open", completedAt: null } });
    return week;
  }
  const qualifying = week.focusMode === "shared_target"
    ? week.sharedTarget
    : week.commitments.filter((c) => !c.skipped && c.targetCount != null).reduce((sum, c) => sum + (c.targetCount ?? 0), 0);
  const progress = week.contributions.length;
  if (qualifying && progress >= qualifying && week.state !== "completed") {
    const completed = await tx.circleWeek.update({ where: { id: week.id }, data: { state: "completed", completedAt: new Date() } });
    const members = await tx.circleMember.findMany({ where: { circleId: week.circleId, status: "active" }, select: { userId: true } });
    await tx.circleWeekPresentation.createMany({ data: members.map((member) => ({ weekId: week.id, userId: member.userId })), skipDuplicates: true });
    for (const member of members) {
      const muted = await tx.circleMember.findUnique({ where: { circleId_userId: { circleId: week.circleId, userId: member.userId } }, select: { notificationMuted: true } });
      if (muted?.notificationMuted) continue;
      const dedupeKey = `circle-week-completed:${week.id}:${member.userId}`;
      await tx.socialNotification.upsert({
        where: { dedupeKey },
        create: { recipientId: member.userId, type: "circleWeeklyGoalCompleted", objectId: week.circleId, message: `${week.circle.name} completed this week’s focus.`, dedupeKey },
        update: {},
      });
    }
    return completed;
  }
  if (week.state === "completed" && progress < (qualifying ?? Number.MAX_SAFE_INTEGER)) {
    return tx.circleWeek.update({ where: { id: week.id }, data: { state: "open", completedAt: null } });
  }
  return week;
}

export async function circlePayload(circleId: string, viewerId: string, includeHistory = false) {
  const prisma = getPrismaClient();
  const circle = await prisma.circle.findUnique({ where: { id: circleId }, include: { owner: { select: shareSafeMemberSelect }, members: { where: { status: "active" }, include: { user: { select: shareSafeMemberSelect } }, orderBy: { joinedAt: "asc" } } } });
  if (!circle) return null;
  const week = await ensureCurrentWeek(prisma, circle.id, new Date());
  const [commitments, history, cheers, viewerMembership, completionPresentation, invitations, activityEvents] = await Promise.all([
    prisma.circleCommitment.findMany({ where: { weekId: week.id } }),
    includeHistory ? prisma.circleWeek.findMany({ where: { circleId, startsAt: { lt: week.startsAt } }, orderBy: { startsAt: "desc" }, take: 12 }) : Promise.resolve([]),
    prisma.circleCheer.findMany({ where: { circleId, weekId: week.id }, orderBy: { createdAt: "desc" }, take: 30 }),
    prisma.circleMember.findUnique({ where: { circleId_userId: { circleId, userId: viewerId } }, select: { notificationMuted: true } }),
    prisma.circleWeekPresentation.findUnique({ where: { weekId_userId: { weekId: week.id, userId: viewerId } }, select: { presentedAt: true } }),
    circle.ownerId === viewerId ? prisma.circleInvitation.findMany({ where: { circleId, status: "pending", OR: [{ expiresAt: null }, { expiresAt: { gt: new Date() } }] }, include: { sender: { select: shareSafeMemberSelect }, recipient: { select: shareSafeMemberSelect }, circle: { select: { id: true, name: true } } }, orderBy: { createdAt: "desc" } }) : Promise.resolve([]),
    prisma.activityEvent.findMany({
      where: {
        sourceCircleId: circleId,
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
  const contributions = await prisma.circleContribution.findMany({
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
        },
      },
    },
    orderBy: { activity: { startedAt: "desc" } },
  });
  const counts = new Map<string, number>();
  for (const contribution of contributions) counts.set(contribution.memberId, (counts.get(contribution.memberId) ?? 0) + 1);
  const activeCount = circle.members.length;
  const payload = {
    id: circle.id,
    name: circle.name,
    lifecycle: circle.lifecycle,
    role: circle.members.find((m) => m.userId === viewerId)?.role ?? null,
    owner: circle.owner,
    resetWeekday: circle.resetWeekday,
    timeZone: circle.timeZone,
    memberLimit: circle.memberLimit,
    memberCount: activeCount,
    eligibleForToday: activeCount >= 2 && circle.lifecycle === "active",
    members: circle.members.map((member) => {
      const commitment = commitments.find((item) => item.memberId === member.id);
      return {
        id: member.id,
        user: member.user,
        role: member.role,
        isCurrentUser: member.userId === viewerId,
        commitment: commitment ? { targetCount: commitment.targetCount, skipped: commitment.skipped } : null,
        contributedCount: counts.get(member.id) ?? 0,
        recentActivity: contributions.find((contribution) => contribution.memberId === member.id)?.activity ?? null,
      };
    }),
    upcomingFocus: { mode: circle.defaultFocusMode, focusConfigured: circle.defaultFocusConfigured, sharedTarget: circle.defaultTarget, themeKey: circle.defaultThemeKey, themeTitle: circle.defaultThemeTitle, themeNote: circle.defaultThemeNote },
    week: { id: week.id, startsAt: week.startsAt, endsAt: week.endsAt, focusMode: week.focusMode, focusConfigured: week.focusConfigured, sharedTarget: week.sharedTarget, themeKey: week.themeKey, themeTitle: week.themeTitle, themeNote: week.themeNote, state: week.state, contributedCount: contributions.length, targetCount: !week.focusConfigured || week.focusMode === "theme" ? null : week.focusMode === "shared_target" ? week.sharedTarget : commitments.filter((c) => !c.skipped).reduce((sum, c) => sum + (c.targetCount ?? 0), 0) || null },
    currentUserMuted: viewerMembership?.notificationMuted ?? false,
    completionPresentationPending: week.state === "completed" && completionPresentation != null && completionPresentation.presentedAt == null,
    cheers: cheers.map((cheer) => ({ id: cheer.id, senderUserId: cheer.senderId, recipientUserId: cheer.recipientId, presetType: cheer.presetType, createdAt: cheer.createdAt })),
    invitations: invitations.map((invitation) => ({ id: invitation.id, circleId: invitation.circleId, circle: invitation.circle, sender: invitation.sender, recipient: invitation.recipient, status: invitation.status, createdAt: invitation.createdAt, expiresAt: invitation.expiresAt })),
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
        creator: event.creator,
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

export function circleWeekInterval(date: Date, resetWeekday: number, timeZone: string) {
  const local = localDateParts(date, timeZone);
  const delta = (local.weekday - resetWeekday + 7) % 7;
  const startLocal = new Date(Date.UTC(local.year, local.month - 1, local.day - delta));
  const endLocal = new Date(Date.UTC(local.year, local.month - 1, local.day - delta + 7));
  const startsAt = zonedLocalToUTC(startLocal, timeZone);
  return { startsAt, endsAt: zonedLocalToUTC(endLocal, timeZone) };
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

function generatedCircleName(names: string[], locale: SupportedLocale) {
  const firstNames = names.map((name) => name.trim().split(/\s+/)[0]).filter(Boolean).slice(0, 3);
  if (!firstNames.length) return locale === "es" ? "Tu círculo" : locale === "zh-Hans" ? "你的活力圈" : "Your Circle";
  if (locale === "zh-Hans") return `${firstNames.join("、")}的活力圈`;
  if (locale === "es") return `Círculo de ${firstNames.join(", ")}`;
  return `${firstNames.join(", ")}’s Circle`;
}

function boundedWeekday(value: number) { return Number.isInteger(value) && value >= 1 && value <= 7 ? value : 1; }
export function validTimeZone(value: string | undefined) { if (!value) return false; try { new Intl.DateTimeFormat("en-US", { timeZone: value }).format(); return true; } catch { return false; } }

export class CircleDomainError extends Error {
  constructor(public readonly code: string, message: string) { super(message); }
}
