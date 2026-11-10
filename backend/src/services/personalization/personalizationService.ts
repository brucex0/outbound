import { standaloneWorkoutCatalog } from "../../data/standaloneWorkouts.js";
import type { ActivitySuggestion, TrainingStimulus } from "../planning/types.js";
import { createHash } from "node:crypto";
import { refreshGeneratedPlanInTransaction } from "../planning/planRefresh.js";
import { lockPlanningUser, isOptionalWorkout } from "../planning/persistence.js";
import { Prisma } from "@prisma/client";
import { getPrismaClient } from "../prisma.js";
import type {
  AdjustmentProposal,
  PersonalizationSnapshot,
  ReadinessCheckInRequest,
  RunnerProfileInput,
  WorkoutFeedbackRequest,
  WorkoutAdjustmentPreviewRequest,
  WorkoutAdjustmentApplyRequest,
} from "./contracts.js";
import { calibrationWorkouts } from "./calibrationTemplates.js";
import { buildBaseActivitySuggestion, dailyConstraintAlternative } from "../planning/activitySuggestion.js";
import { applyDailyWorkoutAdjustment, latestReadinessId, suggestionFingerprint, workoutPreviewPolicy, WorkoutAdjustmentError, type DailyPreviewChange, workoutApplyPolicy, restFingerprint } from "./workoutAdjustmentPolicy.js";
export { WorkoutAdjustmentError } from "./workoutAdjustmentPolicy.js";
import {
  recordFeedbackEvidence,
  recordProfileEvidence,
  recordReadinessEvidence,
} from "../companion/runnerModelProjector.js";

const contractVersion = 1 as const;
const policyVersion = "personalization-v1";

type PreviewChange = AdjustmentProposal["changes"][number] & {
  kind: "planned";
  planVersionId: string;
  beforeDurationSeconds: number;
  afterDurationSeconds: number;
  date: string;
};

/** A workout-change preview is not a readiness check-in or a health/safety observation. */
export async function previewWorkoutAdjustment(userId: string, input: WorkoutAdjustmentPreviewRequest) {
  const prisma = getPrismaClient();
  const baseline = await buildBaseActivitySuggestion(userId);
  const current = await applyDailyWorkoutAdjustment(prisma, userId, baseline);
  const primary = current.primary;
  if (!primary || primary.id !== input.suggestionId || (primary.plannedWorkoutId ?? primary.id) !== input.workoutId || current.validForDate !== input.validForDate) {
    throw new WorkoutAdjustmentError(409, "The recommendation changed. Refresh before choosing an alternative.");
  }
  if (baseline.decision.safetyFlags.length > 0) {
    throw new WorkoutAdjustmentError(409, "Current safety guidance takes priority. Refresh before choosing an alternative.");
  }
  if (!primary.id.startsWith("planned-")) {
    if (input.choice === "good") return { adjustment: null };
    const alternative = { ...dailyConstraintAlternative(primary, input.choice), plannedWorkoutId: primary.plannedWorkoutId };
    const option = readinessAlternative(input.choice, { title: primary.title, durationSeconds: primary.durationMinutes * 60 });
    const change: DailyPreviewChange = {
      kind: "daily", workoutId: primary.id, beforeTitle: primary.title, afterTitle: alternative.title,
      date: baseline.validForDate, baselineFingerprint: suggestionFingerprint(baseline),
      readinessId: await latestReadinessId(prisma, userId), afterSuggestion: alternative,
    };
    const proposal = await prisma.personalizationAdjustment.create({ data: {
      userId, reasonCode: option.reasonCode, explanation: option.explanation,
      requiresConfirmation: true, changes: [change] as unknown as Prisma.InputJsonValue, policyVersion: workoutPreviewPolicy,
    } });
    return { adjustment: adjustmentRecordToDTO(proposal) };
  }
  const workout = await currentPreviewWorkout(prisma, userId, input.workoutId, baseline.validForDate);
  if (input.choice === "good") return { adjustment: null };
  const option = readinessAlternative(input.choice, workout);
  const shortRuns = (workout.planVersion.plan.goal.constraints as Record<string, unknown>).shortRunSessions;
  if (workout.modality === "run" && shortRuns !== true && shortRuns !== "true") {
    option.minutes = Math.max(20, option.minutes);
    option.afterTitle = `${workout.title.replace(/ · \d+ min$/, "")} · ${option.minutes} min`;
    if (option.minutes * 60 >= workout.durationSeconds) throw new WorkoutAdjustmentError(409, "This workout is already at its shortest supported duration.");
  }
  const change: PreviewChange = {
    kind: "planned",
    date: baseline.validForDate,
    workoutId: workout.id,
    beforeTitle: workout.title,
    afterTitle: option.afterTitle,
    planVersionId: workout.planVersionId,
    beforeDurationSeconds: workout.durationSeconds,
    afterDurationSeconds: option.minutes * 60,
  };
  const proposal = await prisma.personalizationAdjustment.create({ data: {
    userId, reasonCode: option.reasonCode, explanation: option.explanation,
    requiresConfirmation: true, changes: [change], policyVersion: workoutPreviewPolicy,
  } });
  return { adjustment: adjustmentRecordToDTO(proposal) };
}

