import { Prisma } from "@prisma/client";
import { buildCoachSystemPrompt } from "./ai.js";
import { getPrismaClient } from "./prisma.js";
import type { CoachProfilePayload, GoalItem, MemorySnapshot, PersonalRecords } from "../types/coach.js";

// Rebuild and persist the coach profile after each activity or on demand.
// Called by the activity completion webhook and the /coach/rebuild endpoint.
export async function rebuildCoachProfile(userId: string): Promise<CoachProfilePayload> {
  const prisma = getPrismaClient();
  const [user, activities] = await Promise.all([
    prisma.user.findUniqueOrThrow({
      where: { id: userId },
      include: { coachProfile: true },
    }),
    prisma.activity.findMany({
      where: { userId, type: "running" },
      orderBy: { startedAt: "desc" },
      take: 90,
    }),
  ]);

  const existing = user.coachProfile;
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

  const athleteProfile = {
    fitnessLevel,
    weeklyVolumeKm: memorySnapshot.weeklyVolumeKm,
    records,
    memorySnapshot,
  };

  const systemPrompt = await buildCoachSystemPrompt(athleteProfile);

  const coachName = existing?.coachName ?? "Coach";
  const personality = (existing?.personality ?? "encouraging") as CoachProfilePayload["personality"];
  const voiceId = existing?.voiceId ?? "default";
  const goals = ((existing?.goals ?? []) as unknown) as GoalItem[];
  const version = (existing?.version ?? 0) + 1;

  await prisma.coachProfile.upsert({
    where: { userId },
    create: {
      userId,
      coachName,
      personality,
      voiceId,
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

  const payload: CoachProfilePayload = {
    version,
    coachName,
    personality,
    voiceId,
    athlete: {
      fitnessLevel: fitnessLevel as CoachProfilePayload["athlete"]["fitnessLevel"],
      weeklyVolumeKm: memorySnapshot.weeklyVolumeKm,
      strengths: existing?.strengths ?? [],
      weaknesses: existing?.weaknesses ?? [],
      records,
    },
    goals,
    memorySnapshot,
    systemPrompt,
    builtAt: new Date().toISOString(),
  };

  return payload;
}
