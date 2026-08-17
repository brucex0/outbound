import { Prisma, type PrismaClient } from "@prisma/client";
import { appendRunnerEvidence } from "./evidenceService.js";

const PROJECTOR_VERSION = "companion-projector-v1";

export async function recordProfileEvidence(
  prisma: PrismaClient,
  userId: string,
  profile: {
    goalSummary: string | null;
    scheduleSummary: string | null;
    comfortableDurationMinutes: number | null;
    targetSessionsPerWeek: number;
    preferredLongRunDay: string | null;
    guidanceDetail: string;
    constraints: Prisma.JsonValue;
    updatedAt: Date;
  }
) {
  const evidence = await appendRunnerEvidence(prisma, userId, {
    dedupeKey: `profile:${userId}:${profile.updatedAt.toISOString()}`,
    type: "runner.profile_updated",
    source: "runner",
    subject: "runner_profile",
    payload: profile,
    consequenceLevel: "medium",
    observedAt: profile.updatedAt,
  });
  const entries = [
    profile.goalSummary ? { key: "goal-summary", kind: "goal", label: "Current goal", value: profile.goalSummary } : null,
    profile.scheduleSummary ? { key: "schedule-summary", kind: "schedule", label: "Usual schedule", value: profile.scheduleSummary } : null,
    { key: "weekly-capacity", kind: "schedule", label: "Target weekly sessions", value: `${profile.targetSessionsPerWeek} sessions` },
    profile.preferredLongRunDay ? { key: "long-run-day", kind: "schedule", label: "Preferred long-run day", value: profile.preferredLongRunDay } : null,
    { key: "guidance-detail", kind: "preference", label: "Guidance detail", value: profile.guidanceDetail },
  ].filter((entry): entry is NonNullable<typeof entry> => Boolean(entry));
  for (const entry of entries) {
    await upsertConfirmedBelief(prisma, userId, entry, evidence.id);
  }
  return persistCompanionModelVersion(prisma, userId, "profileUpdated");
}

export async function recordReadinessEvidence(
  prisma: PrismaClient,
  userId: string,
  input: { idempotencyKey: string; choice: string; recordedAt: string; note?: string | null }
) {
  return appendRunnerEvidence(prisma, userId, {
    dedupeKey: `readiness:${input.idempotencyKey}`,
    type: "readiness.submitted",
    source: "runner",
    subject: "current_readiness",
    payload: input,
    consequenceLevel: input.choice === "sore" ? "high" : "medium",
    observedAt: new Date(input.recordedAt),
    expiresAt: new Date(new Date(input.recordedAt).getTime() + 36 * 60 * 60 * 1000),
  });
}

export async function recordFeedbackEvidence(
  prisma: PrismaClient,
  userId: string,
  input: { idempotencyKey: string; workoutId: string; effort: string; continuationCapacity?: string | null; recordedAt: string; note?: string | null }
) {
  const evidence = await appendRunnerEvidence(prisma, userId, {
    dedupeKey: `feedback:${input.idempotencyKey}`,
    type: "workout.feedback_received",
    source: "runner",
    subject: input.workoutId,
    payload: input,
    consequenceLevel: "medium",
    observedAt: new Date(input.recordedAt),
  });
  const feedbackCount = await prisma.runnerEvidence.count({ where: { userId, type: "workout.feedback_received" } });
  const confidence = Math.min(0.9, 0.35 + feedbackCount * 0.1);
  const summary = input.effort === "tooHard"
    ? "Recent prescribed effort felt harder than intended"
    : input.effort === "easy"
      ? "Recent prescribed effort felt comfortably easy"
      : "Recent prescribed effort felt about right";
  await prisma.runnerBelief.upsert({
    where: { userId_stableKey: { userId, stableKey: "prescribed-effort-fit" } },
    create: {
      userId,
      stableKey: "prescribed-effort-fit",
      kind: "effort",
      label: "Workout effort fit",
      value: { effort: input.effort },
      summary,
      confidence,
      status: "hypothesis",
      source: "inferred",
      supportingEvidenceIds: [evidence.id],
      consequenceLevel: "medium",
    },
    update: {
      value: { effort: input.effort },
      summary,
      confidence,
      refreshedAt: new Date(),
      supportingEvidenceIds: { push: evidence.id },
    },
  });
  return persistCompanionModelVersion(prisma, userId, "workoutFeedbackSubmitted");
}

