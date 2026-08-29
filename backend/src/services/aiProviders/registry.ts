import type { AIProviderConfiguration } from "./config.js";
import type { LiveCoachAIProvider } from "./types.js";
import { AlibabaLiveCoachProvider } from "./alibaba/alibabaLiveCoachProvider.js";

export function buildAIProviderRegistry(config: AIProviderConfiguration): LiveCoachAIProvider[] {
  return config.alibaba.enabled ? [new AlibabaLiveCoachProvider(config.alibaba)] : [];
}