/** Explicit user-approved one-day change; never writes readiness or touches an unrelated proposal. */
export async function applyWorkoutAdjustment(userId: string, input: WorkoutAdjustmentApplyRequest) {
  const prisma = getPrismaClient();
  const id = `workout-apply-${createHash("sha256").update(`${userId}:${input.idempotencyKey}`).digest("hex")}`;
  await prisma.$transaction(async (tx) => {
    await lockPlanningUser(tx, userId);
    if (await tx.personalizationAdjustment.findFirst({ where: { id, userId, status: "applied" } })) return;
    await refreshGeneratedPlanInTransaction(tx, userId, new Date());
    const baseline = await buildBaseActivitySuggestion(userId, "stable", new Date(), tx);
    const current = await applyDailyWorkoutAdjustment(tx, userId, baseline);
    const primary = current.primary;
    if (!primary || primary.id !== input.suggestionId || (primary.plannedWorkoutId ?? primary.id) !== input.workoutId
      || current.validForDate !== input.validForDate || baseline.decision.safetyFlags.length > 0) {
      throw new WorkoutAdjustmentError(409, "The recommendation changed. Refresh before applying a change.");
    }
    if (input.choice === "good" && input.action !== "catalog") throw new WorkoutAdjustmentError(409, "Choose a workout change first.");
    // Missing action uses the existing caller's reason-specific default.
    const action = input.action ?? (input.choice === "sore" ? "rest" : input.choice === "shortOnTime" ? "shorter" : "easy");
    if (input.choice === "sore" && action !== "rest") throw new WorkoutAdjustmentError(409, "Choose rest for soreness.");
    const rest = action === "rest";
    const catalog = action === "catalog" ? standaloneWorkoutCatalog.workouts.find((item) => item.id === input.catalogWorkoutId) : undefined;
    if (action === "catalog" && (!catalog || input.catalogVersion !== standaloneWorkoutCatalog.version || catalog.sport !== primary.modality)) {
      throw new WorkoutAdjustmentError(409, "The workout catalog changed. Refresh before choosing a workout.");
    }
    const plannedWorkout = primary.plannedWorkoutId ? await currentPreviewWorkout(tx, userId, primary.plannedWorkoutId, baseline.validForDate) : null;
    const originalSeconds = plannedWorkout?.durationSeconds ?? primary.durationSeconds ?? primary.durationMinutes * 60;
    const minutes = !input.action && input.choice === "tired" ? 15 : input.minutes;
    if (action === "shorter" && minutes * 60 >= originalSeconds) {
      throw new WorkoutAdjustmentError(409, "Choose a duration shorter than the current workout.");
    }
    if (input.action && action === "easy" && minutes * 60 > originalSeconds) {
      throw new WorkoutAdjustmentError(409, "An easier workout cannot extend the current session.");
    }
    const durationSeconds = catalog ? catalog.targetDistanceMeters ? Math.round(catalog.targetDistanceMeters / 1000 * 420) : catalog.steps.reduce((sum, step) => sum + step.durationSeconds, 0) : minutes * 60;
    const movement = primary.modality === "bike" ? "ride" : primary.modality;
    const title = rest ? "Rest today" : catalog?.title ?? `${minutes} min easy ${movement}`;
    const explanation = rest ? "Rest today. Return to activity when comfortable." : catalog?.guideLine ?? "Keep the effort easy and stop at the selected time.";
    const stimulus: TrainingStimulus = catalog ? ({ speed: "speed", tempo: "threshold", fartlek: "speed", hill: "speed", guided_distance: "longEndurance" } as Record<string, TrainingStimulus>)[catalog.category] ?? "easyAerobic" : "recovery";
    const effortLabel = catalog ? `RPE ${Math.min(...catalog.guideInstructions.segments.map((segment) => segment.effort.rpeMin), 10)}–${Math.max(...catalog.guideInstructions.segments.map((segment) => segment.effort.rpeMax), 1)}` : "Very easy";
    if (plannedWorkout) {
      const workout = plannedWorkout;
      if (rest) {
        await tx.plannedWorkout.update({ where: { id: workout.id }, data: { status: "skipped" } });
      } else {
        await tx.workoutBlock.deleteMany({ where: { plannedWorkoutId: workout.id } });
        await tx.plannedWorkout.update({ where: { id: workout.id }, data: {
          title, modality: catalog?.sport ?? workout.modality, durationSeconds, distanceMeters: catalog?.targetDistanceMeters ?? null, targetCalories: null,
          stimulus, intensityModel: "rpe", intensityTarget: catalog ? {} : { min: 1, max: 2 }, isKeyWorkout: false,
          prescription: { optional: isOptionalWorkout(workout), source: "explicitWorkoutChange", allowShortSession: true,
            ...(catalog ? { catalogWorkoutId: catalog.id, catalogVersion: standaloneWorkoutCatalog.version } : {}) },
          blocks: { create: catalog ? catalog.steps.map((step, sortOrder) => ({
            sortOrder, blockType: step.coachingTarget?.phase ?? "main", modality: catalog.sport, stimulus,
            durationSeconds: step.durationSeconds,
            steps: { create: { sortOrder: 0, kind: step.coachingTarget?.phase ?? "easy", label: step.label,
              durationSeconds: step.durationSeconds, detail: step.detail, target: (step.coachingTarget ?? {}) as Prisma.InputJsonValue } },
          })) : [{ sortOrder: 0, blockType: "main", modality: workout.modality, stimulus, durationSeconds,
            steps: { create: { sortOrder: 0, kind: "recovery", label: title, durationSeconds, target: { rpe: [1, 2] } } } }] },
        } });
      }
    }
    const nextBaseline = await buildBaseActivitySuggestion(userId, "stable", new Date(), tx);
    const afterSuggestion: ActivitySuggestion = { ...primary, id: primary.plannedWorkoutId ? primary.id : `changed-${input.idempotencyKey}`,
      title, durationMinutes: Math.ceil(durationSeconds / 60), durationSeconds, distanceMeters: catalog?.targetDistanceMeters ?? null, targetCalories: null, stimulus,
      intensityModel: "rpe", intensityTarget: catalog ? {} : { min: 1, max: 2 }, effortLabel,
      startLabel: catalog?.startLabel ?? primary.startLabel,
      steps: catalog ? catalog.steps.map((step) => step.label) : [title], why: explanation, allowShortSession: true,
      runWalk: catalog?.category === "walk_run", archetypeId: null,
      // Persist the authoritative structure, so refetch/cache/relaunch use the selected guide.
      catalogWorkout: catalog, catalogVersion: catalog ? standaloneWorkoutCatalog.version : undefined };
    await tx.personalizationAdjustment.create({ data: {
      id, userId, status: "applied", requiresConfirmation: false, decidedAt: new Date(), policyVersion: workoutApplyPolicy,
      reasonCode: input.choice === "sore" ? "soreness" : input.choice === "shortOnTime" ? "timeConstraint" : "fatigue", explanation,
      changes: [{ kind: "daily", rest, note: input.note?.trim() || null, workoutId: primary.id, beforeTitle: primary.title, afterTitle: title,
        date: baseline.validForDate, baselineFingerprint: rest ? restFingerprint(nextBaseline) : suggestionFingerprint(nextBaseline), readinessId: await latestReadinessId(tx, userId), afterSuggestion }] as unknown as Prisma.InputJsonValue,
    } });
  }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable, timeout: 30_000 });
  return { accepted: true };
}

