import { Prisma } from "@prisma/client";
import { buildActivitySuggestion } from "./activitySuggestion.js";
import { computeAthleteTrainingState } from "./athleteState.js";
import { enqueuePlanningEvent } from "./events.js";
import { generateInitialPlan, normalizeGoalInput } from "./generator.js";
import { createPlanVersionWithWorkouts, json } from "./persistence.js";
import { processDuePlanningEventsForUser, processPlanningEventById } from "./processor.js";
import { applyCalorieTargets, resolveLearnedRunPace } from "./runGoalEstimator.js";
import { getPrismaClient } from "../prisma.js";
import { loadTrainingPlanCatalog } from "../trainingPlanCatalog.js";
import { buildTrainingPlanState } from "../trainingPlans.js";
import type {
  ActivityForPlanning,
  CompleteWorkoutInput,
  CreateTrainingGoalInput,
  PlanningEventType,
  PlanningState,
  ActivitySuggestionResponse,
  PlanRecommendationsResponse,
  PlannedWorkoutForState,
  ReadinessForPlanning,
  RebuildPlanInput,
  SubmitReadinessInput,
  TodayPlanningResponse,
} from "./types.js";

export async function createGoal(
  userId: string,
  input: CreateTrainingGoalInput
): Promise<PlanningState> {
  const prisma = getPrismaClient();
  const [activities, profile, calibration] = await Promise.all([
    recentActivities(userId),
    prisma.runnerProfile.findUnique({ where: { userId } }),
    prisma.calibrationProgram.findUnique({ where: { userId } }),
  ]);
  const normalized = normalizeGoalInput({
    ...input,
    primaryMotivation: input.primaryMotivation ?? profile?.primaryMotivation as CreateTrainingGoalInput["primaryMotivation"],
    preferredRunGoalType: input.preferredRunGoalType ?? profile?.preferredRunGoalType as CreateTrainingGoalInput["preferredRunGoalType"],
  });
  const athleteState = computeAthleteTrainingState({
    activities,
    plannedWorkouts: [],
    readiness: [],
  });
  const generated = generateInitialPlan({
    goal: normalized,
    athleteState,
    reason: "initial",
  });
  const generation = {
    ...generated,
    workouts: applyCalorieTargets({
      workouts: generated.workouts,
      preferredRunGoalType: normalized.preferredRunGoalType,
      weightKilograms: profile?.weightKilograms,
      pace: resolveLearnedRunPace(activities, calibration?.status === "completed"),
    }),
  };

  await prisma.$transaction(async (tx) => {
    await tx.trainingPlan.updateMany({
      where: { userId, status: "active" },
      data: { status: "replaced", endedAt: new Date() },
    });
    await tx.trainingGoal.updateMany({
      where: { userId, status: "active" },
      data: { status: "archived" },
    });
    await tx.runnerProfile.upsert({
      where: { userId },
      create: {
        userId,
        primaryMotivation: normalized.primaryMotivation,
        preferredRunGoalType: normalized.preferredRunGoalType,
      },
      update: {
        primaryMotivation: normalized.primaryMotivation,
        preferredRunGoalType: normalized.preferredRunGoalType,
      },
    });

    const goal = await tx.trainingGoal.create({
      data: {
        userId,
        type: normalized.type,
        primaryModality: normalized.primaryModality,
        targetDate: input.targetDate ? new Date(input.targetDate) : null,
        targetDistanceMeters: input.targetDistanceMeters ?? null,
        targetEventName: input.targetEventName ?? null,
        priority: normalized.priority,
        preferredDays: normalized.preferredDays,
        daysPerWeekTarget: normalized.daysPerWeekTarget,
        maxSessionMinutes: normalized.maxSessionMinutes,
        riskTolerance: normalized.riskTolerance,
        primaryMotivation: normalized.primaryMotivation,
        preferredRunGoalType: normalized.preferredRunGoalType,
        constraints: json(normalized.constraints),
      },
    });
    const plan = await tx.trainingPlan.create({
      data: {
        userId,
        goalId: goal.id,
        currentPhase: generation.phase,
        source: "generated",
      },
    });
    const version = await createPlanVersionWithWorkouts(tx, {
      planId: plan.id,
      userId,
      versionNumber: 1,
      reason: "initial",
      summary: generation.summary,
      engineInputs: { athleteState: stateForJson(athleteState), goal: normalized },
      engineDecision: generation.engineDecision,
      workouts: generation.workouts,
    });
    await tx.athleteTrainingState.create({
      data: athleteStateData(userId, athleteState),
    });
    await tx.planAdjustmentEvent.create({
      data: {
        userId,
        planId: plan.id,
        fromVersionId: null,
        toVersionId: version.id,
        eventType: "goalUpdated",
        message: "Created an adaptive plan from the new goal.",
        changedWorkoutIds: [],
        engineInputs: json({ athleteState: stateForJson(athleteState), goal: normalized }),
        engineDecision: json(generation.engineDecision),
      },
    });
  });

  return assemblePlanningState(userId, "updated");
}

