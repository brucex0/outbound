import type { GenerateContentParameters } from "@google/genai";

export type StructuredAIResponse = {
  text?: string;
  modelVersion?: string;
  usageMetadata?: { promptTokenCount?: number; candidatesTokenCount?: number };
};

function strictSchema(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(strictSchema);
  if (!value || typeof value !== "object") return value;
  const schema = Object.fromEntries(Object.entries(value).map(([key, item]) => [key, strictSchema(item)]));
  if (schema.type === "object") schema.additionalProperties = false;
  return schema;
}

export async function generateWithOpenAI(model: string, parameters: Omit<GenerateContentParameters, "model">, signal: AbortSignal): Promise<StructuredAIResponse> {
  const key = process.env.OPENAI_API_KEY?.trim();
  if (!key) throw Object.assign(new Error("OpenAI credential unavailable"), { status: 401 });
  const config = parameters.config;
  if (typeof parameters.contents !== "string" || typeof config?.systemInstruction !== "string" || !config.responseJsonSchema) {
    throw Object.assign(new Error("Unsupported structured AI request configuration"), { status: 400 });
  }
  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST", signal,
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model, instructions: config.systemInstruction, input: parameters.contents, store: false,
      reasoning: { effort: config.thinkingConfig?.thinkingLevel === "HIGH" ? "high" : "low" },
      max_output_tokens: config.maxOutputTokens,
      text: { format: { type: "json_schema", name: "plainstride_response", strict: true, schema: strictSchema(config.responseJsonSchema) } },
    }),
  });
  if (!response.ok) {
    // Extract only the bounded billing classification; never log error bodies.
    let quotaExhausted = false;
    try {
      const failure = await response.json() as { error?: { code?: string; type?: string } };
      quotaExhausted = [failure.error?.code, failure.error?.type].some((code) =>
        code !== undefined && ["insufficient_quota", "credit_balance_exhausted", "billing_hard_limit_reached"].includes(code));
    } catch {
      // Gateways can return non-JSON failures; HTTP status remains diagnostic.
    }
    const retryAfter = response.headers.get("retry-after");
    const retryAfterMilliseconds = retryAfter === null ? undefined
      : Number.isFinite(Number(retryAfter)) ? Math.max(0, Number(retryAfter) * 1_000)
      : Number.isFinite(Date.parse(retryAfter)) ? Math.max(0, Date.parse(retryAfter) - Date.now()) : undefined;
    throw Object.assign(new Error("OpenAI generation HTTP failure"), {
      status: response.status, name: quotaExhausted ? "AIQuotaExhaustedError" : "Error", retryAfterMilliseconds,
    });
  }
  const body = await response.json() as {
    status?: string; model?: string;
    output?: Array<{ type?: string; content?: Array<{ type?: string; text?: string }> }>;
    usage?: { input_tokens?: number; output_tokens?: number };
  };
  // Refusals/incomplete output remain failures of the caller's exact validator.
  const text = body.status === "completed" && Array.isArray(body.output) ? body.output
    .filter((item) => item.type === "message")
    .flatMap((item) => Array.isArray(item.content) ? item.content : [])
    .filter((item) => item.type === "output_text" && typeof item.text === "string")
    .map((item) => item.text ?? "").join("") : undefined;
  return { text, modelVersion: body.model, usageMetadata: { promptTokenCount: body.usage?.input_tokens, candidatesTokenCount: body.usage?.output_tokens } };
}
