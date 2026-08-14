import type { PrismaClient } from "@prisma/client";
import { relativeDayWindow, safeTimeZoneIdentifier, zonedDateParts } from "../assistantActivityTools.js";

export async function loadAuthoritativeRunnerState(
  prisma: PrismaClient,
  userId: string,
  timeZoneIdentifier?: string | null
) {
  const now = new Date();
  const timeZone = safeTimeZoneIdentifier(timeZoneIdentifier);
  const localDate = zonedDateParts(now, timeZone);
  const localWeekday = new Date(Date.UTC(localDate.year, localDate.month - 1, localDate.day)).getUTCDay();
  const startOfWeek = relativeDayWindow(now, -((localWeekday + 6) % 7), timeZone).start;
  const startOfToday = relativeDayWindow(now, 0, timeZone).start;

  const [profile, activePlan, nextWorkouts, latestReadiness, recentActivities, weeklyAggregate, latestModel] = await Promise.all([
    prisma.runnerProfile.findUnique({ where: { userId } }),
    prisma.trainingPlan.findFirst({ where: { userId, status: "active" }, orderBy: { updatedAt: "desc" } }),
    prisma.plannedWorkout.findMany({
      where: { userId, status: "planned", scheduledDate: { gte: startOfToday } },
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
