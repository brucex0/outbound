import type { SupportedAILocale, VoiceProfileId } from "../types.js";

// Approved against Alibaba's Qwen-Omni voice list for the pinned snapshot.
// Keep provider IDs inside the adapter layer; public APIs expose Plainstride IDs only.
export const APPROVED_ALIBABA_LIVE_COACH_MODEL = "qwen3-omni-flash-2025-12-01";

export const APPROVED_ALIBABA_LIVE_COACH_VOICE_MAP: Record<
  VoiceProfileId,
  Record<SupportedAILocale, string>
> = {
  plainstride_warm_1: { en: "Cherry", es: "Cherry", "zh-Hans": "Cherry" },
  plainstride_gentle_1: { en: "Serena", es: "Serena", "zh-Hans": "Serena" },
  plainstride_composed_1: { en: "Maia", es: "Maia", "zh-Hans": "Maia" },
  plainstride_clear_1: { en: "Ethan", es: "Ethan", "zh-Hans": "Ethan" },
  plainstride_driven_1: { en: "Ryan", es: "Ryan", "zh-Hans": "Ryan" },
  plainstride_easygoing_1: { en: "Aiden", es: "Aiden", "zh-Hans": "Aiden" },
};
