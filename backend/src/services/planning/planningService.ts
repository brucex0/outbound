import { accountTimeZone, accountDateLabel, planningCalendarContext } from "../accountCalendar.js";
import { preferredLongRunDays, LongRunDaysError } from "./longRunDays.js";
import { runningPlanReview, runningReviewDecision, clearRunningPlanReview } from "./runningPlanReview.js";
import { recordWorkoutCompletion } from "./workoutCompletion.js";
import { issueWorkout, withIssuanceTransaction } from "./workoutIssuance.js";
import { freshReadiness } from "./runWalkProgramme.js";
import { RunningScheduleError } from "./runningDosePolicy.js";
import { withSessionEffort } from "./sessionEffort.js";
import { benchmarkConstraints, resolveRunningBenchmark, sameRunningBenchmark, RunningBenchmarkError, RunningBenchmarkConflictError } from "./runningBenchmark.js";
import { assessGoalFeasibility, GoalFeasibilityError } from "./goalFeasibility.js";
import { Prisma } from "@prisma/client";
import { buildActivitySuggestion } from "./activitySuggestion.js";
import { computeAthleteTrainingState } from "./athleteState.js";
import { enqueuePlanningEvent } from "./events.js";
import { allowsShortRuns, generateInitialPlan, normalizeGoalInput } from "./generator.js";
import { createPlanVersionWithWorkouts, json, lockPlanningUser, isOptionalWorkout, protectedEditedWorkouts, workoutSlotKey } from "./persistence.js";
import { processDuePlanningEventsForUser, processPlanningEventById } from "./processor.js";
import { applyCalorieTargets, resolveLearnedRunPace } from "./runGoalEstimator.js";
import { getPlanIntakeContext, PlanningContextChangedError } from "./planIntake.js";
import { refreshGeneratedPlan, refreshGeneratedPlanInTransaction, validateGeneratedPlanForWrite } from "./planRefresh.js";
import { generateCatalogWindow } from "./catalogProgramme.js";
import { raceRoadmap } from "./raceRoadmap.js";
import { getPrismaClient } from "../prisma.js";
import { loadTrainingPlanCatalog } from "../trainingPlanCatalog.js";
import { buildTrainingPlanState } from "../trainingPlans.js";
import {
  catalogFocusDistanceMeters,
  catalogFocusGoalType,
  readCatalogRecommendationSelection,
} from "./catalogTemplate.js";
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
  input = { ...input, constraints: benchmarkConstraints(input, new Date()) };
  const eligibility = assessGoalFeasibility(input, new Date());
  if (!eligibility.eligible) {
    console.info("[planning] goal_feasibility_decision", { result: "blocked" });
    throw new GoalFeasibilityError();
  }
  const prisma = getPrismaClient();
  const timeZone = await accountTimeZone(userId);
  const selection = readCatalogRecommendationSelection(input.constraints);
  if (selection && preferredLongRunDays(input.constraints).length) throw new LongRunDaysError("catalog");
  const [activities, plannedWorkouts, readiness, profile, calibration] = await Promise.all([
    recentActivities(userId),
    recentPlannedWorkouts(userId),
    recentReadiness(userId),
    prisma.runnerProfile.findUnique({ where: { userId } }),
    prisma.calibrationProgram.findUnique({ where: { userId } }),
  ]);
  let selectedRecommendation: Awaited<ReturnType<typeof resolveCatalogRecommendation>> | null = null;
  if (selection) selectedRecommendation = await resolveCatalogRecommendation(userId, activities, selection);
  const submittedFocus = catalogFocusForGoalType(input.type);
  if (submittedFocus && !selection) {
    throw new Error("A catalog focus can only be used with a selected recommendation.");
  }
  if (submittedFocus && selectedRecommendation?.template.focus !== submittedFocus) {
    throw new Error("The selected goal focus does not match the chosen plan recommendation.");
  }
  const selectedDistance = selectedRecommendation
    ? catalogFocusDistanceMeters(selectedRecommendation.template.focus)
    : null;
  const goalInput = {
    ...(submittedFocus
      ? {
          ...input,
          type: selectedRecommendation ? catalogFocusGoalType(selectedRecommendation.template.focus) : "endurance",
          targetDistanceMeters: input.targetDistanceMeters ?? catalogFocusDistanceMeters(submittedFocus),
        }
      : input),
    ...(selectedRecommendation
      ? {
          daysPerWeekTarget: input.daysPerWeekTarget ?? selectedRecommendation.sessionsPerWeek,
          maxSessionMinutes: input.maxSessionMinutes ?? selectedRecommendation.longSessionMinutes,
          ...(selectedDistance ? { targetDistanceMeters: selectedDistance } : {}),
        }
      : {}),
  };
  // Resolve the authoritative selected distance before the final admission check.
  // An omitted request distance must not bypass a selected marathon's guard.
  const resolvedEligibility = assessGoalFeasibility(goalInput, new Date());
  console.info("[planning] goal_feasibility_decision", { result: resolvedEligibility.eligible ? "eligible" : "blocked" });
  if (!resolvedEligibility.eligible) throw new GoalFeasibilityError();
  if (!profile?.sexAtBirth || !profile.birthDate || profile.weightKilograms == null) {
    throw new Error("Birth date, sex assigned at birth, and weight are required to create a personalized plan.");
  }
  const age = ageYears(profile.birthDate, new Date());
  if (age < 13 || age > 100) {
    throw new Error("Enter a valid birth date before creating a personalized plan.");
  }
  if (goalInput.type === "eventPreparation" && (!goalInput.targetDate || !goalInput.targetDistanceMeters) && !selectedRecommendation) {
    throw new Error("Event date and distance are required for an event-preparation plan.");
  }
  if (goalInput.intakeContextVersion || goalInput.intakeBaseline?.source === "recent_activities") {
    const currentContext = await getPlanIntakeContext(userId, goalInput.type);
    const submittedBaseline = goalInput.intakeBaseline;
    const observed = currentContext.observedBaseline;
    if (goalInput.intakeContextVersion && currentContext.contextVersion !== goalInput.intakeContextVersion
      || submittedBaseline?.source === "recent_activities" && (!observed || observed.confidence !== "high"
        || observed.sessionsPerWeek !== submittedBaseline.recentSessionsPerWeek
        || observed.comfortableMinutes !== submittedBaseline.comfortableDurationMinutes)) {
      throw new PlanningContextChangedError();
    }
  }
  const normalized = normalizeGoalInput({
    ...goalInput,
    primaryMotivation: goalInput.primaryMotivation ?? profile?.primaryMotivation as CreateTrainingGoalInput["primaryMotivation"],
    preferredRunGoalType: goalInput.preferredRunGoalType ?? profile?.preferredRunGoalType as CreateTrainingGoalInput["preferredRunGoalType"],
  });
  if (!selectedRecommendation && normalized.activities.includes("run") && normalized.maxSessionMinutes < 25 && !allowsShortRuns(normalized)) {
    throw new RunningScheduleError("session_minimum");
  }
  const athleteState = computeAthleteTrainingState({
    activities,
    plannedWorkouts,
    readiness: normalized.activities.includes("run") ? [freshReadiness(readiness, new Date())].filter((row): row is ReadinessForPlanning => row != null) : readiness,
  });
  const generated = selectedRecommendation ? null : generateInitialPlan({
    goal: normalized,
    athleteState,
    reason: "initial",
    scheduleStart: accountDateLabel(new Date(), timeZone),
  });
  const generation = selectedRecommendation
    ? generateCatalogWindow({ template: selectedRecommendation.template, goal: normalized, now: new Date(), createdAt: new Date(), timeZone,
        evidence: [], readyToAdvance: false, explicitDifficulty: false, athleteState })
    : { ...generated!, workouts: applyCalorieTargets({
        workouts: generated!.workouts, preferredRunGoalType: normalized.preferredRunGoalType,
        weightKilograms: profile?.weightKilograms,
        pace: resolveLearnedRunPace(activities, calibration?.status === "completed"),
      }) };


  await prisma.$transaction(async (tx) => {
    await lockPlanningUser(tx, userId);
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
        activities: normalized.activities,
        baselineContext: normalized.baselineContext,
        targetDate: goalInput.targetDate ? new Date(goalInput.targetDate) : null,
        targetDistanceMeters: normalized.targetDistanceMeters ?? null,
        targetEventName: goalInput.targetEventName ?? null,
        eventIntent: goalInput.type === "eventPreparation" ? goalInput.eventIntent ?? "finish" : null,
        targetTimeSeconds: goalInput.type === "eventPreparation" ? goalInput.targetTimeSeconds ?? null : null,
        reviewHorizonWeeks: goalInput.type === "eventPreparation" ? null : goalInput.reviewHorizonWeeks ?? 8,
        successSignal: goalInput.successSignal ?? null,
        goalDescription: goalInput.goalDescription ?? null,
        intakeContextVersion: goalInput.intakeContextVersion ?? null,
        priority: normalized.priority,
        preferredDays: normalized.preferredDays,
        preferredLongSessionDay: normalized.preferredLongSessionDay,
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
        source: selectedRecommendation ? "catalog" : "generated",
      },
    });
    const version = await createPlanVersionWithWorkouts(tx, {
      planId: plan.id,
      userId,
      versionNumber: 1,
      reason: "initial",
      summary: generation.summary,
      engineInputs: {
        athleteState: stateForJson(athleteState),
        goal: normalized,
        planningProfile: {
          ageYears: age,
          sexAtBirth: profile.sexAtBirth,
          weightKilograms: profile.weightKilograms,
        },
      },
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
    await tx.user.updateMany({
      where: { id: userId, onboardingStatus: "pending" },
      data: { onboardingStatus: "completed" },
    });
  });

  return assemblePlanningState(userId, "updated");
}

