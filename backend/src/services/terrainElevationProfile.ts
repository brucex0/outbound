/** Distance-based terrain processing; independent of recording pace/sample cadence. */
export type TerrainRoutePoint = {
  latitude: number;
  longitude: number;
  startsNewSegment: boolean;
};

const SAMPLE_SPACING_METERS = 20;
const MAXIMUM_SAMPLES = 20_000;
const SMOOTHING_RADIUS_METERS = 40;
const MINIMUM_CLIMB_METERS = 3;

export function routeDistance(a: TerrainRoutePoint, b: TerrainRoutePoint): number {
  const radians = Math.PI / 180;
  const latitude = (b.latitude - a.latitude) * radians;
  const longitude = (b.longitude - a.longitude) * radians;
  const h = Math.sin(latitude / 2) ** 2
    + Math.cos(a.latitude * radians) * Math.cos(b.latitude * radians) * Math.sin(longitude / 2) ** 2;
  return 6_371_000 * 2 * Math.asin(Math.sqrt(Math.min(1, h)));
}

/** Keep an index/fraction for every input point so the API preserves its input shape. */
export function resampleTerrainRoute(input: TerrainRoutePoint[]) {
  const points: TerrainRoutePoint[] = [];
  const positions: { lower: number; upper: number; fraction: number }[] = [];
  let start = 0;
  for (let end = 1; end <= input.length; end++) {
    if (end < input.length && !input[end].startsNewSegment) continue;
    const distances = [0];
    for (let i = start + 1; i < end; i++) {
      distances.push(distances.at(-1)! + routeDistance(input[i - 1], input[i]));
    }
    const length = distances.at(-1)!;
    const count = Math.max(1, Math.ceil((length - 1e-6) / SAMPLE_SPACING_METERS));
    if (points.length + count + 1 > MAXIMUM_SAMPLES) throw new Error("terrain_route_too_large");
    const offset = points.length;
    let edge = 1;
    for (let sample = 0; sample <= count; sample++) {
      const distance = sample === count ? length : sample * SAMPLE_SPACING_METERS;
      while (edge < distances.length - 1 && distances[edge] < distance) edge++;
      const lower = Math.max(0, edge - 1);
      const upper = Math.min(edge, distances.length - 1);
      const span = distances[upper] - distances[lower];
      const fraction = span > 0 ? (distance - distances[lower]) / span : 0;
      const a = input[start + lower];
      const b = input[start + upper];
      const longitudeDelta = ((b.longitude - a.longitude + 540) % 360) - 180;
      points.push({
        latitude: a.latitude + (b.latitude - a.latitude) * fraction,
        longitude: ((a.longitude + longitudeDelta * fraction + 540) % 360) - 180,
        startsNewSegment: sample === 0,
      });
    }
    for (const distance of distances) {
      const lower = Math.min(count - 1, Math.floor(distance / SAMPLE_SPACING_METERS));
      const upperDistance = lower + 1 === count ? length : (lower + 1) * SAMPLE_SPACING_METERS;
      const span = upperDistance - lower * SAMPLE_SPACING_METERS;
      positions.push({ lower: offset + lower, upper: offset + lower + 1,
        fraction: span > 0 ? (distance - lower * SAMPLE_SPACING_METERS) / span : 0 });
    }
    start = end;
  }
  return { points, positions };
}

export function smoothTerrainProfile(elevations: number[], points: TerrainRoutePoint[]): number[] {
  const result: number[] = [];
  let start = 0;
  for (let end = 1; end <= points.length; end++) {
    if (end < points.length && !points[end].startsNewSegment) continue;
    const distances = [0];
    for (let i = start + 1; i < end; i++) {
      distances.push(distances.at(-1)! + routeDistance(points[i - 1], points[i]));
    }
    // A local median removes isolated spikes; endpoints are retained so a short
    // monotonic climb/descent isn't shortened just because recording stopped.
    const median = elevations.slice(start, end).map((value, i, values) => {
      if (i === 0 || i === values.length - 1) return value;
      return [values[i - 1], value, values[i + 1]].sort((a, b) => a - b)[1];
    });
    for (let i = 0; i < median.length; i++) {
      if (i === 0 || i === median.length - 1) { result.push(median[i]); continue; }
      let total = 0;
      let weights = 0;
      for (let j = Math.max(0, i - 3); j <= Math.min(median.length - 1, i + 3); j++) {
        const weight = Math.max(0, 1 - Math.abs(distances[j] - distances[i]) / SMOOTHING_RADIUS_METERS);
        total += median[j] * weight;
        weights += weight;
      }
      result.push(total / weights);
    }
    start = end;
  }
  return result;
}

/** Directional hysteresis: descending terrain must never create a climb. */
export function terrainElevationGain(elevations: number[], points: TerrainRoutePoint[]): number {
  if (elevations.length < 2) return 0;
  let total = 0;
  let floor = elevations[0];
  let peak = floor;
  let climbing = false;
  const finish = () => { if (climbing) total += peak - floor; };
  for (let i = 1; i < elevations.length; i++) {
    const altitude = elevations[i];
    if (points[i].startsNewSegment) {
      finish(); floor = altitude; peak = altitude; climbing = false;
    } else if (!climbing) {
      floor = Math.min(floor, altitude);
      if (altitude - floor >= MINIMUM_CLIMB_METERS) { peak = altitude; climbing = true; }
    } else if (altitude > peak) {
      peak = altitude;
    } else if (peak - altitude >= MINIMUM_CLIMB_METERS) {
      finish(); floor = altitude; peak = altitude; climbing = false;
    }
  }
  finish();
  return total;
}
