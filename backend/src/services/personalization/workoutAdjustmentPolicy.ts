import { createHash } from "node:crypto";
import type { Prisma } from "@prisma/client";
import type { ActivitySuggestion, ActivitySuggestionResponse } from "../planning/types.js";

export const workoutPreviewPolicy = "workout-adjustment-preview-v1";

export class WorkoutAdjustmentError extends Error {
  constructor(readonly status: 404 | 409, message: string) { super(message); }
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
    date: response.validForDate, plan: response.planContext,
    primary: primary && {
      id: primary.id, title: primary.title, modality: primary.modality, stimulus: primary.stimulus,
      durationMinutes: primary.durationMinutes, distanceMeters: primary.distanceMeters,
      targetCalories: primary.targetCalories, steps: primary.steps, plannedWorkoutId: primary.plannedWorkoutId,
    },
    safetyFlags: response.decision.safetyFlags,
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
