import { generateWithOpenAI, type StructuredAIResponse } from "./openaiGeneration.js";
import { GoogleGenAI, type GenerateContentParameters } from "@google/genai";

export type AIOperation = "assistant" | "live_coach" | "plan_intake" | "plan_adjustment";
export type AIFailureCategory = "rate_limited" | "timeout" | "server" | "network" | "authentication" | "invalid_request" | "invalid_output" | "circuit_open" | "quota_exhausted";
type ValidationCategory = "json" | "schema" | "moment_coverage" | "instruction_coverage" | "distinct_phrases" | "phrase_bounds" | "product_validation" | "unknown";
export class AIGenerationError extends Error {
  constructor(readonly category: AIFailureCategory, readonly status?: number, readonly validation?: ValidationCategory, readonly retryAfterMilliseconds?: number) {
    super(`AI generation failed (${category}${status ? `, HTTP ${status}` : ""})`);
    this.name = "AIGenerationError";
  }
}

type Circuit = { failures: number; firstFailureAt: number; openUntil: number; probeInFlight: boolean };
const circuits = new Map<string, Circuit>();
const failureWindow = 60_000;
const cooldown = 30_000;

export function aiFailure(error: unknown): AIGenerationError {
  if (error instanceof AIGenerationError) return error;
  const status = error instanceof Error && "status" in error && typeof error.status === "number" ? error.status : undefined;
  if (error instanceof Error && error.name === "AIQuotaExhaustedError") return new AIGenerationError("quota_exhausted", status);
  const retryAfterMilliseconds = error instanceof Error && "retryAfterMilliseconds" in error
    && typeof error.retryAfterMilliseconds === "number" && Number.isFinite(error.retryAfterMilliseconds)
    && error.retryAfterMilliseconds >= 0 ? error.retryAfterMilliseconds : undefined;
  if (status === 429) return new AIGenerationError("rate_limited", status, undefined, retryAfterMilliseconds);
  if (status === 408 || status === 504 || error instanceof Error && ["AbortError", "TimeoutError"].includes(error.name)) return new AIGenerationError("timeout", status);
  if (status && status >= 500) return new AIGenerationError("server", status, undefined, retryAfterMilliseconds);
  if (status === 401 || status === 403) return new AIGenerationError("authentication", status);
  if (status) return new AIGenerationError("invalid_request", status);
  return new AIGenerationError("network");
}

function invalidOutput(error: unknown): AIGenerationError {
  // Only closed classifications leave this function, never raw exception text.
  const known: Record<string, ValidationCategory> = {
    "Planner moments did not match the requested workout scope.": "moment_coverage",
    "Planner workout instructions did not match the selected workout.": "instruction_coverage",
    "Live-coach planner repeated a phrase across moments.": "distinct_phrases",
    "Planner phrase failed semantic validation.": "phrase_bounds",
  };
  const validation = error instanceof SyntaxError ? "json"
    : error instanceof Error && error.name === "ZodError" ? "schema"
    : error instanceof Error && error.name === "AIProviderError" ? "product_validation"
    : error instanceof Error ? known[error.message] ?? "unknown" : "unknown";
  return new AIGenerationError("invalid_output", undefined, validation);
}

function transient(error: AIGenerationError) {
  return ["rate_limited", "timeout", "server", "network"].includes(error.category);
}

function allowCircuit(key: string) {
  const state = circuits.get(key);
  if (!state || !state.openUntil) return true;
  if (Date.now() < state.openUntil || state.probeInFlight) return false;
  state.probeInFlight = true;
  return true;
}

function finishCircuit(key: string, error?: AIGenerationError) {
  if (!error || !transient(error)) { circuits.delete(key); return; }
  const now = Date.now();
  const prior = circuits.get(key);
  const state = prior && now - prior.firstFailureAt <= failureWindow
    ? prior : { failures: 0, firstFailureAt: now, openUntil: 0, probeInFlight: false };
  state.failures += 1;
  if (state.failures >= 3 || prior?.probeInFlight) state.openUntil = now + cooldown;
  state.probeInFlight = false;
  if (circuits.size >= 16 && !circuits.has(key)) circuits.delete(circuits.keys().next().value!);
  circuits.set(key, state);
}

function diagnostic(event: string, fields: Record<string, unknown>) {
  // One JSON line lets Cloud Logging correlate status with operation. Never add
  // prompts, response/error bodies, account IDs, or caller-provided strings here.
  console.info(JSON.stringify({ event, ...fields }));
}

