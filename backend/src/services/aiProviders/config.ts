import { AIProviderError } from "./errors.js";
import { VOICE_PROFILE_IDS, type SupportedAILocale, type VoiceProfileId } from "./types.js";
import {
  APPROVED_ALIBABA_LIVE_COACH_MODEL,
  APPROVED_ALIBABA_LIVE_COACH_VOICE_MAP,
} from "./alibaba/approvedLiveCoachConfiguration.js";

export type AlibabaProviderConfig = {
  enabled: boolean;
  apiKey: string;
  baseUrl: string;
  endpointKey: string;
  deploymentRegion: string;
  model: string;
  voiceMap: Record<VoiceProfileId, Partial<Record<SupportedAILocale, string>>>;
};

export type AIProviderConfiguration = {
  routePolicyVersion: string;
  alibaba: AlibabaProviderConfig;
};

export function loadAIProviderConfiguration(env: NodeJS.ProcessEnv = process.env): AIProviderConfiguration {
  return {
    routePolicyVersion: trimmed(env.AI_ROUTE_POLICY_VERSION) || "1",
    alibaba: {
      enabled: env.ALIBABA_AI_ENABLED === "true",
      apiKey: trimmed(env.ALIBABA_AI_API_KEY),
      baseUrl: trimTrailingSlash(env.ALIBABA_AI_BASE_URL),
      endpointKey: trimmed(env.ALIBABA_AI_ENDPOINT_KEY) || "alibaba-global-primary",
      deploymentRegion: trimmed(env.ALIBABA_AI_DEPLOYMENT_REGION) || "ap-southeast-1",
      model: trimmed(env.ALIBABA_LIVE_COACH_MODEL) || APPROVED_ALIBABA_LIVE_COACH_MODEL,
      voiceMap: env.ALIBABA_LIVE_COACH_VOICE_MAP?.trim()
        ? parseVoiceMap(env.ALIBABA_LIVE_COACH_VOICE_MAP)
        : APPROVED_ALIBABA_LIVE_COACH_VOICE_MAP,
    },
  };
}

export function assertAIProviderConfiguration(config: AIProviderConfiguration): void {
  if (!config.alibaba.enabled) return;
  const missing = [
    ["ALIBABA_AI_API_KEY", config.alibaba.apiKey],
    ["ALIBABA_AI_BASE_URL", config.alibaba.baseUrl],
    ["ALIBABA_LIVE_COACH_MODEL", config.alibaba.model],
  ].filter(([, value]) => !value).map(([name]) => name);
  if (missing.length > 0) {
    throw new AIProviderError("not_configured", `Alibaba AI configuration is missing: ${missing.join(", ")}.`);
  }
  if (Object.keys(config.alibaba.voiceMap).length === 0) {
    throw new AIProviderError("not_configured", "ALIBABA_LIVE_COACH_VOICE_MAP is required when Alibaba AI is enabled.");
  }
  let url: URL;
  try {
    url = new URL(config.alibaba.baseUrl);
  } catch {
    throw new AIProviderError("not_configured", "ALIBABA_AI_BASE_URL must be a valid HTTPS URL.");
  }
  if (url.protocol !== "https:") {
    throw new AIProviderError("not_configured", "ALIBABA_AI_BASE_URL must use HTTPS.");
  }
}

function parseVoiceMap(value: string | undefined): AlibabaProviderConfig["voiceMap"] {
  if (!value?.trim()) return {} as AlibabaProviderConfig["voiceMap"];
  try {
    const parsed = JSON.parse(value) as unknown;
    if (!isRecord(parsed)) throw new Error("not an object");
    const result: Record<string, Partial<Record<SupportedAILocale, string>>> = {};
    for (const [profileId, localeMap] of Object.entries(parsed)) {
      if (!VOICE_PROFILE_IDS.some((knownId) => knownId === profileId)) {
        throw new Error("unknown voice profile");
      }
      if (!isRecord(localeMap)) throw new Error("voice profile mapping is not an object");
      const normalized: Partial<Record<SupportedAILocale, string>> = {};
      for (const locale of ["en", "es", "zh-Hans"] as const) {
        const voice = localeMap[locale];
        if (typeof voice === "string" && voice.trim()) normalized[locale] = voice.trim();
      }
      if (Object.keys(normalized).length > 0) result[profileId] = normalized;
    }
    return result as AlibabaProviderConfig["voiceMap"];
  } catch {
    throw new AIProviderError("not_configured", "ALIBABA_LIVE_COACH_VOICE_MAP must be valid provider voice JSON.");
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
function trimmed(value: string | undefined): string { return value?.trim() ?? ""; }
function trimTrailingSlash(value: string | undefined): string { return trimmed(value).replace(/\/+$/, ""); }
