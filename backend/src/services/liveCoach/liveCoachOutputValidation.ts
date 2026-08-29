import { AIProviderError } from "../aiProviders/errors.js";

const prohibitedPatterns = [
  /ignore (the|your) (pain|injury|symptoms)/i,
  /diagnos/i,
  /guarantee/i,
  /medical advice/i,
];

export function validateLiveCoachOutput(transcript: string): string {
  const normalized = transcript.trim().replace(/\s+/g, " ");
  if (!normalized || normalized.length > 240 || prohibitedPatterns.some((pattern) => pattern.test(normalized))) {
    throw new AIProviderError("invalid_provider_output", "Generated coaching output failed product validation.");
  }
  return normalized;
}
