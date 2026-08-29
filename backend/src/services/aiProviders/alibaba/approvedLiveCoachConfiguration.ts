import type { SupportedAILocale, VoiceProfileId } from "../types.js";

// Dynamic cues still need a conversational model to write and speak a response.
// Fixed assets use the dedicated instruction-controlled TTS snapshot instead.
export const APPROVED_ALIBABA_DYNAMIC_LIVE_COACH_MODEL = "qwen3-omni-flash-2025-12-01";
export const APPROVED_ALIBABA_FIXED_AUDIO_MODEL = "qwen3-tts-instruct-flash-2026-01-26";

export const APPROVED_ALIBABA_LIVE_COACH_VOICE_MAP: Record<
  VoiceProfileId,
  Record<SupportedAILocale, string>
> = {
  plainstride_warm_1: { en: "Cherry", es: "Cherry", "zh-Hans": "Cherry" },
  plainstride_gentle_1: { en: "Serena", es: "Serena", "zh-Hans": "Serena" },
  plainstride_composed_1: { en: "Maia", es: "Maia", "zh-Hans": "Maia" },
  plainstride_clear_1: { en: "Ethan", es: "Ethan", "zh-Hans": "Ethan" },
  plainstride_driven_1: { en: "Moon", es: "Moon", "zh-Hans": "Moon" },
  plainstride_easygoing_1: { en: "Kai", es: "Kai", "zh-Hans": "Kai" },
};
