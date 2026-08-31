import { createHash } from "node:crypto";
import { AIProviderError } from "../aiProviders/errors.js";
import { assertAIProviderConfiguration, loadAIProviderConfiguration } from "../aiProviders/config.js";
import { SUPPORTED_AI_LOCALES, VOICE_PROFILE_IDS, type CoachPersonaId, type SupportedAILocale, type VoiceProfileId } from "../aiProviders/types.js";

export const LIVE_COACH_MODES = ["disabled", "fixed_only", "dynamic"] as const;
export type LiveCoachMode = (typeof LIVE_COACH_MODES)[number];
export type LiveCoachAccessMode = "open_beta" | "founding_trial" | "subscription_required";

export type LiveCoachFeatureConfig = {
  mode: LiveCoachMode;
  accessMode: LiveCoachAccessMode;
  configVersion: string;
  catalogVersion: string;
  allowedMarkets: ["global"];
  enabledLocales: SupportedAILocale[];
  enabledPersonaIds: CoachPersonaId[];
  enabledVoiceProfileIds: VoiceProfileId[];
  dynamicRolloutPercent: number;
  foundingUserLimit: number;
  trialRunLimit: number;
  dynamicCueLimitResponsive: number;
  dynamicCueLimitCoachMe: number;
  cueValidityMilliseconds: number;
  providerDeadlineMilliseconds: number;
  audioManifestUrl: string;
  audioAssetBaseUrl: string;
  deploymentRegion: string;
  planner: {
    enabled: boolean;
    model: string;
    projectId: string;
    location: string;
    apiKey: string;
    deadlineMilliseconds: number;
  };
};

const knownPersonaIds: CoachPersonaId[] = [
  "plainstride_supportive_v1",
  "plainstride_focused_v1",
  "plainstride_calm_v1",
];
const knownVoiceProfileIds: readonly VoiceProfileId[] = VOICE_PROFILE_IDS;

export function loadLiveCoachFeatureConfig(env: NodeJS.ProcessEnv = process.env): LiveCoachFeatureConfig {
  const mode = enumValue(env.LIVE_COACH_SERVER_AUDIO_MODE, LIVE_COACH_MODES, "disabled");
  const accessMode = enumValue(
    env.LIVE_COACH_ACCESS_MODE,
    ["open_beta", "founding_trial", "subscription_required"] as const,
    "open_beta"
  );
  return {
    mode,
    accessMode,
    configVersion: trimmed(env.LIVE_COACH_CONFIG_VERSION) || "1",
    catalogVersion: trimmed(env.LIVE_COACH_CATALOG_VERSION) || "2026-08-30.1",
    allowedMarkets: ["global"],
    enabledLocales: csv(env.LIVE_COACH_ENABLED_LOCALES, [...SUPPORTED_AI_LOCALES]) as SupportedAILocale[],
    enabledPersonaIds: csv(env.LIVE_COACH_ENABLED_PERSONAS, [
      "plainstride_supportive_v1",
      "plainstride_focused_v1",
    ]) as CoachPersonaId[],
    enabledVoiceProfileIds: csv(env.LIVE_COACH_ENABLED_VOICE_PROFILES, [
      "plainstride_warm_1",
      "plainstride_clear_1",
    ]) as VoiceProfileId[],
    dynamicRolloutPercent: boundedInteger(env.LIVE_COACH_DYNAMIC_ROLLOUT_PERCENT, 0, 0, 100),
    foundingUserLimit: boundedInteger(env.LIVE_COACH_FOUNDING_USER_LIMIT, 1_000, 1, 1_000_000),
    trialRunLimit: boundedInteger(env.LIVE_COACH_TRIAL_RUN_LIMIT, 3, 1, 100),
    dynamicCueLimitResponsive: boundedInteger(env.LIVE_COACH_DYNAMIC_CUE_LIMIT_RESPONSIVE, 8, 0, 30),
    dynamicCueLimitCoachMe: boundedInteger(env.LIVE_COACH_DYNAMIC_CUE_LIMIT_COACH_ME, 15, 0, 30),
    cueValidityMilliseconds: boundedInteger(env.LIVE_COACH_CUE_VALIDITY_MILLISECONDS, 5_000, 1_000, 10_000),
    providerDeadlineMilliseconds: boundedInteger(env.LIVE_COACH_PROVIDER_DEADLINE_MILLISECONDS, 1_500, 500, 10_000),
    audioManifestUrl: trimmed(env.LIVE_COACH_AUDIO_MANIFEST_URL),
    audioAssetBaseUrl: trimmed(env.LIVE_COACH_AUDIO_ASSET_BASE_URL).replace(/\/+$/, ""),
    deploymentRegion: trimmed(env.PLAINSTRIDE_DEPLOYMENT_REGION) || "us-central1",
    planner: {
      enabled: env.LIVE_COACH_PLANNER_ENABLED === "true",
      model: trimmed(env.GEMINI_LIVE_COACH_PLANNER_MODEL) || "gemini-3.1-pro-preview",
      projectId: trimmed(env.GEMINI_VERTEX_PROJECT_ID)
        || trimmed(env.GOOGLE_CLOUD_PROJECT)
        || trimmed(env.GCLOUD_PROJECT),
      location: trimmed(env.GEMINI_VERTEX_LOCATION) || "global",
      apiKey: trimmed(env.GEMINI_API_KEY),
      deadlineMilliseconds: boundedInteger(env.GEMINI_LIVE_COACH_PLANNER_DEADLINE_MILLISECONDS, 20_000, 2_000, 60_000),
    },
  };
}

