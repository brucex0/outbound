import { Prisma } from "@prisma/client";
import { getPrismaClient } from "../prisma.js";
import { adaptPlan } from "./adaptationEngine.js";
import { computeAthleteTrainingState } from "./athleteState.js";
import { generateNextWindow, phaseForGoal, PLANNER_POLICY_VERSION, type GeneratePlanInput } from "./generator.js";
import { createPlanVersionWithWorkouts, json, lockPlanningUser, isOptionalWorkout, workoutSlotKey } from "./persistence.js";
import { applyCalorieTargets, resolveLearnedRunPace } from "./runGoalEstimator.js";
import type { ActivityForPlanning, PlannedWorkoutForState, ReadinessForPlanning } from "./types.js";

/** A deterministic repair/refill, independent of AI evaluation budgets and activity imports. */
export async function refreshGeneratedPlan(userId: string, now = new Date()): Promise<void> {
  const prisma = getPrismaClient();
  await prisma.$transaction(async (tx) => {
    await lockPlanningUser(tx, userId);
    await refreshGeneratedPlanInTransaction(tx, userId, now);
  }, { timeout: 30_000 });
}

export async function refreshGeneratedPlanInTransaction(
  tx: Prisma.TransactionClient, userId: string, now: Date, force = false,
): Promise<void> {
  const plan = await tx.trainingPlan.findFirst({
    where: { userId, status: "active", source: "generated" }, orderBy: { createdAt: "desc" },
    include: { goal: true, versions: { orderBy: { versionNumber: "desc" }, take: 1, include: { workouts: true } } },
  });
  if (!plan) return;
  const version = plan.versions[0];
  const goal = { ...plan.goal, activities: plan.goal.activities, constraints: plan.goal.constraints } as GeneratePlanInput["goal"];
  const phase = phaseForGoal(goal, now);
  const today = day(now);
  const decision = version?.engineDecision as Record<string, unknown> | undefined;
  const policyChanged = decision?.plannerPolicyVersion !== PLANNER_POLICY_VERSION;
  const future = (version?.workouts ?? []).filter((workout) => workout.status === "planned" && !isOptionalWorkout(workout) && workout.scheduledDate >= today);
  const lastPlanned = Math.max(0, ...future.map((workout) => workout.scheduledDate.getTime()));
  const evaluatedToday = typeof decision?.windowCheckedOn === "string" && decision.windowCheckedOn === dateKey(today);
  const refill = future.length === 0 || (!evaluatedToday && lastPlanned < addDays(today, 7).getTime());
  if (!force && !policyChanged && phase === plan.currentPhase && !refill) return;
  // An event plan ends at its event; phase still advances after the event without endless refill.
  if (!force && !policyChanged && ["recovery", "maintenance"].includes(phase) && phase === plan.currentPhase) return;
  const [activities, planned, readiness, profile, calibration] = await Promise.all([
    tx.activity.findMany({ where: { userId, deletedAt: null, startedAt: { gte: addDays(today, -90) } }, orderBy: { startedAt: "desc" }, take: 1000, select: { id: true, type: true, startedAt: true, durationSecs: true, distanceM: true, avgPace: true, avgHeartRate: true } }),
    tx.plannedWorkout.findMany({ where: { userId, scheduledDate: { gte: addDays(today, -35) } }, take: 1000, select: { id: true, scheduledDate: true, modality: true, stimulus: true, durationSeconds: true, distanceMeters: true, targetCalories: true, isKeyWorkout: true, status: true, prescription: true } }),
    tx.readinessCheckIn.findMany({ where: { userId, date: { gte: addDays(today, -14) } }, orderBy: { date: "desc" }, take: 30, select: { date: true, energy: true, soreness: true, sleepQuality: true, stress: true, motivation: true, illnessOrPain: true } }),
    tx.runnerProfile.findUnique({ where: { userId } }),
    tx.calibrationProgram.findUnique({ where: { userId } }),
  ]);
  const athleteState = computeAthleteTrainingState({ activities: activities as ActivityForPlanning[], plannedWorkouts: planned as PlannedWorkoutForState[], readiness: readiness as ReadinessForPlanning[], now });
  const protectedWorkouts = await tx.plannedWorkout.findMany({
    where: { userId, planVersion: { planId: plan.id }, status: { in: ["completed", "skipped"] } }, select: { scheduledDate: true, prescription: true },
  });
  const protectedDays = new Set(protectedWorkouts.map(workoutSlotKey));
  let windowStart = today;
  let generation = generateNextWindow({ goal, athleteState, now: windowStart, reason: force ? "goalUpdated" : policyChanged ? "policyUpdated" : "weeklyRollover" });
  const required = generation.workouts.filter((workout) => !isOptionalWorkout(workout));
  if (required.length > 0 && required.every((workout) => protectedDays.has(workoutSlotKey(workout)))) {
    // Skip the entire protected horizon, even when several windows were completed
    // in advance. Optional supports cannot prevent required-run replenishment.
    const latest = Math.max(...protectedWorkouts.filter((workout) => !isOptionalWorkout(workout)).map((workout) => workout.scheduledDate.getTime()));
    windowStart = addDays(new Date(latest), 1);
    generation = generateNextWindow({ goal, athleteState, now: windowStart, reason: "weeklyRollover" });
  }
  const latestReadiness = readiness.find((entry) => entry.date >= addDays(today, -1));
  const adapted = latestReadiness && (latestReadiness.illnessOrPain || latestReadiness.energy <= 2 || latestReadiness.soreness >= 4 || latestReadiness.stress >= 4)
    ? adaptPlan({ goal, athleteState, now: windowStart, eventType: "readinessSubmitted", latestReadiness }) : null;
  const workouts = applyCalorieTargets({
    workouts: (adapted?.workouts ?? generation.workouts).filter((workout) => !protectedDays.has(workoutSlotKey(workout))),
    preferredRunGoalType: goal.preferredRunGoalType, weightKilograms: profile?.weightKilograms,
    pace: resolveLearnedRunPace(activities as ActivityForPlanning[], calibration?.status === "completed"),
  });
  if (!force && !policyChanged && workouts.filter((workout) => !isOptionalWorkout(workout)).length === 0) {
    if (phase !== plan.currentPhase) await tx.trainingPlan.update({ where: { id: plan.id }, data: { currentPhase: phase } });
    return;
  }
  const engineDecision = { ...generation.engineDecision, windowCheckedOn: dateKey(today), activation: policyChanged, phase };
  const created = await createPlanVersionWithWorkouts(tx, {
    userId, planId: plan.id, versionNumber: (version?.versionNumber ?? 0) + 1,
    reason: force ? "goalUpdated" : policyChanged ? "policyUpdated" : "weeklyRollover",
    summary: generation.summary, engineDecision, workouts,
  });
  await tx.trainingPlan.update({ where: { id: plan.id }, data: { currentPhase: phase } });
  await tx.planAdjustmentEvent.create({ data: {
    userId, planId: plan.id, fromVersionId: version?.id, toVersionId: created.id,
    eventType: force ? "goalUpdated" : "weeklyRollover",
    message: force ? "today.race_goal.goal_updated"
      : policyChanged ? "today.race_goal.policy_updated"
      : "today.race_goal.refilled",
    changedWorkoutIds: [], engineDecision: json(engineDecision),
  } });
  // Bounded operational analytics: no goal dates, distances, IDs, body data, or text.
  console.info("[planning] generated_window_refreshed", { reason: force ? "goal_updated" : policyChanged ? "policy_updated" : "refill", phase, requiredSessions: workouts.filter((workout) => workout.prescription.optional !== true).length });
}

function day(value: Date) { return new Date(Date.UTC(value.getUTCFullYear(), value.getUTCMonth(), value.getUTCDate())); }
function addDays(value: Date, amount: number) { return new Date(value.getTime() + amount * 86_400_000); }
function dateKey(value: Date) { return value.toISOString().slice(0, 10); }
