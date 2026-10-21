import { AIProviderError } from "../aiProviders/errors.js";

// Keep the existing rejection patterns; only closed reason labels may leave this module.
const prohibitedPatterns = [
  { reason: "unsafe_pain", pattern: /ignore (the|your) (pain|injury|symptoms)/i },
  { reason: "medical", pattern: /diagnos/i },
  { reason: "guarantee", pattern: /guarantee/i },
  { reason: "medical", pattern: /medical advice/i },
  { reason: "vague_form", pattern: /(?:reset|rebuild|restore|find|bring back).{0,25}(?:posture|rhythm)/i },
  { reason: "abrupt_pace", pattern: /(?:pace.{0,15}(?:sharply|sharp change)|sharp pace change)/i },
  { reason: "vague_form", pattern: /(?:调整.{0,3}跑姿|找回节奏|带回.{0,3}节奏)/ },
  { reason: "vague_form", pattern: /(?:recoloca|corrige).{0,15}postura|recupera.{0,15}ritmo/i },
] as const;

export function validateLiveCoachOutput(transcript: string): string {
  const normalized = transcript.trim().replace(/\s+/g, " ");
  const reason = !normalized || normalized.length > 240 ? "phrase_bounds"
    : prohibitedPatterns.find(({ pattern }) => pattern.test(normalized))?.reason;
  if (reason) {
    throw new AIProviderError("invalid_provider_output", `Generated coaching output failed product validation (${reason}).`);
  }
  return normalized;
}
