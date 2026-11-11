import { runningPlanReview, runningConstraintReview, retainRunningPlanForReview, clearRunningPlanReview } from "./runningPlanReview.js";
import { loadRunningPlanningContext } from "./runningContext.js";
import { sameRunWalkProgramme } from "./runWalkProgramme.js";
import { unexpectedRunningEffort, withSessionEffort } from "./sessionEffort.js";
import { runningBenchmarkDecisionChanged } from "./runningBenchmark.js";
import type { Prisma } from "@prisma/client";
import { loadTrainingPlanCatalog } from "../trainingPlanCatalog.js";
import { adaptPlan } from "./adaptationEngine.js";
import { computeAthleteTrainingState } from "./athleteState.js";
import { CATALOG_POLICY_VERSION, generateCatalogWindow, record, day, addDays } from "./catalogProgramme.js";
import type { GeneratePlanInput } from "./generator.js";
import { createPlanVersionWithWorkouts, json, workoutSlotKey } from "./persistence.js";
import type { ActivityForPlanning, PlannedWorkoutForState, PlanningEventType, ReadinessForPlanning } from "./types.js";

/** Caller holds the planning-user lock; original plan/edit/completion rows stay intact. */
export async function refreshCatalogPlanInTransaction(
  tx: Prisma.TransactionClient, userId: string, now: Date, eventType?: PlanningEventType, expectedPlanId?: string,
): Promise<boolean> {
  if (eventType === "goalUpdated") return refreshCatalogPlanCandidate(tx, userId, now, eventType, expectedPlanId);
  try {
    const handled = await refreshCatalogPlanCandidate(tx, userId, now, eventType, expectedPlanId);
    if (handled) await clearRunningPlanReview(tx, userId, expectedPlanId);
    return handled;
  } catch (error) {
    const review = runningConstraintReview(error);
    if (!review || !await retainRunningPlanForReview(tx, userId, review, { planId: expectedPlanId })) throw error;
    return true;
  }
}

