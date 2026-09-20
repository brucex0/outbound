import type { PlanningEvent } from "@prisma/client";
import { adaptPlan } from "./adaptationEngine.js";
import { computeAthleteTrainingState } from "./athleteState.js";
import { claimDuePlanningEvents, failPlanningEvent } from "./events.js";
import { createPlanVersionWithWorkouts, json } from "./persistence.js";
import { getPrismaClient } from "../prisma.js";
import { applyCalorieTargets, resolveLearnedRunPace } from "./runGoalEstimator.js";
import { evaluationAdmission } from "./evaluationPolicy.js";
import { assessPlanFit } from "./planFit.js";
import { evaluateAndProposePlanAdjustment } from "./aiPlanningEvaluator.js";
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
  const pending = await prisma.planningEvent.findUniqueOrThrow({ where: { id: eventId } });
  const admission = await evaluationAdmission(pending);
  if (!admission.allowed) {
    await prisma.planningEvent.update({
      where: { id: eventId },
      data: { status: "pending", runAfter: admission.retryAt },
    });
    return {
      eventId,
      status: "ignored",
      message: `Evaluation deferred by ${admission.reason.replace("_", " ")}.`,
    };
  }
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
    const admission = await evaluationAdmission(event);
    if (!admission.allowed) {
      await prisma.planningEvent.update({
        where: { id: event.id },
        data: { status: "pending", runAfter: admission.retryAt },
      });
      return {
        eventId: event.id,
        status: "ignored",
        message: `Evaluation deferred by ${admission.reason.replace("_", " ")}.`,
      };
    }
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

    const [activities, plannedWorkouts, readiness, profile, calibration] = await Promise.all([
      prisma.activity.findMany({
        where: { userId: event.userId, deletedAt: null, startedAt: { gte: addDays(new Date(), -90) } },
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
          targetCalories: true,
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
      prisma.runnerProfile.findUnique({ where: { userId: event.userId } }),
      prisma.calibrationProgram.findUnique({ where: { userId: event.userId } }),
    ]);

    const athleteState = computeAthleteTrainingState({
      activities: activities as ActivityForPlanning[],
      plannedWorkouts: plannedWorkouts as PlannedWorkoutForState[],
      readiness: readiness as ReadinessForPlanning[],
    });
    const latestReadiness = readiness[0] as ReadinessForPlanning | undefined;
    const activeVersion = plan.versions[0];
    const planFit = assessPlanFit({
      activities: activities as ActivityForPlanning[],
      athleteState,
      readiness: latestReadiness,
    });
    const eventType = event.type as PlanningEventType;
    const adaptation = adaptPlan({
      eventType,
      goal: {
        type: plan.goal.type,
        activities: plan.goal.activities as import("./types.js").Modality[],
        baselineContext: plan.goal.baselineContext,
        preferredDays: plan.goal.preferredDays,
        preferredLongSessionDay: plan.goal.preferredLongSessionDay,
        daysPerWeekTarget: plan.goal.daysPerWeekTarget,
        maxSessionMinutes: plan.goal.maxSessionMinutes,
        riskTolerance: plan.goal.riskTolerance,
        primaryMotivation: plan.goal.primaryMotivation as "generalFitness" | "consistency" | "performance" | "weightLoss" | "weightMaintenance",
        preferredRunGoalType: plan.goal.preferredRunGoalType as "time" | "distance" | "calories",
        targetDate: plan.goal.targetDate,
        targetDistanceMeters: plan.goal.targetDistanceMeters,
        eventIntent: plan.goal.eventIntent as "finish" | "perform" | "targetTime" | null,
        targetTimeSeconds: plan.goal.targetTimeSeconds,
        reviewHorizonWeeks: plan.goal.reviewHorizonWeeks as 4 | 8 | 12 | null,
      },
      athleteState,
      latestReadiness,
    });
    const adaptedWorkouts = applyCalorieTargets({
      workouts: adaptation.workouts,
      preferredRunGoalType: plan.goal.preferredRunGoalType as "time" | "distance" | "calories",
      weightKilograms: profile?.weightKilograms,
      pace: resolveLearnedRunPace(activities as ActivityForPlanning[], calibration?.status === "completed"),
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
            recentRunSessions3Days: athleteState.recentRunSessions3Days,
            recentRunSessions7Days: athleteState.recentRunSessions7Days,
            recentRunDistance7DaysMeters: athleteState.recentRunDistance7DaysMeters,
            consecutiveActiveDays: athleteState.consecutiveActiveDays,
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
      const aiEvaluation = await evaluateAndProposePlanAdjustment({
        userId: event.userId,
        eventType,
        eventId: event.id,
        athleteState,
        recentActivities: activities as ActivityForPlanning[],
        planFit,
      });
      return {
        eventId: event.id,
        status: "completed",
        message: aiEvaluation.status === "proposed" || aiEvaluation.status === "existing"
          ? `Reassessed athlete state and prepared a reviewable plan adjustment. ${aiEvaluation.explanation}`
          : `Reassessed athlete state; no plan version change needed. ${aiEvaluation.explanation}`,
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
          recentRunSessions3Days: athleteState.recentRunSessions3Days,
          recentRunSessions7Days: athleteState.recentRunSessions7Days,
          recentRunDistance7DaysMeters: athleteState.recentRunDistance7DaysMeters,
          consecutiveActiveDays: athleteState.consecutiveActiveDays,
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
          planFit,
        },
        engineDecision: adaptation.engineDecision,
        workouts: adaptedWorkouts,
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
          engineInputs: json({ eventId: event.id, eventType, athleteState, planFit }),
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
