import { Prisma } from "@prisma/client";
import { getPrismaClient } from "../prisma.js";
import type {
  AdjustmentProposal,
  PersonalizationSnapshot,
  ReadinessCheckInRequest,
  RunnerProfileInput,
  WorkoutFeedbackRequest,
} from "./contracts.js";
import { calibrationWorkouts } from "./calibrationTemplates.js";
import {
  recordFeedbackEvidence,
  recordProfileEvidence,
  recordReadinessEvidence,
} from "../companion/runnerModelProjector.js";

const contractVersion = 1 as const;
const policyVersion = "personalization-v1";

export async function getPersonalizationSnapshot(userId: string): Promise<PersonalizationSnapshot> {
  const prisma = getPrismaClient();
  const [calibration, insights, pendingAdjustment, latestVersion, profile] = await Promise.all([
    ensureCalibration(userId),
    prisma.runnerInsight.findMany({ where: { userId }, orderBy: { updatedAt: "desc" } }),
    prisma.personalizationAdjustment.findFirst({
      where: { userId, status: "proposed" },
      orderBy: { createdAt: "desc" },
    }),
    prisma.runnerModelVersion.findFirst({ where: { userId }, orderBy: { versionNumber: "desc" } }),
    prisma.runnerProfile.findUnique({ where: { userId } }),
  ]);

  return {
    contractVersion,
    modelVersion: latestVersion?.id ?? "runner-model-empty",
    generatedAt: isoDate(new Date()),
    calibration: {
      status: calibration.status as PersonalizationSnapshot["calibration"]["status"],
      completedSessionCount: calibration.completedSessionCount,
      targetSessionCount: calibration.targetSessionCount,
      currentSession: calibration.currentSession as PersonalizationSnapshot["calibration"]["currentSession"],
    },
    calibrationWorkouts: calibrationWorkouts(profile?.comfortableDurationMinutes ?? 30),
    insights: insights.map((insight) => ({
      id: insight.stableKey,
      kind: insight.kind as PersonalizationSnapshot["insights"][number]["kind"],
      label: insight.label,
      value: insight.value,
      confidence: insight.confidence as PersonalizationSnapshot["insights"][number]["confidence"],
      evidenceCount: insight.evidenceCount,
      lastUpdatedAt: isoDate(insight.updatedAt),
    })),
    pendingAdjustment: pendingAdjustment
      ? adjustmentRecordToDTO(pendingAdjustment)
      : null,
  };
}

export async function upsertRunnerProfile(userId: string, input: RunnerProfileInput) {
  const prisma = getPrismaClient();
  const profile = await prisma.runnerProfile.upsert({
    where: { userId },
    create: {
      userId,
      ...profileData(input),
      completedAt: input.complete ? new Date() : null,
    },
    update: {
      ...profileData(input),
      ...(input.complete ? { completedAt: new Date() } : {}),
    },
  });

  await seedProfileInsights(userId, profile);
  await ensureCalibration(userId, input.complete === true);
  await persistModelVersion(userId, "profileUpdated");
  await recordProfileEvidence(prisma, userId, profile);
  return { profile, personalization: await getPersonalizationSnapshot(userId) };
}

export async function submitReadinessCheckIn(userId: string, input: ReadinessCheckInRequest) {
  const prisma = getPrismaClient();
  const existing = await prisma.readinessCheckIn.findUnique({ where: { clientRequestId: input.idempotencyKey } });
  if (existing && existing.userId !== userId) throw new Error("Idempotency key already used.");
  if (!existing) {
    const values = readinessValues(input.choice);
    await prisma.readinessCheckIn.create({
      data: {
        userId,
        clientRequestId: input.idempotencyKey,
        choice: input.choice,
        date: new Date(input.recordedAt),
        notes: input.note ?? null,
        ...values,
      },
    });
    await recordReadinessEvidence(prisma, userId, input);
  }

  const adjustment = await createReadinessAdjustment(userId, input);
  return { accepted: true, adjustment, personalization: await getPersonalizationSnapshot(userId) };
}

