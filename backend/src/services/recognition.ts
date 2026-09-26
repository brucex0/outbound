import { Prisma } from "@prisma/client";
import { safeTimeZoneIdentifier, zonedDateParts } from "./assistantActivityTools.js";
import { decodeStoredActivityRoute } from "./activityRouteCodec.js";
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
  "personalBest400m",
  "personalBest1K",
  "personalBestMile",
  "personalBest5K",
  "personalBest10K",
  "personalBest10Mile",
  "personalBestHalfMarathon",
  "personalBestMarathon",
] as const;

export type RecognitionBadgeId = (typeof recognitionBadgeIds)[number];

type RecognitionDefinition = {
  family: "showedUp" | "momentum" | "social";
  shareEligible: boolean;
  ruleVersion: number;
  priority: number;
};

const definitions: Record<RecognitionBadgeId, RecognitionDefinition> = {
  firstStep: { family: "showedUp", shareEligible: false, ruleVersion: 1, priority: 70 },
  backInMotion: { family: "showedUp", shareEligible: true, ruleVersion: 1, priority: 100 },
  weeklyFocusComplete: { family: "momentum", shareEligible: true, ruleVersion: 1, priority: 90 },
  fourWeekRhythm: { family: "momentum", shareEligible: false, ruleVersion: 1, priority: 85 },
  first5K: { family: "momentum", shareEligible: true, ruleVersion: 1, priority: 82 },
  first10K: { family: "momentum", shareEligible: true, ruleVersion: 1, priority: 84 },
  firstHalfMarathon: { family: "momentum", shareEligible: true, ruleVersion: 1, priority: 92 },
  firstMarathon: { family: "momentum", shareEligible: true, ruleVersion: 1, priority: 95 },
  goodTeammate: { family: "social", shareEligible: false, ruleVersion: 1, priority: 65 },
  relayPlayer: { family: "social", shareEligible: false, ruleVersion: 1, priority: 75 },
  rivalEdge: { family: "social", shareEligible: true, ruleVersion: 1, priority: 88 },
  photoFinish: { family: "social", shareEligible: true, ruleVersion: 1, priority: 80 },
  personalBest400m: { family: "momentum", shareEligible: true, ruleVersion: 1, priority: 96 },
  personalBest1K: { family: "momentum", shareEligible: true, ruleVersion: 1, priority: 97 },
  personalBestMile: { family: "momentum", shareEligible: true, ruleVersion: 1, priority: 98 },
  personalBest5K: { family: "momentum", shareEligible: true, ruleVersion: 1, priority: 100 },
  personalBest10K: { family: "momentum", shareEligible: true, ruleVersion: 1, priority: 102 },
  personalBest10Mile: { family: "momentum", shareEligible: true, ruleVersion: 1, priority: 104 },
  personalBestHalfMarathon: { family: "momentum", shareEligible: true, ruleVersion: 1, priority: 106 },
  personalBestMarathon: { family: "momentum", shareEligible: true, ruleVersion: 1, priority: 108 },
};

export type ActivityRecognitionPayload = {
  badgeId: RecognitionBadgeId;
  family: RecognitionDefinition["family"];
  earnedAt: Date;
};

type ActivityRecognitionSource = { userId: string; clientActivityId: string };

export function activityRecognitionKey(userId: string, clientActivityId: string) {
  return JSON.stringify([userId, clientActivityId]);
}

/** Returns only explicitly shareable awards, joined to the exact owner's activity. */
export async function activityRecognitionsForActivities(
  sources: ActivityRecognitionSource[],
  privateForUserId?: string,
) {
  const byActivity = new Map<string, ActivityRecognitionPayload[]>();
  if (sources.length === 0) return byActivity;

  const uniqueSources = [...new Map(
    sources.map((source) => [activityRecognitionKey(source.userId, source.clientActivityId), source]),
  ).values()];
  const requestedKeys = new Set(
    uniqueSources.map((source) => activityRecognitionKey(source.userId, source.clientActivityId)),
  );
  const awards = await getPrismaClient().recognitionAward.findMany({
    where: {
      OR: uniqueSources.map(({ userId, clientActivityId }) => ({
        userId,
        sourceActivityClientId: clientActivityId,
        ...(privateForUserId === userId ? {} : { shareEligible: true }),
      })),
    },
    select: {
      userId: true,
      sourceActivityClientId: true,
      badgeId: true,
      earnedAt: true,
    },
  });

  for (const award of awards) {
    if (!award.sourceActivityClientId || !isRecognitionBadgeId(award.badgeId)) continue;
    const key = activityRecognitionKey(award.userId, award.sourceActivityClientId);
    if (!requestedKeys.has(key)) continue;
    const presentation: ActivityRecognitionPayload = {
      badgeId: award.badgeId,
      family: definitions[award.badgeId].family,
      earnedAt: award.earnedAt,
    };
    byActivity.set(key, [...(byActivity.get(key) ?? []), presentation]);
  }

  for (const presentations of byActivity.values()) {
    presentations.sort((left, right) =>
      definitions[right.badgeId].priority - definitions[left.badgeId].priority
      || left.earnedAt.getTime() - right.earnedAt.getTime()
    );
  }
  return byActivity;
}

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
  routeBlob: Uint8Array | null;
  routeMetadata: Prisma.JsonValue | null;
};

