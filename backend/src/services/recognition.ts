import { Prisma } from "@prisma/client";
import { safeTimeZoneIdentifier, zonedDateParts } from "./assistantActivityTools.js";
import { getPrismaClient } from "./prisma.js";

export const recognitionBadgeIds = [
  "firstStep",
  "backInMotion",
  "weeklyFocusComplete",
  "fourWeekRhythm",
  "first5K",
  "first10K",
  "firstHalfMarathon",
  "firstMarathon",
  "goodTeammate",
  "relayPlayer",
  "rivalEdge",
  "photoFinish",
] as const;

export type RecognitionBadgeId = (typeof recognitionBadgeIds)[number];

type RecognitionDefinition = {
  family: "showedUp" | "momentum" | "social";
  shareEligible: boolean;
  ruleVersion: number;
};

const definitions: Record<RecognitionBadgeId, RecognitionDefinition> = {
  firstStep: { family: "showedUp", shareEligible: false, ruleVersion: 1 },
  backInMotion: { family: "showedUp", shareEligible: true, ruleVersion: 1 },
  weeklyFocusComplete: { family: "momentum", shareEligible: true, ruleVersion: 1 },
  fourWeekRhythm: { family: "momentum", shareEligible: false, ruleVersion: 1 },
  first5K: { family: "momentum", shareEligible: true, ruleVersion: 1 },
  first10K: { family: "momentum", shareEligible: true, ruleVersion: 1 },
  firstHalfMarathon: { family: "momentum", shareEligible: true, ruleVersion: 1 },
  firstMarathon: { family: "momentum", shareEligible: true, ruleVersion: 1 },
  goodTeammate: { family: "social", shareEligible: false, ruleVersion: 1 },
  relayPlayer: { family: "social", shareEligible: false, ruleVersion: 1 },
  rivalEdge: { family: "social", shareEligible: true, ruleVersion: 1 },
  photoFinish: { family: "social", shareEligible: true, ruleVersion: 1 },
};

type AwardInput = {
  earnedAt?: Date;
  sourceType: "activity" | "social" | "clientMigration";
  sourceActivityClientId?: string | null;
  sourceReferenceId?: string | null;
};

type ActivityForRecognition = {
  clientActivityId: string | null;
  type: string;
  startedAt: Date;
  durationSecs: number | null;
  distanceM: number | null;
  createdAt: Date;
  clientData: Prisma.JsonValue | null;
};

export function isRecognitionBadgeId(value: string): value is RecognitionBadgeId {
  return (recognitionBadgeIds as readonly string[]).includes(value);
}

export async function awardRecognition(userId: string, badgeId: RecognitionBadgeId, input: AwardInput) {
  const definition = definitions[badgeId];
  return getPrismaClient().recognitionAward.upsert({
    where: { userId_badgeId: { userId, badgeId } },
    create: {
      userId,
      badgeId,
      family: definition.family,
      earnedAt: input.earnedAt ?? new Date(),
      sourceType: input.sourceType,
      sourceActivityClientId: input.sourceActivityClientId ?? null,
      sourceReferenceId: input.sourceReferenceId ?? null,
      ruleVersion: definition.ruleVersion,
      shareEligible: definition.shareEligible,
    },
    update: {
      family: definition.family,
      ruleVersion: definition.ruleVersion,
      shareEligible: definition.shareEligible,
    },
  });
}

export async function claimRecognitions(
  userId: string,
  claims: Array<{
    badgeId: RecognitionBadgeId;
    earnedAt: Date;
    sourceActivityClientId?: string | null;
    sourceReferenceId?: string | null;
  }>,
) {
  for (const claim of claims) {
    await awardRecognition(userId, claim.badgeId, {
      earnedAt: claim.earnedAt,
      sourceType: "clientMigration",
      sourceActivityClientId: claim.sourceActivityClientId,
      sourceReferenceId: claim.sourceReferenceId,
    });
  }
}

