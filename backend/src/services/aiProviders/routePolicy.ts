import type { AIRouteFacts, LiveCoachAIProvider } from "./types.js";

export function scoreEligibleRoute(provider: LiveCoachAIProvider, facts: AIRouteFacts): number {
  let score = 0;
  if (facts.latencyClass === "interactive") score += 20;
  if (provider.key === "alibaba") score += 10;
  if (provider.endpointKey.includes(facts.deploymentRegion)) score += 5;
  return score;
}