export async function getState(userId: string): Promise<PlanningState> {
  await processDueEvents(userId);
  return assemblePlanningState(userId, "stable");
}

export async function getToday(userId: string): Promise<TodayPlanningResponse> {
  await processDueEvents(userId);
  const state = await assemblePlanningState(userId, "stable");
  return {
    workout: state.today,
    adjustment: state.latestAdjustment,
    guideLine: state.today
      ? "Here is the best next session based on your current plan."
      : "Create a goal and I will build today's session.",
    planningStatus: state.planningStatus,
  };
}

export async function getActivitySuggestion(userId: string): Promise<ActivitySuggestionResponse> {
  await processDueEvents(userId);
  return buildActivitySuggestion(userId, "stable");
}

export async function getRecommendations(userId: string): Promise<PlanRecommendationsResponse> {
  await processDueEvents(userId);
  const [plan, activities, catalog] = await Promise.all([
    activePlanForUser(userId),
    recentActivities(userId),
    loadTrainingPlanCatalog(),
  ]);
  const activeTemplateId = activeTemplateIdFor(plan);
  const state = buildTrainingPlanState({
    activePlan: null,
    activities,
    catalog,
  });
  const recommendations = activeTemplateId
    ? state.recommendations.filter((recommendation) => recommendation.template.id !== activeTemplateId)
    : state.recommendations;

  return {
    recommendations,
    source: "server",
    generatedAt: new Date().toISOString(),
    activePlanId: plan?.id ?? null,
    catalogVersion: "training-plan-catalog-v1",
  };
}

export async function clearPlan(userId: string): Promise<PlanningState> {
  const prisma = getPrismaClient();
  const now = new Date();

  await prisma.$transaction(async (tx) => {
    await tx.trainingPlan.updateMany({
      where: { userId, status: "active" },
      data: { status: "replaced", endedAt: now },
    });
    await tx.trainingGoal.updateMany({
      where: { userId, status: "active" },
      data: { status: "archived" },
    });
  });

  return assemblePlanningState(userId, "updated");
}

export async function submitReadiness(
  userId: string,
  input: SubmitReadinessInput
): Promise<PlanningState> {
  const prisma = getPrismaClient();
  const plan = await activePlanForUser(userId);
  const checkIn = await prisma.readinessCheckIn.create({
    data: {
      userId,
      date: input.date ? new Date(input.date) : startOfDay(new Date()),
      energy: clampRating(input.energy ?? 3),
      soreness: clampRating(input.soreness ?? 1),
      sleepQuality: clampRating(input.sleepQuality ?? 3),
      stress: clampRating(input.stress ?? 1),
      motivation: clampRating(input.motivation ?? 3),
      illnessOrPain: input.illnessOrPain ?? false,
      notes: input.notes ?? null,
    },
  });
  const event = await enqueuePlanningEvent({
    userId,
    planId: plan?.id,
    type: checkIn.illnessOrPain ? "painFlagged" : "readinessSubmitted",
    sourceId: checkIn.id,
    priority: checkIn.illnessOrPain ? 100 : 80,
    dedupeKey: `user:${userId}:plan:${plan?.id ?? "none"}:normal_reassessment`,
    runAfter: checkIn.illnessOrPain ? new Date() : addMinutes(new Date(), planningDebounceMinutes()),
  });

  if (checkIn.illnessOrPain) await processPlanningEventById(event.id);
  return assemblePlanningState(userId, "updated");
}

