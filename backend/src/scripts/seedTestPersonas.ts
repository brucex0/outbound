import { Prisma, PrismaClient } from "@prisma/client";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { resolveAuthenticatedAppUser } from "../services/currentUser.js";
import { activityPhotoSHA256, activityPhotoStorageKey, deleteUserActivityPhotos, saveActivityPhoto } from "../services/activityPhotoStorage.js";
import { ensureCurrentWeek } from "../services/groups.js";
import { encodeActivityRoute, legacyGeoJSONToRoute, decodeStoredActivityRoute } from "../services/activityRouteCodec.js";

const prisma = new PrismaClient();

const personas = {
  newRunner: {
    uid: "plainstride-test-new-runner",
    email: "new-runner@plainstride.test",
    username: "test-new-runner",
    displayName: "New Runner",
    apiValue: "new",
  },
  activeRunner: {
    uid: "plainstride-test-active-runner",
    email: "active-runner@plainstride.test",
    username: "test-active-runner",
    displayName: "Avery Runner",
    apiValue: "active",
  },
  socialRunner: {
    uid: "plainstride-test-social-runner",
    email: "social-runner@plainstride.test",
    username: "test-social-runner",
    displayName: "Sage Runner",
    apiValue: "social",
  },
  blockedRunner: {
    uid: "plainstride-test-blocked-runner",
    email: "blocked-runner@plainstride.test",
    username: "test-blocked-runner",
    displayName: "Blocked Runner",
    apiValue: "blocked",
  },
} as const;

