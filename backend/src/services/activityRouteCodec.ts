import type { Prisma } from "@prisma/client";

export type ActivityRoutePoint = {
  timestamp: string;
  latitude: number;
  longitude: number;
  altitude?: number | null;
  verticalAccuracy?: number | null;
  startsNewSegment?: boolean;
};

export type ActivityRouteMetadata = {
  visibility: string;
  elevationMetadata: Prisma.InputJsonValue | null;
};

const MAGIC = Buffer.from("PSRT");
const VERSION = 1;
const COORDINATE_SCALE = 1_000_000;
const ALTITUDE_SCALE = 10;
const MAX_ROUTE_POINTS = 100_000;

function zigZag(value: number): bigint {
  const signed = BigInt(Math.trunc(value));
  return signed >= 0n ? signed * 2n : -signed * 2n - 1n;
}

function unZigZag(value: bigint): number {
  const signed = (value & 1n) === 0n ? value / 2n : -(value / 2n) - 1n;
  return Number(signed);
}

function appendVarint(output: number[], value: bigint) {
  let remaining = value;
  while (remaining >= 0x80n) {
    output.push(Number((remaining & 0x7fn) | 0x80n));
    remaining >>= 7n;
  }
  output.push(Number(remaining));
}

function readVarint(payload: Uint8Array, offset: { value: number }): bigint {
  let result = 0n;
  let shift = 0n;
  while (offset.value < payload.length) {
    const byte = payload[offset.value++];
    result |= BigInt(byte & 0x7f) << shift;
    if ((byte & 0x80) === 0) return result;
    shift += 7n;
    if (shift > 70n) throw new Error("Activity route varint is too large.");
  }
  throw new Error("Activity route payload is truncated.");
}

function optionalInteger(value: number | null | undefined): bigint {
  return value == null || !Number.isFinite(value) ? 0n : zigZag(Math.round(value)) + 1n;
}

function decodeOptionalInteger(value: bigint): number | null {
  return value === 0n ? null : unZigZag(value - 1n);
}

function epochSeconds(value: string): number {
  const milliseconds = Date.parse(value);
  if (!Number.isFinite(milliseconds)) throw new Error("Activity route contains an invalid timestamp.");
  return Math.round(milliseconds / 1_000);
}

export function encodeActivityRoute(points: ActivityRoutePoint[]): Buffer {
  if (points.length < 2) return Buffer.alloc(0);
  if (points.length > MAX_ROUTE_POINTS) throw new Error("Activity route contains too many points.");

  const output = [...MAGIC, VERSION];
  appendVarint(output, BigInt(points.length));

  let previousLatitude = 0;
  let previousLongitude = 0;
  let previousTimestamp = 0;
  let previousAltitude: number | null = null;

  points.forEach((point, index) => {
    const latitude = Math.round(point.latitude * COORDINATE_SCALE);
    const longitude = Math.round(point.longitude * COORDINATE_SCALE);
    const timestamp = epochSeconds(point.timestamp);
    const altitude = point.altitude == null || !Number.isFinite(point.altitude)
      ? null
      : Math.round(point.altitude * ALTITUDE_SCALE);
    const verticalAccuracy = point.verticalAccuracy == null || !Number.isFinite(point.verticalAccuracy)
      ? null
      : Math.round(point.verticalAccuracy * ALTITUDE_SCALE);

    appendVarint(output, zigZag(index === 0 ? latitude : latitude - previousLatitude));
    appendVarint(output, zigZag(index === 0 ? longitude : longitude - previousLongitude));
    appendVarint(output, zigZag(index === 0 ? timestamp : timestamp - previousTimestamp));
    appendVarint(output, optionalInteger(altitude == null ? null : altitude - (previousAltitude ?? 0)));
    appendVarint(output, optionalInteger(verticalAccuracy));
    output.push(point.startsNewSegment ? 1 : 0);

    previousLatitude = latitude;
    previousLongitude = longitude;
    previousTimestamp = timestamp;
    previousAltitude = altitude;
  });

  return Buffer.from(output);
}

