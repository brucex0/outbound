import { createHash } from "node:crypto";
import type { PrismaClient } from "@prisma/client";
import type { LiveCoachCompiledContext } from "../aiProviders/types.js";
import { AIProviderError } from "../aiProviders/errors.js";
import { buildSessionBrief } from "../companion/sessionBrief.js";
import type { CompiledLiveCoachSessionContext } from "./liveCoachTypes.js";

const maximumEstimatedTokens = 1_250;

export async function compileLiveCoachContext(
  prisma: PrismaClient,
  userId: string,
  workoutId?: string
): Promise<CompiledLiveCoachSessionContext> {
  const brief = await buildSessionBrief(prisma, userId, workoutId);
  if (workoutId && !brief.workout) {
    throw new AIProviderError("not_eligible", "The selected workout is unavailable for this runner.");
  }
  const context: LiveCoachCompiledContext = {
    version: 1,
    runnerModelVersion: brief.runnerModelVersion,
    workout: brief.workout ? {
      title: clip(brief.workout.title, 80),
      purpose: clip(brief.workout.purpose, 120),
      durationSeconds: brief.workout.durationSeconds,
      intensityTarget: brief.workout.intensityTarget,
      prescription: brief.workout.prescription,
    } : null,
    readiness: brief.readiness ? {
      choice: clip(brief.readiness.choice, 24),
      energy: finiteNumber(brief.readiness.energy),
      soreness: finiteNumber(brief.readiness.soreness),
    } : null,
    guidancePriorities: brief.guidancePriorities.slice(0, 3).map((value) => clip(value, 120)),
    cuePreferences: brief.cuePreferences.slice(0, 3).map((value) => clip(value, 100)),
    safetyRequiresFixedOnly: brief.readiness?.illnessOrPain === true,
  };
  const serialized = stableStringify(context);
  const estimatedTokens = Math.ceil(serialized.length / 4);
  if (estimatedTokens > maximumEstimatedTokens) {
    throw new AIProviderError("budget_exhausted", "Live-coach context exceeds its privacy budget.");
  }
  return {
    context,
    serialized,
    contextHash: createHash("sha256").update(serialized).digest("hex"),
    estimatedTokens,
  };
}

function stableStringify(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.entries(value).sort(([left], [right]) => left.localeCompare(right))
      .map(([key, item]) => `${JSON.stringify(key)}:${stableStringify(item)}`).join(",")}}`;
  }
  return JSON.stringify(value);
}
function clip(value: string | null | undefined, length: number): string {
  return (value ?? "").trim().replace(/\s+/g, " ").slice(0, length);
}
function finiteNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}
