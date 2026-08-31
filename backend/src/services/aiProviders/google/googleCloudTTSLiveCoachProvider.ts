import { TextToSpeechClient } from "@google-cloud/text-to-speech";
import { validateLiveCoachWav } from "../audioValidation.js";
import type { GoogleCloudTTSProviderConfig } from "../config.js";
import { AIProviderError } from "../errors.js";
import { recordRouteFailure, recordRouteSuccess } from "../health.js";
import {
  LIVE_COACH_AUDIO_ENCODING,
  LIVE_COACH_DYNAMIC_AUDIO_MAX_DURATION_MILLISECONDS,
  type LiveCoachAIProvider,
  type LiveCoachGenerationInput,
  type LiveCoachProviderAudioStream,
  type ProviderCapabilities,
  type SupportedAILocale,
  type VoiceProfileId,
} from "../types.js";

export class GoogleCloudTTSLiveCoachProvider implements LiveCoachAIProvider {
  readonly key = "google_cloud_tts" as const;
  readonly endpointKey: string;
  readonly model: string;
  private readonly client: TextToSpeechClient;

  constructor(private readonly config: GoogleCloudTTSProviderConfig) {
    this.endpointKey = config.endpointKey;
    this.model = config.model;
    this.client = new TextToSpeechClient({ apiEndpoint: config.apiEndpoint });
  }

  capabilities(): ProviderCapabilities {
    return {
      text: false,
      audioOutput: true,
      combinedTextAndAudio: false,
      supportedLocales: ["en", "es", "zh-Hans"],
      supportedMarkets: ["global"],
      supportedAudio: [LIVE_COACH_AUDIO_ENCODING],
      maximumOutputSeconds: LIVE_COACH_DYNAMIC_AUDIO_MAX_DURATION_MILLISECONDS / 1_000,
    };
  }

  resolveVoice(voiceProfileId: VoiceProfileId, locale: SupportedAILocale): string | null {
    return this.config.voiceMap[voiceProfileId]?.[locale] ?? null;
  }

  async generateCue(input: LiveCoachGenerationInput, signal: AbortSignal) {
    if (!this.config.enabled) {
      throw new AIProviderError("not_configured", "Google Cloud TTS is not configured.");
    }
    const transcript = normalizeTranscript(input.exactTranscript ?? "");
    validateTranscript(transcript, input);
    if (signal.aborted) throw new DOMException("Aborted", "AbortError");
    const timeout = Math.max(1, input.deadline.getTime() - Date.now());

    try {
      const [response] = await this.client.synthesizeSpeech({
        input: { text: transcript },
        voice: {
          languageCode: googleLanguageCode(input.locale),
          name: input.providerVoice,
        },
        audioConfig: {
          audioEncoding: "LINEAR16",
          sampleRateHertz: LIVE_COACH_AUDIO_ENCODING.sampleRateHz,
        },
      }, { timeout, retry: null });
      if (signal.aborted || Date.now() >= input.deadline.getTime()) {
        throw new AIProviderError("deadline_exceeded", "Google Cloud TTS exceeded the cue deadline.", true);
      }
      const audio = audioBytes(response.audioContent);
      const wav = validateLiveCoachWav(audio, {
        maximumDurationMilliseconds: LIVE_COACH_DYNAMIC_AUDIO_MAX_DURATION_MILLISECONDS,
      });
      recordRouteSuccess(this.key, this.endpointKey);
      return {
        transcript,
        audio,
        audioEncoding: wav.encoding,
        durationMilliseconds: wav.durationMilliseconds,
        usage: {},
      };
    } catch (error) {
      recordRouteFailure(this.key, this.endpointKey);
      throw googleProviderError(error, input.deadline, signal);
    }
  }

