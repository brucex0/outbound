import type { SupportedLocale } from "../../middleware/locale.js";
import { createHash } from "node:crypto";
import type { StandaloneWorkoutCatalogItem } from "../../data/standaloneWorkouts.js";
import type { Prisma } from "@prisma/client";
import type { ActivitySuggestion, ActivitySuggestionResponse } from "../planning/types.js";

/** Load/readiness advice permits only conservative explicit changes; health rest remains binding. */
export function hasBlockingSafetyGuidance(response: ActivitySuggestionResponse): boolean {
  return response.status === "restRecommended" || response.decision.safetyFlags.some((flag) =>
    !recoveryAdvised(response) || !["fatigue_medium", "fatigue_high", "readiness_or_health_concern"].includes(flag));
}
export function recoveryAdvised(response: ActivitySuggestionResponse): boolean {
  return response.decision.reasons.includes("recovery_advised");
}
export function isRecoveryWorkout(workout: StandaloneWorkoutCatalogItem, maximumSeconds: number): boolean {
  const seconds = workout.steps.reduce((sum, step) => sum + step.durationSeconds, 0);
  return workout.targetDistanceMeters == null && workout.coachingTarget?.pace == null && seconds > 0 && seconds <= Math.min(30 * 60, maximumSeconds)
    && workout.steps.every((step) => step.coachingTarget?.pace == null && !["work", "open"].includes(step.coachingTarget?.phase ?? "easy"))
    && workout.guideInstructions.segments.length > 0
    && workout.guideInstructions.segments.every((segment) => segment.effort.rpeMax <= 3);
}

export function recoveryChangeMessage(locale: SupportedLocale): string {
  if (locale === "es") return "Te recomendamos recuperarte. Elige una sesión de recuperación breve y muy suave, o descansa hoy.";
  if (locale === "zh-Hans") return "建议今天先恢复。请选择一次简短、轻松的恢复训练，或今天休息。";
  return "Recovery is recommended. Choose a short, very easy recovery workout or rest today.";
}

export const workoutApplyPolicy = "workout-adjustment-apply-v1";

export const workoutPreviewPolicy = "workout-adjustment-preview-v1";

export class WorkoutAdjustmentError extends Error {
  constructor(readonly status: 404 | 409, message: string, readonly code?: "recovery_change_required") { super(message); }
}

export type DailyPreviewChange = {
  kind: "daily";
  workoutId: string;
  beforeTitle: string;
  afterTitle: string;
  date: string;
  baselineFingerprint: string;
  readinessId: string | null;
  afterSuggestion: ActivitySuggestion;
};

export function suggestionFingerprint(response: ActivitySuggestionResponse): string {
  const primary = response.primary;
  return createHash("sha256").update(JSON.stringify({
    date: response.validForDate, plan: response.planContext, activity: response.activityWatermark,
    primary: primary && {
      id: primary.id, title: primary.title, modality: primary.modality, stimulus: primary.stimulus,
      durationMinutes: primary.durationMinutes, distanceMeters: primary.distanceMeters,
      targetCalories: primary.targetCalories, steps: primary.steps, plannedWorkoutId: primary.plannedWorkoutId,
    },
    safetyFlags: response.decision.safetyFlags,
  })).digest("hex");
}

/** Rest lasts for the day within the same plan even if its rolling window refills. */
export function restFingerprint(response: ActivitySuggestionResponse): string {
  return createHash("sha256").update(JSON.stringify({
    date: response.validForDate, planId: response.planContext?.planId ?? null, activity: response.activityWatermark,
  })).digest("hex");
}

export async function latestReadinessId(prisma: Prisma.TransactionClient, userId: string): Promise<string | null> {
  return (await prisma.readinessCheckIn.findFirst({ where: { userId }, orderBy: { date: "desc" }, select: { id: true } }))?.id ?? null;
}

export async function applyDailyWorkoutAdjustment(
  prisma: Prisma.TransactionClient,
  userId: string,
  baseline: ActivitySuggestionResponse,
): Promise<ActivitySuggestionResponse> {
  // Explicit Apply overrides also cover rest after a planned workout was skipped.
  const applied = await prisma.personalizationAdjustment.findFirst({
    where: { userId, status: "applied", policyVersion: workoutApplyPolicy, decidedAt: { gte: new Date(`${baseline.validForDate}T00:00:00Z`) } },
    orderBy: { decidedAt: "desc" },
  });
  const direct = (applied?.changes as unknown as Array<DailyPreviewChange & { rest: boolean }> | undefined)?.[0];
  if (direct && direct.date === baseline.validForDate && direct.baselineFingerprint === (direct.rest ? restFingerprint(baseline) : suggestionFingerprint(baseline))
    && (!hasBlockingSafetyGuidance(baseline) || direct.rest && baseline.decision.safetyFlags.length === 0) && direct.readinessId === await latestReadinessId(prisma, userId)) {
    return { ...baseline, primary: direct.rest ? null : direct.afterSuggestion, alternates: [],
      status: direct.rest ? "restRecommended" : "suggested", source: "adaptive",
      relationship: direct.rest ? "rest" : baseline.planContext ? "adjustedFromPlan" : "noPlanSuggestion",
      guideLine: applied!.explanation };
  }
  // Genuine safety decisions and current structured plan prescriptions always take precedence.
  if (!baseline.primary || baseline.primary.id.startsWith("planned-") || baseline.decision.safetyFlags.length > 0) return baseline;
  const proposal = await prisma.personalizationAdjustment.findFirst({
    where: { userId, status: "applied", policyVersion: workoutPreviewPolicy, decidedAt: { gte: new Date(`${baseline.validForDate}T00:00:00Z`) } },
    orderBy: { decidedAt: "desc" },
  });
  const change = (proposal?.changes as unknown as DailyPreviewChange[] | undefined)?.find((item) => item.kind === "daily");
  if (!change || change.date !== baseline.validForDate || change.baselineFingerprint !== suggestionFingerprint(baseline)) return baseline;
  if (change.readinessId !== await latestReadinessId(prisma, userId)) return baseline;
  return { ...baseline, primary: change.afterSuggestion, alternates: [] };
}
