import { randomUUID } from "node:crypto";
import { distance, type Candidate, type GenerateLoop, type RoutingProvider } from "./domain.js";
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
  if (request.via && 2 * distance(request.start, request.via) > request.targetDistanceM * 1.1) return [];
  const accepted: { route: Candidate; cells: Set<string>; backtrack: number }[] = [];
  for (let attempt = 0; attempt < 6 && !signal.aborted; attempt++) {
    let result;
    try { result = await provider.generate(request, attempt, signal); }
    catch (error) {
      if (signal.aborted) break;
      console.error("route_planning attempt_failed", { category: error instanceof Error ? error.name : "unknown" });
      if (error instanceof Error && error.message === "provider_unavailable") throw error;
      continue;
    }
    if (!result || !Number.isFinite(result.distanceM) || Math.abs(result.distanceM / request.targetDistanceM - 1) > 0.1) continue;
    const first = result.points[0], last = result.points.at(-1)!;
    if (distance(first, last) > 100 || distance(request.start, first) > 250) continue;
    if (request.via && !result.points.some(p => distance(p, request.via!) <= 100)) continue;
    const route: Candidate = { ...result, id: randomUUID(), deviationFraction: result.distanceM / request.targetDistanceM - 1, requestedStart: request.start, snappedStart: first };
    const all = corridor(route.points, request.start), cells = new Set(all), backtrack = 1 - cells.size / Math.max(1, all.length);
    if (backtrack >= 0.45 || accepted.some(old => [...cells].filter(c => old.cells.has(c)).length / Math.max(1, Math.min(cells.size, old.cells.size)) > 0.8)) continue;
    accepted.push({ route, cells, backtrack });
  }
  if (signal.aborted && accepted.length === 0) throw new Error("generation_timeout");
  return accepted.sort((a,b) => {
    if (request.preference === "less_climbing") {
      const gain = (a.route.elevationGainM ?? Infinity) - (b.route.elevationGainM ?? Infinity);
      if (gain && !Number.isNaN(gain)) return gain;
    }
    return a.backtrack - b.backtrack || Math.abs(a.route.deviationFraction) - Math.abs(b.route.deviationFraction);
  }).slice(0,3).map(c => c.route);
}