async function currentPreviewWorkout(prisma: Prisma.TransactionClient, userId: string, workoutId: string, date: string) {
  const today = new Date(`${date}T00:00:00Z`);
  const tomorrow = new Date(today.getTime() + 86_400_000);
  const workout = await prisma.plannedWorkout.findFirst({
    where: {
      id: workoutId, userId, status: "planned", scheduledDate: { gte: today, lt: tomorrow },
      planVersion: { plan: { userId, status: "active" } },
    },
    include: {
      blocks: { include: { steps: true } },
      planVersion: { include: { plan: { include: { goal: true, versions: { orderBy: { versionNumber: "desc" }, take: 1, select: { id: true } } } } } },
    },
  });
  if (!workout) throw new WorkoutAdjustmentError(404, "The selected workout is no longer available.");
  if (workout.planVersion.plan.versions[0]?.id !== workout.planVersionId) {
    throw new WorkoutAdjustmentError(409, "The plan changed. Refresh before changing this workout.");
  }
  return workout;
}

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

  if (adjustment.policyVersion === workoutPreviewPolicy) {
    return prisma.$transaction(async (tx) => {
      const current = await tx.personalizationAdjustment.findFirst({ where: { id: adjustmentId, userId } });
      if (!current) throw new WorkoutAdjustmentError(404, "Adjustment not found.");
      if (current.status !== "proposed") return adjustmentRecordToDTO(current);
      if (decision === "accept") {
        for (const change of current.changes as unknown as (PreviewChange | DailyPreviewChange)[]) {
          if (change.kind === "daily") {
            const baseline = await buildBaseActivitySuggestion(userId, "stable", new Date(), tx);
            const currentSuggestion = await applyDailyWorkoutAdjustment(tx, userId, baseline);
            if (change.date !== baseline.validForDate || change.baselineFingerprint !== suggestionFingerprint(baseline)
              || baseline.decision.safetyFlags.length > 0 || currentSuggestion.primary?.id !== change.workoutId || change.readinessId !== await latestReadinessId(tx, userId)) {
              throw new WorkoutAdjustmentError(409, "The recommendation changed. Request a new alternative.");
            }
            continue;
          }
          const baseline = await buildBaseActivitySuggestion(userId, "stable", new Date(), tx);
          if (change.date !== baseline.validForDate || baseline.primary?.plannedWorkoutId !== change.workoutId || baseline.decision.safetyFlags.length > 0) {
            throw new WorkoutAdjustmentError(409, "The recommendation changed. Request a new alternative.");
          }
          const workout = await currentPreviewWorkout(tx, userId, change.workoutId, baseline.validForDate);
          if (workout.planVersionId !== change.planVersionId || workout.title !== change.beforeTitle || workout.durationSeconds !== change.beforeDurationSeconds) {
            throw new WorkoutAdjustmentError(409, "The workout changed. Request a new alternative.");
          }
          const shortRuns = (workout.planVersion.plan.goal.constraints as Record<string, unknown>).shortRunSessions;
          await resizeWorkout(tx, workout, change.afterTitle, change.afterDurationSeconds, workout.modality === "run" && shortRuns !== true && shortRuns !== "true" ? 900 : 0);
        }
      }
      const updated = await tx.personalizationAdjustment.update({
        where: { id: current.id },
        data: { status: decision === "accept" ? "applied" : "rejected", decidedAt: new Date() },
      });
      return adjustmentRecordToDTO(updated);
    }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable });
  }

  const changes = adjustment.changes as unknown as AdjustmentProposal["changes"];
  if (decision === "accept") {
    for (const change of changes) {
      const minutes = minutesFromTitle(change.afterTitle);
      if (minutes) await resizePlannedWorkout(userId, change.workoutId, change.afterTitle, minutes * 60);
    }
  }

  const updated = await prisma.personalizationAdjustment.update({
    where: { id: adjustment.id },
    data: { status: decision === "accept" ? "applied" : "rejected", decidedAt: new Date() },
  });
  await persistModelVersion(userId, decision === "accept" ? "adjustmentApplied" : "adjustmentRejected");
  return adjustmentRecordToDTO(updated);
}

