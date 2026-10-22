import { routeDistance } from "./distance.js";
import { decodeStoredActivityRoute } from "../activityRouteCodec.js";
export const STATISTICS_VERSION = 1;
export const targets = [400, 1_000, 1_609.344, 5_000, 10_000, 16_093.44, 21_097.5, 42_195];
export type Fact = {
  version: number; id: string; title: string; startedAt: string; durationSeconds: number; distanceMeters: number;
  elevationGainMeters: number | null; averagePace: number | null; activityType: string; averageHeartRate: number | null;
  heartRateZoneSeconds: Record<string, number>; goalCompleted: boolean | null; windows: Record<string, number>;
  gearID: string | null; sourceKind: string; externalID: string | null; healthWorkoutID: string | null; sessionID: string | null;
};
type ActivityInput = { id: string; clientActivityId: string | null; title: string | null; startedAt: Date; durationSecs: number | null; distanceM: number | null; elevationM: number | null; type: string; avgHeartRate: number | null; avgPace: number | null; energyKilocalories: number | null; clientData: unknown; routeBlob: Uint8Array | null; routeMetadata: unknown };
export function activityFact(row: ActivityInput): Fact {
  const extras = (row.clientData ?? {}) as Record<string, any>;
  const windows: Record<string, number> = {};
  // Route geometry is examined only when deriving/rebuilding this activity's facts.
  if (row.type === "running") {
    const route = decodeStoredActivityRoute(row.routeBlob, row.routeMetadata);
    let distance = 0;
    let previous: { latitude: number; longitude: number } | undefined;
    const points = (route?.points ?? []).map(p => {
      if (previous) {
        distance += routeDistance(previous, p);
      }
      previous = p;
      return { distance, timestamp: Date.parse(p.timestamp) };
    }).sort((a, b) => a.timestamp - b.timestamp);
    for (const target of targets) {
      let end = 0, best = Infinity;
      for (let start = 0; start < points.length; start++) {
        while (end < points.length && points[end].distance < points[start].distance + target) end++;
        if (end === points.length) break;
        const seconds = (points[end].timestamp - points[start].timestamp) / 1_000;
        if (seconds > 0) best = Math.min(best, seconds);
      }
      if (Number.isFinite(best)) windows[String(target)] = Math.round(best);
    }
  }
  const goal = extras.goal;
  const value = goal?.kind === "distance" ? row.distanceM : goal?.kind === "time" ? row.durationSecs : goal?.kind === "calories" ? (row.energyKilocalories ?? extras.energyKilocalories) : null;
  return {
    version: STATISTICS_VERSION, id: row.clientActivityId ?? row.id, title: row.title ?? "", startedAt: row.startedAt.toISOString(),
    durationSeconds: row.durationSecs ?? 0, distanceMeters: row.distanceM ?? 0, elevationGainMeters: row.elevationM,
    activityType: row.type, averagePace: row.avgPace, averageHeartRate: extras.healthMetrics?.averageHeartRateBPM ?? row.avgHeartRate,
    heartRateZoneSeconds: Object.fromEntries((extras.heartRateZones?.zones ?? []).map((z: any) => [String(z.index), z.seconds])),
    goalCompleted: value != null && typeof goal?.value === "number" ? value >= goal.value * 0.98 : null,
    windows, gearID: extras.gear?.shoeID ?? null, sourceKind: extras.source?.kind ?? "outbound",
    externalID: extras.source?.externalID ?? null,
    healthWorkoutID: extras.recordingSession?.healthKitWorkoutExternalReference ?? null,
    sessionID: extras.recordingSession?.sessionUUID ?? null,
  };
}

export function identityColumns(fact: Fact) {
  return { importSourceKey: fact.externalID ? `${fact.sourceKind}:${fact.externalID}` : null, healthWorkoutExternalID: fact.healthWorkoutID, recordingSessionID: fact.sessionID?.toLowerCase() ?? null };
}