export async function skipWorkout(userId: string, workoutId: string): Promise<PlanningState> {
  const prisma = getPrismaClient();
  const workout = await prisma.plannedWorkout.findFirst({
    where: { id: workoutId, userId },
    include: { planVersion: true },
  });
  if (!workout) {
    throw new Error("Planned workout not found.");
  }

  await prisma.plannedWorkout.update({
    where: { id: workout.id },
    data: { status: "skipped" },
  });
  const event = await enqueuePlanningEvent({
    userId,
    planId: workout.planVersion.planId,
    type: "workoutSkipped",
    sourceId: workout.id,
    priority: 90,
    dedupeKey: `user:${userId}:plan:${workout.planVersion.planId}:normal_reassessment`,
    runAfter: addMinutes(new Date(), planningDebounceMinutes()),
  });

  return assemblePlanningState(userId, event.runAfter <= new Date() ? "updated" : "reassessing");
}

export async function completeWorkout(
  userId: string,
  workoutId: string,
  input: CompleteWorkoutInput
): Promise<PlanningState> {
  const prisma = getPrismaClient();
  const workout = await prisma.plannedWorkout.findFirst({
    where: { id: workoutId, userId },
    include: { planVersion: true },
  });
  if (!workout) {
    throw new Error("Planned workout not found.");
  }

  await prisma.$transaction(async (tx) => {
    await tx.plannedWorkout.update({
      where: { id: workout.id },
      data: { status: "completed" },
    });
    await tx.workoutCompletion.create({
      data: {
        plannedWorkoutId: workout.id,
        userId,
        activityId: input.activityId ?? null,
        completedAt: input.completedAt ? new Date(input.completedAt) : new Date(),
        durationSeconds: input.durationSeconds ?? null,
        distanceMeters: input.distanceMeters ?? null,
        targetCalories: input.targetCalories ?? workout.targetCalories ?? null,
        energyKilocalories: input.energyKilocalories ?? null,
        avgPace: input.avgPace ?? null,
        avgHeartRate: input.avgHeartRate ?? null,
        avgPower: input.avgPower ?? null,
        perceivedEffort: input.perceivedEffort ?? null,
        completionQuality: input.completionQuality ?? "completed",
        notes: input.notes ?? null,
      },
    });
  });

  const event = await enqueuePlanningEvent({
    userId,
    planId: workout.planVersion.planId,
    type: "activityCompleted",
    sourceId: input.activityId ?? workout.id,
    priority: 50,
    dedupeKey: `user:${userId}:plan:${workout.planVersion.planId}:normal_reassessment`,
    runAfter: addMinutes(new Date(), planningDebounceMinutes()),
  });

  if (event.runAfter <= new Date()) {
    await processPlanningEventById(event.id);
  }
  return assemblePlanningState(userId, "reassessing");
}

export async function rebuildPlan(
  userId: string,
  input: RebuildPlanInput = {}
): Promise<PlanningState> {
  const plan = await activePlanForUser(userId);
  const event = await enqueuePlanningEvent({
    userId,
    planId: plan?.id,
    type: input.reason ?? "manualRebuild",
    priority: 100,
    dedupeKey: `user:${userId}:plan:${plan?.id ?? "none"}:manual_rebuild`,
  });
  await processPlanningEventById(event.id);
  return assemblePlanningState(userId, "updated");
}

export async function getAdjustments(userId: string) {
  return getPrismaClient().planAdjustmentEvent.findMany({
    where: { userId },
    orderBy: { createdAt: "desc" },
    take: 25,
  });
}

export async function enqueueActivityCompletedEvent(userId: string, activityId: string) {
  const plan = await activePlanForUser(userId);
  if (!plan) return null;

  return enqueuePlanningEvent({
    userId,
    planId: plan.id,
    type: "activityCompleted",
    sourceId: activityId,
    priority: 40,
    dedupeKey: `user:${userId}:plan:${plan.id}:normal_reassessment`,
    runAfter: addMinutes(new Date(), planningDebounceMinutes()),
  });
}

