import { createHash } from "node:crypto";
import type { PrismaClient } from "@prisma/client";
import type { CompanionTurnRequest } from "./contracts.js";
import { loadAuthoritativeRunnerState } from "./domainToolGateway.js";
import { getRelevantSituationalSignals } from "./situationalIntelligence.js";
import type { CompiledContext, ContextReference } from "./types.js";

const TASK_BUDGETS: Record<CompanionTurnRequest["task"], number> = {
  answer_training_question: 5_000,
  adapt_today: 4_500,
  prepare_week: 7_000,
  post_run_reflection: 4_000,
  live_guidance: 1_600,
  inspect_memory: 3_000,
  product_help: 2_500,
};

export async function compileCompanionContext(
  prisma: PrismaClient,
  userId: string,
  request: CompanionTurnRequest
): Promise<CompiledContext> {
  const tokenBudget = TASK_BUDGETS[request.task];
  const [state, beliefs, episodes, signals, conversation] = await Promise.all([
    loadAuthoritativeRunnerState(prisma, userId, request.timeZoneIdentifier),
    prisma.runnerBelief.findMany({
      where: {
        userId,
        status: { in: ["confirmed", "hypothesis"] },
        OR: [{ expiresAt: null }, { expiresAt: { gt: new Date() } }],
      },
      orderBy: [{ consequenceLevel: "desc" }, { confidence: "desc" }, { refreshedAt: "desc" }],
      take: request.task === "prepare_week" ? 18 : 10,
    }),
    prisma.companionEpisode.findMany({
      where: { userId, OR: [{ expiresAt: null }, { expiresAt: { gt: new Date() } }] },
      orderBy: [{ salience: "desc" }, { occurredAt: "desc" }],
      take: request.task === "prepare_week" ? 8 : 4,
    }),
    getRelevantSituationalSignals(prisma, userId),
    prisma.companionConversationState.findUnique({
      where: { userId_conversationKey: { userId, conversationKey: request.conversationKey } },
    }),
  ]);

  const includedRefs: ContextReference[] = [
    ...beliefs.map((belief) => ({ type: "belief", id: belief.id, reason: `ranked:${belief.consequenceLevel}:${belief.confidence.toFixed(2)}` })),
    ...episodes.map((episode) => ({ type: "episode", id: episode.id, reason: `salience:${episode.salience.toFixed(2)}` })),
    ...signals.map((signal) => ({ type: "signal", id: String(signal.id), reason: `fresh:${signal.type}` })),
  ];

  const runnerCore = state.profile ? {
    goalSummary: state.profile.goalSummary,
    scheduleSummary: state.profile.scheduleSummary,
    comfortableDurationMinutes: state.profile.comfortableDurationMinutes,
    targetSessionsPerWeek: state.profile.targetSessionsPerWeek,
    preferredLongRunDay: state.profile.preferredLongRunDay,
    guidanceDetail: state.profile.guidanceDetail,
    constraints: state.profile.constraints,
  } : {};
  const currentState = {
    activePlan: state.activePlan ? { id: state.activePlan.id, phase: state.activePlan.currentPhase } : null,
    nextWorkouts: state.nextWorkouts.map((workout) => ({
      id: workout.id,
      scheduledDate: workout.scheduledDate.toISOString(),
      title: workout.title,
      durationSeconds: workout.durationSeconds,
      stimulus: workout.stimulus,
      isKeyWorkout: workout.isKeyWorkout,
    })),
    latestReadiness: state.latestReadiness,
    recentActivities: state.recentActivities,
    weeklyTotals: state.weeklyAggregate,
  };
  const conversationContext = conversation ? {
    objective: conversation.objective,
    decisions: conversation.decisions,
    openQuestions: conversation.openQuestions,
    promisedFollowUps: conversation.promisedFollowUps,
    compactSummary: conversation.compactSummary,
    lastMessages: conversation.lastMessages,
  } : { lastMessages: request.recentMessages.slice(-6) };

  const draft = {
    task: request.task,
    runnerCore,
    currentState,
    beliefs: beliefs.map((belief) => ({ id: belief.id, stableKey: belief.stableKey, kind: belief.kind, summary: belief.summary, confidence: belief.confidence, status: belief.status, consequenceLevel: belief.consequenceLevel, expiresAt: belief.expiresAt?.toISOString() ?? null })),
    episodes: episodes.map((episode) => ({ id: episode.id, kind: episode.kind, summary: episode.summary, occurredAt: episode.occurredAt.toISOString() })),
    signals,
    conversation: conversationContext,
  };
  const serialized = JSON.stringify(draft);
  const estimatedTokens = Math.ceil(serialized.length / 4);
  const contextHash = createHash("sha256").update(serialized).digest("hex");
  const manifest = await prisma.contextManifest.create({
    data: {
      userId,
      task: request.task,
      surface: request.surface,
      runnerModelVersion: state.runnerModelVersion,
      planVersion: state.nextWorkouts[0]?.planVersionId ?? null,
      tokenBudget,
      estimatedTokens,
      includedRefs,
      omittedRefs: estimatedTokens > tokenBudget ? [{ reason: "budget_pressure", estimatedTokens }] : [],
      sectionBudgets: { policies: 0.15, currentState: 0.25, memories: 0.25, conversation: 0.1, tools: 0.1, response: 0.15 },
      contextHash,
    },
  });

  return {
    task: request.task,
    surface: request.surface,
    runnerModelVersion: state.runnerModelVersion,
    manifestId: manifest.id,
    tokenBudget,
    estimatedTokens,
    systemRules: [
      "Use only supplied evidence and authoritative tool state.",
      "Never diagnose pain or concerning symptoms.",
      "Safety constraints outrank training goals, life constraints, preferences, and convenience.",
      "Do not claim an action occurred unless the executor confirms it.",
    ],
    runnerCore,
    currentState,
    beliefs: draft.beliefs,
    episodes: draft.episodes,
    situationalSignals: signals,
    conversation: conversationContext,
    includedRefs,
  };
}