export async function submitWorkoutFeedback(userId: string, input: WorkoutFeedbackRequest) {
  const prisma = getPrismaClient();
  const existing = await prisma.workoutFeedback.findUnique({ where: { clientRequestId: input.idempotencyKey } });
  if (existing && existing.userId !== userId) throw new Error("Idempotency key already used.");
  if (!existing) {
    await prisma.workoutFeedback.create({
      data: {
        userId,
        clientRequestId: input.idempotencyKey,
        workoutId: input.workoutId,
        activityId: input.activityId ?? null,
        recordedAt: new Date(input.recordedAt),
        effort: input.effort,
        continuationCapacity: input.continuationCapacity ?? null,
        note: input.note ?? null,
      },
    });
    await projectFeedback(userId, input);
    if (input.workoutId.startsWith("calibration-")) {
      await advanceCalibration(userId);
    }
    await persistModelVersion(userId, "workoutFeedbackSubmitted");
    await recordFeedbackEvidence(prisma, userId, input);
  }

  const adjustment = await createFeedbackAdjustment(userId, input);
  return { accepted: true, adjustment, personalization: await getPersonalizationSnapshot(userId) };
}

export async function decideAdjustment(userId: string, adjustmentId: string, decision: "accept" | "reject") {
  const prisma = getPrismaClient();
  const adjustment = await prisma.personalizationAdjustment.findFirst({ where: { id: adjustmentId, userId } });
  if (!adjustment) throw new Error("Adjustment not found.");
  if (adjustment.status !== "proposed") return adjustmentRecordToDTO(adjustment);

  const changes = adjustment.changes as unknown as AdjustmentProposal["changes"];
  if (decision === "accept") {
    for (const change of changes) {
      const minutes = minutesFromTitle(change.afterTitle);
      if (minutes) {
        await prisma.plannedWorkout.updateMany({
          where: { id: change.workoutId, userId, status: "planned" },
          data: { title: change.afterTitle, durationSeconds: minutes * 60 },
        });
      }
    }
  }

  const updated = await prisma.personalizationAdjustment.update({
    where: { id: adjustment.id },
    data: { status: decision === "accept" ? "applied" : "rejected", decidedAt: new Date() },
  });
  await persistModelVersion(userId, decision === "accept" ? "adjustmentApplied" : "adjustmentRejected");
  return adjustmentRecordToDTO(updated);
}

async function ensureCalibration(userId: string, start = false) {
  const prisma = getPrismaClient();
  const existing = await prisma.calibrationProgram.findUnique({ where: { userId } });
  if (existing) {
    if (start && existing.status === "notStarted") {
      return prisma.calibrationProgram.update({ where: { userId }, data: { status: "inProgress", startedAt: new Date(), currentSession: "comfortableRun" } });
    }
    return existing;
  }
  return prisma.calibrationProgram.create({ data: { userId, status: start ? "inProgress" : "notStarted", startedAt: start ? new Date() : null, currentSession: start ? "comfortableRun" : null } });
}

async function advanceCalibration(userId: string) {
  const prisma = getPrismaClient();
  const current = await ensureCalibration(userId, true);
  const completed = Math.min(current.completedSessionCount + 1, current.targetSessionCount);
  const sessions = ["comfortableRun", "easyPickups", "longerRelaxedRun"];
  await prisma.calibrationProgram.update({
    where: { userId },
    data: {
      completedSessionCount: completed,
      status: completed >= current.targetSessionCount ? "completed" : "inProgress",
      currentSession: completed >= current.targetSessionCount ? null : sessions[completed],
      completedAt: completed >= current.targetSessionCount ? new Date() : null,
    },
  });
}

