import { randomUUID } from "node:crypto";
import { RouteGenerationCancelled, RoutingProviderError, distance, type Candidate, type GenerateLoop, type RoutingProvider } from "./domain.js";
// Resample at metric intervals before corridor comparison so provider vertex
// density cannot change duplication or backtracking decisions.
function corridor(points: Candidate["points"], reference: GenerateLoop["start"]): string[] {
  const result: string[] = [];
  const cell = (p: typeof reference) => `${Math.floor((((p.longitude-reference.longitude+540)%360)-180) * 111320 * Math.cos(reference.latitude * Math.PI / 180) / 50)},${Math.floor((p.latitude-reference.latitude) * 111320 / 50)}`;
  let carried = 0;
  result.push(cell(points[0]));
  for (let i = 1; i < points.length; i++) {
    const length = distance(points[i-1], points[i]);
    for (let at = 25-carried; at <= length; at += 25) {
      const t = at / length;
      const key = cell({ latitude: points[i-1].latitude + t * (points[i].latitude-points[i-1].latitude), longitude: points[i-1].longitude + t * (points[i].longitude-points[i-1].longitude) });
      if (result.at(-1) !== key) result.push(key);
    }
    carried = (carried + length) % 25;
  }
  return result;
}
export async function generateLoops(request: GenerateLoop, provider: RoutingProvider, signal: AbortSignal): Promise<Candidate[]> {
  const started = Date.now();
  const counts = { calls: 0, noRoute: 0, providerFailures: 0, invalidGeometry: 0, distance: 0, closure: 0, start: 0, via: 0, backtrack: 0, duplicate: 0 };
  const accepted: { route: Candidate; cells: Set<string>; backtrack: number }[] = [];
  let failure: RoutingProviderError | undefined;
  const budget = AbortSignal.any([signal, AbortSignal.timeout(25000)]);
  const callerCancelled = () => signal.aborted && budget.reason === signal.reason;
  try {
    if (callerCancelled()) throw new RouteGenerationCancelled();
    if (request.via && 2 * distance(request.start, request.via) > request.targetDistanceM * 1.1) {
      counts.noRoute++;
      return [];
    }
    for (let attempt = 0; attempt < 6 && !budget.aborted && accepted.length < 3; attempt++) {
      let result;
      counts.calls++;
      try { result = await provider.generate(request, attempt, budget); }
      catch (error) {
        if (callerCancelled()) throw new RouteGenerationCancelled();
        failure = error instanceof RoutingProviderError ? error : new RoutingProviderError(budget.aborted ? "timeout" : "transport");
        counts.providerFailures++;
        console.error("route_planning attempt_failed", { category: failure.category, ...(failure.status !== undefined ? { status: failure.status } : {}) });
        if (budget.aborted || failure.terminal) break;
        continue;
      }
      if (!result) { counts.noRoute++; continue; }
      if (!Number.isFinite(result.distanceM) || result.distanceM <= 0 || result.points.length < 3 || result.points.some(p => !Number.isFinite(p.latitude) || !Number.isFinite(p.longitude) || Math.abs(p.latitude) > 90 || Math.abs(p.longitude) > 180)) { counts.invalidGeometry++; continue; }
      if (Math.abs(result.distanceM / request.targetDistanceM - 1) > 0.1) { counts.distance++; continue; }
      const first = result.points[0], last = result.points.at(-1)!;
      if (distance(first, last) > 100) { counts.closure++; continue; }
      if (distance(request.start, first) > 250) { counts.start++; continue; }
      if (request.via && !result.points.some(p => distance(p, request.via!) <= 100)) { counts.via++; continue; }
      const route: Candidate = { ...result, id: randomUUID(), deviationFraction: result.distanceM / request.targetDistanceM - 1, requestedStart: request.start, snappedStart: first };
      const all = corridor(route.points, request.start), cells = new Set(all), backtrack = 1 - cells.size / Math.max(1, all.length);
      if (backtrack >= 0.45) { counts.backtrack++; continue; }
      if (accepted.some(old => [...cells].filter(c => old.cells.has(c)).length / Math.max(1, Math.min(cells.size, old.cells.size)) > 0.8)) { counts.duplicate++; continue; }
      accepted.push({ route, cells, backtrack });
    }
    if (callerCancelled()) throw new RouteGenerationCancelled();
    if (accepted.length === 0 && budget.aborted) throw new RoutingProviderError("timeout");
    // Empty success requires actual provider evidence of no suitable route.
    if (accepted.length === 0 && failure) throw failure;
    if (accepted.length === 0 && counts.invalidGeometry > 0) throw new RoutingProviderError("invalid_response");
  } finally {
    console.info("route_planning generation_outcome", { outcome: callerCancelled() ? "cancelled" : accepted.length ? (failure || budget.aborted ? "partial" : "success") : (failure || budget.aborted || counts.invalidGeometry ? "unavailable" : "no_match"), accepted: accepted.length, ...counts, elapsedMs: Date.now() - started });
  }
  return accepted.sort((a,b) => {
    if (request.preference === "less_climbing") {
      const gain = (a.route.elevationGainM ?? Infinity) - (b.route.elevationGainM ?? Infinity);
      if (gain && !Number.isNaN(gain)) return gain;
    }
    return a.backtrack - b.backtrack || Math.abs(a.route.deviationFraction) - Math.abs(b.route.deviationFraction);
  }).slice(0,3).map(c => c.route);
}
