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
import { requestPlanReview } from "../planning/planningService.js";

export async function runCompanionTurn(
  prisma: PrismaClient,
  userId: string,
  request: CompanionTurnRequest,
  locale: SupportedLocale = "en"
) {
  if (request.signals.length > 0) await ingestSituationalSignals(prisma, userId, request.signals);
  const context = await compileCompanionContext(prisma, userId, request);
  let proposal = generateCandidateAction(request.prompt, context);
  let reviewMessage: string | null = null;
  if (proposal.actionType === "recalibrate_plan") {
    const review = await requestPlanReview(userId);
    if (review.status === "proposed" && review.adjustmentId) {
      proposal = {
        ...proposal,
        permissionTier: 2,
        requiresConfirmation: true,
        adjustmentId: review.adjustmentId,
        rationale: review.explanation,
      };
      reviewMessage = localizedCompanionCopy(locale).recalibrationProposed(review.explanation);
    } else {
      proposal = { ...proposal, actionType: "communicate", permissionTier: 0, requiresConfirmation: false };
      reviewMessage = review.status === "unchanged"
        ? localizedCompanionCopy(locale).recalibrationUnchanged
        : localizedCompanionCopy(locale).recalibrationUnavailable(review.explanation);
    }
  }
  const validation = validateCompanionProposal(proposal, context);
  let action = null;
  if (proposal.actionType !== "communicate" && validation.approved) {
    const actionIdentity = proposal.actionType === "recalibrate_plan" && proposal.adjustmentId
      ? `${userId}:${proposal.actionType}:${proposal.adjustmentId}`
      : `${userId}:${request.conversationKey}:${context.manifestId}:${proposal.actionType}:${proposal.workoutId ?? ""}:${proposal.targetCalories ?? ""}:${proposal.goalType ?? ""}`;
    const idempotencyKey = createHash("sha256")
      .update(actionIdentity)
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
  const message = reviewMessage ?? await generateCompanionMessage({
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
      title: proposal.actionType === "recalibrate_plan" ? localizedCompanionCopy(locale).recalibrationTitle : localizedCompanionCopy(locale).confirmationTitle,
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
  if (proposal.actionType === "set_workout_calories" && proposal.targetCalories) {
    return disposition === "confirmation_required"
      ? copy.calorieTarget(proposal.targetCalories)
      : copy.couldNotChange(proposal.rationale);
  }
  if (proposal.actionType === "update_run_goal_preference") {
    return disposition === "confirmation_required"
      ? copy.caloriePreference
      : copy.couldNotChange(proposal.rationale);
  }
  if (proposal.actionType === "recalibrate_plan") {
    return disposition === "confirmation_required"
      ? copy.recalibrationProposed(proposal.rationale)
      : copy.recalibrationUnavailable(proposal.rationale);
  }
  return copy.defaultMessage;
}

function localizedCompanionCopy(locale: SupportedLocale) {
  if (locale === "es") return {
    confirmationTitle: "¿Cambiar el entrenamiento de hoy?", acceptLabel: "Aplicar cambio", rejectLabel: "Mantener original",
    recalibrationTitle: "¿Aplicar esta actualización del plan?",
    suggestedReplies: ["¿Por qué este cambio?", "Mantener el original"],
    preparedExplanation: "Este ajuste se basa en tu plan actual y en las señales de entrenamiento disponibles.",
    shorten: (minutes: number, _rationale: string) => `Encontré una opción más segura para hoy: acortar el entrenamiento previsto a ${minutes} minutos. Todavía no lo he cambiado.`,
    calorieTarget: (calories: number) => `Puedo convertir la carrera suave prevista en un objetivo de ${calories} kcal. Antes de cambiarla, comprobaré tu peso privado y tu ritmo aprendido.`,
    caloriePreference: "Puedo usar calorías como objetivo habitual para futuras carreras suaves y de recuperación que cumplan los requisitos. Esto reconstruirá los entrenamientos próximos elegibles.",
    recalibrationProposed: (explanation: string) => `He revisado tu entrenamiento reciente, recuperación y próximos entrenamientos. Encontré una actualización útil: ${explanation} Todavía no he cambiado el plan.`,
    recalibrationUnchanged: "He revisado tu entrenamiento reciente, recuperación y próximos entrenamientos. Tu plan actual sigue siendo adecuado, así que no propongo ningún cambio.",
    recalibrationUnavailable: (_explanation: string) => "No puedo volver a evaluar el plan ahora mismo. Lo mantendré sin cambios.",
    couldNotChange: (_rationale: string) => "No pude preparar ese cambio de entrenamiento de forma segura.",
    defaultMessage: "Estoy usando tu plan actual, entrenamiento reciente, estado de hoy y preferencias confirmadas. Dime qué se siente difícil del plan de hoy y buscaré el ajuste útil más pequeño.",
  };
  if (locale === "zh-Hans") return {
    confirmationTitle: "要更改今天的训练吗？", acceptLabel: "应用更改", rejectLabel: "保留原计划",
    recalibrationTitle: "要应用这次计划更新吗？",
    suggestedReplies: ["为什么这样调整？", "保留原计划"],
    preparedExplanation: "此调整基于你当前的计划和现有训练信号。",
    shorten: (minutes: number, _rationale: string) => `我找到了更适合今天的安全方案：将计划训练缩短到 ${minutes} 分钟。我还没有进行更改。`,
    calorieTarget: (calories: number) => `我可以把计划中的轻松跑改为 ${calories} 千卡目标。更改前会先检查你的私密体重信息和已学习的配速。`,
    caloriePreference: "我可以让符合条件的轻松跑和恢复跑默认使用热量目标，并重新生成近期符合条件的训练。",
    recalibrationProposed: (explanation: string) => `我已结合近期训练、恢复状态和接下来的训练重新评估。发现一项值得调整的内容：${explanation} 我还没有更改计划。`,
    recalibrationUnchanged: "我已结合近期训练、恢复状态和接下来的训练重新评估。当前计划仍然合适，因此无需调整。",
    recalibrationUnavailable: (_explanation: string) => "目前无法重新评估训练计划。我会保持现有计划不变。",
    couldNotChange: (_rationale: string) => "我无法安全地准备这项训练更改。",
    defaultMessage: "我正在结合你当前的计划、近期训练、今日状态和已确认的偏好。告诉我今天的计划哪里感觉困难，我会帮你找到最小且有效的调整。",
  };
  return {
    confirmationTitle: "Change today's workout?", acceptLabel: "Apply change", rejectLabel: "Keep original",
    recalibrationTitle: "Apply this plan update?",
    suggestedReplies: ["Why this change?", "Keep the original"],
    preparedExplanation: "This adjustment is based on your current plan and available training signals.",
    shorten: (minutes: number, rationale: string) => `I found a safer fit for today: shorten the planned workout to ${minutes} minutes. ${rationale} I have not changed it yet.`,
    calorieTarget: (calories: number) => `I can replace the eligible easy run with a ${calories} kcal goal. I’ll validate your private weight and learned pace before changing it.`,
    caloriePreference: "I can make calories the recurring goal for eligible easy and recovery runs, then rebuild the upcoming workouts that qualify.",
    recalibrationProposed: (explanation: string) => `I reviewed your recent training, recovery, and upcoming workouts. I found a useful update: ${explanation} I have not changed the plan yet.`,
    recalibrationUnchanged: "I reviewed your recent training, recovery, and upcoming workouts. Your current plan still fits, so I am not proposing a change.",
    recalibrationUnavailable: (explanation: string) => `I could not reassess the plan right now, so I left it unchanged. ${explanation}`,
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