async function refreshCatalogPlanCandidate(tx: Prisma.TransactionClient, userId: string, now: Date, eventType?: PlanningEventType, expectedPlanId?: string): Promise<boolean> {
  const plan = await tx.trainingPlan.findFirst({
    where: { userId, status: "active", source: "catalog", ...(expectedPlanId ? { id: expectedPlanId } : {}) }, orderBy: { createdAt: "desc" },
    include: { goal: true, versions: { orderBy: { versionNumber: "desc" }, take: 1, include: { workouts: true } } },
  });
  if (!plan) return false;
  const version = plan.versions[0];
  const decision = record(version?.engineDecision);
  const cursor = record(decision?.programme);
  const today = day(now);
  const elapsed = typeof cursor?.weekAnchor === "string" && today >= addDays(new Date(cursor.weekAnchor), 7);
  // Once checked, a read/refill within an episode does not advance or reset it.
  const benchmarkChanged = runningBenchmarkDecisionChanged(decision?.runningBenchmark, record(plan.goal.constraints), now);

  if (cursor?.status === "completed") return true;
  if (cursor && typeof cursor.weekAnchor === "string" && !Number.isFinite(new Date(cursor.weekAnchor).getTime())) {
    console.error("[planning] catalog_programme_failed", { operation: "refresh", category: "invalid_cursor" });
    throw new Error("The training programme cursor is invalid. Choose a current programme before rebuilding.");
  }
  const templateID = record(plan.goal.constraints)?.templateID;
  const catalog = await loadTrainingPlanCatalog(tx);
  const template = typeof templateID === "string" ? catalog.templateLookup.get(templateID) : undefined;
  if (!template) {
    console.error("[planning] catalog_programme_failed", { operation: "refresh", category: "unknown_template" });
    throw new Error("The selected training programme is unavailable. Choose a current programme before rebuilding.");
  }
  const goal = { ...plan.goal, constraints: record(plan.goal.constraints) } as GeneratePlanInput["goal"];
  const authoredWalkRun = template.weeks[0].workouts.some((row) => !row.isOptional && row.kind === "walkRun");
  const runningContext = template.sport === "run" && !authoredWalkRun ? await loadRunningPlanningContext(tx, {
    userId, planId: plan.id, goal, previousProgramme: decision?.runWalkProgramme, now, createdAt: plan.createdAt,
    enableProgramme: goal.baselineContext !== "currentlyActive", authored: true,
    authoredInitialSeconds: Math.min(...template.weeks[0].workouts.filter((row) => !row.isOptional && row.durationSeconds > 0).map((row) => row.durationSeconds)),
  }) : undefined;
  const programmeChanged = runningContext != null && !sameRunWalkProgramme(decision?.runWalkProgramme, runningContext.state);
  if (!eventType && !runningPlanReview(decision) && decision?.catalogPolicyVersion === CATALOG_POLICY_VERSION && !elapsed && !benchmarkChanged && !programmeChanged) return true;
  const since = template.sport === "run" ? new Date(typeof cursor?.sourceWeekStartedOn === "string" ? cursor.sourceWeekStartedOn : cursor?.episodeStart as string ?? plan.createdAt)
    : typeof cursor?.weekAnchor === "string" ? new Date(cursor.weekAnchor) : day(plan.createdAt);
  const [activities, evidence, readiness, feedback] = await Promise.all([
    tx.activity.findMany({ where: { userId, deletedAt: null, startedAt: { gte: addDays(today, -90) } }, take: 1000,
      select: { id: true, type: true, startedAt: true, durationSecs: true, distanceM: true, avgPace: true, avgHeartRate: true } }),
    tx.plannedWorkout.findMany({ where: { userId, planVersion: { planId: plan.id }, scheduledDate: { gte: since } },
      include: { blocks: { orderBy: { sortOrder: "asc" }, include: { steps: { orderBy: { sortOrder: "asc" } } } }, edits: { select: { operation: true } }, completions: { select: { completedAt: true, durationSeconds: true, completionQuality: true, perceivedEffort: true, performedAsIssued: true, prescriptionRevision: { select: { programmeExposureEligible: true, sourceExposureEligible: true, stimulus: true } } } } } }),
    tx.readinessCheckIn.findMany({ where: { userId, date: { gte: addDays(today, -14) } }, orderBy: { date: "desc" }, take: 30 }),
    tx.workoutFeedback.findMany({ where: { userId, recordedAt: { gte: new Date(Math.max(since.getTime(), addDays(today, -7).getTime())) } },
      select: { effort: true } }),
  ]);
  const ratedActivities = await withSessionEffort(tx, userId, activities as ActivityForPlanning[]);
  const state = runningContext?.athleteState ?? computeAthleteTrainingState({ activities: ratedActivities, plannedWorkouts: evidence as PlannedWorkoutForState[], readiness: readiness.filter((entry) => entry.date >= addDays(today, -1) && entry.date <= now) as ReadinessForPlanning[], now });
  const latestReadiness = runningContext ? runningContext.latestReadiness : readiness.find((entry) => entry.date >= addDays(today, -1) && entry.date <= now);
  const readyToAdvance = state.fatigueRisk === "low" && (!latestReadiness || (!latestReadiness.illnessOrPain && latestReadiness.energy > 2
    && latestReadiness.soreness < 4 && latestReadiness.stress < 4));
  const difficulty = feedback.some((item) => item.effort === "tooHard") || evidence.some((row) => row.scheduledDate >= addDays(today, -7)
    && row.completions.some((completion) => unexpectedRunningEffort({ ...completion, stimulus: completion.prescriptionRevision?.stimulus ?? row.stimulus }, latestReadiness)));
  const generation = generateCatalogWindow({ template, goal, now, createdAt: plan.createdAt, priorDecision: decision,
    evidence, readyToAdvance: readyToAdvance && eventType !== "painFlagged", explicitDifficulty: difficulty, athleteState: state, runWalkProgramme: runningContext?.state });
  const protectedSlots = new Set(evidence.filter((row) => ["completed", "skipped"].includes(row.status)
    || row.status === "planned" && (typeof record(row.prescription)?.workoutEditId === "string" || record(row.prescription)?.source === "explicitWorkoutChange")).map(workoutSlotKey));
  generation.workouts = generation.workouts.filter((workout) => !protectedSlots.has(workoutSlotKey(workout)));
  const adaptation = eventType ? adaptPlan({ goal, athleteState: state, latestReadiness, eventType, now, basePlan: generation }) : null;
  const workouts = adaptation?.workouts ?? generation.workouts;
  const engineDecision = { ...generation.engineDecision, ...adaptation?.engineDecision };
  const created = await createPlanVersionWithWorkouts(tx, {
    userId, planId: plan.id, versionNumber: (version?.versionNumber ?? 0) + 1, effectiveFrom: now,
    reason: eventType ?? "weeklyRollover", summary: adaptation?.summary ?? generation.summary, engineDecision, workouts,
  });
  await tx.trainingPlan.update({ where: { id: plan.id }, data: { currentPhase: generation.phase } });
  await tx.planAdjustmentEvent.create({ data: {
    userId, planId: plan.id, fromVersionId: version?.id, toVersionId: created.id,
    eventType: eventType ?? "weeklyRollover", message: adaptation?.adjustmentMessage ?? "today.race_goal.refilled",
    changedWorkoutIds: [], engineDecision: json(engineDecision),
  } });
  console.info("[planning] catalog_programme_decision", {
    outcome: generation.engineDecision.programmeOutcome,
    reentry: record(generation.engineDecision.runWalkProgramme)?.status ?? "absent",
    timeline: generation.engineDecision.programmeTimelineStatus ?? "not_applicable",
    trigger: eventType ?? "refill", result: "version_created",
  });
  return true;
}