async function projectFeedback(userId: string, input: WorkoutFeedbackRequest) {
  // Effort alone is useful for load adjustment, but it cannot tell us how much
  // duration reserve the runner had. Do not turn a skipped follow-up into a
  // false "near today's limit" endurance observation.
  if (!input.continuationCapacity) return;

  const prisma = getPrismaClient();
  const feedbackCount = await prisma.workoutFeedback.count({ where: { userId } });
  const confidence = feedbackCount >= 5 ? "high" : feedbackCount >= 3 ? "medium" : "low";
  const sustainable = input.continuationCapacity === "muchLonger"
    ? "Current duration leaves substantial reserve"
    : input.continuationCapacity === "tenMinutes"
      ? "Current duration is comfortably sustainable"
      : "Current duration may be near today's limit";
  await prisma.runnerInsight.upsert({
    where: { userId_stableKey: { userId, stableKey: "comfortable-duration" } },
    create: {
      userId,
      stableKey: "comfortable-duration",
      kind: "endurance",
      label: "Comfortable duration",
      value: sustainable,
      confidence,
      evidenceCount: 1,
      evidence: [{ type: "workoutFeedback", requestId: input.idempotencyKey }],
    },
    update: {
      value: sustainable,
      confidence,
      evidenceCount: { increment: 1 },
      evidence: [{ type: "workoutFeedback", requestId: input.idempotencyKey }],
    },
  });
}

async function seedProfileInsights(userId: string, profile: { comfortableDurationMinutes: number | null; targetSessionsPerWeek: number; preferredLongRunDay: string | null }) {
  const prisma = getPrismaClient();
  if (profile.comfortableDurationMinutes) {
    await prisma.runnerInsight.upsert({
      where: { userId_stableKey: { userId, stableKey: "comfortable-duration" } },
      create: { userId, stableKey: "comfortable-duration", kind: "endurance", label: "Comfortable duration", value: `About ${profile.comfortableDurationMinutes} minutes`, confidence: "low", evidenceCount: 1, evidence: [{ type: "runnerProfile" }] },
      update: { value: `About ${profile.comfortableDurationMinutes} minutes` },
    });
  }
  const day = profile.preferredLongRunDay ? `, ${profile.preferredLongRunDay} longer` : "";
  await prisma.runnerInsight.upsert({
    where: { userId_stableKey: { userId, stableKey: "weekly-capacity" } },
    create: { userId, stableKey: "weekly-capacity", kind: "schedule", label: "Realistic week", value: `${profile.targetSessionsPerWeek} runs${day}`, confidence: "medium", evidenceCount: 1, evidence: [{ type: "runnerProfile" }] },
    update: { value: `${profile.targetSessionsPerWeek} runs${day}` },
  });
}

async function createReadinessAdjustment(userId: string, input: ReadinessCheckInRequest) {
  if (input.choice === "good") return null;
  const workout = await nextPlannedWorkout(userId, input.workoutId);
  if (!workout) return null;
  const reasonCode = input.choice === "shortOnTime" ? "timeConstraint" : input.choice === "sore" ? "soreness" : "fatigue";
  const minutes = Math.max(15, Math.round(workout.durationSeconds / 60 * 0.7 / 5) * 5);
  return createAdjustment(userId, reasonCode, input.choice === "sore" ? "Soreness can make the planned load a poor fit today. A shorter easy option protects continuity without asking you to push through pain." : `Your ${input.choice === "tired" ? "fatigue" : "available time"} makes a shorter easy option a better fit today.`, workout.id, workout.title, `${workout.title.replace(/ · \d+ min$/, "")} · ${minutes} min`);
}

async function createFeedbackAdjustment(userId: string, input: WorkoutFeedbackRequest) {
  if (input.effort !== "tooHard") return null;
  const workout = await nextPlannedWorkout(userId);
  if (!workout) return null;
  const minutes = Math.max(15, Math.round(workout.durationSeconds / 60 * 0.8 / 5) * 5);
  return createAdjustment(userId, "harderThanExpected", "Your last run felt harder than intended, so the next session is reduced instead of stacking more load.", workout.id, workout.title, `${workout.title.replace(/ · \d+ min$/, "")} · ${minutes} min`);
}

async function nextPlannedWorkout(userId: string, preferredId?: string) {
  const prisma = getPrismaClient();
  if (preferredId) {
    const selected = await prisma.plannedWorkout.findFirst({ where: { id: preferredId, userId, status: "planned" } });
    if (selected) return selected;
  }
  return prisma.plannedWorkout.findFirst({ where: { userId, status: "planned", scheduledDate: { gte: new Date(new Date().setHours(0, 0, 0, 0)) } }, orderBy: { scheduledDate: "asc" } });
}

