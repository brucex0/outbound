import type { SupportedAILocale, VoiceProfileId } from "../types.js";

export const APPROVED_GOOGLE_CLOUD_TTS_MODEL = "chirp3-hd";

export const APPROVED_GOOGLE_CLOUD_TTS_VOICE_MAP: Record<
  VoiceProfileId,
  Record<SupportedAILocale, string>
> = {
  plainstride_warm_1: {
    en: "en-US-Chirp3-HD-Aoede",
    es: "es-US-Chirp3-HD-Aoede",
    "zh-Hans": "cmn-CN-Chirp3-HD-Aoede",
  },
  plainstride_clear_1: {
    en: "en-US-Chirp3-HD-Charon",
    es: "es-US-Chirp3-HD-Charon",
    "zh-Hans": "cmn-CN-Chirp3-HD-Charon",
  },
};
