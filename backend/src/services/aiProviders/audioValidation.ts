import { AIProviderError } from "./errors.js";
import { LIVE_COACH_AUDIO_ENCODING, type AudioEncoding } from "./types.js";

export type ValidatedWav = {
  encoding: AudioEncoding;
  durationMilliseconds: number;
};

export function validateLiveCoachWav(
  audio: Uint8Array,
  limits: { maximumBytes?: number; maximumDurationMilliseconds?: number } = {}
): ValidatedWav {
  const maximumBytes = limits.maximumBytes ?? 512 * 1024;
  const maximumDurationMilliseconds = limits.maximumDurationMilliseconds ?? 4_500;
  if (audio.byteLength < 44 || audio.byteLength > maximumBytes) {
    throw new AIProviderError("invalid_provider_output", "Provider audio size is invalid.");
  }
  const view = new DataView(audio.buffer, audio.byteOffset, audio.byteLength);
  if (ascii(audio, 0, 4) !== "RIFF" || ascii(audio, 8, 4) !== "WAVE") {
    throw new AIProviderError("invalid_provider_output", "Provider audio is not a WAV container.");
  }

  let offset = 12;
  let format: { audioFormat: number; channels: number; sampleRate: number; bitsPerSample: number } | null = null;
  let dataBytes = 0;
  let audibleSampleCount = 0;
  while (offset + 8 <= audio.byteLength) {
    const chunkId = ascii(audio, offset, 4);
    const chunkSize = view.getUint32(offset + 4, true);
    const payloadOffset = offset + 8;
    if (payloadOffset + chunkSize > audio.byteLength) {
      throw new AIProviderError("invalid_provider_output", "Provider WAV chunks are malformed.");
    }
    if (chunkId === "fmt " && chunkSize >= 16) {
      format = {
        audioFormat: view.getUint16(payloadOffset, true),
        channels: view.getUint16(payloadOffset + 2, true),
        sampleRate: view.getUint32(payloadOffset + 4, true),
        bitsPerSample: view.getUint16(payloadOffset + 14, true),
      };
    } else if (chunkId === "data") {
      dataBytes += chunkSize;
      for (let sampleOffset = payloadOffset; sampleOffset + 1 < payloadOffset + chunkSize; sampleOffset += 48) {
        if (Math.abs(view.getInt16(sampleOffset, true)) >= 64) audibleSampleCount += 1;
      }
    }
    offset = payloadOffset + chunkSize + (chunkSize % 2);
  }

  if (!format || format.audioFormat !== 1 || format.channels !== 1
      || format.sampleRate !== 24_000 || format.bitsPerSample !== 16 || dataBytes <= 0) {
    throw new AIProviderError("invalid_provider_output", "Provider WAV encoding is unsupported.");
  }
  if (audibleSampleCount < 10) {
    throw new AIProviderError("invalid_provider_output", "Provider WAV contains no audible signal.");
  }
  const bytesPerSecond = format.sampleRate * format.channels * (format.bitsPerSample / 8);
  const durationMilliseconds = Math.round((dataBytes / bytesPerSecond) * 1_000);
  if (durationMilliseconds <= 0 || durationMilliseconds > maximumDurationMilliseconds) {
    throw new AIProviderError("invalid_provider_output", "Provider audio duration is invalid.");
  }
  return { encoding: LIVE_COACH_AUDIO_ENCODING, durationMilliseconds };
}

function ascii(bytes: Uint8Array, offset: number, length: number): string {
  return String.fromCharCode(...bytes.subarray(offset, offset + length));
}
