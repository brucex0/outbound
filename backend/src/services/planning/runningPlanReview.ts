import type { Prisma } from "@prisma/client";
import { RunningScheduleError, ProgrammeTimelineError, ProgrammeConstraintError } from "./runningDosePolicy.js";
import { json } from "./persistence.js";

export interface RunningPlanReview {
  status: "needs_review";
  code: "running_schedule_conflict" | "programme_timeline_conflict" | "programme_constraints_conflict";
  category: "session_minimum" | "frequency_capacity" | "session_capacity" | "programme_timeline" | "programme_quality";
  action: "replacement_schedule_or_programme" | "later_date_or_replacement";
}
export function runningConstraintReview(error: unknown): RunningPlanReview | null {
  if (error instanceof RunningScheduleError) return { status: "needs_review", code: error.code, category: error.category, action: "replacement_schedule_or_programme" };
  if (error instanceof ProgrammeTimelineError) return { status: "needs_review", code: error.code, category: "programme_timeline", action: "later_date_or_replacement" };
  if (error instanceof ProgrammeConstraintError) return { status: "needs_review", code: error.code, category: "programme_quality", action: "replacement_schedule_or_programme" };
  return null;
}
function record(value: unknown): Record<string, unknown> { return value != null && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {}; }
export function runningPlanReview(decision: unknown): RunningPlanReview | null {
  const value = record(record(decision).runningPlanReview);
  if (value.status !== "needs_review") return null;
  if (value.code === "running_schedule_conflict" && ["session_minimum", "frequency_capacity", "session_capacity"].includes(String(value.category))) {
    return { status: "needs_review", code: value.code, category: value.category as RunningPlanReview["category"], action: "replacement_schedule_or_programme" };
  }
  if (value.code === "programme_timeline_conflict") return { status: "needs_review", code: value.code, category: "programme_timeline", action: "later_date_or_replacement" };
  if (value.code === "programme_constraints_conflict") return { status: "needs_review", code: value.code, category: "programme_quality", action: "replacement_schedule_or_programme" };
  return null;
}

/** Read-only notice projection: original generation fields remain stored unchanged. */
export function runningReviewDecision(decision: unknown): Record<string, unknown> {
  const original = record(decision), review = runningPlanReview(original);
  return review ? { ...original,
    programmeDoseStatus: review.code === "programme_timeline_conflict" ? original.programmeDoseStatus ?? "supported" : "needs_review",
    programmeTimelineStatus: "needs_review", minimumRemainingCalendarWeeks: null,
    minimumCalendarEstimateCondition: "requires_schedule_review", programmeReviewReason: review.category,
    programmeReviewAction: review.action,
  } : original;
}

/** Caller owns the planning-user lock. A stale event cannot label a newer/replacement plan. */
export async function retainRunningPlanForReview(tx: Prisma.TransactionClient, userId: string, review: RunningPlanReview,
  expected?: { planId?: string; versionId?: string }): Promise<boolean> {
  const plan = await active(tx, userId, expected?.planId);
  const version = plan?.versions[0];
  if (!plan || !version || !plan.goal.activities.includes("run")) return false;
  if (expected && "versionId" in expected && version.id !== expected.versionId) return false;
  const decision = record(version.engineDecision), previous = runningPlanReview(decision);
  if (previous?.code === review.code && previous.category === review.category && previous.action === review.action) return true;
  await tx.trainingPlanVersion.update({ where: { id: version.id }, data: { engineDecision: json({ ...decision, runningPlanReview: review }) } });
  console.info("[planning] running_plan_review", { result: "entered", category: review.category });
  return true;
}

/** Clear only the transient marker after a feasible refresh; never rewrite issued recipes. */
export async function clearRunningPlanReview(tx: Prisma.TransactionClient, userId: string, expectedPlanId?: string): Promise<void> {
  const plan = await active(tx, userId, expectedPlanId), version = plan?.versions[0];
  if (!version || !runningPlanReview(version.engineDecision)) return;
  const { runningPlanReview: _, ...decision } = record(version.engineDecision);
  await tx.trainingPlanVersion.update({ where: { id: version.id }, data: { engineDecision: json(decision) } });
  console.info("[planning] running_plan_review", { result: "cleared" });
}
function active(tx: Prisma.TransactionClient, userId: string, planId?: string) {
  return tx.trainingPlan.findFirst({ where: { userId, status: "active", ...(planId ? { id: planId } : {}) }, orderBy: { createdAt: "desc" },
    include: { goal: { select: { activities: true } }, versions: { orderBy: { versionNumber: "desc" }, take: 1 } } });
}