export async function backfillActivityRecognitions(
  userId: string,
  timeZoneIdentifier?: string | null,
  firstWeekday = 2,
) {
  const prisma = getPrismaClient();
  const [activities, existingAwards] = await Promise.all([
    prisma.activity.findMany({
      where: { userId, deletedAt: null },
      select: {
        clientActivityId: true,
        type: true,
        startedAt: true,
        durationSecs: true,
        distanceM: true,
        createdAt: true,
        clientData: true,
      },
      orderBy: [{ startedAt: "asc" }, { createdAt: "asc" }],
    }),
    prisma.recognitionAward.findMany({
      where: { userId },
      select: { badgeId: true },
    }),
  ]);
  const earnedBadgeIds = new Set(existingAwards.map((award) => award.badgeId));
  const timeZone = safeTimeZoneIdentifier(timeZoneIdentifier);
  const normalizedFirstWeekday = normalizeFirstWeekday(firstWeekday);
  const prior: ActivityForRecognition[] = [];

  for (const activity of activities) {
    const candidates = new Set<RecognitionBadgeId>(claimedActivityBadges(activity.clientData));
    if (prior.length === 0) candidates.add("firstStep");
    if (isComeback(activity, prior, timeZone)) candidates.add("backInMotion");
    if (hasFourWeekRhythm(activity.startedAt, prior, timeZone, normalizedFirstWeekday)) {
      candidates.add("fourWeekRhythm");
    }
    if (["running", "walking", "hiking"].includes(activity.type)) {
      const distanceM = activity.distanceM ?? 0;
      if (distanceM >= 5_000) candidates.add("first5K");
      if (distanceM >= 10_000) candidates.add("first10K");
      if (distanceM >= 21_097.5) candidates.add("firstHalfMarathon");
      if (distanceM >= 42_195) candidates.add("firstMarathon");
    }

    for (const badgeId of candidates) {
      if (earnedBadgeIds.has(badgeId)) continue;
      await awardRecognition(userId, badgeId, {
        earnedAt: activity.createdAt,
        sourceType: "activity",
        sourceActivityClientId: activity.clientActivityId,
      });
      earnedBadgeIds.add(badgeId);
    }
    prior.push(activity);
  }
}

export async function backfillSocialRecognitions(
  userId: string,
  timeZoneIdentifier?: string | null,
  firstWeekday = 2,
) {
  const prisma = getPrismaClient();
  const existingAwards = await prisma.recognitionAward.findMany({
    where: { userId, badgeId: { in: ["goodTeammate", "relayPlayer", "photoFinish"] } },
    select: { badgeId: true },
  });
  const earnedBadgeIds = new Set(existingAwards.map((award) => award.badgeId));
  const needsRelayPlayer = !earnedBadgeIds.has("relayPlayer");
  const needsPhotoFinish = !earnedBadgeIds.has("photoFinish");
  const needsGoodTeammate = !earnedBadgeIds.has("goodTeammate");
  if (!needsRelayPlayer && !needsPhotoFinish && !needsGoodTeammate) return;

  const [membership, participant, photoPost, reactions, comments] = await Promise.all([
    needsRelayPlayer ? prisma.clubMembership.findFirst({
      where: { userId },
      select: { clubId: true, createdAt: true },
      orderBy: { createdAt: "asc" },
    }) : Promise.resolve(null),
    needsRelayPlayer ? prisma.activityEventParticipant.findFirst({
      where: { userId },
      select: { activityEventId: true, joinedAt: true },
      orderBy: { joinedAt: "asc" },
    }) : Promise.resolve(null),
    needsPhotoFinish ? prisma.post.findFirst({
      where: { userId, activity: { is: { photos: { some: {} } } } },
      select: {
        id: true,
        createdAt: true,
        activity: { select: { clientActivityId: true } },
      },
      orderBy: { createdAt: "asc" },
    }) : Promise.resolve(null),
    needsGoodTeammate ? prisma.reaction.findMany({
      where: { userId, post: { userId: { not: userId } } },
      select: { postId: true, createdAt: true },
    }) : Promise.resolve([]),
    needsGoodTeammate ? prisma.comment.findMany({
      where: { authorId: userId, post: { userId: { not: userId } } },
      select: { postId: true, createdAt: true },
    }) : Promise.resolve([]),
  ]);

  const participation = [
    membership && { earnedAt: membership.createdAt, referenceId: `group:${membership.clubId}` },
    participant && { earnedAt: participant.joinedAt, referenceId: `activityEvent:${participant.activityEventId}` },
  ]
    .filter((value): value is { earnedAt: Date; referenceId: string } => Boolean(value))
    .sort((left, right) => left.earnedAt.getTime() - right.earnedAt.getTime())[0];
  if (participation) {
    await awardRecognition(userId, "relayPlayer", {
      earnedAt: participation.earnedAt,
      sourceType: "social",
      sourceReferenceId: participation.referenceId,
    });
  }

  if (photoPost) {
    await awardRecognition(userId, "photoFinish", {
      earnedAt: photoPost.createdAt,
      sourceType: "social",
      sourceActivityClientId: photoPost.activity?.clientActivityId,
      sourceReferenceId: photoPost.id,
    });
  }

  const timeZone = safeTimeZoneIdentifier(timeZoneIdentifier);
  const normalizedFirstWeekday = normalizeFirstWeekday(firstWeekday);
  const supportEvents = [...reactions, ...comments]
    .sort((left, right) => left.createdAt.getTime() - right.createdAt.getTime());
  const supportedPostsByWeek = new Map<number, Set<string>>();
  for (const event of supportEvents) {
    const marker = weekMarker(event.createdAt, timeZone, normalizedFirstWeekday);
    const supportedPosts = supportedPostsByWeek.get(marker) ?? new Set<string>();
    supportedPosts.add(event.postId);
    supportedPostsByWeek.set(marker, supportedPosts);
    if (supportedPosts.size >= 3) {
      await awardRecognition(userId, "goodTeammate", {
        earnedAt: event.createdAt,
        sourceType: "social",
        sourceReferenceId: `weekly-support:${marker}`,
      });
      break;
    }
  }
}

