import { AIProviderError } from "../errors.js";
import { textFromAlibabaContent, type AlibabaStreamChunk, type AlibabaStreamUsage } from "./alibabaSchemas.js";

export type ParsedAlibabaStream = {
  transcript: string;
  audio: Uint8Array;
  usage: AlibabaStreamUsage;
  providerRequestId?: string;
};

export async function parseAlibabaResponse(response: Response, signal: AbortSignal): Promise<ParsedAlibabaStream> {
  if (!response.body) throw new AIProviderError("invalid_provider_output", "Provider returned no response stream.");
  const contentType = response.headers.get("content-type") ?? "";
  if (contentType.includes("application/json") && !contentType.includes("event-stream")) {
    return parseChunks([await safeJSON(response)]);
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let pending = "";
  const chunks: AlibabaStreamChunk[] = [];
  try {
    while (true) {
      if (signal.aborted) throw new DOMException("Aborted", "AbortError");
      const { done, value } = await reader.read();
      pending += decoder.decode(value, { stream: !done });
      const events = pending.split(/\r?\n\r?\n/);
      pending = events.pop() ?? "";
      for (const event of events) appendSSEEvent(event, chunks);
      if (done) break;
    }
    if (pending.trim()) appendSSEEvent(pending, chunks);
  } finally {
    reader.releaseLock();
  }
  return parseChunks(chunks);
}

function appendSSEEvent(event: string, chunks: AlibabaStreamChunk[]): void {
  const data = event.split(/\r?\n/)
    .filter((line) => line.startsWith("data:"))
    .map((line) => line.slice(5).trimStart())
    .join("\n")
    .trim();
  if (!data || data === "[DONE]") return;
  try {
    chunks.push(JSON.parse(data) as AlibabaStreamChunk);
  } catch {
    throw new AIProviderError("invalid_provider_output", "Provider returned malformed stream data.");
  }
}

function parseChunks(chunks: AlibabaStreamChunk[]): ParsedAlibabaStream {
  const contentParts: string[] = [];
  const transcriptParts: string[] = [];
  const audioParts: Uint8Array[] = [];
  let usage: AlibabaStreamUsage = {};
  let providerRequestId: string | undefined;
  for (const chunk of chunks) {
    providerRequestId = providerRequestId ?? chunk.request_id ?? chunk.id;
    if (chunk.usage) usage = chunk.usage;
    for (const choice of chunk.choices ?? []) {
      const output = choice.delta ?? choice.message;
      if (!output) continue;
      const content = textFromAlibabaContent(output.content);
      if (content) contentParts.push(content);
      if (typeof output.audio?.transcript === "string") transcriptParts.push(output.audio.transcript);
      if (typeof output.audio?.data === "string" && output.audio.data) {
        try {
          audioParts.push(Buffer.from(output.audio.data, "base64"));
        } catch {
          throw new AIProviderError("invalid_provider_output", "Provider returned invalid audio data.");
        }
      }
    }
  }
  if (audioParts.length === 0) throw new AIProviderError("invalid_provider_output", "Provider returned no audio modality.");
  const transcript = (transcriptParts.length > 0 ? transcriptParts : contentParts).join("").trim();
  if (!transcript) throw new AIProviderError("invalid_provider_output", "Provider returned no transcript.");
  return { transcript, audio: Buffer.concat(audioParts), usage, providerRequestId };
}

async function safeJSON(response: Response): Promise<AlibabaStreamChunk> {
  try {
    return await response.json() as AlibabaStreamChunk;
  } catch {
    throw new AIProviderError("invalid_provider_output", "Provider returned malformed JSON.");
  }
}