export async function generateStructuredAI<T>(options: {
  operation: AIOperation;
  model: string;
  parameters: Omit<GenerateContentParameters, "model">;
  deadlineMilliseconds: number;
  validate: (response: StructuredAIResponse) => T;
  connection?: { apiKey?: string; project?: string; location?: string };
  // Internal benchmark overrides are never accepted from HTTP request bodies.
  policy?: { fallbackModel?: string | null; primaryAttempts?: 1 | 2; circuit?: boolean };
}): Promise<{ value: T; response: StructuredAIResponse; model: string }> {
  const startedAt = Date.now();
  const deadline = startedAt + options.deadlineMilliseconds;
  const connection = options.connection ?? {
    apiKey: process.env.GEMINI_API_KEY,
    project: process.env.GEMINI_VERTEX_PROJECT_ID || process.env.GOOGLE_CLOUD_PROJECT,
    location: process.env.GEMINI_VERTEX_LOCATION || "global",
  };
  if (!options.model.startsWith("gpt-") && !connection.apiKey && !connection.project) {
    diagnostic("ai_generation", { operation: options.operation, outcome: "failure", category: "authentication", attempts: 0, elapsed_ms: Date.now() - startedAt });
    throw new AIGenerationError("authentication");
  }
  const benchmark = process.env.AI_RELIABILITY_BENCHMARK === "true";
  const circuitEnabled = options.policy?.circuit ?? !benchmark;
  const parentSignal = options.parameters.config?.abortSignal;
  if (parentSignal?.aborted) throw new DOMException("Canceled", "AbortError");
  const fallback = options.policy?.fallbackModel !== undefined ? options.policy.fallbackModel
    : process.env.AI_FALLBACK_VALIDATED === "true" && ["assistant", "live_coach"].includes(options.operation) ? process.env.AI_FALLBACK_MODEL?.trim() || "gemini-3.6-flash" : null;
  const models = [...new Set([options.model, ...(fallback ? [fallback] : [])])];
  let gemini: GoogleGenAI | undefined;
  let lastError = new AIGenerationError("circuit_open");
  let totalAttempts = 0;
  for (const [routeIndex, model] of models.entries()) {
    const routeDeadline = routeIndex === 0 && models.length > 1
      ? Math.min(deadline, startedAt + Math.floor(options.deadlineMilliseconds * 0.45)) : deadline;
    const attempts = routeIndex === 0 ? options.policy?.primaryAttempts ?? (benchmark ? 1 : 2) : 1;
    const key = model.startsWith("gpt-") ? `openai:${model}` : `${connection.project || "api-key"}:${connection.location || "global"}:${model}`;
    for (let attempt = 0; attempt < attempts; attempt++) {
      if (parentSignal?.aborted) throw new DOMException("Canceled", "AbortError");
      const remaining = routeDeadline - Date.now();
      if (remaining < 250) break;
      if (circuitEnabled && !allowCircuit(key)) {
        lastError = new AIGenerationError("circuit_open");
        diagnostic("ai_attempt", { operation: options.operation, model, outcome: "failure", category: "circuit_open", route: routeIndex === 0 ? "primary" : "fallback" });
        break;
      }
      const controller = new AbortController();
      const abort = () => controller.abort();
      parentSignal?.addEventListener("abort", abort, { once: true });
      const timer = setTimeout(abort, remaining);
      let rejectAbort: (() => void) | undefined;
      const attemptStartedAt = Date.now();
      totalAttempts += 1;
      try {
        const canceled = new Promise<never>((_, reject) => {
          rejectAbort = () => reject(new DOMException("Generation deadline elapsed", "AbortError"));
          controller.signal.addEventListener("abort", rejectAbort, { once: true });
        });
        const request = model.startsWith("gpt-")
          ? generateWithOpenAI(model, options.parameters, controller.signal)
          : (gemini ??= connection.apiKey ? new GoogleGenAI({ apiKey: connection.apiKey, apiVersion: "v1beta" })
            : new GoogleGenAI({ vertexai: true, project: connection.project, location: connection.location || "global", apiVersion: "v1beta1" }))
            .models.generateContent({
              ...options.parameters, model,
              config: { ...options.parameters.config, abortSignal: controller.signal,
                httpOptions: { ...options.parameters.config?.httpOptions, retryOptions: { attempts: 1 } } },
            });
        const response = await Promise.race([request, canceled]);
        let value: T;
        try { value = options.validate(response); }
        catch (error) { throw invalidOutput(error); }
        if (circuitEnabled) finishCircuit(key);
        diagnostic("ai_attempt", { operation: options.operation, model, outcome: "success", elapsed_ms: Date.now() - attemptStartedAt, route: routeIndex === 0 ? "primary" : "fallback" });
        diagnostic("ai_generation", { operation: options.operation, model, outcome: "success", fallback: routeIndex > 0, attempts: totalAttempts, elapsed_ms: Date.now() - startedAt });
        return { value, response, model };
      } catch (error) {
        if (parentSignal?.aborted) {
          // A canceled half-open probe must not permanently lock the circuit.
          const circuit = circuitEnabled ? circuits.get(key) : undefined;
          if (circuit) circuit.probeInFlight = false;
          throw new DOMException("Canceled", "AbortError");
        }
        lastError = aiFailure(error);
        if (circuitEnabled) finishCircuit(key, lastError);
        diagnostic("ai_attempt", { operation: options.operation, model, outcome: "failure", category: lastError.category, status: lastError.status, validation: lastError.validation, elapsed_ms: Date.now() - attemptStartedAt, route: routeIndex === 0 ? "primary" : "fallback" });
        // Configuration errors affect every model at the same provider. A
        // separately validated provider can still recover without retrying.
        const hasIndependentAlternate = models.slice(routeIndex + 1).some((alternate) => alternate.startsWith("gpt-") !== model.startsWith("gpt-"));
        if (["authentication", "invalid_request", "quota_exhausted"].includes(lastError.category) && lastError.status !== 404 && !hasIndependentAlternate) {
          diagnostic("ai_generation", { operation: options.operation, outcome: "failure", category: lastError.category, status: lastError.status, attempts: totalAttempts, elapsed_ms: Date.now() - startedAt });
          throw lastError;
        }
        if (!transient(lastError) || lastError.category === "timeout" || attempt + 1 >= attempts) break;
      } finally {
        clearTimeout(timer);
        parentSignal?.removeEventListener("abort", abort);
        if (rejectAbort) controller.signal.removeEventListener("abort", rejectAbort);
      }
      const delay = Math.max(250 + Math.floor(Math.random() * 250), lastError.retryAfterMilliseconds ?? 0);
      if (routeDeadline - Date.now() < delay + 250) break;
      await new Promise((resolve) => setTimeout(resolve, delay));
    }
  }
  diagnostic("ai_generation", { operation: options.operation, outcome: "failure", category: lastError.category, status: lastError.status, attempts: totalAttempts, elapsed_ms: Date.now() - startedAt });
  throw lastError;
}
