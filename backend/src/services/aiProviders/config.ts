import { AIProviderError } from "./errors.js";
import { VOICE_PROFILE_IDS, type SupportedAILocale, type VoiceProfileId } from "./types.js";
import {
  APPROVED_ALIBABA_DYNAMIC_LIVE_COACH_MODEL,
  APPROVED_ALIBABA_FIXED_AUDIO_MODEL,
  APPROVED_ALIBABA_LIVE_COACH_VOICE_MAP,
} from "./alibaba/approvedLiveCoachConfiguration.js";
import {
  APPROVED_GOOGLE_CLOUD_TTS_MODEL,
  APPROVED_GOOGLE_CLOUD_TTS_VOICE_MAP,
} from "./google/approvedLiveCoachConfiguration.js";

export type AlibabaProviderConfig = {
  enabled: boolean;
  apiKey: string;
  baseUrl: string;
  fixedAudioBaseUrl: string;
  endpointKey: string;
  deploymentRegion: string;
  model: string;
  fixedAudioModel: string;
  voiceMap: Record<VoiceProfileId, Partial<Record<SupportedAILocale, string>>>;
};

export type GoogleCloudTTSProviderConfig = {
  enabled: boolean;
  apiEndpoint: string;
  endpointKey: string;
  deploymentRegion: string;
  model: string;
  voiceMap: Record<VoiceProfileId, Partial<Record<SupportedAILocale, string>>>;
};

export type AIProviderConfiguration = {
  routePolicyVersion: string;
  googleCloudTTS: GoogleCloudTTSProviderConfig;
  alibaba: AlibabaProviderConfig;
};

export function loadAIProviderConfiguration(env: NodeJS.ProcessEnv = process.env): AIProviderConfiguration {
  const baseUrl = trimTrailingSlash(env.ALIBABA_AI_BASE_URL);
  return {
    routePolicyVersion: trimmed(env.AI_ROUTE_POLICY_VERSION) || "1",
    googleCloudTTS: {
      enabled: env.GOOGLE_CLOUD_TTS_ENABLED === "true",
      apiEndpoint: trimmed(env.GOOGLE_CLOUD_TTS_API_ENDPOINT) || "us-texttospeech.googleapis.com",
      endpointKey: trimmed(env.GOOGLE_CLOUD_TTS_ENDPOINT_KEY) || "google-cloud-tts-us",
      deploymentRegion: trimmed(env.GOOGLE_CLOUD_TTS_DEPLOYMENT_REGION) || "us",
      model: trimmed(env.GOOGLE_CLOUD_TTS_MODEL) || APPROVED_GOOGLE_CLOUD_TTS_MODEL,
      voiceMap: env.GOOGLE_CLOUD_TTS_VOICE_MAP?.trim()
        ? parseVoiceMap(env.GOOGLE_CLOUD_TTS_VOICE_MAP, "GOOGLE_CLOUD_TTS_VOICE_MAP")
        : APPROVED_GOOGLE_CLOUD_TTS_VOICE_MAP,
    },
    alibaba: {
      enabled: env.ALIBABA_AI_ENABLED === "true",
      apiKey: trimmed(env.ALIBABA_AI_API_KEY),
      baseUrl,
      fixedAudioBaseUrl: trimTrailingSlash(env.ALIBABA_TTS_BASE_URL) || inferredTTSBaseUrl(baseUrl),
      endpointKey: trimmed(env.ALIBABA_AI_ENDPOINT_KEY) || "alibaba-global-primary",
      deploymentRegion: trimmed(env.ALIBABA_AI_DEPLOYMENT_REGION) || "ap-southeast-1",
      model: trimmed(env.ALIBABA_LIVE_COACH_MODEL) || APPROVED_ALIBABA_DYNAMIC_LIVE_COACH_MODEL,
      fixedAudioModel: trimmed(env.ALIBABA_FIXED_AUDIO_MODEL) || APPROVED_ALIBABA_FIXED_AUDIO_MODEL,
      voiceMap: env.ALIBABA_LIVE_COACH_VOICE_MAP?.trim()
        ? parseVoiceMap(env.ALIBABA_LIVE_COACH_VOICE_MAP, "ALIBABA_LIVE_COACH_VOICE_MAP")
        : APPROVED_ALIBABA_LIVE_COACH_VOICE_MAP,
    },
  };
}

