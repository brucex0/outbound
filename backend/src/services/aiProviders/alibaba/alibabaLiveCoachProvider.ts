import { validateLiveCoachWav } from "../audioValidation.js";
import type { AlibabaProviderConfig } from "../config.js";
import { AIProviderError, sanitizedProviderError } from "../errors.js";
import { recordRouteFailure, recordRouteSuccess } from "../health.js";
import { LIVE_COACH_AUDIO_ENCODING, LIVE_COACH_FIXED_AUDIO_MAX_DURATION_MILLISECONDS, type LiveCoachAIProvider, type LiveCoachGenerationInput, type ProviderCapabilities, type SupportedAILocale, type VoiceProfileId } from "../types.js";
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
    if (input.exactTranscript && (!this.config.fixedAudioBaseUrl || !this.config.fixedAudioModel)) {
      throw new AIProviderError("not_configured", "Alibaba fixed-audio synthesis is not configured.");
    }
    const deadlineMilliseconds = Math.max(1, input.deadline.getTime() - Date.now());
    const deadlineController = new AbortController();
    const abortFromCaller = () => deadlineController.abort(signal.reason);
    signal.addEventListener("abort", abortFromCaller, { once: true });
    const timer = setTimeout(() => deadlineController.abort(), deadlineMilliseconds);

    try {
      const result = input.exactTranscript
        ? await this.generateFixedCue(input, deadlineController.signal)
        : await this.generateDynamicCue(input, deadlineController.signal);
      recordRouteSuccess(this.key, this.endpointKey);
      return result;
    } catch (error) {
      recordRouteFailure(this.key, this.endpointKey);
      throw sanitizedProviderError(error);
    } finally {
      clearTimeout(timer);
      signal.removeEventListener("abort", abortFromCaller);
    }
  }

  private async generateDynamicCue(input: LiveCoachGenerationInput, signal: AbortSignal) {
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
        temperature: 0.35,
        max_tokens: 96,
        messages: [
          { role: "system", content: `${input.stableInstructions}\n${input.coachPersonaInstructions}` },
          { role: "user", content: JSON.stringify(providerPayload(input)) },
        ],
      }),
      signal,
    });
    if (!response.ok) throw providerHTTPError(response.status);
    const parsed = await parseAlibabaResponse(response, signal);
    const transcript = normalizeTranscript(parsed.transcript);
    validateTranscript(transcript, input);
    const wav = validateLiveCoachWav(parsed.audio);
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
  }

  private async generateFixedCue(input: LiveCoachGenerationInput, signal: AbortSignal) {
    const transcript = normalizeTranscript(input.exactTranscript ?? "");
    validateTranscript(transcript, input);
    const response = await fetch(
      `${this.config.fixedAudioBaseUrl}/services/aigc/multimodal-generation/generation`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${this.config.apiKey}`,
        },
        body: JSON.stringify({
          model: this.config.fixedAudioModel,
          input: {
            text: transcript,
            voice: input.providerVoice,
            language_type: ttsLanguage(input.locale),
            instructions: fixedCueInstructions(input),
            optimize_instructions: true,
          },
        }),
        signal,
      }
    );
    if (!response.ok) throw providerHTTPError(response.status);
    const parsed = await parseTTSResponse(response);
    const audioResponse = await fetch(validatedAudioURL(parsed.audioUrl), { signal });
    if (!audioResponse.ok) throw providerHTTPError(audioResponse.status);
    const audio = new Uint8Array(await audioResponse.arrayBuffer());
    const wav = validateLiveCoachWav(audio, {
      maximumDurationMilliseconds: LIVE_COACH_FIXED_AUDIO_MAX_DURATION_MILLISECONDS,
    });
    return {
      transcript,
      audio,
      audioEncoding: wav.encoding,
      durationMilliseconds: wav.durationMilliseconds,
      usage: {
        inputTokens: parsed.inputTokens,
        outputAudioTokens: parsed.outputAudioTokens,
      },
      providerRequestId: parsed.requestId,
    };
  }
}

function providerPayload(input: LiveCoachGenerationInput): object {
  const output = input.semanticMoment === "progress"
    ? "Return and speak exactly one short progress sentence. Include current elapsed time, distance, and pace whenever each value is available. Do not include markdown or labels."
    : "Return and speak exactly one short coaching sentence. Do not include markdown or labels.";
  return {
    task: "live_coach_cue",
    locale: input.locale,
    semanticMoment: input.semanticMoment,
    session: input.compiledContext,
    liveState: input.liveState,
    recentCueSummaries: input.recentCueSummaries.slice(-3),
    maximumSpokenWordsEquivalent: input.maximumSpokenWordsEquivalent,
    output,
  };
}

function fixedCueInstructions(input: LiveCoachGenerationInput): string {
  return [
    "Voice a prerecorded Plainstride live endurance coaching cue for one runner who is already moving.",
    `Semantic moment: ${input.semanticMoment}.`,
    input.coachPersonaInstructions,
    "Use natural conversational cadence, human sentence stress, and clean pronunciation that remains easy to catch outdoors.",
    "Speak only the supplied text, exactly once, with no additions, omissions, labels, sound effects, or background audio.",
    "Avoid robotic, sing-song, announcer, commercial, and theatrical delivery.",
  ].join(" ");
}

function ttsLanguage(locale: SupportedAILocale): "English" | "Spanish" | "Chinese" {
  if (locale === "zh-Hans") return "Chinese";
  if (locale === "es") return "Spanish";
  return "English";
}

type ParsedTTSResponse = {
  audioUrl: string;
  requestId?: string;
  inputTokens?: number;
  outputAudioTokens?: number;
};

async function parseTTSResponse(response: Response): Promise<ParsedTTSResponse> {
  let value: unknown;
  try {
    value = await response.json();
  } catch {
    throw new AIProviderError("invalid_provider_output", "Provider returned malformed TTS JSON.");
  }
  if (!isRecord(value)) throw new AIProviderError("invalid_provider_output", "Provider returned invalid TTS output.");
  const output = isRecord(value.output) ? value.output : null;
  const audio = output && isRecord(output.audio) ? output.audio : null;
  if (!audio || typeof audio.url !== "string" || !audio.url.trim()) {
    throw new AIProviderError("invalid_provider_output", "Provider returned no TTS audio URL.");
  }
  const usage = isRecord(value.usage) ? value.usage : null;
  return {
    audioUrl: audio.url,
    requestId: typeof value.request_id === "string" ? value.request_id : undefined,
    inputTokens: numericValue(usage?.input_tokens),
    outputAudioTokens: numericValue(usage?.output_tokens),
  };
}

function validatedAudioURL(value: string): URL {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw new AIProviderError("invalid_provider_output", "Provider returned an invalid TTS audio URL.");
  }
  if (!["http:", "https:"].includes(url.protocol) || !url.hostname.endsWith(".aliyuncs.com")) {
    throw new AIProviderError("invalid_provider_output", "Provider returned an untrusted TTS audio URL.");
  }
  return url;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function numericValue(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
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