  async streamCue(input: LiveCoachGenerationInput, signal: AbortSignal): Promise<LiveCoachProviderAudioStream> {
    if (!this.config.enabled) {
      throw new AIProviderError("not_configured", "Google Cloud TTS is not configured.");
    }
    const transcript = normalizeTranscript(input.exactTranscript ?? "");
    validateTranscript(transcript, input);
    if (signal.aborted) throw new DOMException("Aborted", "AbortError");
    const timeout = Math.max(1, input.deadline.getTime() - Date.now());
    const call = this.client.streamingSynthesize({ timeout, retry: null });
    const cancel = () => call.cancel();
    signal.addEventListener("abort", cancel, { once: true });

    call.write({
      streamingConfig: {
        voice: {
          languageCode: googleLanguageCode(input.locale),
          name: input.providerVoice,
        },
        streamingAudioConfig: {
          audioEncoding: "PCM",
          sampleRateHertz: LIVE_COACH_AUDIO_ENCODING.sampleRateHz,
          speakingRate: 1,
        },
      },
    });
    call.write({ input: { text: transcript } });
    call.end();

    const source = call as unknown as AsyncIterable<{ audioContent?: string | Uint8Array | null }>;
    const endpointKey = this.endpointKey;
    const chunks = (async function* () {
      let byteCount = 0;
      let receivedAudio = false;
      try {
        for await (const response of source) {
          if (signal.aborted) throw new DOMException("Aborted", "AbortError");
          const chunk = optionalAudioBytes(response.audioContent);
          if (!chunk) continue;
          byteCount += chunk.byteLength;
          if (byteCount > 384 * 1024) {
            call.cancel();
            throw new AIProviderError("invalid_provider_output", "Google Cloud TTS streamed too much audio.");
          }
          receivedAudio = true;
          yield chunk;
        }
        if (!receivedAudio) {
          throw new AIProviderError("invalid_provider_output", "Google Cloud TTS returned no streaming audio.");
        }
        recordRouteSuccess("google_cloud_tts", endpointKey);
      } catch (error) {
        recordRouteFailure("google_cloud_tts", endpointKey);
        throw googleProviderError(error, input.deadline, signal);
      } finally {
        signal.removeEventListener("abort", cancel);
      }
    })();

    return {
      transcript,
      audioEncoding: { container: "raw", codec: "pcm_s16le", sampleRateHz: 24_000, channels: 1 },
      chunks,
    };
  }
}

function googleLanguageCode(locale: SupportedAILocale): string {
  if (locale === "zh-Hans") return "cmn-CN";
  if (locale === "es") return "es-US";
  return "en-US";
}

function audioBytes(value: string | Uint8Array | null | undefined): Uint8Array {
  if (typeof value === "string" && value) return new Uint8Array(Buffer.from(value, "base64"));
  if (value instanceof Uint8Array && value.byteLength > 0) return value;
  throw new AIProviderError("invalid_provider_output", "Google Cloud TTS returned no audio.");
}

function optionalAudioBytes(value: string | Uint8Array | null | undefined): Uint8Array | null {
  if (typeof value === "string" && value) return new Uint8Array(Buffer.from(value, "base64"));
  if (value instanceof Uint8Array && value.byteLength > 0) return value;
  return null;
}

function validateTranscript(transcript: string, input: LiveCoachGenerationInput): void {
  if (!input.exactTranscript) {
    throw new AIProviderError("invalid_provider_output", "Google Cloud TTS requires a finalized transcript.");
  }
  if (!transcript || transcript.length > 240) {
    throw new AIProviderError("invalid_provider_output", "Google Cloud TTS transcript length is invalid.");
  }
  const wordEquivalent = input.locale === "zh-Hans"
    ? transcript.replace(/\s/g, "").length / 2
    : transcript.split(/\s+/).filter(Boolean).length;
  if (wordEquivalent > input.maximumSpokenWordsEquivalent + 4) {
    throw new AIProviderError("invalid_provider_output", "Google Cloud TTS transcript exceeds the spoken-word budget.");
  }
}

function normalizeTranscript(value: string): string {
  return value.trim().replace(/\s+/g, " ");
}

function googleProviderError(error: unknown, deadline: Date, signal: AbortSignal): AIProviderError {
  if (error instanceof AIProviderError) return error;
  if (signal.aborted || Date.now() >= deadline.getTime() || grpcCode(error) === 4) {
    return new AIProviderError("deadline_exceeded", "Google Cloud TTS exceeded the cue deadline.", true);
  }
  if (grpcCode(error) === 8) {
    return new AIProviderError("rate_limited", "Google Cloud TTS quota was reached.", true);
  }
  return new AIProviderError("provider_unavailable", "Google Cloud TTS is unavailable.", true);
}

function grpcCode(error: unknown): number | null {
  if (typeof error !== "object" || error === null || !("code" in error)) return null;
  return typeof error.code === "number" ? error.code : null;
}
