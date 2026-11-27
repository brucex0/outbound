import { RoutingProviderError, distance, type CanonicalRoute, type GenerateLoop, type RoutingProvider } from "./domain.js";
export class OpenRouteService implements RoutingProvider {
  constructor(private readonly key: string, private readonly base = "https://api.heigit.org/openrouteservice") {}
  private viaVariant = 0;
  private viaCalls = 0;
  private viaPerimeter?: number;
  private seedOffset = 0;
  private seedCalls = 0;
  private proposedLength?: number;
  async generate(request: GenerateLoop, attempt: number, signal: AbortSignal): Promise<CanonicalRoute | null> {
    const profile = request.activityType === "hiking" ? "foot-hiking" : "foot-walking";
    const pair = (p: { latitude: number; longitude: number }) => [p.longitude, p.latitude];
    let coordinates = [pair(request.start)];
    let options: object = { round_trip: { length: this.proposedLength ?? request.targetDistanceM, points: 3, seed: ((request.variationSeed ?? 0) + this.seedOffset) % 1000000 + 1 } };
    // A required place already beside the start needs a normal loop, not two
    // degenerate out-and-back spokes. Canonical via validation still applies.
    const via = request.via && distance(request.start, request.via) > 50 ? request.via : undefined;
    if (via) {
      // Allocate the fixed start↔via baseline before shaping the remaining
      // length. Opposite sides give outbound and return legs distinct corridors.
      const baseline = distance(request.start, via);
      const proposal = this.viaPerimeter ?? request.targetDistanceM;
      const halfBaseline = baseline / 2;
      const height = Math.sqrt(Math.max(0, (proposal / 4) ** 2 - halfBaseline ** 2));
      const bearing = Math.atan2(
        (((via.longitude - request.start.longitude + 540) % 360) - 180) * Math.cos(request.start.latitude * Math.PI / 180),
        via.latitude - request.start.latitude);
      const skew = [0, -0.2, 0.2][this.viaVariant % 3] + ((request.variationSeed ?? 0) % 7) * 0.03;
      const offset = (side: number) => {
        const along = halfBaseline + side * skew * baseline;
        const north = along * Math.cos(bearing) - side * height * Math.sin(bearing);
        const east = along * Math.sin(bearing) + side * height * Math.cos(bearing);
        return { latitude: request.start.latitude + north / 111320,
          longitude: ((request.start.longitude + east / (111320 * Math.max(0.1, Math.cos(request.start.latitude * Math.PI / 180))) + 540) % 360) - 180 };
      };
      const reverse = ((request.variationSeed ?? 0) + this.viaVariant) % 2 === 0 ? 1 : -1;
      coordinates = [pair(request.start), pair(offset(reverse)), pair(via), pair(offset(-reverse)), pair(request.start)]; options = {};
    }
    let response: Response;
    try {
      response = await fetch(`${this.base.replace(/\/$/, "")}/v2/directions/${profile}/geojson`, {
        method: "POST", headers: { Authorization: this.key, "Content-Type": "application/json" },
        body: JSON.stringify({ coordinates, options, elevation: true, instructions: false }),
        signal: AbortSignal.any([signal, AbortSignal.timeout(8000)]),
      });
    } catch (error) {
      const category = signal.aborted || (error instanceof Error && ["AbortError", "TimeoutError"].includes(error.name)) ? "timeout" : "transport";
      throw new RoutingProviderError(category);
    }
    if (!response.ok) {
      if (response.status === 401 || response.status === 403) throw new RoutingProviderError("authorization", true, response.status);
      if (response.status === 429) throw new RoutingProviderError("quota", true, response.status);
      // ORS documents 2009 as no route and 2010 as no routable point.
      // Do not interpret an arbitrary 404 (wrong service URL) as no route.
      if (response.status === 400 || response.status === 404) {
        const body = await response.json().catch(() => null) as { error?: { code?: number } } | null;
        if (body?.error?.code === 2009 || body?.error?.code === 2010) {
          if (via) this.advanceVia(); else this.advanceSeed();
          return null;
        }
      }
      throw new RoutingProviderError(response.status >= 500 ? "upstream" : "configuration", response.status < 500, response.status);
    }
    const payload = await response.json().catch(() => { throw new RoutingProviderError("invalid_response"); }) as { metadata?: { attribution?: string }; features?: { geometry?: { coordinates?: unknown }; properties?: { ascent?: number; summary?: { ascent?: number } } }[] };
    if (!payload || typeof payload !== "object") throw new RoutingProviderError("invalid_response");
    const raw = payload.features?.[0]?.geometry?.coordinates;
    if (!Array.isArray(raw) || raw.length < 3 || raw.length > 100000) throw new RoutingProviderError("invalid_response");
    const points = raw.map((p: unknown) => {
      if (!Array.isArray(p) || !Number.isFinite(p[0]) || !Number.isFinite(p[1]) || Math.abs(p[0]) > 180 || Math.abs(p[1]) > 90) throw new RoutingProviderError("invalid_response");
      return { longitude: p[0] as number, latitude: p[1] as number, ...(Number.isFinite(p[2]) ? { altitude: p[2] as number } : {}) };
    });
    const distanceM = points.slice(1).reduce((sum, point, i) => sum + distance(points[i], point), 0);
    if (via && distanceM > 0) {
      this.viaCalls++;
      if (Math.abs(distanceM / request.targetDistanceM - 1) > 0.1 && this.viaCalls < 2) {
        // Retry this shape immediately, deriving width from corrected perimeter
        // only after allowing for the baseline that cannot shrink.
        const baseline = 2 * distance(request.start, via);
        const proposed = this.viaPerimeter ?? request.targetDistanceM;
        this.viaPerimeter = Math.max(baseline, Math.min(request.targetDistanceM * 1.5,
          proposed * request.targetDistanceM / distanceM));
      } else this.advanceVia();
    }
    if (!via) {
      this.seedCalls++;
      if (distanceM > 0 && Math.abs(distanceM / request.targetDistanceM - 1) > 0.1 && this.seedCalls < 2) {
        // Correct the provider proposal, never the acceptance target or geometry.
        const proposed = this.proposedLength ?? request.targetDistanceM;
        this.proposedLength = Math.max(request.targetDistanceM * 0.5, Math.min(request.targetDistanceM * 1.5, proposed * request.targetDistanceM / distanceM));
      } else this.advanceSeed();
    }
    const ascent = payload.features?.[0]?.properties?.ascent ?? payload.features?.[0]?.properties?.summary?.ascent;
    return { points, distanceM, attribution: payload.metadata?.attribution?.slice(0,1000) || "© openrouteservice by HeiGIT | Data from OpenStreetMap", ...(typeof ascent === "number" && Number.isFinite(ascent) && ascent >= 0 ? { elevationGainM: ascent } : {}) };
  }
  private advanceVia(): void {
    this.viaVariant++;
    this.viaCalls = 0;
    this.viaPerimeter = undefined;
  }
  private advanceSeed(): void {
    this.seedOffset++;
    this.seedCalls = 0;
    this.proposedLength = undefined;
  }
}
