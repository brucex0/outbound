export type AIProviderErrorCode =
  | "not_configured"
  | "not_eligible"
  | "rate_limited"
  | "deadline_exceeded"
  | "provider_unavailable"
  | "invalid_provider_output"
  | "budget_exhausted";

export class AIProviderError extends Error {
  constructor(
    readonly code: AIProviderErrorCode,
    message: string,
    readonly retryable = false
  ) {
    super(message);
    this.name = "AIProviderError";
  }
}

export function sanitizedProviderError(error: unknown): AIProviderError {
  if (error instanceof AIProviderError) return error;
  if (error instanceof DOMException && error.name === "AbortError") {
    return new AIProviderError("deadline_exceeded", "The AI provider deadline elapsed.", true);
  }
  return new AIProviderError("provider_unavailable", "The AI provider is unavailable.", true);
}