async function resizePlannedWorkout(userId: string, workoutId: string, title: string, durationSeconds: number) {
  const prisma = getPrismaClient();
  const workout = await prisma.plannedWorkout.findFirst({
    where: { id: workoutId, userId, status: "planned" },
    include: { blocks: { include: { steps: true } } },
  });
  if (!workout || workout.durationSeconds <= 0) return;
  await prisma.$transaction((tx) => resizeWorkout(tx, workout, title, durationSeconds));
}

async function resizeWorkout(
  tx: Prisma.TransactionClient,
  workout: { id: string; durationSeconds: number; blocks: Array<{ id: string; blockType: string; durationSeconds: number | null; steps: Array<{ id: string; durationSeconds: number | null }> }> },
  title: string,
  durationSeconds: number,
  minimumMainSeconds = 0,
) {
    const ratio = durationSeconds / workout.durationSeconds;
    const mainSeconds = workout.blocks.filter((block) => block.blockType === "main").reduce((sum, block) => sum + (block.durationSeconds ?? 0), 0);
    const nextMainSeconds = mainSeconds > 0 ? Math.max(Math.min(minimumMainSeconds, mainSeconds), Math.round(mainSeconds * ratio)) : 0;
    const supportingSeconds = workout.durationSeconds - mainSeconds;
    if (nextMainSeconds >= durationSeconds && supportingSeconds > 0) throw new WorkoutAdjustmentError(409, "The alternative is too short for this workout.");
    for (const block of workout.blocks) {
      const blockRatio = minimumMainSeconds > 0 && mainSeconds > 0
        ? block.blockType === "main" ? nextMainSeconds / mainSeconds : supportingSeconds > 0 ? (durationSeconds - nextMainSeconds) / supportingSeconds : ratio
        : ratio;
      if (block.durationSeconds != null) {
        await tx.workoutBlock.update({
          where: { id: block.id },
          data: { durationSeconds: Math.max(1, Math.round(block.durationSeconds * blockRatio)) },
        });
      }
      for (const step of block.steps) {
        if (step.durationSeconds != null) {
          await tx.workoutStep.update({
            where: { id: step.id },
            data: { durationSeconds: Math.max(1, Math.round(step.durationSeconds * blockRatio)) },
          });
        }
      }
    }
    await tx.plannedWorkout.update({
      where: { id: workout.id },
      data: { title, durationSeconds },
    });
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
  const option = readinessAlternative(input.choice, workout);
  return createAdjustment(userId, option.reasonCode, option.explanation, workout.id, workout.title, option.afterTitle);
}

