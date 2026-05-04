import type { PlanningEvent } from "@prisma/client";
import { adaptPlan } from "./adaptationEngine.js";
import { computeAthleteTrainingState } from "./athleteState.js";
import { claimDuePlanningEvents, failPlanningEvent } from "./events.js";
import { createPlanVersionWithWorkouts, json } from "./persistence.js";
import { getPrismaClient } from "../prisma.js";
import type {
  ActivityForPlanning,
  PlanningEventResult,
  PlanningEventType,
  PlannedWorkoutForState,
  ReadinessForPlanning,
} from "./types.js";

export async function processDuePlanningEventsForUser(
  userId: string,
  now: Date = new Date()
): Promise<PlanningEventResult[]> {
  const events = await claimDuePlanningEvents({ userId, now, limit: 10 });
  const results: PlanningEventResult[] = [];
  for (const event of events) {
    results.push(await processPlanningEvent(event));
  }
  return results;
}

export async function processPlanningEventById(eventId: string): Promise<PlanningEventResult> {
  const prisma = getPrismaClient();
  const event = await prisma.planningEvent.update({
    where: { id: eventId },
    data: {
      status: "processing",
      attemptCount: { increment: 1 },
    },
  });
  return processPlanningEvent(event);
}

async function processPlanningEvent(event: PlanningEvent): Promise<PlanningEventResult> {
  const prisma = getPrismaClient();

  try {
    const plan = await prisma.trainingPlan.findFirst({
      where: {
        userId: event.userId,
        status: "active",
        ...(event.planId ? { id: event.planId } : {}),
      },
      include: {
        goal: true,
        versions: {
          orderBy: { versionNumber: "desc" },
          take: 1,
        },
      },
    });

    if (!plan) {
      const result = ignored(event.id, "No active planning plan exists.");
      await prisma.planningEvent.update({
        where: { id: event.id },
        data: { status: "ignored", processedAt: new Date() },
      });
      return result;
    }

    const [activities, plannedWorkouts, readiness] = await Promise.all([
      prisma.activity.findMany({
        where: { userId: event.userId, startedAt: { gte: addDays(new Date(), -90) } },
        orderBy: { startedAt: "desc" },
        select: {
          id: true,
          type: true,
          startedAt: true,
          durationSecs: true,
          distanceM: true,
          avgPace: true,
          avgHeartRate: true,
        },
      }),
      prisma.plannedWorkout.findMany({
        where: { userId: event.userId, scheduledDate: { gte: addDays(new Date(), -35) } },
        orderBy: { scheduledDate: "desc" },
        select: {
          id: true,
          scheduledDate: true,
          modality: true,
          stimulus: true,
          durationSeconds: true,
          distanceMeters: true,
          isKeyWorkout: true,
          status: true,
        },
      }),
      prisma.readinessCheckIn.findMany({
        where: { userId: event.userId, date: { gte: addDays(new Date(), -14) } },
        orderBy: { date: "desc" },
        select: {
          date: true,
          energy: true,
          soreness: true,
          sleepQuality: true,
          stress: true,
          motivation: true,
          illnessOrPain: true,
        },
      }),
    ]);

    const athleteState = computeAthleteTrainingState({
      activities: activities as ActivityForPlanning[],
      plannedWorkouts: plannedWorkouts as PlannedWorkoutForState[],
      readiness: readiness as ReadinessForPlanning[],
    });
    const latestReadiness = readiness[0] as ReadinessForPlanning | undefined;
    const activeVersion = plan.versions[0];
    const eventType = event.type as PlanningEventType;
    const adaptation = adaptPlan({
      eventType,
      goal: {
        type: plan.goal.type,
        primaryModality: plan.goal.primaryModality,
        preferredDays: plan.goal.preferredDays,
        daysPerWeekTarget: plan.goal.daysPerWeekTarget,
        maxSessionMinutes: plan.goal.maxSessionMinutes,
        riskTolerance: plan.goal.riskTolerance,
      },
      athleteState,
      latestReadiness,
    });

    if (!adaptation.shouldCreateVersion) {
      await prisma.$transaction(async (tx) => {
        await tx.athleteTrainingState.create({
          data: {
            userId: event.userId,
            asOfDate: athleteState.asOfDate,
            overallLoadScore: athleteState.overallLoadScore,
            fatigueRisk: athleteState.fatigueRisk,
            consistencyScore: athleteState.consistencyScore,
            adherenceRate: athleteState.adherenceRate,
            weeklyMinutes: athleteState.weeklyMinutes,
            weeklyDistanceMeters: athleteState.weeklyDistanceMeters,
            fourWeekAvgMinutes: athleteState.fourWeekAvgMinutes,
            fourWeekAvgDistanceMeters: athleteState.fourWeekAvgDistanceMeters,
            longestRecentSessionSeconds: athleteState.longestRecentSessionSeconds,
            lastHardWorkoutAt: athleteState.lastHardWorkoutAt,
            modalityBreakdown: json(athleteState.modalityBreakdown),
          },
        });
        await tx.planningEvent.update({
          where: { id: event.id },
          data: { status: "completed", processedAt: new Date() },
        });
      });
      return {
        eventId: event.id,
        status: "completed",
        message: "Reassessed athlete state; no plan version change needed.",
      };
    }

    const versionNumber = (activeVersion?.versionNumber ?? 0) + 1;
    const created = await prisma.$transaction(async (tx) => {
      await tx.athleteTrainingState.create({
        data: {
          userId: event.userId,
          asOfDate: athleteState.asOfDate,
          overallLoadScore: athleteState.overallLoadScore,
          fatigueRisk: athleteState.fatigueRisk,
          consistencyScore: athleteState.consistencyScore,
          adherenceRate: athleteState.adherenceRate,
          weeklyMinutes: athleteState.weeklyMinutes,
          weeklyDistanceMeters: athleteState.weeklyDistanceMeters,
          fourWeekAvgMinutes: athleteState.fourWeekAvgMinutes,
          fourWeekAvgDistanceMeters: athleteState.fourWeekAvgDistanceMeters,
          longestRecentSessionSeconds: athleteState.longestRecentSessionSeconds,
          lastHardWorkoutAt: athleteState.lastHardWorkoutAt,
          modalityBreakdown: json(athleteState.modalityBreakdown),
        },
      });
      await tx.trainingPlan.update({
        where: { id: plan.id },
        data: { currentPhase: (adaptation.engineDecision.phase as string | undefined) ?? plan.currentPhase },
      });
      const version = await createPlanVersionWithWorkouts(tx, {
        planId: plan.id,
        userId: event.userId,
        versionNumber,
        reason: adaptation.reason,
        summary: adaptation.summary,
        engineInputs: {
          eventId: event.id,
          eventType,
          athleteState,
        },
        engineDecision: adaptation.engineDecision,
        workouts: adaptation.workouts,
      });
      await tx.planAdjustmentEvent.create({
        data: {
          userId: event.userId,
          planId: plan.id,
          fromVersionId: activeVersion?.id ?? null,
          toVersionId: version.id,
          eventType,
          message: adaptation.adjustmentMessage,
          changedWorkoutIds: [],
          engineInputs: json({ eventId: event.id, eventType, athleteState }),
          engineDecision: json(adaptation.engineDecision),
        },
      });
      await tx.planningEvent.update({
        where: { id: event.id },
        data: { status: "completed", processedAt: new Date() },
      });
      return version;
    });

    return {
      eventId: event.id,
      status: "completed",
      createdVersionId: created.id,
      message: adaptation.adjustmentMessage,
    };
  } catch (error) {
    await failPlanningEvent(event.id, error instanceof Error ? error : new Error(String(error)));
    return {
      eventId: event.id,
      status: "failed",
      message: error instanceof Error ? error.message : "Planning event failed.",
    };
  }
}

function ignored(eventId: string, message: string): PlanningEventResult {
  return { eventId, status: "ignored", message };
}

function addDays(date: Date, days: number): Date {
  const result = new Date(date);
  result.setDate(result.getDate() + days);
  return result;
}