const personalBestTargets = [
  ["personalBest400m", 400],
  ["personalBest1K", 1_000],
  ["personalBestMile", 1_609.344],
  ["personalBest5K", 5_000],
  ["personalBest10K", 10_000],
  ["personalBest10Mile", 16_093.44],
  ["personalBestHalfMarathon", 21_097.5],
  ["personalBestMarathon", 42_195],
] as const satisfies ReadonlyArray<readonly [RecognitionBadgeId, number]>;

const personalBestBadgeIds = new Set<RecognitionBadgeId>(personalBestTargets.map(([badgeId]) => badgeId));

const activityDerivedBadgeIds = new Set<RecognitionBadgeId>([
  "firstStep",
  "backInMotion",
  "fourWeekRhythm",
  "first5K",
  "first10K",
  "firstHalfMarathon",
  "firstMarathon",
  ...personalBestBadgeIds,
]);

/** Finds fastest timed distance windows from stored GPS points; summary estimates are intentionally excluded. */
export function activityPersonalBestTimes(
  routeBlob: Uint8Array | null,
  routeMetadata: Prisma.JsonValue | null,
) {
  let route: ReturnType<typeof decodeStoredActivityRoute>;
  try {
    route = decodeStoredActivityRoute(routeBlob, routeMetadata);
  } catch {
    return new Map<RecognitionBadgeId, number>();
  }
  if (!route) return new Map<RecognitionBadgeId, number>();
  const segments: Array<typeof route.points> = [];
  let segment: typeof route.points = [];
  for (const point of route.points) {
    if (point.startsNewSegment && segment.length > 0) {
      segments.push(segment);
      segment = [];
    }
    const timestamp = Date.parse(point.timestamp);
    if (
      !Number.isFinite(point.latitude) || !Number.isFinite(point.longitude)
      || point.latitude < -90 || point.latitude > 90
      || point.longitude < -180 || point.longitude > 180
      || !Number.isFinite(timestamp)
    ) {
      if (segment.length > 0) segments.push(segment);
      segment = [];
      continue;
    }
    const previous = segment.at(-1);
    if (previous) {
      const elapsedSeconds = (timestamp - Date.parse(previous.timestamp)) / 1_000;
      const meters = distanceBetweenRoutePoints(previous, point);
      if (elapsedSeconds <= 0 || elapsedSeconds > 30 * 60 || meters / elapsedSeconds > 10) {
        segments.push(segment);
        segment = [];
      }
    }
    segment.push(point);
  }
  if (segment.length > 0) segments.push(segment);

  const bestTimes = new Map<RecognitionBadgeId, number>();
  for (const [badgeId, targetMeters] of personalBestTargets) {
    let fastestSeconds = Number.POSITIVE_INFINITY;
    for (const points of segments) {
      if (points.length < 2) continue;
      const cumulative = [0];
      for (let index = 1; index < points.length; index += 1) {
        cumulative.push(cumulative[index - 1] + distanceBetweenRoutePoints(points[index - 1], points[index]));
      }
      let endIndex = 1;
      for (let startIndex = 0; startIndex < points.length - 1; startIndex += 1) {
        const targetDistance = cumulative[startIndex] + targetMeters;
        endIndex = Math.max(endIndex, startIndex + 1);
        while (endIndex < points.length && cumulative[endIndex] < targetDistance) endIndex += 1;
        if (endIndex >= points.length) break;
        const startTime = Date.parse(points[startIndex].timestamp) / 1_000;
        const priorDistance = cumulative[endIndex - 1];
        const spanDistance = cumulative[endIndex] - priorDistance;
        if (spanDistance <= 0) continue;
        const fraction = (targetDistance - priorDistance) / spanDistance;
        const endTime = (
          Date.parse(points[endIndex - 1].timestamp)
          + (Date.parse(points[endIndex].timestamp) - Date.parse(points[endIndex - 1].timestamp)) * fraction
        ) / 1_000;
        const seconds = endTime - startTime;
        if (seconds > 0 && seconds < fastestSeconds) fastestSeconds = seconds;
      }
    }
    if (Number.isFinite(fastestSeconds)) bestTimes.set(badgeId, fastestSeconds);
  }
  return bestTimes;
}