async function seedTestPersonas() {
  assertLocalOnly();
  const values = Object.values(personas);

  const existingUsers = await prisma.user.findMany({
    where: {
      OR: [
        { firebaseUid: { in: values.map((persona) => persona.uid) } },
        { normalizedEmail: { in: values.map((persona) => persona.email) } },
        { username: { in: values.map((persona) => persona.username) } },
      ],
    },
    select: { id: true },
  });
  await Promise.all(existingUsers.map((user) => deleteUserActivityPhotos(user.id)));
  await prisma.user.deleteMany({ where: { id: { in: existingUsers.map((user) => user.id) } } });
  await prisma.socialGroup.deleteMany({ where: { name: "Plainstride E2E Run Group" } });
  await prisma.socialGroup.deleteMany({ where: { name: "Sunset E2E Striders" } });

  const newRunner = await createAppUser(personas.newRunner);
  const activeRunner = await createAppUser(personas.activeRunner);
  const socialRunner = await createAppUser(personas.socialRunner);
  const blockedRunner = await createAppUser(personas.blockedRunner);
  const now = new Date();

  await prisma.runnerProfile.create({
    data: {
      userId: activeRunner.id,
      goalSummary: "Build toward a comfortable 10K",
      scheduleSummary: "Run Tuesday, Thursday, and Saturday",
      comfortableDurationMinutes: 40,
      recentSessionsPerWeek: 3,
      targetSessionsPerWeek: 3,
      preferredLongRunDay: "Saturday",
      completedAt: daysAgo(now, 30),
    },
  });
  await prisma.calibrationProgram.create({
    data: { userId: activeRunner.id, status: "completed", completedSessionCount: 3, targetSessionCount: 3, startedAt: daysAgo(now, 28), completedAt: daysAgo(now, 20) },
  });

  const activeActivities = await Promise.all([
    createActivity(activeRunner.id, "a11c7100-0000-4000-8000-000000000001", "Easy neighborhood run", daysAgo(now, 2), 32 * 60, 5_100, 376),
    createActivity(activeRunner.id, "a11c7100-0000-4000-8000-000000000002", "Steady tempo", daysAgo(now, 5), 41 * 60, 7_000, 351),
    createActivity(activeRunner.id, "a11c7100-0000-4000-8000-000000000003", "Saturday long run", daysAgo(now, 9), 64 * 60, 10_200, 376),
  ]);
  await seedActivityPhotos(activeRunner.id, activeActivities);
  await prisma.runnerInsight.createMany({
    data: [
      { userId: activeRunner.id, stableKey: "preferred_time", kind: "schedule", label: "Best rhythm", value: "Morning runs", confidence: "medium", evidenceCount: 3 },
      { userId: activeRunner.id, stableKey: "steady_pace", kind: "performance", label: "Steady pace", value: "About 6:10/km", confidence: "medium", evidenceCount: 3 },
    ],
  });

  await prisma.runnerProfile.create({
    data: { userId: socialRunner.id, goalSummary: "Run consistently with friends", scheduleSummary: "Three flexible runs each week", comfortableDurationMinutes: 35, recentSessionsPerWeek: 2, targetSessionsPerWeek: 3, completedAt: daysAgo(now, 18) },
  });
  await prisma.connection.create({ data: { requesterId: socialRunner.id, addresseeId: activeRunner.id, status: "accepted" } });
  await prisma.connection.create({ data: { requesterId: newRunner.id, addresseeId: socialRunner.id, status: "pending" } });
  const communityGroup = await prisma.socialGroup.create({
    data: {
      ownerId: socialRunner.id,
      managementMode: "user",
      name: "Plainstride E2E Run Group",
      normalizedName: "plainstride e2e run group",
      description: "Deterministic local group data for end-to-end testing.",
      city: "San Francisco",
      trustPolicy: "community",
      visibility: "public",
      joinPolicy: "open",
      noticesEnabled: true,
      members: { create: [{ userId: socialRunner.id, role: "owner", displayNameSnapshot: socialRunner.displayName }, { userId: activeRunner.id, role: "member", displayNameSnapshot: activeRunner.displayName }] },
    },
  });
  const activityEvent = await prisma.activityEvent.create({
    data: {
      groupId: communityGroup.id,
      creatorId: socialRunner.id,
      title: "Saturday social 5K",
      startsAt: daysFromNow(now, 3),
      endsAt: new Date(daysFromNow(now, 3).getTime() + 60 * 60 * 1000),
      locationName: "Golden Gate Park",
      note: "Conversational pace; join at the park or from anywhere.",
      participationMode: "hybrid",
      activityPolicy: "fixed",
      activityType: "running",
      options: { create: [{ label: "5K social", distanceMeters: 5_000, paceMinSeconds: 330, paceMaxSeconds: 450, capacity: 20, sortOrder: 0 }] },
    },
  });
  await prisma.socialGroup.create({
    data: {
      managementMode: "system",
      name: "Sunset E2E Striders",
      normalizedName: "sunset e2e striders",
      description: "A discoverable group the social persona has not joined.",
      city: "San Francisco",
      trustPolicy: "community",
      visibility: "public",
      joinPolicy: "open",
    },
  });
  await prisma.activityEventParticipant.create({ data: { activityEventId: activityEvent.id, userId: socialRunner.id, status: "going" } });
  const post = await prisma.post.create({
    data: { userId: activeRunner.id, activityId: activeActivities[0].id, caption: "Easy miles and good energy today.", visibility: "connections" },
  });
  await prisma.reaction.create({ data: { userId: socialRunner.id, postId: post.id, type: "clap" } });
  await prisma.comment.create({ data: { authorId: socialRunner.id, postId: post.id, body: "Nice work — see you Saturday!" } });

  const runInvitation = await prisma.invitation.create({
    data: { senderId: activeRunner.id, recipientId: socialRunner.id, activityEventId: activityEvent.id, kind: "activityEvent", status: "pending", expiresAt: daysFromNow(now, 7) },
  });
  await prisma.socialNotification.createMany({
    data: [
      { recipientId: socialRunner.id, actorId: newRunner.id, type: "connectionRequest", message: "New Runner wants to connect." },
      { recipientId: socialRunner.id, actorId: activeRunner.id, type: "cheer", objectId: post.id, message: "Avery Runner cheered your run." },
      { recipientId: socialRunner.id, actorId: activeRunner.id, type: "runInvitation", objectId: runInvitation.id, message: "Avery Runner invited you to Saturday social 5K." },
    ],
  });
  await prisma.socialBlock.create({ data: { blockerId: socialRunner.id, blockedId: blockedRunner.id } });

  const socialActivity = await createActivity(
    socialRunner.id,
    "a11c7100-0000-4000-8000-000000000004",
    "Golden Gate recovery run",
    daysAgo(now, 1),
    29 * 60,
    4_600,
    378
  );
  const redmondRoute = await prisma.route.create({
    data: {
      ownerId: activeRunner.id,
      sourceActivityId: activeActivities[2].id,
      name: "Redmond Harvest Half Marathon",
      description: "A scenic out-and-back half marathon through Redmond.",
      activityType: "running",
      visibility: "public",
      status: "active",
      geometry: {
        type: "LineString",
        coordinates: redmondHarvestHalfMarathonCoordinates,
      } as Prisma.InputJsonValue,
      distanceM: 21_097.5,
      elevationGainM: 112,
      routeShape: "out_and_back",
      startLatitude: 47.6705,
      startLongitude: -122.1215,
      minLatitude: 47.6705,
      maxLatitude: 47.745,
      minLongitude: -122.161,
      maxLongitude: -122.1215,
      bookmarkCount: 1,
      completionCount: 18,
    },
  });
  await prisma.routeBookmark.create({
    data: { userId: socialRunner.id, routeId: redmondRoute.id },
  });
  const group = await prisma.socialGroup.create({
    data: {
      ownerId: socialRunner.id,
      name: "Weekend Crew",
      normalizedName: "weekend crew",
      trustPolicy: "trusted_private",
      visibility: "private",
      joinPolicy: "invite_only",
      weeklyThemeEnabled: true,
      workoutContributionsEnabled: true,
      presetCheersEnabled: true,
      scheduledActivitiesEnabled: true,
      memberActivityCreation: true,
      lifecycle: "active",
      timeZone: "America/Los_Angeles",
      defaultFocusMode: "theme",
      defaultFocusConfigured: true,
      defaultThemeKey: "build_consistency",
      members: {
        create: [
          { userId: socialRunner.id, role: "owner", displayNameSnapshot: socialRunner.displayName, joinedAt: daysAgo(now, 30) },
          { userId: activeRunner.id, role: "member", displayNameSnapshot: activeRunner.displayName, joinedAt: daysAgo(now, 30) },
        ],
      },
    },
    include: { members: true },
  });
  const groupWeek = await ensureCurrentWeek(prisma, group.id, now);
  await prisma.groupWeek.update({
    where: { id: groupWeek.id },
    data: { focusMode: "theme", focusConfigured: true, themeKey: "build_consistency" },
  });
  await prisma.groupCommitment.createMany({
    data: group.members.map((member) => ({
      weekId: groupWeek.id,
      memberId: member.id,
      targetCount: member.userId === socialRunner.id ? 3 : 4,
    })),
  });
  const socialMember = group.members.find((member) => member.userId === socialRunner.id)!;
  const activeMember = group.members.find((member) => member.userId === activeRunner.id)!;
  await prisma.groupContribution.createMany({
    data: [
      { weekId: groupWeek.id, memberId: socialMember.id, activityId: socialActivity.id, contributedAt: socialActivity.startedAt },
      { weekId: groupWeek.id, memberId: activeMember.id, activityId: activeActivities[0].id, contributedAt: activeActivities[0].startedAt },
      { weekId: groupWeek.id, memberId: activeMember.id, activityId: activeActivities[1].id, contributedAt: activeActivities[1].startedAt },
    ],
  });
  await prisma.groupCheer.create({
    data: {
      groupId: group.id,
      weekId: groupWeek.id,
      senderId: socialRunner.id,
      recipientId: activeRunner.id,
      presetType: "encouragement",
    },
  });
  return { users: values.length, activities: activeActivities.length + 1, groups: 2, routes: 1 };
}

