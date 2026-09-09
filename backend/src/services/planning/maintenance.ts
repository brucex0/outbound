import { getPrismaClient } from "../prisma.js";
import { enqueuePlanningEvent } from "./events.js";
import { processDuePlanningEventsForUser } from "./processor.js";

export interface PlanningMaintenanceResult {
  activeUsersConsidered: number;
  eventsEnqueued: number;
  missedWorkoutsDetected: number;
  eventsProcessed: number;
}

export async function runPlanningMaintenance(now: Date = new Date()): Promise<PlanningMaintenanceResult> {
  const prisma = getPrismaClient();
  const activeSince = addDays(now, -activeUserWindowDays());
  const today = startOfUtcDay(now);
  const plans = await prisma.trainingPlan.findMany({
    where: {
      status: "active",
      OR: [
        { createdAt: { gte: activeSince } },
        { user: { activities: { some: { startedAt: { gte: activeSince } } } } },
        { user: { readinessCheckIns: { some: { createdAt: { gte: activeSince } } } } },
      ],
    },
    select: {
      id: true,
      userId: true,
      versions: {
        orderBy: { versionNumber: "desc" },
        take: 1,
        select: { workouts: { where: { status: "planned", scheduledDate: { lt: today } }, select: { id: true } } },
      },
    },
  });

  let eventsEnqueued = 0;
  let missedWorkoutsDetected = 0;
  let eventsProcessed = 0;
  for (const plan of plans) {
    const missed = plan.versions[0]?.workouts ?? [];
    if (missed.length > 0) {
      await prisma.plannedWorkout.updateMany({
        where: { id: { in: missed.map((workout) => workout.id) }, status: "planned" },
        data: { status: "missed" },
      });
      await enqueuePlanningEvent({
        userId: plan.userId,
        planId: plan.id,
        type: "workoutMissed",
        sourceId: missed[0]?.id,
        payload: { missedWorkoutCount: missed.length },
        priority: 70,
        dedupeKey: `user:${plan.userId}:plan:${plan.id}:normal_reassessment`,
      });
      missedWorkoutsDetected += missed.length;
      eventsEnqueued += 1;
    } else if (await hasChangedInputsSinceLastEvaluation(plan.userId)) {
      await enqueuePlanningEvent({
        userId: plan.userId,
        planId: plan.id,
        type: "dailyReview",
        priority: 10,
        dedupeKey: `user:${plan.userId}:plan:${plan.id}:daily:${today.toISOString().slice(0, 10)}`,
      });
      eventsEnqueued += 1;
    }
    const results = await processDuePlanningEventsForUser(plan.userId, now);
    eventsProcessed += results.filter((result) => result.status === "completed").length;
  }
  return { activeUsersConsidered: plans.length, eventsEnqueued, missedWorkoutsDetected, eventsProcessed };
}

async function hasChangedInputsSinceLastEvaluation(userId: string): Promise<boolean> {
  const prisma = getPrismaClient();
  const state = await prisma.athleteTrainingState.findFirst({
    where: { userId }, orderBy: { asOfDate: "desc" }, select: { asOfDate: true },
  });
  if (!state) return true;
  const [activity, readiness] = await Promise.all([
    prisma.activity.findFirst({ where: { userId, startedAt: { gt: state.asOfDate } }, select: { id: true } }),
    prisma.readinessCheckIn.findFirst({ where: { userId, createdAt: { gt: state.asOfDate } }, select: { id: true } }),
  ]);
  return Boolean(activity || readiness);
}

function activeUserWindowDays(): number {
  const configured = Number(process.env.PLANNING_ACTIVE_USER_WINDOW_DAYS);
  return Number.isInteger(configured) && configured > 0 ? configured : 14;
}

function startOfUtcDay(date: Date): Date {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
}

function addDays(date: Date, days: number): Date {
  return new Date(date.getTime() + days * 86_400_000);
}
