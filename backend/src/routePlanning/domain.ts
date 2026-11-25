export type Coordinate = { latitude: number; longitude: number };
export type GenerateLoop = { start: Coordinate; via?: Coordinate; targetDistanceM: number; activityType: "running" | "walking" | "hiking" | "cycling"; variationSeed?: number; preference?: "balanced" | "less_climbing" };
export type CanonicalRoute = { points: (Coordinate & { altitude?: number })[]; distanceM: number; elevationGainM?: number; attribution: string };
export type Candidate = CanonicalRoute & { id: string; deviationFraction: number; requestedStart: Coordinate; snappedStart: Coordinate };
export interface RoutingProvider { generate(request: GenerateLoop, attempt: number, signal: AbortSignal): Promise<CanonicalRoute | null> }
export function distance(a: Coordinate, b: Coordinate): number {
  const r = Math.PI / 180;
  const h = Math.sin((b.latitude-a.latitude)*r/2)**2 + Math.cos(a.latitude*r)*Math.cos(b.latitude*r)*Math.sin((b.longitude-a.longitude)*r/2)**2;
  return 6371000 * 2 * Math.asin(Math.min(1, Math.sqrt(h)));
}

export type ProviderFailureCategory = "authorization" | "quota" | "configuration" | "upstream" | "timeout" | "transport" | "invalid_response";
export class RoutingProviderError extends Error {
  constructor(readonly category: ProviderFailureCategory, readonly terminal = false, readonly status?: number) {
    super(category);
    this.name = "RoutingProviderError";
  }
}

export class RouteGenerationCancelled extends Error {
  constructor() {
    super("Route generation cancelled");
    this.name = "RouteGenerationCancelled";
  }
}
