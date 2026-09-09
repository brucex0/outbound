import { Prisma, type PrismaClient } from "@prisma/client";
import type { CompanionActionProposal } from "./types.js";
import { appendRunnerEvidence } from "./evidenceService.js";
import { persistCompanionModelVersion } from "./runnerModelProjector.js";
import { rebuildPlan } from "../planning/planningService.js";
import { estimateCalorieRunFromTarget, resolveLearnedRunPace } from "../planning/runGoalEstimator.js";
import { decideAdjustment } from "../personalization/personalizationService.js";

export async function createAgentAction(
  prisma: PrismaClient,
  input: {
    userId: string;
    idempotencyKey: string;
    task: string;
    proposal: CompanionActionProposal;
    validation: unknown;
    contextManifestId: string;
    runnerModelVersion: string;
    policyVersion: string;
    explanation: string;
  }
) {
  return prisma.agentAction.upsert({
    where: { idempotencyKey: input.idempotencyKey },
    create: {
      userId: input.userId,
      idempotencyKey: input.idempotencyKey,
      triggerType: "companion_turn",
      task: input.task,
      actionType: input.proposal.actionType,
      permissionTier: input.proposal.permissionTier,
      requiresConfirmation: input.proposal.requiresConfirmation,
      status: input.proposal.requiresConfirmation ? "proposed" : "validated",
      evidenceIds: input.proposal.evidenceIds,
      contextManifestId: input.contextManifestId,
      runnerModelVersion: input.runnerModelVersion,
      policyVersion: input.policyVersion,
      proposal: input.proposal as unknown as Prisma.InputJsonValue,
      validation: input.validation as Prisma.InputJsonValue,
      explanation: input.explanation,
    },
    update: {},
  });
}

