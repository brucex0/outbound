import { Prisma, type PrismaClient } from "@prisma/client";
import type { SituationalSignalInput } from "./contracts.js";

export async function ingestSituationalSignals(
  prisma: PrismaClient,
  userId: string,
  inputs: SituationalSignalInput[]
) {
  const accepted = [];
  for (const input of inputs) {
    const freshUntil = new Date(input.freshUntil);
    if (freshUntil <= new Date(input.observedAt)) continue;
    accepted.push(await prisma.situationalSignal.upsert({
      where: { idempotencyKey: input.idempotencyKey },
      create: {
        userId,
        idempotencyKey: input.idempotencyKey,
        type: input.type,
        value: sanitizeSignalValue(input.type, input.value) as Prisma.InputJsonValue,
        source: input.source,
        confidence: input.confidence,
        privacy: input.privacy,
        consequenceLevel: input.consequenceLevel,
        possibleEffects: input.possibleEffects,
        scope: sanitizeScope(input.scope) as Prisma.InputJsonValue,
        observedAt: new Date(input.observedAt),
        freshUntil,
      },
      update: {},
    }));
  }
  return accepted;
}

export async function getRelevantSituationalSignals(
  prisma: PrismaClient,
  userId: string,
  now = new Date()
) {
  const signals = await prisma.situationalSignal.findMany({
    where: { userId, freshUntil: { gt: now } },
    orderBy: [{ consequenceLevel: "desc" }, { observedAt: "desc" }],
    take: 24,
  });
  return signals.map((signal) => ({
    id: signal.id,
    type: signal.type,
    value: signal.value,
    confidence: signal.confidence,
    consequenceLevel: signal.consequenceLevel,
    possibleEffects: signal.possibleEffects,
    scope: signal.scope,
    freshUntil: signal.freshUntil.toISOString(),
  }));
}

function sanitizeScope(scope: Record<string, unknown>) {
  const { latitude: _latitude, longitude: _longitude, coordinates: _coordinates, ...safe } = scope;
  return safe;
}

function sanitizeSignalValue(type: string, value: unknown) {
  if (!type.startsWith("location.")) return value;
  if (!value || typeof value !== "object" || Array.isArray(value)) return value;
  const { latitude: _latitude, longitude: _longitude, coordinates: _coordinates, ...safe } = value as Record<string, unknown>;
  return safe;
}