async function createAdjustment(userId: string, reasonCode: AdjustmentProposal["reasonCode"], explanation: string, workoutId: string, beforeTitle: string, afterTitle: string) {
  const prisma = getPrismaClient();
  const existing = await prisma.personalizationAdjustment.findFirst({ where: { userId, status: "proposed", reasonCode }, orderBy: { createdAt: "desc" } });
  if (existing) return adjustmentRecordToDTO(existing);
  const created = await prisma.personalizationAdjustment.create({ data: { userId, reasonCode, explanation, requiresConfirmation: true, changes: [{ workoutId, beforeTitle, afterTitle }], policyVersion } });
  return adjustmentRecordToDTO(created);
}

async function persistModelVersion(userId: string, reason: string) {
  const prisma = getPrismaClient();
  const [latest, calibration, insights] = await Promise.all([
    prisma.runnerModelVersion.findFirst({ where: { userId }, orderBy: { versionNumber: "desc" } }),
    ensureCalibration(userId),
    prisma.runnerInsight.findMany({ where: { userId } }),
  ]);
  const snapshot = {
    calibration: {
      status: calibration.status,
      completedSessionCount: calibration.completedSessionCount,
      targetSessionCount: calibration.targetSessionCount,
      currentSession: calibration.currentSession,
    },
    insights: insights.map((insight) => ({
      stableKey: insight.stableKey,
      kind: insight.kind,
      value: insight.value,
      confidence: insight.confidence,
      evidenceCount: insight.evidenceCount,
      updatedAt: isoDate(insight.updatedAt),
    })),
  };
  await prisma.runnerModelVersion.create({ data: { userId, versionNumber: (latest?.versionNumber ?? 0) + 1, reason, policyVersion, snapshot: snapshot as Prisma.InputJsonValue } });
}

function adjustmentRecordToDTO(record: { id: string; reasonCode: string; explanation: string; requiresConfirmation: boolean; changes: Prisma.JsonValue }): AdjustmentProposal {
  return { id: record.id, reasonCode: record.reasonCode as AdjustmentProposal["reasonCode"], explanation: record.explanation, requiresConfirmation: record.requiresConfirmation, changes: record.changes as unknown as AdjustmentProposal["changes"] };
}

function profileData(input: RunnerProfileInput) {
  return {
    ...(input.goalSummary !== undefined ? { goalSummary: input.goalSummary } : {}),
    ...(input.scheduleSummary !== undefined ? { scheduleSummary: input.scheduleSummary } : {}),
    ...(input.comfortableDurationMinutes !== undefined ? { comfortableDurationMinutes: input.comfortableDurationMinutes } : {}),
    ...(input.recentSessionsPerWeek !== undefined ? { recentSessionsPerWeek: input.recentSessionsPerWeek } : {}),
    ...(input.targetSessionsPerWeek !== undefined ? { targetSessionsPerWeek: input.targetSessionsPerWeek } : {}),
    ...(input.preferredLongRunDay !== undefined ? { preferredLongRunDay: input.preferredLongRunDay } : {}),
    ...(input.coachingDetail !== undefined ? { coachingDetail: input.coachingDetail } : {}),
    ...(input.constraints !== undefined ? { constraints: input.constraints as Prisma.InputJsonValue } : {}),
  };
}

function readinessValues(choice: ReadinessCheckInRequest["choice"]) {
  switch (choice) {
    case "good": return { energy: 4, soreness: 1, sleepQuality: 4, stress: 1, motivation: 4, illnessOrPain: false };
    case "tired": return { energy: 2, soreness: 2, sleepQuality: 2, stress: 3, motivation: 3, illnessOrPain: false };
    case "sore": return { energy: 3, soreness: 5, sleepQuality: 3, stress: 2, motivation: 3, illnessOrPain: true };
    case "shortOnTime": return { energy: 3, soreness: 1, sleepQuality: 3, stress: 3, motivation: 3, illnessOrPain: false };
  }
}

function minutesFromTitle(title: string) {
  const match = title.match(/(\d+) min$/);
  return match ? Number(match[1]) : null;
}

function isoDate(date: Date) {
  return date.toISOString().replace(/\.\d{3}Z$/, "Z");
}
