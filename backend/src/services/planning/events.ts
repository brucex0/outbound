import { Prisma, type PlanningEvent } from "@prisma/client";
import { getPrismaClient } from "../prisma.js";
import type { PlanningEventResult, PlanningEventType } from "./types.js";

type PrismaWriter = Prisma.TransactionClient | ReturnType<typeof getPrismaClient>;

export interface EnqueuePlanningEventInput {
  userId: string;
  planId?: string | null;
  type: PlanningEventType;
  sourceId?: string | null;
  payload?: Record<string, unknown>;
  priority?: number;
  dedupeKey?: string | null;
  runAfter?: Date;
}

export async function enqueuePlanningEvent(
  input: EnqueuePlanningEventInput,
  client: PrismaWriter = getPrismaClient()
): Promise<PlanningEvent> {
  if (input.dedupeKey) {
    const existing = await client.planningEvent.findFirst({
      where: {
        dedupeKey: input.dedupeKey,
        status: { in: ["pending", "processing"] },
      },
      orderBy: { createdAt: "desc" },
    });

    if (existing) {
      return client.planningEvent.update({
        where: { id: existing.id },
        data: {
          runAfter: input.runAfter ?? existing.runAfter,
          priority: Math.max(existing.priority, input.priority ?? existing.priority),
          payload: json(input.payload ?? {}),
        },
      });
    }
  }

  return client.planningEvent.create({
    data: {
      userId: input.userId,
      planId: input.planId ?? null,
      type: input.type,
      sourceId: input.sourceId ?? null,
      payload: json(input.payload ?? {}),
      priority: input.priority ?? 0,
      dedupeKey: input.dedupeKey ?? null,
      runAfter: input.runAfter ?? new Date(),
    },
  });
}

export async function claimDuePlanningEvents(params: {
  userId?: string;
  limit?: number;
  now?: Date;
} = {}): Promise<PlanningEvent[]> {
  const prisma = getPrismaClient();
  const events = await prisma.planningEvent.findMany({
    where: {
      status: "pending",
      runAfter: { lte: params.now ?? new Date() },
      ...(params.userId ? { userId: params.userId } : {}),
    },
    orderBy: [{ priority: "desc" }, { createdAt: "asc" }],
    take: params.limit ?? 10,
  });

  const claimed: PlanningEvent[] = [];
  for (const event of events) {
    try {
      claimed.push(
        await prisma.planningEvent.update({
          where: { id: event.id },
          data: {
            status: "processing",
            attemptCount: { increment: 1 },
          },
        })
      );
    } catch {
      // Another worker may have claimed it first once workers exist.
    }
  }
  return claimed;
}

export async function completePlanningEvent(eventId: string, result: PlanningEventResult) {
  await getPrismaClient().planningEvent.update({
    where: { id: eventId },
    data: {
      status: result.status === "ignored" ? "ignored" : "completed",
      processedAt: new Date(),
      lastError: null,
    },
  });
}

export async function failPlanningEvent(eventId: string, error: Error) {
  await getPrismaClient().planningEvent.update({
    where: { id: eventId },
    data: {
      status: "failed",
      processedAt: new Date(),
      lastError: error.message.slice(0, 1000),
    },
  });
}

function json(value: Record<string, unknown>): Prisma.InputJsonValue {
  return value as Prisma.InputJsonValue;
}
