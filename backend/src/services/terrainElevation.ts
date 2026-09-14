import { PNG } from "pngjs";

const TERRAIN_TILE_ZOOM = 14;
const TILE_SIZE = 256;
const MAX_TILE_CACHE_ENTRIES = 256;
const MAX_TILES_PER_REQUEST = 96;
const TERRAIN_TILE_BASE_URL = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium";
const MINIMUM_CLIMB_PROMINENCE_METERS = 10;

export type TerrainRoutePoint = {
  latitude: number;
  longitude: number;
  startsNewSegment: boolean;
};

export type TerrainElevationCorrection = {
  elevationGainMeters: number;
  elevationsMeters: number[];
  algorithmVersion: "terrain-v1";
  approximateResolutionMeters: number;
  attribution: {
    provider: "Mapzen Terrain Tiles";
    text: "Terrain data from Mapzen and source agencies";
    url: "https://github.com/tilezen/joerd/blob/master/docs/attribution.md";
    modified: true;
  };
};

type PixelSample = { tileX: number; tileY: number; pixelX: number; pixelY: number };

const tileCache = new Map<string, Promise<PNG>>();

export async function correctTerrainElevation(
  points: TerrainRoutePoint[],
): Promise<TerrainElevationCorrection> {
  if (points.length < 2) throw new Error("terrain_route_too_short");

  const pixelLocations = points.map((point) => globalPixel(point.latitude, point.longitude));
  const requiredTiles = new Set<string>();
  for (const pixel of pixelLocations) {
    for (const sample of interpolationSamples(pixel.x, pixel.y)) {
      requiredTiles.add(tileKey(sample.tileX, sample.tileY));
    }
  }
  if (requiredTiles.size > MAX_TILES_PER_REQUEST) throw new Error("terrain_route_too_large");
  await Promise.all([...requiredTiles].map(loadTileByKey));

  const terrainElevations = await Promise.all(pixelLocations.map(async (pixel) => {
    const samples = interpolationSamples(pixel.x, pixel.y);
    const values = await Promise.all(samples.map(sampleElevation));
    const xFraction = pixel.x - Math.floor(pixel.x);
    const yFraction = pixel.y - Math.floor(pixel.y);
    const top = values[0] * (1 - xFraction) + values[1] * xFraction;
    const bottom = values[2] * (1 - xFraction) + values[3] * xFraction;
    return top * (1 - yFraction) + bottom * yFraction;
  }));

  const smoothedElevations = smoothBySegment(terrainElevations, points);
  return {
    elevationGainMeters: round(calculateProminentGain(smoothedElevations, points), 1),
    elevationsMeters: smoothedElevations.map((value) => round(value, 1)),
    algorithmVersion: "terrain-v1",
    approximateResolutionMeters: round(approximateResolution(points), 1),
    attribution: {
      provider: "Mapzen Terrain Tiles",
      text: "Terrain data from Mapzen and source agencies",
      url: "https://github.com/tilezen/joerd/blob/master/docs/attribution.md",
      modified: true,
    },
  };
}

function globalPixel(latitude: number, longitude: number) {
  const worldPixels = 2 ** TERRAIN_TILE_ZOOM * TILE_SIZE;
  const wrappedLongitude = ((longitude + 180) % 360 + 360) % 360 - 180;
  const clampedLatitude = Math.max(-85.05112878, Math.min(85.05112878, latitude));
  const latitudeRadians = clampedLatitude * Math.PI / 180;
  return {
    x: (wrappedLongitude + 180) / 360 * worldPixels,
    y: (1 - Math.log(Math.tan(latitudeRadians) + 1 / Math.cos(latitudeRadians)) / Math.PI)
      / 2 * worldPixels,
  };
}

function interpolationSamples(x: number, y: number): [PixelSample, PixelSample, PixelSample, PixelSample] {
  const x0 = Math.floor(x);
  const y0 = Math.floor(y);
  return [pixelSample(x0, y0), pixelSample(x0 + 1, y0), pixelSample(x0, y0 + 1), pixelSample(x0 + 1, y0 + 1)];
}

function pixelSample(globalX: number, globalY: number): PixelSample {
  const tileCount = 2 ** TERRAIN_TILE_ZOOM;
  const tileX = ((Math.floor(globalX / TILE_SIZE) % tileCount) + tileCount) % tileCount;
  const tileY = Math.max(0, Math.min(tileCount - 1, Math.floor(globalY / TILE_SIZE)));
  return {
    tileX,
    tileY,
    pixelX: ((globalX % TILE_SIZE) + TILE_SIZE) % TILE_SIZE,
    pixelY: Math.max(0, Math.min(TILE_SIZE - 1, globalY - tileY * TILE_SIZE)),
  };
}

