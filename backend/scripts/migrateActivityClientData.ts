import { PrismaClient, Prisma } from "@prisma/client";

const prisma = new PrismaClient();

type LegacySnapshot = Record<string, unknown>;

function nullable<T>(value: unknown): T | null {
  return value === undefined ? null : value as T;
}

function extrasFrom(snapshot: LegacySnapshot) {
  const source = snapshot.source && typeof snapshot.source === "object"
    ? snapshot.source
    : { kind: "outbound", displayName: "Plainstride" };
  const badges = Array.isArray(snapshot.recognitionBadgeIDs) ? snapshot.recognitionBadgeIDs : [];

  return {
    guideNudge: typeof snapshot.guideNudge === "string" ? snapshot.guideNudge : "",
    walkingStepCount: nullable<number>(snapshot.walkingStepCount),
    healthMetrics: nullable(snapshot.healthMetrics),
    goal: nullable(snapshot.goal),
    energyKilocalories: nullable<number>(snapshot.energyKilocalories),
    source,
    gear: nullable(snapshot.gear),
    manualEdits: nullable(snapshot.manualEdits),
    indoor: nullable(snapshot.indoor),
    cadence: nullable(snapshot.cadence),
    heartRateZones: nullable(snapshot.heartRateZones),
    recordingSession: nullable(snapshot.recordingSession),
    activityEventID: nullable<string>(snapshot.activityEventID),
    followedRoute: nullable(snapshot.followedRoute),
    recognitionBadgeIDs: badges,
  } as Prisma.InputJsonValue;
}

async function main() {
  const activities = await prisma.activity.findMany({
    where: { clientData: { not: null } },
    select: { id: true, clientData: true },
  });
  let migrated = 0;
  for (const activity of activities) {
    if (!activity.clientData || typeof activity.clientData !== "object" || Array.isArray(activity.clientData)) continue;
    await prisma.activity.update({
      where: { id: activity.id },
      data: { clientData: extrasFrom(activity.clientData as LegacySnapshot) },
    });
    migrated += 1;
  }
  console.log(`Migrated ${migrated} activity clientData records.`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
}).finally(async () => {
  await prisma.$disconnect();
});