const redmondHarvestHalfMarathonCoordinates: number[][] = [
  [-122.1215, 47.6705, 42],
  [-122.1215, 47.6730, 42],
  [-122.1280, 47.6730, 35],
  [-122.1310, 47.6780, 32],
  [-122.1395, 47.6900, 30],
  [-122.1480, 47.7050, 28],
  [-122.1550, 47.7200, 25],
  [-122.1580, 47.7350, 24],
  [-122.1610, 47.7450, 22],
  [-122.1580, 47.7350, 24],
  [-122.1550, 47.7200, 25],
  [-122.1480, 47.7050, 28],
  [-122.1395, 47.6900, 30],
  [-122.1310, 47.6780, 32],
  [-122.1215, 47.6705, 42],
];

async function createAppUser(persona: (typeof personas)[keyof typeof personas]) {
  const user = await resolveAuthenticatedAppUser(
    {
      subject: `debug:${persona.apiValue}`,
      authenticationKind: "provider",
      provider: "firebase",
      providerSubject: `debug:${persona.apiValue}`,
      internalUserId: null,
      sessionId: null,
      email: persona.email,
      emails: [persona.email],
      emailVerified: true,
      name: persona.displayName,
      picture: null,
      phoneNumber: null,
      phoneNumbers: [],
    },
    { username: persona.username, displayName: persona.displayName }
  );
  if (!user) throw new Error(`Failed to create ${persona.email}`);
  return user;
}