export function assertLiveCoachConfiguration(env: NodeJS.ProcessEnv = process.env): void {
  const feature = loadLiveCoachFeatureConfig(env);
  if (feature.mode === "disabled") return;
  if (!feature.audioManifestUrl || !feature.audioAssetBaseUrl) {
    throw new AIProviderError(
      "not_configured",
      "LIVE_COACH_AUDIO_MANIFEST_URL and LIVE_COACH_AUDIO_ASSET_BASE_URL are required for server audio."
    );
  }
  if (env.LIVE_COACH_AUDIO_PACK_PUBLISHED !== "true") {
    throw new AIProviderError("not_configured", "Server audio cannot be enabled before the fixed pack is reviewed and published.");
  }
  for (const value of [feature.audioManifestUrl, feature.audioAssetBaseUrl]) {
    let url: URL;
    try {
      url = new URL(value);
    } catch {
      throw new AIProviderError("not_configured", "Live-coach audio URLs must be valid HTTPS URLs.");
    }
    if (url.protocol !== "https:") {
      throw new AIProviderError("not_configured", "Live-coach audio URLs must use HTTPS.");
    }
  }
  if (feature.enabledPersonaIds.length === 0 || feature.enabledVoiceProfileIds.length === 0) {
    throw new AIProviderError("not_configured", "At least one live-coach persona and voice profile must be enabled.");
  }
  if (feature.enabledLocales.length === 0
      || feature.enabledLocales.some((locale) => !SUPPORTED_AI_LOCALES.includes(locale))) {
    throw new AIProviderError("not_configured", "LIVE_COACH_ENABLED_LOCALES contains an unsupported locale.");
  }
  if (feature.enabledPersonaIds.some((id) => !knownPersonaIds.includes(id))
      || feature.enabledVoiceProfileIds.some((id) => !knownVoiceProfileIds.includes(id))) {
    throw new AIProviderError("not_configured", "Live-coach configuration contains an unknown persona or voice profile ID.");
  }
  if (feature.accessMode === "subscription_required" && env.LIVE_COACH_PAID_MODE_READY !== "true") {
    throw new AIProviderError("not_configured", "Subscription-required live coaching cannot start before paid mode is ready.");
  }
  if (feature.mode === "dynamic") {
    const providers = loadAIProviderConfiguration(env);
    assertAIProviderConfiguration(providers);
    if (!providers.googleCloudTTS.enabled && !providers.alibaba.enabled) {
      throw new AIProviderError("not_configured", "Dynamic live coaching requires at least one enabled AI provider.");
    }
    for (const voiceProfileId of feature.enabledVoiceProfileIds) {
      for (const locale of feature.enabledLocales) {
        const googleConfigured = providers.googleCloudTTS.enabled
          && Boolean(providers.googleCloudTTS.voiceMap[voiceProfileId]?.[locale]);
        const alibabaConfigured = providers.alibaba.enabled
          && Boolean(providers.alibaba.voiceMap[voiceProfileId]?.[locale]);
        if (!googleConfigured && !alibabaConfigured) {
          throw new AIProviderError(
            "not_configured",
            `No enabled provider has a voice mapping for ${voiceProfileId}/${locale}.`
          );
        }
      }
    }
    if (feature.planner.enabled && !feature.planner.apiKey && !feature.planner.projectId) {
      throw new AIProviderError(
        "not_configured",
        "Gemini live-coach planning requires GEMINI_API_KEY or GEMINI_VERTEX_PROJECT_ID/GOOGLE_CLOUD_PROJECT."
      );
    }
  }
}

export function isLiveCoachLocaleEnabled(config: LiveCoachFeatureConfig, locale: SupportedAILocale): boolean {
  return config.enabledLocales.includes(locale);
}

export function effectiveModeForUser(config: LiveCoachFeatureConfig, userId: string): LiveCoachMode {
  if (config.mode !== "dynamic") return config.mode;
  const bucket = createHash("sha256")
    .update(`${userId}:${config.configVersion}`)
    .digest()
    .readUInt32BE(0) % 100;
  return bucket < config.dynamicRolloutPercent ? "dynamic" : "fixed_only";
}

function enumValue<const T extends readonly string[]>(value: string | undefined, values: T, fallback: T[number]): T[number] {
  if (!value?.trim()) return fallback;
  const normalized = value.trim();
  if (values.includes(normalized as T[number])) return normalized as T[number];
  throw new AIProviderError("not_configured", `Unsupported live-coach configuration value: ${normalized}.`);
}
function csv(value: string | undefined, fallback: string[]): string[] {
  return (value?.trim() ? value.split(",") : fallback).map((item) => item.trim()).filter(Boolean);
}
function boundedInteger(value: string | undefined, fallback: number, minimum: number, maximum: number): number {
  if (!value?.trim()) return fallback;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < minimum || parsed > maximum) {
    throw new AIProviderError("not_configured", `Live-coach numeric configuration must be ${minimum}...${maximum}.`);
  }
  return parsed;
}
function trimmed(value: string | undefined): string { return value?.trim() ?? ""; }
