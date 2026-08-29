import { Prisma, type GuideProfile } from "@prisma/client/index.js";
import { getPrismaClient } from "./prisma.js";
import type { GuideProfilePayload, GoalItem, MemorySnapshot, PersonalRecords } from "../types/guide.js";

// Rebuild and persist the guide profile after each activity or on demand.
// Called by the activity completion webhook and the /guide/rebuild endpoint.
export async function rebuildGuideProfile(userId: string): Promise<GuideProfilePayload> {
  const prisma = getPrismaClient();
  const [user, activities] = await Promise.all([
    prisma.user.findUniqueOrThrow({
      where: { id: userId },
      include: { guideProfile: true },
    }),
    prisma.activity.findMany({
      where: { userId, type: "running" },
      orderBy: { startedAt: "desc" },
      take: 90,
    }),
  ]);

  const existing = user.guideProfile;
  const runActivities = activities.filter((a) => a.distanceM && a.durationSecs);

  // Compute weekly volume (last 7 days)
  const oneWeekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
  const weeklyVolumeM = runActivities
    .filter((a) => a.startedAt >= oneWeekAgo)
    .reduce((sum, a) => sum + (a.distanceM ?? 0), 0);

  // Detect personal records
  const records: PersonalRecords = (existing?.records as PersonalRecords) ?? {};
  for (const activity of runActivities) {
    if (!activity.distanceM || !activity.durationSecs) continue;
    const distKm = activity.distanceM / 1000;
    const pace = activity.durationSecs / distKm;
    const buckets: Array<[string, number]> = [["5k", 5], ["10k", 10], ["half-marathon", 21.1], ["marathon", 42.2]];
    for (const [label, km] of buckets) {
      if (distKm >= km * 0.95) {
        const projectedTime = activity.durationSecs * (km / distKm);
        if (!records[label] || projectedTime < records[label]!) {
          records[label] = Math.round(projectedTime);
        }
      }
    }
  }

  // Build memory snapshot (last 30 days)
  const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
  const recentRuns = runActivities.filter((a) => a.startedAt >= thirtyDaysAgo);
  const memorySnapshot: MemorySnapshot = {
    recentActivities: recentRuns.slice(0, 10).map((a) => ({
      date: a.startedAt.toISOString().split("T")[0],
      type: a.type,
      distanceKm: Math.round((a.distanceM ?? 0) / 100) / 10,
      avgPaceSecs: a.avgPace ?? 0,
    })),
    weeklyVolumeKm: Math.round(weeklyVolumeM / 100) / 10,
    longestRunKm: Math.round(Math.max(...recentRuns.map((a) => a.distanceM ?? 0)) / 100) / 10,
    consistencyScore: Math.min(recentRuns.length / 12, 1),
    recentInsight: "",
  };

  const fitnessLevel =
    memorySnapshot.weeklyVolumeKm > 60 ? "elite" :
    memorySnapshot.weeklyVolumeKm > 40 ? "advanced" :
    memorySnapshot.weeklyVolumeKm > 20 ? "intermediate" : "beginner";

  const guideName = existing?.guideName ?? "Guide";
  const coachPersonaId = (existing?.coachPersonaId ?? "plainstride_supportive_v1") as GuideProfilePayload["coachPersonaId"];
  const voiceProfileId = (existing?.voiceProfileId ?? "plainstride_warm_1") as GuideProfilePayload["voiceProfileId"];
  const goals = ((existing?.goals ?? []) as unknown) as GoalItem[];
  const version = (existing?.version ?? 0) + 1;

  await prisma.guideProfile.upsert({
    where: { userId },
    create: {
      userId,
      guideName,
      coachPersonaId,
      voiceProfileId,
      fitnessLevel,
      weeklyVolumeKm: memorySnapshot.weeklyVolumeKm,
      strengths: [],
      weaknesses: [],
      goals: goals as unknown as Prisma.InputJsonValue,
      records: records as Prisma.InputJsonValue,
      memorySnapshot: memorySnapshot as unknown as Prisma.InputJsonValue,
      lastBuiltAt: new Date(),
      version,
    },
    update: {
      fitnessLevel,
      weeklyVolumeKm: memorySnapshot.weeklyVolumeKm,
      records: records as Prisma.InputJsonValue,
      memorySnapshot: memorySnapshot as unknown as Prisma.InputJsonValue,
      lastBuiltAt: new Date(),
      version,
    },
  });

  const payload: GuideProfilePayload = {
    version,
    guideName,
    coachPersonaId,
    voiceProfileId,
    athlete: {
      fitnessLevel: fitnessLevel as GuideProfilePayload["athlete"]["fitnessLevel"],
      weeklyVolumeKm: memorySnapshot.weeklyVolumeKm,
      strengths: existing?.strengths ?? [],
      weaknesses: existing?.weaknesses ?? [],
      records,
    },
    goals,
    memorySnapshot,
    builtAt: new Date().toISOString(),
  };

  return payload;
}

export async function getGuideProfile(userId: string): Promise<GuideProfilePayload | null> {
  const profile = await getPrismaClient().guideProfile.findUnique({ where: { userId } });
  return profile ? guideProfilePayload(profile) : null;
}

function guideProfilePayload(profile: GuideProfile): GuideProfilePayload {
  return {
    version: profile.version,
    guideName: profile.guideName,
    coachPersonaId: profile.coachPersonaId as GuideProfilePayload["coachPersonaId"],
    voiceProfileId: profile.voiceProfileId as GuideProfilePayload["voiceProfileId"],
    athlete: {
      fitnessLevel: profile.fitnessLevel as GuideProfilePayload["athlete"]["fitnessLevel"],
      weeklyVolumeKm: profile.weeklyVolumeKm,
      preferredPaceSecs: profile.preferredPace ?? undefined,
      strengths: profile.strengths,
      weaknesses: profile.weaknesses,
      records: profile.records as PersonalRecords,
    },
    goals: profile.goals as unknown as GoalItem[],
    memorySnapshot: profile.memorySnapshot as unknown as MemorySnapshot,
    builtAt: (profile.lastBuiltAt ?? profile.updatedAt).toISOString(),
  };
}