function createActivity(userId: string, clientActivityId: string, title: string, startedAt: Date, durationSecs: number, distanceM: number, avgPace: number) {
  const endedAt = new Date(startedAt.getTime() + durationSecs * 1000);
  return prisma.activity.create({
    data: {
      userId,
      clientActivityId,
      syncSource: "e2e-seed",
      type: "running",
      title,
      startedAt,
      endedAt,
      durationSecs,
      distanceM,
      avgPace,
      elevationM: 42,
      energyKilocalories: Math.round(distanceM / 10),
      routeBlob: encodeActivityRoute(legacyGeoJSONToRoute(makeSeedRoute(startedAt, durationSecs, distanceM, Number(clientActivityId.at(-1)) - 1))!.points),
      routeMetadata: { visibility: "private", elevationMetadata: null },
      clientUpdatedAt: endedAt,
    },
  });
}

function makeSeedRoute(startedAt: Date, durationSecs: number, distanceM: number, variant: number) {
  const centers = [
    { latitude: 37.7694, longitude: -122.4862 },
    { latitude: 37.8067, longitude: -122.4050 },
    { latitude: 37.7606, longitude: -122.4181 },
  ];
  const center = centers[variant] ?? centers[0];
  const pointCount = 33;
  const radiusM = distanceM / (2 * Math.PI);
  const latitudeDegreesPerMeter = 1 / 111_320;
  const longitudeDegreesPerMeter = 1 / (111_320 * Math.cos(center.latitude * Math.PI / 180));
  const coordinates: number[][] = [];
  const timestamps: string[] = [];
  const verticalAccuracy: number[] = [];

  for (let index = 0; index < pointCount; index += 1) {
    const progress = index / (pointCount - 1);
    const angle = progress * 2 * Math.PI;
    const shape = 1 + 0.08 * Math.sin(angle * 3 + variant);
    const northM = Math.sin(angle) * radiusM * 0.72 * shape;
    const eastM = Math.cos(angle) * radiusM * 1.38 * shape;
    const altitude = 24 + variant * 8 + 12 * Math.sin(angle * 2 + variant * 0.7);
    coordinates.push([
      center.longitude + eastM * longitudeDegreesPerMeter,
      center.latitude + northM * latitudeDegreesPerMeter,
      Math.round(altitude * 10) / 10,
    ]);
    timestamps.push(new Date(startedAt.getTime() + progress * durationSecs * 1_000).toISOString());
    verticalAccuracy.push(5);
  }

  return {
    type: "Feature",
    geometry: { type: "LineString", coordinates },
    properties: { visibility: "private", timestamps, verticalAccuracy },
  };
}

