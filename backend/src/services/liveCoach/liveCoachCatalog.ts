import type { CoachPersonaId, SupportedAILocale, VoiceProfileId } from "../aiProviders/types.js";
import type { LiveCoachFeatureConfig } from "./liveCoachFeatureConfig.js";

export type CoachPersonaDefinition = {
  id: CoachPersonaId;
  instructionVersion: number;
  instructions: string;
  defaultVoiceProfileId: VoiceProfileId;
  allowedVoiceProfileIds: VoiceProfileId[];
  fixedScriptStyleId: "standard" | "calm";
  localized: Record<SupportedAILocale, { displayName: string; description: string }>;
};

export type VoiceProfileDefinition = {
  id: VoiceProfileId;
  style: "warm" | "clear";
  supportedLocales: SupportedAILocale[];
  localized: Record<SupportedAILocale, { displayName: string; description: string }>;
};

export const COACH_PERSONAS: CoachPersonaDefinition[] = [
  {
    id: "plainstride_supportive_v1",
    instructionVersion: 1,
    instructions: "Sound encouraging, practical, and grounded. Acknowledge the moment, give one sustainable adjustment, and avoid hype or judgment.",
    defaultVoiceProfileId: "plainstride_warm_1",
    allowedVoiceProfileIds: ["plainstride_warm_1", "plainstride_clear_1"],
    fixedScriptStyleId: "standard",
    localized: {
      en: { displayName: "Supportive", description: "Encouraging, practical coaching that keeps effort sustainable." },
      es: { displayName: "Cercano", description: "Orientación práctica y alentadora para mantener un esfuerzo sostenible." },
      "zh-Hans": { displayName: "陪伴型", description: "用鼓励而实用的方式，帮助你保持可持续的强度。" },
    },
  },
  {
    id: "plainstride_focused_v1",
    instructionVersion: 1,
    instructions: "Sound direct, calm, and precise. Use one relevant metric when available, then state one clear action without criticism or pressure.",
    defaultVoiceProfileId: "plainstride_clear_1",
    allowedVoiceProfileIds: ["plainstride_clear_1", "plainstride_warm_1"],
    fixedScriptStyleId: "standard",
    localized: {
      en: { displayName: "Focused", description: "Clear, concise coaching with one useful action at a time." },
      es: { displayName: "Enfocado", description: "Indicaciones claras y breves, con una acción útil cada vez." },
      "zh-Hans": { displayName: "专注型", description: "提示清晰简洁，每次只给一个有用的行动建议。" },
    },
  },
  {
    id: "plainstride_calm_v1",
    instructionVersion: 1,
    instructions: "Sound quiet, reassuring, and unhurried. Favor breathing, relaxation, and composure. Never add urgency unless the product marks a caution.",
    defaultVoiceProfileId: "plainstride_warm_1",
    allowedVoiceProfileIds: ["plainstride_warm_1"],
    fixedScriptStyleId: "calm",
    localized: {
      en: { displayName: "Calm", description: "Low-key guidance centered on breathing, rhythm, and composure." },
      es: { displayName: "Sereno", description: "Acompañamiento suave centrado en la respiración, el ritmo y la calma." },
      "zh-Hans": { displayName: "沉静型", description: "低干扰地关注呼吸、节奏与从容感。" },
    },
  },
];

export const VOICE_PROFILES: VoiceProfileDefinition[] = [
  {
    id: "plainstride_warm_1",
    style: "warm",
    supportedLocales: ["en", "es", "zh-Hans"],
    localized: {
      en: { displayName: "Warm", description: "Relaxed, natural, and reassuring." },
      es: { displayName: "Cálida", description: "Relajada, natural y tranquilizadora." },
      "zh-Hans": { displayName: "温暖", description: "自然放松，令人安心。" },
    },
  },
  {
    id: "plainstride_clear_1",
    style: "clear",
    supportedLocales: ["en", "es", "zh-Hans"],
    localized: {
      en: { displayName: "Clear", description: "Crisp, steady, and easy to follow while moving." },
      es: { displayName: "Clara", description: "Nítida, estable y fácil de seguir en movimiento." },
      "zh-Hans": { displayName: "清晰", description: "清楚稳定，运动中也容易听懂。" },
    },
  },
];

export function findCoachPersona(id: string): CoachPersonaDefinition | null {
  return COACH_PERSONAS.find((persona) => persona.id === id) ?? null;
}

export function findVoiceProfile(id: string): VoiceProfileDefinition | null {
  return VOICE_PROFILES.find((voice) => voice.id === id) ?? null;
}

export function publicLiveCoachCatalog(config: LiveCoachFeatureConfig, locale: SupportedAILocale) {
  const voices = VOICE_PROFILES.filter((voice) =>
    config.enabledVoiceProfileIds.includes(voice.id) && voice.supportedLocales.includes(locale)
  );
  const voiceIds = new Set(voices.map((voice) => voice.id));
  const personas = COACH_PERSONAS.filter((persona) => config.enabledPersonaIds.includes(persona.id))
    .map((persona) => ({ ...persona, allowed: persona.allowedVoiceProfileIds.filter((id) => voiceIds.has(id)) }))
    .filter((persona) => persona.allowed.length > 0 && persona.allowed.includes(persona.defaultVoiceProfileId));
  return {
    contractVersion: 1,
    catalogVersion: config.catalogVersion,
    audioPack: config.audioManifestUrl ? {
      manifestVersion: config.catalogVersion,
      manifestUrl: config.audioManifestUrl,
    } : undefined,
    coachPersonas: personas.map((persona) => ({
      id: persona.id,
      displayName: persona.localized[locale].displayName,
      description: persona.localized[locale].description,
      defaultVoiceProfileId: persona.defaultVoiceProfileId,
      allowedVoiceProfileIds: persona.allowed,
      fixedScriptStyleId: persona.fixedScriptStyleId,
      access: "included" as const,
    })),
    voices: voices.map((voice) => ({
      id: voice.id,
      displayName: voice.localized[locale].displayName,
      description: voice.localized[locale].description,
      style: voice.style,
      previewAssetId: "voice.preview",
    })),
  };
}
