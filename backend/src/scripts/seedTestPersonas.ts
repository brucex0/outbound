import { PrismaClient } from "@prisma/client";
import { getAuth } from "firebase-admin/auth";
import { getFirebaseApp } from "../services/firebaseAuth.js";
import { resolveAuthenticatedAppUser } from "../services/currentUser.js";

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

  await prisma.user.deleteMany({ where: { firebaseUid: { in: values.map((persona) => persona.uid) } } });
  await prisma.club.deleteMany({ where: { name: "Plainstride E2E Run Club" } });
  await prisma.club.deleteMany({ where: { name: "Sunset E2E Striders" } });

  for (const persona of values) {
    try {
      await auth.deleteUser(persona.uid);
    } catch (error: any) {
      if (error?.code !== "auth/user-not-found") throw error;
    }
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
    createActivity(activeRunner.id, "e2e-active-easy", "Easy neighborhood run", daysAgo(now, 2), 32 * 60, 5_100, 376),
    createActivity(activeRunner.id, "e2e-active-tempo", "Steady tempo", daysAgo(now, 5), 41 * 60, 7_000, 351),
    createActivity(activeRunner.id, "e2e-active-long", "Saturday long run", daysAgo(now, 9), 64 * 60, 10_200, 376),
  ]);
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
  const groupRun = await prisma.groupRun.create({
    data: {
      clubId: club.id,
      creatorId: socialRunner.id,
      title: "Saturday social 5K",
      startsAt: daysFromNow(now, 3),
      locationName: "Golden Gate Park",
      paceNote: "Conversational pace; nobody runs alone.",
      groups: { create: [{ label: "5K social", distanceMeters: 5_000, paceMinSeconds: 330, paceMaxSeconds: 450, capacity: 20, sortOrder: 0 }] },
    },
  });
  await prisma.club.create({
    data: {
      name: "Sunset E2E Striders",
      description: "A discoverable group the social persona has not joined.",
      city: "San Francisco",
    },
  });
  await prisma.groupRunRSVP.create({ data: { groupRunId: groupRun.id, userId: socialRunner.id, status: "going" } });
  const post = await prisma.post.create({
    data: { userId: activeRunner.id, activityId: activeActivities[0].id, caption: "Easy miles and good energy today.", visibility: "connections" },
  });
  await prisma.reaction.create({ data: { userId: socialRunner.id, postId: post.id, type: "clap" } });
  await prisma.comment.create({ data: { authorId: socialRunner.id, postId: post.id, body: "Nice work — see you Saturday!" } });

  const runInvitation = await prisma.invitation.create({
    data: { senderId: activeRunner.id, recipientId: socialRunner.id, groupRunId: groupRun.id, kind: "groupRun", status: "pending", expiresAt: daysFromNow(now, 7) },
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
    data: { userId, clientActivityId, syncSource: "e2e-seed", type: "running", title, startedAt, endedAt: new Date(startedAt.getTime() + durationSecs * 1000), durationSecs, distanceM, avgPace, elevationM: 42, calories: Math.round(distanceM / 10) },
  });
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