async function assemblePlanningState(
  userId: string,
  planningStatus: PlanningState["planningStatus"]
): Promise<PlanningState> {
  const prisma = getPrismaClient();
  const [goal, plan, athleteState, latestAdjustment] = await Promise.all([
    prisma.trainingGoal.findFirst({
      where: { userId, status: "active" },
      orderBy: { createdAt: "desc" },
    }),
    prisma.trainingPlan.findFirst({
      where: { userId, status: "active" },
      orderBy: { createdAt: "desc" },
      include: {
        versions: {
          orderBy: { versionNumber: "desc" },
          take: 1,
          include: {
            workouts: {
              orderBy: { scheduledDate: "asc" },
              include: {
                blocks: {
                  orderBy: { sortOrder: "asc" },
                  include: { steps: { orderBy: { sortOrder: "asc" } } },
                },
              },
            },
          },
        },
      },
    }),
    prisma.athleteTrainingState.findFirst({
      where: { userId },
      orderBy: { asOfDate: "desc" },
    }),
    prisma.planAdjustmentEvent.findFirst({
      where: { userId },
      orderBy: { createdAt: "desc" },
    }),
  ]);
  const version = plan?.versions[0] ?? null;
  const workouts = version?.workouts ?? [];
  const now = startOfDay(new Date());
  const today =
    workouts.find((workout) => sameDay(workout.scheduledDate, now) && workout.status === "planned") ??
    workouts.find((workout) => workout.scheduledDate >= now && workout.status === "planned") ??
    null;
  const recommendations = plan ? [] : await trainingPlanRecommendationsForUser(userId);

  return {
    goal,
    plan: plan ? { ...plan, versions: undefined } : null,
    currentVersion: version ? { ...version, workouts: undefined } : null,
    today,
    upcoming: workouts.filter((workout) => workout.scheduledDate >= now).slice(0, 10),
    recommendations,
    athleteState,
    latestAdjustment,
    planningStatus,
  };
}

async function processDueEvents(userId: string) {
  try {
    await processDuePlanningEventsForUser(userId);
  } catch (error) {
    console.error("[planning] Failed to process due planning events", error);
  }
}

async function activePlanForUser(userId: string) {
  return getPrismaClient().trainingPlan.findFirst({
    where: { userId, status: "active" },
    orderBy: { createdAt: "desc" },
    include: { goal: true },
  });
}

function activeTemplateIdFor(plan: Awaited<ReturnType<typeof activePlanForUser>>): string | null {
  const constraints = plan?.goal.constraints;
  if (!constraints || typeof constraints !== "object" || Array.isArray(constraints)) return null;
  const templateId = (constraints as Record<string, unknown>).templateID;
  return typeof templateId === "string" ? templateId : null;
}

async function recentActivities(userId: string): Promise<ActivityForPlanning[]> {
  return getPrismaClient().activity.findMany({
    where: { userId, startedAt: { gte: addDays(new Date(), -90) } },
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
  }) as Promise<ActivityForPlanning[]>;
}

async function trainingPlanRecommendationsForUser(userId: string) {
  const [activities, catalog] = await Promise.all([
    recentActivities(userId),
    loadTrainingPlanCatalog(),
  ]);
  return buildTrainingPlanState({
    activePlan: null,
    activities,
    catalog,
  }).recommendations;
}

function athleteStateData(userId: string, state: ReturnType<typeof computeAthleteTrainingState>) {
  return {
    userId,
    asOfDate: state.asOfDate,
    overallLoadScore: state.overallLoadScore,
    fatigueRisk: state.fatigueRisk,
    consistencyScore: state.consistencyScore,
    adherenceRate: state.adherenceRate,
    weeklyMinutes: state.weeklyMinutes,
    weeklyDistanceMeters: state.weeklyDistanceMeters,
    fourWeekAvgMinutes: state.fourWeekAvgMinutes,
    fourWeekAvgDistanceMeters: state.fourWeekAvgDistanceMeters,
    longestRecentSessionSeconds: state.longestRecentSessionSeconds,
    lastHardWorkoutAt: state.lastHardWorkoutAt,
    modalityBreakdown: json(state.modalityBreakdown),
  };
}

function stateForJson(state: ReturnType<typeof computeAthleteTrainingState>) {
  return {
    ...state,
    asOfDate: state.asOfDate.toISOString(),
    lastHardWorkoutAt: state.lastHardWorkoutAt?.toISOString() ?? null,
  };
}

function clampRating(value: number): number {
  return Math.min(5, Math.max(1, Math.round(value)));
}

function startOfDay(date: Date): Date {
  const result = new Date(date);
  result.setHours(0, 0, 0, 0);
  return result;
}

function sameDay(left: Date, right: Date): boolean {
  return left.toISOString().slice(0, 10) === right.toISOString().slice(0, 10);
}

function addDays(date: Date, days: number): Date {
  const result = new Date(date);
  result.setDate(result.getDate() + days);
  return result;
}

function addMinutes(date: Date, minutes: number): Date {
  const result = new Date(date);
  result.setMinutes(result.getMinutes() + minutes);
  return result;
}

function planningDebounceMinutes(): number {
  const configured = Number(process.env.PLANNING_EVENT_DEBOUNCE_MINUTES);
  return Number.isInteger(configured) && configured >= 0 ? configured : 45;
}
