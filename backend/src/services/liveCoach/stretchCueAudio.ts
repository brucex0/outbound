import { TextToSpeechClient } from "@google-cloud/text-to-speech";
import { loadAIProviderConfiguration } from "../aiProviders/config.js";
import { AIProviderError, sanitizedProviderError } from "../aiProviders/errors.js";
import { validateLiveCoachWav } from "../aiProviders/audioValidation.js";
import type { SupportedAILocale, VoiceProfileId } from "../aiProviders/types.js";

export const stretchCueKeys = [
  "glute_left", "glute_right", "hamstring_left", "hamstring_right", "inner_thigh_both",
  "calf_left", "calf_right", "quad_left", "quad_right", "hip_flexor_left", "hip_flexor_right",
  "release", "five", "four", "three", "two", "one",
] as const;
type Cue = typeof stretchCueKeys[number];
const names = {
  en: ["Glute stretch", "Hamstring stretch", "Inner thigh stretch", "Calf stretch", "Quad stretch", "Hip flexor stretch"],
  es: ["Estiramiento de glúteos", "Estiramiento de isquiotibiales", "Estiramiento de aductores", "Estiramiento de pantorrilla", "Estiramiento de cuádriceps", "Estiramiento de flexores de cadera"],
  "zh-Hans": ["臀部拉伸", "大腿后侧拉伸", "大腿内侧拉伸", "小腿拉伸", "大腿前侧拉伸", "髋屈肌拉伸"],
};
const extras = {
  en: ["Release.", "Five.", "Four.", "Three.", "Two.", "One."],
  es: ["Relaja.", "Cinco.", "Cuatro.", "Tres.", "Dos.", "Uno."],
  "zh-Hans": ["放松。", "五。", "四。", "三。", "二。", "一。"],
};
// Finite catalog: at most 17 cues × 3 locales × 2 voices. Share in-flight synthesis.
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
    const index = stretchCueKeys.indexOf(cue);
    let text: string;
    if (index >= 11) text = extras[locale][index - 11]!;
    else {
      const movement = index < 4 ? Math.floor(index / 2) : index === 4 ? 2 : Math.floor((index + 1) / 2);
      const side = cue.endsWith("left") ? 0 : cue.endsWith("right") ? 1 : 2;
      const sides = locale === "en" ? ["left side", "right side", "both sides"]
        : locale === "es" ? ["lado izquierdo", "lado derecho", "ambos lados"] : ["左侧", "右侧", "双侧"];
      text = `${names[locale][movement]}. ${sides[side]}.`;
    }
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
      if (cache.size >= 102) cache.clear();
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
