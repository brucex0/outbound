import type { AIProviderConfiguration } from "./config.js";
import type { LiveCoachAIProvider } from "./types.js";
import { AlibabaLiveCoachProvider } from "./alibaba/alibabaLiveCoachProvider.js";
import { GoogleCloudTTSLiveCoachProvider } from "./google/googleCloudTTSLiveCoachProvider.js";

export function buildAIProviderRegistry(config: AIProviderConfiguration): LiveCoachAIProvider[] {
  const providers: LiveCoachAIProvider[] = [];
  if (config.googleCloudTTS.enabled) providers.push(new GoogleCloudTTSLiveCoachProvider(config.googleCloudTTS));
  if (config.alibaba.enabled) providers.push(new AlibabaLiveCoachProvider(config.alibaba));
  return providers;
}
