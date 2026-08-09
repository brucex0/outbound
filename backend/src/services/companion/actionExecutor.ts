import { Prisma, type PrismaClient } from "@prisma/client";
import type { CompanionActionProposal } from "./types.js";
import { appendRunnerEvidence } from "./evidenceService.js";
import { persistCompanionModelVersion } from "./runnerModelProjector.js";

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
  if (decision === "reject") {
    const rejected = await prisma.agentAction.update({ where: { id: action.id }, data: { status: "rejected", decidedAt: new Date() } });
    await recordOutcome(prisma, userId, action.id, "rejected", {});
    return rejected;
  }

  const proposal = action.proposal as unknown as CompanionActionProposal;
  let beforeState: Prisma.InputJsonValue | undefined;
  let afterState: Prisma.InputJsonValue | undefined;
  let rollback: Prisma.InputJsonValue | undefined;
  if (proposal.actionType === "shorten_workout" && proposal.workoutId && proposal.durationMinutes) {
    const workout = await prisma.plannedWorkout.findFirst({ where: { id: proposal.workoutId, userId, status: "planned" } });
    if (!workout) throw new Error("Planned workout is no longer available.");
    const nextDurationSeconds = proposal.durationMinutes * 60;
    beforeState = { workoutId: workout.id, durationSeconds: workout.durationSeconds, title: workout.title };
    const updated = await prisma.plannedWorkout.update({
      where: { id: workout.id },
      data: { durationSeconds: nextDurationSeconds, title: replaceDuration(workout.title, proposal.durationMinutes) },
    });
    afterState = { workoutId: updated.id, durationSeconds: updated.durationSeconds, title: updated.title };
    rollback = beforeState;
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

