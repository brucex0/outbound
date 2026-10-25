import { TextToSpeechClient } from "@google-cloud/text-to-speech";
import { loadAIProviderConfiguration } from "../aiProviders/config.js";
import { AIProviderError, sanitizedProviderError } from "../aiProviders/errors.js";
import { validateLiveCoachWav } from "../aiProviders/audioValidation.js";
import type { SupportedAILocale, VoiceProfileId } from "../aiProviders/types.js";

import { stretchMovementTitles } from "./stretchCatalogData.js";

// Only finite catalog-generated cues can reach synthesis. Existing cue text stays unchanged.
const extras = {
  en: ["Release.", "Five.", "Four.", "Three.", "Two.", "One."],
  es: ["Relaja.", "Cinco.", "Cuatro.", "Tres.", "Dos.", "Uno."],
  "zh-Hans": ["放松。", "五。", "四。", "三。", "二。", "一。"],
};
const extraKeys = ["release", "five", "four", "three", "two", "one"];
export const stretchCueKeys = [
  ...Object.keys(stretchMovementTitles).flatMap(id =>
    ["inner_thigh", "chest", "upper_back", "lat"].includes(id) ? [`${id}_both`] : [`${id}_left`, `${id}_right`]),
  ...extraKeys,
] as [string, ...string[]];
type Cue = string;
export function stretchCueTranscript(cue: Cue, locale: SupportedAILocale): string {
  const extraIndex = extraKeys.indexOf(cue);
  if (extraIndex >= 0) return extras[locale][extraIndex]!;
  const movement = cue.replace(/_(left|right|both)$/, "") as keyof typeof stretchMovementTitles;
  if (!stretchCueKeys.includes(cue) || !(movement in stretchMovementTitles)) {
    throw new AIProviderError("invalid_provider_output", "Unknown stretch cue.");
  }
  const sides = locale === "en" ? ["left side", "right side", "both sides"]
    : locale === "es" ? ["lado izquierdo", "lado derecho", "ambos lados"] : ["左侧", "右侧", "双侧"];
  return `${stretchMovementTitles[movement][locale]}. ${sides[cue.endsWith("left") ? 0 : cue.endsWith("right") ? 1 : 2]}.`;
}

// Finite catalog of keys × 3 locales × 2 voices. Share in-flight synthesis.
const cache = new Map<string, Uint8Array>();
const pending = new Map<string, Promise<Uint8Array>>();
export async function stretchCueAudio(cue: Cue, locale: SupportedAILocale, voice: VoiceProfileId): Promise<Uint8Array> {
  const config = loadAIProviderConfiguration().googleCloudTTS;
  const providerVoice = config.voiceMap[voice]?.[locale];
  if (!config.enabled || !providerVoice) throw new AIProviderError("not_configured", "Stretch voice unavailable.");
  const key = `${config.apiEndpoint}:${providerVoice}:${locale}:${cue}`;
  const cached = cache.get(key);
  if (cached) return cached;
  const existing = pending.get(key);
  if (existing) return existing;
  const work = (async () => {
    const text = stretchCueTranscript(cue, locale);
    const client = new TextToSpeechClient({ apiEndpoint: config.apiEndpoint });
    try {
      const [response] = await client.synthesizeSpeech({
        input: { text },
        voice: { name: providerVoice, languageCode: locale === "zh-Hans" ? "cmn-CN" : locale === "es" ? "es-US" : "en-US" },
        audioConfig: { audioEncoding: "LINEAR16", sampleRateHertz: 24000 },
      }, { timeout: 8000, retry: null });
      const audio = typeof response.audioContent === "string" ? Buffer.from(response.audioContent, "base64") : response.audioContent;
      if (!audio) throw new AIProviderError("invalid_provider_output", "Empty stretch audio.");
      validateLiveCoachWav(audio, { maximumDurationMilliseconds: 10000 });
      if (cache.size >= stretchCueKeys.length * 6) cache.clear();
      cache.set(key, audio);
      return audio;
    } catch (error) {
      const safe = sanitizedProviderError(error);
      console.warn("[stretch-audio] synthesis failed", { category: safe.code });
      throw safe;
    } finally { await client.close(); }
  })();
  pending.set(key, work);
  try { return await work; } finally { pending.delete(key); }
}