export async function evaluateGoodTeammate(
  userId: string,
  now = new Date(),
  timeZoneIdentifier?: string | null,
  firstWeekday = 2,
) {
  const timeZone = safeTimeZoneIdentifier(timeZoneIdentifier);
  const normalizedFirstWeekday = normalizeFirstWeekday(firstWeekday);
  const currentWeek = weekMarker(now, timeZone, normalizedFirstWeekday);
  const recentCutoff = new Date(now.getTime() - 8 * 86_400_000);
  const [reactions, comments] = await Promise.all([
    getPrismaClient().reaction.findMany({
      where: { userId, createdAt: { gte: recentCutoff }, post: { userId: { not: userId } } },
      select: { postId: true, createdAt: true },
    }),
    getPrismaClient().comment.findMany({
      where: { authorId: userId, createdAt: { gte: recentCutoff }, post: { userId: { not: userId } } },
      select: { postId: true, createdAt: true },
    }),
  ]);
  const supportedPosts = new Set(
    [...reactions, ...comments]
      .filter((event) => weekMarker(event.createdAt, timeZone, normalizedFirstWeekday) === currentWeek)
      .map((event) => event.postId),
  );
  if (supportedPosts.size >= 3) {
    await awardRecognition(userId, "goodTeammate", {
      earnedAt: now,
      sourceType: "social",
      sourceReferenceId: "weekly-support",
    });
  }
}

export async function recognitionAwards(userId: string, shareableOnly = false) {
  const awards = await getPrismaClient().recognitionAward.findMany({
    where: {
      userId,
      badgeId: { in: [...recognitionBadgeIds] },
      ...(shareableOnly ? { shareEligible: true } : {}),
    },
    orderBy: [{ earnedAt: "desc" }, { createdAt: "desc" }],
  });
  return awards.map((award) => ({
    id: award.id,
    badgeId: award.badgeId,
    family: award.family,
    earnedAt: award.earnedAt,
    sourceType: award.sourceType,
    sourceActivityId: shareableOnly ? null : award.sourceActivityClientId,
    sourceReferenceId: shareableOnly ? null : award.sourceReferenceId,
    ruleVersion: award.ruleVersion,
    shareEligible: award.shareEligible,
  }));
}

function claimedActivityBadges(clientData: Prisma.JsonValue | null): RecognitionBadgeId[] {
  if (!clientData || typeof clientData !== "object" || Array.isArray(clientData)) return [];
  const raw = (clientData as Record<string, unknown>).recognitionBadgeIDs;
  if (!Array.isArray(raw)) return [];
  return raw.filter((value): value is RecognitionBadgeId =>
    typeof value === "string" && isRecognitionBadgeId(value) && definitions[value].family !== "social"
  );
}

function localDayIndex(date: Date, timeZone: string) {
  const parts = zonedDateParts(date, timeZone);
  return Math.floor(Date.UTC(parts.year, parts.month - 1, parts.day) / 86_400_000);
}

function weekMarker(date: Date, timeZone: string, firstWeekday: number) {
  const dayIndex = localDayIndex(date, timeZone);
  const weekday = new Date(dayIndex * 86_400_000).getUTCDay() + 1;
  return dayIndex - ((weekday - firstWeekday + 7) % 7);
}

function normalizeFirstWeekday(value: number) {
  return Number.isInteger(value) && value >= 1 && value <= 7 ? value : 2;
}

function isComeback(candidate: ActivityForRecognition, prior: ActivityForRecognition[], timeZone: string) {
  const candidateDay = localDayIndex(candidate.startedAt, timeZone);
  const earlierDayDifferences = prior
    .map((activity) => candidateDay - localDayIndex(activity.startedAt, timeZone))
    .filter((dayDifference) => dayDifference >= 1);
  return earlierDayDifferences.length > 0
    && earlierDayDifferences.every((dayDifference) => dayDifference > 7);
}

function hasFourWeekRhythm(
  date: Date,
  prior: ActivityForRecognition[],
  timeZone: string,
  firstWeekday: number,
) {
  const currentWeek = weekMarker(date, timeZone, firstWeekday);
  const markers = new Set<number>([currentWeek]);
  for (const activity of prior) {
    markers.add(weekMarker(activity.startedAt, timeZone, firstWeekday));
  }
  return [0, 1, 2, 3].every((offset) => markers.has(currentWeek - offset * 7));
}
