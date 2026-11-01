import type { ActivityRoutePoint } from "./activityRouteCodec.js";

type ActivitySplit = {
  number: number;
  timeSeconds: number;
  distanceMeters: number;
  elevationChangeM: number | null;
};

// Compute before map simplification: preview point spacing carries no timing information.
// Match stored iOS splits, including pause boundaries, interpolated edges, and >20 m tails.
export function activitySplits(points: ActivityRoutePoint[], splitMeters: number): ActivitySplit[] {
  const splits: ActivitySplit[] = [];
  let distance = 0;
  let seconds = 0;
  let elevation = 0;
  let hasElevation = false;
  const append = () => {
    splits.push({
      number: splits.length + 1,
      timeSeconds: seconds,
      distanceMeters: distance,
      elevationChangeM: hasElevation ? elevation : null,
    });
    distance = 0;
    seconds = 0;
    elevation = 0;
    hasElevation = false;
  };
  for (let i = 1; i < points.length; i++) {
    const start = points[i - 1];
    const end = points[i];
    if (end.startsNewSegment) continue;
    if (![start, end].every((point) => Number.isFinite(point.latitude)
      && Number.isFinite(point.longitude) && Math.abs(point.latitude) <= 90
      && Math.abs(point.longitude) <= 180)) continue;
    const radians = Math.PI / 180;
    const a = Math.sin((end.latitude - start.latitude) * radians / 2) ** 2
      + Math.cos(start.latitude * radians) * Math.cos(end.latitude * radians)
      * Math.sin((end.longitude - start.longitude) * radians / 2) ** 2;
    const edgeDistance = 6_371_000 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(Math.max(0, 1 - a)));
    const edgeSeconds = Math.max(0, (Date.parse(end.timestamp) - Date.parse(start.timestamp)) / 1000);
    if (!(edgeDistance > 0) || !Number.isFinite(edgeDistance) || !Number.isFinite(edgeSeconds)) continue;
    let consumed = 0;
    while (consumed < edgeDistance) {
      const portion = Math.min(edgeDistance - consumed, splitMeters - distance);
      distance += portion;
      seconds += edgeSeconds * portion / edgeDistance;
      if (start.altitude != null && end.altitude != null
        && Number.isFinite(start.altitude) && Number.isFinite(end.altitude)) {
        elevation += (end.altitude - start.altitude) * portion / edgeDistance;
        hasElevation = true;
      }
      consumed += portion;
      if (distance >= splitMeters - 0.001) append();
    }
  }
  if (distance > 20) append();
  return splits;
}
