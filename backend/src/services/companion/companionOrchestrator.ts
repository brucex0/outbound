import { createHash, randomUUID } from "node:crypto";
import { Prisma, type PrismaClient } from "@prisma/client";
import { generateCompanionMessage } from "../ai.js";
import type { CompanionTurnRequest } from "./contracts.js";
import { compileCompanionContext } from "./contextCompiler.js";
import { generateCandidateAction } from "./candidateGenerator.js";
import { validateCompanionProposal } from "./policyValidator.js";
import { createAgentAction } from "./actionExecutor.js";
import { ingestSituationalSignals } from "./situationalIntelligence.js";
import type { SupportedLocale } from "../../middleware/locale.js";

export async function runCompanionTurn(
  prisma: PrismaClient,
  userId: string,
  request: CompanionTurnRequest,
  locale: SupportedLocale = "en"
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

  const fallbackMessage = deterministicMessage(proposal, validation.disposition, locale);
  const message = await generateCompanionMessage({
    prompt: request.prompt,
    context,
    proposal,
    actionStatus: action?.status,
    locale,
  }).catch(() => fallbackMessage);
  await updateConversationState(prisma, userId, request, message);

  return {
    message,
    action: action ? serializeAction(action) : null,
    confirmationRequest: action?.requiresConfirmation ? {
      actionId: action.id,
      title: localizedCompanionCopy(locale).confirmationTitle,
      explanation: locale === "en" ? action.explanation : localizedCompanionCopy(locale).preparedExplanation,
      acceptLabel: localizedCompanionCopy(locale).acceptLabel,
      rejectLabel: localizedCompanionCopy(locale).rejectLabel,
    } : null,
    suggestedReplies: proposal.actionType === "communicate" ? [] : localizedCompanionCopy(locale).suggestedReplies,
    locale,
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
  disposition: string,
  locale: SupportedLocale
) {
  const copy = localizedCompanionCopy(locale);
  if (proposal.actionType === "shorten_workout" && proposal.durationMinutes) {
    if (disposition === "confirmation_required") {
      return copy.shorten(proposal.durationMinutes, proposal.rationale);
    }
    return copy.couldNotChange(proposal.rationale);
  }
  return copy.defaultMessage;
}

function localizedCompanionCopy(locale: SupportedLocale) {
  if (locale === "es") return {
    confirmationTitle: "¿Cambiar el entrenamiento de hoy?", acceptLabel: "Aplicar cambio", rejectLabel: "Mantener original",
    suggestedReplies: ["¿Por qué este cambio?", "Mantener el original"],
    preparedExplanation: "Este ajuste se basa en tu plan actual y en las señales de entrenamiento disponibles.",
    shorten: (minutes: number, _rationale: string) => `Encontré una opción más segura para hoy: acortar el entrenamiento previsto a ${minutes} minutos. Todavía no lo he cambiado.`,
    couldNotChange: (_rationale: string) => "No pude preparar ese cambio de entrenamiento de forma segura.",
    defaultMessage: "Estoy usando tu plan actual, entrenamiento reciente, estado de hoy y preferencias confirmadas. Dime qué se siente difícil del plan de hoy y buscaré el ajuste útil más pequeño.",
  };
  if (locale === "zh-Hans") return {
    confirmationTitle: "要更改今天的训练吗？", acceptLabel: "应用更改", rejectLabel: "保留原计划",
    suggestedReplies: ["为什么这样调整？", "保留原计划"],
    preparedExplanation: "此调整基于你当前的计划和现有训练信号。",
    shorten: (minutes: number, _rationale: string) => `我找到了更适合今天的安全方案：将计划训练缩短到 ${minutes} 分钟。我还没有进行更改。`,
    couldNotChange: (_rationale: string) => "我无法安全地准备这项训练更改。",
    defaultMessage: "我正在结合你当前的计划、近期训练、今日状态和已确认的偏好。告诉我今天的计划哪里感觉困难，我会帮你找到最小且有效的调整。",
  };
  return {
    confirmationTitle: "Change today's workout?", acceptLabel: "Apply change", rejectLabel: "Keep original",
    suggestedReplies: ["Why this change?", "Keep the original"],
    preparedExplanation: "This adjustment is based on your current plan and available training signals.",
    shorten: (minutes: number, rationale: string) => `I found a safer fit for today: shorten the planned workout to ${minutes} minutes. ${rationale} I have not changed it yet.`,
    couldNotChange: (rationale: string) => `I could not safely prepare that workout change. ${rationale}`,
    defaultMessage: "I’m using your current plan, recent training, readiness, and confirmed preferences. Tell me what feels difficult about today’s plan and I’ll help find the smallest useful adjustment.",
  };
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
