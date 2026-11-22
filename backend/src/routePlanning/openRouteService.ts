import { distance, type CanonicalRoute, type GenerateLoop, type RoutingProvider } from "./domain.js";
export class OpenRouteService implements RoutingProvider {
  constructor(private readonly key: string, private readonly base = "https://api.heigit.org/openrouteservice") {}
  private readonly radii = new Map<number, number>();
  async generate(request: GenerateLoop, attempt: number, signal: AbortSignal): Promise<CanonicalRoute | null> {
    const profile = request.activityType === "hiking" ? "foot-hiking" : "foot-walking";
    const pair = (p: { latitude: number; longitude: number }) => [p.longitude, p.latitude];
    let coordinates = [pair(request.start)];
    let options: object = { round_trip: { length: request.targetDistanceM, points: 3, seed: ((request.variationSeed ?? 0) + attempt) % 1000000 + 1 } };
    if (request.via) {
      const variant = attempt % 3;
      const angle = (variant * 120 + (request.variationSeed ?? 0) % 120) * Math.PI / 180;
      const radius = this.radii.get(variant) ?? request.targetDistanceM / 4.5;
      const offset = (heading: number) => ({ latitude: request.start.latitude + radius * Math.cos(heading) / 111320,
        longitude: request.start.longitude + radius * Math.sin(heading) / (111320 * Math.max(0.1, Math.cos(request.start.latitude * Math.PI / 180))) });
      const waypoint = offset(angle), second = offset(angle + 2 * Math.PI / 3);
      coordinates = [pair(request.start), pair(request.via), pair(waypoint), pair(second), pair(request.start)]; options = {};
    }
    const response = await fetch(`${this.base.replace(/\/$/, "")}/v2/directions/${profile}/geojson`, {
      method: "POST", headers: { Authorization: this.key, "Content-Type": "application/json" },
      body: JSON.stringify({ coordinates, options, elevation: true, instructions: false }),
      signal: AbortSignal.any([signal, AbortSignal.timeout(8000)]),
    });
    if (!response.ok) {
      console.error("route_planning provider_failed", { status: response.status });
      if ([401,403,429].includes(response.status)) throw new Error("provider_unavailable");
      return null;
    }
    const payload = await response.json() as { metadata?: { attribution?: string }; features?: { geometry?: { coordinates?: unknown }; properties?: { ascent?: number; summary?: { ascent?: number } } }[] };
    const raw = payload.features?.[0]?.geometry?.coordinates;
    if (!Array.isArray(raw) || raw.length < 3 || raw.length > 100000) return null;
    const points = raw.map((p: unknown) => {
      if (!Array.isArray(p) || !Number.isFinite(p[0]) || !Number.isFinite(p[1]) || Math.abs(p[0]) > 180 || Math.abs(p[1]) > 90) throw new Error("provider_invalid_geometry");
      return { longitude: p[0] as number, latitude: p[1] as number, ...(Number.isFinite(p[2]) ? { altitude: p[2] as number } : {}) };
    });
    const distanceM = points.slice(1).reduce((sum, point, i) => sum + distance(points[i], point), 0);
    if (request.via && distanceM > 0) {
      const radius = this.radii.get(attempt % 3) ?? request.targetDistanceM / 4.5;
      this.radii.set(attempt % 3, Math.min(request.targetDistanceM / 2, Math.max(100, radius * request.targetDistanceM / distanceM)));
    }
    const ascent = payload.features?.[0]?.properties?.ascent ?? payload.features?.[0]?.properties?.summary?.ascent;
    return { points, distanceM, attribution: payload.metadata?.attribution?.slice(0,1000) || "© openrouteservice by HeiGIT | Data from OpenStreetMap", ...(typeof ascent === "number" && Number.isFinite(ascent) && ascent >= 0 ? { elevationGainM: ascent } : {}) };
  }
}
