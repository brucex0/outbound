import type { PlanningEvent } from "@prisma/client";
import { getPrismaClient } from "../prisma.js";
import type { PlanningEventType } from "./types.js";

const DEFAULT_NORMAL_DAILY_LIMIT = 2;
const DEFAULT_MANUAL_COOLDOWN_MINUTES = 120;

const CRITICAL_EVENTS = new Set<PlanningEventType>([
  "painFlagged",
  "goalUpdated",
  "scheduleUpdated",
]);

export type EvaluationAdmission =
  | { allowed: true; critical: boolean }
  | { allowed: false; reason: "daily_limit" | "manual_cooldown"; retryAt: Date };

export async function evaluationAdmission(
  event: PlanningEvent,
  now: Date = new Date()
): Promise<EvaluationAdmission> {
  const type = event.type as PlanningEventType;
  if (CRITICAL_EVENTS.has(type)) return { allowed: true, critical: true };

  const prisma = getPrismaClient();
  if (type === "manualRebuild" || type === "planReviewRequested") {
    const cooldownMinutes = positiveInteger(
      process.env.PLANNING_MANUAL_COOLDOWN_MINUTES,
      DEFAULT_MANUAL_COOLDOWN_MINUTES
    );
    const since = addMinutes(now, -cooldownMinutes);
    const prior = await prisma.planningEvent.findFirst({
      where: {
        userId: event.userId,
        type: { in: ["manualRebuild", "planReviewRequested"] },
        status: { in: ["completed", "ignored"] },
        processedAt: { gte: since },
        id: { not: event.id },
      },
      orderBy: { processedAt: "desc" },
    });
    if (prior?.processedAt) {
      return {
        allowed: false,
        reason: "manual_cooldown",
        retryAt: addMinutes(prior.processedAt, cooldownMinutes),
      };
    }
    return { allowed: true, critical: false };
  }

  const dailyLimit = positiveInteger(
    process.env.PLANNING_NORMAL_EVALUATIONS_PER_DAY,
    DEFAULT_NORMAL_DAILY_LIMIT
  );
  const dayStart = startOfUtcDay(now);
  const processed = await prisma.planningEvent.count({
    where: {
      userId: event.userId,
      status: { in: ["completed", "ignored"] },
      processedAt: { gte: dayStart },
      type: { notIn: [...CRITICAL_EVENTS] },
    },
  });
  if (processed < dailyLimit) return { allowed: true, critical: false };

  return {
    allowed: false,
    reason: "daily_limit",
    retryAt: addMinutes(addDays(dayStart, 1), stableJitterMinutes(event.userId)),
  };
}

export function isCriticalPlanningEvent(type: PlanningEventType): boolean {
  return CRITICAL_EVENTS.has(type);
}

function positiveInteger(value: string | undefined, fallback: number): number {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : fallback;
}

function stableJitterMinutes(value: string): number {
  let hash = 0;
  for (const character of value) hash = (hash * 31 + character.charCodeAt(0)) >>> 0;
  return hash % 60;
}

function startOfUtcDay(date: Date): Date {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
}

function addMinutes(date: Date, minutes: number): Date {
  return new Date(date.getTime() + minutes * 60_000);
}

function addDays(date: Date, days: number): Date {
  return new Date(date.getTime() + days * 86_400_000);
}
