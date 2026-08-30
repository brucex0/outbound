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
  style: "warm" | "gentle" | "composed" | "bright" | "driven" | "easygoing";
  presentation: "female" | "male";
  supportedLocales: SupportedAILocale[];
  localized: Record<SupportedAILocale, { displayName: string; description: string }>;
};

export const COACH_PERSONAS: CoachPersonaDefinition[] = [
  {
    id: "plainstride_supportive_v1",
    instructionVersion: 1,
    instructions: "Sound encouraging, practical, and grounded. Acknowledge the moment, give one sustainable adjustment, and avoid hype or judgment.",
    defaultVoiceProfileId: "plainstride_warm_1",
    allowedVoiceProfileIds: [
      "plainstride_warm_1",
      "plainstride_gentle_1",
      "plainstride_composed_1",
      "plainstride_clear_1",
      "plainstride_driven_1",
      "plainstride_easygoing_1",
    ],
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
    allowedVoiceProfileIds: [
      "plainstride_clear_1",
      "plainstride_driven_1",
      "plainstride_composed_1",
      "plainstride_warm_1",
      "plainstride_gentle_1",
      "plainstride_easygoing_1",
    ],
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
    defaultVoiceProfileId: "plainstride_gentle_1",
    allowedVoiceProfileIds: [
      "plainstride_gentle_1",
      "plainstride_composed_1",
      "plainstride_easygoing_1",
      "plainstride_warm_1",
    ],
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
    presentation: "female",
    supportedLocales: ["en", "es", "zh-Hans"],
    localized: {
      en: { displayName: "Cherry", description: "Bright, friendly, and naturally encouraging." },
      es: { displayName: "Cherry", description: "Luminosa, cercana y alentadora con naturalidad." },
      "zh-Hans": { displayName: "Cherry", description: "明亮亲切，自然而有鼓励感。" },
    },
  },
  {
    id: "plainstride_gentle_1",
    style: "gentle",
    presentation: "female",
    supportedLocales: ["en", "es", "zh-Hans"],
    localized: {
      en: { displayName: "Serena", description: "Soft, calm, and reassuring." },
      es: { displayName: "Serena", description: "Suave, tranquila y reconfortante." },
      "zh-Hans": { displayName: "Serena", description: "轻柔平静，让人安心。" },
    },
  },
  {
    id: "plainstride_composed_1",
    style: "composed",
    presentation: "female",
    supportedLocales: ["en", "es", "zh-Hans"],
    localized: {
      en: { displayName: "Maia", description: "Thoughtful, balanced, and clear." },
      es: { displayName: "Maia", description: "Reflexiva, equilibrada y clara." },
      "zh-Hans": { displayName: "Maia", description: "理性从容，表达清楚。" },
    },
  },
  {
    id: "plainstride_clear_1",
    style: "bright",
    presentation: "male",
    supportedLocales: ["en", "es", "zh-Hans"],
    localized: {
      en: { displayName: "Ethan", description: "Warm, energetic, and easy to hear while moving." },
      es: { displayName: "Ethan", description: "Cálida, enérgica y fácil de seguir en movimiento." },
      "zh-Hans": { displayName: "Ethan", description: "温暖有活力，运动中也容易听清。" },
    },
  },
  {
    id: "plainstride_driven_1",
    style: "driven",
    presentation: "male",
    supportedLocales: ["en", "es", "zh-Hans"],
    localized: {
      en: { displayName: "Moon", description: "Rhythmic and motivating for harder efforts." },
      es: { displayName: "Moon", description: "Rítmica y motivadora para los esfuerzos exigentes." },
      "zh-Hans": { displayName: "Moon", description: "节奏有力，适合更具挑战的训练。" },
    },
  },
  {
    id: "plainstride_easygoing_1",
    style: "easygoing",
    presentation: "male",
    supportedLocales: ["en", "es", "zh-Hans"],
    localized: {
      en: { displayName: "Kai", description: "Friendly, casual, and low-pressure." },
      es: { displayName: "Kai", description: "Cercana, informal y sin presión." },
      "zh-Hans": { displayName: "Kai", description: "友好随和，没有压力感。" },
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
  const localeEnabled = config.enabledLocales.includes(locale);
  const voices = localeEnabled ? VOICE_PROFILES.filter((voice) =>
    config.enabledVoiceProfileIds.includes(voice.id) && voice.supportedLocales.includes(locale)
  ) : [];
  const voiceIds = new Set(voices.map((voice) => voice.id));
  const personas = COACH_PERSONAS.filter((persona) => config.enabledPersonaIds.includes(persona.id))
    .map((persona) => ({ ...persona, allowed: persona.allowedVoiceProfileIds.filter((id) => voiceIds.has(id)) }))
    .filter((persona) => persona.allowed.length > 0 && persona.allowed.includes(persona.defaultVoiceProfileId));
  return {
    contractVersion: 1,
    catalogVersion: config.catalogVersion,
    audioPack: localeEnabled && config.audioManifestUrl ? {
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
      presentation: voice.presentation,
      previewAssetId: "voice.preview",
    })),
  };
}