async function seedActivityPhotos(userId: string, activities: Awaited<ReturnType<typeof createActivity>>[]) {
  const seeds = [
    { file: "coastal-trail.jpg", clientPhotoId: "2bb48b3c-8edc-49de-b109-7f96203113aa", pace: 365, heartRate: 144, distance: 1_200 },
    { file: "waterfront-run.jpg", clientPhotoId: "22cb6d92-c7e8-494b-a0bb-1598dc0092b7", pace: 348, heartRate: 151, distance: 2_600 },
    { file: "park-after-rain.jpg", clientPhotoId: "89df25b7-c636-4db7-b67f-29021d5f8e2b", pace: 378, heartRate: 139, distance: 4_300 },
  ];
  const activity = activities[0];
  if (!activity) return;

  await Promise.all(seeds.map(async (seed) => {
    const coordinate = seedRouteCoordinateAtDistance(decodeStoredActivityRoute(activity.routeBlob, activity.routeMetadata), seed.distance);
    const data = await readFile(path.resolve(process.cwd(), "src", "scripts", "assets", "running-photos", seed.file));
    const storageKey = activityPhotoStorageKey(userId, activity.id, seed.clientPhotoId);
    await saveActivityPhoto(storageKey, data);
    await prisma.photo.create({
      data: {
        activityId: activity.id,
        clientPhotoId: seed.clientPhotoId,
        storageKey,
        contentType: "image/jpeg",
        byteSize: data.length,
        sha256: activityPhotoSHA256(data),
        url: "",
        takenAt: new Date(activity.startedAt.getTime() + (activity.durationSecs ?? 0) * Math.min(seed.distance / (activity.distanceM ?? 1), 1) * 1_000),
        paceAtShot: seed.pace,
        hrAtShot: seed.heartRate,
        distAtShot: seed.distance,
        lat: coordinate?.latitude,
        lng: coordinate?.longitude,
        captureContext: "active",
      },
    });
  }));
}

function seedRouteCoordinateAtDistance(route: { points?: Array<{ latitude: number; longitude: number }> } | null, targetDistanceM: number) {
  const coordinates = route?.points?.map((point) => [point.longitude, point.latitude]) ?? [];
  if (coordinates.length === 0) return null;

  let traversedM = 0;
  for (let index = 1; index < coordinates.length; index += 1) {
    const start = coordinates[index - 1];
    const end = coordinates[index];
    const segmentM = seedCoordinateDistanceM(start, end);
    if (traversedM + segmentM >= targetDistanceM) {
      const progress = segmentM > 0 ? (targetDistanceM - traversedM) / segmentM : 0;
      return {
        longitude: start[0] + (end[0] - start[0]) * progress,
        latitude: start[1] + (end[1] - start[1]) * progress,
      };
    }
    traversedM += segmentM;
  }
  const last = coordinates.at(-1)!;
  return { longitude: last[0], latitude: last[1] };
}

function seedCoordinateDistanceM(start: number[], end: number[]) {
  const radians = Math.PI / 180;
  const latitudeDelta = (end[1] - start[1]) * radians;
  const longitudeDelta = (end[0] - start[0]) * radians;
  const haversine = Math.sin(latitudeDelta / 2) ** 2
    + Math.cos(start[1] * radians) * Math.cos(end[1] * radians) * Math.sin(longitudeDelta / 2) ** 2;
  return 12_742_000 * Math.asin(Math.sqrt(Math.min(1, haversine)));
}

function daysAgo(origin: Date, days: number) {
  return new Date(origin.getTime() - days * 86_400_000);
}

function daysFromNow(origin: Date, days: number) {
  return new Date(origin.getTime() + days * 86_400_000);
}

function assertLocalOnly() {
  const databaseURL = process.env.DATABASE_URL ?? "";
  if (!/@(127\.0\.0\.1|localhost):/.test(databaseURL)) {
    throw new Error("Refusing to seed: DATABASE_URL must point to localhost.");
  }
}

try {
  const result = await seedTestPersonas();
  console.log(`[seed:e2e] Seeded ${result.users} users, ${result.activities} activities, ${result.groups} Groups, and ${result.routes} route.`);
} finally {
  await prisma.$disconnect();
}