export interface UpdateRaceGoalInput {
  targetDate: string;
  targetDistanceMeters: number;
  eventIntent: "finish" | "perform" | "targetTime";
  targetTimeSeconds?: number | null;
  daysPerWeekTarget: number;
  maxSessionMinutes: number;
  shortRunSessions: boolean;
  optionalMobility: boolean;
}

export async function updateRaceGoal(userId: string, goalId: string, input: UpdateRaceGoalInput): Promise<PlanningState> {
  await getPrismaClient().$transaction(async (tx) => {
    await lockPlanningUser(tx, userId);
    const plan = await tx.trainingPlan.findFirst({ where: { userId, goalId, status: "active", source: "generated", goal: { type: "eventPreparation" } }, include: { goal: true } });
    if (!plan) throw new Error("The active race goal changed. Refresh the plan before editing.");
    const eligibility = assessGoalFeasibility({ ...plan.goal, targetDate: input.targetDate, targetDistanceMeters: input.targetDistanceMeters }, new Date());
    console.info("[planning] goal_feasibility_decision", { result: eligibility.eligible ? "eligible" : "blocked" });
    if (!eligibility.eligible) throw new GoalFeasibilityError();
    const constraints = plan.goal.constraints as Record<string, unknown>;
    const targetTime = input.eventIntent === "targetTime" ? input.targetTimeSeconds ?? null : null;
    const unchanged = plan.goal.targetDate?.getTime() === new Date(input.targetDate).getTime()
      && plan.goal.targetDistanceMeters === input.targetDistanceMeters && plan.goal.eventIntent === input.eventIntent
      && plan.goal.targetTimeSeconds === targetTime && plan.goal.daysPerWeekTarget === input.daysPerWeekTarget
      && plan.goal.maxSessionMinutes === input.maxSessionMinutes
      && (constraints.shortRunSessions === "true") === input.shortRunSessions
      && (constraints.optionalMobility === "true") === input.optionalMobility;
    if (unchanged) {
      await validateGeneratedPlanForWrite(tx, userId, new Date());
      await clearRunningPlanReview(tx, userId, plan.id);
      return;
    }
    await tx.trainingGoal.update({ where: { id: goalId }, data: {
      targetDate: new Date(input.targetDate), targetDistanceMeters: input.targetDistanceMeters,
      eventIntent: input.eventIntent, targetTimeSeconds: input.eventIntent === "targetTime" ? input.targetTimeSeconds : null,
      daysPerWeekTarget: input.daysPerWeekTarget, maxSessionMinutes: input.maxSessionMinutes,
      constraints: json({ ...constraints, shortRunSessions: String(input.shortRunSessions), optionalMobility: String(input.optionalMobility) }),
    } });
    await refreshGeneratedPlanInTransaction(tx, userId, new Date(), true);
  }, { timeout: 30_000 });
  return assemblePlanningState(userId, "updated");
}

