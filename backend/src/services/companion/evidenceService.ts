import { Prisma, type PrismaClient } from "@prisma/client";

type EvidenceInput = {
  dedupeKey: string;
  type: string;
  source: string;
  subject: string;
  payload: unknown;
  confidence?: number;
  sensitivity?: string;
  consequenceLevel?: string;
  observedAt?: Date;
  expiresAt?: Date | null;
};

export async function appendRunnerEvidence(
  prisma: PrismaClient,
  userId: string,
  input: EvidenceInput
) {
  return prisma.runnerEvidence.upsert({
    where: { dedupeKey: input.dedupeKey },
    create: {
      userId,
      dedupeKey: input.dedupeKey,
      type: input.type,
      source: input.source,
      subject: input.subject,
      payload: input.payload as Prisma.InputJsonValue,
      confidence: input.confidence ?? 1,
      sensitivity: input.sensitivity ?? "standard",
      consequenceLevel: input.consequenceLevel ?? "low",
      observedAt: input.observedAt ?? new Date(),
      expiresAt: input.expiresAt ?? null,
    },
    update: {},
  });
}

export function confidenceLabel(value: number): "low" | "medium" | "high" {
  if (value >= 0.8) return "high";
  if (value >= 0.55) return "medium";
  return "low";
}