export function decodeActivityRoute(payload: Uint8Array): ActivityRoutePoint[] {
  if (payload.length === 0) return [];
  if (payload.length < MAGIC.length + 1 || !Buffer.from(payload.slice(0, 4)).equals(MAGIC)) {
    throw new Error("Unsupported activity route payload.");
  }
  if (payload[4] !== VERSION) throw new Error(`Unsupported activity route version: ${payload[4]}`);

  const offset = { value: 5 };
  const count = Number(readVarint(payload, offset));
  if (!Number.isSafeInteger(count) || count < 2 || count > MAX_ROUTE_POINTS) throw new Error("Invalid activity route point count.");

  const points: ActivityRoutePoint[] = [];
  let previousLatitude = 0n;
  let previousLongitude = 0n;
  let previousTimestamp = 0n;
  let previousAltitude: bigint | null = null;

  for (let index = 0; index < count; index++) {
    const latitude = previousLatitude + BigInt(unZigZag(readVarint(payload, offset)));
    const longitude = previousLongitude + BigInt(unZigZag(readVarint(payload, offset)));
    const timestamp = previousTimestamp + BigInt(unZigZag(readVarint(payload, offset)));
    const altitudeDelta = decodeOptionalInteger(readVarint(payload, offset));
    const verticalAccuracy = decodeOptionalInteger(readVarint(payload, offset));
    if (offset.value >= payload.length) throw new Error("Activity route payload is truncated.");
    const flags = payload[offset.value++];
    const altitude: bigint | null = altitudeDelta == null
      ? null
      : (previousAltitude ?? 0n) + BigInt(altitudeDelta);

    points.push({
      timestamp: new Date(Number(timestamp) * 1_000).toISOString(),
      latitude: Number(latitude) / COORDINATE_SCALE,
      longitude: Number(longitude) / COORDINATE_SCALE,
      altitude: altitude == null ? null : Number(altitude) / ALTITUDE_SCALE,
      verticalAccuracy: verticalAccuracy == null ? null : verticalAccuracy / ALTITUDE_SCALE,
      startsNewSegment: (flags & 1) !== 0,
    });
    previousLatitude = latitude;
    previousLongitude = longitude;
    previousTimestamp = timestamp;
    previousAltitude = altitude;
  }
  return points;
}

export function legacyGeoJSONToRoute(value: unknown): {
  points: ActivityRoutePoint[];
  metadata: ActivityRouteMetadata;
} | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const route = value as {
    geometry?: { coordinates?: unknown };
    properties?: {
      timestamps?: unknown;
      verticalAccuracy?: unknown;
      segmentStarts?: unknown;
      visibility?: unknown;
      elevationMetadata?: unknown;
    };
  };
  const coordinates = route.geometry?.coordinates;
  if (!Array.isArray(coordinates) || coordinates.length < 2) return null;
  const timestamps = Array.isArray(route.properties?.timestamps) ? route.properties.timestamps : [];
  const accuracy = Array.isArray(route.properties?.verticalAccuracy) ? route.properties.verticalAccuracy : [];
  const segmentStarts = Array.isArray(route.properties?.segmentStarts) ? route.properties.segmentStarts : [];
  const points: ActivityRoutePoint[] = [];
  for (let index = 0; index < coordinates.length; index++) {
    const coordinate = coordinates[index];
    if (!Array.isArray(coordinate) || typeof coordinate[0] !== "number" || typeof coordinate[1] !== "number") return null;
    const timestamp = typeof timestamps[index] === "string" ? timestamps[index] : new Date(0).toISOString();
    points.push({
      timestamp,
      longitude: coordinate[0],
      latitude: coordinate[1],
      altitude: typeof coordinate[2] === "number" ? coordinate[2] : null,
      verticalAccuracy: typeof accuracy[index] === "number" ? accuracy[index] : null,
      startsNewSegment: segmentStarts[index] === true || (index === 0 && segmentStarts.length === 0),
    });
  }
  return {
    points,
    metadata: {
      visibility: typeof route.properties?.visibility === "string" ? route.properties.visibility : "private",
      elevationMetadata: route.properties?.elevationMetadata && typeof route.properties.elevationMetadata === "object"
        ? route.properties.elevationMetadata as Prisma.InputJsonValue
        : null,
    },
  };
}

export function decodeStoredActivityRoute(payload: Uint8Array | null | undefined, metadata: unknown) {
  if (!payload || payload.length === 0) return null;
  let points: ActivityRoutePoint[];
  const first = payload[0];
  if (first === 123 || first === 91) {
    const legacy = legacyGeoJSONToRoute(JSON.parse(Buffer.from(payload).toString("utf8")));
    if (!legacy) return null;
    points = legacy.points;
    metadata = legacy.metadata;
  } else {
    points = decodeActivityRoute(payload);
  }
  const meta = metadata && typeof metadata === "object" && !Array.isArray(metadata)
    ? metadata as { visibility?: unknown; elevationMetadata?: unknown }
    : {};
  return {
    points,
    visibility: typeof meta.visibility === "string" ? meta.visibility : "private",
    elevationMetadata: meta.elevationMetadata ?? null,
  };
}

export function routeResponse(
  payload: Uint8Array | null | undefined,
  metadata: Partial<ActivityRouteMetadata> = {}
) {
  if (!payload || payload.length === 0) return null;
  const points = decodeActivityRoute(payload);
  return {
    points,
    visibility: metadata.visibility ?? "private",
    elevationMetadata: metadata.elevationMetadata ?? null,
  };
}
