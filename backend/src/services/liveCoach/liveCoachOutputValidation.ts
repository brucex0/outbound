import { AIProviderError } from "../aiProviders/errors.js";

const prohibitedPatterns = [
  /ignore (the|your) (pain|injury|symptoms)/i,
  /diagnos/i,
  /guarantee/i,
  /medical advice/i,
  /(?:reset|rebuild|restore|find|bring back).{0,25}(?:posture|rhythm)/i,
  /(?:pace.{0,15}(?:sharply|sharp change)|sharp pace change)/i,
  /(?:调整.{0,3}跑姿|找回节奏|带回.{0,3}节奏)/,
  /(?:recoloca|corrige).{0,15}postura|recupera.{0,15}ritmo/i,
];

export function validateLiveCoachOutput(transcript: string): string {
  const normalized = transcript.trim().replace(/\s+/g, " ");
  if (!normalized || normalized.length > 240 || prohibitedPatterns.some((pattern) => pattern.test(normalized))) {
    throw new AIProviderError("invalid_provider_output", "Generated coaching output failed product validation.");
  }
  return normalized;
}
