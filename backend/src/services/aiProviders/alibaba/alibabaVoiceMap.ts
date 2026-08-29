import type { AlibabaProviderConfig } from "../config.js";
import type { SupportedAILocale, VoiceProfileId } from "../types.js";

export function resolveAlibabaVoice(
  config: AlibabaProviderConfig,
  voiceProfileId: VoiceProfileId,
  locale: SupportedAILocale
): string | null {
  return config.voiceMap[voiceProfileId]?.[locale] ?? null;
}