export function assertAIProviderConfiguration(config: AIProviderConfiguration): void {
  if (config.googleCloudTTS.enabled) {
    if (!config.googleCloudTTS.apiEndpoint || !config.googleCloudTTS.model) {
      throw new AIProviderError("not_configured", "Google Cloud TTS endpoint and model are required when it is enabled.");
    }
    if (!/^[a-z0-9.-]+\.googleapis\.com$/i.test(config.googleCloudTTS.apiEndpoint)) {
      throw new AIProviderError("not_configured", "GOOGLE_CLOUD_TTS_API_ENDPOINT must be a googleapis.com host name.");
    }
    if (Object.keys(config.googleCloudTTS.voiceMap).length === 0) {
      throw new AIProviderError("not_configured", "GOOGLE_CLOUD_TTS_VOICE_MAP is required when Google Cloud TTS is enabled.");
    }
  }
  if (config.alibaba.enabled) {
    const missing = [
      ["ALIBABA_AI_API_KEY", config.alibaba.apiKey],
      ["ALIBABA_AI_BASE_URL", config.alibaba.baseUrl],
      ["ALIBABA_TTS_BASE_URL", config.alibaba.fixedAudioBaseUrl],
      ["ALIBABA_LIVE_COACH_MODEL", config.alibaba.model],
      ["ALIBABA_FIXED_AUDIO_MODEL", config.alibaba.fixedAudioModel],
    ].filter(([, value]) => !value).map(([name]) => name);
    if (missing.length > 0) {
      throw new AIProviderError("not_configured", `Alibaba AI configuration is missing: ${missing.join(", ")}.`);
    }
    if (Object.keys(config.alibaba.voiceMap).length === 0) {
      throw new AIProviderError("not_configured", "ALIBABA_LIVE_COACH_VOICE_MAP is required when Alibaba AI is enabled.");
    }
    assertHTTPSURL(config.alibaba.baseUrl, "ALIBABA_AI_BASE_URL");
    assertHTTPSURL(config.alibaba.fixedAudioBaseUrl, "ALIBABA_TTS_BASE_URL");
  }
}

function assertHTTPSURL(value: string, name: string): void {
  try {
    if (new URL(value).protocol === "https:") return;
  } catch {
    // Use the configuration error below for malformed URLs too.
  }
  throw new AIProviderError("not_configured", `${name} must be a valid HTTPS URL.`);
}

function inferredTTSBaseUrl(baseUrl: string): string {
  if (!baseUrl) return "";
  try {
    const url = new URL(baseUrl);
    if (url.pathname.replace(/\/+$/, "") !== "/compatible-mode/v1") return "";
    url.pathname = "/api/v1";
    return url.toString().replace(/\/+$/, "");
  } catch {
    return "";
  }
}

function parseVoiceMap(
  value: string | undefined,
  environmentName: string
): Record<VoiceProfileId, Partial<Record<SupportedAILocale, string>>> {
  if (!value?.trim()) return {} as Record<VoiceProfileId, Partial<Record<SupportedAILocale, string>>>;
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
    return result as Record<VoiceProfileId, Partial<Record<SupportedAILocale, string>>>;
  } catch {
    throw new AIProviderError("not_configured", `${environmentName} must be valid provider voice JSON.`);
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
function trimmed(value: string | undefined): string { return value?.trim() ?? ""; }
function trimTrailingSlash(value: string | undefined): string { return trimmed(value).replace(/\/+$/, ""); }