export async function correctRunnerBelief(
  prisma: PrismaClient,
  userId: string,
  stableKey: string,
  input: { value?: unknown; summary: string; label?: string; idempotencyKey: string }
) {
  const correctedValue = input.value ?? input.summary;
  const evidence = await appendRunnerEvidence(prisma, userId, {
    dedupeKey: `memory-correction:${input.idempotencyKey}`,
    type: "runner.fact_corrected",
    source: "runner",
    subject: stableKey,
    payload: { value: correctedValue, summary: input.summary },
    consequenceLevel: "high",
  });
  const belief = await prisma.runnerBelief.upsert({
    where: { userId_stableKey: { userId, stableKey } },
    create: {
      userId,
      stableKey,
      kind: "preference",
      label: input.label ?? stableKey,
      value: correctedValue as Prisma.InputJsonValue,
      summary: input.summary,
      confidence: 1,
      status: "confirmed",
      source: "runner",
      supportingEvidenceIds: [evidence.id],
      consequenceLevel: "medium",
    },
    update: {
      label: input.label,
      value: correctedValue as Prisma.InputJsonValue,
      summary: input.summary,
      confidence: 1,
      status: "confirmed",
      source: "runner",
      refreshedAt: new Date(),
      expiresAt: null,
      supportingEvidenceIds: [evidence.id],
      contradictingEvidenceIds: [],
    },
  });
  await persistCompanionModelVersion(prisma, userId, "runnerFactCorrected");
  return belief;
}

export async function forgetRunnerBelief(
  prisma: PrismaClient,
  userId: string,
  stableKey: string,
  idempotencyKey: string
) {
  await appendRunnerEvidence(prisma, userId, {
    dedupeKey: `memory-forgotten:${idempotencyKey}`,
    type: "runner.memory_forgotten",
    source: "runner",
    subject: stableKey,
    payload: { stableKey },
    consequenceLevel: "high",
  });
  const result = await prisma.runnerBelief.updateMany({
    where: { userId, stableKey },
    data: { status: "forgotten", refreshedAt: new Date() },
  });
  await persistCompanionModelVersion(prisma, userId, "runnerMemoryForgotten");
  return result.count > 0;
}

export async function persistCompanionModelVersion(prisma: PrismaClient, userId: string, reason: string) {
  const [latest, beliefs] = await Promise.all([
    prisma.runnerModelVersion.findFirst({ where: { userId }, orderBy: { versionNumber: "desc" } }),
    prisma.runnerBelief.findMany({ where: { userId, status: { in: ["confirmed", "hypothesis"] } }, orderBy: { stableKey: "asc" } }),
  ]);
  return prisma.runnerModelVersion.create({
    data: {
      userId,
      versionNumber: (latest?.versionNumber ?? 0) + 1,
      reason,
      snapshot: {
        projectorVersion: PROJECTOR_VERSION,
        beliefIds: beliefs.map((belief) => belief.id),
        beliefs: beliefs.map((belief) => ({ stableKey: belief.stableKey, summary: belief.summary, confidence: belief.confidence, status: belief.status })),
      },
      policyVersion: PROJECTOR_VERSION,
    },
  });
}

async function upsertConfirmedBelief(
  prisma: PrismaClient,
  userId: string,
  entry: { key: string; kind: string; label: string; value: string },
  evidenceId: string
) {
  return prisma.runnerBelief.upsert({
    where: { userId_stableKey: { userId, stableKey: entry.key } },
    create: {
      userId,
      stableKey: entry.key,
      kind: entry.kind,
      label: entry.label,
      value: entry.value,
      summary: entry.value,
      confidence: 1,
      status: "confirmed",
      source: "runner",
      supportingEvidenceIds: [evidenceId],
      consequenceLevel: "medium",
    },
    update: {
      value: entry.value,
      summary: entry.value,
      confidence: 1,
      status: "confirmed",
      source: "runner",
      refreshedAt: new Date(),
      supportingEvidenceIds: { push: evidenceId },
    },
  });
}
