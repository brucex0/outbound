import { validateLiveCoachWav } from "../audioValidation.js";
import type { AlibabaProviderConfig } from "../config.js";
import { AIProviderError, sanitizedProviderError } from "../errors.js";
import { recordRouteFailure, recordRouteSuccess } from "../health.js";
import { LIVE_COACH_AUDIO_ENCODING, type LiveCoachAIProvider, type LiveCoachGenerationInput, type ProviderCapabilities, type SupportedAILocale, type VoiceProfileId } from "../types.js";
import { parseAlibabaResponse } from "./alibabaStreamParser.js";
import { resolveAlibabaVoice } from "./alibabaVoiceMap.js";

export class AlibabaLiveCoachProvider implements LiveCoachAIProvider {
  readonly key = "alibaba" as const;
  readonly endpointKey: string;
  readonly model: string;

  constructor(private readonly config: AlibabaProviderConfig) {
    this.endpointKey = config.endpointKey;
    this.model = config.model;
  }

  capabilities(): ProviderCapabilities {
    return {
      text: true,
      audioOutput: true,
      combinedTextAndAudio: true,
      supportedLocales: ["en", "es", "zh-Hans"],
      supportedMarkets: ["global"],
      supportedAudio: [LIVE_COACH_AUDIO_ENCODING],
      maximumOutputSeconds: 4.5,
    };
  }

  resolveVoice(voiceProfileId: VoiceProfileId, locale: SupportedAILocale): string | null {
    return resolveAlibabaVoice(this.config, voiceProfileId, locale);
  }

  async generateCue(input: LiveCoachGenerationInput, signal: AbortSignal) {
    if (!this.config.enabled || !this.config.apiKey || !this.config.baseUrl || !this.config.model) {
      throw new AIProviderError("not_configured", "Alibaba live coaching is not configured.");
    }
    const deadlineMilliseconds = Math.max(1, input.deadline.getTime() - Date.now());
    const deadlineController = new AbortController();
    const abortFromCaller = () => deadlineController.abort(signal.reason);
    signal.addEventListener("abort", abortFromCaller, { once: true });
    const timer = setTimeout(() => deadlineController.abort(), deadlineMilliseconds);

    try {
      const response = await fetch(`${this.config.baseUrl}/chat/completions`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${this.config.apiKey}`,
          "X-DashScope-SSE": "enable",
        },
        body: JSON.stringify({
          model: this.config.model,
          modalities: ["text", "audio"],
          audio: { voice: input.providerVoice, format: "wav" },
          stream: true,
          stream_options: { include_usage: true },
          enable_thinking: false,
          temperature: input.exactTranscript ? 0 : 0.35,
          max_tokens: 96,
          messages: [
            { role: "system", content: `${input.stableInstructions}\n${input.coachPersonaInstructions}` },
            { role: "user", content: JSON.stringify(providerPayload(input)) },
          ],
        }),
        signal: deadlineController.signal,
      });
      if (!response.ok) throw providerHTTPError(response.status);
      const parsed = await parseAlibabaResponse(response, deadlineController.signal);
      const transcript = normalizeTranscript(parsed.transcript);
      validateTranscript(transcript, input);
      const wav = validateLiveCoachWav(parsed.audio);
      recordRouteSuccess(this.key, this.endpointKey);
      return {
        transcript,
        audio: parsed.audio,
        audioEncoding: wav.encoding,
        durationMilliseconds: wav.durationMilliseconds,
        usage: {
          inputTokens: parsed.usage.prompt_tokens,
          outputTextTokens: parsed.usage.output_tokens_details?.text_tokens ?? parsed.usage.completion_tokens,
          outputAudioTokens: parsed.usage.output_tokens_details?.audio_tokens,
        },
        providerRequestId: parsed.providerRequestId,
      };
    } catch (error) {
      recordRouteFailure(this.key, this.endpointKey);
      throw sanitizedProviderError(error);
    } finally {
      clearTimeout(timer);
      signal.removeEventListener("abort", abortFromCaller);
    }
  }
}

function providerPayload(input: LiveCoachGenerationInput): object {
  if (input.exactTranscript) {
    return {
      task: "speak_exact_text",
      locale: input.locale,
      text: input.exactTranscript,
      constraint: "Speak the exact text with no additions or omissions.",
    };
  }
  return {
    task: "live_coach_cue",
    locale: input.locale,
    semanticMoment: input.semanticMoment,
    session: input.compiledContext,
    liveState: input.liveState,
    recentCueSummaries: input.recentCueSummaries.slice(-3),
    maximumSpokenWordsEquivalent: input.maximumSpokenWordsEquivalent,
    output: "Return and speak exactly one short coaching sentence. Do not include markdown or labels.",
  };
}

function validateTranscript(transcript: string, input: LiveCoachGenerationInput): void {
  if (!transcript || transcript.length > 240) {
    throw new AIProviderError("invalid_provider_output", "Provider transcript length is invalid.");
  }
  if (input.exactTranscript && normalizeTranscript(input.exactTranscript) !== transcript) {
    throw new AIProviderError("invalid_provider_output", "Provider fixed-asset transcript did not match source text.");
  }
  const wordEquivalent = input.locale === "zh-Hans"
    ? transcript.replace(/\s/g, "").length / 2
    : transcript.split(/\s+/).filter(Boolean).length;
  if (wordEquivalent > input.maximumSpokenWordsEquivalent + 4) {
    throw new AIProviderError("invalid_provider_output", "Provider transcript exceeds the spoken-word budget.");
  }
}

function normalizeTranscript(value: string): string {
  return value.trim().replace(/\s+/g, " ");
}

function providerHTTPError(status: number): AIProviderError {
  if (status === 429) return new AIProviderError("rate_limited", "The AI provider rate limit was reached.", true);
  if (status === 408 || status === 504) return new AIProviderError("deadline_exceeded", "The AI provider deadline elapsed.", true);
  return new AIProviderError("provider_unavailable", "The AI provider rejected the request.", status >= 500);
}