async function sampleElevation(sample: PixelSample) {
  const tile = await loadTile(sample.tileX, sample.tileY);
  const offset = (sample.pixelY * tile.width + sample.pixelX) * 4;
  return tile.data[offset] * 256 + tile.data[offset + 1] + tile.data[offset + 2] / 256 - 32_768;
}

function loadTile(tileX: number, tileY: number) {
  return loadTileByKey(tileKey(tileX, tileY));
}

function loadTileByKey(key: string): Promise<PNG> {
  const cached = tileCache.get(key);
  if (cached) return cached;
  const loading = fetch(`${TERRAIN_TILE_BASE_URL}/${key}.png`, {
    headers: { Accept: "image/png", "User-Agent": "Plainstride/1.0 https://plainstride.run" },
    signal: AbortSignal.timeout(8_000),
  }).then(async (response) => {
    if (!response.ok) throw new Error(`terrain_provider_${response.status}`);
    const png = PNG.sync.read(Buffer.from(await response.arrayBuffer()));
    if (png.width !== TILE_SIZE || png.height !== TILE_SIZE) throw new Error("terrain_provider_invalid_tile");
    return png;
  }).catch((error) => {
    tileCache.delete(key);
    throw error;
  });
  tileCache.set(key, loading);
  pruneTileCache();
  return loading;
}

function tileKey(tileX: number, tileY: number) {
  return `${TERRAIN_TILE_ZOOM}/${tileX}/${tileY}`;
}

function pruneTileCache() {
  while (tileCache.size > MAX_TILE_CACHE_ENTRIES) {
    const oldest = tileCache.keys().next().value as string | undefined;
    if (!oldest) return;
    tileCache.delete(oldest);
  }
}

function smoothBySegment(elevations: number[], points: TerrainRoutePoint[]) {
  const result: number[] = [];
  let start = 0;
  for (let index = 1; index <= points.length; index += 1) {
    if (index < points.length && !points[index].startsNewSegment) continue;
    const segment = elevations.slice(start, index);
    const median = rollingMedian(segment, 5);
    result.push(...weightedAverage(median));
    start = index;
  }
  return result;
}

function rollingMedian(values: number[], windowSize: number) {
  const radius = Math.floor(windowSize / 2);
  return values.map((_, index) => {
    const window = values.slice(Math.max(0, index - radius), Math.min(values.length, index + radius + 1))
      .sort((left, right) => left - right);
    return window[Math.floor(window.length / 2)];
  });
}

function weightedAverage(values: number[]) {
  if (values.length < 3) return values;
  return values.map((value, index) => {
    const previous = values[Math.max(0, index - 1)];
    const next = values[Math.min(values.length - 1, index + 1)];
    return previous * 0.25 + value * 0.5 + next * 0.25;
  });
}

function calculateProminentGain(elevations: number[], points: TerrainRoutePoint[]) {
  let total = 0;
  let start = 0;
  for (let index = 1; index <= points.length; index += 1) {
    if (index < points.length && !points[index].startsNewSegment) continue;
    total += prominentGain(elevations.slice(start, index));
    start = index;
  }
  return total;
}

function prominentGain(elevations: number[]) {
  if (elevations.length < 2) return 0;
  let floor = elevations[0];
  let peak = elevations[0];
  let committed = 0;
  for (const elevation of elevations.slice(1)) {
    if (elevation > peak) {
      peak = elevation;
    } else if (peak - elevation >= MINIMUM_CLIMB_PROMINENCE_METERS) {
      if (peak - floor >= MINIMUM_CLIMB_PROMINENCE_METERS) committed += peak - floor;
      floor = elevation;
      peak = elevation;
    } else if (elevation < floor) {
      floor = elevation;
      peak = Math.max(peak, elevation);
    }
  }
  if (peak - floor >= MINIMUM_CLIMB_PROMINENCE_METERS) committed += peak - floor;
  return committed;
}

function approximateResolution(points: TerrainRoutePoint[]) {
  const averageLatitude = points.reduce((sum, point) => sum + point.latitude, 0) / points.length;
  return 156_543.03392 * Math.cos(averageLatitude * Math.PI / 180) / 2 ** TERRAIN_TILE_ZOOM;
}

function round(value: number, digits: number) {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}