/** Correct/remove the same goal's benchmark; replan under the edit/completion lock. */
export async function updateRunningBenchmark(userId: string, goalId: string, runningBenchmark: unknown): Promise<PlanningState> {
  if (runningBenchmark === undefined) throw new RunningBenchmarkError("missing_input");
  await getPrismaClient().$transaction(async (tx) => {
    await lockPlanningUser(tx, userId);
    const plan = await tx.trainingPlan.findFirst({ where: { userId, goalId, status: "active" }, include: { goal: true } });
    if (!plan) throw new RunningBenchmarkConflictError();
    const constraints = benchmarkConstraints({ activities: plan.goal.activities,
      constraints: { ...(plan.goal.constraints as Record<string, unknown>), runningBenchmark: undefined }, runningBenchmark }, new Date());
    if (sameRunningBenchmark((plan.goal.constraints as Record<string, unknown>).runningBenchmark, constraints.runningBenchmark)) return;
    await tx.trainingGoal.update({ where: { id: goalId }, data: { constraints: json(constraints) } });
    await refreshGeneratedPlanInTransaction(tx, userId, new Date(), true);
    const result = resolveRunningBenchmark(constraints.runningBenchmark, new Date());
    console.info("[planning] running_benchmark_updated", { status: result.status, source: result.source, present: result.status !== "absent" });
  }, { timeout: 30_000 });
  return assemblePlanningState(userId, "updated");
}