function distanceBetweenRoutePoints(
  left: { latitude: number; longitude: number },
  right: { latitude: number; longitude: number },
) {
  const radians = Math.PI / 180;
  const latitudeDelta = (right.latitude - left.latitude) * radians;
  const longitudeDelta = (right.longitude - left.longitude) * radians;
  const leftLatitude = left.latitude * radians;
  const rightLatitude = right.latitude * radians;
  const chord = Math.sin(latitudeDelta / 2) ** 2
    + Math.cos(leftLatitude) * Math.cos(rightLatitude) * Math.sin(longitudeDelta / 2) ** 2;
  return 6_371_000 * 2 * Math.atan2(Math.sqrt(chord), Math.sqrt(Math.max(0, 1 - chord)));
}

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
    if (personalBestBadgeIds.has(claim.badgeId)) continue;
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
        routeBlob: true,
        routeMetadata: true,
      },
      orderBy: [{ startedAt: "asc" }, { createdAt: "asc" }],
    }),
    prisma.recognitionAward.findMany({
      where: { userId },
      select: { badgeId: true },
    }),
  ]);
  const earnedBadgeIds = new Set(existingAwards.map((award) => award.badgeId));
  const reconciledActivityBadgeIds = new Set<RecognitionBadgeId>();
  const timeZone = safeTimeZoneIdentifier(timeZoneIdentifier);
  const normalizedFirstWeekday = normalizeFirstWeekday(firstWeekday);
  const prior: ActivityForRecognition[] = [];
  const priorPersonalBestTimes = new Map<RecognitionBadgeId, number>();

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
    if (activity.type === "running") {
      for (const [badgeId, seconds] of activityPersonalBestTimes(activity.routeBlob, activity.routeMetadata)) {
        const previousBest = priorPersonalBestTimes.get(badgeId);
        if (previousBest == null || seconds < previousBest) {
          candidates.add(badgeId);
          priorPersonalBestTimes.set(badgeId, seconds);
        }
      }
    }

    for (const badgeId of candidates) {
      if (personalBestBadgeIds.has(badgeId)) {
        const definition = definitions[badgeId];
        await prisma.recognitionAward.upsert({
          where: { userId_badgeId: { userId, badgeId } },
          create: {
            userId,
            badgeId,
            family: definition.family,
            earnedAt: activity.startedAt,
            sourceType: "activity",
            sourceActivityClientId: activity.clientActivityId,
            ruleVersion: definition.ruleVersion,
            shareEligible: definition.shareEligible,
          },
          update: {
            family: definition.family,
            earnedAt: activity.startedAt,
            sourceType: "activity",
            sourceActivityClientId: activity.clientActivityId,
            sourceReferenceId: null,
            ruleVersion: definition.ruleVersion,
            shareEligible: definition.shareEligible,
          },
        });
        earnedBadgeIds.add(badgeId);
        continue;
      }
      if (activityDerivedBadgeIds.has(badgeId) && !reconciledActivityBadgeIds.has(badgeId)) {
        const definition = definitions[badgeId];
        await prisma.recognitionAward.upsert({
          where: { userId_badgeId: { userId, badgeId } },
          create: {
            userId,
            badgeId,
            family: definition.family,
            earnedAt: activity.startedAt,
            sourceType: "activity",
            sourceActivityClientId: activity.clientActivityId,
            ruleVersion: definition.ruleVersion,
            shareEligible: definition.shareEligible,
          },
          update: {
            family: definition.family,
            earnedAt: activity.startedAt,
            sourceType: "activity",
            sourceActivityClientId: activity.clientActivityId,
            sourceReferenceId: null,
            ruleVersion: definition.ruleVersion,
            shareEligible: definition.shareEligible,
          },
        });
        reconciledActivityBadgeIds.add(badgeId);
        earnedBadgeIds.add(badgeId);
        continue;
      }
      if (earnedBadgeIds.has(badgeId)) continue;
      await awardRecognition(userId, badgeId, {
        earnedAt: activity.startedAt,
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
    needsRelayPlayer ? prisma.groupMember.findFirst({
      where: { userId, status: "active" },
      select: { groupId: true, createdAt: true },
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
    membership && { earnedAt: membership.createdAt, referenceId: `group:${membership.groupId}` },
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
    typeof value === "string"
    && isRecognitionBadgeId(value)
    && definitions[value].family !== "social"
    && !personalBestBadgeIds.has(value)
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
