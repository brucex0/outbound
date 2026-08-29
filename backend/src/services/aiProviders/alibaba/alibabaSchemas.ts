export type AlibabaStreamUsage = {
  prompt_tokens?: number;
  completion_tokens?: number;
  output_tokens_details?: { audio_tokens?: number; text_tokens?: number };
};

export type AlibabaStreamChunk = {
  id?: string;
  request_id?: string;
  choices?: Array<{
    delta?: {
      content?: unknown;
      audio?: { data?: unknown; transcript?: unknown };
    };
    message?: {
      content?: unknown;
      audio?: { data?: unknown; transcript?: unknown };
    };
  }>;
  usage?: AlibabaStreamUsage;
};

export function textFromAlibabaContent(content: unknown): string {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content.map((part) => {
    if (typeof part === "string") return part;
    if (typeof part === "object" && part !== null && "text" in part && typeof part.text === "string") {
      return part.text;
    }
    return "";
  }).join("");
}