export async function getState(userId: string): Promise<PlanningState> {
  await processDueEvents(userId);
  await refreshGeneratedPlan(userId);
  const state = await assemblePlanningState(userId, "stable");
  return { ...state, editContext: (await buildActivitySuggestion(userId)).editContext ?? null };
}

export async function getToday(userId: string): Promise<TodayPlanningResponse> {
  await processDueEvents(userId);
  await refreshGeneratedPlan(userId);
  const state = await assemblePlanningState(userId, "stable");
  return {
    workout: state.today,
    runningPlanReview: state.runningPlanReview,
    adjustment: state.latestAdjustment,
    guideLine: state.today
      ? "Here is the best next session based on your current plan."
      : "Create a goal and I will build today's session.",
    planningStatus: state.planningStatus,
  };
}

export async function getActivitySuggestion(userId: string): Promise<ActivitySuggestionResponse> {
  await processDueEvents(userId);
  await refreshGeneratedPlan(userId);
  return buildActivitySuggestion(userId, "stable");
}

export async function getRecommendations(userId: string): Promise<PlanRecommendationsResponse> {
  await processDueEvents(userId);
  await refreshGeneratedPlan(userId);
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
    await lockPlanningUser(tx, userId);
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

  const changed = await prisma.$transaction(async (tx) => {
    await lockPlanningUser(tx, userId);
    const current = await tx.plannedWorkout.findUniqueOrThrow({ where: { id: workout.id } });
    if (current.status === "completed" || current.status === "skipped") return false;
    await tx.plannedWorkout.update({ where: { id: workout.id }, data: { status: "skipped" } });
    const replacements = await tx.plannedWorkout.findMany({
      where: { userId, id: { not: workout.id }, planVersion: { planId: workout.planVersion.planId }, scheduledDate: workout.scheduledDate, status: "planned" }, select: { id: true, prescription: true },
    });
    await tx.plannedWorkout.updateMany({ where: { id: { in: replacements.filter((replacement) => isOptionalWorkout(replacement) === isOptionalWorkout(workout)).map((replacement) => replacement.id) }, status: "planned" }, data: { status: "superseded" } });
    return true;
  });
  if (!changed || isOptionalWorkout(workout)) return assemblePlanningState(userId, "stable");
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

  const changed = await prisma.$transaction(async (tx) => {
    await lockPlanningUser(tx, userId);
    const result = await recordWorkoutCompletion(tx, userId, workoutId, input, input.performedWorkoutReference);
    return result.changed;
  });
  if (!changed || isOptionalWorkout(workout)) return assemblePlanningState(userId, "stable");

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

export async function requestPlanReview(userId: string): Promise<{
  status: "proposed" | "unchanged" | "deferred" | "noPlan";
  adjustmentId?: string;
  explanation: string;
}> {
  const prisma = getPrismaClient();
  const plan = await activePlanForUser(userId);
  if (!plan) return { status: "noPlan", explanation: "You need an active training plan before I can recalibrate it." };

  const existing = await prisma.personalizationAdjustment.findFirst({
    where: { userId, status: "proposed" },
    orderBy: { createdAt: "desc" },
  });
  if (existing) return { status: "proposed", adjustmentId: existing.id, explanation: existing.explanation };

  const event = await enqueuePlanningEvent({
    userId,
    planId: plan.id,
    type: "planReviewRequested",
    priority: 95,
    dedupeKey: `user:${userId}:plan:${plan.id}:assistant_plan_review`,
  });
  const result = await processPlanningEventById(event.id);
  if (result.message.toLowerCase().includes("deferred")) {
    return { status: "deferred", explanation: result.message };
  }

  const adjustment = await prisma.personalizationAdjustment.findFirst({
    where: { userId, status: "proposed" },
    orderBy: { createdAt: "desc" },
  });
  if (adjustment) return { status: "proposed", adjustmentId: adjustment.id, explanation: adjustment.explanation };
  return { status: "unchanged", explanation: result.message };
}

export async function getAdjustments(userId: string) {
  return getPrismaClient().planAdjustmentEvent.findMany({
    where: { userId },
    orderBy: { createdAt: "desc" },
    take: 25,
  });
}

export async function enqueueActivityCompletedEvent(userId: string, activityId: string, performedPlanId?: string) {
  const plan = await activePlanForUser(userId);
  if (!plan || performedPlanId && plan.id !== performedPlanId) return null;

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

export async function assemblePlanningState(
  userId: string,
  planningStatus: PlanningState["planningStatus"],
  prisma: Prisma.TransactionClient = getPrismaClient()
): Promise<PlanningState> {
  return withIssuanceTransaction(prisma, userId, async (prisma) => {
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
    const timeZone = await accountTimeZone(userId, undefined, prisma);
    const calendar = planningCalendarContext(timeZone, new Date(), plan?.startedAt);
    const now = accountDateLabel(new Date(), timeZone);
    // A rolling replan replaces future prescriptions, not completed progress.
    // Monday labels select the whole current account week, including prior versions.
    const earlierCompletions = plan && version ? await prisma.plannedWorkout.findMany({
      where: {
        userId,
        planVersion: { planId: plan.id },
        planVersionId: { not: version.id },
        status: "completed",
        scheduledDate: { gte: accountDateLabel(new Date(calendar.weekStart), timeZone), lt: addDays(now, 29) },
      },
      orderBy: { scheduledDate: "asc" },
      take: 50,
      include: {
        blocks: {
          orderBy: { sortOrder: "asc" },
          include: { steps: { orderBy: { sortOrder: "asc" } } },
        },
      },
    }) : [];
    const protectedEdits = plan && version ? await protectedEditedWorkouts(prisma, userId, plan.id, version.id, now) : [];
    const existingWorkouts = [...protectedEdits, ...earlierCompletions, ...(version?.workouts ?? []).filter((workout) => workout.status !== "superseded")];
    // Refill replaces future prescriptions, not this calendar week's existing target.
    // Historical planned rows count even before missed-workout maintenance runs;
    // skipped slots stay protected for the whole current week, including future days.
    const priorCalendarWorkouts = plan && version ? await prisma.plannedWorkout.findMany({
      where: {
        userId, planVersion: { planId: plan.id }, planVersionId: { not: version.id },
        scheduledDate: { gte: accountDateLabel(new Date(calendar.weekStart), timeZone), lt: accountDateLabel(new Date(calendar.weekEnd), timeZone) },
        OR: [{ status: "skipped" }, { status: { in: ["planned", "missed"] }, scheduledDate: { lt: now } }],
      },
      orderBy: [{ planVersion: { versionNumber: "desc" } }, { createdAt: "desc" }, { id: "desc" }],
      include: { blocks: { orderBy: { sortOrder: "asc" }, include: { steps: { orderBy: { sortOrder: "asc" } } } } },
    }) : [];
    const representedSlots = new Set(existingWorkouts.map(workoutSlotKey));
    const retainedCalendarWorkouts = priorCalendarWorkouts.filter((workout) => {
      const slot = workoutSlotKey(workout);
      if (representedSlots.has(slot)) return false;
      representedSlots.add(slot);
      return true;
    });
    const storedWorkouts = [...existingWorkouts, ...retainedCalendarWorkouts]
      .sort((left, right) => left.scheduledDate.getTime() - right.scheduledDate.getTime());
    const workouts = await Promise.all(storedWorkouts.map(async (workout) => workout.status === "planned"
      ? { ...workout, performedWorkoutReference: await issueWorkout(prisma, userId, workout.id) } : workout));
    const today =
      workouts.find((workout) => sameDay(workout.scheduledDate, now) && workout.status === "planned" && !isOptionalWorkout(workout)) ??
      workouts.find((workout) => workout.scheduledDate >= now && workout.status === "planned" && !isOptionalWorkout(workout)) ??
      null;
    const recommendations = plan ? [] : await trainingPlanRecommendationsForUser(userId);

    // Reads and accepted activity transactions share the user planning lock. Every
    // assembled snapshot is ordered; this deliberately is an observation watermark.
    const observation = await prisma.user.update({ where: { id: userId },
      data: { planningStateRevision: { increment: 1 } }, select: { planningStateRevision: true } });
    return {
      revision: observation.planningStateRevision,
      calendar,
      goal: goal ? { ...goal, currentRunningFitness: resolveRunningBenchmark((goal.constraints as Record<string, unknown>).runningBenchmark, new Date()), shortRunSessions: (goal.constraints as Record<string, unknown>).shortRunSessions === "true", optionalMobility: (goal.constraints as Record<string, unknown>).optionalMobility === "true" } : null,
      plan: plan ? { ...plan, versions: undefined } : null,
      currentVersion: version ? { ...version, engineDecision: runningReviewDecision(version.engineDecision), workouts: undefined } : null,
      runningPlanReview: runningPlanReview(version?.engineDecision),
      today,
      workouts,
      upcoming: workouts.filter((workout) => workout.scheduledDate >= now && workout.status === "planned").slice(0, 20),
      roadmap: goal && plan ? raceRoadmap(goal, plan.currentPhase, version?.workouts ?? []) : null,
      recommendations,
      athleteState,
      latestAdjustment,
      planningStatus,
    };
  });
}

async function processDueEvents(userId: string) {
  try {
    await processDuePlanningEventsForUser(userId);
  } catch (error) {
    console.error("[planning] due_event_processing_failed", { errorType: error instanceof Error ? error.name : "unknown" });
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
  const db = getPrismaClient();
  const activities = await db.activity.findMany({
    where: { userId, deletedAt: null, startedAt: { gte: addDays(new Date(), -90) } },
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
  });
  return withSessionEffort(db, userId, activities);
}

async function recentPlannedWorkouts(userId: string): Promise<PlannedWorkoutForState[]> {
  return getPrismaClient().plannedWorkout.findMany({
    where: { userId, scheduledDate: { gte: addDays(new Date(), -35) } },
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
  }) as Promise<PlannedWorkoutForState[]>;
}

async function recentReadiness(userId: string): Promise<ReadinessForPlanning[]> {
  return getPrismaClient().readinessCheckIn.findMany({
    where: { userId, date: { gte: addDays(new Date(), -14) } },
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
  }) as Promise<ReadinessForPlanning[]>;
}

function ageYears(birthDate: Date, now: Date) {
  let age = now.getUTCFullYear() - birthDate.getUTCFullYear();
  const beforeBirthday = now.getUTCMonth() < birthDate.getUTCMonth()
    || (now.getUTCMonth() === birthDate.getUTCMonth() && now.getUTCDate() < birthDate.getUTCDate());
  if (beforeBirthday) age -= 1;
  return age;
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

async function resolveCatalogRecommendation(
  userId: string,
  activities: ActivityForPlanning[],
  selection: { candidateID: string; templateID: string }
) {
  const [catalog, activePlan] = await Promise.all([
    loadTrainingPlanCatalog(),
    activePlanForUser(userId),
  ]);
  const recommendations = buildTrainingPlanState({
    activePlan: null,
    activities,
    catalog,
  }).recommendations.filter((recommendation) => recommendation.template.id !== activeTemplateIdFor(activePlan));
  const recommendation = recommendations.find((candidate) =>
    candidate.id === selection.candidateID && candidate.template.id === selection.templateID
  );
  if (!recommendation) {
    throw new Error("That plan recommendation is no longer current. Refresh recommendations and choose again.");
  }
  return recommendation;
}

function catalogFocusForGoalType(value: string) {
  switch (value) {
    case "consistency":
    case "comeback":
    case "fiveK":
    case "tenK":
    case "tenMile":
    case "halfMarathon":
    case "marathon":
      return value;
    default:
      return null;
  }
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
    recentRunSessions3Days: state.recentRunSessions3Days,
    recentRunSessions7Days: state.recentRunSessions7Days,
    recentRunDistance7DaysMeters: state.recentRunDistance7DaysMeters,
    consecutiveActiveDays: state.consecutiveActiveDays,
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