function readinessAlternative(choice: ReadinessCheckInRequest["choice"], workout: { title: string; durationSeconds: number }) {
  const reasonCode = choice === "shortOnTime" ? "timeConstraint" : choice === "sore" ? "soreness" : "fatigue";
  const minutes = Math.max(15, Math.round(workout.durationSeconds / 60 * 0.7 / 5) * 5);
  const explanation = choice === "sore" ? "Soreness can make the planned load a poor fit today. A shorter easy option protects continuity without asking you to push through pain." : `Your ${choice === "tired" ? "fatigue" : "available time"} makes a shorter easy option a better fit today.`;
  return { reasonCode: reasonCode as AdjustmentProposal["reasonCode"], minutes, explanation, afterTitle: `${workout.title.replace(/ · \d+ min$/, "")} · ${minutes} min` };
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
  const changes = (record.changes as unknown as AdjustmentProposal["changes"]).map(({ workoutId, beforeTitle, afterTitle }) => ({ workoutId, beforeTitle, afterTitle }));
  return { id: record.id, reasonCode: record.reasonCode as AdjustmentProposal["reasonCode"], explanation: record.explanation, requiresConfirmation: record.requiresConfirmation, changes };
}

function profileData(input: RunnerProfileInput) {
  return {
    ...(input.goalSummary !== undefined ? { goalSummary: input.goalSummary } : {}),
    ...(input.scheduleSummary !== undefined ? { scheduleSummary: input.scheduleSummary } : {}),
    ...(input.comfortableDurationMinutes !== undefined ? { comfortableDurationMinutes: input.comfortableDurationMinutes } : {}),
    ...(input.recentSessionsPerWeek !== undefined ? { recentSessionsPerWeek: input.recentSessionsPerWeek } : {}),
    ...(input.targetSessionsPerWeek !== undefined ? { targetSessionsPerWeek: input.targetSessionsPerWeek } : {}),
    ...(input.preferredLongRunDay !== undefined ? { preferredLongRunDay: input.preferredLongRunDay } : {}),
    ...(input.guidanceDetail !== undefined ? { guidanceDetail: input.guidanceDetail } : {}),
    ...(input.primaryMotivation !== undefined ? { primaryMotivation: input.primaryMotivation } : {}),
    ...(input.preferredRunGoalType !== undefined ? { preferredRunGoalType: input.preferredRunGoalType } : {}),
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
