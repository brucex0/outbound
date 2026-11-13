import { runningProgressionBlocked } from "./generator.js";
import { accountTimeZone, accountDateLabel } from "../accountCalendar.js";
import { runningConstraintReview, retainRunningPlanForReview } from "./runningPlanReview.js";
import { loadRunningPlanningContext } from "./runningContext.js";
import { parseRunWalkProgramme } from "./runWalkProgramme.js";
import { withSessionEffort } from "./sessionEffort.js";
import type { PlanningEvent } from "@prisma/client";
import { refreshCatalogPlanInTransaction } from "./catalogRefresh.js";
import { adaptPlan } from "./adaptationEngine.js";
import { computeAthleteTrainingState } from "./athleteState.js";
import { claimDuePlanningEvents, failPlanningEvent } from "./events.js";
import { createPlanVersionWithWorkouts, json, lockPlanningUser } from "./persistence.js";
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
  let assessedPlan: { planId: string; versionId?: string } | undefined;

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
          include: { workouts: { select: { scheduledDate: true, modality: true, durationSeconds: true } } },
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

    assessedPlan = { planId: plan.id, versionId: plan.versions[0]?.id };

    // Catalogue plans must never pass through generic stimulus generation. Reads
    // and rollover also use this source-aware path, under the same user lock.
    if (plan.source === "catalog" && !["activityCompleted", "planReviewRequested", "dailyReview"].includes(event.type)) {
      const handled = await prisma.$transaction(async (tx) => {
        await lockPlanningUser(tx, event.userId);
        const active = await refreshCatalogPlanInTransaction(tx, event.userId, new Date(), event.type as PlanningEventType, plan.id);
        await tx.planningEvent.update({ where: { id: event.id }, data: { status: active ? "completed" : "ignored", processedAt: new Date() } });
        return active;
      }, { timeout: 30_000 });
      return { eventId: event.id, status: handled ? "completed" : "ignored", message: handled ? "Reassessed the selected training programme." : "The original training programme is no longer active." };
    }

    const [rawActivities, plannedWorkouts, readiness, profile, calibration] = await Promise.all([
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
      prescription: true,
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

    const activities = await withSessionEffort(prisma, event.userId, rawActivities);
    let athleteState = computeAthleteTrainingState({
      activities: activities as ActivityForPlanning[],
      plannedWorkouts: plannedWorkouts as PlannedWorkoutForState[],
      readiness: readiness as ReadinessForPlanning[],
    });
    let latestReadiness = readiness[0] as ReadinessForPlanning | undefined;
    const activeVersion = plan.versions[0];
    const planFit = assessPlanFit({
      activities: activities as ActivityForPlanning[],
      athleteState,
      readiness: latestReadiness,
    });
    const eventType = event.type as PlanningEventType;
    const goal = {
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
        constraints: plan.goal.constraints as Record<string, unknown>,
      };
    const calendarNow = new Date();
    const timeZone = await accountTimeZone(event.userId, undefined, prisma);
    let adaptation = adaptPlan({
      eventType,
      now: calendarNow,
      scheduleStart: accountDateLabel(calendarNow, timeZone),
      planStart: accountDateLabel(plan.createdAt, timeZone),
      previousWorkouts: activeVersion?.workouts,
      progressionBlocked: runningProgressionBlocked(readiness, plannedWorkouts, accountDateLabel(calendarNow, timeZone)),
      basePlan: plan.source === "catalog" ? { phase: plan.currentPhase as import("./types.js").TrainingPlanPhase, summary: "Catalogue review", workouts: [], engineDecision: (activeVersion?.engineDecision as Record<string, unknown>) ?? {} } : undefined,
      goal,
      runWalkProgramme: parseRunWalkProgramme((activeVersion?.engineDecision as Record<string, unknown> | undefined)?.runWalkProgramme),
      athleteState,
      latestReadiness,
    });
    let adaptedWorkouts = applyCalorieTargets({
      workouts: adaptation.workouts,
      preferredRunGoalType: plan.goal.preferredRunGoalType as "time" | "distance" | "calories",
      weightKilograms: profile?.weightKilograms,
      pace: resolveLearnedRunPace(activities as ActivityForPlanning[], calibration?.status === "completed"),
    });

    if (!adaptation.shouldCreateVersion || plan.source === "catalog") {
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
      await lockPlanningUser(tx, event.userId);
      const current = await tx.trainingPlan.findFirst({ where: { id: plan.id, status: "active" }, include: { versions: { orderBy: { versionNumber: "desc" }, take: 1 } } });
      if (!current || current.versions[0]?.id !== activeVersion?.id || current.updatedAt.getTime() !== plan.updatedAt.getTime()) {
        await tx.planningEvent.update({ where: { id: event.id }, data: { status: current ? "pending" : "ignored", runAfter: new Date() } });
        return null;
      }
      if (goal.activities.includes("run")) {
        const context = await loadRunningPlanningContext(tx, { userId: event.userId, planId: plan.id, goal,
          previousProgramme: (current.versions[0]?.engineDecision as Record<string, unknown> | undefined)?.runWalkProgramme,
          now: new Date(), createdAt: plan.createdAt, enableProgramme: goal.baselineContext !== "currentlyActive" });
        athleteState = context.athleteState;
        latestReadiness = context.latestReadiness;
        adaptation = adaptPlan({ eventType, goal, athleteState, latestReadiness, runWalkProgramme: context.state, previousWorkouts: activeVersion?.workouts,
          now: calendarNow, scheduleStart: accountDateLabel(calendarNow, timeZone), planStart: accountDateLabel(plan.createdAt, timeZone),
          progressionBlocked: runningProgressionBlocked(readiness, plannedWorkouts, accountDateLabel(calendarNow, timeZone)) });
        adaptedWorkouts = applyCalorieTargets({ workouts: adaptation.workouts,
          preferredRunGoalType: goal.preferredRunGoalType, weightKilograms: profile?.weightKilograms,
          pace: resolveLearnedRunPace(context.activities, calibration?.status === "completed") });
      }
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
      createdVersionId: created?.id,
      message: adaptation.adjustmentMessage,
    };
  } catch (error) {
    const review = runningConstraintReview(error);
    if (review && assessedPlan) {
      try {
        const retained = await prisma.$transaction(async (tx) => {
          await lockPlanningUser(tx, event.userId);
          const retained = await retainRunningPlanForReview(tx, event.userId, review, assessedPlan);
          await tx.planningEvent.update({ where: { id: event.id }, data: { status: retained ? "completed" : "ignored", processedAt: new Date() } });
          return retained;
        }, { timeout: 30_000 });
        return { eventId: event.id, status: retained ? "completed" : "ignored", message: retained ? "The existing plan needs schedule review; issued workouts are retained." : "The assessed plan version is no longer active." };
      } catch (reviewError) {
        console.error("[planning] running_plan_review_failed", { operation: "event", errorType: reviewError instanceof Error ? reviewError.name : "unknown" });
        await failPlanningEvent(event.id, reviewError instanceof Error ? reviewError : new Error("Unable to retain planning review."));
        return { eventId: event.id, status: "failed", message: "Unable to retain the planning review." };
      }
    }
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
