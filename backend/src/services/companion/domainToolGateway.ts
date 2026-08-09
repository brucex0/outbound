import type { PrismaClient } from "@prisma/client";

export async function loadAuthoritativeRunnerState(prisma: PrismaClient, userId: string) {
  const now = new Date();
  const startOfWeek = new Date(now);
  startOfWeek.setUTCDate(now.getUTCDate() - ((now.getUTCDay() + 6) % 7));
  startOfWeek.setUTCHours(0, 0, 0, 0);

  const [profile, activePlan, nextWorkouts, latestReadiness, recentActivities, weeklyAggregate, latestModel] = await Promise.all([
    prisma.runnerProfile.findUnique({ where: { userId } }),
    prisma.trainingPlan.findFirst({ where: { userId, status: "active" }, orderBy: { updatedAt: "desc" } }),
    prisma.plannedWorkout.findMany({
      where: { userId, status: "planned", scheduledDate: { gte: new Date(now.setHours(0, 0, 0, 0)) } },
      orderBy: { scheduledDate: "asc" },
      take: 8,
    }),
    prisma.readinessCheckIn.findFirst({ where: { userId }, orderBy: { date: "desc" } }),
    prisma.activity.findMany({
      where: { userId },
      orderBy: { startedAt: "desc" },
      take: 12,
      select: { id: true, type: true, title: true, startedAt: true, durationSecs: true, distanceM: true, avgPace: true },
    }),
    prisma.activity.aggregate({
      where: { userId, startedAt: { gte: startOfWeek } },
      _sum: { distanceM: true, durationSecs: true },
      _count: true,
    }),
    prisma.runnerModelVersion.findFirst({ where: { userId }, orderBy: { versionNumber: "desc" } }),
  ]);

  return {
    profile,
    activePlan,
    nextWorkouts,
    latestReadiness,
    recentActivities,
    weeklyAggregate,
    runnerModelVersion: latestModel?.id ?? "runner-model-empty",
  };
}

