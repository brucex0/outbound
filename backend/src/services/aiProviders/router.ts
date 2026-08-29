import { AIProviderError } from "./errors.js";
import { isRouteHealthy } from "./health.js";
import { scoreEligibleRoute } from "./routePolicy.js";
import type { AIRouteFacts, LiveCoachAIProvider, ResolvedAIRoute } from "./types.js";

export function resolveAIRoute(
  providers: LiveCoachAIProvider[],
  facts: AIRouteFacts,
  routePolicyVersion: string
): { provider: LiveCoachAIProvider; route: ResolvedAIRoute } {
  const eligible = providers.flatMap((provider) => {
    const capabilities = provider.capabilities();
    if (!isRouteHealthy(provider.key, provider.endpointKey)) return [];
    if (!capabilities.supportedMarkets.includes(facts.market)) return [];
    if (!capabilities.supportedLocales.includes(facts.locale)) return [];
    if (facts.requiredCapabilities.includes("audio_output") && !capabilities.audioOutput) return [];
    if (facts.requiredCapabilities.includes("combined_text_audio") && !capabilities.combinedTextAndAudio) return [];
    const providerVoice = provider.resolveVoice(facts.voiceProfileId, facts.locale);
    if (!providerVoice) return [];
    return [{ provider, providerVoice, score: scoreEligibleRoute(provider, facts) }];
  }).sort((left, right) => right.score - left.score || left.provider.key.localeCompare(right.provider.key));

  const selected = eligible[0];
  if (!selected) throw new AIProviderError("not_eligible", "No AI route satisfies the live-coach request.");
  return {
    provider: selected.provider,
    route: {
      providerKey: selected.provider.key,
      providerEndpointKey: selected.provider.endpointKey,
      providerModel: selected.provider.model,
      providerVoice: selected.providerVoice,
      routePolicyVersion,
    },
  };
}
