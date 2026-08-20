import { PrismaClient } from "@prisma/client";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { getAuth } from "firebase-admin/auth";
import { getFirebaseApp } from "../services/firebaseAuth.js";
import { resolveAuthenticatedAppUser } from "../services/currentUser.js";
import { activityPhotoSHA256, activityPhotoStorageKey, deleteUserActivityPhotos, saveActivityPhoto } from "../services/activityPhotoStorage.js";

const prisma = new PrismaClient();
const password = "plainstride-test-persona";

const personas = {
  newRunner: {
    uid: "plainstride-test-new-runner",
    email: "new-runner@plainstride.test",
    username: "test-new-runner",
    displayName: "New Runner",
  },
  activeRunner: {
    uid: "plainstride-test-active-runner",
    email: "active-runner@plainstride.test",
    username: "test-active-runner",
    displayName: "Avery Runner",
  },
  socialRunner: {
    uid: "plainstride-test-social-runner",
    email: "social-runner@plainstride.test",
    username: "test-social-runner",
    displayName: "Sage Runner",
  },
  blockedRunner: {
    uid: "plainstride-test-blocked-runner",
    email: "blocked-runner@plainstride.test",
    username: "test-blocked-runner",
    displayName: "Blocked Runner",
  },
} as const;

async function seedTestPersonas() {
  assertLocalOnly();
  const auth = getAuth(getFirebaseApp());
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
  await prisma.club.deleteMany({ where: { name: "Plainstride E2E Run Club" } });
  await prisma.club.deleteMany({ where: { name: "Sunset E2E Striders" } });

  for (const persona of values) {
    const staleUIDs = new Set<string>();
    const existingByUID = await getAuthUserUID(() => auth.getUser(persona.uid));
    const existingByEmail = await getAuthUserUID(() => auth.getUserByEmail(persona.email));
    if (existingByUID) staleUIDs.add(existingByUID);
    if (existingByEmail) staleUIDs.add(existingByEmail);
    await Promise.all([...staleUIDs].map((uid) => auth.deleteUser(uid)));
    await auth.createUser({
      uid: persona.uid,
      email: persona.email,
      emailVerified: true,
      password,
      displayName: persona.displayName,
    });
  }

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
  await seedActivityPhotos(activeRunner.id, activeActivities, now);
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
  const club = await prisma.club.create({
    data: {
      name: "Plainstride E2E Run Club",
      description: "Deterministic local club data for end-to-end testing.",
      city: "San Francisco",
      memberships: { create: [{ userId: socialRunner.id, role: "organizer" }, { userId: activeRunner.id, role: "member" }] },
    },
  });
  const activityEvent = await prisma.activityEvent.create({
    data: {
      clubId: club.id,
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
  await prisma.club.create({
    data: {
      name: "Sunset E2E Striders",
      description: "A discoverable group the social persona has not joined.",
      city: "San Francisco",
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

  return { users: values.length, activities: activeActivities.length, clubs: 2 };
}

async function getAuthUserUID(fetchUser: () => Promise<{ uid: string }>) {
  try {
    return (await fetchUser()).uid;
  } catch (error: any) {
    if (error?.code === "auth/user-not-found") return null;
    throw error;
  }
}

async function createAppUser(persona: (typeof personas)[keyof typeof personas]) {
  return resolveAuthenticatedAppUser(
    {
      firebaseUid: persona.uid,
      email: persona.email,
      emails: [persona.email],
      emailVerified: true,
      name: persona.displayName,
      picture: null,
      phoneNumber: null,
      phoneNumbers: [],
      providerIds: ["email"],
      signInProvider: "password",
    },
    { username: persona.username, displayName: persona.displayName }
  );
}

function createActivity(userId: string, clientActivityId: string, title: string, startedAt: Date, durationSecs: number, distanceM: number, avgPace: number) {
  return prisma.activity.create({
    data: {
      userId,
      clientActivityId,
      syncSource: "e2e-seed",
      type: "running",
      title,
      startedAt,
      endedAt: new Date(startedAt.getTime() + durationSecs * 1000),
      durationSecs,
      distanceM,
      avgPace,
      elevationM: 42,
      calories: Math.round(distanceM / 10),
      route: makeSeedRoute(startedAt, durationSecs, distanceM, Number(clientActivityId.at(-1)) - 1),
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

async function seedActivityPhotos(userId: string, activities: Awaited<ReturnType<typeof createActivity>>[], now: Date) {
  const seeds = [
    { file: "coastal-trail.jpg", clientPhotoId: "2bb48b3c-8edc-49de-b109-7f96203113aa", pace: 365, heartRate: 144, distance: 2_400 },
    { file: "waterfront-run.jpg", clientPhotoId: "22cb6d92-c7e8-494b-a0bb-1598dc0092b7", pace: 348, heartRate: 151, distance: 3_600 },
    { file: "park-after-rain.jpg", clientPhotoId: "89df25b7-c636-4db7-b67f-29021d5f8e2b", pace: 378, heartRate: 139, distance: 6_800 },
  ];

  await Promise.all(seeds.map(async (seed, index) => {
    const activity = activities[index];
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
        takenAt: new Date(activity.startedAt.getTime() + Math.min(20 * 60, (activity.durationSecs ?? 0) / 2) * 1_000),
        paceAtShot: seed.pace,
        hrAtShot: seed.heartRate,
        distAtShot: seed.distance,
        captureContext: "active",
      },
    });
  }));
}

function daysAgo(origin: Date, days: number) {
  return new Date(origin.getTime() - days * 86_400_000);
}

function daysFromNow(origin: Date, days: number) {
  return new Date(origin.getTime() + days * 86_400_000);
}

function assertLocalOnly() {
  const emulatorHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
  const databaseURL = process.env.DATABASE_URL ?? "";
  if (!emulatorHost || !/^(127\.0\.0\.1|localhost):\d+$/.test(emulatorHost)) {
    throw new Error("Refusing to seed: FIREBASE_AUTH_EMULATOR_HOST must point to localhost.");
  }
  if (!/@(127\.0\.0\.1|localhost):/.test(databaseURL)) {
    throw new Error("Refusing to seed: DATABASE_URL must point to localhost.");
  }
}

try {
  const result = await seedTestPersonas();
  console.log(`[seed:e2e] Seeded ${result.users} users, ${result.activities} activities, and ${result.clubs} clubs.`);
} finally {
  await prisma.$disconnect();
}
