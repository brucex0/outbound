import type { AIProviderKey } from "./types.js";

type CircuitState = {
  consecutiveFailures: number;
  openUntil: number | null;
  lastSuccessAt: number | null;
};

const states = new Map<string, CircuitState>();
const failureThreshold = 3;
const coolDownMilliseconds = 60_000;

export function isRouteHealthy(providerKey: AIProviderKey, endpointKey: string, now = Date.now()): boolean {
  const state = states.get(routeKey(providerKey, endpointKey));
  if (!state?.openUntil) return true;
  return state.openUntil <= now;
}

export function recordRouteSuccess(providerKey: AIProviderKey, endpointKey: string, now = Date.now()): void {
  states.set(routeKey(providerKey, endpointKey), {
    consecutiveFailures: 0,
    openUntil: null,
    lastSuccessAt: now,
  });
}

export function recordRouteFailure(providerKey: AIProviderKey, endpointKey: string, now = Date.now()): void {
  const key = routeKey(providerKey, endpointKey);
  const current = states.get(key) ?? { consecutiveFailures: 0, openUntil: null, lastSuccessAt: null };
  const consecutiveFailures = current.consecutiveFailures + 1;
  states.set(key, {
    consecutiveFailures,
    openUntil: consecutiveFailures >= failureThreshold ? now + coolDownMilliseconds : null,
    lastSuccessAt: current.lastSuccessAt,
  });
}

function routeKey(providerKey: AIProviderKey, endpointKey: string): string {
  return `${providerKey}:${endpointKey}`;
}
