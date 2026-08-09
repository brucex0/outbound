import { createHash, randomUUID } from "node:crypto";
import { Prisma, type PrismaClient } from "@prisma/client";
import { generateCompanionMessage } from "../ai.js";
import type { CompanionTurnRequest } from "./contracts.js";
import { compileCompanionContext } from "./contextCompiler.js";
import { generateCandidateAction } from "./candidateGenerator.js";
import { validateCompanionProposal } from "./policyValidator.js";
import { createAgentAction } from "./actionExecutor.js";
import { ingestSituationalSignals } from "./situationalIntelligence.js";

export async function runCompanionTurn(
  prisma: PrismaClient,
  userId: string,
  request: CompanionTurnRequest
) {
  if (request.signals.length > 0) await ingestSituationalSignals(prisma, userId, request.signals);
  const context = await compileCompanionContext(prisma, userId, request);
  const proposal = generateCandidateAction(request.prompt, context);
  const validation = validateCompanionProposal(proposal, context);
  let action = null;
  if (proposal.actionType !== "communicate" && validation.approved) {
    const idempotencyKey = createHash("sha256")
      .update(`${userId}:${request.conversationKey}:${context.manifestId}:${proposal.actionType}:${proposal.workoutId ?? ""}`)
      .digest("hex");
    action = await createAgentAction(prisma, {
      userId,
      idempotencyKey,
      task: request.task,
      proposal: validation.normalizedProposal,
      validation,
      contextManifestId: context.manifestId,
      runnerModelVersion: context.runnerModelVersion,
      policyVersion: validation.policyVersion,
      explanation: proposal.rationale,
    });
  }

  const fallbackMessage = deterministicMessage(proposal, validation.disposition);
  const message = await generateCompanionMessage({
    prompt: request.prompt,
    context,
    proposal,
    actionStatus: action?.status,
  }).catch(() => fallbackMessage);
  await updateConversationState(prisma, userId, request, message);

  return {
    message,
    action: action ? serializeAction(action) : null,
    confirmationRequest: action?.requiresConfirmation ? {
      actionId: action.id,
      title: "Change today's workout?",
      explanation: action.explanation,
      acceptLabel: "Apply change",
      rejectLabel: "Keep original",
    } : null,
    suggestedReplies: proposal.actionType === "communicate" ? [] : ["Why this change?", "Keep the original"],
    runnerModelVersion: context.runnerModelVersion,
    contextReceipt: {
      manifestId: context.manifestId,
      task: context.task,
      tokenBudget: context.tokenBudget,
      estimatedTokens: context.estimatedTokens,
      includedReferenceCount: context.includedRefs.length,
    },
  };
}

function deterministicMessage(
  proposal: ReturnType<typeof generateCandidateAction>,
  disposition: string
) {
  if (proposal.actionType === "shorten_workout" && proposal.durationMinutes) {
    if (disposition === "confirmation_required") {
      return `I found a safer fit for today: shorten the planned workout to ${proposal.durationMinutes} minutes. ${proposal.rationale} I have not changed it yet.`;
    }
    return `I could not safely prepare that workout change. ${proposal.rationale}`;
  }
  return "I’m using your current plan, recent training, readiness, and confirmed preferences. Tell me what feels difficult about today’s plan and I’ll help find the smallest useful adjustment.";
}

async function updateConversationState(
  prisma: PrismaClient,
  userId: string,
  request: CompanionTurnRequest,
  response: string
) {
  const lastMessages = [
    ...request.recentMessages.slice(-4),
    { role: "user", text: request.prompt },
    { role: "assistant", text: response },
  ].slice(-6);
  const summary = `Latest objective: ${request.task}. Latest runner request: ${request.prompt.slice(0, 320)}`;
  return prisma.companionConversationState.upsert({
    where: { userId_conversationKey: { userId, conversationKey: request.conversationKey } },
    create: {
      userId,
      conversationKey: request.conversationKey,
      surface: request.surface,
      objective: request.task,
      compactSummary: summary,
      lastMessages: lastMessages as Prisma.InputJsonValue,
    },
    update: {
      surface: request.surface,
      objective: request.task,
      compactSummary: summary,
      lastMessages: lastMessages as Prisma.InputJsonValue,
    },
  });
}

function serializeAction(action: { id: string; actionType: string; permissionTier: number; requiresConfirmation: boolean; status: string; explanation: string; proposal: Prisma.JsonValue }) {
  return {
    id: action.id,
    actionType: action.actionType,
    permissionTier: action.permissionTier,
    requiresConfirmation: action.requiresConfirmation,
    status: action.status,
    explanation: action.explanation,
    proposal: action.proposal,
  };
}