export async function decideAndExecuteAgentAction(
  prisma: PrismaClient,
  userId: string,
  actionId: string,
  decision: "accept" | "reject"
) {
  const action = await prisma.agentAction.findFirst({ where: { id: actionId, userId } });
  if (!action) throw new Error("Companion action not found.");
  if (action.status !== "proposed") return action;
  const proposal = action.proposal as unknown as CompanionActionProposal;
  if (decision === "reject") {
    if (proposal.actionType === "recalibrate_plan" && proposal.adjustmentId) {
      await decideAdjustment(userId, proposal.adjustmentId, "reject");
    }
    const rejected = await prisma.agentAction.update({ where: { id: action.id }, data: { status: "rejected", decidedAt: new Date() } });
    await recordOutcome(prisma, userId, action.id, "rejected", {});
    return rejected;
  }

  let beforeState: Prisma.InputJsonValue | undefined;
  let afterState: Prisma.InputJsonValue | undefined;
  let rollback: Prisma.InputJsonValue | undefined;
  if (proposal.actionType === "shorten_workout" && proposal.workoutId && proposal.durationMinutes) {
    const durationMinutes = proposal.durationMinutes;
    const workout = await prisma.plannedWorkout.findFirst({
      where: { id: proposal.workoutId, userId, status: "planned" },
      include: { blocks: { include: { steps: true } } },
    });
    if (!workout) throw new Error("Planned workout is no longer available.");
    const nextDurationSeconds = durationMinutes * 60;
    beforeState = { workoutId: workout.id, durationSeconds: workout.durationSeconds, title: workout.title };
    const ratio = nextDurationSeconds / workout.durationSeconds;
    const updated = await prisma.$transaction(async (tx) => {
      for (const block of workout.blocks) {
        if (block.durationSeconds) {
          await tx.workoutBlock.update({
            where: { id: block.id },
            data: { durationSeconds: Math.max(1, Math.round(block.durationSeconds * ratio)) },
          });
        }
        for (const step of block.steps) {
          if (step.durationSeconds) {
            await tx.workoutStep.update({
              where: { id: step.id },
              data: { durationSeconds: Math.max(1, Math.round(step.durationSeconds * ratio)) },
            });
          }
        }
      }
      return tx.plannedWorkout.update({
        where: { id: workout.id },
        data: { durationSeconds: nextDurationSeconds, title: replaceDuration(workout.title, durationMinutes) },
      });
    });
    afterState = {
      workoutId: updated.id,
      durationSeconds: updated.durationSeconds,
      title: updated.title,
      summary: `Duration changed from ${Math.round(workout.durationSeconds / 60)} to ${durationMinutes} minutes; timed blocks and steps were resized to fit.`,
    };
    rollback = beforeState;
  } else if (proposal.actionType === "set_workout_calories" && proposal.workoutId && proposal.targetCalories) {
    const [workout, profile, calibration, activities] = await Promise.all([
      prisma.plannedWorkout.findFirst({ where: { id: proposal.workoutId, userId, status: "planned" } }),
      prisma.runnerProfile.findUnique({ where: { userId } }),
      prisma.calibrationProgram.findUnique({ where: { userId } }),
      prisma.activity.findMany({
        where: { userId, type: "running", startedAt: { gte: new Date(Date.now() - 90 * 24 * 60 * 60 * 1_000) } },
        orderBy: { startedAt: "desc" },
        select: { id: true, type: true, startedAt: true, durationSecs: true, distanceM: true, avgPace: true, avgHeartRate: true },
      }),
    ]);
    if (!workout) throw new Error("Planned workout is no longer available.");
    if (workout.modality !== "run" || !["easyAerobic", "recovery"].includes(workout.stimulus)) {
      throw new Error("Only easy and recovery runs can use a calorie target.");
    }
    if (profile?.weightKilograms == null) throw new Error("Add weight in your private training profile before using calorie targets.");
    const pace = resolveLearnedRunPace(activities, calibration?.status === "completed");
    if (!pace.paceSecondsPerKilometer) throw new Error("Complete calibration or save at least three valid runs before using calorie targets.");
    const estimate = estimateCalorieRunFromTarget({
      targetCalories: proposal.targetCalories,
      weightKilograms: profile.weightKilograms,
      paceSecondsPerKilometer: pace.paceSecondsPerKilometer,
    });
    if (!estimate) throw new Error("Unable to calculate a safe calorie target from the current profile.");
    beforeState = {
      workoutId: workout.id,
      durationSeconds: workout.durationSeconds,
      distanceMeters: workout.distanceMeters,
      targetCalories: workout.targetCalories,
      title: workout.title,
    };
    const updated = await prisma.$transaction(async (tx) => {
      await tx.workoutBlock.deleteMany({ where: { plannedWorkoutId: workout.id } });
      return tx.plannedWorkout.update({
        where: { id: workout.id },
        data: {
          targetCalories: estimate.targetCalories,
          distanceMeters: estimate.distanceMeters,
          durationSeconds: estimate.durationSeconds,
          prescription: {
            runGoalType: "calories",
            targetCalories: estimate.targetCalories,
            estimatedDistanceMeters: estimate.distanceMeters,
            estimatedDurationSeconds: estimate.durationSeconds,
          },
        },
      });
    });
    afterState = {
      workoutId: updated.id,
      durationSeconds: updated.durationSeconds,
      distanceMeters: updated.distanceMeters,
      targetCalories: updated.targetCalories,
      title: updated.title,
      summary: "The eligible run now has one calorie completion goal with synchronized distance and duration estimates.",
    };
    rollback = beforeState;
  } else if (proposal.actionType === "update_run_goal_preference" && proposal.goalType) {
    beforeState = await prisma.runnerProfile.findUnique({
      where: { userId },
      select: { preferredRunGoalType: true, primaryMotivation: true },
    }) ?? { preferredRunGoalType: "time", primaryMotivation: "generalFitness" };
    await prisma.$transaction(async (tx) => {
      await tx.runnerProfile.upsert({
        where: { userId },
        create: { userId, preferredRunGoalType: proposal.goalType },
        update: { preferredRunGoalType: proposal.goalType },
      });
      await tx.trainingGoal.updateMany({
        where: { userId, status: "active" },
        data: { preferredRunGoalType: proposal.goalType },
      });
    });
    await rebuildPlan(userId, { reason: "manualRebuild" });
    afterState = {
      preferredRunGoalType: proposal.goalType,
      summary: "Updated the recurring run-goal preference and rebuilt eligible upcoming workouts.",
    };
    rollback = beforeState;
  } else if (proposal.actionType === "recalibrate_plan" && proposal.adjustmentId) {
    beforeState = { adjustmentId: proposal.adjustmentId, status: "proposed" };
    const applied = await decideAdjustment(userId, proposal.adjustmentId, "accept");
    afterState = { adjustmentId: proposal.adjustmentId, status: "applied", adjustment: applied } as unknown as Prisma.InputJsonValue;
  } else {
    throw new Error("Unsupported companion action.");
  }

  const executed = await prisma.agentAction.update({
    where: { id: action.id },
    data: { status: "executed", decidedAt: new Date(), executedAt: new Date(), beforeState, afterState, rollback },
  });
  const outcome = await recordOutcome(prisma, userId, action.id, "accepted", { afterState });
  await appendRunnerEvidence(prisma, userId, {
    dedupeKey: `agent-action:${action.id}:executed`,
    type: "agent.action_accepted",
    source: "companion",
    subject: action.id,
    payload: { actionType: action.actionType, outcomeId: outcome.id },
    consequenceLevel: "medium",
  });
  await persistCompanionModelVersion(prisma, userId, "agentActionExecuted");
  return executed;
}

async function recordOutcome(prisma: PrismaClient, userId: string, actionId: string, type: string, payload: unknown) {
  return prisma.agentOutcome.create({ data: { userId, actionId, type, payload: payload as Prisma.InputJsonValue, observedAt: new Date() } });
}

function replaceDuration(title: string, minutes: number) {
  return /·\s*\d+\s*min\s*$/i.test(title)
    ? title.replace(/·\s*\d+\s*min\s*$/i, `· ${minutes} min`)
    : `${title} · ${minutes} min`;
}
